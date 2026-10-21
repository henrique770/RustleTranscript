import AppKit
import SwiftUI

// MARK: - Sources

/// Where a line of speech came from: your microphone or what the Mac is playing.
enum AudioSource: String, Codable, CaseIterable, Identifiable {
    case mic, system
    var id: String { rawValue }
    var label: String { self == .mic ? "Você" : "Computador" }
    var longLabel: String { self == .mic ? "Microfone" : "Áudio do computador" }
    var icon: String { self == .mic ? "mic.fill" : "speaker.wave.2.fill" }
}

// MARK: - History

/// One transcribed segment (a finalized phrase from the recognizer).
struct Segment: Codable, Identifiable, Hashable {
    var id = UUID()
    var source: AudioSource
    var text: String
    /// Seconds since the session started.
    var start: TimeInterval
    var end: TimeInterval
}

/// A transcription session, from Iniciar to Parar, as saved in the history.
struct TranscriptSession: Codable, Identifiable, Hashable {
    var id = UUID()
    var title = ""
    var started = Date()
    var ended: Date?
    var language = "pt-BR"
    var sources: [AudioSource] = [.mic]
    var segments: [Segment] = []

    var isLive: Bool { ended == nil }

    var displayTitle: String {
        if !title.trimmingCharacters(in: .whitespaces).isEmpty { return title }
        return "Transcrição · \(started.formatted(.dateTime.day().month(.abbreviated).hour().minute()))"
    }

    var duration: TimeInterval { (ended ?? Date()).timeIntervalSince(started) }

