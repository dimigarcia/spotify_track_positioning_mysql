-- ============================================================
-- 03_data.sql
-- Spotify Track Positioning Analytics
-- MySQL 8.0 / MySQL Workbench
-- ============================================================
--
-- Purpose:
--   Validate the raw/staging import, run data-quality checks, clean the raw
--   data, and populate the relational dimensional model.
--
-- Before running:
--   Run sql/01_schema.sql.
--   Run sql/02_import_raw_data.sql to populate raw_spotify_tracks.
-- ============================================================

USE spotify_track_positioning;

SET SQL_SAFE_UPDATES = 0;
SET FOREIGN_KEY_CHECKS = 0;

-- ------------------------------------------------------------
-- 1. Validate source import into the raw/staging table
-- ------------------------------------------------------------
-- The raw data is loaded by sql/02_import_raw_data.sql before running this
-- script. That script contains generated INSERT statements derived from the
-- original CSV in data/raw/spotify_tracks.csv.
--
-- Expected raw row count before cleaning: 114,000.
-- If this check fails, rerun sql/02_import_raw_data.sql before continuing.

SELECT
    COUNT(*) AS raw_rows_after_import
FROM raw_spotify_tracks;

DROP PROCEDURE IF EXISTS sp_assert_raw_import_count;

DELIMITER $$
CREATE PROCEDURE sp_assert_raw_import_count()
BEGIN
    DECLARE raw_count INT DEFAULT 0;

    SELECT COUNT(*)
    INTO raw_count
    FROM raw_spotify_tracks;

    IF raw_count <> 114000 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Import incomplete: raw_spotify_tracks must contain 114000 rows before running 03_data.sql.';
    END IF;
END$$
DELIMITER ;

CALL sp_assert_raw_import_count();
DROP PROCEDURE IF EXISTS sp_assert_raw_import_count;

-- Remove possible carriage-return residue if the file was saved with CRLF endings.
UPDATE raw_spotify_tracks
SET track_genre = TRIM(BOTH CHAR(13) FROM track_genre);

-- ------------------------------------------------------------
-- 2. Reset loaded model/audit tables so the script can be rerun
-- ------------------------------------------------------------

DELETE FROM bridge_track_artist;
DELETE FROM bridge_track_genre;
DELETE FROM fact_track_metrics;
DELETE FROM dim_artist;
DELETE FROM dim_track;
DELETE FROM dim_album;
DELETE FROM dim_genre;
DELETE FROM dim_audio_key;
DELETE FROM dim_mode;
DELETE FROM dim_explicit;
DELETE FROM util_numbers;
DELETE FROM dq_album_name_audit;
DELETE FROM dq_repeated_track_attribute_audit;
DELETE FROM dq_track_genre_duplicate_audit;
DELETE FROM dq_quality_summary;
DELETE FROM etl_run_log;

SET FOREIGN_KEY_CHECKS = 1;

INSERT INTO etl_run_log (step_name, rows_recorded)
SELECT 'raw_rows_after_csv_import', COUNT(*)
FROM raw_spotify_tracks;

-- ------------------------------------------------------------
-- 3. Initial data-quality summary
-- ------------------------------------------------------------

INSERT INTO dq_quality_summary (metric_name, metric_value, metric_note)
SELECT
    'raw_rows_after_csv_import',
    COUNT(*),
    'Rows loaded into raw_spotify_tracks from generated SQL INSERT statements.'
FROM raw_spotify_tracks;

INSERT INTO dq_quality_summary (metric_name, metric_value, metric_note)
SELECT
    'null_or_blank_artist_rows',
    COUNT(*),
    'Rows with missing artist text before basic descriptive cleaning.'
FROM raw_spotify_tracks
WHERE artists IS NULL OR TRIM(artists) = '';

INSERT INTO dq_quality_summary (metric_name, metric_value, metric_note)
SELECT
    'null_or_blank_album_rows',
    COUNT(*),
    'Rows with missing album text before basic descriptive cleaning.'
