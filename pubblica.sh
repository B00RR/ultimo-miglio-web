#!/usr/bin/env bash
# Uso: ./pubblica.sh <cartella_build_webgl>   (contiene Build/ e opzionalmente TemplateData/, StreamingAssets/)
# Opzioni env: NO_PUSH=1 (solo prepara, niente commit/push/verifica), WAIT=secondi max attesa deploy (default 300)
set -euo pipefail
SRC="${1:?Uso: $0 <cartella_build>}"; SRC="$(cd "$SRC" && pwd)"
REPO="$(cd "$(dirname "$0")" && pwd)"; cd "$REPO"
URL="https://b00rr.github.io/ultimo-miglio-web"
[ -d "$SRC/Build" ] || { echo "ERRORE: $SRC/Build non trovata"; exit 1; }
B="$SRC/Build"
LOADER=$(ls "$B" | grep -E '\.loader\.js$' | head -1 || true)
[ -n "$LOADER" ] || { echo "ERRORE: nessun *.loader.js in Build/"; exit 1; }
NAME="${LOADER%.loader.js}"
pick(){ for s in "$@"; do [ -f "$B/$NAME$s" ] && { echo "$NAME$s"; return; }; done; echo ""; }
DATA=$(pick .data .data.unityweb .data.br .data.gz)
FW=$(pick .framework.js .framework.js.unityweb .framework.js.br .framework.js.gz)
WASM=$(pick .wasm .wasm.unityweb .wasm.br .wasm.gz)
for f in DATA FW WASM; do [ -n "${!f}" ] || { echo "ERRORE: file $f mancante per $NAME"; exit 1; }; done
# .br/.gz: GitHub Pages non invia Content-Encoding -> serve il Decompression Fallback (che produce .unityweb)
if ls "$B" | grep -qE '\.(br|gz)$'; then
  echo "ERRORE: trovati file .br/.gz. GitHub Pages non imposta Content-Encoding."
  echo "Ricompila con Compression Format = Disabled, oppure Gzip/Brotli + 'Decompression Fallback' attivo (file .unityweb)."
  exit 1
fi
echo "Build: $NAME | $DATA | $FW | $WASM"
rm -rf Build TemplateData StreamingAssets
cp -r "$B" Build
[ -d "$SRC/TemplateData" ] && cp -r "$SRC/TemplateData" TemplateData
[ -d "$SRC/StreamingAssets" ] && cp -r "$SRC/StreamingAssets" StreamingAssets
# file >100MB rifiutati da GitHub
big=$(find Build StreamingAssets -type f -size +95M 2>/dev/null || true)
[ -z "$big" ] || { echo "ERRORE: file troppo grandi per GitHub (>100MB): $big"; exit 1; }
sed -e "s|^var LOADER_FILE = .*|var LOADER_FILE = \"$LOADER\";|" \
    -e "s|^var DATA_FILE = .*|var DATA_FILE = \"$DATA\";|" \
    -e "s|^var FRAMEWORK_FILE = .*|var FRAMEWORK_FILE = \"$FW\";|" \
    -e "s|^var CODE_FILE = .*|var CODE_FILE = \"$WASM\";|" index_unity.html > index.html
touch .nojekyll
[ "${NO_PUSH:-0}" = 1 ] && { echo "NO_PUSH=1: preparato, nessun commit."; exit 0; }
git add -A
git commit -m "Pubblica build WebGL $NAME ($(date '+%Y-%m-%d %H:%M'))" || echo "Niente da committare"
git push origin HEAD
SHA=$(git rev-parse --short HEAD)
echo "Attendo deploy GitHub Pages..."
end=$(( $(date +%s) + ${WAIT:-300} )); ok=0
while [ "$(date +%s)" -lt "$end" ]; do
  if curl -fsS "$URL/?v=$SHA" 2>/dev/null | grep -q "$LOADER"; then ok=1; break; fi
  sleep 10
done
[ $ok = 1 ] || { echo "ERRORE: index.html nuovo non visibile dopo ${WAIT:-300}s"; exit 1; }
fail=0
for f in "" "Build/$LOADER" "Build/$FW" "Build/$DATA" "Build/$WASM"; do
  r=$(curl -sI -o /dev/null -w '%{http_code} %{content_type}' "$URL/$f")
  echo "$r  $URL/$f"
  case "$r" in 200*) ;; *) fail=1;; esac
  case "$f" in *.wasm) echo "$r" | grep -q 'application/wasm' || echo "  AVVISO: mime wasm non application/wasm (Unity usa fallback più lento)";; esac
done
[ $fail = 0 ] && echo "OK: $URL" || { echo "ERRORE: alcuni file non rispondono 200"; exit 1; }
