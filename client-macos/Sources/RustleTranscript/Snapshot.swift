import AppKit
import SwiftUI

/// `RustleTranscript --snapshot <dir>` renders every page off-screen to PNG with sample data (no
/// Screen Recording permission needed), then exits. Used to check the UI without a display.
@MainActor
enum Snapshot {
    static func run(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = AppModel(persist: false)
        model.permissions = .init(microphone: true)
        seed(model)
        let size = NSSize(width: 1120, height: 760)

        render(MainView(model: model, initialPage: .home), size: size, to: dir.appendingPathComponent("home.png"))
        render(MainView(model: model, initialPage: .history), size: size, to: dir.appendingPathComponent("history.png"))
        model.openSession = model.sessions.first?.id
        render(MainView(model: model, initialPage: .history), size: NSSize(width: 1120, height: 1000), to: dir.appendingPathComponent("history-detail.png"))
        model.openSession = nil
        render(MainView(model: model, initialPage: .caption), size: NSSize(width: 1120, height: 1900), to: dir.appendingPathComponent("caption.png"))
        model.style = CaptionStyle.presets[2].style
        render(MainView(model: model, initialPage: .caption), size: size, to: dir.appendingPathComponent("caption-paper.png"))
        model.style = CaptionStyle()
        render(MainView(model: model, initialPage: .settings), size: NSSize(width: 1120, height: 1500), to: dir.appendingPathComponent("settings.png"))

        // Live: a session in progress, with the caption being written.
        model.activeSessionID = model.sessions.first?.id
        model.engine = .running
        model.feed.preview(CaptionFeed.sample.entries, volatile: CaptionFeed.sample.volatile)
        model.feed.elapsed = 754
        for s in AudioSource.allCases { for _ in 0..<12 { model.feed.push(level: Float.random(in: 0.002...0.2), from: s) } }
        render(MainView(model: model, initialPage: .home), size: size, to: dir.appendingPathComponent("home-live.png"))
        model.engine = .idle
        model.activeSessionID = nil
        model.sessions = []
        render(MainView(model: model, initialPage: .home), size: size, to: dir.appendingPathComponent("home-empty.png"))

        // The overlay caption on its own, for each preset.
        for p in CaptionStyle.presets {
            let box = ZStack { Color(hex: 0x2A2A29); CaptionBox(style: p.style, text: CaptionRenderer.attributed(
                entries: CaptionFeed.sample.entries, volatile: CaptionFeed.sample.volatile, style: p.style, speakers: true),
                width: 820, blending: .withinWindow) }
            render(box, size: NSSize(width: 880, height: CaptionRenderer.maxBoxHeight(p.style) + 40),
                   to: dir.appendingPathComponent("overlay-\(p.id).png"))
        }

        let icon = ImageRenderer(content: AppIconView())
        icon.scale = 0.5
        if let cg = icon.cgImage {
            try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("icon.png"))
        }
        render(BrandRow().padding(20).background(DS.backgroundTertiary), size: NSSize(width: 260, height: 70), to: dir.appendingPathComponent("brand-row.png"))
        print("snapshots written to \(dir.path)")
    }

    private static func render<V: View>(_ view: V, size: NSSize, to url: URL) {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func seed(_ model: AppModel) {
        let now = Date()
        var a = TranscriptSession(title: "Daily com o time de produto", started: now.addingTimeInterval(-2400),
                                  ended: now.addingTimeInterval(-600), sources: [.mic, .system])
        a.segments = [
            Segment(source: .system, text: "Bom dia, pessoal. Vamos começar pelo que ficou pendente da sprint passada.", start: 2, end: 7),
            Segment(source: .system, text: "O beta do app de legendas está quase pronto, falta só a parte do histórico.", start: 8, end: 13),
            Segment(source: .mic, text: "O histórico já está salvando cada sessão com data, duração e quem falou.", start: 15, end: 20),
            Segment(source: .mic, text: "Hoje eu termino a exportação em SRT e já mando a build para vocês testarem.", start: 21, end: 26),
            Segment(source: .system, text: "Perfeito. E a legenda dá para mover para qualquer lugar da tela?", start: 29, end: 33),
            Segment(source: .mic, text: "Dá, sim: é só apertar Option Command E, arrastar e redimensionar pelas laterais.", start: 35, end: 41),
        ]
        var b = TranscriptSession(started: now.addingTimeInterval(-5400), ended: now.addingTimeInterval(-4300), language: "en-US", sources: [.system])
        b.segments = [
            Segment(source: .system, text: "Welcome back to the channel. Today we are looking at on-device speech recognition on the Mac.", start: 1, end: 6),
            Segment(source: .system, text: "The new analyzer gives you volatile results almost instantly and finalizes them a moment later.", start: 7, end: 13),
        ]
        var c = TranscriptSession(title: "Aula de inglês", started: now.addingTimeInterval(-90000), ended: now.addingTimeInterval(-87000), sources: [.mic])
        c.segments = [Segment(source: .mic, text: "Hoje eu quero praticar a apresentação para a entrevista de sexta.", start: 3, end: 8)]
        model.sessions = [a, b, c]
    }
}
