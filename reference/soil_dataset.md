# One dataset of the catalog

The full catalog entry of one dataset (`GET /datasets/{name}`): the same
fields as a row of
[`soil_datasets()`](https://giulange.github.io/soilhub-r/reference/soil_datasets.md),
as a list, with `source_assets` and `notes` as data frames. Printing
shows the title, the release, the counts, the licence, the citation and
the titles of the notes.

## Usage

``` r
soil_dataset(soil = soil_session(), name)
```

## Arguments

- soil:

  A session; the default session when omitted (the dataset name may then
  be given first: `soil_dataset("wise_profiles")`). Client-side: not
  sent to the API.

- name:

  The dataset name (e.g. `"soter_profiles"`). API path parameter
  `{dataset_name}` of `GET /datasets/{dataset_name}`.

## Value

A `soil_dataset` list with the fields of
[`soil_datasets()`](https://giulange.github.io/soilhub-r/reference/soil_datasets.md).
An unknown name raises `soilhub_not_found_error`.

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
[`soil_datasets()`](https://giulange.github.io/soilhub-r/reference/soil_datasets.md),
[`soil_formats()`](https://giulange.github.io/soilhub-r/reference/soil_formats.md),
[`soil_ttr_flag_legend()`](https://giulange.github.io/soilhub-r/reference/soil_ttr_flag_legend.md),
[`soil_variable_mappings()`](https://giulange.github.io/soilhub-r/reference/soil_variable_mappings.md),
[`soil_variables()`](https://giulange.github.io/soilhub-r/reference/soil_variables.md)

## Examples

``` r
if (FALSE) { # \dontrun{
soter <- soil_dataset(soil, "soter_profiles")
soter
soter$notes[soter$notes$kind == "licence", c("source_dataset_name", "body")]
} # }
```
