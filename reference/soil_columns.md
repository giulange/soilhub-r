# Typing of the variable columns of a wide table

One row per variable column of a wide
[`soil_observations()`](https://giulange.github.io/soilhub-r/reference/soil_observations.md)
read, from the `metadata.variables` of the API merged over the pages:
the canonical property key (`organic_carbon`; `src_<code>` columns have
none), whether the column is numeric (`numeric = FALSE`: the column
holds the source text verbatim), the source units, the source codes, the
horizons with a value, the multi-value cells (WoSIS cells listing
several values: the column holds their mean, the `<key>_values` column
every original value), the laboratory methods, the notes of the source
mappings and the method facets of the multi-value cells.

## Usage

``` r
soil_columns(x)
```

## Arguments

- x:

  A wide `soil_table`, or a downloaded wide `soil_export`. Client-side:
  not sent to the API.

## Value

A data frame `column`, `property_key`, `numeric`, `units` (list),
`source_codes` (list), `horizon_count`, `multi_value_cells`, `methods`
(list of named character: method code -\> description), `source_notes`
(list of data frames `dataset`, `source_code`, `source_notes`),
`method_facets` (list of named lists).

## See also

Other results:
[`soil_first_layer()`](https://giulange.github.io/soilhub-r/reference/soil_first_layer.md),
[`soil_flags()`](https://giulange.github.io/soilhub-r/reference/soil_flags.md),
[`soil_markings()`](https://giulange.github.io/soilhub-r/reference/soil_markings.md),
[`soil_metadata()`](https://giulange.github.io/soilhub-r/reference/soil_metadata.md),
[`soil_revised_rules()`](https://giulange.github.io/soilhub-r/reference/soil_revised_rules.md),
[`soil_table`](https://giulange.github.io/soilhub-r/reference/soil_table.md)

## Examples

``` r
if (FALSE) { # \dontrun{
x <- soil_observations(soil, datasets = "wosis_points", country = "KEN")
cols <- soil_columns(x)
cols[cols$multi_value_cells > 0, c("column", "multi_value_cells")]
} # }
```
