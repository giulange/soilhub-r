#' @include typing.R
NULL

# Asynchronous jobs (design 4.6): the unified job registry of the API
# (`GET /jobs/{id}`, `POST /jobs/{id}/cancel`) and the dataset-specific views
# of publication jobs. Every job endpoint needs `soil:publish` (API fact
# 12.2.3), also for the job of an export; exports have their own reader
# functions (exports.R).
#
# Lifecycle (API `soil_api.jobs`): queued, running, validating, promoting,
# then one of the terminal states completed, failed, cancelled.

job_terminal_states <- c("completed", "failed", "cancelled")

unified_job_schema <- list(
  job_id = "chr", job_type = "chr", status = "chr", progress_percent = "dbl",
  received_count = "dbl", staged_count = "dbl", accepted_count = "dbl",
  rejected_count = "dbl", published_count = "dbl", checksum_sha256 = "chr",
  byte_size = "dbl", receipt_id = "chr", correlation_id = "chr",
  diagnostics = "json", error = "json", retry_count = "int",
  cancel_requested = "lgl", worker_id = "chr", lease_expires_at = "time",
  heartbeat_at = "time", created_at = "time", started_at = "time",
  finished_at = "time", updated_at = "time"
)

publication_job_schema <- list(
  job_id = "chr", run_id = "dbl", status = "chr", input_format = "chr",
  checksum_sha256 = "chr", byte_size = "dbl", staged_count = "dbl",
  published_count = "dbl", rejected_count = "dbl", diagnostics = "json",
  publication_id = "chr"
)

health_job_schema <- list(
  job_id = "chr", run_id = "dbl", status = "chr", input_format = "chr",
  checksum_sha256 = "chr", byte_size = "dbl", staged_count = "dbl",
  accepted_count = "dbl", rejected_count = "dbl", published_count = "dbl",
  publication_ids = "chr_list", diagnostics = "json"
)

job_views <- list(
  unified = list(path = "/jobs/", schema = unified_job_schema),
  publication = list(path = "/publication-jobs/", schema = publication_job_schema),
  soil_health = list(path = "/soil-health-publication-jobs/", schema = health_job_schema)
)

# A typed single object: the record typed by `schema` (typing.R), as a list.
typed_object <- function(x, schema, context) {
  request_id <- attr(x, "request_id")
  out <- frame_row_list(records_frame(x, schema, context))
  attr(out, "request_id") <- request_id
  out
}

new_soil_job <- function(x, view = "unified") {
  spec <- job_views[[view]]
  job <- typed_object(x, spec$schema, paste0("GET ", spec$path, "{job_id}"))
  structure(job, view = view, class = "soil_job")
}

check_job_id <- function(job_id) {
  if (inherits(job_id, "soil_job") || inherits(job_id, "soil_publication")) {
    job_id <- job_id$job_id
  }
  if (!is_string(job_id)) {
    abort(soilhub_argument_error(
      "`job_id` must be the id of a job (a string, as returned at submission).",
      "job_id"
    ))
  }
  job_id
}

#' The status of an asynchronous job
#'
#' Reads a job of the API: a bulk publication of values
#' ([soil_publish_values()] with `transport = "ndjson"`), of soil-health
#' scores, a source ingest, a country refresh or an export. The API keeps
#' no list of a user's jobs: the job id returned at submission is the only
#' handle, so keep it.
#'
#' `detail = "unified"` reads the common lifecycle of every job
#' (`GET /jobs/{job_id}`): `status` (`queued`, `running`, `validating`,
#' `promoting`, then `completed`, `failed` or `cancelled`),
#' `progress_percent`, the counts of received, staged, accepted, rejected and
#' published rows, the checksum and size of the uploaded file, the
#' publication receipt (`receipt_id`), `diagnostics` and `error`.
#' `"publication"` and `"soil_health"` read the views of a value or a
#' soil-health publication job (`GET /publication-jobs/{job_id}`,
#' `GET /soil-health-publication-jobs/{job_id}`), whose `diagnostics` hold the
#' rejected rows (at most 1,000, `diagnostics_truncated`) of a failed
#' validation.
#'
#' Rights: `soil:publish`.
#'
#' @param soil A session; the default session when omitted. Client-side: not sent to the API.
#' @param job_id The job id (or the result of a submission). API path parameter `{job_id}` of
#'   `GET /jobs/{job_id}` (also `GET /publication-jobs/{job_id}` and
#'   `GET /soil-health-publication-jobs/{job_id}`, by `detail`), `POST /jobs/{job_id}/cancel` and
#'   `POST /source-ingests/{job_id}/validate` or `/promote`.
#' @param detail Which view of the job: `"unified"`, `"publication"`,
#'   `"soil_health"`. Client-side; selects the endpoint read, not sent to the API.
#' @return A `soil_job` list with the fields of the view, typed (times as
#'   `POSIXct`, counts as numbers, `diagnostics` and `error` as lists).
#' @family jobs
#' @examples
#' \dontrun{
#' job <- soil_job(soil, "0b4e...")
#' job$status
#' soil_job(soil, job$job_id, detail = "publication")$diagnostics
#' }
#' @export
soil_job <- function(soil = soil_session(), job_id,
                     detail = c("unified", "publication", "soil_health")) {
  check_session(soil)
  soil_require_right(soil, "soil:publish", "`soil_job()`")
  job_id <- check_job_id(job_id)
  detail <- match.arg(detail)
  fetch_job(soil, job_id, detail)
}

