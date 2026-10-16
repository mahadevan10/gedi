#!/usr/bin/env bash
# One-time setup. Safe to re-run: every step skips work that is already done.
#   1. Ollama model            (GEDI_MODEL, default qwen3.5:9b)
#   2. Indic-Parler-TTS in a venv  ~/Library/Application Support/Gedi/tts-venv
#   3. Model download (gated: needs a Hugging Face login with access granted)
#   4. parler_server.py copied next to it
#   5. persona.md + clips/clips.json (only if missing, never overwritten)
#   6. Apple's ml-IN speech model
set -euo pipefail
cd "$(dirname "$0")/.."

SUPPORT="$HOME/Library/Application Support/Gedi"
VENV="$SUPPORT/tts-venv"
MODEL="${GEDI_MODEL:-qwen3.5:9b}"
mkdir -p "$SUPPORT/clips"

echo "==> 1/6 Ollama model $MODEL"
command -v ollama >/dev/null || { echo "ollama not installed: https://ollama.com/download"; exit 1; }
if ollama list | awk 'NR>1 {print $1}' | grep -qx "$MODEL"; then
  echo "    already pulled"
else
  ollama pull "$MODEL"
fi

echo "==> 2/6 Parler TTS venv"
command -v uv >/dev/null || { echo "uv not installed: brew install uv"; exit 1; }
[ -x "$VENV/bin/python" ] || uv venv --python 3.12 "$VENV"
UV_HTTP_TIMEOUT=300 uv pip install --quiet --python "$VENV/bin/python" torch soundfile \
  "parler-tts @ git+https://github.com/huggingface/parler-tts.git"

echo "==> 3/6 Indic-Parler-TTS model (about 3.7 GB)"
if ! "$VENV/bin/hf" download ai4bharat/indic-parler-tts >/dev/null; then
  echo "Download failed. The model is gated:"
  echo "  1. accept the terms at https://huggingface.co/ai4bharat/indic-parler-tts"
  echo "  2. run in Terminal: \"$VENV/bin/hf\" auth login"
  exit 1
fi
echo "    ok"

echo "==> 4/6 TTS server script"
cp scripts/parler_server.py "$SUPPORT/parler_server.py"
echo "    copied to $SUPPORT/parler_server.py"

echo "==> 5/6 persona.md and clips/clips.json"
swift build --product gedi-debug >/dev/null
DEBUG_BIN="$(swift build --show-bin-path)/gedi-debug"
[ -f "$SUPPORT/persona.md" ] || "$DEBUG_BIN" persona > "$SUPPORT/persona.md"
[ -f "$SUPPORT/clips/clips.json" ] || echo "[]" > "$SUPPORT/clips/clips.json"
echo "    edit $SUPPORT/persona.md to change how Gedi talks"

echo "==> 6/6 Apple speech model (ml-IN)"
"$DEBUG_BIN" install-speech ml-IN

echo "Setup complete."
