import AppKit
import SwiftUI

/// The Rustle design system, shared with RustleApp and RustleLanguage: the "sand" / "vast"
/// neutrals, accent ramps, type scale and radii.
/// Fonts: Figtree (UI) and EB Garamond (display), both SIL OFL, bundled from Google Fonts.
enum DS {
    // MARK: Palette (exact hex values from the CSS variables)
    static let sand50 = Color(hex: 0xFCFCFB)
    static let sand100 = Color(hex: 0xFAF9F7)
    static let sand200 = Color(hex: 0xF8F7F3)
    static let sand500 = Color(hex: 0xF5F4F0)
    static let sand600 = Color(hex: 0xEEEBE3)
    static let sand700 = Color(hex: 0xC5C0B3)
    static let sand950 = Color(hex: 0x4D4A42)
    static let vast300 = Color(hex: 0xB3B2AD)
    static let vast500 = Color(hex: 0x878683)
    static let vast600 = Color(hex: 0x71716E)
    static let vast700 = Color(hex: 0x5B5B59)
    static let vast900 = Color(hex: 0x30302F)
    static let vast950 = Color(hex: 0x1A1A1A)
    static let dawn100 = Color(hex: 0xFCF7FF)
    static let dawn400 = Color(hex: 0xF4E1FF)
    static let dawn500 = Color(hex: 0xF0D7FF)
    static let dawn700 = Color(hex: 0xA26EC1)
    static let signal500 = Color(hex: 0xFFBCF2)
    static let flare400 = Color(hex: 0xFF6C4C)
    static let glow300 = Color(hex: 0xFFA946)
    static let chord600 = Color(hex: 0x7232A6)
    static let fathom500 = Color(hex: 0x68BDB0)
    static let fathom950 = Color(hex: 0x034F46)
    static let success500 = Color(hex: 0x4FBF78)
    static let destructive500 = Color(hex: 0xEE6A6A)
    static let red600 = Color(hex: 0xDC2626)

    // MARK: Semantic roles (as mapped in the CSS)
    static let background = sand50            // --background
    static let backgroundTertiary = sand500   // --background-tertiary (sidebar / window)
    static let neutral200 = sand600           // --neutral-200 (hover / active)
    static let border = sand600               // --border
    static let card = Color.white             // --card
    static let foreground = vast950           // --foreground
    static let foregroundTertiary = vast600   // --foreground-tertiary
    static let neutral600 = vast900           // --neutral-600 (descriptions)
    static let primary = vast950              // --primary
    static let primaryForeground = sand50     // --primary-foreground

    /// Processing ring: conic-gradient(#f0d7ff, #ffbcf2, #ff6c4c, #ffa946, #7232a6, #f0d7ff)
    static let rainbow: [Color] = [dawn500, signal500, flare400, glow300, chord600, dawn500]

    // MARK: Type
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Figtree", size: size).weight(weight)
    }
    /// EB Garamond display face; the CSS pairs it with letter-spacing -0.04em.
    static func display(_ size: CGFloat) -> Font {
        .custom("EB Garamond", size: size)
    }
    /// 550 in CSS sits between medium and semibold.
    static let w550: Font.Weight = .semibold
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - Reusable pieces

/// Page title: EB Garamond 28/28, letter-spacing -0.04em (settings .pageTitle).
struct PageTitle: View {
    let text: String
    var size: CGFloat = 28
    var body: some View {
        Text(text)
            .font(DS.display(size))
            .tracking(-0.04 * size)
            .foregroundColor(DS.foreground)
    }
}

/// Uppercase section label: 12/20, weight 600, letter-spacing .075em, tertiary color.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(DS.ui(12, .semibold))
            .tracking(12 * 0.075)
            .foregroundColor(DS.foregroundTertiary)
    }
}

/// Primary (black) button.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.ui(15, DS.w550))
            .foregroundColor(DS.primaryForeground)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 8).fill(DS.primary.opacity(configuration.isPressed ? 0.8 : 1)))
            .contentShape(Rectangle())
    }
}

/// Secondary (outlined, sand) button.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.ui(15, DS.w550))
            .foregroundColor(DS.foreground)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 8).fill(configuration.isPressed ? DS.neutral200 : DS.card))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DS.border, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// Small square icon button (32x32, radius 6, hover neutral-200) like the hub's sidebarAction.
