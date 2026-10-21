import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Histórico: every session grouped by day (like RustleApp's Notetaker list), and the transcript
/// of one session with copy, export (.txt / .srt), rename and delete.
struct HistoryPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let id = model.openSession, let session = model.session(id) {
            SessionDetail(model: model, feed: model.feed, session: session)
        } else {
            HistoryList(model: model)
        }
    }
}

private struct HistoryList: View {
    @ObservedObject var model: AppModel
    @State private var query = ""

    var body: some View {
        PageScroll {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(title: "Histórico",
                           description: "Tudo o que foi legendado fica salvo neste Mac, com data, duração e quem falou.") {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundColor(DS.vast500)
                        TextField("", text: $query, prompt: Text("Buscar nas transcrições").foregroundColor(DS.vast500))
                            .textFieldStyle(.plain).font(DS.ui(14))
                    }
                    .padding(.horizontal, 12).frame(width: 260, height: 36)
                    .background(RoundedRectangle(cornerRadius: 8).fill(DS.card))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DS.border, lineWidth: 1))
                }

                if model.sessions.isEmpty {
                    ListCard {
                        EmptyState(icon: "clock.arrow.circlepath", title: "Nada por aqui ainda",
                                   detail: "Quando você iniciar as legendas (⌥⌘T), cada sessão aparece nesta lista.")
                    }
                } else if groups.isEmpty {
                    ListCard {
                        EmptyState(icon: "magnifyingglass", title: "Nenhum resultado",
                                   detail: "Nenhuma transcrição contém “\(query)”.")
                    }
                } else {
                    ForEach(groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(text: group.title)
                            ListCard {
                                ForEach(Array(group.sessions.enumerated()), id: \.element.id) { i, s in
                                    if i > 0 { Rectangle().fill(DS.border).frame(height: 1) }
                                    SessionRow(session: s, live: s.id == model.activeSessionID, highlight: query) {
                                        model.openSession = s.id
                                    }
                                    .contextMenu {
                                        Button("Copiar texto") { Pasteboard.copy(s.plainText) }
                                        if s.id != model.activeSessionID {
                                            Divider()
                                            Button("Excluir", role: .destructive) { model.delete(s.id) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var groups: [(title: String, sessions: [TranscriptSession])] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let filtered = q.isEmpty ? model.sessions : model.sessions.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(q) || $0.segments.contains { $0.text.localizedCaseInsensitiveContains(q) }
        }
        let cal = Calendar.current
        var out: [(title: String, sessions: [TranscriptSession])] = []
        for s in filtered {
            let title: String
            if cal.isDateInToday(s.started) { title = "Hoje" }
            else if cal.isDateInYesterday(s.started) { title = "Ontem" }
            else { title = s.started.formatted(.dateTime.weekday(.wide).day().month(.wide)) }
            if out.last?.title == title { out[out.count - 1].sessions.append(s) } else { out.append((title, [s])) }
        }
        return out
    }
}

/// A row in the history lists (.historyRow: 16 px padding, hover neutral-200).
struct SessionRow: View {
    let session: TranscriptSession
    var live = false
    var highlight = ""
    let open: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(live ? DS.vast950 : DS.backgroundTertiary)
                    if live { RecordingDot() } else {
                        Image(systemName: session.sources.count > 1 ? "person.2.wave.2" : (session.sources.first ?? .mic).icon)
                            .font(.system(size: 13)).foregroundColor(DS.foregroundTertiary)
                    }
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.displayTitle).font(DS.ui(15, DS.w550)).lineLimit(1)
                    Text(snippet).font(DS.ui(13)).foregroundColor(DS.neutral600).lineLimit(1)
                }
                Spacer(minLength: 16)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(live ? "Ao vivo" : session.started.formatted(.dateTime.hour().minute()))
                        .font(DS.ui(13, DS.w550)).foregroundColor(live ? DS.destructive500 : DS.foreground)
                    Text("\(session.durationLabel) · \(session.wordCount) palavras")
                        .font(DS.ui(12)).foregroundColor(DS.foregroundTertiary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(hover ? DS.sand100 : DS.card)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    /// The matching phrase when searching, otherwise the beginning.
    private var snippet: String {
        let q = highlight.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty, let hit = session.segments.first(where: { $0.text.localizedCaseInsensitiveContains(q) }) { return hit.text }
        return session.preview
    }
}

private struct SessionDetail: View {
    @ObservedObject var model: AppModel
    @ObservedObject var feed: CaptionFeed
    let session: TranscriptSession
    @State private var title = ""
    @State private var confirmDelete = false

    private var live: Bool { session.id == model.activeSessionID }

    var body: some View {
        ScrollViewReader { proxy in
            PageScroll {
                VStack(alignment: .leading, spacing: 24) {
                    Button { model.openSession = nil } label: {
                        Label("Histórico", systemImage: "chevron.left").font(DS.ui(13, DS.w550))
                    }
                    .buttonStyle(.plain).foregroundColor(DS.foregroundTertiary)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 12) {
                            TextField("", text: $title, prompt: Text(session.displayTitle).foregroundColor(DS.foreground))
                                .textFieldStyle(.plain)
                                .font(DS.display(30)).tracking(-1.2)
                                .onSubmit(saveTitle)
                            Spacer(minLength: 12)
                            CopyButton(text: { session.plainText }, help: "Copiar o texto")
                            Menu {
                                Button("Texto (.txt)") { export(srt: false) }
                                Button("Legendas (.srt)") { export(srt: true) }
                            } label: {
                                Image(systemName: "square.and.arrow.up").font(.system(size: 14, weight: .medium))
                                    .foregroundColor(DS.foregroundTertiary)
                            }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .help("Exportar")
                            if !live {
                                IconButton(systemName: "trash", help: "Excluir") { confirmDelete = true }
                            }
                        }
                        HStack(spacing: 8) {
                            if live { RecordingDot(); Text("Ao vivo").font(DS.ui(13, DS.w550)).foregroundColor(DS.destructive500) }
                            Text(meta).font(DS.ui(14)).foregroundColor(DS.neutral600)
                            ForEach(session.sources) { s in
                                Label(s.longLabel, systemImage: s.icon)
                                    .font(DS.ui(12, DS.w550)).foregroundColor(DS.neutral600)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(DS.backgroundTertiary))
                            }
                        }
                    }

                    if session.segments.isEmpty && !live {
                        ListCard { EmptyState(icon: "text.alignleft", title: "Sem texto", detail: "Nada foi transcrito nesta sessão.") }
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(blocks) { block in
                                TranscriptBlock(block: block, speakers: session.sources.count > 1, style: model.style)
                            }
                            if live { LiveTail(feed: feed) }
                        }
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 16).fill(DS.card))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(DS.border, lineWidth: 1))
                        Color.clear.frame(height: 1).id("bottom")
                    }
                }
            }
            .onChange(of: session.segments.count) { _, _ in
                if live { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
        }
        .onAppear { title = session.title }
        .onChange(of: session.id) { _, _ in title = session.title }
        .alert("Excluir esta transcrição?", isPresented: $confirmDelete) {
            Button("Excluir", role: .destructive) { model.delete(session.id) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("“\(session.displayTitle)” será apagada deste Mac.")
        }
    }

    private var meta: String {
        let date = session.started.formatted(.dateTime.day().month(.wide).year().hour().minute())
        return "\(date) · \(session.durationLabel) · \(session.wordCount) palavras"
    }

    private func saveTitle() {
        let t = title.trimmingCharacters(in: .whitespaces)
        model.update(session.id) { $0.title = t }
    }

    /// Consecutive segments from the same source read as one paragraph.
    private var blocks: [TranscriptBlock.Block] {
        var out: [TranscriptBlock.Block] = []
        for s in session.segments {
            if let last = out.last, last.source == s.source, s.start - last.end < 20 {
                out[out.count - 1].text += " " + s.text
                out[out.count - 1].end = s.end
            } else {
                out.append(.init(id: s.id, source: s.source, start: s.start, end: s.end, text: s.text))
            }
        }
        return out
    }

    private func export(srt: Bool) {
        let panel = NSSavePanel()
        let base = session.displayTitle.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "h")
        panel.nameFieldStringValue = base + (srt ? ".srt" : ".txt")
        panel.allowedContentTypes = [srt ? (UTType(filenameExtension: "srt") ?? .plainText) : .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? (srt ? session.srt : session.plainText).write(to: url, atomically: true, encoding: .utf8)
    }
}

