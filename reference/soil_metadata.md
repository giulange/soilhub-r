# Metadata and warnings of a result

`soil_metadata()` returns what the API and the client recorded about a
read: `request` (the body sent) and `endpoint`, `api_version`,
`schema_version`, `client_version`, `retrieved_at` (UTC), `request_ids`
(one per page, quote them when reporting a problem), `pages`, `complete`
(`FALSE` for a partial result) and `next_offset` (the offset to continue
from), `total_count` (`NA` for the wide layout: the API does not count),
`warnings`, `variables` (see
[`soil_columns()`](https://giulange.github.io/soilhub-r/reference/soil_columns.md)),
`view` and `revised` (see
[`soil_revised_rules()`](https://giulange.github.io/soilhub-r/reference/soil_revised_rules.md)),
`first_layer` (see
[`soil_first_layer()`](https://giulange.github.io/soilhub-r/reference/soil_first_layer.md)),
`components` and `min_cumulative_percent` (when a component dataset is
selected), `crs`, `datasets` (the catalog rows of the datasets read:
what
[`soil_citations()`](https://giulange.github.io/soilhub-r/reference/soil_citations.md)
reads) and `multi_value_rule` (`"mean"`: the value of a multi-value
WoSIS cell in the numeric column).

## Usage

``` r
soil_metadata(x)

soil_warnings(x)
```

## Arguments

- x:

  A `soil_table` (or a summary or export result). Client-side: not sent
  to the API.

## Value

`soil_metadata()`: a list. `soil_warnings()`: a character vector.

## Details

`soil_warnings()` returns the warnings of the API over all pages, once
each: mixed units in a column, multi-value cells, renamed columns,
collapsed duplicate measurements, component ties, component proportions
not summing to 100.

## See also

Other results:
[`soil_columns()`](https://giulange.github.io/soilhub-r/reference/soil_columns.md),
[`soil_first_layer()`](https://giulange.github.io/soilhub-r/reference/soil_first_layer.md),
[`soil_flags()`](https://giulange.github.io/soilhub-r/reference/soil_flags.md),
[`soil_markings()`](https://giulange.github.io/soilhub-r/reference/soil_markings.md),
[`soil_revised_rules()`](https://giulange.github.io/soilhub-r/reference/soil_revised_rules.md),
[`soil_table`](https://giulange.github.io/soilhub-r/reference/soil_table.md)

## Examples

``` r
if (FALSE) { # \dontrun{
x <- soil_observations(soil, datasets = "wosis_points", country = "KEN")
soil_metadata(x)$request_ids
soil_warnings(x)
} # }
```
