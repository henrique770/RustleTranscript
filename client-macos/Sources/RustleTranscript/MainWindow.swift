import AppKit
import SwiftUI

/// The hub window, same frame as RustleApp and RustleLanguage: a 216 px sand sidebar and the page
/// as an inset card (radius 24/24/16/16, 1 px border, 8 px right/bottom margin) under a 52 px
/// title-bar strip.
struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var page: Page

    init(model: AppModel, initialPage: Page = .home) {
        self.model = model
        _page = State(initialValue: initialPage)
    }

    enum Page: String, CaseIterable, Identifiable {
        case home, history, caption, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .home: return "Início"
            case .history: return "Histórico"
            case .caption: return "Legenda"
            case .settings: return "Configurações"
            }
        }
        var icon: String {
            switch self {
            case .home: return "square.grid.2x2"
            case .history: return "clock.arrow.circlepath"
            case .caption: return "captions.bubble"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model, page: $page)
            VStack(spacing: 0) {
                Color.clear.frame(height: 52)
                PageCard {
                    switch page {
                    case .home: HomePage(model: model, feed: model.feed, page: $page)
                    case .history: HistoryPage(model: model)
                    case .caption: CaptionStylePage(model: model)
                    case .settings: SettingsPage(model: model)
                    }
                }
                .padding(.trailing, 8)
                .padding(.bottom, 8)
            }
        }
        .background(DS.backgroundTertiary)
        .foregroundColor(DS.foreground)
        .font(DS.ui(15))
        .tint(DS.vast950)
        .frame(minWidth: 920, minHeight: 620)
        .ignoresSafeArea()
        .onChange(of: model.pageRequest) { _, request in
            guard let request else { return }
            page = request
            model.pageRequest = nil
        }
    }
}

// MARK: - Frame

private struct PageCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 16,
                                           bottomTrailingRadius: 16, topTrailingRadius: 24)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(shape.fill(DS.background))
            .clipShape(shape)
            .overlay(shape.stroke(DS.border, lineWidth: 1))
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @ObservedObject var model: AppModel
    @Binding var page: MainView.Page

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(height: 28)
            BrandRow().padding(.bottom, 16)
            VStack(spacing: 4) {
                ForEach([MainView.Page.home, .history, .caption]) { p in
                    SidebarItem(title: p.title, icon: p.icon, active: page == p,
                                recording: p == .home && model.isRunning,
                                badge: p == .history ? model.sessions.count : 0) {
                        if p == .history && page == .history { model.openSession = nil }
                        page = p
                    }
                }
            }
            Spacer(minLength: 0)
            if model.settings.captureMic && !model.permissions.microphone {
                SidebarNudge(title: "Conceda o microfone", detail: "Sem ele o Rustle Transcript não ouve a sua voz.") {
                    model.requestPermissions()
                    page = .settings
                }
            }
            SidebarLive(model: model)
            Rectangle().fill(DS.border).frame(height: 1).padding(.top, 8)
            VStack(spacing: 4) {
                SidebarItem(title: MainView.Page.settings.title, icon: MainView.Page.settings.icon,
                            active: page == .settings) { page = .settings }
                SidebarItem(title: "Ajuda", icon: "questionmark.circle", active: false) {
                    NSWorkspace.shared.open(Log.url)
                }
            }
            .padding(.top, 8)
        }
        .padding(12)
        .frame(width: 216)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Start / stop from anywhere in the hub.
private struct SidebarLive: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Button { model.isRunning ? model.stop() : model.start() } label: {
            HStack(spacing: 8) {
                if model.isRunning { RecordingDot() } else { Image(systemName: "captions.bubble.fill").font(.system(size: 13)) }
                Text(model.isRunning ? "Parar legendas" : "Iniciar legendas").lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isBusy)
        .help("⌥⌘T")
    }
    private var isBusy: Bool {
        if case .preparing = model.engine { return true }
        if case .downloading = model.engine { return true }
        return false
    }
}

private struct SidebarItem: View {
    let title: String
    let icon: String
    let active: Bool
    var recording = false
    var badge = 0
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 20, height: 20)
                Text(title).font(DS.ui(15, DS.w550))
                Spacer(minLength: 0)
                if recording { RecordingDot() }
                if badge > 0 {
                    Text("\(badge)").font(DS.ui(12, DS.w550)).foregroundColor(DS.foregroundTertiary)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(active || hover ? DS.neutral200 : DS.backgroundTertiary))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct SidebarNudge: View {
    let title: String
    let detail: String
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(DS.ui(15, .semibold))
                Text(detail).font(DS.ui(13)).foregroundColor(DS.neutral600)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(DS.neutral200))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DS.border, lineWidth: 1))
            .shadow(color: Color(hex: 0x1A1A1A, opacity: 0.1), radius: 3, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }
}

// MARK: - Home

