# Export a selection

Submits the selection as an export (`POST /exports`): the API writes
**every record** of the selection, up to
`limits$max_export_observations` observations (10,000,000;
[`soil_capabilities()`](https://giulange.github.io/soilhub-r/reference/soil_capabilities.md)),
into a zip of files, then keeps it for 7 days. Exports are the way to
large selections: the synchronous reads
([`soil_observations()`](https://giulange.github.io/soilhub-r/reference/soil_observations.md),
[`soil_features()`](https://giulange.github.io/soilhub-r/reference/soil_features.md))
are refused above `limits$max_sync_observations` (1,000,000). Rule of
thumb: size the selection with
[`soil_summary()`](https://giulange.github.io/soilhub-r/reference/soil_summary.md);
below about 200,000 observations read synchronously, above it export (a
whole-WoSIS wide CSV export takes about 9 minutes on the server, 88 MB
zipped). Exports also give GeoPackage and Shapefile files for GIS.

## Usage

``` r
soil_export(
  soil = soil_session(),
  datasets = NULL,
  variables = NULL,
  bbox = NULL,
  country = NULL,
  geometry = "any",
  layer = "all",
  view = "raw",
  profile_type = NULL,
  components = NULL,
  min_cumulative_percent = NULL,
  format = c("gpkg", "geojson", "csv", "tsv", "shp"),
  content = c("all", "features"),
  layout = c("wide", "long"),
  wait = TRUE,
  timeout = 3600,
  poll = 5,
  download = wait,
  dir = NULL,
  unzip = TRUE,
  progress = interactive()
)
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

- datasets:

  Catalog dataset codes (`"wosis_points"`, `"wise_profiles"`,
  `"soter_profiles"`, `"soter_polygons"`, `"sotwis_polygons"`,
  `"sotwis_components"`, `"sotwis_estimates"`, see
  [`soil_datasets()`](https://giulange.github.io/soilhub-r/reference/soil_datasets.md));
  `NULL` (the API default) selects every dataset, usually above the
  limit of synchronous reads. API field `datasets`.

- variables:

  Source codes (`"ORGC"`, `"CLAY"`) or canonical property keys
  (`"organic_carbon"`), see
  [`soil_variables()`](https://giulange.github.io/soilhub-r/reference/soil_variables.md);
  `NULL` returns every variable. With `variables` the column set is
  fixed by the request, so every page has the same columns. API field
  `variables`.

- bbox:

  `c(xmin, ymin, xmax, ymax)` in WGS84 degrees (longitude, latitude).
  API field `bbox`.

- country:

  Countries as ISO 3166 alpha-2 or alpha-3 codes or names,
  case-insensitive (the API resolves them). API field `country`.

- geometry:

  `"any"`, `"point"` (profiles) or `"polygon"` (map units). API field
  `geometry`.

- layer:

  `"all"` horizons, or `"first"`: the first horizon(s) of each profile
  with `first_layer_status` and `profile_markings` (see
  [`soil_first_layer()`](https://giulange.github.io/soilhub-r/reference/soil_first_layer.md)).
  API field `layer`.

- view:

  `"raw"`: the ISRIC mirror as stored (sent explicitly); `"revised"`:
  the decided rules of the revised view applied by the API in the
  response (see
  [`soil_revised_rules()`](https://giulange.github.io/soilhub-r/reference/soil_revised_rules.md)).
  API field `view`.

- profile_type:

  Profiles by the source's own type term: `"synthetic"` (KENSOTER),
  `"virtual"` (Upper Tana), `"none"` (no type in the source record), all
  selecting or all excluded with a `"!"` prefix
  (`c("!synthetic", "!virtual")`); `NULL` keeps every profile. API field
  `profile_type`.

- components:

  Components of multi-component map units (SOTWIS, SOTER polygons):
  `NULL` (the API default, `"representative"`), `"representative"`
  (largest `proportion_percent`), `"all"`, or `"cumulative"` (by
  decreasing proportion until `min_cumulative_percent`). API field
  `components`.

- min_cumulative_percent:

  Threshold of `components = "cumulative"`, 0 to 100 (required with it,
  refused without it). API field `min_cumulative_percent`.

- format:

  File format: `"gpkg"` (GeoPackage, the default), `"geojson"`, `"csv"`,
  `"tsv"`, or `"shp"` (Shapefile: only with `content = "features"`). The
  formats are those of `soil_capabilities()$exports`. API field
  `format`.

- content:

  `"all"` (the features and their observations) or `"features"` (the
  features only). API field `content`.

- layout:

  Shape of the observations table: `"wide"` (one row per horizon) or
  `"long"` (one row per observation); not sent with
  `content = "features"`. API field `layout`.

- wait:

  Wait for the export to end (`TRUE`), or return at once with its
  `job_id` (`FALSE`). Client-side: not sent to the API.

- timeout:

  Seconds to wait for the export (default one hour); the export
  continues on the server after a timeout. Client-side: not sent to the
  API.

- poll:

  Seconds between two polls of the export (at least 2). Client-side: not
  sent to the API.

- download:

  Download the zip once the export is completed (needs `wait = TRUE`).
  Client-side: not sent to the API.

- dir:

  Directory of the downloads; `NULL` uses the option
  `soilhub.export_dir`, the environment variable `SOILHUB_EXPORT_DIR`,
  else `file.path(tempdir(), "soilhub-exports")`. Client-side: not sent
  to the API.

- unzip:

  Unzip the download into `<dir>/<job_id>/`. Client-side: not sent to
  the API.

- progress:

  Show the progress of the export (fraction written) and of the
  download: progress bars in an interactive session, else one message
  per change of status. Client-side: not sent to the API.

## Value

A `soil_export` (a list): `job_id`, `status` (`queued`, `running`,
`completed`, `failed`, `cancelled`), `progress` (percent),
`observation_count` (the observations of the selection, counted at
submission), `records` (the records written per table, once completed),
`file_size_bytes`, `expires_at` (POSIXct UTC), `error_message`,
`format`, `content`, `layout`, `request` (the body sent), `selection`
(the selection arguments), and after the download `zip` (path), `files`
(names), `dir` (the unzipped directory) and `metadata` (the parsed
`metadata.json`, read by
[`soil_metadata()`](https://giulange.github.io/soilhub-r/reference/soil_metadata.md),
[`soil_citations()`](https://giulange.github.io/soilhub-r/reference/soil_citations.md),
[`soil_columns()`](https://giulange.github.io/soilhub-r/reference/soil_columns.md),
[`soil_revised_rules()`](https://giulange.github.io/soilhub-r/reference/soil_revised_rules.md)).

## Details

The zip holds `metadata.json` (the request, the record counts, the
datasets with citation and licence, the variables, the typing of the
wide columns, the warnings and the revised rules) and two tables joined
on `feature_id`: `features` (one record per feature, with its geometry)
and, with `content = "all"`, `observations` in the `layout` asked (wide:
one row per horizon, every variable column on every row; long: one row
per observation), without geometry. Files by format: `"gpkg"`
`export.gpkg` (layers `features` and `observations`); `"geojson"`
`features.geojson`, `observations.geojson`; `"csv"`/`"tsv"`
`features.csv` (geometry as WKT in `geometry_wkt`), `observations.csv`
(nested values as JSON text); `"shp"` (features only)
`features_points.*` and `features_polygons.*`.

With `wait = TRUE` (the default) the function polls the export every
`poll` seconds until it ends, downloads the zip into `dir` and unzips it
into `<dir>/<job_id>/`; read the tables with
[`soil_export_read()`](https://giulange.github.io/soilhub-r/reference/soil_export_read.md).
With `wait = FALSE` it returns at once: **keep the `job_id`**, the API
keeps no list of a user's exports, and resume later, also in another R
session, with `soil_export_wait(soil, job_id)` then
[`soil_export_download()`](https://giulange.github.io/soilhub-r/reference/soil_export_status.md).

Rights: `soil:read`. Capabilities: `complete_exports` (checked at
[`soil_connect()`](https://giulange.github.io/soilhub-r/reference/soil_connect.md));
`revised_view`, `profile_type_filter`, `component_selection` as for the
reads.

## See also

[`soil_export_read()`](https://giulange.github.io/soilhub-r/reference/soil_export_read.md),
[`soil_summary()`](https://giulange.github.io/soilhub-r/reference/soil_summary.md)
to size a selection.

Other exports:
[`soil_export_from_error()`](https://giulange.github.io/soilhub-r/reference/soil_export_from_error.md),
[`soil_export_read()`](https://giulange.github.io/soilhub-r/reference/soil_export_read.md),
[`soil_export_status()`](https://giulange.github.io/soilhub-r/reference/soil_export_status.md)

## Examples

``` r
if (FALSE) { # \dontrun{
soil <- soil_connect()
x <- soil_export(soil, datasets = "wosis_points", country = "BRA", format = "csv")
x
obs <- soil_export_read(x)
features <- soil_export_read(x, "features")
soil_citations(x)

# submit now, collect later (keep the job id)
x <- soil_export(soil, datasets = "wosis_points", format = "gpkg", wait = FALSE)
x$job_id
x <- soil_export_wait(soil, x$job_id)
x <- soil_export_download(soil, x)
} # }
```