FROM raw_spotify_tracks
WHERE album_name IS NULL OR TRIM(album_name) = '';

INSERT INTO dq_quality_summary (metric_name, metric_value, metric_note)
SELECT
    'null_or_blank_track_rows',
    COUNT(*),
    'Rows with missing track-name text before basic descriptive cleaning.'
FROM raw_spotify_tracks
WHERE track_name IS NULL OR TRIM(track_name) = '';

-- ------------------------------------------------------------
-- 4. Basic raw-data cleaning with COMMIT
-- ------------------------------------------------------------
-- Missing descriptive fields are converted to explicit unknown labels.
-- The transaction is committed because the labels are needed to satisfy
-- NOT NULL constraints in the dimensional model.

START TRANSACTION;

UPDATE raw_spotify_tracks
SET artists = 'Unknown Artist'
WHERE artists IS NULL OR TRIM(artists) = '';

UPDATE raw_spotify_tracks
SET album_name = 'Unknown Album'
WHERE album_name IS NULL OR TRIM(album_name) = '';

UPDATE raw_spotify_tracks
SET track_name = 'Unknown Track'
WHERE track_name IS NULL OR TRIM(track_name) = '';

UPDATE raw_spotify_tracks
SET track_genre = 'Unknown Genre'
WHERE track_genre IS NULL OR TRIM(track_genre) = '';

COMMIT;

-- ------------------------------------------------------------
-- 5. Transaction safety check with ROLLBACK
-- ------------------------------------------------------------
-- The block tests a possible range correction for popularity values and
-- deliberately cancels it. This demonstrates how a risky cleaning action
-- can be checked without silently changing source metrics.

START TRANSACTION;

UPDATE raw_spotify_tracks
SET popularity = CASE
    WHEN CAST(popularity AS SIGNED) < 0 THEN '0'
    WHEN CAST(popularity AS SIGNED) > 100 THEN '100'
    ELSE popularity
END
WHERE CAST(popularity AS SIGNED) < 0
   OR CAST(popularity AS SIGNED) > 100;

SET @range_correction_rows_tested = ROW_COUNT();

ROLLBACK;

INSERT INTO dq_quality_summary (metric_name, metric_value, metric_note)
VALUES (
    'rollback_demo_popularity_range_rows',
    @range_correction_rows_tested,
    'Rows that would have been changed by a popularity range correction. The transaction was rolled back.'
);

-- ------------------------------------------------------------
-- 6. Audit and remove duplicated track_id + genre rows
-- ------------------------------------------------------------
-- A repeated track_id across different genres is valid. A repeated
-- track_id + genre row is audited as a possible source duplicate.

CREATE TEMPORARY TABLE tmp_track_genre_duplicate_signature AS
SELECT
    source_row_id,
    track_id,
    track_genre,
    MD5(CONCAT_WS('||',
        track_id,
        artists,
        album_name,
        track_name,
        popularity,
        duration_ms,
        explicit,
        danceability,
        energy,
        `key`,
        loudness,
        mode,
        speechiness,
        acousticness,
        instrumentalness,
        liveness,
        valence,
        tempo,
        time_signature,
        track_genre
    )) AS substantive_signature
FROM raw_spotify_tracks;

INSERT INTO dq_track_genre_duplicate_audit (
    track_id,
    track_genre,
    duplicate_rows,
    distinct_substantive_versions,
    min_source_row_id,
    max_source_row_id
)
SELECT
    track_id,
    track_genre,
    COUNT(*) AS duplicate_rows,
    COUNT(DISTINCT substantive_signature) AS distinct_substantive_versions,
    MIN(source_row_id) AS min_source_row_id,
    MAX(source_row_id) AS max_source_row_id
FROM tmp_track_genre_duplicate_signature
GROUP BY track_id, track_genre
HAVING COUNT(*) > 1;

