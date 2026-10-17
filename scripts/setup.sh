#!/usr/bin/env bash
# One-time setup. Safe to re-run: every step skips work that is already done.
#   1. Ollama model            (GEDI_MODEL, default qwen3.5:9b)
#   2. Piper TTS in a venv     ~/Library/Application Support/Gedi/piper-venv
#   3. Malayalam voice         ml_IN-arjun-medium
#   4. Piper smoke test
#   5. persona.md + clips/clips.json (only if missing, never overwritten)
#   6. Apple's ml-IN speech model
set -euo pipefail
cd "$(dirname "$0")/.."

SUPPORT="$HOME/Library/Application Support/Gedi"
VENV="$SUPPORT/piper-venv"
VOICES="$SUPPORT/voices"
VOICE=ml_IN-arjun-medium
MODEL="${GEDI_MODEL:-qwen3.5:9b}"
mkdir -p "$VOICES" "$SUPPORT/clips"

echo "==> 1/6 Ollama model $MODEL"
command -v ollama >/dev/null || { echo "ollama not installed: https://ollama.com/download"; exit 1; }
if ollama list | awk 'NR>1 {print $1}' | grep -qx "$MODEL"; then
  echo "    already pulled"
else
  ollama pull "$MODEL"
fi

echo "==> 2/6 Piper venv"
command -v uv >/dev/null || { echo "uv not installed: brew install uv"; exit 1; }
[ -x "$VENV/bin/python" ] || uv venv --python 3.12 "$VENV"
UV_HTTP_TIMEOUT=300 uv pip install --quiet --python "$VENV/bin/python" "piper-tts[http]==1.8.0"

echo "==> 3/6 Voice $VOICE"
if [ -f "$VOICES/$VOICE.onnx" ]; then
  echo "    already downloaded"
else
  "$VENV/bin/python" -m piper.download_voices --download-dir "$VOICES" "$VOICE"
fi

echo "==> 4/6 Piper smoke test"
SMOKE="$(mktemp -t gedi-smoke).wav"
echo "ഗഡീ" | "$VENV/bin/python" -m piper -m "$VOICE" --data-dir "$VOICES" -f "$SMOKE" 2>"$SMOKE.log" || true
if [ "$(stat -f%z "$SMOKE" 2>/dev/null || echo 0)" -lt 1000 ]; then
  cat "$SMOKE.log"
  echo "Piper produced no audio. If the error mentions /Users/runner/.../phontab, the venv path is"
  echo "too long for espeak-ng (~160 chars max for .../site-packages/piper/espeak-ng-data)."
  exit 1
fi
echo "    ok ($(stat -f%z "$SMOKE") bytes)"
rm -f "$SMOKE" "$SMOKE.log"

echo "==> 5/6 persona.md and clips/clips.json"
swift build --product gedi-debug >/dev/null
DEBUG_BIN="$(swift build --show-bin-path)/gedi-debug"
[ -f "$SUPPORT/persona.md" ] || "$DEBUG_BIN" persona > "$SUPPORT/persona.md"
[ -f "$SUPPORT/clips/clips.json" ] || echo "[]" > "$SUPPORT/clips/clips.json"
echo "    edit $SUPPORT/persona.md to change how Gedi talks"

echo "==> 6/6 Apple speech model (ml-IN)"
"$DEBUG_BIN" install-speech ml-IN

echo "Setup complete."
