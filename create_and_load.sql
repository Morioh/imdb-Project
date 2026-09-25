-- ============================================================
-- create_and_load.sql
-- DSAI-691 Group Project - Phase 2
-- IMDb Database
--
-- Data source: IMDb Non-Commercial Datasets
--   Download:      https://datasets.imdbws.com/
--   Documentation: https://developer.imdb.com/non-commercial-datasets/
-- Files used (unzip the .tsv.gz files into rawdata/):
--   title.basics.tsv, name.basics.tsv, title.akas.tsv, title.crew.tsv,
--   title.episode.tsv, title.principals.tsv, title.ratings.tsv
--
-- One script: creates the database, creates all tables,
-- loads the raw IMDb files, then adds keys.
-- Setup: put the unzipped IMDb .tsv files in a folder named
--        rawdata/ next to this script.
-- Run from the folder that contains this script and rawdata/:
--   psql -U postgres -f create_and_load.sql
--   (or in pgAdmin PSQL Tool:  \cd <that folder>  then  \i create_and_load.sql)
--
-- Order (bulk-load best practice):
--   1. Create tables without PKs / FKs
--   2. Load data
--   3. Add PKs, then FKs
-- Building keys once on loaded data is much faster than checking
-- them row by row during a 100M+ row load.
-- ============================================================


-- ============================================================
-- SECTION 0: RESET + CREATE DATABASE (Role C)
-- Makes the script re-runnable. FORCE closes other connections
-- (e.g. Metabase) so the DROP does not fail.
-- ============================================================

-- Move off imdb first: a session cannot drop the database it is connected to.
\c postgres
DROP DATABASE IF EXISTS imdb WITH (FORCE);
CREATE DATABASE imdb;
\c imdb

-- More memory for sorting and index builds in this session only.
SET maintenance_work_mem = '1GB';
SET work_mem = '256MB';


-- ============================================================
-- SECTION 1: SCHEMA + DDL (Role B)
-- Tables are created with columns and NOT NULL only.
-- PRIMARY KEYs and FOREIGN KEYs are added in Section 3,
-- after the data is loaded.
-- ============================================================

-- TITLE  (source: title.basics.tsv) — central table of IMDb titles
CREATE TABLE title (
    tconst VARCHAR(20) NOT NULL,
    title_type VARCHAR(50) NOT NULL,
    primary_title TEXT NOT NULL,
    original_title TEXT NOT NULL,
    is_adult BOOLEAN NOT NULL,
    start_year INTEGER,
    end_year INTEGER,
    runtime_minutes INTEGER
);

-- PERSON  (source: name.basics.tsv) — central table of IMDb people
CREATE TABLE person (
    nconst VARCHAR(20) NOT NULL,
    primary_name TEXT NOT NULL,
    birth_year INTEGER,
    death_year INTEGER
);

-- TITLE AKA  (source: title.akas.tsv) — alternative/localized titles
CREATE TABLE title_aka (
    title_id VARCHAR(20) NOT NULL,
    ordering INTEGER NOT NULL,
    title TEXT NOT NULL,
    region VARCHAR(20),
    language VARCHAR(20),
    types TEXT,
    attributes TEXT,
    is_original_title BOOLEAN
);

-- TITLE GENRE  (source: genres field of title.basics.tsv)
CREATE TABLE title_genre (
    tconst VARCHAR(20) NOT NULL,
    genre VARCHAR(50) NOT NULL
);

-- TITLE EPISODE  (source: title.episode.tsv)
CREATE TABLE title_episode (
    tconst VARCHAR(20) NOT NULL,
    parent_tconst VARCHAR(20) NOT NULL,
    season_number INTEGER,
    episode_number INTEGER
);

-- TITLE RATING  (source: title.ratings.tsv)
CREATE TABLE title_rating (
    tconst VARCHAR(20) NOT NULL,
    average_rating NUMERIC(3,1) NOT NULL,
    num_votes INTEGER NOT NULL
);

