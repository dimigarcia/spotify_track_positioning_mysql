-- ============================================================
-- 04_eda.sql
-- Spotify Track Positioning Analytics
-- MySQL 8.0 / MySQL Workbench
-- ============================================================
--
-- Purpose:
--   Run data-quality checks and analytical SQL queries.
--
-- Analytical convention:
--   Global rankings use vw_track_profile or fact_track_metrics so each track
--   appears once. Genre-specific questions use vw_track_genre_profile; in those
--   queries, a multi-genre track contributes once to each genre it belongs to.
-- ============================================================

USE spotify_track_positioning;

-- ============================================================
-- SECTION A. DATA-QUALITY AND MODEL-CHECK QUERIES
-- ============================================================

-- A1. ETL row-count log, including date/time functions.
SELECT
    step_name,
    rows_recorded,
    DATE(run_started_at) AS run_date,
    TIME(run_started_at) AS run_time
FROM etl_run_log
ORDER BY run_id;

-- A2. Main data-quality metrics.
SELECT
    metric_name,
    metric_value,
    metric_note,
    checked_at
FROM dq_quality_summary
ORDER BY metric_name;

-- A3. Repeated-track audit: verifies whether multi-genre rows are different songs
-- or repeated observations of the same track under different genre labels.
SELECT
    COUNT(*) AS multi_genre_tracks,
    MAX(genre_count) AS max_genres_for_one_track,
    SUM(CASE WHEN distinct_non_genre_attribute_versions > 1 THEN 1 ELSE 0 END)
        AS tracks_with_non_genre_attribute_differences,
    SUM(CASE WHEN distinct_popularity_values > 1 THEN 1 ELSE 0 END)
        AS tracks_with_popularity_differences,
    MAX(popularity_range) AS max_popularity_range,
    SUM(CASE WHEN popularity_range >= 5 THEN 1 ELSE 0 END)
        AS tracks_with_popularity_range_5_or_more
FROM dq_repeated_track_attribute_audit;

-- A4. Examples of repeated tracks where popularity varies across genre rows.
-- These rows support the decision to store a single selected popularity value
-- in the track-level fact table while retaining audit columns.
SELECT
    a.track_id,
    dt.track_name,
    a.genre_count,
    a.min_popularity,
    a.max_popularity,
    a.avg_popularity,
    a.popularity_range,
    GROUP_CONCAT(DISTINCT dg.genre_name ORDER BY dg.genre_name SEPARATOR '; ') AS genre_list
FROM dq_repeated_track_attribute_audit AS a
INNER JOIN dim_track AS dt
    ON a.track_id = dt.track_id
INNER JOIN bridge_track_genre AS btg
    ON dt.track_surrogate_id = btg.track_surrogate_id
INNER JOIN dim_genre AS dg
    ON btg.genre_id = dg.genre_id
WHERE a.distinct_popularity_values > 1
GROUP BY
    a.track_id,
    dt.track_name,
    a.genre_count,
    a.min_popularity,
    a.max_popularity,
    a.avg_popularity,
    a.popularity_range
ORDER BY a.popularity_range DESC, a.max_popularity DESC
LIMIT 20;

-- A5. Final table sizes.
SELECT
    'fact_track_metrics' AS table_name,
    COUNT(*) AS row_count
FROM fact_track_metrics
UNION ALL
SELECT 'bridge_track_genre', COUNT(*) FROM bridge_track_genre
UNION ALL
SELECT 'bridge_track_artist', COUNT(*) FROM bridge_track_artist
UNION ALL
SELECT 'dim_track', COUNT(*) FROM dim_track
UNION ALL
SELECT 'dim_artist', COUNT(*) FROM dim_artist
UNION ALL
SELECT 'dim_genre', COUNT(*) FROM dim_genre
UNION ALL
SELECT 'dim_album', COUNT(*) FROM dim_album;

-- A6. Referential-integrity check for high-popularity tracks and artist links.
SELECT
    COUNT(*) AS high_popularity_tracks_without_artist_links
