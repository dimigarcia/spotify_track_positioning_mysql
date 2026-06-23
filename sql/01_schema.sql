-- ============================================================
-- 01_schema.sql
-- Spotify Track Positioning Analytics
-- MySQL 8.0 / MySQL Workbench
-- ============================================================
--
-- Purpose:
--   Create the relational database structure from scratch.
--
-- Design summary:
--   raw_spotify_tracks      = staging table for the source CSV
--   dim_*                   = descriptive dimension tables
--   fact_track_metrics      = one row per unique Spotify track_id
--   bridge_track_genre      = many-to-many track/genre relation
--   bridge_track_artist     = many-to-many track/artist relation
--   dq_*                    = data-quality audit tables
--   vw_*                    = business views / semantic layer for EDA
-- ============================================================

DROP DATABASE IF EXISTS spotify_track_positioning;
CREATE DATABASE IF NOT EXISTS spotify_track_positioning
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE spotify_track_positioning;

-- ============================================================
-- RAW / STAGING LAYER
-- ============================================================
-- Mirrors the CSV structure. Business constraints are applied after
-- validation and type conversion in the dimensional model.

CREATE TABLE IF NOT EXISTS raw_spotify_tracks (
    source_row_id INT NOT NULL,
    track_id VARCHAR(32) NOT NULL,
    artists TEXT,
    album_name VARCHAR(300),
    track_name VARCHAR(600),
    popularity VARCHAR(10),
    duration_ms VARCHAR(20),
    explicit VARCHAR(10),
    danceability VARCHAR(20),
    energy VARCHAR(20),
    `key` VARCHAR(10),
    loudness VARCHAR(20),
    mode VARCHAR(10),
    speechiness VARCHAR(20),
    acousticness VARCHAR(20),
    instrumentalness VARCHAR(20),
    liveness VARCHAR(20),
    valence VARCHAR(20),
    tempo VARCHAR(20),
    time_signature VARCHAR(10),
    track_genre VARCHAR(50),
    PRIMARY KEY (source_row_id),
    INDEX idx_raw_track_genre (track_id, track_genre),
    INDEX idx_raw_genre (track_genre)
) ENGINE = InnoDB;

