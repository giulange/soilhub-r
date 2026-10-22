# Open, complete or fail a run

A run is one execution of a product version: the results published in it
come from the exact source releases listed in `input_release_ids` (the
input snapshot) and the `parameters` of the execution (geographic scope,
options, external execution reference; never a secret).

## Usage

``` r
soil_run_open(
  soil = soil_session(),
  product_version_id,
  idempotency_key,
  input_release_ids = integer(),
  parameters = list()
)

soil_run_complete(soil = soil_session(), run_id, diagnostics = list())

soil_run_fail(soil = soil_session(), run_id, diagnostics = list())
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

- product_version_id:

  The id of the version
  ([`soil_product_version()`](https://giulange.github.io/soilhub-r/reference/soil_product_version.md)).
  API path parameter `{product_version_id}` of
  `POST /product-versions/{product_version_id}/runs`.

- idempotency_key:

  Key of the run (at most 200 characters), stable for one execution. API
  field `idempotency_key`.

- input_release_ids:

  Ids of the source releases used by the execution (integer). API field
  `input_release_ids`.

- parameters:

  Parameters of the execution, a named list. API field `parameters`.

- run_id:

  The id of the run. API path parameter `{run_id}` of
  `POST /publications/{run_id}/complete` and
  `POST /publications/{run_id}/fail`.

- diagnostics:

  Diagnostics recorded with the closing, a named list. API field
  `diagnostics`.

## Value

The run: a list `run_id`, `product_version_id`, `product_code`,
`version_code`, `status` (`running`, `completed`, `failed`),
`idempotency_key`, `started_at`, `completed_at`, `parameters`,
`diagnostics`, `input_release_ids`.

## Details

`soil_run_open()` is idempotent: the same `idempotency_key` with the
same parameters and input snapshot returns the run already open; with
other parameters it is a `soilhub_conflict_error` (HTTP 409). Keep the
`run_id`: there is no way to list runs.

`soil_run_complete()` closes a run whose publications are all verified
(every receipt has `published_count == received_count`, no job left
`queued` or `running`); `soil_run_fail()` closes it as failed, with
structured `diagnostics`. Repeating the same closing is harmless;
closing a run already closed the other way is a
`soilhub_conflict_error`, as is completing a run with a soil-health job
that did not complete.

Rights: `soil:publish`.

## See also

Other writing:
[`soil_product()`](https://giulange.github.io/soilhub-r/reference/soil_product.md),
[`soil_product_version()`](https://giulange.github.io/soilhub-r/reference/soil_product_version.md),
[`soil_publish_health()`](https://giulange.github.io/soilhub-r/reference/soil_publish_health.md),
[`soil_publish_source()`](https://giulange.github.io/soilhub-r/reference/soil_publish_source.md),
[`soil_publish_values()`](https://giulange.github.io/soilhub-r/reference/soil_publish_values.md),
[`soil_register_variable()`](https://giulange.github.io/soilhub-r/reference/soil_register_variable.md),
[`soil_source_validate()`](https://giulange.github.io/soilhub-r/reference/soil_source_validate.md)

## Examples

``` r
if (FALSE) { # \dontrun{
run <- soil_run_open(soil, v$product_version_id, "run-india-2026-10",
                     input_release_ids = c(12L, 14L),
                     parameters = list(country = "IND"))
# ... soil_publish_values(soil, run$run_id, ...) ...
soil_run_complete(soil, run$run_id)
} # }
```
