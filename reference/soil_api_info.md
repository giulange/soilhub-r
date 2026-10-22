# Versions, liveness and compatibility of the API

Asks the API whether it is alive (`GET /health`) and can reach its
database (`GET /ready`), and reports the API and response schema
versions and the authentication advertised by `/capabilities`, the
version of this client and whether the two are compatible (design 9.1:
API 0.5.0 or later, same major version, and every required capability
present).

## Usage

``` r
soil_api_info(soil = soil_session())
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

## Value

A `soil_api_info` list: `api_url`, `health` (`"ok"` or the error),
`ready` (`"ready"`, or the reason the database is not reachable),
`api_version`, `schema_version` (the `response_schema_version`),
`authentication` (list), `client_version`, `supported_api` (the range
supported by this client), `compatible` (logical, `NA` when unknown),
`status` (`"supported"`, `"newer_minor"`, `"too_old"`, `"other_major"`,
`"unknown"`) and `missing_capabilities`.

## Details

It also works on the session attached to the `soilhub_capability_error`
of an incompatible server (`e$session`), to inspect the versions.

Rights: none for `health` and `ready`; the capabilities are those read
at the login (or read now, with `soil:summary`, when not cached).

## See also

Other discovery:
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
[`soil_variable_mappings()`](https://giulange.github.io/soilhub-r/reference/soil_variable_mappings.md),
[`soil_variables()`](https://giulange.github.io/soilhub-r/reference/soil_variables.md)

## Examples

``` r
if (FALSE) { # \dontrun{
soil_api_info(soil)

# an incompatible server
soil <- tryCatch(soil_connect(), soilhub_capability_error = function(e) e$session)
soil_api_info(soil)
} # }
```