FROM fact_track_metrics AS ftm
LEFT JOIN bridge_track_artist AS bta
    ON ftm.track_surrogate_id = bta.track_surrogate_id
WHERE ftm.selected_popularity >= 70
  AND bta.track_surrogate_id IS NULL;

-- ============================================================
-- SECTION B. ANALYTICAL EDA QUERIES
-- ============================================================

-- Q1. What is the final track-level popularity baseline?
-- Insight: the catalogue-level baseline is computed once per track, not once per
-- track/genre relation.
SELECT
    COUNT(*) AS unique_tracks,
    ROUND(AVG(selected_popularity), 2) AS avg_selected_popularity,
    MIN(selected_popularity) AS min_selected_popularity,
    MAX(selected_popularity) AS max_selected_popularity,
    ROUND(AVG(popularity_range), 3) AS avg_popularity_range_after_track_aggregation,
    SUM(popularity_conflict_flag) AS tracks_with_popularity_conflicts
FROM fact_track_metrics;

-- Q2. Which tracks have the highest selected popularity overall?
-- Insight: because this query uses vw_track_profile, each Spotify track_id can
-- appear only once in the ranking.
SELECT
    track_id,
    track_name,
    artist_credit,
    genre_list,
    selected_popularity,
    popularity_band,
    popularity_range
FROM vw_track_profile
ORDER BY selected_popularity DESC, track_name
LIMIT 20;

-- Q3. Which artists combine high average popularity with catalogue depth?
-- Insight: artist averages are calculated across unique tracks, not repeated
-- track/genre rows.
SELECT
    artist_name,
    unique_tracks,
    avg_selected_popularity,
    max_selected_popularity,
    genre_count
FROM vw_artist_track_summary
WHERE unique_tracks >= 5
ORDER BY avg_selected_popularity DESC, unique_tracks DESC
LIMIT 20;

-- Q4. Which album-credit contexts perform best?
-- Insight: album title alone is not unique, so the album dimension uses
-- album_name + album_artist_text.
SELECT
    album_name,
    album_artist_text,
    COUNT(*) AS unique_tracks,
    ROUND(AVG(selected_popularity), 2) AS avg_selected_popularity,
    MAX(selected_popularity) AS max_selected_popularity
FROM vw_track_profile
GROUP BY album_name, album_artist_text
HAVING COUNT(*) >= 5
ORDER BY avg_selected_popularity DESC, unique_tracks DESC
LIMIT 20;

-- Q5. Which playlist strategy buckets show higher selected popularity?
-- Insight: playlist buckets are simple interpretable segments based on audio
-- features, useful for high-level catalogue positioning.
SELECT
    playlist_strategy,
    COUNT(*) AS unique_tracks,
    ROUND(AVG(selected_popularity), 2) AS avg_selected_popularity,
    MIN(selected_popularity) AS min_selected_popularity,
    MAX(selected_popularity) AS max_selected_popularity
FROM vw_track_profile
GROUP BY playlist_strategy
ORDER BY avg_selected_popularity DESC;

