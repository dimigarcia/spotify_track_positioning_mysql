# Requirements checklist

| Requirement | Where addressed |
|---|---|
| Minimum 5 tables | `01_schema.sql`: 7 dimensions/bridge/fact plus raw and audit tables. |
| 1 fact table | `fact_track_metrics`, one row per unique `track_id`, with selected track-level popularity. |
| 4+ dimensions | `dim_track`, `dim_album`, `dim_artist`, `dim_genre`, `dim_audio_key`, `dim_mode`, `dim_explicit`. |
| PKs/FKs/constraints | `01_schema.sql`, with comments and `CHECK`, `UNIQUE`, PK and FK constraints. |
| Raw/staging layer | `raw_spotify_tracks`; loaded through `sql/02_import_raw_data.sql` using standard SQL `INSERT` statements. |
| Dimensional model | Dimension, bridge and fact tables populated in `03_data.sql`. |
| 2+ business views | `vw_track_profile`, `vw_track_genre_profile`, `vw_genre_audio_profile`, `vw_artist_track_summary`. |
| 8–12 analytical queries | `04_eda.sql`, Section B, Q1–Q12. |
| Data-quality validation | `dq_*` tables and Section A of `04_eda.sql`. |
| Null checks / updates | `03_data.sql`, initial quality summary and missing descriptive-field updates. |
| Duplicate checks | `dq_track_genre_duplicate_audit` and duplicate deletion in `03_data.sql`. |
| Type conversion | `CAST` in `03_data.sql` when loading the dimensional model. |
| Out-of-range checks | Popularity rollback safety check and fact-table `CHECK` constraints. |
| INSERT / UPDATE / DELETE | `03_data.sql`. |
| Date functions | `04_eda.sql`, ETL timestamp audit using `DATE()` and `TIME()`. |
| Aggregations | `COUNT`, `SUM`, `AVG`, `MIN`, `MAX` throughout `04_eda.sql`. |
| Subqueries | `03_data.sql` and `04_eda.sql`. |
| JOINs | Views and analytical queries use multiple `INNER` and `LEFT` joins. |
| CASE | Functions, data loading and EDA queries. |
| CTEs | Multiple chained CTEs in `04_eda.sql`. |
| Window functions | `ROW_NUMBER`, `NTILE`, and `ROW_NUMBER` rankings in `03_data.sql`/`04_eda.sql`. |
| Transactions | `03_data.sql` uses `START TRANSACTION`, `COMMIT`, and `ROLLBACK`. |
| Index | `idx_fact_selected_popularity`, `idx_bridge_genre`, `idx_fact_audio_profile`, `idx_bridge_artist`. |
| Function | `fn_popularity_band`, `fn_playlist_strategy`. |
| Model diagram | Screenshot in `docs/workbench_model_diagram.png`; Mermaid version in `docs/model_mermaid.md`. |
| README | `README.md`. |
