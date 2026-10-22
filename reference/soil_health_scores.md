# Soil-health scores

Reads the soil-health scores published on horizons
(`POST /query/soil-health`), page by page, as a typed table: one row per
horizon, category and model version, with the score, its class and
status, the model and the run that produced it.

## Usage

``` r
soil_health_scores(
  soil = soil_session(),
  providers = NULL,
  datasets = NULL,
  release_ids = NULL,
  release_codes = NULL,
  model_versions = NULL,
  run_ids = NULL,
  categories = NULL,
  score_classes = NULL,
  statuses = NULL,
  source_supports = NULL,
  country = NULL,
  bbox = NULL,
  depth_top_cm = NULL,
  depth_bottom_cm = NULL,
  with_geometry = c("none", "sf", "text"),
  include_details = FALSE,
  max_rows = Inf,
  progress = interactive()
)
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

- providers:

  Provider codes. API field `providers`.

- datasets:

  Catalog dataset codes. API field `datasets`.

- release_ids, release_codes:

  Releases of the scored horizons. API fields `release_ids` and
  `release_codes`.

- model_versions:

  Soil-health model version codes (an unknown code is refused by the
  API). API field `model_versions`.

- run_ids:

  Product run ids (API field `product_run_ids`).

- categories:

  Category codes (`"physical"`, `"chemical"`, ...). API field
  `categories`.

- score_classes:

  Score classes. API field `score_classes`.

- statuses:

  Score statuses: `"scored"`, `"insufficient_data"`, `"not_applicable"`
  (API field `score_statuses`).

- source_supports:

  Source supports (`"point_observation"`, `"polygon_estimate"`, ...).
  API field `source_supports`.

- country:

  Countries as ISO 3166 alpha-2 or alpha-3 codes or names. API field
  `country`.

- bbox:

  `c(xmin, ymin, xmax, ymax)` in WGS84 degrees. API field `bbox`.

- depth_top_cm, depth_bottom_cm:

  Depth interval in cm: the horizons overlapping it. API fields
  `depth_top_cm` and `depth_bottom_cm`.

- with_geometry:

  `"none"`, `"text"` (the geometry of the feature as GeoJSON text in
  `geometry_text`) or `"sf"` (an `sf` object with a `geometry` column,
  EPSG:4326; needs the package `sf`, else a `soilhub_dependency_error`).
  Client-side; sets the API field `include_geometry` (`false` for
  `"none"`), the form is built locally.

- include_details:

  Add the list columns `inputs`, `derived_variables`, `memberships`,
  `activated_rules`, `diagnostics`, `input_observations` (how each score
  was computed). API field `include_details`.

- max_rows:

  Maximum number of scores to read (`Inf`: all). Client-side; caps the
  API field `limit` of each page request.

- progress:

  Report the pages read. Client-side: not sent to the API.

## Value

A `soil_table` (see
[soil_table](https://giulange.github.io/soilhub-r/reference/soil_table.md))
with `soil_layout = "health"`: `horizon_score_id`, `value_id`,
`variable_code`, `horizon_id`, `profile_id`, `component_id`,
`feature_id`, `dataset_code`, `provider_code`, `release_id`,
`release_code`, `source_support`, `geometry_kind`, (`geometry_text`),
`horizon_key`, `horizon_name`, `top_depth_cm`, `bottom_depth_cm`,
`model_version_id`, `model_version_code`, `model_name`,
`model_checksum`, `health_run_id`, `product_run_id`, `category_code`,
`category_name`, `score` (double), `score_class`, `score_status`,
`created_at` (POSIXct UTC), and the detail columns.

## Details

Filters are combined with AND; each takes several values. `NULL` means
no filter.

Rights: `soil:read`. Capabilities: `query_soil_health`;
`country_filtering` for `country`.

## See also

[`soil_health_summary()`](https://giulange.github.io/soilhub-r/reference/soil_health_summary.md),
[`soil_publish_health()`](https://giulange.github.io/soilhub-r/reference/soil_publish_health.md)

Other thematic reads:
[`soil_health_summary()`](https://giulange.github.io/soilhub-r/reference/soil_health_summary.md),
[`soil_resolve_targets()`](https://giulange.github.io/soilhub-r/reference/soil_resolve_targets.md),
[`soil_ttr_flags()`](https://giulange.github.io/soilhub-r/reference/soil_ttr_flags.md),
[`soil_values()`](https://giulange.github.io/soilhub-r/reference/soil_values.md),
[`soil_values_summary()`](https://giulange.github.io/soilhub-r/reference/soil_values_summary.md)

## Examples

``` r
if (FALSE) { # \dontrun{
h <- soil_health_scores(soil, datasets = "sotwis_polygons", country = "TUN",
                        categories = "physical", include_details = TRUE)
table(h$score_class)
} # }
```
