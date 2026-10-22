# The country inventory

Daily totals per country (`GET /countries`), including the countries
without data. A feature is assigned to every country its geometry
intersects (`country_assignment = "intersects"`): a polygon crossing a
border counts in each country, so **country totals must not be summed**
to obtain a global total (use
[`soil_consistency()`](https://giulange.github.io/soilhub-r/reference/soil_consistency.md)
for distinct totals).

## Usage

``` r
soil_countries(soil = soil_session())
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

## Value

A data frame, one row per country: `iso_a2`, `iso_a3`, `name`, the
counts `dataset_count`, `feature_count`, `point_count`, `polygon_count`,
`profile_count`, `horizon_count`, `original_observation_count`,
`value_count`, `observation_count`, `variable_count` (double) and
`as_of` (POSIXct, UTC: the last successful refresh of that country).
Attributes `country_assignment` (`"intersects"`) and `soil_metadata`
(the response metadata).

## Details

Rights: `soil:summary`.

## See also

[`soil_country()`](https://giulange.github.io/soilhub-r/reference/soil_country.md)

Other discovery:
[`soil_api_info()`](https://giulange.github.io/soilhub-r/reference/soil_api_info.md),
[`soil_capabilities()`](https://giulange.github.io/soilhub-r/reference/soil_capabilities.md),
[`soil_citations()`](https://giulange.github.io/soilhub-r/reference/soil_citations.md),
[`soil_code_list()`](https://giulange.github.io/soilhub-r/reference/soil_code_list.md),
[`soil_code_lists()`](https://giulange.github.io/soilhub-r/reference/soil_code_lists.md),
[`soil_country()`](https://giulange.github.io/soilhub-r/reference/soil_country.md),
[`soil_dataset()`](https://giulange.github.io/soilhub-r/reference/soil_dataset.md),
[`soil_datasets()`](https://giulange.github.io/soilhub-r/reference/soil_datasets.md),
[`soil_formats()`](https://giulange.github.io/soilhub-r/reference/soil_formats.md),
[`soil_ttr_flag_legend()`](https://giulange.github.io/soilhub-r/reference/soil_ttr_flag_legend.md),
[`soil_variable_mappings()`](https://giulange.github.io/soilhub-r/reference/soil_variable_mappings.md),
[`soil_variables()`](https://giulange.github.io/soilhub-r/reference/soil_variables.md)

## Examples

``` r
if (FALSE) { # \dontrun{
countries <- soil_countries(soil)
head(countries[order(-countries$profile_count), c("iso_a3", "name", "profile_count")])
} # }
```
