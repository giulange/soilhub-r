# What each source code means in each dataset

One row per mapping of a source code to a variable: the original code
and label of the provider, its unit and procedure as the source gives
them, and how the hub judged the mapping (`semantic_status`,
`unit_status`, `unit_evidence`). Original terms are kept: no unit is
converted, no label rewritten.

## Usage

``` r
soil_variable_mappings(soil = soil_session(), ...)
```

## Arguments

- soil:

  A session (the default session when omitted), or the result of
  [`soil_variables()`](https://giulange.github.io/soilhub-r/reference/soil_variables.md),
  whose mappings are then listed without a request. Client-side: not
  sent to the API.

- ...:

  The filters of
  [`soil_variables()`](https://giulange.github.io/soilhub-r/reference/soil_variables.md)
  (`code`, `domain`, `measurement_kind`, `target_level`, `dataset`,
  `provider`, `available_only`) when `soil` is a session. API query
  parameters of `GET /variables`, as for
  [`soil_variables()`](https://giulange.github.io/soilhub-r/reference/soil_variables.md).

## Value

A data frame, one row per (variable, dataset, mapping): `variable_code`,
`provider_code`, `dataset_code`, `source_code`, `source_official_code`,
`source_label`, `source_unit`, `procedure_code`,
`procedure_description`, `source_value_kind`, `mapping_status`,
`semantic_status`, `unit_status`, `unit_evidence` (list),
`source_scope`, `source_notes`, `documentation_url`, `method_facets`
(list of data frames `facet_key`, `facet_value`, `element_count`,
`source_dataset_counts`).

## Details

Terms: `source_code` is the code of the source as stored,
`source_official_code` the provider's official spelling; `source_scope`
limits a mapping to one source dataset (e.g. `"<SOTWIS package>/"`) when
the same code means something different there; `method_facets` are the
facets of the WoSIS methods that change the meaning of a value.

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
[`soil_formats()`](https://giulange.github.io/soilhub-r/reference/soil_formats.md),
[`soil_ttr_flag_legend()`](https://giulange.github.io/soilhub-r/reference/soil_ttr_flag_legend.md),
[`soil_variables()`](https://giulange.github.io/soilhub-r/reference/soil_variables.md)

## Examples

``` r
if (FALSE) { # \dontrun{
m <- soil_variable_mappings(soil, dataset = "sotwis_polygons")
m[m$unit_status != "documented", c("variable_code", "source_code", "source_unit", "source_notes")]
} # }
```