private struct HomePage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var feed: CaptionFeed
    @Binding var page: MainView.Page

    var body: some View {
        PageScroll {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .firstTextBaseline) {
                    PageTitle(text: model.displayFirstName.isEmpty ? "Bem-vindo de volta" : "Bem-vindo de volta, \(model.displayFirstName)", size: 34)
                    Spacer()
                    StatusChip(model: model)
                }

                HStack(spacing: 36) {
                    Stat(value: "\(model.sessions.count)", label: model.sessions.count == 1 ? "transcrição" : "transcrições")
                    Stat(value: "\(model.totalMinutes)", label: "min legendados")
                    Stat(value: model.totalWords.formatted(), label: "palavras")
                }

                LiveHero(model: model, feed: feed, openHistory: {
                    model.openSession = model.activeSessionID
                    page = .history
                }, openStyle: { page = .caption })

                if model.settings.captureMic && !model.permissions.microphone {
                    SetupBanner(icon: "mic", title: "Falta a permissão do microfone",
                                detail: "O microfone ouve a sua voz. O áudio do computador é pedido pelo macOS na primeira vez que você iniciar.",
                                button: "Permitir") { model.requestPermissions() }
                }

                RecentSessions(model: model, page: $page)
            }
        }
    }
}

struct StatusChip: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(DS.ui(13, .medium)).foregroundColor(DS.neutral600)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(DS.backgroundTertiary))
    }
    private var color: Color {
        switch model.engine {
        case .running: return DS.destructive500
        case .preparing, .downloading: return DS.glow300
        case .failed: return DS.destructive500
        case .idle: return model.settings.captureMic && !model.permissions.microphone ? DS.glow300 : DS.success500
        }
    }
    private var text: String {
        switch model.engine {
        case .running: return "Transcrevendo"
        case .preparing(let s): return s
        case .downloading(let p): return "Baixando modelo de fala · \(Int(p * 100))%"
        case .failed: return "Não foi possível iniciar"
        case .idle: return "Pronto · reconhecimento local"
        }
    }
}

private struct Stat: View {
    let value: String
    let label: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value).font(DS.display(28)).tracking(-1.1)
            Text(label).font(DS.ui(16)).foregroundColor(DS.neutral600)
        }
    }
}

/// Dark hero card (vast-950), the same treatment as RustleApp's hotkey hint and RustleLanguage's
/// practice card. Idle: start + sources. Live: the caption as it is being written, with levels.
private struct LiveHero: View {
    @ObservedObject var model: AppModel
    @ObservedObject var feed: CaptionFeed
    let openHistory: () -> Void
    let openStyle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.isRunning { live } else { idle }
            if case .failed(let message) = model.engine {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(DS.ui(14)).foregroundColor(DS.destructive500)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(DS.vast950))
    }

    private var idle: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Legendas ao vivo para tudo que você fala e ouve")
                    .font(DS.display(28)).tracking(-1.1).foregroundColor(DS.sand50)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Sua voz e o áudio do computador viram texto na tela em tempo real, reconhecidos aqui no seu Mac.")
                    .font(DS.ui(15)).foregroundColor(DS.vast300)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    SourceToggle(source: .mic, on: $model.settings.captureMic)
                    SourceToggle(source: .system, on: $model.settings.captureSystem)
                }
                .padding(.top, 8)
                HStack(spacing: 8) {
                    Button(action: model.start) {
                        HStack(spacing: 8) {
                            Label(busyLabel ?? "Iniciar transcrição", systemImage: "waveform")
                            if busyLabel == nil { Text("⌥⌘T").foregroundColor(DS.vast500) }
                        }
                    }
                    .buttonStyle(DarkButtonStyle(filled: true))
                    .disabled(busyLabel != nil)
                    Button(action: model.toggleEditOverlay) { Label("Posicionar legenda", systemImage: "arrow.up.and.down.and.arrow.left.and.right") }
                        .buttonStyle(DarkButtonStyle(filled: false))
                    Button(action: openStyle) { Label("Estilo", systemImage: "paintbrush") }
                        .buttonStyle(DarkButtonStyle(filled: false))
                }
                .padding(.top, 6)
                if case .downloading(let p) = model.engine {
                    ProgressView(value: p).tint(DS.fathom500).frame(maxWidth: 320)
                }
            }
            Spacer(minLength: 0)
            BrandMark().frame(width: 76, height: 76).opacity(0.9)
        }
    }

    private var busyLabel: String? {
        switch model.engine {
        case .preparing(let s): return s
        case .downloading(let p): return "Baixando modelo · \(Int(p * 100))%"
        default: return nil
        }
    }

    private var live: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                RecordingDot()
                Text("Ao vivo").font(DS.ui(14, DS.w550)).foregroundColor(DS.sand50)
                Text(TranscriptSession.clock(feed.elapsed)).font(DS.ui(14).monospacedDigit()).foregroundColor(DS.vast300)
                Spacer()
                ForEach(model.settings.enabledSources) { s in
                    HStack(spacing: 6) {
                        Image(systemName: s.icon).font(.system(size: 11)).foregroundColor(DS.vast300)
                        LevelBars(levels: feed.levels[s] ?? [])
                    }
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                }
            }
            LiveText(feed: feed, style: model.style, speakers: model.settings.enabledSources.count > 1)
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .bottomLeading)
            HStack(spacing: 8) {
                Button(action: model.stop) { Label(busyLabel ?? "Parar", systemImage: "stop.fill") }
                    .buttonStyle(DarkButtonStyle(filled: true))
                    .disabled(busyLabel != nil)
                Button(action: model.toggleEditOverlay) { Label(model.editingOverlay ? "Concluir posição" : "Posicionar legenda", systemImage: "arrow.up.and.down.and.arrow.left.and.right") }
                    .buttonStyle(DarkButtonStyle(filled: false))
                Button(action: openHistory) { Label("Ver transcrição completa", systemImage: "text.alignleft") }
                    .buttonStyle(DarkButtonStyle(filled: false))
            }
        }
    }
}

