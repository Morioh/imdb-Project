#!/usr/bin/env bash
# Rebuilds everything teardown.sh removed:
#   1. downloads any missing IMDb .tsv files into data/ (download_data.sh)
#   2. pulls the images and starts postgres, pgadmin and metabase
#   3. waits for Postgres to accept connections
#   4. creates and loads the imdb database with create_and_load.sql
# If imdb is already loaded, step 4 is skipped unless --reload is given.
# The load output is saved to load.log.
#
# Usage: ./composer.sh [--reload]
#   --reload  rebuild the imdb database even if it is already loaded
set -euo pipefail

cd "$(dirname "$0")"

reload=false
for arg in "$@"; do
  case "$arg" in
    --reload) reload=true ;;
    *) echo "Unknown option: $arg" >&2; echo "Usage: $0 [--reload]" >&2; exit 1 ;;
  esac
done

# Docker must be up before the ~10 GB download; re-ask until it responds
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

echo "Step 1/4: checking raw data files ..."
./download_data.sh

echo
echo "Step 2/4: starting containers ..."
docker compose up -d

echo
echo "Step 3/4: waiting for Postgres ..."
# Check over TCP: during first-time init the image runs a temporary
# server on the unix socket only, which would pass a plain pg_isready.
for _ in $(seq 1 60); do
  if docker exec project_postgres pg_isready -h 127.0.0.1 -U postgres -q; then
    break
  fi
  sleep 2
done
docker exec project_postgres pg_isready -h 127.0.0.1 -U postgres

# Check for loaded data, not just the database: POSTGRES_DB in
# docker-compose.yml creates an empty imdb database on a fresh volume.
loaded=$(docker exec project_postgres psql -U postgres -d imdb -tAc \
  "SELECT EXISTS (SELECT 1 FROM title LIMIT 1)" 2>/dev/null || true)

echo
if [ "$loaded" = "t" ] && ! $reload; then
  echo "Step 4/4: imdb is already loaded, skipping load (use --reload to rebuild)"
else
  echo "Step 4/4: creating and loading the imdb database ..."
  echo "This takes a long time on the full dataset. Output goes to load.log."
  docker exec -i -w / project_postgres psql -U postgres -d postgres \
    < create_and_load.sql > load.log 2>&1
  # \copy reports a missing file without an ERROR prefix
  if grep -qE '^ERROR|No such file' load.log; then
    echo "WARNING: the load reported errors. See load.log:"
    grep -nE '^ERROR|No such file' load.log | head -20 || true
  fi
fi

echo
echo "Row count in title:"
docker exec project_postgres psql -U postgres -d imdb -tAc "SELECT count(*) FROM title"

echo
echo "Done."
echo "  pgAdmin:  http://localhost:5050  (register server: host postgres, db imdb)"
if [ -f metabase-data/metabase.db.mv.db ]; then
  echo "  Metabase: http://localhost:3000  (settings restored from metabase-data/, sign in as before)"
else
  echo "  Metabase: http://localhost:3000  (first-run setup, then add database imdb, host postgres)"
fi