struct IconButton: View {
    let systemName: String
    var help: String = ""
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(hover ? DS.foreground : DS.foregroundTertiary)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(hover ? DS.neutral200 : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

/// White list card: 1px border, radius 16, rows separated by 1px borders (history/dictionary lists).
struct ListCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 16).fill(DS.card))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(DS.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// Settings card: padding 20, radius 12, background-tertiary.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 20) { content }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(DS.backgroundTertiary))
    }
}

/// Single-line text input in the hub style.
struct HubTextField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}
    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(DS.vast500))
            .textFieldStyle(.plain)
            .font(DS.ui(15))
            .foregroundColor(DS.foreground)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 8).fill(DS.card))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DS.border, lineWidth: 1))
            .onSubmit(onSubmit)
    }
}

/// Scrollable page body: padding 40, content max-width ~800 (.pageScrollable).
struct PageScroll<Content: View>: View {
    var maxWidth: CGFloat = 800
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: maxWidth, alignment: .leading)
                .padding(40)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    let description: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 12) {
                PageTitle(text: title)
                Text(description).font(DS.ui(15)).foregroundColor(DS.neutral600)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 24)
            trailing
        }
    }
}

/// Outlined / filled buttons on dark cards (Notetaker's live card).
struct DarkButtonStyle: ButtonStyle {
    let filled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.ui(14, DS.w550))
            .foregroundColor(filled ? DS.vast950 : DS.sand50)
            .padding(.horizontal, 12).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(filled ? DS.sand50 : Color.white.opacity(configuration.isPressed ? 0.15 : 0.08)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(filled ? 0 : 0.2), lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// Small capsule button (.inBarPill: height 26-30, radius 9999, 1 px border).
struct PillButton: View {
    let title: String
    var icon: String? = nil
    var active = false
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .medium)) }
                Text(title).font(DS.ui(13, DS.w550))
            }
            .foregroundColor(active ? DS.sand50 : DS.foreground)
            .padding(.horizontal, 12).frame(height: 30)
            .background(Capsule().fill(active ? DS.vast950 : (hover ? DS.neutral200 : DS.background)))
            .overlay(Capsule().strokeBorder(active ? DS.vast950 : DS.border, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Pulsing red dot used while recording.
struct RecordingDot: View {
    var color: Color = DS.destructive500
    @State private var on = false
    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
            .opacity(on ? 1 : 0.35)
            .animation(.easeInOut(duration: 0.9).repeatForever(), value: on)
            .onAppear { on = true }
    }
}

/// Wraps children onto new lines, like inline text (chips, karaoke words).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat? = nil

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { y += row + (lineSpacing ?? spacing); x = 0; row = 0 }
            x += size.width + spacing; row = max(row, size.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { y += row + (lineSpacing ?? spacing); x = bounds.minX; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; row = max(row, size.height)
        }
    }
}

/// .emptyTable: icon tile + 20/28 w600 title + 15/20 body.
struct EmptyState: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(DS.foregroundTertiary)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 6).fill(DS.backgroundTertiary))
            VStack(spacing: 8) {
                Text(title).font(DS.ui(20, .semibold))
                Text(detail).font(DS.ui(15)).foregroundColor(DS.neutral600)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// Copies to the pasteboard and flips a checkmark for a moment.
struct CopyButton: View {
    let text: () -> String
    var help = "Copiar"
    @State private var copied = false
    var body: some View {
        IconButton(systemName: copied ? "checkmark" : "doc.on.doc", help: help) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text(), forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        }
    }
}

/// Score ring (0–100): green / amber / red stroke over the sand track.
struct ScoreRing: View {
    let score: Int
    var size: CGFloat = 64
    var body: some View {
        ZStack {
            Circle().stroke(DS.neutral200, lineWidth: size / 10)
            Circle().trim(from: 0, to: CGFloat(max(0, min(100, score))) / 100)
                .stroke(Self.color(score), style: StrokeStyle(lineWidth: size / 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)").font(DS.display(size * 0.42)).tracking(-1)
        }
        .frame(width: size, height: size)
    }
    static func color(_ score: Int) -> Color {
        score >= 80 ? DS.success500 : score >= 60 ? DS.glow300 : DS.destructive500
    }
}