CREATE TEMPORARY TABLE tmp_duplicate_rank AS
SELECT
    source_row_id,
    track_id,
    track_genre,
    ROW_NUMBER() OVER (
        PARTITION BY track_id, track_genre
        ORDER BY source_row_id
    ) AS duplicate_rank
FROM raw_spotify_tracks;

START TRANSACTION;

DELETE r
FROM raw_spotify_tracks AS r
INNER JOIN tmp_duplicate_rank AS d
    ON r.source_row_id = d.source_row_id
INNER JOIN dq_track_genre_duplicate_audit AS a
    ON a.track_id = d.track_id
   AND a.track_genre = d.track_genre
WHERE d.duplicate_rank > 1
  AND a.distinct_substantive_versions = 1;

SET @duplicate_rows_removed = ROW_COUNT();

COMMIT;

DROP TEMPORARY TABLE tmp_duplicate_rank;
DROP TEMPORARY TABLE tmp_track_genre_duplicate_signature;

INSERT INTO dq_quality_summary (metric_name, metric_value, metric_note)
VALUES (
    'duplicate_track_genre_rows_removed',
    @duplicate_rows_removed,
    'Redundant repeated track_id + genre rows removed after confirming no substantive conflicts within duplicate groups.'
);

INSERT INTO etl_run_log (step_name, rows_recorded)
SELECT 'raw_rows_after_duplicate_delete', COUNT(*)
FROM raw_spotify_tracks;

-- ------------------------------------------------------------
-- 7. Audit repeated tracks across genres before choosing grain
-- ------------------------------------------------------------
-- The audit checks whether repeated track_id rows have different audio or
-- metadata attributes apart from genre and popularity. It also quantifies how
-- much popularity varies for the same track across genre rows. Most conflicts
-- are very small relative to the full 0-100 popularity scale, and some larger
-- conflicts contain suspicious zero values. For global track rankings, the
-- project therefore uses MAX(popularity) as the selected track-level value and
-- retains min/max/average/range for auditability.

INSERT INTO dq_repeated_track_attribute_audit (
    track_id,
    genre_count,
    distinct_non_genre_attribute_versions,
    distinct_popularity_values,
    min_popularity,
    max_popularity,
    avg_popularity,
    popularity_range,
    treatment_note
)
SELECT
    track_id,
    COUNT(DISTINCT track_genre) AS genre_count,
    COUNT(DISTINCT MD5(CONCAT_WS('||',
        artists,
        album_name,
        track_name,
        duration_ms,
        explicit,
        danceability,
        energy,
        `key`,
        loudness,
        mode,
        speechiness,
        acousticness,
        instrumentalness,
        liveness,
        valence,
        tempo,
        time_signature
    ))) AS distinct_non_genre_attribute_versions,
    COUNT(DISTINCT CAST(popularity AS UNSIGNED)) AS distinct_popularity_values,
    MIN(CAST(popularity AS UNSIGNED)) AS min_popularity,
    MAX(CAST(popularity AS UNSIGNED)) AS max_popularity,
    ROUND(AVG(CAST(popularity AS UNSIGNED)), 2) AS avg_popularity,
    MAX(CAST(popularity AS UNSIGNED)) - MIN(CAST(popularity AS UNSIGNED)) AS popularity_range,
    'Audio and metadata attributes are loaded at track level. Popularity is selected as MAX(popularity) per track because conflicts are rare and mostly small, while some larger conflicts contain suspicious zero values.'
FROM raw_spotify_tracks
GROUP BY track_id
HAVING COUNT(DISTINCT track_genre) > 1;

INSERT INTO dq_quality_summary (metric_name, metric_value, metric_note)
SELECT
    'multi_genre_tracks_with_non_genre_attribute_differences',
    COUNT(*),
    'Tracks appearing in multiple genres where non-genre, non-popularity attributes differ.'
FROM dq_repeated_track_attribute_audit
WHERE distinct_non_genre_attribute_versions > 1;

