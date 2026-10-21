import AppKit
import Combine
import SwiftUI

// MARK: - Rendering

/// Builds the caption text with AppKit attributes, so the partial words can be slanted
/// (obliqueness) in any font, even ones without an italic face.
enum CaptionRenderer {
    static func attributed(entries: [CaptionFeed.Entry], volatile: [AudioSource: CaptionFeed.Volatile],
                           style: CaptionStyle, speakers: Bool) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = style.alignment.ns
        paragraph.lineBreakMode = .byWordWrapping
        var base: [NSAttributedString.Key: Any] = [
            .font: style.font(),
            .foregroundColor: style.textColor.nsColor,
            .paragraphStyle: paragraph,
        ]
        if style.shadow {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
            shadow.shadowBlurRadius = max(2, style.fontSize / 10)
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            base[.shadow] = shadow
        }
        var partial = base
        partial[.foregroundColor] = style.partialColor.nsColor
        if style.partialItalic { partial[.obliqueness] = 0.18 }

        var last: AudioSource?
        func add(_ text: String, _ source: AudioSource, _ attrs: [NSAttributedString.Key: Any]) {
            guard !text.isEmpty else { return }
            if speakers && source != last {
                if out.length > 0 { out.append(NSAttributedString(string: "\n", attributes: base)) }
                var label = base
                label[.font] = style.font(size: max(11, style.fontSize * 0.36), weight: .heavy)
                label[.foregroundColor] = (source == .mic ? style.micColor : style.systemColor).nsColor
                label[.kern] = 1.2
                label[.obliqueness] = nil
                label[.baselineOffset] = style.fontSize * 0.1
                out.append(NSAttributedString(string: source.label.uppercased() + "  ", attributes: label))
            } else if out.length > 0 {
                out.append(NSAttributedString(string: " ", attributes: base))
            }
            out.append(NSAttributedString(string: text, attributes: attrs))
            last = source
        }
        for e in entries { add(e.text, e.source, base) }
        for source in AudioSource.allCases {
            guard let v = volatile[source], !v.isEmpty else { continue }
            add(v.stable, source, base)
            if !v.stable.isEmpty && !v.tail.isEmpty {
                out.append(NSAttributedString(string: " ", attributes: base))
                out.append(NSAttributedString(string: v.tail, attributes: partial))
            } else {
                add(v.tail, source, partial)
            }
        }
        return out
    }

    /// Height of one line of caption text.
    static func lineHeight(_ style: CaptionStyle) -> CGFloat {
        let f = style.font()
        return ceil(NSLayoutManager().defaultLineHeight(for: f))
    }

    static func height(of text: NSAttributedString, width: CGFloat) -> CGFloat {
        guard text.length > 0, width > 0 else { return 0 }
        return ceil(text.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                      options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
    }

    /// The tallest the box can get (all lines + padding).
    static func maxBoxHeight(_ style: CaptionStyle) -> CGFloat {
        lineHeight(style) * CGFloat(style.maxLines) + style.padding * 2
    }
}

