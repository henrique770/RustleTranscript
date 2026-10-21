import AVFoundation
import Foundation
import WhisperKit

/// Anything that turns one audio source into live text: Apple's SpeechAnalyzer (one fixed language)
/// or Whisper (any language, detected on the fly).
protocol SpeechEngine: AnyObject {
    /// Main thread: the phrase still being recognized.
    var onVolatile: ((String) -> Void)? { get set }
    /// Main thread: a settled phrase, with its start and end in seconds since the source started.
    var onFinal: ((String, Double, Double) -> Void)? { get set }
    /// Thread-safe; called from the audio threads.
    func append(_ buffer: AVAudioPCMBuffer)
    /// Flushes what is still volatile into final results, then stops.
    func stop() async
}

extension LiveTranscriber: SpeechEngine {}

// MARK: - Model

/// The Whisper model, downloaded once into Application Support and shared by every source.
actor WhisperModel {
    static let shared = WhisperModel()

    struct Variant: Identifiable {
        let id: String
        let name: String
        let detail: String
    }

    static let variants = [
        Variant(id: "openai_whisper-large-v3-v20240930_turbo_632MB", name: "Preciso",
                detail: "Whisper large-v3 turbo, cerca de 630 MB. Melhor para sotaques, ruído e idiomas misturados."),
        Variant(id: "openai_whisper-small", name: "Rápido",
                detail: "Whisper small, cerca de 220 MB. Mais leve, erra mais em áudio difícil."),
    ]
    static let defaultVariant = variants[0].id

    private var kit: WhisperKit?
    private var loaded: String?
    private var loading: Task<Void, Error>?

    static let base = AppModel.folder.appendingPathComponent("Models")

    /// Where WhisperKit's downloader (Hugging Face hub layout) puts a variant.
    static func folder(for variant: String) -> URL {
        base.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(variant)")
    }

    static func isDownloaded(_ variant: String) -> Bool {
        FileManager.default.fileExists(atPath: folder(for: variant).appendingPathComponent("AudioEncoder.mlmodelc").path)
    }

    /// Downloads (first time only) and loads the model. `progress` is 0...1 while downloading,
    /// `status` describes the slow steps.
    func load(_ variant: String,
              progress: @escaping @Sendable (Double) -> Void,
              status: @escaping @Sendable (String) -> Void) async throws {
        if kit != nil, loaded == variant { return }
        if let loading { return try await loading.value }
        let task = Task<Void, Error> {
            var folder = Self.folder(for: variant)
            if !Self.isDownloaded(variant) {
                Log.info("downloading whisper \(variant)")
                folder = try await WhisperKit.download(variant: variant, downloadBase: Self.base) { p in
                    progress(p.fractionCompleted)
                }
            }
            // The first load compiles the model for the Neural Engine: it can take a minute or two.
            status("Carregando o Whisper (a primeira vez pode levar alguns minutos)…")
            let started = Date()
            let kit = try await WhisperKit(WhisperKitConfig(modelFolder: folder.path, verbose: false, logLevel: .error,
                                                            prewarm: true, load: true, download: false))
            Log.info("whisper \(variant) loaded in \(Int(Date().timeIntervalSince(started))) s")
            self.kit = kit
            self.loaded = variant
        }
        loading = task
        defer { loading = nil }
        try await task.value
    }

    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// One decode at a time: the sources take turns on the GPU / Neural Engine.
    func transcribe(_ samples: [Float]) async throws -> [TranscriptionResult] {
        guard let kit else { return [] }
        if busy { await withCheckedContinuation { waiters.append($0) } }
        busy = true
        defer {
            if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
        }
        let options = DecodingOptions(task: .transcribe, language: nil, temperature: 0, temperatureFallbackCount: 2,
                                      usePrefillPrompt: true, detectLanguage: true, skipSpecialTokens: true,
                                      withoutTimestamps: false, suppressBlank: true, noSpeechThreshold: 0.6)
        return try await kit.transcribe(audioArray: samples, decodeOptions: options)
    }
}

// MARK: - Streaming

/// Live Whisper on one source. Whisper is not a streaming model, so the audio since the last
/// settled point is re-transcribed every few hundred milliseconds: every segment but the last
/// settles (final), the last one is shown as volatile; a pause settles everything.
final class WhisperStream: SpeechEngine, @unchecked Sendable {
    var onVolatile: ((String) -> Void)?
    var onFinal: ((String, Double, Double) -> Void)?

