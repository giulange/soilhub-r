# Markings of a table

Every marking of a wide read as a long data frame: the raw markings of
the cells (`cell_markings`: `value_count`, `methods_differ`,
`value_spread`, `source_method_kind`, `method_facets` of WoSIS cells
listing several values), of the layers (`texture_sum`,
`consistency_flags`), of the profiles (`also_in_datasets`,
`possible_profile`, `superseded_by`, and with `layer = "first"` the
`profile_markings`), the retirement of cells (`retired_cells`) and, with
`view = "revised"`, the revised markings of the horizons, of the cells
and the values a revised rule did not return (`hidden_values`). Markings
change no row and no value: they describe them.

## Usage

``` r
soil_markings(x)
```

## Arguments

- x:

  A `soil_table`. Client-side: not sent to the API.

## Value

A data frame `row` (row number in `x`), `horizon_id`, `scope` (`"cell"`,
`"layer"`, `"profile"`, `"retired_cell"`, `"revised_horizon"`,
`"revised_cell"`, `"hidden_value"`), `column` (the variable column, or
the source property code of a hidden value; `NA` for a row marking),
`marking` (the marking name, or the rule of a hidden value) and `value`
(character).

## Details

A marking holding several values gives one row per value; an object
(such as `method_facets`) gives one row with its JSON text.

In the long layout the cell markings are columns of the row (`column` is
its `property_code`), the layer and profile markings repeat on every
observation of the horizon, and `revised_markings` mixes the horizon
markings with those of the cell (`texture_normalized`,
`guessed_elements_removed`, `value_from_estimates`, `kept_from_copy`,
`values_differ`: scope `"revised_cell"`).

## See also

Other results:
[`soil_columns()`](https://giulange.github.io/soilhub-r/reference/soil_columns.md),
[`soil_first_layer()`](https://giulange.github.io/soilhub-r/reference/soil_first_layer.md),
[`soil_flags()`](https://giulange.github.io/soilhub-r/reference/soil_flags.md),
[`soil_metadata()`](https://giulange.github.io/soilhub-r/reference/soil_metadata.md),
[`soil_revised_rules()`](https://giulange.github.io/soilhub-r/reference/soil_revised_rules.md),
[`soil_table`](https://giulange.github.io/soilhub-r/reference/soil_table.md)

## Examples

``` r
if (FALSE) { # \dontrun{
m <- soil_markings(x)
m[m$scope == "hidden_value", ]
} # }
```