-- PERSON PROFESSION  (source: primaryProfession field of name.basics.tsv)
CREATE TABLE person_profession (
    nconst VARCHAR(20) NOT NULL,
    profession VARCHAR(100) NOT NULL
);

-- PERSON KNOWN FOR  (source: knownForTitles field of name.basics.tsv)
CREATE TABLE person_known_for (
    nconst VARCHAR(20) NOT NULL,
    tconst VARCHAR(20) NOT NULL
);

-- TITLE PRINCIPAL  (source: title.principals.tsv)
CREATE TABLE title_principal (
    tconst VARCHAR(20) NOT NULL,
    ordering INTEGER NOT NULL,
    nconst VARCHAR(20) NOT NULL,
    category VARCHAR(100),
    job TEXT,
    characters TEXT
);

-- TITLE DIRECTOR  (source: directors field of title.crew.tsv)
CREATE TABLE title_director (
    tconst VARCHAR(20) NOT NULL,
    nconst VARCHAR(20) NOT NULL
);

-- TITLE WRITER  (source: writers field of title.crew.tsv)
CREATE TABLE title_writer (
    tconst VARCHAR(20) NOT NULL,
    nconst VARCHAR(20) NOT NULL
);


-- ============================================================
-- SECTION 2: LOAD DATA (Role C)
--
-- Method: staging tables
--   2a. Create one TEMP table per raw file (same columns as the file,
--       all TEXT), because \copy can only load a file as-is.
--   2b. \copy each raw file into its staging table, then ANALYZE it
--       (TEMP tables get no automatic statistics; without them the
--       planner guesses row counts and can pick slow joins).
--   2c. INSERT INTO the parent tables (title, person) with type casts.
--   2d. INSERT INTO the child tables: split comma lists into rows and
--       keep only rows whose parent ID exists, so the FKs added in
--       Section 3 always pass.
-- TEMP tables disappear automatically when the session ends.
--
-- FORMAT text: tab-separated, reads \N as NULL (matches IMDb).
-- HEADER true: skips the column-name line.
-- Each \copy must stay on ONE line.
-- ============================================================


-- ------------------------------------------------------------
-- 2a. Staging tables (column order = raw file column order)
-- ------------------------------------------------------------

CREATE TEMP TABLE stg_title_basics (
    tconst TEXT, title_type TEXT, primary_title TEXT, original_title TEXT,
    is_adult TEXT, start_year TEXT, end_year TEXT, runtime_minutes TEXT,
    genres TEXT
);

CREATE TEMP TABLE stg_name_basics (
    nconst TEXT, primary_name TEXT, birth_year TEXT, death_year TEXT,
    primary_profession TEXT, known_for_titles TEXT
);

CREATE TEMP TABLE stg_title_akas (
    title_id TEXT, ordering TEXT, title TEXT, region TEXT, language TEXT,
    types TEXT, attributes TEXT, is_original_title TEXT
);

CREATE TEMP TABLE stg_title_crew (
    tconst TEXT, directors TEXT, writers TEXT
);

CREATE TEMP TABLE stg_title_episode (
    tconst TEXT, parent_tconst TEXT, season_number TEXT, episode_number TEXT
);

CREATE TEMP TABLE stg_title_principals (
    tconst TEXT, ordering TEXT, nconst TEXT, category TEXT, job TEXT,
    characters TEXT
);

CREATE TEMP TABLE stg_title_ratings (
    tconst TEXT, average_rating TEXT, num_votes TEXT
);


-- ------------------------------------------------------------
-- 2b. Load raw files into staging + collect statistics
-- Paths are relative to the folder the script is run from.
-- ------------------------------------------------------------