    let source: AudioSource
    private static let rate = 16_000.0
    private let lock = NSLock()
    private var samples: [Float] = []
    /// Index (in all samples since start) where `samples[0]` sits.
    private var offset = 0
    private var transcribedCount = 0
    private var running = true
    private let converter = BufferConverter(
        target: AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!)
    private var loop: Task<Void, Never>?

    init(source: AudioSource) { self.source = source }

    func start() {
        loop = Task.detached(priority: .userInitiated) { [weak self] in
            while let self, self.isRunning {
                let worked = await self.step(final: false)
                try? await Task.sleep(for: .milliseconds(worked ? 120 : 250))
            }
        }
    }

    private var isRunning: Bool { lock.withLock { running } }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard running, let out = converter.convert(buffer), let ch = out.floatChannelData else { return }
            samples.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
        }
    }

    func stop() async {
        lock.withLock { running = false }
        await loop?.value
        _ = await step(final: true)
    }

    /// One pass over the pending audio. Returns false when there was nothing new to do.
    private func step(final: Bool) async -> Bool {
        let (window, start, total) = lock.withLock { (samples, offset, offset + samples.count) }
        let seconds = Double(window.count) / Self.rate
        guard final || (seconds >= 1 && total - transcribedCount >= Int(0.35 * Self.rate)) else { return false }
        guard !window.isEmpty else { return false }
        let seen = lock.withLock { () -> Int in
            let seen = transcribedCount
            transcribedCount = total
            return seen
        }
        // Follow the background level on the audio that is new since the last pass only.
        vad.learn(window[max(0, min(window.count, seen - start))...])

        // Nothing but silence or background noise: drop it without waking the model
        // (Whisper invents "Thank you." and the like over noise).
        let voiced = vad.voicedSeconds(window)
        if voiced < 0.3 {
            if seconds > 2 || final { drop(upTo: start + window.count); await emitVolatile("") }
            return true
        }

        let results: [TranscriptionResult]
        do { results = try await WhisperModel.shared.transcribe(window) } catch {
            Log.info("whisper \(source.rawValue) failed: \(error.localizedDescription)")
            return true
        }
        let segments = results.flatMap(\.segments).compactMap { seg -> (text: String, start: Double, end: Double)? in
            if WhisperStream.debug {
                Log.info("seg [\(source.rawValue)] nsp=\(seg.noSpeechProb) lp=\(seg.avgLogprob) cr=\(seg.compressionRatio) rms=\(Self.rms(window)) \(seg.text)")
            }
            if seg.noSpeechProb > 0.6 && seg.avgLogprob < -0.8 { return nil }
            // Low confidence or looping text: almost always invented.
            if seg.avgLogprob < -1.0 || seg.compressionRatio > 2.4 { return nil }
            let text = SpeechFilter.clean(seg.text, voicedSeconds: voiced)
            return text.isEmpty ? nil : (text, Double(seg.start), Double(seg.end))
        }

        // A pause at the end (or the window getting long, or stopping) settles everything.
        let paused = vad.voicedSeconds(window.suffix(Int(0.7 * Self.rate))) == 0
        if final || paused || seconds > 24 {
            if !segments.isEmpty {
                let text = segments.map(\.text).joined(separator: " ")
                await emitFinal(text, start: Double(start) / Self.rate + segments[0].start,
                                end: Double(start) / Self.rate + segments[segments.count - 1].end)
            }
            drop(upTo: start + window.count)
            await emitVolatile("")
        } else if segments.count >= 2 {
            let settled = segments.dropLast()
            await emitFinal(settled.map(\.text).joined(separator: " "),
                            start: Double(start) / Self.rate + settled.first!.start,
                            end: Double(start) / Self.rate + settled.last!.end)
            drop(upTo: start + Int(settled.last!.end * Self.rate))
            await emitVolatile(segments.last!.text)
        } else {
            await emitVolatile(segments.map(\.text).joined(separator: " "))
        }
        return true
    }

    private func drop(upTo absolute: Int) {
        lock.withLock {
            let n = min(max(0, absolute - offset), samples.count)
            samples.removeFirst(n)
            offset += n
        }
    }

    private func emitFinal(_ text: String, start: Double, end: Double) async {
        await MainActor.run { onFinal?(text, start, end) }
    }

    private func emitVolatile(_ text: String) async {
        await MainActor.run { onVolatile?(text) }
    }

    private var vad = VoiceDetector()
    nonisolated(unsafe) static var debug = false

    static func rms<C: Collection>(_ x: C) -> Float where C.Element == Float {
        guard !x.isEmpty else { return 0 }
        var sum: Float = 0
        for v in x { sum += v * v }
        return (sum / Float(x.count)).squareRoot()
    }
}

