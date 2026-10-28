#!/usr/bin/env bash
# Tears down everything docker-compose.yml created and frees the disk space:
#   - the postgres, pgadmin and metabase containers
#   - the project network
#   - the pgdata volume (the loaded imdb database, ~30 GB)
#   - the postgres, pgadmin4 and metabase images
#   - the raw .tsv files in data/ (~10 GB); composer.sh downloads them again
# Metabase's settings in metabase-data/ are kept, so composer.sh
# restores the admin account, database connection and dashboards.
#
# Usage: ./teardown.sh [--keep-data] [-y]
#   --keep-data  keep data/*.tsv (skips the re-download in composer.sh)
#   -y           skip the delete confirmation (the Docker Desktop question is still asked)
set -euo pipefail

cd "$(dirname "$0")"

delete_data=true
assume_yes=false
for arg in "$@"; do
  case "$arg" in
    --keep-data) delete_data=false ;;
    -y|--yes) assume_yes=true ;;
    *) echo "Unknown option: $arg" >&2; echo "Usage: $0 [--keep-data] [-y]" >&2; exit 1 ;;
  esac
done

# docker compose down needs the Docker engine; re-ask until it responds
while true; do
  read -r -p "Start Docker Desktop and wait until it shows as running, then type y or yes to continue: " reply
  case "$reply" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
  docker info >/dev/null 2>&1 && break
  echo "Docker isn't responding yet. Wait for Docker Desktop to finish starting."
done
echo "Docker is running."
echo

echo "This will permanently remove the project's containers, network, images"
echo "and the pgdata volume. The imdb database is deleted and must be"
echo "reloaded with create_and_load.sql afterwards."
if $delete_data; then
  echo "It will also delete the raw IMDb files in data/ (use --keep-data to keep them)."
fi
echo "Metabase settings in metabase-data/ are kept."

if ! $assume_yes; then
  read -r -p "Continue? [y/N] " reply
  case "$reply" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

echo
echo "Removing containers, network, volumes and images ..."
docker compose down --volumes --rmi all --remove-orphans
# Leftover tag from before Metabase was pinned to a version; --rmi all only
# removes the tags named in docker-compose.yml
docker image rm metabase/metabase:latest >/dev/null 2>&1 || true

if $delete_data; then
  echo "Deleting data/*.tsv ..."
  rm -f data/*.tsv data/*.tsv.gz
fi

echo
echo "Done. Docker disk usage now:"
docker system df
