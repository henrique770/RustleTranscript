#!/usr/bin/env bash
# Installs Rustle Transcript on this Mac: checks the requirements, creates the local signing
# certificate, builds and signs the app, copies it to /Applications (or ~/Applications) and opens it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

say() { printf "\n==> %s\n" "$1"; }
fail() { printf "\nErro: %s\n" "$1" >&2; exit 1; }

say "Verificando requisitos"
MACOS="$(sw_vers -productVersion)"
[ "${MACOS%%.*}" -ge 26 ] || fail "o Rustle Transcript precisa do macOS 26 ou mais recente (SpeechAnalyzer); este Mac tem $MACOS."
command -v swift >/dev/null || fail "Swift não encontrado. Instale as ferramentas de linha de comando: xcode-select --install"
echo "macOS $MACOS · $(swift --version 2>/dev/null | head -1)"

say "Criando o certificado local de assinatura (mantém as permissões entre atualizações)"
"$ROOT/scripts/create-signing-cert.sh"

say "Compilando o app"
"$ROOT/scripts/build-app.sh"

say "Copiando para Aplicativos"
DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"
pkill -x RustleTranscript 2>/dev/null || true
rm -rf "$DEST/RustleTranscript.app"
cp -R "$ROOT/build/RustleTranscript.app" "$DEST/RustleTranscript.app"
echo "Instalado em $DEST/RustleTranscript.app"

say "Abrindo o Rustle Transcript"
open "$DEST/RustleTranscript.app"
cat <<MSG

Pronto! Clique em Iniciar transcrição (ou ⌥⌘T). O macOS vai pedir o Microfone e a Gravação de
áudio do sistema; o modelo de fala do idioma escolhido é baixado uma vez, na primeira transcrição.
MSG