/// Draws the text bottom-aligned: when it is taller than the box, the oldest lines scroll off the top.
private final class CaptionTextNSView: NSView {
    var text = NSAttributedString() { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let h = CaptionRenderer.height(of: text, width: bounds.width)
        text.draw(with: NSRect(x: 0, y: bounds.height - h, width: bounds.width, height: h),
                  options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}

private struct CaptionText: NSViewRepresentable {
    let text: NSAttributedString
    func makeNSView(context: Context) -> CaptionTextNSView { CaptionTextNSView() }
    func updateNSView(_ view: CaptionTextNSView, context: Context) { view.text = text }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

/// The caption itself: text on a rounded, translucent (optionally blurred) background.
/// Used by the overlay and by the live preview in the Legenda page.
struct CaptionBox: View {
    let style: CaptionStyle
    let text: NSAttributedString
    let width: CGFloat
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    var body: some View {
        let inner = max(40, width - style.padding * 2)
        let line = CaptionRenderer.lineHeight(style)
        let maxH = line * CGFloat(style.maxLines)
        let measured = CaptionRenderer.height(of: text, width: inner)
        let h = max(line, min(measured, maxH))
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
        CaptionText(text: text)
            .frame(width: inner, height: h)
            .mask(
                // Fade the line that is scrolling away.
                LinearGradient(stops: measured > maxH + 1
                               ? [.init(color: .clear, location: 0), .init(color: .black, location: min(0.2, line * 0.3 / h))]
                               : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            )
            .padding(style.padding)
            .frame(width: width)
            .background(
                ZStack {
                    if style.blur && style.backgroundOpacity > 0 { VisualEffect(material: .hudWindow, blending: blending) }
                    shape.fill(style.backgroundColor.color.opacity(style.backgroundOpacity))
                }
                .clipShape(shape)
            )
    }
}

extension CaptionFeed {
    /// Sample caption for the edit mode and the style preview.
    static let sample: (entries: [Entry], volatile: [AudioSource: Volatile]) = (
        [Entry(source: .system, text: "Then we ship the beta next week and"), Entry(source: .mic, text: "Perfeito, então a gente")],
        [.mic: Volatile(stable: "só não pode", tail: "esquecer")]
    )
}

// MARK: - Overlay window

/// The floating caption: a borderless, transparent panel above every app (including full-screen
/// ones) that lets clicks through. In edit mode (⌥⌘E) it takes the mouse: drag to move, pull the
/// side handles to resize. Position and width are remembered.
@MainActor
final class CaptionOverlay: ObservableObject {
    @Published private(set) var editing = false
    @Published var width: CGFloat = 860

    private let model: AppModel
    private let panel: NSPanel
    private var cancellables: Set<AnyCancellable> = []
    private var showingSample = false
    private var dragOrigin: NSPoint?
    private var dragMouse: NSPoint?
    private var dragFrame: NSRect?
    private static let hintHeight: CGFloat = 46

    init(model: AppModel) {
        self.model = model
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 860, height: 200),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.sharingType = .readOnly

        let host = NSHostingView(rootView: OverlayRoot(model: model, feed: model.feed, overlay: self))
        host.sizingOptions = []
        panel.contentView = host

        restoreFrame()
        model.$style.dropFirst().sink { [weak self] style in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.relayout(style) } }
        }.store(in: &cancellables)
        model.$settings.map(\.showOverlay).removeDuplicates().sink { [weak self] show in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.setVisible(show) } }
        }.store(in: &cancellables)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.keepOnScreen() }
        }
        setVisible(model.settings.showOverlay)
    }

    var isVisible: Bool { panel.isVisible }

    func setVisible(_ visible: Bool) {
        if visible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }

    func setEditing(_ on: Bool) {
        guard on != editing else { return }
        editing = on
        model.editingOverlay = on
        panel.ignoresMouseEvents = !on
        if on {
            if !model.settings.showOverlay { model.settings.showOverlay = true }
            panel.orderFrontRegardless()
            if model.feed.isEmpty {
                showingSample = true
                model.feed.preview(CaptionFeed.sample.entries, volatile: CaptionFeed.sample.volatile)
            }
        } else {
            if showingSample && !model.isRunning { model.feed.clear() }
            showingSample = false
            saveFrame()
        }
    }

    func toggleEditing() { setEditing(!editing) }

    /// Bottom-center of the main screen, 60% of its width.
    func resetPosition() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        width = min(980, max(420, screen.width * 0.6))
        let h = panelHeight(model.style)
        panel.setFrame(NSRect(x: screen.midX - width / 2, y: screen.minY + 40, width: width, height: h), display: true)
        saveFrame()
    }

    // MARK: Drag & resize (edit mode)

    func dragChanged() {
        let mouse = NSEvent.mouseLocation
        if dragOrigin == nil { dragOrigin = panel.frame.origin; dragMouse = mouse }
        guard let o = dragOrigin, let m = dragMouse else { return }
        panel.setFrameOrigin(NSPoint(x: o.x + mouse.x - m.x, y: o.y + mouse.y - m.y))
    }

    func resizeChanged(leading: Bool) {
        let mouse = NSEvent.mouseLocation
        if dragFrame == nil { dragFrame = panel.frame; dragMouse = mouse }
        guard var f = dragFrame, let m = dragMouse else { return }
        let dx = mouse.x - m.x
        let minW: CGFloat = 260
        if leading {
            let w = max(minW, f.width - dx)
            f.origin.x += f.width - w
            f.size.width = w
        } else {
            f.size.width = max(minW, f.width + dx)
        }
        width = f.width
        panel.setFrame(f, display: true)
    }

    func dragEnded() {
        dragOrigin = nil
        dragMouse = nil
        dragFrame = nil
        keepOnScreen()
        saveFrame()
    }

    // MARK: Layout

    private func panelHeight(_ style: CaptionStyle) -> CGFloat {
        CaptionRenderer.maxBoxHeight(style) + Self.hintHeight + 8
    }

    /// Height follows the style (font size × lines); the bottom edge stays where it is.
    private func relayout(_ style: CaptionStyle) {
        var f = panel.frame
        f.size.height = panelHeight(style)
        panel.setFrame(f, display: true)
    }

    private func keepOnScreen() {
        let f = panel.frame
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(f) } ?? NSScreen.main
        guard let v = screen?.visibleFrame else { return }
        var o = f.origin
        o.x = min(max(o.x, v.minX - f.width + 80), v.maxX - 80)
        o.y = min(max(o.y, v.minY - Self.hintHeight), v.maxY - f.height)
        if o != f.origin { panel.setFrameOrigin(o) }
    }

    private func saveFrame() {
        let f = panel.frame
        UserDefaults.standard.set(["x": f.minX, "y": f.minY, "w": f.width], forKey: Prefs.overlayFrame)
    }

    private func restoreFrame() {
        guard let d = UserDefaults.standard.dictionary(forKey: Prefs.overlayFrame) as? [String: Double],
              let x = d["x"], let y = d["y"], let w = d["w"] else {
            resetPosition()
            return
        }
        width = w
        panel.setFrame(NSRect(x: x, y: y, width: w, height: panelHeight(model.style)), display: true)
        keepOnScreen()
    }
}

