# Observed analytical results

These results were computed from the Spotify CSV and are used to interpret the SQL EDA outputs. The related modelling choices are documented in `docs/data_quality_and_model_decisions.md`, including the duplicate checks, repeated-track audit, selected-popularity rule and bridge-table structure.

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

The quality checks support the final model structure. Redundant repeated `track_id + genre` rows are removed, but genuine multi-genre relationships are preserved through `bridge_track_genre`. After duplicate cleanup, repeated tracks across genres do not differ in their audio attributes or core metadata. Popularity is the only field that sometimes varies for the same track across genre rows.

Popularity conflicts are rare: 720 of 89,741 tracks have more than one observed popularity value, and most conflicts are small relative to the 0-100 scale. Some larger conflicts include suspicious zero values in one genre row while another genre row has a plausible non-zero value. For this reason, the project uses `MAX(popularity)` as `selected_popularity` and retains minimum, maximum, average, range and conflict-flag fields for auditability.

## Q1. Final track-level popularity baseline

| Metric | Observed result |
|---|---:|
| Unique tracks | 89,741 |
| Average selected popularity | 33.21 |
| Minimum selected popularity | 0 |
| Maximum selected popularity | 100 |
| Average popularity range after track aggregation | 0.014 |
| Tracks with popularity conflicts before aggregation | 720 |

Global popularity analysis is based on `fact_track_metrics.selected_popularity`, exposed through `vw_track_profile`. This ensures that each Spotify `track_id` contributes once to global rankings, artist summaries, album summaries and playlist bucket analysis.

## Q2. Highest selected-popularity tracks overall

| Track | Artist credit | Genre list | Selected popularity |
|---|---|---|---:|
| Unholy (feat. Kim Petras) | Kim Petras; Sam Smith | dance; pop | 100 |
| Quevedo: Bzrp Music Sessions, Vol. 52 | Bizarrap; Quevedo | hip-hop | 99 |
| I'm Good (Blue) | Bebe Rexha; David Guetta | dance; edm; pop | 98 |
| La Bachata | Manuel Turizo | latin; latino; reggae; reggaeton | 98 |
| Me Porto Bonito | Bad Bunny; Chencho Corleone | latin; latino; reggae; reggaeton | 97 |
| Tití Me Preguntó | Bad Bunny | latin; latino; reggae; reggaeton | 97 |
| Efecto | Bad Bunny | latin; latino; reggae; reggaeton | 96 |
| I Ain't Worried | OneRepublic | piano; pop; rock | 96 |
| Under The Influence | Chris Brown | dance; pop | 96 |
| As It Was | Harry Styles | pop | 95 |

The highest track-level popularity rankings are dominated by mainstream pop, dance, Latin/reggaeton and hip-hop crossover material. Bad Bunny appears repeatedly near the top, especially through tracks linked to Latin, reggae and reggaeton labels.

## Q3. Artists combining high average popularity with catalogue depth

This query only includes artists with at least five unique tracks, so it does not simply rank artists who appear once with one very popular song.

| Artist | Unique tracks | Avg selected popularity | Max selected popularity | Genre count |
|---|---:|---:|---:|---:|
| Olivia Rodrigo | 5 | 87.40 | 88 | 1 |
| One Direction | 5 | 83.00 | 88 | 1 |
| Lil Nas X | 8 | 82.75 | 90 | 2 |
| Måneskin | 5 | 82.60 | 86 | 3 |
| Mora | 6 | 80.33 | 89 | 3 |
| Mitski | 6 | 78.33 | 83 | 2 |
| Shubh | 5 | 77.80 | 83 | 1 |
| Frank Ocean | 21 | 74.14 | 85 | 4 |
| Limp Bizkit | 6 | 73.83 | 77 | 3 |
| Radiohead | 11 | 73.55 | 85 | 4 |

The artist-level results show that high average popularity is not limited to artists with very large catalogues in the dataset. Olivia Rodrigo and One Direction rank highest with five tracks each, while Frank Ocean, Radiohead and The Neighbourhood combine stronger catalogue depth with high average selected popularity.

## Q4. Best-performing album-credit contexts

The album analysis groups by album name and artist-credit text because album titles alone are not unique in the source data.