-- Q6. Which genres of interest are available in the source data?
-- Insight: shoegaze is kept as a source-coverage check. Genre analysis uses
-- available music genre labels rather than treating any genre as a substitute.
WITH selected_genres AS (
    SELECT 'shoegaze' AS genre_name, 'coverage_check' AS sample_reason UNION ALL
    SELECT 'idm', 'niche_or_experimental' UNION ALL
    SELECT 'ambient', 'niche_or_experimental' UNION ALL
    SELECT 'trip-hop', 'niche_or_experimental' UNION ALL
    SELECT 'psych-rock', 'niche_or_experimental' UNION ALL
    SELECT 'industrial', 'niche_or_experimental' UNION ALL
    SELECT 'breakbeat', 'niche_or_experimental' UNION ALL
    SELECT 'indie', 'music_genre_of_interest' UNION ALL
    SELECT 'indie-pop', 'music_genre_of_interest' UNION ALL
    SELECT 'synth-pop', 'music_genre_of_interest' UNION ALL
    SELECT 'electronic', 'music_genre_of_interest' UNION ALL
    SELECT 'k-pop', 'high_popularity_context' UNION ALL
    SELECT 'pop-film', 'high_popularity_context' UNION ALL
    SELECT 'grunge', 'high_popularity_context' UNION ALL
    SELECT 'world-music', 'attribute_relevance_context' UNION ALL
    SELECT 'classical', 'attribute_relevance_context' UNION ALL
    SELECT 'j-pop', 'attribute_relevance_context' UNION ALL
    SELECT 'blues', 'attribute_relevance_context' UNION ALL
    SELECT 'funk', 'attribute_relevance_context' UNION ALL
    SELECT 'hip-hop', 'attribute_relevance_context'
)
SELECT
    sg.genre_name,
    sg.sample_reason,
    CASE WHEN g.genre_id IS NULL THEN 'Absent from source labels'
         ELSE 'Available in source labels'
    END AS source_status,
    COUNT(DISTINCT v.track_id) AS unique_tracks,
    ROUND(AVG(v.selected_popularity), 2) AS avg_selected_popularity
FROM selected_genres AS sg
LEFT JOIN dim_genre AS g
    ON sg.genre_name = g.genre_name
LEFT JOIN vw_track_genre_profile AS v
    ON sg.genre_name = v.genre_name
GROUP BY sg.genre_name, sg.sample_reason, source_status
ORDER BY source_status DESC, avg_selected_popularity DESC;

-- Q7. Within selected genres, which attributes distinguish top-quartile tracks?
-- Insight: compares popular tracks against the rest inside each genre.
WITH selected_genres AS (
    SELECT 'idm' AS genre_name UNION ALL
    SELECT 'ambient' UNION ALL
    SELECT 'trip-hop' UNION ALL
    SELECT 'psych-rock' UNION ALL
    SELECT 'industrial' UNION ALL
    SELECT 'breakbeat' UNION ALL
    SELECT 'indie' UNION ALL
    SELECT 'indie-pop' UNION ALL
    SELECT 'synth-pop' UNION ALL
    SELECT 'electronic' UNION ALL
    SELECT 'k-pop' UNION ALL
    SELECT 'pop-film' UNION ALL
    SELECT 'grunge' UNION ALL
    SELECT 'world-music' UNION ALL
    SELECT 'classical' UNION ALL
    SELECT 'j-pop' UNION ALL
    SELECT 'blues' UNION ALL
    SELECT 'funk' UNION ALL
    SELECT 'hip-hop'
), genre_tracks AS (
    SELECT
        v.*,
        NTILE(4) OVER (
            PARTITION BY v.genre_name
            ORDER BY v.selected_popularity
        ) AS popularity_quartile
    FROM vw_track_genre_profile AS v
    INNER JOIN selected_genres AS sg
        ON v.genre_name = sg.genre_name
), attribute_summary AS (
    SELECT
        genre_name,
        CASE WHEN popularity_quartile = 4 THEN 'Top popularity quartile'
             ELSE 'Lower three quartiles'
        END AS popularity_group,
        COUNT(*) AS track_genre_rows,
        ROUND(AVG(selected_popularity), 2) AS avg_selected_popularity,
        ROUND(AVG(danceability), 3) AS avg_danceability,
        ROUND(AVG(energy), 3) AS avg_energy,
        ROUND(AVG(valence), 3) AS avg_valence,
        ROUND(AVG(acousticness), 3) AS avg_acousticness,
        ROUND(AVG(instrumentalness), 3) AS avg_instrumentalness,
        ROUND(AVG(tempo), 2) AS avg_tempo
    FROM genre_tracks
    GROUP BY genre_name, popularity_group
)
SELECT *
FROM attribute_summary
ORDER BY genre_name, popularity_group DESC;


