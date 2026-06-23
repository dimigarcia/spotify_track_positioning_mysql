# Data-quality checks and model-design decisions

This document records the main checks and modelling choices behind the relational structure of the project. It complements the executable SQL scripts:

- `sql/03_data.sql` performs the cleaning, audit checks and dimensional-model build.
- `sql/04_eda.sql` reports the final quality checks and analytical queries.
- `docs/analysis_results.md` records the observed outputs used to interpret the project.

The purpose of this document is to make the reasoning behind the model explicit: why the project uses a track-level fact table, why genre and artist relations are stored through bridge tables, and how duplicate or repeated source rows are treated.

## 1. Source-data grain

The raw CSV is first loaded into `raw_spotify_tracks`, where each row corresponds to one source row from the Spotify Tracks Dataset. The raw table preserves the original catalogue-style data before cleaning or modelling decisions are applied.

Important source characteristics:

| Check | Observed result |
|---|---:|
| Raw source rows | 114,000 |
| Rows after duplicate `track_id + genre` cleanup | 113,550 |
| Unique Spotify `track_id` values | 89,741 |
| Final track-genre relations | 113,550 |
| Tracks appearing in more than one genre | 16,299 |
| Maximum genre labels attached to one track | 9 |

The source therefore does not have a simple one-row-per-track grain. Some tracks appear under more than one genre label, and some `track_id + genre` pairs are repeated redundantly.

## 2. Duplicate `track_id + genre` rows

The first duplicate check looks for repeated rows at the `track_id + genre` level. These are not interpreted as meaningful repeated observations, because they duplicate the same track under the same genre label.

Observed result:

| Check | Observed result |
|---|---:|
| Repeated `track_id + genre` groups | 444 |
| Source rows involved in those groups | 894 |
| Excess repeated rows removed | 450 |

Model decision:

Redundant repeated `track_id + genre` rows are removed before building the dimensional model. The deletion is done inside a transaction in `sql/03_data.sql`, and the duplicate groups are recorded in `dq_track_genre_duplicate_audit` before deletion. This preserves the audit trail while preventing repeated source rows from inflating genre-level analysis.

## 3. Repeated tracks across genres

After duplicate `track_id + genre` cleanup, the remaining repeated `track_id` rows mainly represent tracks attached to more than one genre label. These are not deleted, because the genre memberships are analytically useful.

The project audits whether repeated tracks differ in their non-genre attributes. The audit checks whether the same `track_id` has different values for metadata or audio variables across genre rows.

Observed result:

| Check | Observed result |
|---|---:|
| Tracks appearing in more than one genre | 16,299 |
| Multi-genre tracks with different non-genre, non-popularity attributes | 0 |
| Multi-genre tracks with different popularity values | 720 |
| Tracks with popularity range of at least 5 points | 21 |
| Maximum observed popularity range for one track | 44 |

Model decision:

The audit supports storing audio features and core track metadata once per track. Repeated genre rows do not require multiple fact records because the non-genre attributes are stable after duplicate cleanup.

Popularity is the only field that sometimes varies for the same track across genre rows. Since those conflicts are rare relative to the full track table, and many are small relative to the 0-100 popularity scale, the project stores one selected track-level popularity value while retaining audit fields.

## 4. Track-level fact table

The final fact table is `fact_track_metrics`, with one row per unique Spotify `track_id`.

This table stores:

- selected track-level popularity;
- popularity audit fields;
- numerical audio features;
- foreign keys to track, album, audio key, mode and explicit-content dimensions.

Model decision:

`fact_track_metrics` is track-level rather than track-genre-level. This avoids duplicating tracks in global rankings, artist summaries, album summaries and playlist-style analyses.

The project uses:

```sql
MAX(popularity) AS selected_popularity
```

for the selected track-level popularity value. This choice is used because averaging would be more affected by suspicious zero values in some repeated genre rows. The original popularity variation is not discarded: the model retains `popularity_min_observed`, `popularity_max_observed`, `popularity_avg_observed`, `popularity_range` and `popularity_conflict_flag`.

## 5. Genre bridge table

The final genre relation is stored in `bridge_track_genre`.

Model decision:

A separate bridge table is needed because the source contains many-to-many track-genre relationships: one track can belong to more than one genre, and one genre contains many tracks.

This means:

- global rankings should use `fact_track_metrics` or `vw_track_profile`, where each track appears once;
- genre-context analysis should use `bridge_track_genre` or `vw_track_genre_profile`, where a multi-genre track can contribute once to each genre it belongs to.

The `genre_list` shown in `vw_track_profile` is display-oriented. It is useful for reading results, but it is not used as the main analytical structure.

## 6. Artist bridge table

Artists are stored through `dim_artist` and `bridge_track_artist`.

Model decision:

The source artist field can contain multiple artists in one text string. Splitting this into a bridge table avoids storing multi-artist credits as a single unstructured analytical category. It also allows artist-level summaries to count unique tracks per artist.

## 7. Album dimension

The project uses `dim_album` with album name plus artist-credit text.

Observed result:

| Check | Observed result |
|---|---:|
| Album names associated with multiple artist-credit strings | 5,128 |

Model decision:

Album title alone is not treated as a reliable album identifier. Many album names are reused by different artists or releases, so `dim_album` uses the combination of `album_name` and `album_artist_text`, supported by `album_key_hash`, to reduce false merging of different album-credit contexts.

This does not claim to reconstruct official Spotify album IDs. The source dataset does not provide album IDs, so the model uses the most defensible album-credit key available from the supplied columns.

## 8. Raw, audit and analytical layers

The project deliberately separates raw, audit and analytical objects.

| Layer | Main objects | Purpose |
|---|---|---|
| Raw/staging | `raw_spotify_tracks` | Preserve source rows before modelling. |
| Audit/quality | `dq_quality_summary`, `dq_track_genre_duplicate_audit`, `dq_repeated_track_attribute_audit`, `dq_album_name_audit`, `etl_run_log` | Record checks, row counts and data-quality decisions. |
| Dimensional model | dimensions, bridges, `fact_track_metrics` | Store the clean relational structure used for analysis. |
| Business views | `vw_track_profile`, `vw_track_genre_profile`, `vw_artist_track_summary`, `vw_genre_audio_profile` | Provide readable analytical outputs over the relational model. |
| EDA | `sql/04_eda.sql` | Run documented data-quality checks and business-oriented analytical queries. |

This structure keeps the final model usable while preserving the evidence behind cleaning and modelling decisions.

## 9. Analytical convention

The EDA follows a consistent grain convention:

- Track-level questions use `fact_track_metrics` or `vw_track_profile`.
- Genre-context questions use `vw_track_genre_profile`.

This distinction is important. Without it, global popularity rankings would overcount multi-genre tracks. With the convention, global outputs are one-row-per-track, while genre outputs intentionally reflect genre memberships.

## 10. Limitations of the modelling choices

The project uses the strongest structure available from the supplied dataset, but the source does not include several identifiers or behavioural variables that would improve the model.

Main limitations:

- There is no official album ID in the source, so album modelling relies on album name plus artist-credit text.
- Popularity is an observed catalogue variable, not a stream count, sales figure or time-series outcome.
- The source does not include release dates, listener demographics, playlist placements, countries, marketing variables or historical popularity changes.
- Genre labels are source classifications. They are useful for exploratory positioning, but they should not be interpreted as complete or definitive genre taxonomies.

These limitations are why the EDA is framed as exploratory catalogue-positioning analysis rather than a causal model of music success.
