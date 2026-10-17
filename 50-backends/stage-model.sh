#!/usr/bin/env bash
# I30LTZ Recovery OS - stage qwen2.5:7b for USB/persistence
# Version: 0.3.0-alpha | Date: 2026-10-05
# Run: bash /mnt/recoverybuild/50-backends/stage-model.sh
# Copies ONLY the qwen2.5:7b manifest + blobs from your local Ollama store
# into /mnt/recoverybuild/50-backends/models/ (consumed by make-persistent-usb.sh)
# -------------------------------------------------------
set -e
MODEL_NAME="${MODEL_NAME:-qwen2.5}"
MODEL_TAG="${MODEL_TAG:-7b}"
OUT="/mnt/recoverybuild/50-backends/models"

SRC=""
for d in "${OLLAMA_MODELS:-}" /usr/share/ollama/.ollama/models "$HOME/.ollama/models" /var/lib/ollama/models; do
  [ -n "$d" ] && [ -d "$d/manifests" ] && SRC="$d" && break
done

if [ -z "$SRC" ] || [ ! -f "$SRC/manifests/registry.ollama.ai/library/$MODEL_NAME/$MODEL_TAG" ]; then
  echo "[STAGE] ${MODEL_NAME}:${MODEL_TAG} not found locally - pulling..."
  ollama pull "${MODEL_NAME}:${MODEL_TAG}"
  for d in "${OLLAMA_MODELS:-}" /usr/share/ollama/.ollama/models "$HOME/.ollama/models" /var/lib/ollama/models; do
    [ -n "$d" ] && [ -f "$d/manifests/registry.ollama.ai/library/$MODEL_NAME/$MODEL_TAG" ] && SRC="$d" && break
  done
fi
[ -n "$SRC" ] || { echo "[STAGE] ERROR: cannot locate Ollama model store"; exit 1; }

MAN="manifests/registry.ollama.ai/library/$MODEL_NAME/$MODEL_TAG"
mkdir -p "$OUT/$(dirname "$MAN")" "$OUT/blobs"
cp "$SRC/$MAN" "$OUT/$MAN"

python3 - "$SRC" "$OUT" "$MAN" <<'PY'
import json, shutil, sys, os
src, out, man = sys.argv[1:4]
m = json.load(open(os.path.join(src, man)))
digests = [m["config"]["digest"]] + [l["digest"] for l in m["layers"]]
for dg in digests:
    f = "sha256-" + dg.split(":")[1]
    s, d = os.path.join(src, "blobs", f), os.path.join(out, "blobs", f)
    if os.path.exists(d) and os.path.getsize(d) == os.path.getsize(s):
        print("  have", f[:19]); continue
    print("  copy", f[:19], round(os.path.getsize(s)/1e6), "MB")
    shutil.copyfile(s, d)
PY
echo "[STAGE] done: $(du -sh "$OUT" | cut -f1) staged at $OUT"
