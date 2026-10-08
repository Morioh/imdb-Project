# imdb-Project

A PostgreSQL relational database built from IMDb's non-commercial datasets,
normalized into linked tables for titles, people, genres, crew and ratings.
SQL queries then explore how genre, release year and the people involved
relate to audience ratings, with findings surfaced in an interactive
Metabase dashboard.

## Which setup am I doing?

Run this one command first — it tells you objectively whether this machine
has already been set up before:

```bash
docker ps -a --filter "name=project_postgres" --format "{{.Names}}: {{.Status}}"
```

- **Prints nothing** → this machine has never run the stack. Do
  **First-time setup** below, steps 1–6, in order.
- **Prints a line** (any status — `Up`, `Exited`, doesn't matter) → the
  containers already exist here, which means the database was already
  created and loaded, and Metabase was already connected, in an earlier
  session. Skip straight to **Resuming on an already-set-up machine**
  further down — don't repeat steps 1–6, and specifically don't run
  `docker compose up -d` or re-run `create_and_load.sql`.

---

## First-time setup

*(Do this section only if `docker ps -a` above printed nothing.)*

### Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Mac/Windows)
  or Docker Engine + Compose plugin (Linux)
- `git`, `curl` (for the optional download script)
- A few GB of free disk space (raw IMDb files + Postgres volume)

### 1. Clone this repo

```bash
git clone https://github.com/Morioh/imdb-Project.git
cd imdb-Project
```

### 2. Get the raw IMDb data

The raw `.tsv` files are **not committed to this repo** — they're large,
and IMDb's non-commercial license doesn't cover redistributing them. The
`data/` folder is checked in empty; populate it one of two ways.

**Option A — script (recommended):**

```bash
bash download_data.sh
```

Downloads and unzips all 7 files directly into `data/`. Safe to re-run —
it skips any file that's already there.

**Option B — manual:**

1. Go to https://datasets.imdbws.com/
2. Download these 7 files:
   - `name.basics.tsv.gz`
   - `title.akas.tsv.gz`
   - `title.basics.tsv.gz`
   - `title.crew.tsv.gz`
   - `title.episode.tsv.gz`
   - `title.principals.tsv.gz`
   - `title.ratings.tsv.gz`
3. Unzip each one and put the resulting `.tsv` file directly in `data/`.

Either way, `data/` should end up looking like:

```
data/
├── name.basics.tsv
├── title.akas.tsv
├── title.basics.tsv
├── title.crew.tsv
├── title.episode.tsv
├── title.principals.tsv
└── title.ratings.tsv
```

### 3. Start the stack

```bash
docker compose up -d
```

| Service | Purpose | Access |
|---|---|---|
| `project_postgres` | PostgreSQL 18 | `localhost:5432` |
| `project_pgadmin` | Optional GUI for Postgres | http://localhost:5050 |
| `project_metabase` | Dashboarding | http://localhost:3000 |

Confirm everything's actually running (not restarting):

```bash
docker ps
```

All three should show `Up`.

### 4. Create the database and load the data

```bash
docker exec -i -w / project_postgres psql -U postgres -d postgres < create_and_load.sql
```

`create_and_load.sql` drops/recreates the `imdb` database, creates all 11
tables, loads the raw files, adds primary/foreign keys, and finishes with
a set of exploration and validation queries. It's fully re-runnable —
running it again just rebuilds from scratch. Given the real dataset size,
this takes a while; let it finish.

The `-w /` sets the container's working directory to root, so the script's
relative `rawdata/...` paths resolve to `/rawdata`, which `docker-compose.yml`
mounts to this repo's local `data/` folder.

### 5. Verify the load

```bash
docker exec -it project_postgres psql -U postgres -d imdb
```

```sql
\dt                                              -- should list 11 tables
SELECT count(*) FROM title;
SELECT count(*) FROM title_principal;
SELECT * FROM title WHERE tconst = 'tt0111161';  -- The Shawshank Redemption
```

### 6. Connect Metabase

1. Open http://localhost:3000 and complete the first-run setup (admin account).
2. Admin settings → Databases → Add a database:
   - Type: **PostgreSQL**
   - Host: `postgres` (the Docker service name — **not** `localhost`)
   - Port: `5432`
   - Database name: `imdb`
   - Username: `postgres`
   - Password: `postgres`
3. Save, let it sync, then confirm all 11 tables are browsable and a
   question against any table returns real rows.

---

## Resuming on an already-set-up machine

*(Do this section only if `docker ps -a --filter "name=project_postgres"`
at the top printed a line. Everything below — the containers, the loaded
`imdb` database, and the Metabase connection — was already built in a
previous session, so none of steps 1–6 above are needed.)*

Just start the existing containers back up:

```bash
docker start project_postgres project_pgadmin project_metabase
```

Confirm they're actually running (not restarting):

```bash
docker ps
```

All three should show `Up`. Then:

- **Postgres** already has the `imdb` database loaded — no need to touch
  `create_and_load.sql` again. If you want to sanity-check the data is
  still there: `docker exec -it project_postgres psql -U postgres -d imdb -c "SELECT count(*) FROM title;"`.
- **Metabase** at http://localhost:3000 already has the admin account and
  the `imdb` database connection saved — sign in with the admin credentials
  from last time (you won't see the first-run setup screen), and your
  existing questions/dashboard should be right there.

**Don't run `docker compose up -d` here.** Compose names containers after
the folder it's run from, so if this clone lives in a differently-named
folder than the one used originally, `up -d` will either collide with the
existing `project_postgres`/`project_pgadmin`/`project_metabase` containers
("Conflict. The container name ... is already in use") or spin up a second,
empty data volume alongside the real one. `docker start` resumes the exact
containers and volume you already have, regardless of which folder you're
running it from.

## Troubleshooting

- **Container stuck "Restarting"** — usually a Postgres major-version
  mismatch against an existing volume. Postgres 18's image expects a single
  mount at `/var/lib/postgresql`, not `.../data`. Check
  `docker logs project_postgres` for details. Fix: `docker compose down -v`
  (wipes the volume — only safe before real data is loaded) then
  `docker compose up -d` again.
- **`\copy` fails with "no such file"** — `docker-compose.yml` mounts the
  local `data/` folder to both `/data` and `/rawdata` inside the container,
  covering either path convention the script might use. Make sure your raw
  files are actually in `data/` at the project root first, and that you
  passed `-w /` as shown in step 4 if running `create_and_load.sql` directly.
- **`could not resize shared memory segment ... No space left on device`**
  — not actually about disk space. Docker's default `/dev/shm` (64MB) is too
  small for Postgres's parallel hash joins on large tables like
  `title_principal`. `docker-compose.yml` sets `shm_size: '1gb'` on the
  `postgres` service to fix this. As an immediate one-session workaround:
  `SET max_parallel_workers_per_gather = 0;` before re-running the query.
- **Metabase can't connect** — host must be `postgres`, not `localhost`.
  Inside the Metabase container, `localhost` means the Metabase container
  itself, not Postgres.
- **`docker ps` shows nothing / daemon errors** — Docker Desktop isn't
  running. Open the app and wait for the whale icon to go steady, then retry.
- **`Conflict. The container name "/project_postgres" is already in use`**
  — you ran `docker compose up -d` on a machine that already has this stack
  set up. Run `docker ps -a | grep project_` to confirm the containers
  already exist, then use `docker start project_postgres project_pgadmin
  project_metabase` instead (see "Resuming on an already-set-up machine"
  above) rather than recreating them. Don't run `docker compose down -v`
  to "fix" this — it destroys the volume holding the already-loaded data.

## Repo structure

```
.
├── docker-compose.yml     # Postgres + pgAdmin + Metabase, one shared network
├── create_and_load.sql    # creates DB, tables, loads data, adds keys, runs validation queries
├── download_data.sh       # optional: fetches the 7 raw IMDb files into data/
├── data/                  # raw IMDb .tsv files — not committed, see step 2
├── imdb_er_diagram.html   # entity-relationship diagram for the schema
├── LICENSE
└── README.md
```