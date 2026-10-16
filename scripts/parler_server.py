"""Indic-Parler-TTS behind Piper's HTTP API: GET /info, POST /synthesize {"text": ...} -> WAV.

usage: parler_server.py [--port 5917] [--dtype float16|float32]
"""
import argparse, io, json, time
from http.server import BaseHTTPRequestHandler, HTTPServer

import soundfile as sf
import torch
from transformers import AutoTokenizer
from parler_tts import ParlerTTSForConditionalGeneration

REPO = "ai4bharat/indic-parler-tts"
# Harish is one of the model's Malayalam speakers. Slow, stretched delivery suits a Thrissur drawl.
VOICE = ("Harish speaks slowly in a relaxed, playful and teasing tone, stretching out some words, "
         "with a close-sounding recording and very clear audio.")

ap = argparse.ArgumentParser()
ap.add_argument("--host", default="127.0.0.1")
ap.add_argument("--port", type=int, default=5917)
ap.add_argument("--dtype", default="float16", choices=["float16", "float32"])
ap.add_argument("--voice", default=VOICE)
args = ap.parse_args()

dev = "mps" if torch.backends.mps.is_available() else "cpu"
dtype = getattr(torch, args.dtype) if dev == "mps" else torch.float32
model = ParlerTTSForConditionalGeneration.from_pretrained(REPO, torch_dtype=dtype).to(dev)
tok = AutoTokenizer.from_pretrained(REPO)
desc = AutoTokenizer.from_pretrained(model.config.text_encoder._name_or_path)(args.voice, return_tensors="pt").to(dev)


def synthesize(text: str) -> bytes:
    p = tok(text, return_tensors="pt").to(dev)
    with torch.no_grad():
        audio = model.generate(input_ids=desc.input_ids, attention_mask=desc.attention_mask,
                               prompt_input_ids=p.input_ids, prompt_attention_mask=p.attention_mask)
    buf = io.BytesIO()
    sf.write(buf, audio.to(torch.float32).cpu().numpy().squeeze(), model.config.sampling_rate,
             format="WAV", subtype="PCM_16")
    return buf.getvalue()


t = time.time()
synthesize("ഗഡീ")  # warm-up: the first generate on MPS is much slower
print(f"ready on {dev}/{dtype} (warm-up {time.time() - t:.1f}s)", flush=True)


class Handler(BaseHTTPRequestHandler):
    def _send(self, status: int, body: bytes, kind: str):
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/info":
            self._send(200, json.dumps({"model": REPO, "device": dev}).encode(), "application/json")
        else:
            self._send(404, b"not found", "text/plain")

    def do_POST(self):
        if self.path != "/synthesize":
            return self._send(404, b"not found", "text/plain")
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
            text = str(body["text"]).strip()
            if not text:
                return self._send(400, b"empty text", "text/plain")
            t = time.time()
            wav = synthesize(text)
            print(f"{time.time() - t:.1f}s  {text}", flush=True)
            self._send(200, wav, "audio/wav")
        except Exception as e:
            self._send(500, repr(e).encode(), "text/plain")


HTTPServer((args.host, args.port), Handler).serve_forever()
