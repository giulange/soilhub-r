# One country by dataset and variable

The inventory of one country (`GET /countries/{code}`): its totals, the
totals per dataset and per (dataset, variable). Same assignment rule as
[`soil_countries()`](https://giulange.github.io/soilhub-r/reference/soil_countries.md)
(`intersects`).

## Usage

``` r
soil_country(soil = soil_session(), code)
```

## Arguments

- soil:

  A session; the default session when omitted (the code may then be
  given first: `soil_country("KEN")`). Client-side: not sent to the API.

- code:

  ISO 3166-1 alpha-2 or alpha-3 code (`"KE"`, `"KEN"`), any case. API
  path parameter `{code}` of `GET /countries/{code}`.

## Value

A list: `country` (one-row data frame: `iso_a2`, `iso_a3`, `name`, the
counts of
[`soil_countries()`](https://giulange.github.io/soilhub-r/reference/soil_countries.md),
`source_signature`, `aggregation_version`, `refresh_job_id`,
`refreshed_at`), `datasets` (data frame per dataset: `provider_code`,
`dataset_code`, `dataset_name`, the API ids `country_id`, `dataset_id`,
the counts, `refreshed_at`, ...), `variables` (data frame per dataset
and variable: `provider_code`, `dataset_code`, `variable_code`,
`original_observation_count`, `value_count`, `observation_count`),
`as_of` (POSIXct) and `country_assignment`. An unknown code raises
`soilhub_not_found_error`.

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
[`soil_dataset()`](https://giulange.github.io/soilhub-r/reference/soil_dataset.md),
[`soil_datasets()`](https://giulange.github.io/soilhub-r/reference/soil_datasets.md),
[`soil_formats()`](https://giulange.github.io/soilhub-r/reference/soil_formats.md),
[`soil_ttr_flag_legend()`](https://giulange.github.io/soilhub-r/reference/soil_ttr_flag_legend.md),
[`soil_variable_mappings()`](https://giulange.github.io/soilhub-r/reference/soil_variable_mappings.md),
[`soil_variables()`](https://giulange.github.io/soilhub-r/reference/soil_variables.md)

## Examples

``` r
if (FALSE) { # \dontrun{
kenya <- soil_country(soil, "KEN")
kenya$datasets[, c("dataset_code", "profile_count", "observation_count")]
} # }
```
