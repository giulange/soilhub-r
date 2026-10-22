# Published derived values

Reads the values published by products (models, derivations, expert
assessments) on the features, profiles, components and horizons of the
Global Soil Data Hub (`POST /query/values`), page by page, as a typed
table: one row per value, with its variable, target, product version and
run, status, validity time and depth.

## Usage

``` r
soil_values(
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
  statuses = NULL,
  with_geometry = c("none", "sf", "text"),
  include_lineage = FALSE,
  max_rows = Inf,
  progress = interactive()
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

- with_geometry:

  `"none"`, `"text"` (the geometry of the target's feature as GeoJSON
  text in `geometry_text`, EPSG:4326) or `"sf"` (an `sf` object with a
  `geometry` column; needs the package `sf`, else a
  `soilhub_dependency_error`). Client-side; sets the API field
  `include_geometry` (`false` for `"none"`), the form is built locally.

- include_lineage:

  Add the lineage list columns `observation_inputs`, `value_inputs`,
  `release_inputs`, `asset_inputs` (what each value was computed from).
  API field `include_lineage`.

- max_rows:

  Maximum number of values to read (`Inf`: all). Client-side; caps the
  API field `limit` of each page request.

- progress:

  Report the pages read. Client-side: not sent to the API.

## Value

A `soil_table` (see
[soil_table](https://giulange.github.io/soilhub-r/reference/soil_table.md))
with `soil_layout = "values"`: `value_id`, `variable_code`,
`variable_name`, `domain_code`, `value_type`, `measurement_kind_code`,
`target_level`, `feature_id`, `profile_id`, `component_id`,
`horizon_id`, `dataset_code`, `provider_code`, `source_support`,
`geometry_kind`, (`geometry_text`), `release_code`,
`product_version_code`, `run_id`, `value`, `numeric_value`,
`text_value`, `boolean_value`, `json_value` (list), `value_status`,
`quality_code`, `valid_time_start`, `valid_time_end` (POSIXct UTC),
`depth_top_cm`, `depth_bottom_cm`, and the lineage columns.
`soil_metadata(x)$total_count` is the number of values of the selection.

## Details

`value` holds the value in its own type: a double column when every
value read is numeric, character for text, logical for boolean, else a
list column with each value in its type (`json` values as parsed lists).
The API columns `numeric_value`, `text_value`, `boolean_value` and
`json_value` are kept as returned.

Filters are combined with AND; each takes several values (OR within the
filter). `NULL` means no filter.

Rights: `soil:read`. Capabilities: `query_generic_values`;
`country_filtering` for `country`.

## See also

[`soil_values_summary()`](https://giulange.github.io/soilhub-r/reference/soil_values_summary.md)
to count before reading,
[`soil_publish_values()`](https://giulange.github.io/soilhub-r/reference/soil_publish_values.md)
to publish.

Other thematic reads:
[`soil_health_scores()`](https://giulange.github.io/soilhub-r/reference/soil_health_scores.md),
[`soil_health_summary()`](https://giulange.github.io/soilhub-r/reference/soil_health_summary.md),
[`soil_resolve_targets()`](https://giulange.github.io/soilhub-r/reference/soil_resolve_targets.md),
[`soil_ttr_flags()`](https://giulange.github.io/soilhub-r/reference/soil_ttr_flags.md),
[`soil_values_summary()`](https://giulange.github.io/soilhub-r/reference/soil_values_summary.md)

## Examples

``` r
if (FALSE) { # \dontrun{
v <- soil_values(soil, variables = "soc_stock_0_30", country = "KEN",
                 statuses = "published", include_lineage = TRUE)
v[, c("target_level", "horizon_id", "value", "run_id")]
} # }
```
