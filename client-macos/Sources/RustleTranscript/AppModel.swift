import AppKit
import SwiftUI

/// App state shared by the hub window, the caption overlay and the menu-bar item.
/// History lives in ~/Library/Application Support/RustleTranscript/sessions.json; the caption
/// style and settings in UserDefaults.
@MainActor
final class AppModel: ObservableObject {
    enum EngineState: Equatable {
        case idle
        case preparing(String)
        case downloading(Double)
        case running
        case failed(String)
    }

    struct Permissions: Equatable {
        var microphone = false
    }

    @Published var sessions: [TranscriptSession] = []
    @Published var style: CaptionStyle { didSet { if persist { save(style, Prefs.style) }; feed.style = style } }
    @Published var settings: AppSettings { didSet { if persist { save(settings, Prefs.settings) } } }
    @Published var engine: EngineState = .idle
    @Published var activeSessionID: UUID?
    /// Session shown in Histórico (nil = the list).
    @Published var openSession: UUID?
    @Published var pageRequest: MainView.Page?
    @Published var permissions = Permissions()
    @Published var editingOverlay = false

    /// The live caption, kept apart so volatile text does not redraw the whole hub.
    let feed = CaptionFeed()

    // Actions wired by AppDelegate.
    var start: () -> Void = {}
    var stop: () -> Void = {}
    var toggleEditOverlay: () -> Void = {}
    var resetOverlayPosition: () -> Void = {}
    var requestPermissions: () -> Void = {}

    private let persist: Bool
    private var saveWork: DispatchWorkItem?

    nonisolated static let folder: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RustleTranscript")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    static var sessionsURL: URL { folder.appendingPathComponent("sessions.json") }

    init(persist: Bool = true) {
        self.persist = persist
        let style: CaptionStyle = persist ? Self.load(Prefs.style) ?? CaptionStyle() : CaptionStyle()
        self.style = style
        settings = persist ? Self.load(Prefs.settings) ?? AppSettings() : AppSettings()
        feed.style = style
        guard persist else { return }
        if let data = try? Data(contentsOf: Self.sessionsURL),
           let saved = try? JSONDecoder().decode([TranscriptSession].self, from: data) {
            // A session still marked live means the app quit mid-transcription.
            sessions = saved.map { s in
                var s = s
                if s.ended == nil { s.ended = s.started.addingTimeInterval(s.segments.last?.end ?? 0) }
                return s
            }
        }
    }

    var isRunning: Bool { activeSessionID != nil }

    var displayFirstName: String {
        NSFullUserName().split(separator: " ").first.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? ""
    }

    // MARK: Sessions

    func session(_ id: UUID) -> TranscriptSession? { sessions.first { $0.id == id } }

    func beginSession() -> UUID {
        let s = TranscriptSession(language: settings.language, sources: settings.enabledSources)
        sessions.insert(s, at: 0)
        activeSessionID = s.id
        scheduleSave()
        return s.id
    }

    func endSession() {
        guard let id = activeSessionID else { return }
        update(id) { $0.ended = Date() }
        // Nothing said: don't keep an empty entry in the history.
        if let s = session(id), s.segments.isEmpty { sessions.removeAll { $0.id == id } }
        activeSessionID = nil
        saveNow()
    }

    func append(_ segment: Segment) {
        guard let id = activeSessionID else { return }
        update(id) { $0.segments.append(segment) }
    }

    func update(_ id: UUID, _ change: (inout TranscriptSession) -> Void) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        change(&sessions[i])
        scheduleSave()
    }

    func delete(_ id: UUID) {
        guard id != activeSessionID else { return }
        sessions.removeAll { $0.id == id }
        if openSession == id { openSession = nil }
        saveNow()
    }

    func deleteAll() {
        sessions.removeAll { $0.id != activeSessionID }
        openSession = nil
        saveNow()
    }

    // MARK: Stats

    var totalMinutes: Int { Int(sessions.reduce(0) { $0 + $1.duration } / 60) }
    var totalWords: Int { sessions.reduce(0) { $0 + $1.wordCount } }

    // MARK: Persistence

    private func scheduleSave() {
        guard persist else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.saveNow() } }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    func saveNow() {
        guard persist else { return }
        saveWork?.cancel()
        let snapshot = sessions, url = Self.sessionsURL
        DispatchQueue.global(qos: .utility).async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

/// The text on screen right now: recently finalized phrases plus what each source is still saying.
/// Clears itself after `style.fadeAfter` seconds of silence.
@MainActor
final class CaptionFeed: ObservableObject {
    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let source: AudioSource
        let text: String
    }

    /// A phrase still being recognized: the words that held still across the last two updates,
    /// and the tail that keeps changing (drawn in the "partial" style, italic grey by default).
    struct Volatile: Equatable {
        var stable = ""
        var tail = ""
        var isEmpty: Bool { stable.isEmpty && tail.isEmpty }
        var text: String { [stable, tail].filter { !$0.isEmpty }.joined(separator: " ") }
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var volatile: [AudioSource: Volatile] = [:]
    @Published var levels: [AudioSource: [CGFloat]] = [.mic: Array(repeating: 0, count: 12), .system: Array(repeating: 0, count: 12)]
    @Published var elapsed: TimeInterval = 0
    var style = CaptionStyle()

    private var fadeWork: DispatchWorkItem?

    var isEmpty: Bool { entries.isEmpty && volatile.values.allSatisfy { $0.isEmpty } }

    func setVolatile(_ text: String, from source: AudioSource) {
        let words = text.split(separator: " ").map(String.init)
        let previous = (volatile[source]?.text ?? "").split(separator: " ").map(String.init)
        var k = 0
        while k < min(words.count, previous.count), words[k] == previous[k] { k += 1 }
        // The last word can always still change.
        k = min(k, max(words.count - 1, 0))
        volatile[source] = Volatile(stable: words[..<k].joined(separator: " "), tail: words[k...].joined(separator: " "))
        keepAlive()
    }

    func commit(_ text: String, from source: AudioSource) {
        volatile[source] = Volatile()
        guard !text.isEmpty else { return }
        entries.append(Entry(source: source, text: text))
        // Only the tail is ever visible; keep the layout cheap.
        if entries.count > 12 { entries.removeFirst(entries.count - 12) }
        keepAlive()
    }

    func clear() {
        fadeWork?.cancel()
        entries.removeAll()
        volatile.removeAll()
    }

    func push(level: Float, from source: AudioSource) {
        let db = 20 * log10(max(level, 1e-5))
        var bars = levels[source] ?? Array(repeating: 0, count: 12)
        bars.removeFirst()
        bars.append(CGFloat(max(0, min(1, (db + 55) / 45))))
        levels[source] = bars
    }

    /// Sample text for previews and the edit mode.
    func preview(_ entries: [Entry], volatile: [AudioSource: Volatile]) {
        fadeWork?.cancel()
        self.entries = entries
        self.volatile = volatile
    }

    private func keepAlive() {
        fadeWork?.cancel()
        guard style.fadeAfter > 0 else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.volatile.values.allSatisfy({ $0.isEmpty }) else { return }
                withAnimation(.easeOut(duration: 0.35)) { self.entries.removeAll() }
            }
        }
        fadeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + style.fadeAfter, execute: work)
    }
}
