# Publish soil-health scores

Publishes the soil-health scores computed by an external model in an
open run of a product version that declares one or more of the variables
`soil_health_physical_score`, `soil_health_chemical_score`,
`soil_health_soc_score`. Each score is one horizon and one category; the
API publishes the generic value and the soil-health details in one
transaction.

## Usage

``` r
soil_publish_health(
  soil = soil_session(),
  run_id,
  scores,
  idempotency_key,
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
  `soil_publish_health()`: `/soil-health` and `/soil-health/jobs`).

- scores:

  A data frame (list columns for nested fields) or a list of records
  with `horizon_id`, `release_id`, `category_code` (e.g. `"physical"`),
  `score_status` (`"scored"`, `"insufficient_data"`,
  `"not_applicable"`), `score`, `score_class`, `source_support`
  (`"observed_point_profile"`, `"polygon_estimate"`,
  `"map_unit_profile_relation"`, `"non_spatial_profile"`,
  `"non_spatial_estimate"`), and optionally `quality_code`,
  `observation_inputs` (list of
  `list(observation_id =, input_role =, required =, transformation =)`),
  `value_inputs`, `release_inputs`, `asset_inputs` (lists of
  `list(id =, role =)`), `inputs`, `derived_variables`, `memberships`,
  `diagnostics` (named lists) and `activated_rules` (list of named
  lists). API field `scores`; with the NDJSON transport, the lines of
  the file sent as API form field `file`.

- idempotency_key:

  Key of this publication (at most 200 characters), stable for one
  content. API field `idempotency_key` of a synchronous publication; API
  query parameter `idempotency_key` of an NDJSON upload.

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

A `soil_publication` list as
[`soil_publish_values()`](https://giulange.github.io/soilhub-r/reference/soil_publish_values.md),
with `score_count` for a synchronous publication.

## Details

Local checks of every record before anything is sent: required fields
(`horizon_id` a UUID, `release_id`, `category_code`, `score_status`,
`source_support`), allowed `score_status` and `source_support`, score
and class consistency (a `scored` record has a numeric `score` and a
`score_class`; any other status has neither), observation inputs with an
`observation_id` (UUID) and an `input_role`, and no duplicate horizon,
category and release. Problems are a `soilhub_argument_error` whose
`errors` lists them by record.

Up to 10,000 records are published synchronously
(`POST /publications/{run_id}/soil-health`; a rejected batch is a
`soilhub_validation_error` with the API's `errors`); above, or with
`transport = "ndjson"`, an NDJSON file with its SHA-256 checksum is
uploaded as a job (`POST /publications/{run_id}/soil-health/jobs`),
never repeated automatically. The same `idempotency_key` with the same
content returns the first receipt; any difference, even only in the
memberships, rules or diagnostics, is a `soilhub_conflict_error` (HTTP
409): use a new key. The receipt is reconciled with the records sent
(`published_count`, `score_count`): a difference is a
`soilhub_reconciliation_warning`.

Rights: `soil:publish`. Capabilities: `publish_soil_health_sync`
(synchronous), `bulk_soil_health` (job).

## See also

Other writing:
[`soil_product()`](https://giulange.github.io/soilhub-r/reference/soil_product.md),
[`soil_product_version()`](https://giulange.github.io/soilhub-r/reference/soil_product_version.md),
[`soil_publish_source()`](https://giulange.github.io/soilhub-r/reference/soil_publish_source.md),
[`soil_publish_values()`](https://giulange.github.io/soilhub-r/reference/soil_publish_values.md),
[`soil_register_variable()`](https://giulange.github.io/soilhub-r/reference/soil_register_variable.md),
[`soil_run_open()`](https://giulange.github.io/soilhub-r/reference/soil_run_open.md),
[`soil_source_validate()`](https://giulange.github.io/soilhub-r/reference/soil_source_validate.md)

## Examples

``` r
if (FALSE) { # \dontrun{
scores <- list(list(
  horizon_id = "4fa5fbe3-8fd4-4fb1-94cf-d07963eb50f7", release_id = 12L,
  category_code = "physical", score_status = "scored", score = 72.5,
  score_class = "good", source_support = "polygon_estimate",
  observation_inputs = list(list(
    observation_id = "46f252f1-5f38-4223-b329-88822f60fe75",
    input_role = "bulk_density", transformation = "membership_low_compaction"
  )),
  inputs = list(bulk_density = 1.31),
  memberships = list(poor = 0.1, moderate = 0.3, good = 0.8),
  activated_rules = list(list(rule = "physical_r4", strength = 0.7))
))
soil_publish_health(soil, run$run_id, scores, "fuzzy-v1-india-2026-10")
} # }
```