-- Q8. In selected genres, which audio attribute carries the clearest popularity signal?
-- Insight:
--   This query identifies the audio attribute most strongly associated with
--   selected popularity inside each selected genre. It helps indicate whether
--   popularity in a genre is more closely aligned with energy, loudness,
--   acousticness, danceability or another track characteristic. For performance,
--   the query first materialises only the selected genres and required variables
--   into a temporary table, avoiding repeated scans of the heavier semantic view.

DROP TEMPORARY TABLE IF EXISTS tmp_selected_genre_tracks;

CREATE TEMPORARY TABLE tmp_selected_genre_tracks AS
SELECT
    dg.genre_name,
    ftm.selected_popularity,
    ftm.danceability,
    ftm.energy,
    ftm.loudness,
    ftm.speechiness,
    ftm.acousticness,
    ftm.instrumentalness,
    ftm.liveness,
    ftm.valence,
    ftm.tempo
FROM fact_track_metrics AS ftm
INNER JOIN bridge_track_genre AS btg
    ON ftm.track_surrogate_id = btg.track_surrogate_id
INNER JOIN dim_genre AS dg
    ON btg.genre_id = dg.genre_id
WHERE dg.genre_name IN (
    'idm', 'ambient', 'trip-hop', 'psych-rock', 'industrial', 'breakbeat',
    'indie', 'indie-pop', 'synth-pop', 'electronic', 'k-pop', 'pop-film',
    'grunge', 'world-music', 'classical', 'j-pop', 'blues', 'funk', 'hip-hop'
);

CREATE INDEX idx_tmp_selected_genre_tracks_genre
ON tmp_selected_genre_tracks (genre_name);

WITH attribute_names AS (
    SELECT 'danceability' AS attribute_name UNION ALL
    SELECT 'energy' UNION ALL
    SELECT 'loudness' UNION ALL
    SELECT 'speechiness' UNION ALL
    SELECT 'acousticness' UNION ALL
    SELECT 'instrumentalness' UNION ALL
    SELECT 'liveness' UNION ALL
    SELECT 'valence' UNION ALL
    SELECT 'tempo'
),
long_attributes AS (
    SELECT
        t.genre_name,
        a.attribute_name,
        CASE a.attribute_name
            WHEN 'danceability' THEN t.danceability
            WHEN 'energy' THEN t.energy
            WHEN 'loudness' THEN t.loudness
            WHEN 'speechiness' THEN t.speechiness
            WHEN 'acousticness' THEN t.acousticness
            WHEN 'instrumentalness' THEN t.instrumentalness
            WHEN 'liveness' THEN t.liveness
            WHEN 'valence' THEN t.valence
            WHEN 'tempo' THEN t.tempo
        END AS attribute_value,
        t.selected_popularity
    FROM tmp_selected_genre_tracks AS t
    CROSS JOIN attribute_names AS a
),
correlations AS (
    SELECT
        genre_name,
        attribute_name,
        COUNT(*) AS n,
        ROUND(
            (COUNT(*) * SUM(attribute_value * selected_popularity)
             - SUM(attribute_value) * SUM(selected_popularity))
            /
            NULLIF(
                SQRT(
                    (COUNT(*) * SUM(POW(attribute_value, 2)) - POW(SUM(attribute_value), 2))
                    *
                    (COUNT(*) * SUM(POW(selected_popularity, 2)) - POW(SUM(selected_popularity), 2))
                ),
                0
            ),
            3
        ) AS pearson_r
    FROM long_attributes
    GROUP BY genre_name, attribute_name
),
ranked AS (
    SELECT
        genre_name,
        attribute_name,
        n,
        pearson_r,
        ROW_NUMBER() OVER (
            PARTITION BY genre_name
            ORDER BY ABS(COALESCE(pearson_r, 0)) DESC
        ) AS attribute_rank
    FROM correlations
)
SELECT
    genre_name,
    attribute_name,
    n,
    pearson_r