/// The live caption inside the app, in the brand's display face: finished text in sand, the words
/// still changing in italic grey.
private struct LiveText: View {
    @ObservedObject var feed: CaptionFeed
    let style: CaptionStyle
    let speakers: Bool

    var body: some View {
        if feed.isEmpty {
            Text("Comece a falar ou dê play em algo…")
                .font(DS.display(26)).tracking(-0.8).foregroundColor(DS.vast600)
        } else {
            Text(text).tracking(-0.9).lineSpacing(2)
                .lineLimit(4)
                .truncationMode(.head)
        }
    }

    private var text: AttributedString {
        var out = AttributedString()
        var last: AudioSource?
        func run(_ s: String, font: Font, color: Color) {
            var a = AttributedString(s)
            a.font = font
            a.foregroundColor = color
            out += a
        }
        func add(_ t: String, _ s: AudioSource, partial: Bool) {
            guard !t.isEmpty else { return }
            if speakers && s != last {
                if !out.characters.isEmpty { run("\n", font: DS.display(30), color: DS.sand50) }
                run(s.label.uppercased() + "  ", font: DS.ui(12, .heavy), color: (s == .mic ? style.micColor : style.systemColor).color)
            } else if !out.characters.isEmpty {
                run(" ", font: DS.display(30), color: DS.sand50)
            }
            run(t, font: partial ? DS.display(30).italic() : DS.display(30), color: partial ? DS.vast500 : DS.sand50)
            last = s
        }
        for e in feed.entries.suffix(4) { add(e.text, e.source, partial: false) }
        for s in AudioSource.allCases {
            guard let v = feed.volatile[s], !v.isEmpty else { continue }
            add(v.stable, s, partial: false)
            if !v.stable.isEmpty && !v.tail.isEmpty {
                run(" ", font: DS.display(30), color: DS.sand50)
                run(v.tail, font: DS.display(30).italic(), color: DS.vast500)
            } else {
                add(v.tail, s, partial: true)
            }
        }
        return out
    }
}

private struct SourceToggle: View {
    let source: AudioSource
    @Binding var on: Bool
    var body: some View {
        Button { on.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 12))
                    .foregroundColor(on ? DS.fathom500 : DS.vast600)
                Image(systemName: source.icon).font(.system(size: 11))
                Text(source.longLabel).font(DS.ui(13, DS.w550))
            }
            .foregroundColor(on ? DS.sand50 : DS.vast500)
            .padding(.horizontal, 12).frame(height: 30)
            .background(Capsule().fill(Color.white.opacity(on ? 0.1 : 0.04)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(on ? 0.22 : 0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// White bars driven by the input level, like the Flow bar's waveform.
struct LevelBars: View {
    let levels: [CGFloat]
    var color: Color = .white
    var body: some View {
        HStack(spacing: 2) {
            ForEach(levels.indices, id: \.self) { i in
                Capsule().fill(color).frame(width: 2.5, height: max(3, levels[i] * 16))
            }
        }
        .frame(height: 16)
        .animation(.linear(duration: 0.08), value: levels)
    }
}

private struct SetupBanner: View {
    let icon: String
    let title: String
    let detail: String
    let button: String
    let action: () -> Void
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 18)).foregroundColor(DS.foregroundTertiary)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(DS.card))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(DS.ui(16, .semibold))
                Text(detail).font(DS.ui(14)).foregroundColor(DS.neutral600).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(button, action: action).buttonStyle(PrimaryButtonStyle())
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(DS.backgroundTertiary))
    }
}

private struct RecentSessions: View {
    @ObservedObject var model: AppModel
    @Binding var page: MainView.Page
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "Recentes")
                Spacer()
                if model.sessions.count > 4 {
                    Button("Ver tudo") { model.openSession = nil; page = .history }
                        .buttonStyle(.plain).font(DS.ui(13, DS.w550)).foregroundColor(DS.foregroundTertiary)
                }
            }
            if model.sessions.isEmpty {
                ListCard {
                    EmptyState(icon: "captions.bubble", title: "Nenhuma transcrição ainda",
                               detail: "Inicie as legendas e tudo que for dito fica salvo aqui, com data, duração e quem falou.")
                }
            } else {
                ListCard {
                    ForEach(Array(model.sessions.prefix(4).enumerated()), id: \.element.id) { i, s in
                        if i > 0 { Rectangle().fill(DS.border).frame(height: 1) }
                        SessionRow(session: s, live: s.id == model.activeSessionID) {
                            model.openSession = s.id
                            page = .history
                        }
                    }
                }
            }
        }
    }
}