| Album name | Album artist text | Unique tracks | Avg selected popularity | Max selected popularity |
|---|---|---:|---:|---:|
| Un Verano Sin Ti | Bad Bunny | 13 | 88.08 | 97 |
| SOUR | Olivia Rodrigo | 5 | 87.40 | 88 |
| YHLQMDLG | Bad Bunny | 5 | 80.60 | 83 |
| WHEN WE ALL FALL ASLEEP, WHERE DO WE GO? | Billie Eilish | 5 | 78.00 | 84 |
| AM | Arctic Monkeys | 12 | 77.33 | 92 |
| 17 | XXXTENTACION | 7 | 76.29 | 87 |
| Cry Baby (Deluxe Edition) | Melanie Martinez | 6 | 76.17 | 80 |
| dont smile at me | Billie Eilish | 6 | 76.17 | 81 |
| Happier Than Ever | Billie Eilish | 9 | 76.11 | 88 |
| Back In Black | AC/DC | 5 | 75.40 | 85 |

`Un Verano Sin Ti` is the strongest album-credit context among albums with at least five tracks, combining 13 unique tracks with an average selected popularity of 88.08. `SOUR` also performs very strongly, matching the artist-level result for Olivia Rodrigo.

## Q5. Playlist strategy buckets with higher selected popularity

| Playlist strategy | Unique tracks | Avg selected popularity | Min | Max |
|---|---:|---:|---:|---:|
| General playlist | 25,072 | 35.34 | 0 | 99 |
| Sad / introspective | 19,272 | 34.44 | 0 | 100 |
| Upbeat / feel-good | 10,674 | 33.20 | 0 | 98 |
| Party / high-energy | 14,096 | 32.32 | 0 | 97 |
| Acoustic / calm | 17,677 | 30.26 | 0 | 94 |
| Focus / instrumental | 2,950 | 28.97 | 0 | 84 |

The highest average selected popularity is in the broad `General playlist` bucket, followed by `Sad / introspective`. This suggests that the simple playlist strategy segmentation does not reduce popularity to only high-energy or upbeat tracks. More general or emotionally oriented catalogue positions can also carry relatively high popularity.

## Q6. Availability of selected genres of interest

| Genre | Source status | Unique tracks | Avg selected popularity |
|---|---|---:|---:|
| pop-film | Available | 999 | 59.28 |
| k-pop | Available | 999 | 56.92 |
| grunge | Available | 999 | 49.58 |
| electronic | Available | 1,000 | 44.33 |
| ambient | Available | 999 | 44.21 |
| psych-rock | Available | 996 | 42.90 |
| world-music | Available | 999 | 41.89 |
| j-pop | Available | 998 | 41.23 |
| indie-pop | Available | 1,000 | 40.67 |
| indie | Available | 997 | 39.31 |
| hip-hop | Available | 991 | 38.10 |
| synth-pop | Available | 1,000 | 36.59 |
| trip-hop | Available | 997 | 34.51 |
| funk | Available | 1,000 | 32.33 |
| blues | Available | 998 | 31.22 |
| industrial | Available | 1,000 | 31.04 |
| breakbeat | Available | 999 | 20.13 |
| idm | Available | 998 | 15.76 |
| classical | Available | 933 | 13.52 |
| shoegaze | Absent | 0 | — |

`shoegaze` is absent from the source genre labels. The selected-genre analysis therefore keeps shoegaze as a source-coverage check and analyses only the available genre labels. Within the selected genres, `pop-film`, `k-pop` and `grunge` have the highest average selected popularity, while `classical`, `idm` and `breakbeat` are much lower in this dataset.

## Q7. Audio attributes distinguishing top-quartile tracks inside selected genres

The top-quartile comparison shows how the most popular tracks within each selected genre differ from the lower three quartiles. The table below reports selected examples where the top-quartile tracks show clear audio-profile differences.

| Genre | Top-quartile avg popularity | Lower-quartile avg popularity | Main observed difference in top quartile |
|---|---:|---:|---|
| classical | 41.93 | 4.06 | Much higher energy (+0.242), lower instrumentalness (-0.399), lower acousticness (-0.137) |
| k-pop | 73.83 | 51.30 | Higher energy (+0.093), much lower acousticness (-0.219) |
| world-music | 55.06 | 37.51 | Lower instrumentalness (-0.116), lower acousticness (-0.116), slightly higher energy (+0.048) |
| blues | 66.15 | 19.61 | Lower acousticness (-0.119), lower valence (-0.073), higher tempo (+6.69 BPM) |
| indie | 74.52 | 27.58 | Higher instrumentalness (+0.088), lower acousticness (-0.058), lower valence (-0.057) |
| breakbeat | 40.45 | 13.38 | Lower danceability (-0.077), lower valence (-0.105), slightly higher energy (+0.018) |