-- ============================================================
-- UTILITY AND AUDIT TABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS util_numbers (
    n INT NOT NULL PRIMARY KEY,
    CHECK (n BETWEEN 1 AND 50)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS etl_run_log (
    run_id INT NOT NULL AUTO_INCREMENT,
    step_name VARCHAR(120) NOT NULL,
    rows_recorded INT NULL,
    run_started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (run_id)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS dq_quality_summary (
    metric_name VARCHAR(120) NOT NULL,
    metric_value INT NOT NULL,
    metric_note VARCHAR(600) NULL,
    checked_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (metric_name)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS dq_track_genre_duplicate_audit (
    track_id VARCHAR(32) NOT NULL,
    track_genre VARCHAR(50) NOT NULL,
    duplicate_rows INT NOT NULL,
    distinct_substantive_versions INT NOT NULL,
    min_source_row_id INT NOT NULL,
    max_source_row_id INT NOT NULL,
    PRIMARY KEY (track_id, track_genre)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS dq_repeated_track_attribute_audit (
    track_id VARCHAR(32) NOT NULL,
    genre_count INT NOT NULL,
    distinct_non_genre_attribute_versions INT NOT NULL,
    distinct_popularity_values INT NOT NULL,
    min_popularity INT NULL,
    max_popularity INT NULL,
    avg_popularity DECIMAL(6,2) NULL,
    popularity_range INT NULL,
    treatment_note VARCHAR(600) NOT NULL,
    PRIMARY KEY (track_id)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS dq_album_name_audit (
    album_name VARCHAR(300) NOT NULL,
    distinct_artist_credits INT NOT NULL,
    treatment_note VARCHAR(600) NOT NULL,
    PRIMARY KEY (album_name)
) ENGINE = InnoDB;

-- ============================================================
-- DIMENSION TABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS dim_genre (
    genre_id INT NOT NULL AUTO_INCREMENT,
    genre_name VARCHAR(50) NOT NULL,
    PRIMARY KEY (genre_id),
    UNIQUE KEY uq_dim_genre_name (genre_name),
    CHECK (genre_name <> '')
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS dim_album (
    album_id INT NOT NULL AUTO_INCREMENT,
    album_name VARCHAR(300) NOT NULL,
    album_artist_text TEXT NOT NULL,
    album_key_hash CHAR(32) NOT NULL,
    PRIMARY KEY (album_id),
    UNIQUE KEY uq_dim_album_hash (album_key_hash),
    CHECK (album_name <> '')
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS dim_artist (
    artist_id INT NOT NULL AUTO_INCREMENT,
    artist_name VARCHAR(300) NOT NULL,
    PRIMARY KEY (artist_id),
    UNIQUE KEY uq_dim_artist_name (artist_name),
    CHECK (artist_name <> '')
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS dim_track (
    track_surrogate_id INT NOT NULL AUTO_INCREMENT,
    track_id VARCHAR(32) NOT NULL,
    track_name VARCHAR(600) NOT NULL,
    duration_ms INT NOT NULL,
    PRIMARY KEY (track_surrogate_id),
    UNIQUE KEY uq_dim_track_source_id (track_id),
    CHECK (track_id <> ''),
    CHECK (track_name <> ''),
    CHECK (duration_ms >= 0)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS dim_audio_key (
    key_id INT NOT NULL AUTO_INCREMENT,
    key_code TINYINT NOT NULL,
    key_name VARCHAR(20) NOT NULL,
    PRIMARY KEY (key_id),
    UNIQUE KEY uq_dim_audio_key_code (key_code),
    CHECK (key_code BETWEEN 0 AND 11)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS dim_mode (
    mode_id INT NOT NULL,
    mode_name VARCHAR(20) NOT NULL,
    PRIMARY KEY (mode_id),
    CHECK (mode_id IN (0, 1)),
    CHECK (mode_name IN ('Minor', 'Major'))
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS dim_explicit (
    explicit_id TINYINT NOT NULL,
    explicit_label VARCHAR(20) NOT NULL,
    PRIMARY KEY (explicit_id),
    CHECK (explicit_id IN (0, 1)),
    CHECK (explicit_label IN ('Not explicit', 'Explicit'))
) ENGINE = InnoDB;

-- ============================================================
-- FACT AND BRIDGE TABLES
-- ============================================================
-- fact_track_metrics stores one row per unique Spotify track_id.
-- selected_popularity is the track-level popularity value used for global
-- rankings. It is defined as MAX(popularity) across source rows for the same
-- track_id because repeated track rows sometimes contain suspicious zero values
-- in one genre while another genre row has a plausible non-zero value. The
-- original min/max/average/range are retained for auditability.
-- bridge_track_genre stores many-to-many track/genre membership only.

CREATE TABLE IF NOT EXISTS fact_track_metrics (
    fact_id BIGINT NOT NULL AUTO_INCREMENT,
    track_surrogate_id INT NOT NULL,
    album_id INT NOT NULL,
    key_id INT NOT NULL,
    mode_id INT NOT NULL,
    explicit_id TINYINT NOT NULL,
    selected_popularity INT NOT NULL,
    popularity_min_observed INT NOT NULL,
    popularity_max_observed INT NOT NULL,
    popularity_avg_observed DECIMAL(6,2) NOT NULL,
    popularity_range INT NOT NULL,
    popularity_conflict_flag TINYINT NOT NULL DEFAULT 0,
    danceability DECIMAL(6,5) NOT NULL,
    energy DECIMAL(6,5) NOT NULL,
    loudness DECIMAL(8,3) NOT NULL,
    speechiness DECIMAL(6,5) NOT NULL,
    acousticness DECIMAL(6,5) NOT NULL,
    instrumentalness DECIMAL(6,5) NOT NULL,
    liveness DECIMAL(6,5) NOT NULL,
    valence DECIMAL(6,5) NOT NULL,
    tempo DECIMAL(8,3) NOT NULL,
    time_signature TINYINT NOT NULL,
    loaded_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (fact_id),
    UNIQUE KEY uq_fact_track (track_surrogate_id),
    CONSTRAINT fk_fact_track
        FOREIGN KEY (track_surrogate_id) REFERENCES dim_track(track_surrogate_id),
    CONSTRAINT fk_fact_album
        FOREIGN KEY (album_id) REFERENCES dim_album(album_id),
    CONSTRAINT fk_fact_key
        FOREIGN KEY (key_id) REFERENCES dim_audio_key(key_id),
    CONSTRAINT fk_fact_mode
        FOREIGN KEY (mode_id) REFERENCES dim_mode(mode_id),
    CONSTRAINT fk_fact_explicit
        FOREIGN KEY (explicit_id) REFERENCES dim_explicit(explicit_id),
    CHECK (selected_popularity BETWEEN 0 AND 100),
    CHECK (popularity_min_observed BETWEEN 0 AND 100),
    CHECK (popularity_max_observed BETWEEN 0 AND 100),
    CHECK (popularity_avg_observed BETWEEN 0 AND 100),
    CHECK (popularity_range BETWEEN 0 AND 100),
    CHECK (popularity_conflict_flag IN (0, 1)),
    CHECK (popularity_max_observed >= popularity_min_observed),
    CHECK (selected_popularity = popularity_max_observed),
    CHECK (danceability BETWEEN 0 AND 1),
    CHECK (energy BETWEEN 0 AND 1),
    CHECK (speechiness BETWEEN 0 AND 1),
    CHECK (acousticness BETWEEN 0 AND 1),
    CHECK (instrumentalness BETWEEN 0 AND 1),
    CHECK (liveness BETWEEN 0 AND 1),
    CHECK (valence BETWEEN 0 AND 1),
    CHECK (tempo >= 0),
    CHECK (time_signature BETWEEN 0 AND 5)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS bridge_track_genre (
    track_surrogate_id INT NOT NULL,
    genre_id INT NOT NULL,
    source_row_count INT NOT NULL DEFAULT 1,
    PRIMARY KEY (track_surrogate_id, genre_id),
    CONSTRAINT fk_bridge_genre_track
        FOREIGN KEY (track_surrogate_id) REFERENCES dim_track(track_surrogate_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_bridge_genre_genre
        FOREIGN KEY (genre_id) REFERENCES dim_genre(genre_id)
        ON DELETE CASCADE,
    CHECK (source_row_count >= 1)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS bridge_track_artist (
    track_surrogate_id INT NOT NULL,
    artist_id INT NOT NULL,
    PRIMARY KEY (track_surrogate_id, artist_id),
    CONSTRAINT fk_bridge_artist_track
        FOREIGN KEY (track_surrogate_id) REFERENCES dim_track(track_surrogate_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_bridge_artist_artist
        FOREIGN KEY (artist_id) REFERENCES dim_artist(artist_id)
        ON DELETE CASCADE
) ENGINE = InnoDB;

-- ============================================================
-- INDEXES
-- ============================================================
-- idx_fact_selected_popularity supports global track rankings.
-- idx_bridge_genre supports genre-level grouping and filtering.
-- idx_fact_audio_profile supports profile queries using energy, danceability and valence.
-- idx_bridge_artist supports artist joins.

CREATE INDEX idx_fact_selected_popularity
    ON fact_track_metrics (selected_popularity DESC);

CREATE INDEX idx_bridge_genre
    ON bridge_track_genre (genre_id, track_surrogate_id);

CREATE INDEX idx_fact_audio_profile
    ON fact_track_metrics (energy, danceability, valence);

CREATE INDEX idx_bridge_artist
    ON bridge_track_artist (artist_id, track_surrogate_id);

-- ============================================================
-- FUNCTIONS
-- ============================================================

DELIMITER //

CREATE FUNCTION fn_popularity_band(popularity_value INT)
RETURNS VARCHAR(30)
DETERMINISTIC
BEGIN
    RETURN CASE
        WHEN popularity_value >= 80 THEN 'Breakout / hit'
        WHEN popularity_value >= 60 THEN 'High'
        WHEN popularity_value >= 40 THEN 'Medium'
        WHEN popularity_value >= 20 THEN 'Low'
        ELSE 'Very low'
    END;
END//

CREATE FUNCTION fn_playlist_strategy(
    danceability_value DECIMAL(6,5),
    energy_value DECIMAL(6,5),
    valence_value DECIMAL(6,5),
    acousticness_value DECIMAL(6,5),
    instrumentalness_value DECIMAL(6,5)
)
RETURNS VARCHAR(40)
DETERMINISTIC
BEGIN
    RETURN CASE
        WHEN energy_value >= 0.70 AND danceability_value >= 0.65 THEN 'Party / high-energy'
        WHEN acousticness_value >= 0.60 AND energy_value < 0.50 THEN 'Acoustic / calm'
        WHEN instrumentalness_value >= 0.50 AND energy_value < 0.60 THEN 'Focus / instrumental'
        WHEN valence_value < 0.35 THEN 'Sad / introspective'
        WHEN valence_value >= 0.65 AND danceability_value >= 0.55 THEN 'Upbeat / feel-good'
        ELSE 'General playlist'
    END;
END//

DELIMITER ;

-- ============================================================
-- BUSINESS VIEWS / SEMANTIC LAYER
-- ============================================================

CREATE OR REPLACE VIEW vw_track_profile AS
SELECT
    ftm.track_surrogate_id,
    dt.track_id,
    dt.track_name,
    COALESCE(GROUP_CONCAT(DISTINCT da.artist_name ORDER BY da.artist_name SEPARATOR '; '), 'Unknown Artist') AS artist_credit,
    dal.album_name,
    dal.album_artist_text,
    COALESCE(GROUP_CONCAT(DISTINCT dg.genre_name ORDER BY dg.genre_name SEPARATOR '; '), 'Unknown Genre') AS genre_list,
    COUNT(DISTINCT dg.genre_id) AS genre_count,
    ftm.selected_popularity,
    fn_popularity_band(ftm.selected_popularity) AS popularity_band,
    ftm.popularity_min_observed,
    ftm.popularity_max_observed,
    ftm.popularity_avg_observed,
    ftm.popularity_range,
    ftm.popularity_conflict_flag,
    de.explicit_label,
    dk.key_name,
    dm.mode_name,
    ftm.danceability,
    ftm.energy,
    ftm.loudness,
    ftm.speechiness,
    ftm.acousticness,
    ftm.instrumentalness,
    ftm.liveness,
    ftm.valence,
    ftm.tempo,
    ftm.time_signature,
    fn_playlist_strategy(
        ftm.danceability,
        ftm.energy,
        ftm.valence,
        ftm.acousticness,
        ftm.instrumentalness
    ) AS playlist_strategy
FROM fact_track_metrics AS ftm
INNER JOIN dim_track AS dt
    ON ftm.track_surrogate_id = dt.track_surrogate_id
INNER JOIN dim_album AS dal
    ON ftm.album_id = dal.album_id
INNER JOIN dim_audio_key AS dk
    ON ftm.key_id = dk.key_id
INNER JOIN dim_mode AS dm
    ON ftm.mode_id = dm.mode_id
INNER JOIN dim_explicit AS de
    ON ftm.explicit_id = de.explicit_id
LEFT JOIN bridge_track_artist AS bta
    ON ftm.track_surrogate_id = bta.track_surrogate_id
LEFT JOIN dim_artist AS da
    ON bta.artist_id = da.artist_id
LEFT JOIN bridge_track_genre AS btg
    ON ftm.track_surrogate_id = btg.track_surrogate_id
LEFT JOIN dim_genre AS dg
    ON btg.genre_id = dg.genre_id
GROUP BY
    ftm.track_surrogate_id,
    dt.track_id,
    dt.track_name,
    dal.album_name,
    dal.album_artist_text,
    ftm.selected_popularity,
    ftm.popularity_min_observed,
    ftm.popularity_max_observed,
    ftm.popularity_avg_observed,
    ftm.popularity_range,
    ftm.popularity_conflict_flag,
    de.explicit_label,
    dk.key_name,
    dm.mode_name,
    ftm.danceability,
    ftm.energy,
    ftm.loudness,
    ftm.speechiness,
    ftm.acousticness,
    ftm.instrumentalness,
    ftm.liveness,
    ftm.valence,
    ftm.tempo,
    ftm.time_signature;

CREATE OR REPLACE VIEW vw_track_genre_profile AS
SELECT
    vp.track_surrogate_id,
    vp.track_id,
    vp.track_name,
    vp.artist_credit,
    vp.album_name,
    vp.album_artist_text,
    dg.genre_name,
    vp.genre_list,
    vp.genre_count,
    vp.selected_popularity,
    vp.popularity_band,
    vp.popularity_min_observed,
    vp.popularity_max_observed,
    vp.popularity_avg_observed,
    vp.popularity_range,
    vp.popularity_conflict_flag,
    vp.explicit_label,
    vp.key_name,
    vp.mode_name,
    vp.danceability,
    vp.energy,
    vp.loudness,
    vp.speechiness,
    vp.acousticness,
    vp.instrumentalness,
    vp.liveness,
    vp.valence,
    vp.tempo,
    vp.time_signature,
    vp.playlist_strategy
FROM vw_track_profile AS vp
INNER JOIN bridge_track_genre AS btg
    ON vp.track_surrogate_id = btg.track_surrogate_id
INNER JOIN dim_genre AS dg
    ON btg.genre_id = dg.genre_id;

CREATE OR REPLACE VIEW vw_genre_audio_profile AS
SELECT
    genre_name,
    COUNT(*) AS track_genre_rows,
    COUNT(DISTINCT track_id) AS unique_tracks,
    ROUND(AVG(selected_popularity), 2) AS avg_selected_popularity,
    ROUND(AVG(danceability), 3) AS avg_danceability,
    ROUND(AVG(energy), 3) AS avg_energy,
    ROUND(AVG(loudness), 2) AS avg_loudness,
    ROUND(AVG(acousticness), 3) AS avg_acousticness,
    ROUND(AVG(instrumentalness), 3) AS avg_instrumentalness,
    ROUND(AVG(valence), 3) AS avg_valence,
    ROUND(AVG(tempo), 2) AS avg_tempo
FROM vw_track_genre_profile
GROUP BY genre_name;

CREATE OR REPLACE VIEW vw_artist_track_summary AS
SELECT
    da.artist_id,
    da.artist_name,
    COUNT(DISTINCT ftm.track_surrogate_id) AS unique_tracks,
    ROUND(AVG(ftm.selected_popularity), 2) AS avg_selected_popularity,
    MAX(ftm.selected_popularity) AS max_selected_popularity,
    (
        SELECT COUNT(DISTINCT btg.genre_id)
        FROM bridge_track_artist AS bta2
        INNER JOIN bridge_track_genre AS btg
            ON bta2.track_surrogate_id = btg.track_surrogate_id
        WHERE bta2.artist_id = da.artist_id
    ) AS genre_count
FROM dim_artist AS da
INNER JOIN bridge_track_artist AS bta
    ON da.artist_id = bta.artist_id
INNER JOIN fact_track_metrics AS ftm
    ON bta.track_surrogate_id = ftm.track_surrogate_id
GROUP BY da.artist_id, da.artist_name;