\copy stg_title_basics     FROM 'rawdata/title.basics.tsv'     WITH (FORMAT text, HEADER true)
\copy stg_name_basics      FROM 'rawdata/name.basics.tsv'      WITH (FORMAT text, HEADER true)
\copy stg_title_akas       FROM 'rawdata/title.akas.tsv'       WITH (FORMAT text, HEADER true)
\copy stg_title_crew       FROM 'rawdata/title.crew.tsv'       WITH (FORMAT text, HEADER true)
\copy stg_title_episode    FROM 'rawdata/title.episode.tsv'    WITH (FORMAT text, HEADER true)
\copy stg_title_principals FROM 'rawdata/title.principals.tsv' WITH (FORMAT text, HEADER true)
\copy stg_title_ratings    FROM 'rawdata/title.ratings.tsv'    WITH (FORMAT text, HEADER true)

ANALYZE stg_title_basics;
ANALYZE stg_name_basics;
ANALYZE stg_title_akas;
ANALYZE stg_title_crew;
ANALYZE stg_title_episode;
ANALYZE stg_title_principals;
ANALYZE stg_title_ratings;


-- ------------------------------------------------------------
-- 2c. Parent tables
-- Rows missing a NOT NULL value are skipped.
-- ------------------------------------------------------------

-- title <- title.basics (genres go to title_genre)
INSERT INTO title (tconst, title_type, primary_title, original_title,
                   is_adult, start_year, end_year, runtime_minutes)
SELECT tconst,
       title_type,
       primary_title,
       original_title,
       is_adult::BOOLEAN,
       start_year::INTEGER,
       end_year::INTEGER,
       runtime_minutes::INTEGER
FROM stg_title_basics
WHERE title_type IS NOT NULL
  AND primary_title IS NOT NULL
  AND original_title IS NOT NULL
  AND is_adult IS NOT NULL;

-- person <- name.basics (professions / known-for go to their own tables)
INSERT INTO person (nconst, primary_name, birth_year, death_year)
SELECT nconst,
       primary_name,
       birth_year::INTEGER,
       death_year::INTEGER
FROM stg_name_basics
WHERE primary_name IS NOT NULL;

-- Parent PKs now, so the child-table JOINs below can use them.
ALTER TABLE title  ADD PRIMARY KEY (tconst);
ALTER TABLE person ADD PRIMARY KEY (nconst);
ANALYZE title;
ANALYZE person;


-- ------------------------------------------------------------
-- 2d. Child tables
-- JOIN to the parent keeps only rows whose parent ID exists.
-- DISTINCT removes duplicate pairs so the PKs in Section 3 pass.
-- string_to_array(x, ',') splits "A,B" into {A,B};
-- unnest(...) turns that array into one row per value.
-- ------------------------------------------------------------

-- title_genre <- genres list in title.basics
INSERT INTO title_genre (tconst, genre)
SELECT DISTINCT s.tconst, g.genre
FROM stg_title_basics s
JOIN title t ON t.tconst = s.tconst
CROSS JOIN LATERAL unnest(string_to_array(s.genres, ',')) AS g(genre);

-- title_rating <- title.ratings
INSERT INTO title_rating (tconst, average_rating, num_votes)
SELECT s.tconst,
       s.average_rating::NUMERIC(3,1),
       s.num_votes::INTEGER
FROM stg_title_ratings s
JOIN title t ON t.tconst = s.tconst
WHERE s.average_rating IS NOT NULL
  AND s.num_votes IS NOT NULL;

-- title_aka <- title.akas
INSERT INTO title_aka (title_id, ordering, title, region, language,
                       types, attributes, is_original_title)
SELECT s.title_id,
       s.ordering::INTEGER,
       s.title,
       s.region,
       s.language,
       s.types,
       s.attributes,
       s.is_original_title::BOOLEAN
FROM stg_title_akas s
JOIN title t ON t.tconst = s.title_id
WHERE s.title IS NOT NULL;

-- title_episode <- title.episode (episode and its parent must both exist)
INSERT INTO title_episode (tconst, parent_tconst, season_number, episode_number)
SELECT s.tconst,
       s.parent_tconst,
       s.season_number::INTEGER,
       s.episode_number::INTEGER
FROM stg_title_episode s
JOIN title t  ON t.tconst  = s.tconst
JOIN title tp ON tp.tconst = s.parent_tconst;