FROM ranked
WHERE attribute_rank = 1
ORDER BY ABS(COALESCE(pearson_r, 0)) DESC, genre_name;

-- Q9. Which genres reward typicality, and which reward distinctiveness?
-- Insight:
--   Typicality is defined as closeness to the average audio profile of a genre.
--   Positive associations indicate genres where tracks closer to the genre's
--   audio centre tend to be more popular. Negative associations indicate genres
--   where tracks farther from the genre's average profile tend to perform better.
--   This gives a catalogue-positioning view of whether success is more linked
--   to fitting the genre profile or standing apart from it. Loudness and tempo
--   are divided by approximate scale ranges so they do not dominate the distance
--   score relative to the 0-1 audio-feature variables.
WITH genre_stats AS (
    SELECT
        genre_name,
        AVG(danceability) AS avg_danceability,
        AVG(energy) AS avg_energy,
        AVG(loudness) AS avg_loudness,
        AVG(speechiness) AS avg_speechiness,
        AVG(acousticness) AS avg_acousticness,
        AVG(instrumentalness) AS avg_instrumentalness,
        AVG(liveness) AS avg_liveness,
        AVG(valence) AS avg_valence,
        AVG(tempo) AS avg_tempo
    FROM vw_track_genre_profile
    WHERE genre_name NOT IN ('comedy', 'children', 'sleep')
    GROUP BY genre_name
), track_distance AS (
    SELECT
        v.genre_name,
        v.track_id,
        v.selected_popularity,
        SQRT(
            POW(v.danceability - gs.avg_danceability, 2) +
            POW(v.energy - gs.avg_energy, 2) +
            POW((v.loudness - gs.avg_loudness) / 60, 2) +
            POW(v.speechiness - gs.avg_speechiness, 2) +
            POW(v.acousticness - gs.avg_acousticness, 2) +
            POW(v.instrumentalness - gs.avg_instrumentalness, 2) +
            POW(v.liveness - gs.avg_liveness, 2) +
            POW(v.valence - gs.avg_valence, 2) +
            POW((v.tempo - gs.avg_tempo) / 200, 2)
        ) AS distance_from_genre_profile
    FROM vw_track_genre_profile AS v
    INNER JOIN genre_stats AS gs
        ON v.genre_name = gs.genre_name
), typicality AS (
    SELECT
        genre_name,
        track_id,
        selected_popularity,
        -1 * distance_from_genre_profile AS genre_typicality_score
    FROM track_distance
), correlations AS (
    SELECT
        genre_name,
        COUNT(*) AS n,
        ROUND(
            (COUNT(*) * SUM(genre_typicality_score * selected_popularity)
             - SUM(genre_typicality_score) * SUM(selected_popularity))
            /
            NULLIF(
                SQRT(
                    (COUNT(*) * SUM(POW(genre_typicality_score, 2)) - POW(SUM(genre_typicality_score), 2))
                    *
                    (COUNT(*) * SUM(POW(selected_popularity, 2)) - POW(SUM(selected_popularity), 2))
                ),
                0
            ),
            3
        ) AS typicality_popularity_r
    FROM typicality
    GROUP BY genre_name
), positive_rank AS (
    SELECT
        'Top positive typicality-popularity association' AS association_group,
        genre_name,
        n,
        typicality_popularity_r,
        ROW_NUMBER() OVER (ORDER BY typicality_popularity_r DESC) AS rank_in_group
    FROM correlations
    WHERE typicality_popularity_r > 0
), negative_rank AS (
    SELECT
        'Top negative typicality-popularity association' AS association_group,
        genre_name,
        n,
        typicality_popularity_r,
        ROW_NUMBER() OVER (ORDER BY typicality_popularity_r ASC) AS rank_in_group
    FROM correlations
    WHERE typicality_popularity_r < 0
)
SELECT association_group, rank_in_group, genre_name, n, typicality_popularity_r
FROM positive_rank
WHERE rank_in_group <= 5
UNION ALL
SELECT association_group, rank_in_group, genre_name, n, typicality_popularity_r
FROM negative_rank
WHERE rank_in_group <= 5
ORDER BY association_group, rank_in_group;

