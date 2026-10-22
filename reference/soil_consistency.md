# Authoritative distinct totals

The distinct counts of features, profiles, horizons, observations and
variables of a selection, as the daily statistics of the Global Soil
Data Hub compute them (`POST /query/consistency`): the totals count
every feature, profile and horizon once, so they are the numbers to
quote; the country rows count a feature in each country it intersects
and **must never be summed**. Without filters, or with one country and
no other filter than `providers` and `datasets`, the API reads the daily
statistics (`metadata$calculation = "summary"`, `as_of` the refresh
time); other selections are counted live (`"live"`).

## Usage

``` r
soil_consistency(
  soil = soil_session(),
  providers = NULL,
  datasets = NULL,
  geometry = NULL,
  country = NULL,
  bbox = NULL,
  variables = NULL
)
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

- providers:

  Provider codes (`"isric"`), `NULL` for all. API field `providers`.

- datasets:

  Catalog dataset codes, `NULL` for all. API field `datasets`.

- geometry:

  `NULL` (all), or `"point"` and/or `"polygon"`. API field `geometry`.

- country:

  Countries as ISO 3166 alpha-2 or alpha-3 codes. API field `country`.

- bbox:

  `c(xmin, ymin, xmax, ymax)` in WGS84 degrees. API field `bbox`.

- variables:

  Canonical variable codes or source codes. API field `variables`.

## Value

A `soil_consistency` list: `totals` (named list: `feature_count`,
`point_count`, `polygon_count`, `profile_count`, `horizon_count`,
`original_observation_count`, `value_count`, `observation_count`,
`variable_count`, `dataset_count` as doubles and `variables` character),
`countries`, `datasets` and `variables` (data frames, the columns of the
calculation used: counts double, `refreshed_at` POSIXct) and `metadata`
(`calculation`, `as_of` POSIXct, `summary_scope`, `country_assignment`,
the request).

## Details

This endpoint has its own request: it takes no `view`, `profile_type`,
`components` or `canonical`, and its counts include the published
derived values (`value_count`), so they differ by design from
[`soil_summary()`](https://giulange.github.io/soilhub-r/reference/soil_summary.md).

Rights: `soil:summary`. Capability: `unified_consistency`.

## See also

Other summaries:
[`soil_availability()`](https://giulange.github.io/soilhub-r/reference/soil_availability.md),
[`soil_summary()`](https://giulange.github.io/soilhub-r/reference/soil_summary.md)

## Examples

``` r
if (FALSE) { # \dontrun{
k <- soil_consistency(soil, country = "KEN")
k$totals$feature_count
k$metadata$calculation
} # }
```
