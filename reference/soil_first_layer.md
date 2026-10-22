# First-layer vocabulary of a table

With `layer = "first"` the API keeps only the first horizon(s) of each
profile (of each selected component for SOTWIS and SOTER polygons) and
adds the columns `first_layer_status` (`surface`, `tie`, `not_surface`,
`depth_missing`; with `view = "revised"` also `surface_within_5cm` and
`first_mineral`) and `profile_markings` (`negative_depth_above`,
`empty_row`, `depth_order_conflict`, `numbering_starts_at_<N>`,
`numbering_gap`). This returns the vocabulary the API reported for the
read.

## Usage

``` r
soil_first_layer(x)
```

## Arguments

- x:

  A `soil_table` read with `layer = "first"`. Client-side: not sent to
  the API.

## Value

A list `view`, `statuses` (character), `profile_markings` (character);
`NULL` when `x` was not read with `layer = "first"`.

## See also

Other results:
[`soil_columns()`](https://giulange.github.io/soilhub-r/reference/soil_columns.md),
[`soil_flags()`](https://giulange.github.io/soilhub-r/reference/soil_flags.md),
[`soil_markings()`](https://giulange.github.io/soilhub-r/reference/soil_markings.md),
[`soil_metadata()`](https://giulange.github.io/soilhub-r/reference/soil_metadata.md),
[`soil_revised_rules()`](https://giulange.github.io/soilhub-r/reference/soil_revised_rules.md),
[`soil_table`](https://giulange.github.io/soilhub-r/reference/soil_table.md)

## Examples

``` r
if (FALSE) { # \dontrun{
x <- soil_observations(soil, datasets = "soter_profiles", layer = "first")
soil_first_layer(x)
table(x$first_layer_status)
} # }
```