-- Q10. Which selected-genre tracks look under-positioned for playlist discovery?
-- Insight:
--   Tracks with strong danceability/energy/valence but below-genre-average
--   selected popularity may be useful discovery candidates. Because this is a
--   genre-contextual query, a multi-genre track can appear once for each selected
--   genre it belongs to.
WITH selected_genres AS (
    SELECT 'idm' AS genre_name UNION ALL SELECT 'ambient' UNION ALL SELECT 'trip-hop' UNION ALL
    SELECT 'psych-rock' UNION ALL SELECT 'industrial' UNION ALL SELECT 'breakbeat' UNION ALL
    SELECT 'indie' UNION ALL SELECT 'indie-pop' UNION ALL SELECT 'synth-pop' UNION ALL
    SELECT 'electronic' UNION ALL SELECT 'k-pop' UNION ALL SELECT 'pop-film' UNION ALL
    SELECT 'grunge' UNION ALL SELECT 'world-music' UNION ALL SELECT 'classical' UNION ALL
    SELECT 'j-pop' UNION ALL SELECT 'blues' UNION ALL SELECT 'funk' UNION ALL SELECT 'hip-hop'
), scored AS (
    SELECT
        v.*,
        ROUND((v.danceability + v.energy + v.valence) / 3, 3) AS playlist_momentum_score,
        AVG(v.selected_popularity) OVER (PARTITION BY v.genre_name) AS genre_avg_popularity
    FROM vw_track_genre_profile AS v
    INNER JOIN selected_genres AS sg
        ON v.genre_name = sg.genre_name
)
SELECT
    genre_name,
    track_name,
    artist_credit,
    selected_popularity,
    ROUND(genre_avg_popularity, 2) AS genre_avg_popularity,
    playlist_momentum_score,
    danceability,
    energy,
    valence
FROM scored
WHERE playlist_momentum_score >= 0.70
  AND selected_popularity < genre_avg_popularity
ORDER BY playlist_momentum_score DESC, selected_popularity ASC
LIMIT 30;

-- Q11. How does explicit content relate to selected popularity within selected genres?
-- Insight:
--   This query compares explicit and non-explicit tracks inside selected genres.
--   It helps identify where explicit content is more common among higher-
--   popularity tracks and where non-explicit tracks have the stronger average
--   popularity profile.
WITH selected_genres AS (
    SELECT 'k-pop' AS genre_name UNION ALL SELECT 'hip-hop' UNION ALL SELECT 'pop-film' UNION ALL
    SELECT 'grunge' UNION ALL SELECT 'indie' UNION ALL SELECT 'indie-pop' UNION ALL SELECT 'funk'
)
SELECT
    v.genre_name,
    v.explicit_label,
    COUNT(*) AS track_genre_rows,
    ROUND(AVG(v.selected_popularity), 2) AS avg_selected_popularity
FROM vw_track_genre_profile AS v
INNER JOIN selected_genres AS sg
    ON v.genre_name = sg.genre_name
GROUP BY v.genre_name, v.explicit_label
ORDER BY v.genre_name, avg_selected_popularity DESC;

-- Q12. Do tracks with broader genre coverage have higher selected popularity?
-- Insight:
--   This query checks whether tracks assigned to more genre labels tend to have
--   higher selected popularity. It is calculated from vw_track_profile, so each
--   track contributes once, regardless of how many genres it belongs to.
SELECT
    genre_count,
    COUNT(*) AS unique_tracks,
    ROUND(AVG(selected_popularity), 2) AS avg_selected_popularity,
    MIN(selected_popularity) AS min_selected_popularity,
    MAX(selected_popularity) AS max_selected_popularity
FROM vw_track_profile
GROUP BY genre_count
ORDER BY genre_count;
