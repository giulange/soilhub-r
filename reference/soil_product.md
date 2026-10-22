# Register a product

A product is the family of results of one external model (e.g. a soil
health index), attached to one canonical target level. Its scientific
content lives in immutable versions
([`soil_product_version()`](https://giulange.github.io/soilhub-r/reference/soil_product_version.md));
results are published in runs of a version
([`soil_run_open()`](https://giulange.github.io/soilhub-r/reference/soil_run_open.md)).

## Usage

``` r
soil_product(
  soil = soil_session(),
  product_code,
  name,
  target_level,
  description = NULL
)
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

- product_code:

  Code of the product: lowercase letters, digits, `_`. API field
  `product_code` of `POST /products`; for
  [`soil_product_version()`](https://giulange.github.io/soilhub-r/reference/soil_product_version.md),
  API path parameter `{product_code}` of
  `POST /products/{product_code}/versions`.

- name:

  Human name. API field `name` of `POST /products`.

- target_level:

  The canonical level of its results: `"feature"`, `"profile"`,
  `"component"` or `"horizon"`. API field `target_level` of
  `POST /products`.

- description:

  Optional description. API field `description` of `POST /products`.

## Value

The product: a list `product_code`, `name`, `description`,
`target_level`.

## Details

Registering the same definition again returns it unchanged. A
`product_code` already registered with another name, description or
target level is a `soilhub_conflict_error` (HTTP 409); the API offers no
way to read the existing product, so keep using its code if it is yours,
or choose another code.

Rights: `soil:admin`.

## See also

Other writing:
[`soil_product_version()`](https://giulange.github.io/soilhub-r/reference/soil_product_version.md),
[`soil_publish_health()`](https://giulange.github.io/soilhub-r/reference/soil_publish_health.md),
[`soil_publish_source()`](https://giulange.github.io/soilhub-r/reference/soil_publish_source.md),
[`soil_publish_values()`](https://giulange.github.io/soilhub-r/reference/soil_publish_values.md),
[`soil_register_variable()`](https://giulange.github.io/soilhub-r/reference/soil_register_variable.md),
[`soil_run_open()`](https://giulange.github.io/soilhub-r/reference/soil_run_open.md),
[`soil_source_validate()`](https://giulange.github.io/soilhub-r/reference/soil_source_validate.md)

## Examples

``` r
if (FALSE) { # \dontrun{
soil_product(soil, "soil_health_fuzzy", "Soil health (fuzzy model)", "horizon")
} # }
```
