import AppKit
import AVFoundation
import Speech

/// One audio source → Apple's on-device SpeechAnalyzer (macOS 26). Volatile results arrive within a
/// few hundred milliseconds and keep changing; a final result replaces them once the phrase settles.
final class LiveTranscriber: @unchecked Sendable {
    enum Failure: LocalizedError {
        case unsupported(String)
        case noFormat
        var errorDescription: String? {
            switch self {
            case .unsupported(let id): return "O idioma \(id) não é suportado pelo reconhecimento de fala deste Mac."
            case .noFormat: return "O reconhecimento de fala não aceitou nenhum formato de áudio."
            }
        }
    }

    let source: AudioSource
    /// Main thread.
    var onVolatile: ((String) -> Void)?
    /// Main thread: text, start and end in seconds of audio.
    var onFinal: ((String, Double, Double) -> Void)?

    private let lock = NSLock()
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: BufferConverter?
    private var resultsTask: Task<Void, Never>?

    init(source: AudioSource) { self.source = source }

    /// Resolves the language and downloads its model the first time (progress 0...1).
    static func prepare(language: String, progress: @escaping @MainActor (Double) -> Void) async throws -> Locale {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else {
            throw Failure.unsupported(language)
        }
        let probe = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [probe]) {
            Log.info("downloading speech model for \(locale.identifier)")
            let watcher = Task {
                while !Task.isCancelled {
                    await progress(request.progress.fractionCompleted)
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            defer { watcher.cancel() }
            try await request.downloadAndInstall()
        }
        return locale
    }

    static func isInstalled(language: String) async -> Bool {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else { return false }
        return await SpeechTranscriber.installedLocales.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
    }

    func start(locale: Locale) async throws {
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                            reportingOptions: [.volatileResults, .fastResults],
                                            attributeOptions: [.audioTimeRange])
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw Failure.noFormat
        }
        try await analyzer.prepareToAnalyze(in: format)
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()

        lock.withLock {
            self.analyzer = analyzer
            self.continuation = continuation
            converter = BufferConverter(target: format)
        }

        let source = source
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let owner = self else { return }
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    if result.isFinal {
                        let start = result.range.start.seconds, end = result.range.end.seconds
                        await MainActor.run {
                            owner.onFinal?(text, start.isFinite ? start : 0, end.isFinite ? end : 0)
                        }
                    } else {
                        await MainActor.run { owner.onVolatile?(text) }
                    }
                }
            } catch {
                Log.info("\(source.rawValue) results ended: \(error.localizedDescription)")
            }
        }
        try await analyzer.start(inputSequence: stream)
        Log.info("\(source.rawValue) transcriber started (\(locale.identifier), \(format.sampleRate) Hz)")
    }

    /// Thread-safe; called from the audio threads.
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let continuation, let converter, let converted = converter.convert(buffer) else { return }
        continuation.yield(AnalyzerInput(buffer: converted))
    }

    /// Flushes what is still volatile into final results, then stops.
    func stop() async {
        let (continuation, analyzer) = lock.withLock {
            let pair = (self.continuation, self.analyzer)
            self.continuation = nil
            converter = nil
            return pair
        }
        continuation?.finish()
        do { try await analyzer?.finalizeAndFinishThroughEndOfInput() } catch {
            Log.info("finalize failed: \(error.localizedDescription)")
            await analyzer?.cancelAndFinishNow()
        }
        await resultsTask?.value
        self.analyzer = nil
    }
}

/// Starts and stops a live session: audio sources → transcribers → caption feed + history.
@MainActor
final class TranscriptionController {
    private let model: AppModel
    private var mic: MicStream?
    private var system: SystemAudioCapture?
    private var transcribers: [AudioSource: SpeechEngine] = [:]
    private var echo = EchoFilter()
    private var busy = false
    private var clock: Timer?
    private var sessionStart = Date()
    private var lastLevel: [AudioSource: Date] = [:]
    /// Diagnostics: logs every result and the loudness each source receives.
    var probe = false
    private var peaks: [AudioSource: Float] = [:]

    init(model: AppModel) { self.model = model }

    var isActive: Bool { model.isRunning || busy }

    func toggle() { isActive ? stop() : start() }