The strongest differences are not the same across genres. In classical, top-quartile tracks are much more energetic and less instrumental than the lower three quartiles. In k-pop, the top quartile is also more energetic and much less acoustic. In world-music, the top quartile is less instrumental and less acoustic. This reinforces the genre-specific structure of the EDA.

## Q8. Audio attributes carrying the clearest popularity signal inside selected genres

| Genre | Attribute | N | Pearson r |
|---|---|---:|---:|
| world-music | instrumentalness | 999 | -0.480 |
| classical | energy | 933 | 0.410 |
| j-pop | energy | 998 | 0.397 |
| blues | acousticness | 998 | -0.371 |
| k-pop | loudness | 999 | 0.359 |
| funk | danceability | 1,000 | 0.330 |
| hip-hop | acousticness | 991 | 0.277 |
| breakbeat | danceability | 999 | -0.248 |
| psych-rock | valence | 996 | -0.222 |
| trip-hop | valence | 997 | -0.198 |
| indie | valence | 997 | -0.193 |
| indie-pop | instrumentalness | 1,000 | 0.191 |
| pop-film | liveness | 999 | -0.164 |
| industrial | instrumentalness | 1,000 | -0.156 |
| grunge | liveness | 999 | -0.138 |
| ambient | instrumentalness | 999 | -0.124 |
| electronic | valence | 1,000 | -0.096 |
| synth-pop | tempo | 1,000 | -0.086 |
| idm | danceability | 998 | 0.073 |

The correlation results do not suggest one universal popularity formula. Instead, the strongest attribute-popularity relationship changes by genre. For example, popularity in `classical` and `j-pop` is most aligned with energy, while popularity in `world-music` is most strongly associated with lower instrumentalness. In `funk`, danceability carries the clearest positive signal, while in `k-pop`, loudness is the clearest selected-genre signal.

## Q9. Genres where typicality or distinctiveness is more associated with popularity

The typicality analysis compares each track to the average audio profile of its genre. Higher typicality means a track is closer to the genre's average profile across danceability, energy, loudness, speechiness, acousticness, instrumentalness, liveness, valence and tempo.

Top positive typicality-popularity associations:

| Genre | N | Typicality-popularity r |
|---|---:|---:|
| world-music | 999 | 0.474 |
| pagode | 1,000 | 0.270 |
| dub | 999 | 0.235 |
| pop-film | 999 | 0.222 |
| british | 1,000 | 0.205 |

Top negative typicality-popularity associations:

| Genre | N | Typicality-popularity r |
|---|---:|---:|
| classical | 933 | -0.367 |
| jazz | 999 | -0.179 |
| reggae | 1,000 | -0.164 |
| opera | 992 | -0.152 |
| edm | 993 | -0.147 |

The typicality result is one of the clearest positioning findings. In `world-music`, `pagode`, `dub`, `pop-film` and `british`, tracks closer to the genre's average audio profile are more popular. In `classical`, `jazz`, `reggae`, `opera` and `edm`, the relationship is negative, suggesting that more distinctive tracks perform better within those genre labels.

## Q10. Selected-genre tracks that look under-positioned for playlist discovery

This query looks for tracks with strong playlist-momentum scores but below-average selected popularity within their genre. The score is the average of danceability, energy and valence.

| Genre | Track | Artist credit | Selected popularity | Genre avg popularity | Momentum score |
|---|---|---|---:|---:|---:|
| breakbeat | Giant | The Chemical Brothers | 11 | 20.13 | 0.925 |
| trip-hop | Koito Oie Biera - Palov feat. Angelos Angelides Remix | Angelos Angelides; Mo' Horizons; Palov | 19 | 34.51 | 0.914 |
| electronic | Daft Punk Is Playing at My House | LCD Soundsystem | 0 | 44.33 | 0.913 |
| synth-pop | Dance Floor (Single Version) | Zapp | 23 | 36.59 | 0.913 |
| synth-pop | Freedom of Choice - 2009 Remaster | DEVO | 25 | 36.59 | 0.909 |
| breakbeat | Come Alive (feat. Dr. Luke) | A.Skillz; Dr. Luke; Krafty Kuts | 13 | 20.13 | 0.907 |
| breakbeat | London Sound | Freestylers | 16 | 20.13 | 0.904 |
| k-pop | Da Da Da - Remix by Mikis | Mikis; Tanir; Tyomcha | 54 | 56.92 | 0.903 |
| breakbeat | Life Gets Better | Ed Solo; Skool Of Thought | 10 | 20.13 | 0.896 |
| breakbeat | Masterplan (feat. Dynamite MC) | Dynamite MC; Krafty Kuts | 14 | 20.13 | 0.894 |

