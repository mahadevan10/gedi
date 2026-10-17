# gedi

A small Thrissur guy who walks along the bottom of your MacBook screen and makes
passive-aggressive comments in Malayalam about what you're doing (mostly about YouTube
Shorts). Say **"gedeee"** and talk to him; he talks back.

Everything runs on the Mac except the brain:

| Part | What it uses |
|---|---|
| Brain | Gemini Flash (`gemini-flash-latest`) over Google's OpenAI-compatible API; Ollama optional |
| Ears | Apple SpeechAnalyzer, `ml-IN` (on-device; writes Malayalam in Latin letters) |
| Voice | Piper TTS, `ml_IN-arjun-medium`, plus clips you record yourself |
| Eyes | Frontmost app + the active Chrome/Safari tab (AppleScript) |

## Requirements

macOS 26+, Apple silicon, Command Line Tools (`xcode-select --install`), a Gemini API key,
[Ollama](https://ollama.com/download) (setup still pulls the local fallback model), and [uv](https://docs.astral.sh/uv/) (`brew install uv`).

## Setup

```bash
scripts/setup.sh                 # model, Piper + voice, persona, speech model (re-runnable)
scripts/bundle.sh                # builds build/Gedi.app
open build/Gedi.app
```

The first launch asks for the microphone, and the first time you're in Chrome or Safari
it asks to control the browser. Quit from the **ഗഡി** menu-bar item.

## Customising

Everything lives in `~/Library/Application Support/Gedi/`:

- `persona.md`: who Gedi is and how he talks. Edit the example lines; they matter most.
- `config.json`: optional overrides, e.g.
  `{"model": "qwen3.5:4b", "commentIntervalSeconds": 60, "wakeWords": ["gadi", "gadhi", "gade", "gedi"]}`.
  Keys: `model`, `ollamaURL`, `commentIntervalSeconds`, `localeID`, `wakeWords`, `silenceSeconds`,
  `followUpSeconds`, `piperPython`, `piperVoice`, `piperDataDir`, `piperPort`, `chatURL`, `chatAPIKey`, `fallbacks`.
  The brain is Gemini Flash (screen activity leaves your Mac): put your key in `{"chatAPIKey": "…"}`
  (free at aistudio.google.com; free tier is 5 requests/min). For local Ollama instead:
  `{"chatURL": null, "model": "qwen3.5:9b"}`.
  `fallbacks` lists OpenAI-compatible backups tried in order when the main brain fails (e.g. a 429):
  `{"fallbacks": [{"chatURL": "https://api.groq.com/openai/v1/", "chatAPIKey": "…", "model": "…"}]}`
  (optional `reasoningEffort` per entry). Failures show in `/usr/bin/log stream --predicate 'category == "brain"'`.
- `clips/`: your own recordings. Put `shorts_again.m4a` there and add it to `clips/clips.json`:
  ```json
  [{"id": "shorts_again", "file": "shorts_again.m4a", "text": "എന്തൂട്ടാ ഗഡീ, പിന്നേം ഷോർട്സ്?", "use": "user is on YouTube Shorts or Reels"}]
  ```
  `.build/debug/gedi-debug record` walks the list and records each line that has no audio yet
  (`record <id>` re-records one).

Restart Gedi after changing any of these.

## Development

```bash
scripts/test.sh                          # unit tests (GediCore)
swift build --product gedi-debug
.build/debug/gedi-debug                  # lists commands: say, transcribe, comment, reply, activity, listen…
.build/debug/Gedi --snapshot /tmp/s.png  # render the character + bubble to a PNG
/usr/bin/log stream --predicate 'subsystem == "com.mahadevan.gedi"' --level info   # app logs
```

`GEDI_CONFIG=/path/to/config.json` points both binaries at a different config file.
