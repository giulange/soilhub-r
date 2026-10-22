# Validate or promote a source ingest job

The two server steps of
[`soil_publish_source()`](https://giulange.github.io/soilhub-r/reference/soil_publish_source.md),
for a job uploaded with `wait = FALSE`.

## Usage

``` r
soil_source_validate(soil = soil_session(), job_id)

soil_source_promote(soil = soil_session(), job_id)
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

- job_id:

  The job id (or the result of a submission). API path parameter
  `{job_id}` of `GET /jobs/{job_id}` (also
  `GET /publication-jobs/{job_id}` and
  `GET /soil-health-publication-jobs/{job_id}`, by `detail`),
  `POST /jobs/{job_id}/cancel` and
  `POST /source-ingests/{job_id}/validate` or `/promote`.

## Value

`soil_source_validate()`: a `soil_source_validation` list: `job_id`,
`valid`, `counts` (staged records by type), `errors` (data frame:
`record_number`, `source_record_id`, `errors`), `diagnostics_truncated`,
`unmapped_property_codes`. `soil_source_promote()`: the `soil_job`
(unified view), `completed`, with `published_count`, `receipt_id` and,
in `diagnostics`, the `release_id` and the promoted `counts`.

## Details

`soil_source_validate()` (`POST /source-ingests/{job_id}/validate`)
stages the uploaded file and checks identities, hierarchy, geometry and
observation declarations; it can be repeated while the job is
`validating`. An invalid bundle is not an error here: the report has
`valid = FALSE`, the rejected records in `errors` (at most 1,000,
`diagnostics_truncated`), and the job fails.

`soil_source_promote()` (`POST /source-ingests/{job_id}/promote`)
publishes a validated job in one transaction: provider, dataset, release
(immutable: an existing `release_code` makes it fail), assets, canonical
features, profiles, components, horizons and observations, coverage and
receipt. Promoting a completed job returns it unchanged. A job that has
not passed validation, or whose promotion is refused, is a
`soilhub_conflict_error` (HTTP 409) explaining why.

Rights: `soil:publish`. Capability: `source_ingest`.

## See also

Other writing:
[`soil_product()`](https://giulange.github.io/soilhub-r/reference/soil_product.md),
[`soil_product_version()`](https://giulange.github.io/soilhub-r/reference/soil_product_version.md),
[`soil_publish_health()`](https://giulange.github.io/soilhub-r/reference/soil_publish_health.md),
[`soil_publish_source()`](https://giulange.github.io/soilhub-r/reference/soil_publish_source.md),
[`soil_publish_values()`](https://giulange.github.io/soilhub-r/reference/soil_publish_values.md),
[`soil_register_variable()`](https://giulange.github.io/soilhub-r/reference/soil_register_variable.md),
[`soil_run_open()`](https://giulange.github.io/soilhub-r/reference/soil_run_open.md)

## Examples

``` r
if (FALSE) { # \dontrun{
ingest <- soil_publish_source(soil, manifest, sites, idempotency_key = "k", wait = FALSE)
report <- soil_source_validate(soil, ingest$job_id)
report$unmapped_property_codes
if (report$valid) soil_source_promote(soil, ingest$job_id)
} # }
```
