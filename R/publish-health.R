#' @include publish-values.R
NULL

# Publication of soil-health scores (design 4.6): externally computed
# horizon/category scores with their fuzzy details (prepared inputs, derived
# variables, memberships, activated rules, diagnostics). The client contains
# no fuzzy logic: it checks the records, transports them and reconciles the
# receipt. The API has no validate endpoint for soil health: the synchronous
# publication validates everything before inserting anything (422 with the
# rejected rows), a job validates the whole file before promoting it.

health_score_statuses <- c("scored", "insufficient_data", "not_applicable")
health_source_supports <- c(
  "observed_point_profile", "polygon_estimate", "map_unit_profile_relation",
  "non_spatial_profile", "non_spatial_estimate"
)

health_receipt_schema <- c(publication_receipt_schema, list(score_count = "dbl"))

#' Publish soil-health scores
#'
#' Publishes the soil-health scores computed by an external model in an
#' open run of a product version that declares one or more of the variables
#' `soil_health_physical_score`, `soil_health_chemical_score`,
#' `soil_health_soc_score`. Each score is one horizon and one category; the
#' API publishes the generic value and the soil-health details in one
#' transaction.
#'
#' Local checks of every record before anything is sent: required fields
#' (`horizon_id` a UUID, `release_id`, `category_code`, `score_status`,
#' `source_support`), allowed `score_status` and `source_support`, score and
#' class consistency (a `scored` record has a numeric `score` and a
#' `score_class`; any other status has neither), observation inputs with an
#' `observation_id` (UUID) and an `input_role`, and no duplicate horizon,
#' category and release. Problems are a `soilhub_argument_error` whose
#' `errors` lists them by record.
#'
#' Up to 10,000 records are published synchronously
#' (`POST /publications/{run_id}/soil-health`; a rejected batch is a
#' `soilhub_validation_error` with the API's `errors`); above, or with
#' `transport = "ndjson"`, an NDJSON file with its SHA-256 checksum is
#' uploaded as a job (`POST /publications/{run_id}/soil-health/jobs`), never
#' repeated automatically. The same `idempotency_key` with the same content
#' returns the first receipt; any difference, even only in the memberships,
#' rules or diagnostics, is a `soilhub_conflict_error` (HTTP 409): use a new
#' key. The receipt is reconciled with the records sent (`published_count`,
#' `score_count`): a difference is a `soilhub_reconciliation_warning`.
#'
#' Rights: `soil:publish`. Capabilities: `publish_soil_health_sync`
#' (synchronous), `bulk_soil_health` (job).
#'
#' @inheritParams soil_publish_values
#' @param scores A data frame (list columns for nested fields) or a list of
#'   records with `horizon_id`, `release_id`, `category_code` (e.g.
#'   `"physical"`), `score_status` (`"scored"`, `"insufficient_data"`,
#'   `"not_applicable"`), `score`, `score_class`, `source_support`
#'   (`"observed_point_profile"`, `"polygon_estimate"`,
#'   `"map_unit_profile_relation"`, `"non_spatial_profile"`,
#'   `"non_spatial_estimate"`), and optionally `quality_code`,
#'   `observation_inputs` (list of `list(observation_id =, input_role =,
#'   required =, transformation =)`), `value_inputs`, `release_inputs`,
#'   `asset_inputs` (lists of `list(id =, role =)`), `inputs`,
#'   `derived_variables`, `memberships`, `diagnostics` (named lists) and
#'   `activated_rules` (list of named lists).
#' @return A `soil_publication` list as [soil_publish_values()], with
#'   `score_count` for a synchronous publication.
#' @family writing
#' @examples
#' \dontrun{
#' scores <- list(list(
#'   horizon_id = "4fa5fbe3-8fd4-4fb1-94cf-d07963eb50f7", release_id = 12L,
#'   category_code = "physical", score_status = "scored", score = 72.5,
#'   score_class = "good", source_support = "polygon_estimate",
#'   observation_inputs = list(list(
#'     observation_id = "46f252f1-5f38-4223-b329-88822f60fe75",
#'     input_role = "bulk_density", transformation = "membership_low_compaction"
#'   )),
#'   inputs = list(bulk_density = 1.31),
#'   memberships = list(poor = 0.1, moderate = 0.3, good = 0.8),
#'   activated_rules = list(list(rule = "physical_r4", strength = 0.7))
#' ))
#' soil_publish_health(soil, run$run_id, scores, "fuzzy-v1-india-2026-10")
#' }
#' @export
soil_publish_health <- function(soil = soil_session(), run_id, scores, idempotency_key,
                                transport = c("auto", "sync", "ndjson"),
                                wait = TRUE, timeout = 3600, poll = 5,
                                progress = interactive()) {
  what <- "`soil_publish_health()`"
  check_session(soil)
  soil_require_right(soil, "soil:publish", what)
  id <- check_id(run_id, "run_id")
  check_idempotency_key(idempotency_key)
  transport <- match.arg(transport)
  timeout <- check_timeout(timeout)
  poll <- check_timeout(poll, "poll")
  records <- as_records(scores, "scores")
  check_health_records(records)
  transport <- choose_transport(transport, length(records))

  if (identical(transport, "sync")) {
    soil_require_capability(soil, "publish_soil_health_sync", what)
    receipt <- with_conflict_advice(
      soil_request(
        soil, "POST", paste0("/publications/", id, "/soil-health"),
        body = list(idempotency_key = idempotency_key, scores = records),
        right = "soil:publish"
      ),
      paste0(
        publication_conflict_advice(),
        " For soil health any difference counts, also in memberships, rules or diagnostics."
      )
    )
    receipt <- typed_object(receipt, health_receipt_schema, "POST /publications/{run_id}/soil-health")
    out <- sync_publication(receipt, length(records), NULL,
                            extra = list(score_count = receipt$score_count))
    reconcile_publication(soil, out, c(scores = receipt$score_count))
    return(out)
  }

  soil_require_capability(soil, "bulk_soil_health", what)
  publish_job(
    soil, records, paste0("/publications/", id, "/soil-health/jobs"), idempotency_key,
    detail = "soil_health", wait = wait, timeout = timeout, poll = poll,
    progress = isTRUE(progress)
  )
}