INSERT INTO dq_quality_summary (metric_name, metric_value, metric_note)
SELECT
    'multi_genre_tracks_with_popularity_differences',
    COUNT(*),
    'Tracks appearing in multiple genres where popularity differs across genre rows before track-level aggregation.'
FROM dq_repeated_track_attribute_audit
WHERE distinct_popularity_values > 1;

INSERT INTO dq_quality_summary (metric_name, metric_value, metric_note)
SELECT
    'max_popularity_range_for_same_track',
    MAX(popularity_range),
    'Largest difference between minimum and maximum observed popularity for the same track across genre rows.'
FROM dq_repeated_track_attribute_audit;

INSERT INTO dq_quality_summary (metric_name, metric_value, metric_note)
SELECT
    'tracks_with_popularity_range_5_or_more',
    COUNT(*),
    'Multi-genre tracks whose observed popularity differs by at least 5 points on the 0-100 scale.'
FROM dq_repeated_track_attribute_audit
WHERE popularity_range >= 5;

-- ------------------------------------------------------------
-- 8. Audit album-name ambiguity
-- ------------------------------------------------------------
-- The dataset has album names but no album IDs. Album names are not unique
-- across artist credits, so album_name + artist-credit text is used.

INSERT INTO dq_album_name_audit (album_name, distinct_artist_credits, treatment_note)
SELECT
    TRIM(album_name) AS album_name,
    COUNT(DISTINCT TRIM(artists)) AS distinct_artist_credits,
    'Album title alone is not treated as a unique album identifier. dim_album uses album_name + artist-credit text.'
FROM raw_spotify_tracks
GROUP BY TRIM(album_name)
HAVING COUNT(DISTINCT TRIM(artists)) > 1;

INSERT INTO dq_quality_summary (metric_name, metric_value, metric_note)
SELECT
    'album_names_with_multiple_artist_credits',
    COUNT(*),
    'Album names associated with more than one artist-credit string.'
FROM dq_album_name_audit;

-- ------------------------------------------------------------
-- 9. Populate utility and static dimensions
-- ------------------------------------------------------------

INSERT INTO util_numbers (n) VALUES
    (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),
    (11),(12),(13),(14),(15),(16),(17),(18),(19),(20),
    (21),(22),(23),(24),(25),(26),(27),(28),(29),(30),
    (31),(32),(33),(34),(35),(36),(37),(38),(39),(40),
    (41),(42),(43),(44),(45),(46),(47),(48),(49),(50);

INSERT INTO dim_audio_key (key_code, key_name) VALUES
    (0, 'C'),
    (1, 'C# / Db'),
    (2, 'D'),
    (3, 'D# / Eb'),
    (4, 'E'),
    (5, 'F'),
    (6, 'F# / Gb'),
    (7, 'G'),
    (8, 'G# / Ab'),
    (9, 'A'),
    (10, 'A# / Bb'),
    (11, 'B');

INSERT INTO dim_mode (mode_id, mode_name) VALUES
    (0, 'Minor'),
    (1, 'Major');

INSERT INTO dim_explicit (explicit_id, explicit_label) VALUES
    (0, 'Not explicit'),
    (1, 'Explicit');

-- ------------------------------------------------------------
-- 10. Populate core dimensions
-- ------------------------------------------------------------

INSERT INTO dim_genre (genre_name)
SELECT DISTINCT TRIM(track_genre) AS genre_name
FROM raw_spotify_tracks
WHERE track_genre IS NOT NULL
  AND TRIM(track_genre) <> ''
ORDER BY genre_name;

INSERT INTO dim_album (album_name, album_artist_text, album_key_hash)
SELECT DISTINCT
    TRIM(album_name) AS album_name,
    TRIM(artists) AS album_artist_text,
    MD5(CONCAT_WS('||', TRIM(album_name), TRIM(artists))) AS album_key_hash
FROM raw_spotify_tracks
WHERE album_name IS NOT NULL
  AND TRIM(album_name) <> '';

