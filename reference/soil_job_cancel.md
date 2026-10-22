# Cancel a job

Asks the API to cancel a job that has not ended
(`POST /jobs/{job_id}/cancel`); the worker stops at its next heartbeat.
A job that has already ended is returned unchanged, with a message.

## Usage

``` r
soil_job_cancel(soil = soil_session(), job_id)
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

The `soil_job` after the request (unified view): `status` `cancelled`
and `cancel_requested` `TRUE`.

## Details

Rights: `soil:publish`.

## See also

Other jobs:
[`soil_job()`](https://giulange.github.io/soilhub-r/reference/soil_job.md),
[`soil_job_wait()`](https://giulange.github.io/soilhub-r/reference/soil_job_wait.md),
[`soil_refresh_countries()`](https://giulange.github.io/soilhub-r/reference/soil_refresh_countries.md)

## Examples

``` r
if (FALSE) { # \dontrun{
soil_job_cancel(soil, "0b4e...")
} # }
```
