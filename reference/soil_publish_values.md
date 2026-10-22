# Publish derived values

Publishes the values computed by an external model in an open run
([`soil_run_open()`](https://giulange.github.io/soilhub-r/reference/soil_run_open.md)),
against existing canonical targets (feature, profile, component or
horizon ids). The hub stores, validates and serves them; it runs no
model.

## Usage

``` r
soil_publish_values(
  soil = soil_session(),
  run_id,
  values,
  idempotency_key,
  validate = TRUE,
  transport = c("auto", "sync", "ndjson"),
  wait = TRUE,
  timeout = 3600,
  poll = 5,
  progress = interactive()
)
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

- run_id:

  The id of an open run. API path parameter `{run_id}` of
  `POST /publications/{run_id}/values`, `/validate` and `/jobs` (for
  [`soil_publish_health()`](https://giulange.github.io/soilhub-r/reference/soil_publish_health.md):
  `/soil-health` and `/soil-health/jobs`).

- values:

  A data frame (list columns for nested fields) or a list of records
  with `variable_code`, `target_level`, `target_id` (UUID), `value`
  (typed as the variable: number, text, logical, or a list for `json`),
  `value_status` (`"published"`, the default, needs a value;
  `"insufficient_data"` and `"not_applicable"` none), `release_id`,
  `quality_code`, `valid_time_start`, `valid_time_end`, `depth_top_cm`,
  `depth_bottom_cm` (optional) and `lineage`: a list with one or more of
  `observations`, `values`, `releases`, `assets`, each a list of
  `list(id =, role =, transformation =)` (or a data frame), at least one
  item in all. `NA` fields are left out. API field `values`; with the
  NDJSON transport, the lines of the file sent as API form field `file`.

- idempotency_key:

  Key of this publication (at most 200 characters), stable for one
  content. API field `idempotency_key` of a synchronous publication; API
  query parameter `idempotency_key` of an NDJSON upload.

- validate:

  Validate on the server before publishing. Client-side: decides whether
  `POST /publications/{run_id}/validate` is called first; not sent to
  the API.

- transport:

  `"auto"` (synchronous up to 10,000 records, else NDJSON), `"sync"` or
  `"ndjson"`. Client-side: not sent to the API.

- wait:

  For a job: wait for it to end (see
  [`soil_job_wait()`](https://giulange.github.io/soilhub-r/reference/soil_job_wait.md)).
  Client-side: not sent to the API.

- timeout, poll:

  Seconds to wait for a job, and between two polls. Client-side: not
  sent to the API.

- progress:

  Print the progress of the job. Client-side: not sent to the API.

## Value

A `soil_publication` list: `transport`, `run_id`, `status`,
`record_count` (records sent), `received_count`, `published_count`,
`publication_id` (the receipt), `idempotent_replay`, `validation` (the
server validation, or `NULL`), and for a job `job_id`, `job` (the last
`soil_job`), `checksum_sha256`, `byte_size`. With `wait = FALSE` the job
is returned as submitted (`status` `queued`): follow it with
[`soil_job_wait()`](https://giulange.github.io/soilhub-r/reference/soil_job_wait.md).
A job that fails is a `soilhub_job_error` whose `errors` holds the
rejected rows reported by the job.

## Details

Steps:

1.  local checks of every record (required fields, target level and id,
    `value_status` and value, lineage, depth and time intervals):
    problems are a `soilhub_argument_error` whose `errors` lists them by
    record;

2.  with `validate = TRUE`, server validation without writing
    (`POST /publications/{run_id}/validate`: run open, variables
    declared by the version, targets and lineage existing, typed values,
    duplicates); an invalid batch is a `soilhub_validation_error` with
    the API's `errors` (`row` is 0-based, `record` the 1-based record);

3.  publication: synchronous (`POST /publications/{run_id}/values`) up
    to 10,000 records, else (`transport = "ndjson"`, or `"auto"` above
    10,000) an NDJSON file with its SHA-256 checksum uploaded as a job
    (`POST /publications/{run_id}/jobs`). Before an upload with
    `validate = TRUE` the client checks that every `variable_code` is
    registered
    ([`soil_variables()`](https://giulange.github.io/soilhub-r/reference/soil_variables.md));
    the job validates the whole file on the server before publishing
    anything.

The upload is never repeated automatically and has no total timeout
(only the connection timeout). Publication is idempotent: the same
`idempotency_key` with the same content returns the first receipt
(`idempotent_replay = TRUE`) or the job already submitted, so after a
transport failure call the function again with the same key and the same
values. The same key with different content is a
`soilhub_conflict_error` (HTTP 409): use a new key.

The receipt is reconciled with the records sent: a `published_count`
different from their number is a `soilhub_reconciliation_warning`; do
not complete the run until it is understood.

Rights: `soil:publish`. Capabilities: `publish_generic_values`
(synchronous), `generic_bulk_publication` (job).

## See also

Other writing:
[`soil_product()`](https://giulange.github.io/soilhub-r/reference/soil_product.md),
[`soil_product_version()`](https://giulange.github.io/soilhub-r/reference/soil_product_version.md),
[`soil_publish_health()`](https://giulange.github.io/soilhub-r/reference/soil_publish_health.md),
[`soil_publish_source()`](https://giulange.github.io/soilhub-r/reference/soil_publish_source.md),
[`soil_register_variable()`](https://giulange.github.io/soilhub-r/reference/soil_register_variable.md),
[`soil_run_open()`](https://giulange.github.io/soilhub-r/reference/soil_run_open.md),
[`soil_source_validate()`](https://giulange.github.io/soilhub-r/reference/soil_source_validate.md)

## Examples

``` r
if (FALSE) { # \dontrun{
values <- data.frame(
  variable_code = "soil_health_physical_score", target_level = "horizon",
  target_id = horizon_ids, value = scores
)
values$lineage <- lapply(observation_ids, function(id) {
  list(observations = list(list(id = id, role = "bulk_density")))
})
receipt <- soil_publish_values(soil, run$run_id, values, "pub-india-2026-10-a")
receipt$published_count
} # }
```
