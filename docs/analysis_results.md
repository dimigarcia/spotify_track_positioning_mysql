# Observed analytical results

These results were computed from the Spotify CSV and are used to interpret the SQL EDA outputs.

## EDA question structure

The results below correspond to the current `sql/04_eda.sql` structure. The EDA begins with model and data-quality checks, then runs 12 analytical queries:

1. Final track-level popularity baseline.
2. Highest selected-popularity tracks overall.
3. Artists combining high average popularity with catalogue depth.
4. Best-performing album-credit contexts.
5. Playlist strategy buckets with higher selected popularity.
6. Availability of selected genres of interest in the source data.
7. Audio attributes distinguishing top-quartile tracks inside selected genres.
8. Audio attributes carrying the clearest popularity signal inside selected genres.
9. Genres where typicality or distinctiveness is more associated with popularity.
10. Selected-genre tracks that look under-positioned for playlist discovery.
11. Explicit-content patterns within selected genres.
12. Relationship between genre-label coverage and selected popularity.

## Data-quality and model results

| Check | Observed result |
|---|---:|
| Raw CSV rows | 114,000 |
| Rows after duplicate `track_id + genre` cleanup | 113,550 |
| Unique `track_id` values / fact rows | 89,741 |
| Track-genre bridge rows | 113,550 |
| Repeated `track_id + genre` groups | 444 |
| Excess repeated rows removed | 450 |
| Tracks appearing in more than one genre | 16,299 |
| Maximum genres attached to one track | 9 |
| Multi-genre tracks with different non-genre, non-popularity attributes | 0 |
| Multi-genre tracks with different popularity values | 720 |
| Tracks with popularity range of at least 5 points | 21 |
| Maximum popularity range for the same track | 44 |
| Album names associated with multiple artist-credit strings | 5,128 |

The attribute audit supports a track-level fact table for audio metrics. Popularity conflicts across repeated track rows are rare: 720 of 89,741 tracks have more than one observed popularity value, and most of those conflicts differ by only one point on the 0-100 scale. Some larger conflicts include suspicious zero values in one genre row while another genre row has a plausible non-zero value. For this reason, the project uses `MAX(popularity)` as the selected track-level popularity value and retains minimum, maximum, average, range and conflict-flag fields for auditability.

## Track-level popularity baseline

| Metric | Observed result |
|---|---:|
| Unique tracks | 89,741 |
| Average selected popularity | 33.21 |
| Minimum selected popularity | 0 |
| Maximum selected popularity | 100 |
| Tracks with popularity conflicts before aggregation | 720 |

Global popularity rankings are based on `fact_track_metrics.selected_popularity` through `vw_track_profile`, so each Spotify `track_id` appears at most once in track, artist, album and playlist-ranking outputs.

## Selected genre availability

Shoegaze is absent from the source genre labels. The selected-genre analysis therefore keeps shoegaze as a source-coverage check and analyses available music genres including IDM, ambient, trip-hop, psych-rock, industrial, breakbeat, indie, indie-pop, synth-pop, electronic, k-pop, pop-film, grunge, world-music, classical, j-pop, blues, funk and hip-hop.

## Correlation-based attribute relevance

Within selected genres, the strongest exploratory correlations between individual audio attributes and selected popularity are moderate rather than strong. Examples include:

| Genre | Attribute | Pearson r |
|---|---|---:|
| world-music | instrumentalness | -0.480 |
| classical | energy | 0.410 |
| j-pop | energy | 0.397 |
| blues | acousticness | -0.371 |
| k-pop | loudness | 0.359 |
| funk | danceability | 0.330 |
| hip-hop | acousticness | 0.277 |
| breakbeat | danceability | -0.248 |
| psych-rock | valence | -0.222 |
| trip-hop | valence | -0.198 |

These correlations help identify which audio attributes carry the clearest popularity signal within each selected genre. The pattern is useful for exploratory positioning: for example, popularity in classical and j-pop is most aligned with energy, while popularity in world-music and blues is more strongly associated with lower instrumentalness or acousticness.

## Genre typicality and popularity

The typicality analysis compares each track to the average audio profile of its genre. Higher typicality means a track is closer to the genre's average profile across danceability, energy, loudness, speechiness, acousticness, instrumentalness, liveness, valence and tempo.

Top positive typicality-popularity associations include:

| Genre | Typicality-popularity r |
|---|---:|
| world-music | 0.474 |
| pagode | 0.270 |
| dub | 0.235 |
| pop-film | 0.222 |
| british | 0.205 |

Top negative typicality-popularity associations include:

| Genre | Typicality-popularity r |
|---|---:|
| classical | -0.367 |
| jazz | -0.179 |
| reggae | -0.164 |
| opera | -0.152 |
| edm | -0.147 |

The result suggests a genre-specific positioning pattern. In some contexts, popularity is higher for tracks close to the genre's average audio profile; in others, popularity is higher for tracks that remain inside the genre label while sounding more distinctive from the genre centre.

## Genre coverage and selected popularity

The one-row-per-track view reports how many genre labels are attached to each track. This allows genre coverage to be analysed without duplicating tracks in the popularity ranking.

| Genre labels per track | Unique tracks | Avg selected popularity | Min | Max |
|---:|---:|---:|---:|---:|
| 1 | 73,442 | 32.46 | 0 | 99 |
| 2 | 11,424 | 39.06 | 0 | 100 |
| 3 | 2,955 | 35.06 | 0 | 98 |
| 4 | 1,361 | 26.65 | 0 | 98 |
| 5 | 431 | 14.43 | 0 | 89 |
| 6 | 104 | 27.89 | 0 | 90 |
| 7 | 21 | 25.00 | 0 | 70 |
| 8 | 2 | 37.00 | 0 | 74 |
| 9 | 1 | 67.00 | 67 | 67 |

Tracks with two or three genre labels have higher average selected popularity than tracks with one genre label. This suggests that moderate cross-genre coverage may be associated with broader catalogue positioning. Tracks with very high genre counts are rare, so the clearest comparison is between one, two and three genre labels.