    var durationLabel: String {
        let m = Int(duration) / 60
        return m < 1 ? "< 1 min" : m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) min"
    }

    var wordCount: Int { segments.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count } }

    /// First words, for the list preview.
    var preview: String {
        let text = segments.map(\.text).joined(separator: " ")
        return text.isEmpty ? "Nada transcrito ainda" : String(text.prefix(160))
    }

    var plainText: String {
        var lines: [String] = []
        var last: AudioSource?
        for s in segments {
            if s.source != last && sources.count > 1 { lines.append(""); lines.append("\(s.source.label):") }
            lines.append(s.text)
            last = s.source
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var srt: String {
        segments.enumerated().map { i, s in
            let speaker = sources.count > 1 ? "[\(s.source.label)] " : ""
            return "\(i + 1)\n\(Self.srtTime(s.start)) --> \(Self.srtTime(max(s.end, s.start + 0.5)))\n\(speaker)\(s.text)\n"
        }.joined(separator: "\n")
    }

    static func srtTime(_ t: TimeInterval) -> String {
        let ms = Int((t * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
    }
}

// MARK: - Caption style

/// A color that can be stored in JSON (sRGB components).
struct RGBA: Codable, Equatable, Hashable {
    var r: Double, g: Double, b: Double, a: Double = 1

    init(r: Double, g: Double, b: Double, a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    init(hex: UInt32, a: Double = 1) {
        self.init(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255, a: a)
    }
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(r: ns.redComponent, g: ns.greenComponent, b: ns.blueComponent, a: ns.alphaComponent)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }

    static let white = RGBA(hex: 0xFFFFFF)
    static let black = RGBA(hex: 0x000000)
}

/// Everything about how the on-screen caption looks. Stored as JSON in UserDefaults.
struct CaptionStyle: Codable, Equatable {
    enum Weight: String, Codable, CaseIterable, Identifiable {
        case regular, medium, semibold, bold, heavy
        var id: String { rawValue }
        var label: String {
            switch self {
            case .regular: return "Normal"
            case .medium: return "Média"
            case .semibold: return "Semi"
            case .bold: return "Negrito"
            case .heavy: return "Black"
            }
        }
        var ns: NSFont.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            case .heavy: return .heavy
            }
        }
    }

    enum Align: String, Codable, CaseIterable, Identifiable {
        case leading, center, trailing
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .leading: return "text.alignleft"
            case .center: return "text.aligncenter"
            case .trailing: return "text.alignright"
            }
        }
        var ns: NSTextAlignment { self == .leading ? .left : self == .center ? .center : .right }
    }

    var fontName = "Figtree"
    var fontSize: Double = 44
    var weight: Weight = .bold
    var textColor: RGBA = .white
    /// The words still being recognized (volatile): the italic grey of the reference caption.
    var partialColor = RGBA(hex: 0xB3B2AD)
    var partialItalic = true
    var backgroundColor = RGBA(hex: 0x1A1A1A)
    var backgroundOpacity: Double = 0.72
    var blur = true
    var cornerRadius: Double = 18
    var padding: Double = 18
    var maxLines = 2
    var alignment: Align = .leading
    var shadow = true
    /// Shows "VOCÊ" / "COMPUTADOR" before the text when both sources are on.
    var showSpeaker = true
    var micColor = RGBA(hex: 0x68BDB0)
    var systemColor = RGBA(hex: 0xFFA946)
    /// Seconds of silence before the caption fades away (0 = never).
    var fadeAfter: Double = 5

    static let fonts = ["Figtree", "EB Garamond", "SF Pro", "SF Rounded", "Helvetica Neue", "Avenir Next", "Georgia", "Menlo"]

    func font(size: Double? = nil, weight: Weight? = nil) -> NSFont {
        let size = CGFloat(size ?? fontSize)
        let w = (weight ?? self.weight).ns
        switch fontName {
        case "SF Pro":
            return .systemFont(ofSize: size, weight: w)
        case "SF Rounded":
            let base = NSFont.systemFont(ofSize: size, weight: w)
            return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        default:
            let descriptor = NSFontDescriptor(fontAttributes: [
                .family: fontName,
                .traits: [NSFontDescriptor.TraitKey.weight: w.rawValue],
            ])
            if let f = NSFont(descriptor: descriptor, size: size), f.familyName == fontName { return f }
            return .systemFont(ofSize: size, weight: w)
        }
    }

    /// Height of one caption line in points.
    var lineHeight: CGFloat {
        let f = font()
        return ceil(f.ascender - f.descender + f.leading) * 1.08
    }

    // MARK: Presets

    struct Preset: Identifiable {
        let id: String
        let name: String
        let style: CaptionStyle
    }

    static let presets: [Preset] = {
        let classic = CaptionStyle()
        var cinema = CaptionStyle()
        cinema.fontName = "SF Pro"; cinema.fontSize = 38; cinema.weight = .semibold
        cinema.backgroundOpacity = 0; cinema.blur = false; cinema.alignment = .center
        cinema.partialItalic = false; cinema.partialColor = RGBA(hex: 0xE5E5E5); cinema.shadow = true
        var paper = CaptionStyle()
        paper.fontName = "EB Garamond"; paper.fontSize = 40; paper.weight = .medium
        paper.textColor = RGBA(hex: 0x1A1A1A); paper.partialColor = RGBA(hex: 0x878683)
        paper.backgroundColor = RGBA(hex: 0xFAF9F7); paper.backgroundOpacity = 0.94; paper.blur = false
        paper.shadow = false; paper.cornerRadius = 22
        paper.micColor = RGBA(hex: 0x034F46); paper.systemColor = RGBA(hex: 0xA26EC1)
        var compact = CaptionStyle()
        compact.fontSize = 24; compact.weight = .semibold; compact.maxLines = 3
        compact.cornerRadius = 12; compact.padding = 12; compact.backgroundOpacity = 0.82
        var neon = CaptionStyle()
        neon.fontName = "SF Rounded"; neon.fontSize = 46; neon.weight = .heavy
        neon.textColor = RGBA(hex: 0xF0D7FF); neon.partialColor = RGBA(hex: 0xFFBCF2)
        neon.backgroundColor = RGBA(hex: 0x7232A6); neon.backgroundOpacity = 0.55
        return [
            Preset(id: "classic", name: "Clássico", style: classic),
            Preset(id: "cinema", name: "Cinema", style: cinema),
            Preset(id: "paper", name: "Papel", style: paper),
            Preset(id: "compact", name: "Compacto", style: compact),
            Preset(id: "dawn", name: "Dawn", style: neon),
        ]
    }()
}

// MARK: - Settings

struct AppSettings: Codable, Equatable {
    /// "auto" = Whisper, any language detected on the fly; otherwise Apple's recognizer in that language.
    var language = AppSettings.auto
    var whisperModel = WhisperModel.defaultVariant
    var captureMic = true
    var captureSystem = true
    /// Drop mic phrases that repeat what the computer just played (speakers heard by the mic).
    var echoCancellation = true
    var showOverlay = true

    static let auto = "auto"
    var usesWhisper: Bool { language == Self.auto }

    static let languages: [(id: String, name: String)] = [
        (auto, "Automático · qualquer idioma"),
        ("pt-BR", "Português (Brasil)"), ("pt-PT", "Português (Portugal)"), ("en-US", "English (US)"),
        ("en-GB", "English (UK)"), ("es-ES", "Español"), ("fr-FR", "Français"), ("de-DE", "Deutsch"),
        ("it-IT", "Italiano"), ("ja-JP", "日本語"), ("zh-CN", "中文"),
    ]

    var enabledSources: [AudioSource] {
        AudioSource.allCases.filter { $0 == .mic ? captureMic : captureSystem }
    }
}

enum Prefs {
    static let style = "captionStyle"
    static let settings = "appSettings"
    static let overlayFrame = "overlayFrame"
}
