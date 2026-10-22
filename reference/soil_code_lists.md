# Source code lists

The code lists kept as in the source (`GET /code-lists`), today the
`SOTWIS_codes` table of three SOTWIS packages (Senegal and The Gambia,
Tunisia, Upper Tana), which explains the codes of `CLAF`, `DRAI`,
`ISOC`, `LITH`, `LNDF`, `PHAS`, ...

## Usage

``` r
soil_code_lists(soil = soil_session())
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

## Value

A data frame, one row per code list and provider: `code_list`,
`provider_code`, `row_count`, `distinct_entries`, `attributes` (list of
character), `source_datasets` (list of data frames `source_record_id`,
`source_dataset_name`).

## Details

Rights: `soil:summary`. Capability: `code_lists`.

## See also

[`soil_code_list()`](https://giulange.github.io/soilhub-r/reference/soil_code_list.md)

Other discovery:
[`soil_api_info()`](https://giulange.github.io/soilhub-r/reference/soil_api_info.md),
[`soil_capabilities()`](https://giulange.github.io/soilhub-r/reference/soil_capabilities.md),
[`soil_citations()`](https://giulange.github.io/soilhub-r/reference/soil_citations.md),
[`soil_code_list()`](https://giulange.github.io/soilhub-r/reference/soil_code_list.md),
[`soil_countries()`](https://giulange.github.io/soilhub-r/reference/soil_countries.md),
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
soil_code_lists(soil)
} # }
```
