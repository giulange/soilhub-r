# Register an immutable product version

A version freezes the scientific content of a product: the SHA-256
checksum of the algorithm (code, model artifact), its configuration and
the variables it publishes with their target levels. Every variable must
be registered
([`soil_register_variable()`](https://giulange.github.io/soilhub-r/reference/soil_register_variable.md))
and allow the declared levels. Any scientific change is a new version.

## Usage

``` r
soil_product_version(
  soil = soil_session(),
  product_code,
  version_code,
  algorithm_checksum,
  variables,
  configuration = list()
)
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

- product_code:

  Code of the product: lowercase letters, digits, `_`. API field
  `product_code` of `POST /products`; for `soil_product_version()`, API
  path parameter `{product_code}` of
  `POST /products/{product_code}/versions`.

- version_code:

  Code of the version (e.g. `"v1.0.0"`). API field `version_code`.

- algorithm_checksum:

  SHA-256 of the algorithm: 64 lowercase hexadecimal characters (e.g.
  `openssl::sha256(file("model.R"))`). API field `algorithm_checksum`.

- variables:

  The variables published by the version: a data frame with
  `variable_code` and `target_levels` (a character column, one level per
  row, or a list column of character vectors), or a list of
  `list(variable_code =, target_levels =)`. API field `variables`.

- configuration:

  The configuration of the model, a named list (a JSON object). API
  field `configuration`.

## Value

The version: a list `product_code`, `product_name`, `description`,
`product_version_id` (the id to open runs), `version_code`,
`algorithm_checksum`, `configuration` (list), `declared_variables` (data
frame `variable_code`, `target_levels`), `created_at`.

## Details

Registering the same version again returns it (with its
`product_version_id`). A `version_code` already registered with another
checksum, configuration or variables is a `soilhub_conflict_error` (HTTP
409): register a new version code. An unknown product is a
`soilhub_not_found_error`.

Rights: `soil:admin`.

## See also

Other writing:
[`soil_product()`](https://giulange.github.io/soilhub-r/reference/soil_product.md),
[`soil_publish_health()`](https://giulange.github.io/soilhub-r/reference/soil_publish_health.md),
[`soil_publish_source()`](https://giulange.github.io/soilhub-r/reference/soil_publish_source.md),
[`soil_publish_values()`](https://giulange.github.io/soilhub-r/reference/soil_publish_values.md),
[`soil_register_variable()`](https://giulange.github.io/soilhub-r/reference/soil_register_variable.md),
[`soil_run_open()`](https://giulange.github.io/soilhub-r/reference/soil_run_open.md),
[`soil_source_validate()`](https://giulange.github.io/soilhub-r/reference/soil_source_validate.md)

## Examples

``` r
if (FALSE) { # \dontrun{
v <- soil_product_version(
  soil, "soil_health_fuzzy", "v1.0.0",
  algorithm_checksum = as.character(openssl::sha256(file("model.R"))),
  variables = data.frame(variable_code = "soil_health_physical_score",
                         target_levels = "horizon"),
  configuration = list(rule_base = "physical-v1")
)
v$product_version_id
} # }
```