/// Energy voice detector on 30 ms frames, with an adaptive noise floor: a frame is voiced when it
/// is clearly louder than the room (or the source's) background.
struct VoiceDetector {
    private var floor: Float = 0.002
    private static let frame = 480

    var gate: Float { max(0.009, floor * 3.5) }

    /// Follows the background level: fast down, slow up.
    mutating func learn<C: Collection>(_ x: C) where C.Element == Float, C.Index == Int {
        var i = x.startIndex
        while i + Self.frame <= x.endIndex {
            let r = WhisperStream.rms(x[i..<(i + Self.frame)])
            if r < floor { floor = max(r, 0.0005) } else { floor += (r - floor) * 0.002 }
            i += Self.frame
        }
    }

    /// Seconds of frames clearly above the background.
    func voicedSeconds<C: Collection>(_ x: C) -> Double where C.Element == Float, C.Index == Int {
        var voiced = 0
        var i = x.startIndex
        while i + Self.frame <= x.endIndex {
            if WhisperStream.rms(x[i..<(i + Self.frame)]) > gate { voiced += 1 }
            i += Self.frame
        }
        return Double(voiced * Self.frame) / 16_000
    }
}

// MARK: - Only speech

/// Keeps only spoken words: drops sound descriptions ([Música], (aplausos), ♪) and the phrases
/// Whisper tends to invent over silence or music.
enum SpeechFilter {
    private static let bracketed = try! NSRegularExpression(pattern: "\\[[^\\]]*\\]|\\([^)]*\\)|\\*[^*]*\\*|<[^>]*>|[♪♫♬🎵🎶]")
    private static let hallucinations = [
        "obrigado por assistir", "obrigada por assistir", "legendas pela comunidade amara.org", "amara.org",
        "thanks for watching", "thank you for watching", "subtitles by", "subscribe", "inscreva-se",
        "legendado por", "transcrição", "gracias por ver", "subtítulos realizados por", "sous-titrage",
        "untertitel im auftrag", "ご視聴ありがとうございました", "请不吝点赞",
    ]

    /// Short thank-yous are Whisper's favourite inventions over noise; dropped unless clearly spoken.
    private static let weak: Set<String> = ["thank you", "thank you.", "thanks.", "thank god.", "you", "obrigado.", "obrigada.",
                                            "tchau.", "bye.", "ありがとうございました", "ご視聴ありがとうございました", "谢谢", "gracias."]

    static func clean(_ raw: String, voicedSeconds: Double = 10) -> String {
        let ns = raw as NSString
        var text = bracketed.stringByReplacingMatches(in: raw, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Only punctuation or a dash left: nothing was said.
        guard text.unicodeScalars.contains(where: { CharacterSet.letters.union(.decimalDigits).contains($0) }) else { return "" }
        let lower = text.lowercased()
        if voicedSeconds < 1.2 && weak.contains(lower) { return "" }
        if hallucinations.contains(where: { lower.contains($0) }) && lower.count < 80 { return "" }
        return text
    }
}

// MARK: - Echo

/// Without voice processing (it silences the system-audio tap), a mic near the speakers also hears
/// the computer. Mic phrases that repeat what the computer just said are dropped.
struct EchoFilter {
    private var recent: [(date: Date, words: Set<String>)] = []
    private var current: Set<String> = []

    mutating func heardFromSystem(_ text: String, final: Bool) {
        let words = Self.words(text)
        if final {
            recent.append((Date(), words))
            current = []
        } else {
            current = words
        }
        recent.removeAll { Date().timeIntervalSince($0.date) > 15 }
    }

    /// True when most of the mic phrase was just said by the computer.
    func isEcho(_ text: String) -> Bool {
        let words = Self.words(text)
        guard words.count >= 2 else { return !words.isEmpty && (current.union(recent.last?.words ?? []).isSuperset(of: words)) }
        let pool = recent.reduce(current) { $0.union($1.words) }
        let shared = words.intersection(pool).count
        return Double(shared) / Double(words.count) >= 0.6
    }

    static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 1 })
    }
}
