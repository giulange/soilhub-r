# Counts of soil-health scores

Counts the scores a
[`soil_health_scores()`](https://giulange.github.io/soilhub-r/reference/soil_health_scores.md)
selection holds, without reading them
(`POST /query/soil-health/summary`): in total and by dataset, release,
source support, category, class and status.

## Usage

``` r
soil_health_summary(
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
  depth_bottom_cm = NULL
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

## Value

A `soil_health_summary` list: `total_score_count`, `feature_count`,
`horizon_count` and the data frames `by_dataset` (`dataset`, `provider`,
`score_count`, `feature_count`, `horizon_count`), `by_release`
(`release_id`, `release_code`, `score_count`), `by_source_support`
(`source_support`, `score_count`), `by_category` (`category`,
`variable`, `score_count`), `by_class` (`score_class`, `score_count`),
`by_status` (`score_status`, `score_count`), and `metadata`.

## Details

Rights: `soil:summary`. Capabilities: `query_soil_health`;
`country_filtering` for `country`.

## See also

Other thematic reads:
[`soil_health_scores()`](https://giulange.github.io/soilhub-r/reference/soil_health_scores.md),
[`soil_resolve_targets()`](https://giulange.github.io/soilhub-r/reference/soil_resolve_targets.md),
[`soil_ttr_flags()`](https://giulange.github.io/soilhub-r/reference/soil_ttr_flags.md),
[`soil_values()`](https://giulange.github.io/soilhub-r/reference/soil_values.md),
[`soil_values_summary()`](https://giulange.github.io/soilhub-r/reference/soil_values_summary.md)

## Examples

``` r
if (FALSE) { # \dontrun{
soil_health_summary(soil, country = "TUN")$by_class
} # }
```