private struct TranscriptBlock: View {
    struct Block: Identifiable {
        let id: UUID
        let source: AudioSource
        let start: TimeInterval
        var end: TimeInterval
        var text: String
    }

    let block: Block
    let speakers: Bool
    let style: CaptionStyle

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(TranscriptSession.clock(block.start))
                .font(DS.ui(12, .medium).monospacedDigit()).foregroundColor(DS.vast500)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                if speakers {
                    HStack(spacing: 6) {
                        Circle().fill((block.source == .mic ? style.micColor : style.systemColor).color).frame(width: 7, height: 7)
                        Text(block.source.label).font(DS.ui(12, .semibold)).foregroundColor(DS.foregroundTertiary)
                    }
                }
                Text(block.text).font(DS.ui(16)).lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What is still being recognized, under the saved lines of a live session.
private struct LiveTail: View {
    @ObservedObject var feed: CaptionFeed
    var body: some View {
        let text = AudioSource.allCases.compactMap { feed.volatile[$0]?.text }.filter { !$0.isEmpty }.joined(separator: " ")
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            RecordingDot().frame(width: 52, alignment: .leading)
            Text(text.isEmpty ? "Ouvindo…" : text).font(DS.ui(16).italic()).foregroundColor(DS.vast500)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum Pasteboard {
    static func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}
