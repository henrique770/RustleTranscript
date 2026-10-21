import AVFoundation
import CoreAudio

/// The microphone through AVAudioEngine. Apple's voice processing (echo cancellation) is not used:
/// it silences the system-audio tap. Echo is filtered on the text instead (EchoFilter).
final class MicStream {
    /// Raw input buffers, on the audio thread.
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    private(set) var isRunning = false
    private var engine = AVAudioEngine()

    func start() throws {
        guard !isRunning else { return }
        engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw NSError(domain: "RustleTranscript", code: 1, userInfo: [NSLocalizedDescriptionKey: "Nenhum microfone disponível"])
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.onBuffer?(buffer)
        }
        engine.prepare()
        try engine.start()
        isRunning = true
        Log.info("mic started (\(format.sampleRate) Hz, \(format.channelCount) ch)")
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }
}

/// Records what the Mac is playing, the same way as RustleApp's Notetaker: a Core Audio process
/// tap (CATapDescription + AudioHardwareCreateProcessTap) read through a private aggregate device.
/// Needs the "System Audio Recording" permission, which macOS asks for the first time it starts.
final class SystemAudioCapture {
    enum CaptureError: LocalizedError {
        case coreAudio(String, OSStatus)
        var errorDescription: String? {
            switch self { case .coreAudio(let step, let status): return "\(step) falhou (\(status))" }
        }
    }

    /// Buffers on a private queue. They point at Core Audio's memory: use them before returning.
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "rustle-transcript.system-audio", qos: .userInitiated)

    func start() throws {
        // Everything but ourselves (the app plays nothing, but keep the tap clean).
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "Rustle Transcript"
        description.muteBehavior = .unmuted
        description.isPrivate = true

        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &tap), "Criar tap de áudio")
        tapID = tap

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format), "Ler formato do tap")
        guard let tapFormat = AVAudioFormat(streamDescription: &format) else {
            throw CaptureError.coreAudio("Formato do tap", -1)
        }

        let outputUID = try Self.defaultOutputUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Rustle Transcript",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        var agg = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &agg), "Criar dispositivo agregado")
        aggregateID = agg

        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
            guard let self,
                  let buffer = AVAudioPCMBuffer(pcmFormat: tapFormat, bufferListNoCopy: input, deallocator: nil) else { return }
            self.onBuffer?(buffer)
        }, "Criar IOProc")
        try check(AudioDeviceStart(aggregateID, procID), "Iniciar captura")
        Log.info("system audio tap started (\(tapFormat.sampleRate) Hz, \(tapFormat.channelCount) ch)")
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            if let procID { AudioDeviceDestroyIOProcID(aggregateID, procID) }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    deinit { stop() }

    private func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else {
            stop()
            throw CaptureError.coreAudio(step, status)
        }
    }

    private static func defaultOutputUID() throws -> String {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr else { throw CaptureError.coreAudio("Saída de áudio padrão", status) }

        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid)
        guard status == noErr, let value = uid?.takeRetainedValue() else {
            throw CaptureError.coreAudio("UID da saída de áudio", status)
        }
        return value as String
    }
}

/// Converts any PCM buffer to the format the speech analyzer asks for.
final class BufferConverter {
    let target: AVAudioFormat
    private var source: AVAudioFormat?
    private var converter: AVAudioConverter?
    /// Voice-processed mic input arrives as 3+ identical channels with no channel layout, which
    /// AVAudioConverter downmixes to silence; for those, channel 0 is copied into a mono buffer first.
    private var mono: AVAudioFormat?

    init(target: AVAudioFormat) { self.target = target }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0 else { return nil }
        if source != buffer.format { rebuild(for: buffer.format) }
        guard let converter else { return nil }
        var input = buffer
        if let mono {
            guard let src = buffer.floatChannelData,
                  let m = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: buffer.frameLength),
                  let dst = m.floatChannelData else { return nil }
            m.frameLength = buffer.frameLength
            let stride = buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1
            for i in 0..<Int(buffer.frameLength) { dst[0][i] = src[0][i * stride] }
            input = m
        }
        let ratio = target.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, out.frameLength > 0 else { return nil }
        return out
    }

    private func rebuild(for format: AVAudioFormat) {
        source = format
        if format.channelCount > 2, format.commonFormat == .pcmFormatFloat32 {
            mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: format.sampleRate, channels: 1, interleaved: false)
            converter = mono.flatMap { AVAudioConverter(from: $0, to: target) }
        } else {
            mono = nil
            converter = AVAudioConverter(from: format, to: target)
        }
    }

    /// Loudness of channel 0, for the waveform.
    static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        let stride = buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1
        var sum: Float = 0
        if let f = buffer.floatChannelData {
            for i in 0..<n { let s = f[0][i * stride]; sum += s * s }
        } else if let s16 = buffer.int16ChannelData {
            for i in 0..<n { let s = Float(s16[0][i * stride]) / 32768; sum += s * s }
        } else {
            return 0
        }
        return (sum / Float(n)).squareRoot()
    }
}