check_health_records <- function(records) {
  if (length(records) == 0L) {
    abort(soilhub_argument_error("`scores` holds no record.", "scores"))
  }
  problems <- lapply(records, function(record) {
    issues <- character()
    if (!is_string(record[["horizon_id"]])) {
      issues <- c(issues, "horizon_id_missing")
    } else if (!grepl(uuid_pattern, record[["horizon_id"]])) {
      issues <- c(issues, "horizon_id_not_uuid")
    }
    release <- record[["release_id"]]
    if (is.null(release) || length(release) != 1L || !is.numeric(release) ||
        release != round(release)) {
      issues <- c(issues, "release_id_missing")
    }
    if (!is_string(record[["category_code"]])) issues <- c(issues, "category_code_missing")
    status <- record[["score_status"]]
    if (!is_string(status)) {
      issues <- c(issues, "score_status_missing")
    } else if (!status %in% health_score_statuses) {
      issues <- c(issues, "invalid_score_status")
    }
    if (!is_string(record[["source_support"]])) {
      issues <- c(issues, "source_support_missing")
    } else if (!record[["source_support"]] %in% health_source_supports) {
      issues <- c(issues, "invalid_source_support")
    }
    has_score <- !is.null(record[["score"]])
    has_class <- !is.null(record[["score_class"]])
    if (identical(status, "scored")) {
      if (!has_score || !is.numeric(record[["score"]]) || length(record[["score"]]) != 1L) {
        issues <- c(issues, "scored_without_numeric_score")
      }
      if (!has_class || !is_string(record[["score_class"]])) {
        issues <- c(issues, "scored_without_score_class")
      }
    } else if (is_string(status) && (has_score || has_class)) {
      issues <- c(issues, "non_scored_with_score_or_class")
    }
    issues <- c(issues, observation_input_issues(record[["observation_inputs"]]))
    issues
  })
  identity <- vapply(records, function(r) {
    paste(r[["horizon_id"]] %||% "", r[["category_code"]] %||% "", format(r[["release_id"]] %||% ""), sep = "|")
  }, character(1))
  duplicated_rows <- which(duplicated(identity))
  for (i in duplicated_rows) {
    problems[[i]] <- c(problems[[i]], "duplicate_horizon_category_release")
  }
  records_problems(problems, records, "scores", "horizon_id")
}

observation_input_issues <- function(inputs) {
  if (is.null(inputs)) return(character())
  items <- if (is.data.frame(inputs)) {
    lapply(seq_len(nrow(inputs)), function(i) frame_row_list(inputs, i))
  } else if (is.list(inputs) && is.null(names(inputs))) {
    inputs
  } else {
    return("observation_inputs_not_a_list")
  }
  ok <- vapply(items, function(item) {
    is.list(item) && is_string(item[["observation_id"]]) &&
      grepl(uuid_pattern, item[["observation_id"]]) && is_string(item[["input_role"]])
  }, logical(1))
  if (all(ok)) character() else "invalid_observation_input"
}
