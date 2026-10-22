# The status of an asynchronous job

Reads a job of the API: a bulk publication of values
([`soil_publish_values()`](https://giulange.github.io/soilhub-r/reference/soil_publish_values.md)
with `transport = "ndjson"`), of soil-health scores, a source ingest, a
country refresh or an export. The API keeps no list of a user's jobs:
the job id returned at submission is the only handle, so keep it.

## Usage

``` r
soil_job(
  soil = soil_session(),
  job_id,
  detail = c("unified", "publication", "soil_health")
)
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

- detail:

  Which view of the job: `"unified"`, `"publication"`, `"soil_health"`.
  Client-side; selects the endpoint read, not sent to the API.

## Value

A `soil_job` list with the fields of the view, typed (times as
`POSIXct`, counts as numbers, `diagnostics` and `error` as lists).

## Details

`detail = "unified"` reads the common lifecycle of every job
(`GET /jobs/{job_id}`): `status` (`queued`, `running`, `validating`,
`promoting`, then `completed`, `failed` or `cancelled`),
`progress_percent`, the counts of received, staged, accepted, rejected
and published rows, the checksum and size of the uploaded file, the
publication receipt (`receipt_id`), `diagnostics` and `error`.
`"publication"` and `"soil_health"` read the views of a value or a
soil-health publication job (`GET /publication-jobs/{job_id}`,
`GET /soil-health-publication-jobs/{job_id}`), whose `diagnostics` hold
the rejected rows (at most 1,000, `diagnostics_truncated`) of a failed
validation.

Rights: `soil:publish`.

## See also

Other jobs:
[`soil_job_cancel()`](https://giulange.github.io/soilhub-r/reference/soil_job_cancel.md),
[`soil_job_wait()`](https://giulange.github.io/soilhub-r/reference/soil_job_wait.md),
[`soil_refresh_countries()`](https://giulange.github.io/soilhub-r/reference/soil_refresh_countries.md)

## Examples

``` r
if (FALSE) { # \dontrun{
job <- soil_job(soil, "0b4e...")
job$status
soil_job(soil, job$job_id, detail = "publication")$diagnostics
} # }
```