fetch_job <- function(soil, job_id, detail = "unified") {
  spec <- job_views[[detail]]
  body <- soil_request(
    soil, "GET", paste0(spec$path, url_segment(job_id)), right = "soil:publish"
  )
  new_soil_job(body, detail)
}

#' Wait for a job to end
#'
#' Polls the job (`GET /jobs/{job_id}`) every `poll` seconds until it reaches
#' a terminal state. A `completed` job is returned; a `failed` or
#' `cancelled` job, or a job still running after `timeout` seconds, is a
#' `soilhub_job_error` holding the last status in `e$job` (the job itself
#' continues on the server after a timeout: wait again or cancel it with
#' [soil_job_cancel()]). Each poll is an ordinary request: the session is
#' renewed as needed, so a wait may last longer than the access token.
#'
#' Rights: `soil:publish`.
#'
#' @inheritParams soil_job
#' @param timeout Seconds to wait before giving up (default one hour). Client-side: not sent to the
#'   API.
#' @param poll Seconds between two polls. Client-side: not sent to the API.
#' @param progress Print a line each time the status or the progress
#'   changes. Client-side: not sent to the API.
#' @return The completed `soil_job` (unified view).
#' @family jobs
#' @examples
#' \dontrun{
#' job <- soil_job_wait(soil, "0b4e...", timeout = 600)
#' job$published_count
#' }
#' @export
soil_job_wait <- function(soil = soil_session(), job_id, timeout = 3600,
                          poll = 5, progress = interactive()) {
  check_session(soil)
  soil_require_right(soil, "soil:publish", "`soil_job_wait()`")
  job_id <- check_job_id(job_id)
  timeout <- check_timeout(timeout)
  poll <- check_timeout(poll, "poll")
  wait_job(soil, job_id, timeout, poll, isTRUE(progress))
}

# The polling loop: deadline on `soil_now()`, pauses through `http_sleep()`
# (both replaceable by tests).
wait_job <- function(soil, job_id, timeout, poll, progress) {
  deadline <- soil_now() + timeout
  shown <- NULL
  repeat {
    job <- fetch_job(soil, job_id)
    line <- sprintf(
      "soilhub: job %s %s (%s%%)", job_id, job$status,
      format(round(job$progress_percent %||% NA_real_))
    )
    if (progress && !identical(line, shown)) soilhub_message(line)
    shown <- line
    if (job$status %in% job_terminal_states) break
    remaining <- as.numeric(difftime(deadline, soil_now(), units = "secs"))
    if (remaining <= 0) {
      abort(soilhub_job_error(
        sprintf(
          paste0(
            "Job %s is still %s after %s s: it continues on the server. ",
            "Wait again with soil_job_wait(soil, \"%s\") or cancel it with soil_job_cancel()."
          ),
          job_id, job$status, format(timeout), job_id
        ),
        job = job, job_id = job_id, reason = "timeout"
      ))
    }
    http_sleep(min(poll, remaining))
  }
  if (identical(job$status, "completed")) return(job)
  error <- job$error
  why <- if (is.list(error) && !is.null(error$message)) {
    paste0(": ", error$message, if (!is.null(error$code)) paste0(" (", error$code, ")") else "")
  } else {
    ""
  }
  abort(soilhub_job_error(
    sprintf("Job %s (%s) ended %s%s.", job_id, job$job_type %||% "job", job$status, why),
    job = job, job_id = job_id, reason = job$status
  ))
}

