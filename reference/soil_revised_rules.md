# Revised rules applied to a result

With `view = "revised"` the API applies the decided rules of the revised
view (R2 to R19 of the API documentation) in the response only, and
lists the rules that changed or flagged something in the selection with
their counts over the whole selection (every page, not only the rows
read). One row per rule and effect (`values_hidden`, `rows_hidden`,
`values_changed`, `values_flagged:<flag>`, ...).

## Usage

``` r
soil_revised_rules(x)
```

## Arguments

- x:

  A `soil_table` read with `view = "revised"` (or a summary or an export
  of the revised view). Client-side: not sent to the API.

## Value

A data frame `id`, `title`, `issue`, `effect`, `n` (zero rows for the
raw view). Its attribute `pairs` holds the spellings linked by R6
(SOTWIS PRID linked without case), when listed; `pending` and
`unchanged` the rules not applied and the rules whose revised view
equals the raw one; `scope` what the counts cover.

## See also

Other results:
[`soil_columns()`](https://giulange.github.io/soilhub-r/reference/soil_columns.md),
[`soil_first_layer()`](https://giulange.github.io/soilhub-r/reference/soil_first_layer.md),
[`soil_flags()`](https://giulange.github.io/soilhub-r/reference/soil_flags.md),
[`soil_markings()`](https://giulange.github.io/soilhub-r/reference/soil_markings.md),
[`soil_metadata()`](https://giulange.github.io/soilhub-r/reference/soil_metadata.md),
[`soil_table`](https://giulange.github.io/soilhub-r/reference/soil_table.md)

## Examples

``` r
if (FALSE) { # \dontrun{
x <- soil_observations(soil, datasets = "wise_profiles", view = "revised")
soil_revised_rules(x)
attr(soil_revised_rules(x), "pairs")
} # }
```
