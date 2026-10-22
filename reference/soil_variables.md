# The variable catalog

The registered variables (`GET /variables`): canonical soil properties
(`organic_carbon`, `clay`, ...) and variables published by products,
with where they are available and, for each one, the source codes that
map to it in each dataset (`source_mappings`, see
[`soil_variable_mappings()`](https://giulange.github.io/soilhub-r/reference/soil_variable_mappings.md)).

## Usage

``` r
soil_variables(
  soil = soil_session(),
  code = NULL,
  domain = NULL,
  measurement_kind = NULL,
  target_level = NULL,
  dataset = NULL,
  provider = NULL,
  available_only = FALSE,
  include_unmapped = FALSE
)
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

- code:

  Variable codes (`variable_code`, e.g. `"organic_carbon"`). API query
  parameter `code`.

- domain:

  Domains (`domain_code`, e.g. `"soil"`). API query parameter `domain`.

- measurement_kind:

  Measurement kinds (`measurement_kind_code`, e.g. `"observed"`). API
  query parameter `measurement_kind`.

- target_level:

  Target levels allowed for the variable (`"horizon"`, `"profile"`,
  `"feature"`, ...). API query parameter `target_level`.

- dataset:

  Datasets where the variable has values or a source mapping (e.g.
  `"wosis_points"`); the mappings are limited to them too. API query
  parameter `dataset`.

- provider:

  Providers (e.g. `"isric"`), as `dataset`. API query parameter
  `provider`.

- available_only:

  Only variables with at least one value. API query parameter
  `available_only`.

- include_unmapped:

  Also list the source codes that map to no variable, in
  `soil_metadata(x)$unmapped_source_codes`. API query parameter
  `include_unmapped`.

## Value

A data frame, one row per variable: `variable_code`, `name`,
`description`, `domain_code`, `value_type`, `measurement_kind_code`,
`allowed_target_levels` (list), `property_family`,
`property_family_name`, `documentation_url`, the counts of published
values `value_count` and `feature_count`, `datasets`, `providers`,
`available_target_levels`, `statuses`, `product_versions` (lists of
character), `min_depth_cm`, `max_depth_cm`, `valid_time_start`,
`valid_time_end`, `coverage` (list: the GeoJSON extent of the published
values, `NULL` when none) and `source_mappings` (list of data frames,
see
[`soil_variable_mappings()`](https://giulange.github.io/soilhub-r/reference/soil_variable_mappings.md)).
The attribute `soil_metadata` holds `variable_count`,
`unmapped_included`, `unmapped_source_code_count`,
`unmapped_source_codes` (data frame `provider_code`, `dataset_code`,
`source_code`, `observation_count`), the `request` and `retrieved_at`.

## Details

Every filter is optional (`NULL`, the default, means no filter; `"ALL"`
is not accepted) and takes several values.

Rights: `soil:summary`.

## See also

[`soil_variable_mappings()`](https://giulange.github.io/soilhub-r/reference/soil_variable_mappings.md)

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
[`soil_variable_mappings()`](https://giulange.github.io/soilhub-r/reference/soil_variable_mappings.md)

## Examples

``` r
if (FALSE) { # \dontrun{
v <- soil_variables(soil, dataset = "wise_profiles")
v[, c("variable_code", "name", "property_family")]
soil_variable_mappings(v)
} # }
```