-- person_profession <- primaryProfession list in name.basics
INSERT INTO person_profession (nconst, profession)
SELECT DISTINCT s.nconst, p.profession
FROM stg_name_basics s
JOIN person pe ON pe.nconst = s.nconst
CROSS JOIN LATERAL unnest(string_to_array(s.primary_profession, ',')) AS p(profession)
WHERE p.profession <> '';

-- person_known_for <- knownForTitles list in name.basics
INSERT INTO person_known_for (nconst, tconst)
SELECT DISTINCT s.nconst, k.tconst
FROM stg_name_basics s
JOIN person pe ON pe.nconst = s.nconst
CROSS JOIN LATERAL unnest(string_to_array(s.known_for_titles, ',')) AS k(tconst)
JOIN title t ON t.tconst = k.tconst;

-- title_principal <- title.principals (title and person must exist)
INSERT INTO title_principal (tconst, ordering, nconst, category, job, characters)
SELECT s.tconst,
       s.ordering::INTEGER,
       s.nconst,
       s.category,
       s.job,
       s.characters
FROM stg_title_principals s
JOIN title  t ON t.tconst = s.tconst
JOIN person p ON p.nconst = s.nconst;

-- title_director <- directors list in title.crew
INSERT INTO title_director (tconst, nconst)
SELECT DISTINCT s.tconst, d.nconst
FROM stg_title_crew s
JOIN title t ON t.tconst = s.tconst
CROSS JOIN LATERAL unnest(string_to_array(s.directors, ',')) AS d(nconst)
JOIN person p ON p.nconst = d.nconst;

-- title_writer <- writers list in title.crew
INSERT INTO title_writer (tconst, nconst)
SELECT DISTINCT s.tconst, w.nconst
FROM stg_title_crew s
JOIN title t ON t.tconst = s.tconst
CROSS JOIN LATERAL unnest(string_to_array(s.writers, ',')) AS w(nconst)
JOIN person p ON p.nconst = w.nconst;


-- ============================================================
-- SECTION 3: KEYS (Role B schema, added after load)
-- Same PKs, FKs, and constraint names as the original DDL.
-- title and person PKs were already added in 2c.
-- ============================================================

-- Primary keys
ALTER TABLE title_aka         ADD PRIMARY KEY (title_id, ordering);
ALTER TABLE title_genre       ADD PRIMARY KEY (tconst, genre);
ALTER TABLE title_episode     ADD PRIMARY KEY (tconst);
ALTER TABLE title_rating      ADD PRIMARY KEY (tconst);
ALTER TABLE person_profession ADD PRIMARY KEY (nconst, profession);
ALTER TABLE person_known_for  ADD PRIMARY KEY (nconst, tconst);
ALTER TABLE title_principal   ADD PRIMARY KEY (tconst, ordering);
ALTER TABLE title_director    ADD PRIMARY KEY (tconst, nconst);
ALTER TABLE title_writer      ADD PRIMARY KEY (tconst, nconst);

-- Foreign keys
ALTER TABLE title_aka
    ADD CONSTRAINT fk_title_aka_title
    FOREIGN KEY (title_id) REFERENCES title(tconst);

ALTER TABLE title_genre
    ADD CONSTRAINT fk_title_genre_title
    FOREIGN KEY (tconst) REFERENCES title(tconst);

ALTER TABLE title_episode
    ADD CONSTRAINT fk_title_episode_title
    FOREIGN KEY (tconst) REFERENCES title(tconst);

ALTER TABLE title_episode
    ADD CONSTRAINT fk_title_episode_parent
    FOREIGN KEY (parent_tconst) REFERENCES title(tconst);

ALTER TABLE title_rating
    ADD CONSTRAINT fk_title_rating_title
    FOREIGN KEY (tconst) REFERENCES title(tconst);

ALTER TABLE person_profession
    ADD CONSTRAINT fk_person_profession_person
    FOREIGN KEY (nconst) REFERENCES person(nconst);

