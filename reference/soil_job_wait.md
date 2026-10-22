# Wait for a job to end

Polls the job (`GET /jobs/{job_id}`) every `poll` seconds until it
reaches a terminal state. A `completed` job is returned; a `failed` or
`cancelled` job, or a job still running after `timeout` seconds, is a
`soilhub_job_error` holding the last status in `e$job` (the job itself
continues on the server after a timeout: wait again or cancel it with
[`soil_job_cancel()`](https://giulange.github.io/soilhub-r/reference/soil_job_cancel.md)).
Each poll is an ordinary request: the session is renewed as needed, so a
wait may last longer than the access token.

## Usage

``` r
soil_job_wait(
  soil = soil_session(),
  job_id,
  timeout = 3600,
  poll = 5,
  progress = interactive()
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

- timeout:

  Seconds to wait before giving up (default one hour). Client-side: not
  sent to the API.

- poll:

  Seconds between two polls. Client-side: not sent to the API.

- progress:

  Print a line each time the status or the progress changes.
  Client-side: not sent to the API.

## Value

The completed `soil_job` (unified view).

## Details

Rights: `soil:publish`.

## See also

Other jobs:
[`soil_job()`](https://giulange.github.io/soilhub-r/reference/soil_job.md),
[`soil_job_cancel()`](https://giulange.github.io/soilhub-r/reference/soil_job_cancel.md),
[`soil_refresh_countries()`](https://giulange.github.io/soilhub-r/reference/soil_refresh_countries.md)

## Examples

``` r
if (FALSE) { # \dontrun{
job <- soil_job_wait(soil, "0b4e...", timeout = 600)
job$published_count
} # }
```
