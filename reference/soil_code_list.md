# Rows of one source code list

The rows of a code list (`GET /code-lists/{code_list}`), verbatim: one
row per source row, with its source dataset and row number. A code may
appear once per source dataset (the same triple in each package).

## Usage

``` r
soil_code_list(
  soil = soil_session(),
  name,
  attribute = NULL,
  code = NULL,
  source_dataset = NULL
)
```

## Arguments

- soil:

  A session; the default session when omitted (the name may then be
  given first: `soil_code_list("SOTWIS_codes")`). Client-side: not sent
  to the API.

- name:

  The code list (`"SOTWIS_codes"`). API path parameter `{code_list}` of
  `GET /code-lists/{code_list}`.

- attribute:

  Source attributes (`ATTRIBUTE`, e.g. `"LNDF"`), `NULL` for all. API
  query parameter `attribute`.

- code:

  Codes (`CODE`), `NULL` for all. API query parameter `code`.

- source_dataset:

  One source dataset (record id or name), `NULL` for all. API query
  parameter `source_dataset`.

## Value

A data frame: `attribute`, `code`, `description`, `source_record_id`,
`source_dataset_name`, `source_table`, `source_row_number` (integer),
`provider_code`. An unknown list raises `soilhub_not_found_error`.

## Details

Rights: `soil:summary`. Capability: `code_lists`.

## See also

Other discovery:
[`soil_api_info()`](https://giulange.github.io/soilhub-r/reference/soil_api_info.md),
[`soil_capabilities()`](https://giulange.github.io/soilhub-r/reference/soil_capabilities.md),
[`soil_citations()`](https://giulange.github.io/soilhub-r/reference/soil_citations.md),
[`soil_code_lists()`](https://giulange.github.io/soilhub-r/reference/soil_code_lists.md),
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
soil_code_list(soil, "SOTWIS_codes", attribute = "LNDF")
} # }
```
