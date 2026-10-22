# Value flags of a table

The `value_flags` column of a wide or long read as a long data frame:
one row per flag of a cell (of an observation in the long layout). Flags
are markings computed by the API in both views (`trace_convention`,
`method_label_contradicted`, `uniform_profile_value`, `extreme`,
`above_unit_maximum`, `impossible_for_declared_unit`); they change no
value.

## Usage

``` r
soil_flags(x)
```

## Arguments

- x:

  A `soil_table` with a `value_flags` column. Client-side: not sent to
  the API.

## Value

A data frame `row` (row number in `x`), `horizon_id`, `column` (the
variable column; in the long layout the `property_code` of the row),
`flag`.

## See also

Other results:
[`soil_columns()`](https://giulange.github.io/soilhub-r/reference/soil_columns.md),
[`soil_first_layer()`](https://giulange.github.io/soilhub-r/reference/soil_first_layer.md),
[`soil_markings()`](https://giulange.github.io/soilhub-r/reference/soil_markings.md),
[`soil_metadata()`](https://giulange.github.io/soilhub-r/reference/soil_metadata.md),
[`soil_revised_rules()`](https://giulange.github.io/soilhub-r/reference/soil_revised_rules.md),
[`soil_table`](https://giulange.github.io/soilhub-r/reference/soil_table.md)

## Examples

``` r
if (FALSE) { # \dontrun{
soil_flags(x)
} # }
```
