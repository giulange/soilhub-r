# The capabilities of the server

The deployment contract of the API, `GET /capabilities`: API and
response schema versions, authentication (the audience of the rights),
the limits advertised for this deployment (`max_page_size`,
`max_sync_observations`, `max_export_observations`,
`max_publication_bytes`), formats, exports, filters, the capability
flags (`capabilities`), the profile types (`profile_types`) and the
views with their revised rules (`views`).

## Usage

``` r
soil_capabilities(soil = soil_session(), refresh = FALSE)
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

- refresh:

  Read the capabilities from the server again. Client-side: not sent to
  the API.

## Value

The `/capabilities` object as a named list (as parsed, nothing renamed).

## Details

The capabilities are read once after the login and kept in the session;
`refresh = TRUE` reads them again and repeats the version check of
[`soil_connect()`](https://giulange.github.io/soilhub-r/reference/soil_connect.md).

Rights: `soil:summary`.

## See also

[`soil_api_info()`](https://giulange.github.io/soilhub-r/reference/soil_api_info.md)
for the versions and the compatibility of the server with this client.

Other discovery:
[`soil_api_info()`](https://giulange.github.io/soilhub-r/reference/soil_api_info.md),
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
caps <- soil_capabilities(soil)
caps$api_version
caps$limits$max_sync_observations
names(Filter(isTRUE, caps$capabilities))
} # }
```
