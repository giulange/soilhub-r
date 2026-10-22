# Follow, download and cancel an export

`soil_export_status()` reads the state of an export once
(`GET /exports/{job_id}`). `soil_export_wait()` polls it every `poll`
seconds until it ends: a `completed` export is returned; a `failed` or
`cancelled` export, an unknown job id (the API answers
`status = "unknown"` for an id it does not know, e.g. an expired export)
or an export still running after `timeout` seconds is a
`soilhub_job_error` with the last state in `e$job` and `e$reason`
(`failed`, `cancelled`, `unknown_job`, `timeout`).
`soil_export_download()` streams the zip of a completed export to
`<dir>/<job_id>.zip` (the server's name) and unzips it into
`<dir>/<job_id>/`; existing files are never replaced unless
`overwrite = TRUE`. An export is kept 7 days after submission
(`expires_at`): a later download is a `soilhub_not_found_error`.
`soil_export_cancel()` asks the API to stop an export that has not ended
(`POST /jobs/{job_id}/cancel`); the worker stops at its next heartbeat.

## Usage

``` r
soil_export_status(soil = soil_session(), x)

soil_export_wait(
  soil = soil_session(),
  x,
  timeout = 3600,
  poll = 5,
  progress = interactive()
)

soil_export_download(
  soil = soil_session(),
  x,
  dir = NULL,
  unzip = TRUE,
  overwrite = FALSE,
  progress = interactive()
)

soil_export_cancel(soil = soil_session(), x)
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

- x:

  A `soil_export` or a job id (`"exp_<stamp>_<hex>"`). API path
  parameter `{job_id}` of `GET /exports/{job_id}`,
  `GET /exports/{job_id}/download` and `POST /jobs/{job_id}/cancel`.

- timeout:

  Seconds to wait before giving up (default one hour). Client-side: not
  sent to the API.

- poll:

  Seconds between two polls (at least 2). Client-side: not sent to the
  API.

- progress:

  Show the progress (a bar in an interactive session, else one message
  per change). Client-side: not sent to the API.

- dir:

  Directory of the download; `NULL` uses the option
  `soilhub.export_dir`, the environment variable `SOILHUB_EXPORT_DIR`,
  else `file.path(tempdir(), "soilhub-exports")`. Client-side: not sent
  to the API.

- unzip:

  Unzip the download into `<dir>/<job_id>/`. Client-side: not sent to
  the API.

- overwrite:

  Replace an existing zip or directory of the same export. Client-side:
  not sent to the API.

## Value

`soil_export_status()`, `soil_export_wait()`, `soil_export_download()`:
the updated `soil_export` (see
[`soil_export()`](https://giulange.github.io/soilhub-r/reference/soil_export.md)).
`soil_export_cancel()`: the job after the request (a `soil_job`, see
[`soil_job()`](https://giulange.github.io/soilhub-r/reference/soil_job.md)).

## Details

The job id is the only handle on an export (the API lists no exports),
so each function accepts the `soil_export` returned by
[`soil_export()`](https://giulange.github.io/soilhub-r/reference/soil_export.md)
or the job id alone, also in a later R session.

Rights: `soil:read`; `soil_export_cancel()` needs `soil:publish` (the
API controls every job through the unified job registry, which needs
that right).

## See also

Other exports:
[`soil_export()`](https://giulange.github.io/soilhub-r/reference/soil_export.md),
[`soil_export_from_error()`](https://giulange.github.io/soilhub-r/reference/soil_export_from_error.md),
[`soil_export_read()`](https://giulange.github.io/soilhub-r/reference/soil_export_read.md)

## Examples

``` r
if (FALSE) { # \dontrun{
x <- soil_export(soil, datasets = "wosis_points", wait = FALSE)
soil_export_status(soil, x)$status
x <- soil_export_wait(soil, x, timeout = 1800)
x <- soil_export_download(soil, x, dir = "exports")
x$files

# in a later session, from the id alone
x <- soil_export_download(soil, "exp_20261019_101500_1a2b3c4d")
} # }
```
