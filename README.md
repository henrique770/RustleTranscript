# Rustle Transcript

Rustle Transcript is a macOS app that shows live captions on screen for everything you say and everything your Mac plays. It uses the same design as RustleApp and RustleLanguage: Figtree and EB Garamond fonts, the sand and vast palette, the sidebar, and the page card.

- **Live captions in any language.** Your microphone and the computer's audio (calls, videos, classes) become text in real time. By default the app uses Whisper (WhisperKit, large-v3 turbo or small), which detects the language of each sentence on its own: Portuguese, English, Spanish, or any other. If you pick a fixed language, it uses Apple's SpeechAnalyzer instead, which is lighter. Everything runs on your Mac. The end of a sentence that is still changing appears in italic grey and turns into normal text once it is final.
- **Only speech.** Sound descriptions such as `[Música]`, `(aplausos)` and `♪` are removed. A voice detector with an adaptive noise floor and a confidence filter keep Whisper from inventing phrases over silence or noise (such as "Thank you." or "Legendas pela comunidade Amara.org").
- **Echo.** When the mic picks up the speakers, mic phrases that repeat what the computer just said are dropped. Apple's voice processing is not used because it silences the system-audio tap.
- **Floating caption.** It stays on top of every app, including full-screen ones, and lets clicks pass through. Press **⌥⌘E** to drag it anywhere on screen and resize it from the sides. Its position and width are remembered.
- **Customization (Legenda page).** You can change the font, size, weight, alignment, text color and shadow, the style of the words still being recognized, the background (color, opacity, blur, corner radius, padding), the number of visible lines, how long the caption stays after silence, and the speaker labels. There are 5 ready-made styles.
- **History.** Every session is saved, grouped by day, and searchable. You can rename a session, copy it, export it as `.txt` or `.srt`, and delete it.

## Shortcuts

| Shortcut | Action |
|---|---|
| ⌥⌘T | Start or stop the transcription |
| ⌥⌘E | Position the caption (drag and resize) |
| ⌥⌘L | Show or hide the caption |

## Installation

Requirements: macOS 26 or later and the Swift command-line tools. On first use, the Whisper model is downloaded once (about 630 MB, or 220 MB for "Rápido") into `~/Library/Application Support/RustleTranscript/Models`.

```bash
./scripts/install.sh
```

| Script | What it does |
|---|---|
| `scripts/build-app.sh` | Builds `build/RustleTranscript.app` |
| `scripts/make-icon.sh` | Regenerates `AppIcon.icns` from the logo in `Brand.swift` |
| `RustleTranscript --snapshot <dir>` | Renders every screen to PNG using sample data |
| `open -n build/RustleTranscript.app --args --probe-live <s> [--system-only] [--no-echo]` | Diagnostics: runs a session for `<s>` seconds and logs every result to `~/Library/Logs/RustleTranscript.log` |

## Architecture

```
client-macos/Sources/RustleTranscript
  Audio.swift           microphone (AVAudioEngine + echo cancellation) and system audio (Core Audio process tap)
  Whisper.swift         Whisper on a sliding window per source (any language), voice detector, speech/echo filters
  Transcription.swift   Apple SpeechAnalyzer engine (fixed language) and the session controller
  CaptionOverlay.swift  floating panel, caption rendering (AppKit, italic via obliqueness), edit mode
  AppModel.swift        state, history (~/Library/Application Support/RustleTranscript), live caption
  MainWindow / HistoryView / CaptionStyleView / SettingsView   the hub's pages
  Brand.swift           logo and app icon
```

The next step from the plan is refining the text with an LLM such as DeepSeek. Final segments would go to an OpenAI-compatible endpoint, and the corrected text would replace the raw text in the caption and in the history.
