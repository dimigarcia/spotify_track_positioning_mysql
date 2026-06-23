# Raw data

This folder contains the original Spotify Tracks Dataset CSV used by the project:

`spotify_tracks.csv`

Original data source:

https://www.kaggle.com/datasets/maharshipandya/-spotify-tracks-dataset

The source CSV is kept for traceability. The executable import used in MySQL Workbench is `sql/02_import_raw_data.sql`, which contains batched `INSERT` statements generated programmatically from this CSV. The generator is included at `tools/generate_raw_import_sql.py`.

During conversion, the first CSV column, exported as a blank index column, is mapped to `source_row_id` in the SQL staging table `raw_spotify_tracks`.
