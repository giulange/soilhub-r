# Refresh the country inventory

Queues the recomputation of the daily country totals read by
[`soil_countries()`](https://giulange.github.io/soilhub-r/reference/soil_countries.md)
(`POST /countries/refresh`). The job runs on the server; follow it with
[`soil_job_wait()`](https://giulange.github.io/soilhub-r/reference/soil_job_wait.md)
(which needs `soil:publish`).

## Usage

``` r
soil_refresh_countries(soil = soil_session(), idempotency_key = NULL)
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

- idempotency_key:

  Optional key: a second request with the same key returns the job
  already queued instead of queuing another one. API query parameter
  `idempotency_key`.

## Value

The queued `soil_job` (unified view).

## Details

Rights: `soil:admin`.

## See also

Other jobs:
[`soil_job()`](https://giulange.github.io/soilhub-r/reference/soil_job.md),
[`soil_job_cancel()`](https://giulange.github.io/soilhub-r/reference/soil_job_cancel.md),
[`soil_job_wait()`](https://giulange.github.io/soilhub-r/reference/soil_job_wait.md)

## Examples

``` r
if (FALSE) { # \dontrun{
job <- soil_refresh_countries(soil, idempotency_key = "countries-2026-10-18")
soil_job_wait(soil, job$job_id)
} # }
```
