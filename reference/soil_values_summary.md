# Counts of published derived values

Counts the values a
[`soil_values()`](https://giulange.github.io/soilhub-r/reference/soil_values.md)
selection holds, without reading them (`POST /query/values/summary`): in
total, by variable, by dataset, by target level and by status.

## Usage

``` r
soil_values_summary(
  soil = soil_session(),
  providers = NULL,
  datasets = NULL,
  variables = NULL,
  domains = NULL,
  measurement_kinds = NULL,
  target_levels = NULL,
  country = NULL,
  bbox = NULL,
  valid_at = NULL,
  depth_top_cm = NULL,
  depth_bottom_cm = NULL,
  product_versions = NULL,
  run_ids = NULL,
  statuses = NULL
)
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

- providers:

  Provider codes of the targets (`"isric"`). API field `providers`.

- datasets:

  Catalog dataset codes of the targets. API field `datasets`.

- variables:

  Variable codes (see
  [`soil_variables()`](https://giulange.github.io/soilhub-r/reference/soil_variables.md)).
  API field `variables`.

- domains:

  Domain codes of the variables. API field `domains`.

- measurement_kinds:

  Measurement kinds of the variables (`"derived"`, `"modelled"`, ...).
  API field `measurement_kinds`.

- target_levels:

  `"feature"`, `"profile"`, `"component"`, `"horizon"`. API field
  `target_levels`.

- country:

  Countries as ISO 3166 alpha-2 or alpha-3 codes or names. API field
  `country`.

- bbox:

  `c(xmin, ymin, xmax, ymax)` in WGS84 degrees. API field `bbox`.

- valid_at:

  A date-time (POSIXct, Date or ISO 8601 text): only the values valid at
  that instant (`valid_time_start <= valid_at < valid_time_end`, open
  ends included). API field `valid_at`.

- depth_top_cm, depth_bottom_cm:

  Depth interval in cm: the values whose depth interval overlaps it
  (values without depth included). API fields `depth_top_cm` and
  `depth_bottom_cm`.

- product_versions:

  Product version codes. API field `product_versions`.

- run_ids:

  Run ids. API field `run_ids`.

- statuses:

  Value statuses: `"published"`, `"insufficient_data"`,
  `"not_applicable"`. API field `statuses`.

## Value

A `soil_values_summary` list: `total_value_count`, `feature_count`,
`variables` (data frame `code`, `domain`), `by_dataset` (data frame
`dataset`, `provider`, `value_count`, `feature_count`,
`variable_count`), `by_target_level` and `by_status` (named doubles),
`metadata`.

## Details

Rights: `soil:summary`. Capabilities: `query_generic_values`;
`country_filtering` for `country`.

## See also

Other thematic reads:
[`soil_health_scores()`](https://giulange.github.io/soilhub-r/reference/soil_health_scores.md),
[`soil_health_summary()`](https://giulange.github.io/soilhub-r/reference/soil_health_summary.md),
[`soil_resolve_targets()`](https://giulange.github.io/soilhub-r/reference/soil_resolve_targets.md),
[`soil_ttr_flags()`](https://giulange.github.io/soilhub-r/reference/soil_ttr_flags.md),
[`soil_values()`](https://giulange.github.io/soilhub-r/reference/soil_values.md)

## Examples

``` r
if (FALSE) { # \dontrun{
soil_values_summary(soil, country = "KEN")$by_status
} # }
```