ALTER TABLE person_known_for
    ADD CONSTRAINT fk_person_known_for_person
    FOREIGN KEY (nconst) REFERENCES person(nconst);

ALTER TABLE person_known_for
    ADD CONSTRAINT fk_person_known_for_title
    FOREIGN KEY (tconst) REFERENCES title(tconst);

ALTER TABLE title_principal
    ADD CONSTRAINT fk_title_principal_title
    FOREIGN KEY (tconst) REFERENCES title(tconst);

ALTER TABLE title_principal
    ADD CONSTRAINT fk_title_principal_person
    FOREIGN KEY (nconst) REFERENCES person(nconst);

ALTER TABLE title_director
    ADD CONSTRAINT fk_title_director_title
    FOREIGN KEY (tconst) REFERENCES title(tconst);

ALTER TABLE title_director
    ADD CONSTRAINT fk_title_director_person
    FOREIGN KEY (nconst) REFERENCES person(nconst);

ALTER TABLE title_writer
    ADD CONSTRAINT fk_title_writer_title
    FOREIGN KEY (tconst) REFERENCES title(tconst);

ALTER TABLE title_writer
    ADD CONSTRAINT fk_title_writer_person
    FOREIGN KEY (nconst) REFERENCES person(nconst);

-- Fresh statistics on the final tables for later queries.
ANALYZE;


-- ============================================================
-- SECTION 4: EXPLORATION + VALIDATION (Role D)
-- Paste Anu's queries here.
-- ============================================================
-- 1. VALIDATION: every table is populated.
SELECT 'title'             AS table_name, COUNT(*) AS rows FROM title
UNION ALL SELECT 'title_rating',      COUNT(*) FROM title_rating
UNION ALL SELECT 'title_genre',       COUNT(*) FROM title_genre
UNION ALL SELECT 'title_principal',   COUNT(*) FROM title_principal
UNION ALL SELECT 'title_director',    COUNT(*) FROM title_director
UNION ALL SELECT 'title_writer',      COUNT(*) FROM title_writer
UNION ALL SELECT 'title_aka',         COUNT(*) FROM title_aka
UNION ALL SELECT 'title_episode',     COUNT(*) FROM title_episode
UNION ALL SELECT 'person',            COUNT(*) FROM person
UNION ALL SELECT 'person_known_for',  COUNT(*) FROM person_known_for
UNION ALL SELECT 'person_profession', COUNT(*) FROM person_profession
ORDER BY rows DESC;


-- 2. VALIDATION: column types are correct, not TEXT or FLOAT.
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('title', 'title_rating', 'person')
ORDER BY table_name, ordinal_position;


-- 3. VALIDATION: foreign-key integrity. Every count must be 0.
SELECT 'ratings with no title' AS integrity_check, COUNT(*) AS violations
FROM title_rating r
LEFT JOIN title t ON t.tconst = r.tconst
WHERE t.tconst IS NULL
UNION ALL
SELECT 'genres with no title', COUNT(*)
FROM title_genre g
LEFT JOIN title t ON t.tconst = g.tconst
WHERE t.tconst IS NULL
UNION ALL
SELECT 'principals with no person', COUNT(*)
FROM title_principal p
LEFT JOIN person n ON n.nconst = p.nconst
WHERE n.nconst IS NULL;


-- 4. VALIDATION: spot-check three known titles against the raw TSV.
-- Expected: Shawshank 1994/142min, Dark Knight 2008/152min,
-- Endgame 2019/181min.
SELECT t.tconst,
       t.primary_title,
       t.start_year,
       t.runtime_minutes,
       r.average_rating,
       r.num_votes,
       string_agg(g.genre, ', ' ORDER BY g.genre) AS genres
FROM title t
LEFT JOIN title_rating r ON r.tconst = t.tconst
LEFT JOIN title_genre  g ON g.tconst = t.tconst
WHERE t.tconst IN ('tt0111161', 'tt0468569', 'tt4154796')
GROUP BY t.tconst, t.primary_title, t.start_year,
         t.runtime_minutes, r.average_rating, r.num_votes
