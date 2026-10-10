-- =========================================================
-- Chart 1 — "C1 — Top 15 Directors by Highly Rated Movie Count (2000–2025)"
-- Chart type: Bar
-- =========================================================
SELECT
    p.primary_name AS director_name,
    COUNT(DISTINCT t.tconst) AS high_rated_movies
FROM title_director AS d
JOIN person AS p
    ON p.nconst = d.nconst
JOIN title AS t
    ON t.tconst = d.tconst
JOIN title_rating AS r
    ON r.tconst = t.tconst
WHERE t.title_type = 'movie'
  AND t.start_year BETWEEN 2000 AND 2025
  AND r.average_rating >= 7.0
  AND r.num_votes >= 1000
GROUP BY p.nconst, p.primary_name
HAVING COUNT(DISTINCT t.tconst) >= 5
ORDER BY high_rated_movies DESC, director_name ASC
LIMIT 15;


-- =========================================================
-- Chart 2 — "C2 — Top 5 Genres by Average IMDb Rating (2000–2025)"
-- Chart type: Bar
-- =========================================================
SELECT
    g.genre,
    COUNT(DISTINCT t.tconst) AS movie_count,
    ROUND(AVG(r.average_rating), 2) AS avg_rating
FROM title_genre AS g
JOIN title AS t
    ON t.tconst = g.tconst
JOIN title_rating AS r
    ON r.tconst = t.tconst
WHERE t.title_type = 'movie'
  AND t.start_year BETWEEN 2000 AND 2025
  AND r.num_votes >= 1000
GROUP BY g.genre
HAVING COUNT(DISTINCT t.tconst) >= 100
ORDER BY avg_rating DESC, movie_count DESC, g.genre ASC
LIMIT 5;


-- =========================================================
-- Chart 3 — "Genre Mix by Decade"
-- Chart type: Bar
-- =========================================================
WITH genre_by_decade AS (
    SELECT (t.start_year / 10) * 10 AS decade,
           CASE WHEN g.genre IN ('Drama','Documentary','Comedy','Action','Thriller','Romance')
                THEN g.genre ELSE 'Other' END AS genre_bucket,
           COUNT(DISTINCT t.tconst) AS movie_count
    FROM title t
    JOIN title_genre g ON g.tconst = t.tconst
    WHERE t.title_type = 'movie'
      AND t.start_year BETWEEN 1920 AND 2025
    GROUP BY decade, genre_bucket
),
decade_totals AS (
    SELECT decade, SUM(movie_count) AS total
    FROM genre_by_decade
    GROUP BY decade
)
SELECT g.decade                                                                AS "Decade",
       ROUND(100.0 * SUM(CASE WHEN g.genre_bucket = 'Drama'       THEN g.movie_count ELSE 0 END) / dt.total, 1) AS "Drama %",
       ROUND(100.0 * SUM(CASE WHEN g.genre_bucket = 'Documentary' THEN g.movie_count ELSE 0 END) / dt.total, 1) AS "Documentary %",
       ROUND(100.0 * SUM(CASE WHEN g.genre_bucket = 'Comedy'      THEN g.movie_count ELSE 0 END) / dt.total, 1) AS "Comedy %",
       ROUND(100.0 * SUM(CASE WHEN g.genre_bucket = 'Action'      THEN g.movie_count ELSE 0 END) / dt.total, 1) AS "Action %",
       ROUND(100.0 * SUM(CASE WHEN g.genre_bucket = 'Thriller'    THEN g.movie_count ELSE 0 END) / dt.total, 1) AS "Thriller %",
       ROUND(100.0 * SUM(CASE WHEN g.genre_bucket = 'Romance'     THEN g.movie_count ELSE 0 END) / dt.total, 1) AS "Romance %",
       ROUND(100.0 * SUM(CASE WHEN g.genre_bucket = 'Other'       THEN g.movie_count ELSE 0 END) / dt.total, 1) AS "Other %"
FROM genre_by_decade g
JOIN decade_totals dt ON dt.decade = g.decade
GROUP BY g.decade, dt.total
ORDER BY "Decade";


-- =========================================================
-- Chart 4 — "Genre Quality vs Output: Rating Rank Minus Volume Rank"
-- Chart type: Bar
-- =========================================================
WITH genre_stats AS (
    SELECT g.genre,
           COUNT(DISTINCT t.tconst)                             AS movie_count,
           ROUND(AVG(r.average_rating), 2)                      AS avg_rating,
           RANK() OVER (ORDER BY AVG(r.average_rating) DESC)    AS rank_by_rating,
           RANK() OVER (ORDER BY COUNT(DISTINCT t.tconst) DESC) AS rank_by_volume
    FROM title t
    JOIN title_genre  g ON g.tconst = t.tconst
    JOIN title_rating r ON r.tconst = t.tconst
    WHERE t.title_type = 'movie'
      AND r.num_votes >= 1000
    GROUP BY g.genre
    HAVING COUNT(DISTINCT t.tconst) >= 50
)
SELECT genre                           AS "Genre",
       movie_count                     AS "Movies",
       avg_rating                      AS "Average Rating",
       rank_by_rating                  AS "Rank by Rating",
       rank_by_volume                  AS "Rank by Volume",
       rank_by_volume - rank_by_rating AS "Rank Gap"
FROM genre_stats
ORDER BY "Rank Gap" DESC;


-- =========================================================
-- Chart 5 — "Highest-Rated Prolific Actors"
-- Chart type: Row Bar
-- =========================================================
SELECT
    p.primary_name AS "Actor",
    COUNT(DISTINCT t.tconst) AS "Movies",
    ROUND(AVG(r.average_rating), 2) AS "Avg Rating"
