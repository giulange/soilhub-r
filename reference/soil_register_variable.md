# Register a variable

Declares a new variable that products may publish (an output of an
external model, e.g. a soil-health score). The definition is first
validated by the API (`POST /variables/validate`: the domain and the
measurement kind must exist in the controlled vocabulary), then
registered (`POST /variables`). Variables carry no unit: the hub mirrors
its sources and converts nothing.

## Usage

``` r
soil_register_variable(
  soil = soil_session(),
  variable_code,
  name,
  domain_code,
  value_type = c("numeric", "text", "boolean", "json"),
  measurement_kind_code,
  allowed_target_levels,
  description = NULL,
  idempotency_key,
  validate_only = FALSE
)
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

- variable_code:

  Code of the variable: lowercase letters, digits and `_` (e.g.
  `"soil_health_physical_score"`). API field `variable_code`.

- name:

  Human name. API field `name`.

- domain_code:

  Domain of the controlled vocabulary (e.g. `"soil"`). API field
  `domain_code`.

- value_type:

  Type of the published values: `"numeric"`, `"text"`, `"boolean"` or
  `"json"`. API field `value_type`.

- measurement_kind_code:

  Measurement kind of the controlled vocabulary (e.g. `"derived"`). API
  field `measurement_kind_code`.

- allowed_target_levels:

  Levels a value may be attached to, one or more of `"feature"`,
  `"profile"`, `"component"`, `"horizon"`. API field
  `allowed_target_levels`.

- description:

  Optional description. API field `description`.

- idempotency_key:

  Key of this registration (at most 200 characters), stable for one
  definition. API field `idempotency_key`.

- validate_only:

  Only validate: nothing is registered. Client-side: stops after
  `POST /variables/validate` and skips `POST /variables`; not sent to
  the API.

## Value

With `validate_only = TRUE`, the validation: a list `valid`,
`variable_code`, `errors` (data frame). Otherwise the registered
variable: a list `variable_id`, `variable_code`, `name`, `description`,
`domain_code`, `value_type`, `measurement_kind_code`,
`allowed_target_levels` (character), `idempotent_replay`. An invalid
definition is a `soilhub_validation_error` whose `errors` lists the
problems.

## Details

Registration is idempotent: the same `idempotency_key` with the same
definition returns the variable already registered
(`idempotent_replay = TRUE`). A different definition under a key already
used, or a `variable_code` already registered with another definition,
is a `soilhub_conflict_error` (HTTP 409): choose a new key, or a new
code.

Rights: `soil:admin`. Capability: `variable_registration`.

## See also

Other writing:
[`soil_product()`](https://giulange.github.io/soilhub-r/reference/soil_product.md),
[`soil_product_version()`](https://giulange.github.io/soilhub-r/reference/soil_product_version.md),
[`soil_publish_health()`](https://giulange.github.io/soilhub-r/reference/soil_publish_health.md),
[`soil_publish_source()`](https://giulange.github.io/soilhub-r/reference/soil_publish_source.md),
[`soil_publish_values()`](https://giulange.github.io/soilhub-r/reference/soil_publish_values.md),
[`soil_run_open()`](https://giulange.github.io/soilhub-r/reference/soil_run_open.md),
[`soil_source_validate()`](https://giulange.github.io/soilhub-r/reference/soil_source_validate.md)

## Examples

``` r
if (FALSE) { # \dontrun{
soil_register_variable(
  soil, "soil_health_physical_score", name = "Soil health, physical score",
  domain_code = "soil", value_type = "numeric",
  measurement_kind_code = "derived", allowed_target_levels = "horizon",
  idempotency_key = "var-soil-health-physical-v1"
)
} # }
```