ORDER BY r.num_votes DESC;


-- 5. VALIDATION: missing-value profile.
-- 11.6% of titles have no start year and 64% have no runtime. This is
-- the source data, not a load failure, but it constrains later charts.
SELECT COUNT(*)                                        AS total_titles,
       COUNT(*) FILTER (WHERE start_year IS NULL)      AS missing_start_year,
       COUNT(*) FILTER (WHERE runtime_minutes IS NULL) AS missing_runtime,
       ROUND(100.0 * COUNT(*) FILTER (WHERE runtime_minutes IS NULL)
             / COUNT(*), 1)                            AS pct_missing_runtime
FROM title;


-- 6. EXPLORATION: what kind of titles did we load?
-- Only 5.9% are movies; 77% are TV episodes.
SELECT title_type,
       COUNT(*)                                          AS titles,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM title
GROUP BY title_type
ORDER BY titles DESC;


-- 7. EXPLORATION: movie output per decade.
-- Output roughly quadrupled between the 1990s and the 2010s.
SELECT (start_year / 10) * 10 AS decade,
       COUNT(*)               AS movies
FROM title
WHERE title_type = 'movie'
  AND (start_year BETWEEN 1900 AND 2029)
GROUP BY decade
ORDER BY decade;


-- 8. EXPLORATION: rating and volume by genre.
-- Joins three tables, aggregates, and filters out films with too few
-- votes to be meaningful. Documentary rates highest; Drama dominates
-- volume; Horror rates lowest despite high output.
SELECT g.genre,
       COUNT(DISTINCT t.tconst)        AS movies,
       ROUND(AVG(r.average_rating), 2) AS avg_rating
FROM title t
JOIN title_genre  g ON g.tconst = t.tconst
JOIN title_rating r ON r.tconst = t.tconst
WHERE t.title_type = 'movie'
  AND r.num_votes >= 1000
GROUP BY g.genre
HAVING COUNT(DISTINCT t.tconst) >= 50
ORDER BY avg_rating DESC;


-- 9. EXPLORATION: directors with the highest average movie ratings.
-- Joins person to title through the title_director bridge table. The
-- HAVING floor requires a real filmography. Doubles as a sanity check:
-- the result is Nolan, Satyajit Ray, Miyazaki, Kurosawa, Kubrick.
SELECT p.primary_name                  AS director,
       COUNT(DISTINCT t.tconst)        AS movies,
       ROUND(AVG(r.average_rating), 2) AS avg_rating
FROM title_director d
JOIN person p       ON p.nconst = d.nconst
JOIN title t        ON t.tconst = d.tconst
JOIN title_rating r ON r.tconst = t.tconst
WHERE t.title_type = 'movie'
  AND r.num_votes >= 1000
GROUP BY p.nconst, p.primary_name
HAVING COUNT(DISTINCT t.tconst) >= 10
ORDER BY avg_rating DESC
LIMIT 15;


-- 10. EXPLORATION: ratings and votes by era.
-- Median as well as mean, because vote counts are heavily skewed by a
-- few blockbusters.
SELECT CASE
           WHEN start_year < 1970 THEN 'Pre-1970'
           WHEN start_year < 1990 THEN '1970-1989'
           WHEN start_year < 2005 THEN '1990-2004'
           WHEN start_year < 2015 THEN '2005-2014'
           ELSE                        '2015+'
       END                                             AS era,
       COUNT(*)                                        AS movies,
       ROUND(AVG(r.average_rating), 2)                 AS avg_rating,
       ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP
             (ORDER BY r.average_rating))::numeric, 2) AS median_rating,
       ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP
             (ORDER BY r.num_votes))::numeric)         AS median_votes
FROM title t
JOIN title_rating r ON r.tconst = t.tconst
WHERE t.title_type = 'movie'
  AND t.start_year IS NOT NULL
GROUP BY era
ORDER BY era;
