#!/usr/bin/env bash
# Downloads the 7 IMDb non-commercial dataset files this project needs
# and unpacks them into data/, next to this script.
# Source: https://datasets.imdbws.com/ (see https://developer.imdb.com/non-commercial-datasets/)
set -euo pipefail

mkdir -p "$(dirname "$0")/data"
cd "$(dirname "$0")/data"

files=(
  name.basics
  title.akas
  title.basics
  title.crew
  title.episode
  title.principals
  title.ratings
)

i=0
for f in "${files[@]}"; do
  i=$((i + 1))
  if [ -f "${f}.tsv" ]; then
    echo "[${i}/${#files[@]}] ${f}.tsv already present, skipping"
    continue
  fi
  echo "[${i}/${#files[@]}] Downloading ${f}.tsv.gz ..."
  # --progress-bar draws a #### bar with a percentage; -S still prints errors
  curl --progress-bar -SL "https://datasets.imdbws.com/${f}.tsv.gz" -o "${f}.tsv.gz"
  echo "Unzipping ${f}.tsv.gz ..."
  gunzip "${f}.tsv.gz"
done

echo
echo "Done. Files in data/:"
ls -lh ./*.tsv