private struct OverlayRoot: View {
    @ObservedObject var model: AppModel
    @ObservedObject var feed: CaptionFeed
    @ObservedObject var overlay: CaptionOverlay

    var body: some View {
        let style = model.style
        let speakers = style.showSpeaker && model.settings.enabledSources.count > 1
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            if overlay.editing {
                EditHint { overlay.setEditing(false) }
                    .transition(.opacity)
            }
            if !feed.isEmpty || overlay.editing {
                CaptionBox(style: style,
                           text: CaptionRenderer.attributed(entries: feed.entries, volatile: feed.volatile, style: style, speakers: speakers),
                           width: overlay.width)
                    .overlay(editFrame)
                    .contentShape(Rectangle())
                    .gesture(overlay.editing ? DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { _ in overlay.dragChanged() }
                        .onEnded { _ in overlay.dragEnded() } : nil)
                    .transition(.opacity)
            }
        }
        .frame(width: overlay.width)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .animation(.easeOut(duration: 0.2), value: feed.isEmpty)
        .animation(.easeOut(duration: 0.2), value: overlay.editing)
    }

    @ViewBuilder private var editFrame: some View {
        if overlay.editing {
            ZStack {
                RoundedRectangle(cornerRadius: model.style.cornerRadius, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .foregroundColor(DS.dawn500)
                HStack {
                    ResizeHandle { overlay.resizeChanged(leading: true) } ended: { overlay.dragEnded() }
                    Spacer()
                    ResizeHandle { overlay.resizeChanged(leading: false) } ended: { overlay.dragEnded() }
                }
                .padding(.horizontal, -5)
            }
        }
    }
}

private struct ResizeHandle: View {
    let changed: () -> Void
    let ended: () -> Void
    @State private var hover = false
    var body: some View {
        Capsule()
            .fill(Color.white)
            .overlay(Capsule().strokeBorder(DS.vast950, lineWidth: 1))
            .frame(width: 10, height: 44)
            .scaleEffect(hover ? 1.15 : 1)
            .onHover { inside in
                hover = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { _ in changed() }
                .onEnded { _ in ended() })
    }
}

/// Black tooltip pill, the same as RustleApp's Flow bar tooltips.
private struct EditHint: View {
    let done: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right").font(.system(size: 12, weight: .semibold))
            Text("Arraste para mover · puxe as laterais para redimensionar").font(DS.ui(14))
            Button(action: done) {
                Text("Concluir").font(DS.ui(13, DS.w550)).foregroundColor(DS.vast950)
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(Capsule().fill(DS.sand50))
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(.white)
        .padding(.leading, 14).padding(.trailing, 6).frame(height: 36)
        .background(Capsule().fill(Color.black))
        .overlay(Capsule().strokeBorder(DS.vast900, lineWidth: 1))
        .fixedSize()
    }
}
