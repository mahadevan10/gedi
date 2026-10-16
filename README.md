# gedi

A small Thrissur guy who walks along the bottom of your MacBook screen and makes
passive-aggressive comments in Malayalam about what you're doing (mostly about YouTube
Shorts). Say **"gedeee"** and talk to him; he talks back.

Everything runs on the Mac:

| Part | What it uses |
|---|---|
| Brain | Qwen (`qwen3.5:9b` by default) served by Ollama |
| Ears | Apple SpeechAnalyzer, `ml-IN` (on-device; writes Malayalam in Latin letters) |
| Voice | Indic-Parler-TTS (AI4Bharat, voice "Harish"), plus clips you record yourself |
| Eyes | Frontmost app + the active Chrome/Safari tab (AppleScript) |

## Requirements

macOS 26+, Apple silicon, Command Line Tools (`xcode-select --install`), [Ollama](https://ollama.com/download)
running, [uv](https://docs.astral.sh/uv/) (`brew install uv`), and a Hugging Face account that has
accepted the terms of [ai4bharat/indic-parler-tts](https://huggingface.co/ai4bharat/indic-parler-tts).

## Setup

```bash
scripts/setup.sh                 # model, Parler TTS, persona, speech model (re-runnable)
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
  `followUpSeconds`, `ttsPython`, `ttsScript`, `ttsPort`.
- `clips/`: your own recordings. Put `shorts_again.m4a` there and add it to `clips/clips.json`:
  ```json
  [{"id": "shorts_again", "file": "shorts_again.m4a", "text": "എന്തൂട്ടാ ഗഡീ, പിന്നേം ഷോർട്സ്?", "use": "user is on YouTube Shorts or Reels"}]
  ```

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
