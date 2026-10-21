import AppKit
import SwiftUI

struct SettingsPage: View {
    @ObservedObject var model: AppModel
    @State private var modelInstalled: Bool?
    @State private var downloading: Double?
    @State private var downloadError: String?
    @State private var confirmClear = false

    var body: some View {
        PageScroll {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(title: "Configurações",
                           description: "Idioma, fontes de áudio, permissões e atalhos. O reconhecimento de fala roda neste Mac: o áudio não sai daqui.") { EmptyView() }

                if model.isRunning {
                    Label("Mudanças de idioma e de fontes valem a partir da próxima transcrição.", systemImage: "info.circle")
                        .font(DS.ui(14)).foregroundColor(DS.neutral600)
                }

                SettingsCard {
                    CardTitle(icon: "waveform", title: "Reconhecimento de fala")
                    SettingRow("Idioma", detail: model.settings.usesWhisper
                               ? "O Whisper detecta sozinho o idioma de cada frase: português, inglês, espanhol, qualquer um."
                               : "Um idioma fixo usa o reconhecimento da Apple: mais leve, mas só entende esse idioma.") {
                        Picker("", selection: $model.settings.language) {
                            ForEach(AppSettings.languages, id: \.id) { Text($0.name).tag($0.id) }
                        }
                        .labelsHidden().frame(width: 210)
                    }
                    if model.settings.usesWhisper {
                        SettingRow("Modelo do Whisper", detail: WhisperModel.variants.first { $0.id == model.settings.whisperModel }?.detail) {
                            Picker("", selection: $model.settings.whisperModel) {
                                ForEach(WhisperModel.variants) { Text($0.name).tag($0.id) }
                            }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                        }
                    }
                    SettingRow("Modelo de fala", detail: modelDetail) {
                        if let downloading {
                            ProgressView(value: downloading).frame(width: 140)
                        } else if modelInstalled == false {
                            Button("Baixar agora", action: download).buttonStyle(SecondaryButtonStyle())
                        } else if modelInstalled == true {
                            Label("Instalado", systemImage: "checkmark.circle.fill")
                                .font(DS.ui(14, DS.w550)).foregroundColor(DS.success500)
                        }
                    }
                }

                SettingsCard {
                    CardTitle(icon: "speaker.wave.2", title: "Fontes de áudio")
                    SettingRow("Microfone", detail: "A sua voz.") {
                        Toggle("", isOn: $model.settings.captureMic).toggleStyle(.switch).labelsHidden()
                    }
                    SettingRow("Áudio do computador", detail: "Chamadas, vídeos, aulas: tudo o que toca no Mac.") {
                        Toggle("", isOn: $model.settings.captureSystem).toggleStyle(.switch).labelsHidden()
                    }
                    SettingRow("Ignorar o eco dos alto-falantes", detail: "Com as duas fontes ligadas, o microfone descarta frases que repetem o que o computador acabou de dizer. Com fone de ouvido, pode desligar.") {
                        Toggle("", isOn: $model.settings.echoCancellation).toggleStyle(.switch).labelsHidden()
                    }
                    .disabled(!model.settings.captureMic)
                    SettingRow("Mostrar a legenda na tela", detail: "Você também pode ocultar e mostrar com ⌥⌘L.") {
                        Toggle("", isOn: $model.settings.showOverlay).toggleStyle(.switch).labelsHidden()
                    }
                }

                SettingsCard {
                    CardTitle(icon: "lock", title: "Permissões")
                    SettingRow("Microfone", detail: model.permissions.microphone ? "Permitido." : "Necessário para transcrever a sua voz.") {
                        if model.permissions.microphone {
                            Label("Permitido", systemImage: "checkmark.circle.fill").font(DS.ui(14, DS.w550)).foregroundColor(DS.success500)
                        } else {
                            Button("Permitir") { model.requestPermissions() }.buttonStyle(PrimaryButtonStyle())
                        }
                    }
                    SettingRow("Gravação de áudio do sistema", detail: "O macOS pede esta permissão na primeira vez que você inicia com o áudio do computador ligado. Para revisar, abra Privacidade e Segurança.") {
                        Button("Abrir Ajustes") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }

                SettingsCard {
                    CardTitle(icon: "keyboard", title: "Atalhos")
                    ForEach(Hotkeys.all, id: \.label) { s in
                        SettingRow(s.title) { KeyCaps(label: s.label) }
                    }
                }

                SettingsCard {
                    CardTitle(icon: "clock.arrow.circlepath", title: "Histórico")
                    SettingRow("Transcrições salvas", detail: "\(model.sessions.count) sessões, \(model.totalWords.formatted()) palavras. Ficam em ~/Library/Application Support/RustleTranscript.") {
                        HStack(spacing: 8) {
                            Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([AppModel.sessionsURL]) }
                                .buttonStyle(SecondaryButtonStyle())
                            Button("Apagar tudo") { confirmClear = true }
                                .buttonStyle(SecondaryButtonStyle())
                                .disabled(model.sessions.isEmpty)
                        }
                    }
                }
            }
        }
        .task(id: model.settings.language + model.settings.whisperModel) { await checkModel() }
        .alert("Apagar todo o histórico?", isPresented: $confirmClear) {
            Button("Apagar", role: .destructive) { model.deleteAll() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("As \(model.sessions.count) transcrições salvas serão removidas deste Mac.")
        }
    }

    private var modelDetail: String {
        if let downloadError { return downloadError }
        switch modelInstalled {
        case .some(true): return "Instalado neste Mac. Funciona sem internet."
        case .some(false) where model.settings.usesWhisper: return "É baixado uma vez, na primeira transcrição. Tudo roda neste Mac."
        case .some(false): return "É baixado uma vez (algumas centenas de MB) na primeira transcrição neste idioma."
        case .none: return "Verificando…"
        }
    }

    private func checkModel() async {
        modelInstalled = nil
        downloadError = nil
        if model.settings.usesWhisper {
            modelInstalled = WhisperModel.isDownloaded(model.settings.whisperModel)
        } else {
            modelInstalled = await LiveTranscriber.isInstalled(language: model.settings.language)
        }
    }

    private func download() {
        downloading = 0
        downloadError = nil
        let settings = model.settings
        Task {
            do {
                if settings.usesWhisper {
                    try await WhisperModel.shared.load(settings.whisperModel,
                                                       progress: { p in Task { @MainActor in downloading = p } },
                                                       status: { _ in Task { @MainActor in downloading = 1 } })
                } else {
                    _ = try await LiveTranscriber.prepare(language: settings.language) { p in downloading = p }
                }
                modelInstalled = true
            } catch {
                downloadError = error.localizedDescription
            }
            downloading = nil
        }
    }
}

private struct KeyCaps: View {
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(label), id: \.self) { ch in
                Text(String(ch)).font(DS.ui(13, .semibold))
                    .frame(minWidth: 24, minHeight: 24)
                    .background(RoundedRectangle(cornerRadius: 6).fill(DS.card))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.border, lineWidth: 1))
            }
        }
    }
}