#' Cancel a job
#'
#' Asks the API to cancel a job that has not ended (`POST
#' /jobs/{job_id}/cancel`); the worker stops at its next heartbeat. A job
#' that has already ended is returned unchanged, with a message.
#'
#' Rights: `soil:publish`.
#'
#' @inheritParams soil_job
#' @return The `soil_job` after the request (unified view): `status`
#'   `cancelled` and `cancel_requested` `TRUE`.
#' @family jobs
#' @examples
#' \dontrun{
#' soil_job_cancel(soil, "0b4e...")
#' }
#' @export
soil_job_cancel <- function(soil = soil_session(), job_id) {
  check_session(soil)
  soil_require_right(soil, "soil:publish", "`soil_job_cancel()`")
  job_id <- check_job_id(job_id)
  body <- with_conflict_advice(
    soil_request(
      soil, "POST", paste0("/jobs/", url_segment(job_id), "/cancel"),
      right = "soil:publish"
    ),
    "A job that has ended cannot change state: read it with soil_job()."
  )
  job <- new_soil_job(body)
  if (!isTRUE(job$cancel_requested) && job$status %in% job_terminal_states) {
    soil_inform(soil, 1, sprintf(
      "soilhub: job %s had already ended (%s); nothing was cancelled.", job_id, job$status
    ))
  }
  job
}

#' Refresh the country inventory
#'
#' Queues the recomputation of the daily country totals read by
#' [soil_countries()] (`POST /countries/refresh`). The job runs on the
#' server; follow it with [soil_job_wait()] (which needs `soil:publish`).
#'
#' Rights: `soil:admin`.
#'
#' @param soil A session; the default session when omitted. Client-side: not sent to the API.
#' @param idempotency_key Optional key: a second request with the same key
#'   returns the job already queued instead of queuing another one. API query parameter
#'   `idempotency_key`.
#' @return The queued `soil_job` (unified view).
#' @family jobs
#' @examples
#' \dontrun{
#' job <- soil_refresh_countries(soil, idempotency_key = "countries-2026-10-18")
#' soil_job_wait(soil, job$job_id)
#' }
#' @export
soil_refresh_countries <- function(soil = soil_session(), idempotency_key = NULL) {
  check_session(soil)
  soil_require_right(soil, "soil:admin", "`soil_refresh_countries()`")
  if (!is.null(idempotency_key)) check_idempotency_key(idempotency_key)
  body <- soil_request(
    soil, "POST", "/countries/refresh",
    query = list(idempotency_key = idempotency_key),
    # without a key a repeated request could queue a second refresh
    right = "soil:admin", retry = !is.null(idempotency_key)
  )
  new_soil_job(body)
}

#' @export
print.soil_job <- function(x, ...) {
  view <- attr(x, "view") %||% "unified"
  cat("<soil_job> ", x$job_id, if (!is.null(x$job_type) && !is.na(x$job_type)) paste0(" (", x$job_type, ")"), "\n", sep = "")
  status <- x$status
  if (!is.null(x$progress_percent) && !is.na(x$progress_percent)) {
    status <- sprintf("%s, %s%%", status, format(round(x$progress_percent)))
  }
  cat("  Status:  ", status, "\n", sep = "")
  counts <- c("received_count", "staged_count", "accepted_count", "rejected_count", "published_count")
  counts <- counts[counts %in% names(x)]
  values <- vapply(counts, function(n) {
    v <- x[[n]]
    if (is.null(v) || is.na(v)) NA_character_ else paste0(sub("_count$", "", n), " ", format_count(v))
  }, character(1))
  values <- values[!is.na(values)]
  if (length(values)) cat("  Rows:    ", paste(values, collapse = ", "), "\n", sep = "")
  receipt <- x$receipt_id %||% x$publication_id
  if (!is.null(receipt) && !is.na(receipt)) cat("  Receipt: ", receipt, "\n", sep = "")
  if (is.list(x$error) && !is.null(x$error$message)) {
    cat("  Error:   ", x$error$message, "\n", sep = "")
  }
  if (!identical(view, "unified")) cat("  View:    ", view, "\n", sep = "")
  invisible(x)
}

# ---------------------------------------------------------------------------
# Shared by the write functions.

# Re-signal a 409 with the way out appended (design 2.5: no GET exists to
# read the object in conflict, fact 12.2.6).
with_conflict_advice <- function(expr, advice) {
  tryCatch(expr, soilhub_conflict_error = function(e) {
    # A conflict found by a semantic check carries its errors as JSON text
    # (variable registration): give them as a data frame too.
    detail <- e$detail
    if (is_string(detail) && grepl("^\\s*[\\[{]", detail)) {
      parsed <- tryCatch(jsonlite::fromJSON(detail, simplifyVector = FALSE), error = function(err) NULL)
      if (!is.null(parsed)) e$errors <- validation_errors_frame(parsed)
    }
    e$message <- paste0(conditionMessage(e), "\n", advice)
    e$advice <- advice
    abort(e)
  })
}

check_idempotency_key <- function(key, argument = "idempotency_key") {
  if (!is_string(key) || nchar(key) > 200L) {
    abort(soilhub_argument_error(
      sprintf(
        paste0(
          "`%s` must be a non-empty string of at most 200 characters, stable for ",
          "one payload: a retry with the same key and the same content returns the ",
          "first receipt; different content needs a new key."
        ),
        argument
      ),
      argument
    ))
  }
  key
}
