# Export formats

The formats of exports (`GET /formats`): GeoPackage, GeoJSON, CSV, TSV
and Shapefile (`shp` only for exports of features; see
[`soil_capabilities()`](https://giulange.github.io/soilhub-r/reference/soil_capabilities.md)`$exports`
for the formats per export content).

## Usage

``` r
soil_formats(soil = soil_session())
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

## Value

A character vector.

## Details

Rights: `soil:summary`.

## See also

Other discovery:
[`soil_api_info()`](https://giulange.github.io/soilhub-r/reference/soil_api_info.md),
[`soil_capabilities()`](https://giulange.github.io/soilhub-r/reference/soil_capabilities.md),
[`soil_citations()`](https://giulange.github.io/soilhub-r/reference/soil_citations.md),
[`soil_code_list()`](https://giulange.github.io/soilhub-r/reference/soil_code_list.md),
[`soil_code_lists()`](https://giulange.github.io/soilhub-r/reference/soil_code_lists.md),
[`soil_countries()`](https://giulange.github.io/soilhub-r/reference/soil_countries.md),
[`soil_country()`](https://giulange.github.io/soilhub-r/reference/soil_country.md),
[`soil_dataset()`](https://giulange.github.io/soilhub-r/reference/soil_dataset.md),
[`soil_datasets()`](https://giulange.github.io/soilhub-r/reference/soil_datasets.md),
[`soil_ttr_flag_legend()`](https://giulange.github.io/soilhub-r/reference/soil_ttr_flag_legend.md),
[`soil_variable_mappings()`](https://giulange.github.io/soilhub-r/reference/soil_variable_mappings.md),
[`soil_variables()`](https://giulange.github.io/soilhub-r/reference/soil_variables.md)

## Examples

``` r
if (FALSE) { # \dontrun{
soil_formats(soil)
} # }
```