FROM title_principal tp
JOIN title t ON t.tconst = tp.tconst
JOIN person p ON p.nconst = tp.nconst
JOIN title_rating r ON r.tconst = t.tconst
WHERE t.title_type = 'movie'
  AND tp.category IN ('actor', 'actress')
  AND r.num_votes >= 50000
GROUP BY p.nconst, p.primary_name
HAVING COUNT(DISTINCT t.tconst) >= 10
ORDER BY "Avg Rating" DESC
LIMIT 15;


-- =========================================================
-- Chart 6 — "Rating Difference by Genre"
-- Chart type: Row Bar
-- =========================================================
WITH eligible_movies AS (
    SELECT
        t.tconst,
        r.average_rating,
        r.num_votes
    FROM title AS t
    JOIN title_rating AS r
        ON r.tconst = t.tconst
    WHERE t.title_type = 'movie'
      AND t.start_year BETWEEN 2000 AND 2025
      AND r.num_votes >= 1000
),
genre_comparison AS (
    SELECT
        g.genre,
        COUNT(*) FILTER (WHERE m.num_votes < 10000) AS lower_vote_movie_count,
        COUNT(*) FILTER (WHERE m.num_votes >= 10000) AS higher_vote_movie_count,
        AVG(m.average_rating) FILTER (WHERE m.num_votes < 10000) AS lower_vote_average,
        AVG(m.average_rating) FILTER (WHERE m.num_votes >= 10000) AS higher_vote_average
    FROM eligible_movies AS m
    JOIN title_genre AS g
        ON g.tconst = m.tconst
    GROUP BY g.genre
),
rating_gaps AS (
    SELECT
        *,
        higher_vote_average - lower_vote_average AS gap
    FROM genre_comparison
    WHERE lower_vote_movie_count >= 30
      AND higher_vote_movie_count >= 30
)
SELECT
    genre,
    ROUND(gap, 2) AS rating_difference,
    ROUND(lower_vote_average, 2) AS lower_vote_avg_rating,
    ROUND(higher_vote_average, 2) AS higher_vote_avg_rating,
    lower_vote_movie_count,
    higher_vote_movie_count
FROM rating_gaps
ORDER BY gap DESC, genre;


-- =========================================================
-- Chart 7 — "What Netflix Killed"
-- Chart type: Line graph
-- =========================================================
WITH seasons AS (
  SELECT parent_tconst, season_number, COUNT(*) AS eps
  FROM title_episode
  WHERE season_number IS NOT NULL
  GROUP BY 1, 2
)
SELECT
    t.start_year,
    ROUND(AVG(s.eps), 1) AS avg_episodes_per_season,
    COUNT(DISTINCT t.tconst) AS series,
    CASE WHEN t.start_year = 2013 THEN 50 ELSE 0 END AS netflix_marker
FROM seasons s
JOIN title t ON t.tconst = s.parent_tconst
WHERE t.title_type = 'tvSeries'
  AND t.start_year BETWEEN 1960 AND 2024
GROUP BY 1
ORDER BY 1;


-- =========================================================
-- Chart 8 — "Proportion of Movies > 8/10"
-- Chart type: Pie chart
-- =========================================================
WITH eligible_movies AS (
    SELECT
        t.tconst,
        r.average_rating
    FROM title AS t
    JOIN title_rating AS r
        ON r.tconst = t.tconst
    WHERE t.title_type = 'movie'
      AND t.start_year BETWEEN 2000 AND 2025
      AND r.num_votes >= 1000
),
rating_counts AS (
    SELECT
        CASE
            WHEN average_rating >= 8.0 THEN 'Rated 8 or above'
            ELSE 'Rated below 8'
        END AS rating_category,
        COUNT(*) AS movie_count
    FROM eligible_movies
    GROUP BY 1
)
SELECT
    rating_category,
    movie_count,
    ROUND(
        100.0 * movie_count
        / NULLIF((SELECT SUM(movie_count) FROM rating_counts), 0),
        2
    ) AS percentage
FROM rating_counts
ORDER BY rating_category;


-- =========================================================
-- Chart 9 — "The Magic of 40 for Directors"
-- Chart type: Line chart
-- =========================================================
SELECT ((t.start_year - p.birth_year) / 5) * 5 AS director_age,
       ROUND(AVG(r.average_rating), 2) AS avg_rating,
       COUNT(*) AS films
FROM title_director d
JOIN person p ON p.nconst = d.nconst
JOIN title t ON t.tconst = d.tconst AND t.title_type = 'movie'
JOIN title_rating r ON r.tconst = t.tconst
WHERE p.birth_year IS NOT NULL
  AND r.num_votes >= 1000
  AND t.start_year - p.birth_year BETWEEN 20 AND 90
GROUP BY 1
ORDER BY 1;


-- =========================================================
-- Chart 10 — "Movies Released Per Year, 1920 to 2025"
-- Chart type: line graph 
-- =========================================================
WITH per_year AS (
    SELECT t.start_year AS year,
           COUNT(*)     AS movies
    FROM title t
    WHERE t.title_type = 'movie'
      AND (t.start_year BETWEEN 1920 AND 2025)
    GROUP BY t.start_year
)
SELECT year                                            AS "Year",
       movies                                          AS "Movies Released",
       SUM(movies) OVER (ORDER BY year)                AS "Cumulative Movies",
       movies - LAG(movies) OVER (ORDER BY year)       AS "Change vs Prev Year",
       ROUND(100.0 * (movies - LAG(movies) OVER (ORDER BY year))
             / NULLIF(LAG(movies) OVER (ORDER BY year), 0), 1)
                                                       AS "Growth (%)",
       ROUND(AVG(movies) OVER (
                 ORDER BY year
                 ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
             ))                                        AS "5-Year Moving Avg"
FROM per_year
ORDER BY "Year";