INSERT INTO dim_track (track_id, track_name, duration_ms)
SELECT
    r.track_id,
    MAX(TRIM(r.track_name)) AS track_name,
    MAX(CAST(r.duration_ms AS UNSIGNED)) AS duration_ms
FROM raw_spotify_tracks AS r
WHERE r.track_id IS NOT NULL
  AND TRIM(r.track_id) <> ''
GROUP BY r.track_id;

INSERT INTO dim_artist (artist_name)
SELECT DISTINCT split_artists.artist_name
FROM (
    SELECT
        TRIM(
            SUBSTRING_INDEX(
                SUBSTRING_INDEX(r.artists, ';', n.n),
                ';',
                -1
            )
        ) AS artist_name
    FROM raw_spotify_tracks AS r
    INNER JOIN util_numbers AS n
        ON n.n <= 1 + LENGTH(r.artists) - LENGTH(REPLACE(r.artists, ';', ''))
) AS split_artists
WHERE split_artists.artist_name IS NOT NULL
  AND split_artists.artist_name <> ''
ORDER BY split_artists.artist_name;

-- ------------------------------------------------------------
-- 11. Populate track-level fact table
-- ------------------------------------------------------------
-- Each fact row represents one unique track_id. Popularity is aggregated to a
-- single selected value per track using MAX(popularity). This prevents global
-- rankings from being duplicated by track/genre pairs. The max rule is used
-- because repeated-track popularity conflicts are rare, mostly small relative
-- to the full 0-100 scale, and some larger conflicts include suspicious zero
-- values in one genre row while another row has a plausible non-zero value.
-- Min, max, average, range and conflict flag are retained for auditability.

CREATE TEMPORARY TABLE tmp_track_representative AS
SELECT *
FROM (
    SELECT
        r.*,
        ROW_NUMBER() OVER (
            PARTITION BY r.track_id
            ORDER BY r.source_row_id
        ) AS track_rank
    FROM raw_spotify_tracks AS r
) AS ranked_tracks
WHERE track_rank = 1;

CREATE TEMPORARY TABLE tmp_track_popularity_summary AS
SELECT
    track_id,
    MAX(CAST(popularity AS UNSIGNED)) AS selected_popularity,
    MIN(CAST(popularity AS UNSIGNED)) AS popularity_min_observed,
    MAX(CAST(popularity AS UNSIGNED)) AS popularity_max_observed,
    ROUND(AVG(CAST(popularity AS UNSIGNED)), 2) AS popularity_avg_observed,
    MAX(CAST(popularity AS UNSIGNED)) - MIN(CAST(popularity AS UNSIGNED)) AS popularity_range,
    CASE
        WHEN COUNT(DISTINCT CAST(popularity AS UNSIGNED)) > 1 THEN 1
        ELSE 0
    END AS popularity_conflict_flag
FROM raw_spotify_tracks
GROUP BY track_id;

INSERT INTO fact_track_metrics (
    track_surrogate_id,
    album_id,
    key_id,
    mode_id,
    explicit_id,
    selected_popularity,
    popularity_min_observed,
    popularity_max_observed,
    popularity_avg_observed,
    popularity_range,
    popularity_conflict_flag,
    danceability,
    energy,
    loudness,
    speechiness,
    acousticness,
    instrumentalness,
    liveness,
    valence,
    tempo,
    time_signature
)
SELECT
    dt.track_surrogate_id,
    dal.album_id,
    dk.key_id,
    dm.mode_id,
    de.explicit_id,
    ps.selected_popularity,
    ps.popularity_min_observed,
    ps.popularity_max_observed,
    ps.popularity_avg_observed,
    ps.popularity_range,
    ps.popularity_conflict_flag,
    CAST(r.danceability AS DECIMAL(6,5)) AS danceability,
    CAST(r.energy AS DECIMAL(6,5)) AS energy,
    CAST(r.loudness AS DECIMAL(8,3)) AS loudness,
    CAST(r.speechiness AS DECIMAL(6,5)) AS speechiness,
    CAST(r.acousticness AS DECIMAL(6,5)) AS acousticness,
    CAST(r.instrumentalness AS DECIMAL(6,5)) AS instrumentalness,
    CAST(r.liveness AS DECIMAL(6,5)) AS liveness,
    CAST(r.valence AS DECIMAL(6,5)) AS valence,
    CAST(r.tempo AS DECIMAL(8,3)) AS tempo,
    CAST(r.time_signature AS UNSIGNED) AS time_signature
