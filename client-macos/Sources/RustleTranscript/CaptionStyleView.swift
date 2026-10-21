import AppKit
import SwiftUI

/// Legenda: how the on-screen caption looks, with a live preview over a mock desktop.
/// Every change applies to the overlay right away.
struct CaptionStylePage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        PageScroll(maxWidth: 860) {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(title: "Legenda",
                           description: "Escolha fonte, tamanho, cores e fundo. As mudanças aparecem na hora, aqui e na tela.") {
                    HStack(spacing: 8) {
                        Button { model.toggleEditOverlay() } label: {
                            Label(model.editingOverlay ? "Concluir" : "Posicionar na tela", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }

                StylePreview(style: model.style, speakers: model.settings.enabledSources.count > 1)

                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "Estilos prontos")
                    HStack(spacing: 8) {
                        ForEach(CaptionStyle.presets) { p in
                            PillButton(title: p.name, active: model.style == p.style) {
                                withAnimation(.easeOut(duration: 0.2)) { model.style = p.style }
                            }
                        }
                    }
                }

                SettingsCard {
                    CardTitle(icon: "textformat", title: "Texto")
                    SettingRow("Fonte") {
                        Picker("", selection: $model.style.fontName) {
                            ForEach(CaptionStyle.fonts, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden().frame(width: 200)
                    }
                    SettingRow("Tamanho", value: "\(Int(model.style.fontSize)) pt") {
                        Slider(value: $model.style.fontSize, in: 16...96, step: 1).frame(width: 260)
                    }
                    SettingRow("Peso") {
                        Picker("", selection: $model.style.weight) {
                            ForEach(CaptionStyle.Weight.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 320)
                    }
                    SettingRow("Alinhamento") {
                        Picker("", selection: $model.style.alignment) {
                            ForEach(CaptionStyle.Align.allCases) { Image(systemName: $0.icon).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 140)
                    }
                    SettingRow("Cor do texto") { ColorWell(color: $model.style.textColor) }
                    SettingRow("Sombra no texto", detail: "Ajuda a ler sobre fundos claros ou sem fundo.") {
                        Toggle("", isOn: $model.style.shadow).toggleStyle(.switch).labelsHidden()
                    }
                }

                SettingsCard {
                    CardTitle(icon: "italic", title: "Palavras sendo reconhecidas")
                    Text("O final da frase muda enquanto o reconhecimento ainda decide o que ouviu. Ele aparece neste estilo até se firmar.")
                        .font(DS.ui(14)).foregroundColor(DS.neutral600).fixedSize(horizontal: false, vertical: true)
                    SettingRow("Cor") { ColorWell(color: $model.style.partialColor) }
                    SettingRow("Itálico") { Toggle("", isOn: $model.style.partialItalic).toggleStyle(.switch).labelsHidden() }
                }

                SettingsCard {
                    CardTitle(icon: "rectangle.fill", title: "Fundo")
                    SettingRow("Cor do fundo") { ColorWell(color: $model.style.backgroundColor) }
                    SettingRow("Opacidade", value: "\(Int(model.style.backgroundOpacity * 100))%") {
                        Slider(value: $model.style.backgroundOpacity, in: 0...1).frame(width: 260)
                    }
                    SettingRow("Desfoque", detail: "Desfoca o que está atrás da legenda, como um vidro fosco.") {
                        Toggle("", isOn: $model.style.blur).toggleStyle(.switch).labelsHidden()
                    }
                    SettingRow("Arredondamento", value: "\(Int(model.style.cornerRadius)) pt") {
                        Slider(value: $model.style.cornerRadius, in: 0...40, step: 1).frame(width: 260)
                    }
                    SettingRow("Margem interna", value: "\(Int(model.style.padding)) pt") {
                        Slider(value: $model.style.padding, in: 4...40, step: 1).frame(width: 260)
                    }
                }

                SettingsCard {
                    CardTitle(icon: "slider.horizontal.3", title: "Comportamento")
                    SettingRow("Linhas visíveis", value: "\(model.style.maxLines)") {
                        Stepper("", value: $model.style.maxLines, in: 1...6).labelsHidden()
                    }
                    SettingRow("Sumir depois de", value: model.style.fadeAfter == 0 ? "nunca" : "\(Int(model.style.fadeAfter)) s de silêncio") {
                        Slider(value: $model.style.fadeAfter, in: 0...20, step: 1).frame(width: 260)
                    }
                    SettingRow("Mostrar quem fala", detail: "Com as duas fontes ligadas, marca “Você” e “Computador”.") {
                        Toggle("", isOn: $model.style.showSpeaker).toggleStyle(.switch).labelsHidden()
                    }
                    if model.style.showSpeaker {
                        SettingRow("Cor de “Você”") { ColorWell(color: $model.style.micColor) }
                        SettingRow("Cor de “Computador”") { ColorWell(color: $model.style.systemColor) }
                    }
                }

                HStack {
                    Button("Restaurar o padrão") { withAnimation { model.style = CaptionStyle() } }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Centralizar embaixo da tela") { model.resetOverlayPosition() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }
}

/// The caption over a mock desktop (dark app windows, like the reference screenshot).
private struct StylePreview: View {
    let style: CaptionStyle
    let speakers: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .bottom) {
                MockDesktop()
                CaptionBox(style: style,
                           text: CaptionRenderer.attributed(entries: CaptionFeed.sample.entries, volatile: CaptionFeed.sample.volatile,
                                                            style: style, speakers: speakers),
                           width: w - 64, blending: .withinWindow)
                    .padding(.bottom, 28)
            }
            .frame(width: w, height: geo.size.height)
        }
        .frame(height: max(260, CaptionRenderer.maxBoxHeight(style) + 120))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(DS.border, lineWidth: 1))
    }
}

private struct MockDesktop: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(hex: 0x3A3A38), Color(hex: 0x1F1F1E)], startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(0..<9, id: \.self) { i in
                        Capsule().fill(Color.white.opacity(i % 4 == 0 ? 0.35 : 0.16))
                            .frame(width: [220, 300, 260, 180, 280, 240, 310, 200, 260][i], height: 7)
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x262625)))
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(0..<4, id: \.self) { i in
                        HStack(spacing: 10) {
                            Circle().fill([DS.fathom500, DS.glow300, DS.dawn700, DS.flare400][i].opacity(0.7)).frame(width: 22, height: 22)
                            VStack(alignment: .leading, spacing: 5) {
                                Capsule().fill(Color.white.opacity(0.3)).frame(width: 70, height: 6)
                                Capsule().fill(Color.white.opacity(0.14)).frame(width: 140, height: 6)
                            }
                        }
                    }
                }
                .padding(18)
                .frame(width: 230)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x2B2B2A)))
            }
            .padding(16)
        }
    }
}

// MARK: - Shared form pieces

struct CardTitle: View {
    let icon: String
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(DS.foregroundTertiary)
            Text(title).font(DS.ui(17, .semibold))
        }
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    var value: String?
    @ViewBuilder var control: Control

    init(_ title: String, detail: String? = nil, value: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.value = value
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title).font(DS.ui(15, DS.w550))
                    if let value { Text(value).font(DS.ui(13).monospacedDigit()).foregroundColor(DS.foregroundTertiary) }
                }
                if let detail {
                    Text(detail).font(DS.ui(13)).foregroundColor(DS.neutral600).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
    }
}

/// A color swatch that opens the system color picker (with opacity).
struct ColorWell: View {
    @Binding var color: RGBA
    var body: some View {
        ColorPicker("", selection: Binding(get: { color.color }, set: { color = RGBA($0) }), supportsOpacity: true)
            .labelsHidden()
    }
}