The discovery-candidate query surfaces tracks with accessible audio profiles but lower-than-average popularity inside their genre. `Giant` by The Chemical Brothers is the clearest example in the output: it has very high playlist momentum but selected popularity below the breakbeat average. Other notable examples include LCD Soundsystem, Zapp, DEVO, Freestylers and Krafty Kuts-related tracks.

## Q11. Explicit-content patterns within selected genres

| Genre | Explicit label | Track-genre rows | Avg selected popularity |
|---|---|---:|---:|
| funk | Explicit | 304 | 43.15 |
| funk | Not explicit | 696 | 27.60 |
| grunge | Explicit | 72 | 50.68 |
| grunge | Not explicit | 927 | 49.50 |
| hip-hop | Not explicit | 677 | 44.81 |
| hip-hop | Explicit | 314 | 23.64 |
| indie | Explicit | 84 | 45.32 |
| indie | Not explicit | 913 | 38.75 |
| indie-pop | Explicit | 107 | 49.77 |
| indie-pop | Not explicit | 893 | 39.58 |
| k-pop | Not explicit | 950 | 58.80 |
| k-pop | Explicit | 49 | 20.47 |
| pop-film | Explicit | 1 | 71.00 |
| pop-film | Not explicit | 998 | 59.27 |

Explicit-content patterns differ strongly by genre. In `funk`, `indie` and `indie-pop`, explicit tracks have higher average selected popularity than non-explicit tracks. In `hip-hop` and `k-pop`, the opposite pattern appears in this dataset, with non-explicit tracks showing higher average selected popularity. The `pop-film` explicit result is based on only one row, so it is not a stable comparison.

## Q12. Relationship between genre-label coverage and selected popularity

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

Tracks with two genre labels have the highest average selected popularity in this output, followed by tracks with three labels. The clearest comparison is between one-genre tracks and moderately cross-genre tracks: one-genre tracks average 32.46, while two-genre tracks average 39.06 and three-genre tracks average 35.06. Very high genre counts are rare, so those rows should not be interpreted as a stable trend.

## Discussion of main EDA findings

The strongest global popularity results are concentrated around mainstream crossover material. The top track rankings include `Unholy`, `Quevedo: Bzrp Music Sessions, Vol. 52`, `I'm Good (Blue)`, `La Bachata`, and several Bad Bunny tracks. The artist and album-credit summaries reinforce this pattern: Olivia Rodrigo, One Direction, Lil Nas X, Måneskin and Mora perform strongly among artists with at least five tracks, while `Un Verano Sin Ti` and `SOUR` stand out among album-credit contexts.

The selected-genre analysis shows that genre context matters. `pop-film`, `k-pop`, `grunge`, `electronic` and `ambient` have higher average selected popularity than more niche or specialist labels such as `idm`, `breakbeat` and `classical`. The absence of `shoegaze` is also informative because it limits what the dataset can support directly.

The audio-feature results do not point to a single catalogue-wide popularity formula. Instead, the attribute most associated with selected popularity changes by genre. `world-music` is most strongly associated with lower instrumentalness, `classical` and `j-pop` with higher energy, `k-pop` with loudness, and `funk` with danceability. These are moderate exploratory correlations, but they are useful because they show that track characteristics need to be interpreted inside genre contexts.

The typicality analysis adds a broader positioning interpretation. In `world-music`, `pagode`, `dub`, `pop-film` and `british`, tracks closer to the average genre audio profile are more popular. In `classical`, `jazz`, `reggae`, `opera` and `edm`, more distinctive tracks appear to perform better. This suggests that popularity can reflect either genre fit or differentiation, depending on the genre.

The discovery-candidate output makes the analysis more actionable. Tracks such as `Giant` by The Chemical Brothers and `Daft Punk Is Playing at My House` by LCD Soundsystem have strong playlist-style audio momentum but sit below their genre's average selected popularity. These tracks are not the most popular results, but they are useful catalogue-review candidates because their audio profile suggests playlist accessibility.

Finally, the genre-count query suggests that moderate cross-genre positioning is associated with broader reach. Tracks with two or three genre labels have higher average selected popularity than tracks with only one genre label. The pattern weakens for very high genre counts, where there are far fewer observations, so the most defensible interpretation is that moderate cross-genre classification is associated with higher selected popularity in this dataset.