FROM tmp_track_representative AS r
INNER JOIN tmp_track_popularity_summary AS ps
    ON r.track_id = ps.track_id
INNER JOIN dim_track AS dt
    ON r.track_id = dt.track_id
INNER JOIN dim_album AS dal
    ON MD5(CONCAT_WS('||', TRIM(r.album_name), TRIM(r.artists))) = dal.album_key_hash
INNER JOIN dim_audio_key AS dk
    ON CAST(r.`key` AS SIGNED) = dk.key_code
INNER JOIN dim_mode AS dm
    ON CAST(r.mode AS UNSIGNED) = dm.mode_id
INNER JOIN dim_explicit AS de
    ON CASE
        WHEN LOWER(TRIM(r.explicit)) IN ('true', '1', 'yes') THEN 1
        ELSE 0
       END = de.explicit_id;

DROP TEMPORARY TABLE tmp_track_popularity_summary;
DROP TEMPORARY TABLE tmp_track_representative;

-- ------------------------------------------------------------
-- 12. Populate track/genre bridge
-- ------------------------------------------------------------
-- Genre remains a normalized many-to-many relation. The bridge is used when
-- a question needs genre context, but global popularity rankings should use
-- fact_track_metrics.selected_popularity so each track contributes once.

INSERT INTO bridge_track_genre (
    track_surrogate_id,
    genre_id,
    source_row_count
)
SELECT
    dt.track_surrogate_id,
    dg.genre_id,
    COUNT(*) AS source_row_count
FROM raw_spotify_tracks AS r
INNER JOIN dim_track AS dt
    ON r.track_id = dt.track_id
INNER JOIN dim_genre AS dg
    ON TRIM(r.track_genre) = dg.genre_name
GROUP BY dt.track_surrogate_id, dg.genre_id;

-- ------------------------------------------------------------
-- 13. Populate track/artist bridge
-- ------------------------------------------------------------

INSERT INTO bridge_track_artist (track_surrogate_id, artist_id)
SELECT DISTINCT
    dt.track_surrogate_id,
    da.artist_id
FROM raw_spotify_tracks AS r
INNER JOIN dim_track AS dt
    ON r.track_id = dt.track_id
INNER JOIN util_numbers AS n
    ON n.n <= 1 + LENGTH(r.artists) - LENGTH(REPLACE(r.artists, ';', ''))
INNER JOIN dim_artist AS da
    ON da.artist_name = TRIM(
        SUBSTRING_INDEX(
            SUBSTRING_INDEX(r.artists, ';', n.n),
            ';',
            -1
        )
    );

-- ------------------------------------------------------------
-- 14. Final audit row counts
-- ------------------------------------------------------------

INSERT INTO etl_run_log (step_name, rows_recorded)
SELECT 'dim_track_rows', COUNT(*)
FROM dim_track;

INSERT INTO etl_run_log (step_name, rows_recorded)
SELECT 'dim_artist_rows', COUNT(*)
FROM dim_artist;

INSERT INTO etl_run_log (step_name, rows_recorded)
SELECT 'dim_genre_rows', COUNT(*)
FROM dim_genre;

INSERT INTO etl_run_log (step_name, rows_recorded)
SELECT 'fact_track_metrics_rows', COUNT(*)
FROM fact_track_metrics;

INSERT INTO etl_run_log (step_name, rows_recorded)
SELECT 'bridge_track_genre_rows', COUNT(*)
FROM bridge_track_genre;

SET SQL_SAFE_UPDATES = 1;