    func start() {
        guard !isActive else { return }
        let sources = model.settings.enabledSources
        guard !sources.isEmpty else {
            model.engine = .failed("Ative o microfone ou o áudio do computador em Configurações.")
            return
        }
        busy = true
        Task {
            defer { busy = false }
            do {
                model.engine = .preparing("Preparando o reconhecimento de fala…")
                let settings = model.settings
                let onProgress: @MainActor (Double) -> Void = { [weak self] p in self?.model.engine = .downloading(p) }
                var locale: Locale?
                if settings.usesWhisper {
                    try await WhisperModel.shared.load(settings.whisperModel,
                        progress: { p in Task { @MainActor in onProgress(p) } },
                        status: { s in Task { @MainActor [weak self] in self?.model.engine = .preparing(s) } })
                } else {
                    locale = try await LiveTranscriber.prepare(language: settings.language, progress: onProgress)
                }
                model.engine = .preparing("Iniciando…")
                model.feed.clear()
                echo = EchoFilter()
                bothSources = sources.count > 1
                _ = model.beginSession()
                sessionStart = Date()
                for source in sources {
                    let t: SpeechEngine
                    if let locale {
                        let apple = LiveTranscriber(source: source)
                        try await apple.start(locale: locale)
                        t = apple
                    } else {
                        let whisper = WhisperStream(source: source)
                        whisper.start()
                        t = whisper
                    }
                    t.onVolatile = { [weak self] text in self?.volatile(text, source: source) }
                    t.onFinal = { [weak self] text, start, end in self?.commit(text, source: source, start: start, end: end) }
                    transcribers[source] = t
                }
                var failures: [String] = []
                if let t = transcribers[.mic] {
                    let m = MicStream()
                    m.onBuffer = { [weak self] buffer in
                        t.append(buffer)
                        self?.level(buffer, source: .mic)
                    }
                    do { try m.start(); mic = m } catch {
                        failures.append("Microfone: \(error.localizedDescription)")
                    }
                }
                if let t = transcribers[.system] {
                    let s = SystemAudioCapture()
                    s.onBuffer = { [weak self] buffer in
                        t.append(buffer)
                        self?.level(buffer, source: .system)
                    }
                    do { try s.start(); system = s } catch {
                        failures.append("Áudio do computador: \(error.localizedDescription)")
                    }
                }
                guard mic != nil || system != nil else { throw NSError(domain: "RustleTranscript", code: 2, userInfo: [NSLocalizedDescriptionKey: failures.joined(separator: " · ")]) }
                if !failures.isEmpty { Log.info("partial start: \(failures)") }
                model.engine = .running
                model.feed.elapsed = 0
                clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.model.feed.elapsed = Date().timeIntervalSince(self.sessionStart)
                    }
                }
            } catch {
                Log.info("start failed: \(error.localizedDescription)")
                await teardown()
                model.engine = .failed(error.localizedDescription)
            }
        }
    }

    func stop() {
        guard model.isRunning, !busy else { return }
        busy = true
        model.engine = .preparing("Finalizando…")
        Task {
            await teardown()
            model.engine = .idle
            busy = false
        }
    }

    private func teardown() async {
        clock?.invalidate()
        clock = nil
        mic?.stop()
        system?.stop()
        mic = nil
        system = nil
        let running = transcribers
        transcribers = [:]
        for t in running.values { await t.stop() }
        model.endSession()
    }

    /// Set at start: teardown empties `transcribers` while the last phrases are still arriving.
    private var bothSources = false
    private var dedupe: Bool { model.settings.echoCancellation && bothSources }

    private func volatile(_ text: String, source: AudioSource) {
        if probe { Log.info("volatile [\(source.rawValue)] \(text)") }
        if source == .system { echo.heardFromSystem(text, final: false) }
        if source == .mic && dedupe && echo.isEcho(text) { model.feed.setVolatile("", from: .mic); return }
        model.feed.setVolatile(text, from: source)
    }

    private func commit(_ text: String, source: AudioSource, start: Double, end: Double) {
        if probe { Log.info("final [\(source.rawValue)] \(start)-\(end) \(text) · peaks \(peaks)") }
        if source == .system { echo.heardFromSystem(text, final: true) }
        if source == .mic && dedupe && echo.isEcho(text) {
            if probe { Log.info("dropped mic echo: \(text)") }
            model.feed.commit("", from: .mic)
            return
        }
        model.feed.commit(text, from: source)
        guard !text.isEmpty else { return }
        model.append(Segment(source: source, text: text, start: start, end: end))
    }

    /// Audio thread → main, at most ~20 times a second per source.
    nonisolated private func level(_ buffer: AVAudioPCMBuffer, source: AudioSource) {
        let rms = BufferConverter.rms(buffer)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = Date()
                if let last = self.lastLevel[source], now.timeIntervalSince(last) < 0.05 { return }
                self.lastLevel[source] = now
                self.model.feed.push(level: rms, from: source)
                if self.probe { self.peaks[source] = max(self.peaks[source] ?? 0, rms) }
            }
        }
    }
}
