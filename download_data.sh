#!/usr/bin/env bash
# Downloads the 7 IMDb non-commercial dataset files this project needs
# and unpacks them into data/, next to this script.
# Source: https://datasets.imdbws.com/ (see https://developer.imdb.com/non-commercial-datasets/)
set -euo pipefail

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

for f in "${files[@]}"; do
  if [ -f "${f}.tsv" ]; then
    echo "${f}.tsv already present, skipping"
    continue
  fi
  echo "Downloading ${f}.tsv.gz ..."
  curl -sSL "https://datasets.imdbws.com/${f}.tsv.gz" -o "${f}.tsv.gz"
  echo "Unzipping ${f}.tsv.gz ..."
  gunzip "${f}.tsv.gz"
done

echo
echo "Done. Files in data/:"
ls -lh ./*.tsv
