import AppKit

// Regular app (Dock + hub window); AppDelegate also adds the caption overlay and a menu-bar item.
MainActor.assumeIsolated {
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
        _ = NSApplication.shared
        Fonts.register()
        Snapshot.run(to: URL(fileURLWithPath: args[i + 1]))
        exit(0)
    }
    if let i = args.firstIndex(of: "--icon"), i + 1 < args.count {
        _ = NSApplication.shared
        AppIconView.writeIconset(to: URL(fileURLWithPath: args[i + 1]))
        exit(0)
    }
    // `--probe-system <seconds>`: logs the loudness the system-audio tap receives (diagnostics).
    if let i = args.firstIndex(of: "--probe-system"), i + 1 < args.count, let seconds = Double(args[i + 1]) {
        let tap = SystemAudioCapture()
        let lock = NSLock()
        var peak: Float = 0, buffers = 0, frames = 0
        tap.onBuffer = { b in
            let r = BufferConverter.rms(b)
            lock.withLock { peak = max(peak, r); buffers += 1; frames += Int(b.frameLength) }
        }
        do { try tap.start() } catch { Log.info("probe: tap failed: \(error.localizedDescription)"); exit(1) }
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        tap.stop()
        lock.withLock { Log.info("probe: \(buffers) buffers, \(frames) frames, peak rms \(peak)") }
        Thread.sleep(forTimeInterval: 0.5)
        exit(0)
    }
    // `--probe-live <seconds>`: runs a full session (both sources) and logs what is recognized.
    if let i = args.firstIndex(of: "--probe-live"), i + 1 < args.count, let seconds = Double(args[i + 1]) {
        let model = AppModel(persist: false)
        if args.contains("--no-echo") { model.settings.echoCancellation = false }
        if args.contains("--system-only") { model.settings.captureMic = false }
        let controller = TranscriptionController(model: model)
        controller.probe = true
        WhisperStream.debug = true
        controller.start()
        // Wait for the model (first run: download + compile), then listen for `seconds`.
        let deadline = Date().addingTimeInterval(900)
        while model.engine != .running && Date() < deadline {
            if case .failed = model.engine { break }
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        }
        Log.info("probe-live: listening (\(model.engine))")
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        controller.stop()
        RunLoop.main.run(until: Date().addingTimeInterval(3))
        Log.info("probe-live: engine=\(model.engine) segments=\(model.sessions.first?.segments.map { "[\($0.source.rawValue)] \($0.text)" } ?? [])")
        Thread.sleep(forTimeInterval: 0.5)
        exit(0)
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
