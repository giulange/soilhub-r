# Canonical ids of source records

Finds the canonical ids (`target_id`, and the `feature_id`,
`profile_id`, `component_id`, `horizon_id` it belongs to) of records
known by their source identity: provider, dataset, release, level and
the source record id (`POST /query/targets/resolve`). It is the step
before publishing derived values
([`soil_publish_values()`](https://giulange.github.io/soilhub-r/reference/soil_publish_values.md))
on records known by their source ids. Targets are sent in requests of at
most 10,000.

## Usage

``` r
soil_resolve_targets(soil = soil_session(), targets, strict = TRUE)
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

- targets:

  A data frame with the columns `provider_code`, `dataset_code`
  (lower-case codes), `release_code`, `target_level` (`"feature"`,
  `"profile"`, `"component"`, `"horizon"`), `source_record_id` and
  optionally `source_table`, without `NA` (except in `source_table`).
  API field `targets`.

- strict:

  Stop with `soilhub_argument_error` (argument `targets`) when a target
  is `missing` or `ambiguous`; the full resolution is in the error's
  `resolution` field. Client-side: not sent to the API.

## Value

A data frame, one row per row of `targets` and in the same order:
`input_index` (0-based position in `targets`), `status`,
`provider_code`, `dataset_code`, `release_code`, `target_level`,
`source_record_id`, `source_table`, `release_status`, `target_id`,
`feature_id`, `profile_id`, `component_id`, `horizon_id`,
`source_support`, `geometry_kind`, `top_depth_cm`, `bottom_depth_cm`,
`candidate_count` (integer). Attribute `soil_metadata`: the request ids
and `status_counts`.

## Details

Each target is `resolved` (one canonical record), `missing` (none) or
`ambiguous` (several: give `source_table` to choose). With
`strict = TRUE` (the default) any `missing` or `ambiguous` target is an
error, so a later publication never uses a partial resolution; with
`strict = FALSE` the statuses are returned for inspection.

Rights: `soil:read`. Capability: `target_resolution`.

## See also

Other thematic reads:
[`soil_health_scores()`](https://giulange.github.io/soilhub-r/reference/soil_health_scores.md),
[`soil_health_summary()`](https://giulange.github.io/soilhub-r/reference/soil_health_summary.md),
[`soil_ttr_flags()`](https://giulange.github.io/soilhub-r/reference/soil_ttr_flags.md),
[`soil_values()`](https://giulange.github.io/soilhub-r/reference/soil_values.md),
[`soil_values_summary()`](https://giulange.github.io/soilhub-r/reference/soil_values_summary.md)

## Examples

``` r
if (FALSE) { # \dontrun{
keys <- data.frame(provider_code = "isric", dataset_code = "wosis_points",
                   release_code = "2023-12", target_level = "profile",
                   source_record_id = c("101", "102"))
ids <- soil_resolve_targets(soil, keys)
ids$target_id

# inspect instead of stopping
res <- soil_resolve_targets(soil, keys, strict = FALSE)
table(res$status)
} # }
```
