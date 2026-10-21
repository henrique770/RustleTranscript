import AppKit
import SwiftUI

/// Rustle Transcript's mark: RustleApp's black tile and sound bars, with the sound turning into two
/// caption lines. The second line is slanted and grey, like a word still being recognized, and
/// ends in a fathom (teal) cursor. Drawn on a 100-unit grid.
struct BrandMark: View {
    var body: some View {
        Canvas { ctx, size in
            let k = min(size.width, size.height) / 100
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x * k, y: y * k, width: w * k, height: h * k) }

            let tile = Path(roundedRect: r(0, 0, 100, 100), cornerRadius: 23 * k, style: .continuous)
            ctx.fill(tile, with: .linearGradient(Gradient(colors: [Color(hex: 0x2E2E2D), DS.vast950]),
                                                 startPoint: .zero, endPoint: CGPoint(x: 100 * k, y: 100 * k)))

            // Sound: three bars, like RustleApp's waveform.
            for (x, h) in [(17.0, 16.0), (26.0, 34.0), (35.0, 24.0)] {
                ctx.fill(Path(roundedRect: r(x, 50 - h / 2, 5.5, h), cornerRadius: 2.75 * k), with: .color(DS.sand50))
            }

            // Text: a finished line in white…
            ctx.fill(Path(roundedRect: r(46, 36.5, 37, 8), cornerRadius: 4 * k), with: .color(DS.sand50))
            // …and the line still being heard, slanted and grey.
            var partial = Path()
            partial.move(to: CGPoint(x: 48 * k, y: 55.5 * k))
            partial.addLine(to: CGPoint(x: 68 * k, y: 55.5 * k))
            partial.addLine(to: CGPoint(x: 66 * k, y: 63.5 * k))
            partial.addLine(to: CGPoint(x: 46 * k, y: 63.5 * k))
            partial.closeSubpath()
            ctx.fill(partial, with: .color(DS.vast500))
            ctx.fill(Path(roundedRect: r(72, 53, 3.6, 13), cornerRadius: 1.8 * k), with: .color(DS.fathom500))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Brand row in the sidebar, the same as RustleApp's and RustleLanguage's, with a "Transcript" chip.
struct BrandRow: View {
    var body: some View {
        HStack(spacing: 8) {
            BrandMark().frame(width: 25, height: 25)
            Text("Rustle").font(DS.ui(18, .bold)).tracking(-0.3)
            Text("Transcript")
                .font(DS.ui(11, .semibold))
                .foregroundColor(DS.fathom950)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(Color(hex: 0xE2F5F2)))
        }
        .padding(.horizontal, 5)
    }
}

/// The app icon: the mark as the macOS tile (824 pt on a 1024 canvas), like RustleApp's.
struct AppIconView: View {
    var body: some View {
        BrandMark()
            .frame(width: 824, height: 824)
            .shadow(color: .black.opacity(0.22), radius: 14, y: 8)
            .frame(width: 1024, height: 1024)
    }

    /// `RustleTranscript --icon <dir.iconset>`: writes every size iconutil needs.
    @MainActor
    static func writeIconset(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let renderer = ImageRenderer(content: AppIconView())
                renderer.scale = CGFloat(size * scale) / 1024
                guard let cg = renderer.cgImage else { continue }
                let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
                try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                    .write(to: dir.appendingPathComponent(name))
            }
        }
    }
}
