# Publication of derived values (design 4.6): local checks of the records,
# server validation, then a synchronous publication (at most 10,000 rows per
# request, a limit of the API request model) or a checksummed NDJSON job.
# Shared with soil-health publication (publish-health.R): transport choice,
# upload (never retried, design 2.4), job wait and receipt reconciliation.

sync_publication_max <- 10000L
value_statuses <- c("published", "insufficient_data", "not_applicable")
lineage_groups <- c("observations", "values", "releases", "assets")
uuid_pattern <- "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

publication_receipt_schema <- list(
  publication_id = "chr", run_id = "dbl", status = "chr",
  received_count = "dbl", published_count = "dbl", idempotent_replay = "lgl"
)

#' Publish derived values
#'
#' Publishes the values computed by an external model in an open run
#' ([soil_run_open()]), against existing canonical targets (feature,
#' profile, component or horizon ids). The hub stores, validates and serves
#' them; it runs no model.
#'
#' Steps:
#' 1. local checks of every record (required fields, target level and id,
#'    `value_status` and value, lineage, depth and time intervals): problems
#'    are a `soilhub_argument_error` whose `errors` lists them by record;
#' 2. with `validate = TRUE`, server validation without writing
#'    (`POST /publications/{run_id}/validate`: run open, variables declared
#'    by the version, targets and lineage existing, typed values, duplicates);
#'    an invalid batch is a `soilhub_validation_error` with the API's
#'    `errors` (`row` is 0-based, `record` the 1-based record);
#' 3. publication: synchronous (`POST /publications/{run_id}/values`) up to
#'    10,000 records, else (`transport = "ndjson"`, or `"auto"` above 10,000)
#'    an NDJSON file with its SHA-256 checksum uploaded as a job
#'    (`POST /publications/{run_id}/jobs`). Before an upload with
#'    `validate = TRUE` the client checks that every `variable_code` is
#'    registered ([soil_variables()]); the job validates the whole file on
#'    the server before publishing anything.
#'
#' The upload is never repeated automatically and has no total timeout
#' (only the connection timeout). Publication is idempotent:
#' the same `idempotency_key` with the same content returns the first
#' receipt (`idempotent_replay = TRUE`) or the job already submitted, so
#' after a transport failure call the function again with the same key and
#' the same values. The same key with different content is a
#' `soilhub_conflict_error` (HTTP 409): use a new key.
#'
#' The receipt is reconciled with the records sent: a `published_count`
#' different from their number is a `soilhub_reconciliation_warning`; do
#' not complete the run until it is understood.
#'
#' Rights: `soil:publish`. Capabilities: `publish_generic_values`
#' (synchronous), `generic_bulk_publication` (job).
#'
#' @param soil A session; the default session when omitted. Client-side: not sent to the API.
#' @param run_id The id of an open run. API path parameter `{run_id}` of
#'   `POST /publications/{run_id}/values`, `/validate` and `/jobs` (for [soil_publish_health()]:
#'   `/soil-health` and `/soil-health/jobs`).
#' @param values A data frame (list columns for nested fields) or a list of
#'   records with `variable_code`, `target_level`, `target_id` (UUID),
#'   `value` (typed as the variable: number, text, logical, or a list for
#'   `json`), `value_status` (`"published"`, the default, needs a value;
#'   `"insufficient_data"` and `"not_applicable"` none), `release_id`,
#'   `quality_code`, `valid_time_start`, `valid_time_end`, `depth_top_cm`,
#'   `depth_bottom_cm` (optional) and `lineage`: a list with one or more of
#'   `observations`, `values`, `releases`, `assets`, each a list of
#'   `list(id =, role =, transformation =)` (or a data frame), at least one
#'   item in all. `NA` fields are left out. API field `values`; with the NDJSON transport, the lines
#'   of the file sent as API form field `file`.
#' @param idempotency_key Key of this publication (at most 200 characters),
#'   stable for one content. API field `idempotency_key` of a synchronous publication; API query
#'   parameter `idempotency_key` of an NDJSON upload.
#' @param validate Validate on the server before publishing. Client-side: decides whether
#'   `POST /publications/{run_id}/validate` is called first; not sent to the API.
#' @param transport `"auto"` (synchronous up to 10,000 records, else
#'   NDJSON), `"sync"` or `"ndjson"`. Client-side: not sent to the API.
#' @param wait For a job: wait for it to end (see [soil_job_wait()]). Client-side: not sent to the
#'   API.
#' @param timeout,poll Seconds to wait for a job, and between two polls. Client-side: not sent to
#'   the API.
#' @param progress Print the progress of the job. Client-side: not sent to the API.
#' @return A `soil_publication` list: `transport`, `run_id`, `status`,
#'   `record_count` (records sent), `received_count`, `published_count`,
#'   `publication_id` (the receipt), `idempotent_replay`, `validation` (the
#'   server validation, or `NULL`), and for a job `job_id`, `job` (the last
#'   `soil_job`), `checksum_sha256`, `byte_size`. With `wait = FALSE` the
#'   job is returned as submitted (`status` `queued`): follow it with
#'   [soil_job_wait()]. A job that fails is a `soilhub_job_error` whose
#'   `errors` holds the rejected rows reported by the job.
#' @family writing
#' @examples
#' \dontrun{
#' values <- data.frame(
#'   variable_code = "soil_health_physical_score", target_level = "horizon",
#'   target_id = horizon_ids, value = scores
#' )
#' values$lineage <- lapply(observation_ids, function(id) {
#'   list(observations = list(list(id = id, role = "bulk_density")))
#' })
#' receipt <- soil_publish_values(soil, run$run_id, values, "pub-india-2026-10-a")
#' receipt$published_count
#' }
#' @export
soil_publish_values <- function(soil = soil_session(), run_id, values, idempotency_key,
                                validate = TRUE,
                                transport = c("auto", "sync", "ndjson"),
                                wait = TRUE, timeout = 3600, poll = 5,
                                progress = interactive()) {
  what <- "`soil_publish_values()`"
  check_session(soil)
  soil_require_right(soil, "soil:publish", what)
  id <- check_id(run_id, "run_id")
  check_idempotency_key(idempotency_key)
  transport <- match.arg(transport)
  timeout <- check_timeout(timeout)
  poll <- check_timeout(poll, "poll")
  records <- as_records(values, "values")
  check_value_records(records)
  transport <- choose_transport(transport, length(records))

  if (identical(transport, "sync")) {
    soil_require_capability(soil, "publish_generic_values", what)
    body <- list(idempotency_key = idempotency_key, values = records)
    validation <- NULL
    if (isTRUE(validate)) {
      validation <- validate_values(soil, id, body)
    }
    receipt <- with_conflict_advice(
      soil_request(soil, "POST", paste0("/publications/", id, "/values"),
                   body = body, right = "soil:publish"),
      publication_conflict_advice()
    )
    receipt <- typed_object(receipt, publication_receipt_schema, "POST /publications/{run_id}/values")
    out <- sync_publication(receipt, length(records), validation)
    reconcile_publication(soil, out)
    return(out)
  }

  soil_require_capability(soil, "generic_bulk_publication", what)
  if (isTRUE(validate)) check_variables_exist(soil, records)
  publish_job(
    soil, records, paste0("/publications/", id, "/jobs"), idempotency_key,
    detail = "publication", wait = wait, timeout = timeout, poll = poll,
    progress = isTRUE(progress)
  )
}

choose_transport <- function(transport, n) {
  if (identical(transport, "auto")) {
    return(if (n <= sync_publication_max) "sync" else "ndjson")
  }
  if (identical(transport, "sync") && n > sync_publication_max) {
    abort(soilhub_argument_error(
      sprintf(
        "A synchronous publication holds at most %s records (here %s): use transport = \"ndjson\" or \"auto\".",
        format_count(sync_publication_max), format_count(n)
      ),
      "transport"
    ))
  }
  transport
}

validate_values <- function(soil, id, body) {
  validation <- soil_request(
    soil, "POST", paste0("/publications/", id, "/validate"),
    body = body, right = "soil:publish"
  )
  errors <- publication_errors(validation$errors)
  result <- list(
    valid = isTRUE(validation$valid),
    run_id = validation$run_id %||% NA,
    received_count = validation$received_count %||% NA,
    errors = errors
  )
  if (!result$valid) {
    abort(local_validation_error(
      sprintf(
        "The server rejected the publication of %s record(s) in run %s; nothing was published.",
        format_count(length(body$values)), id
      ),
      errors, endpoint = paste0("/publications/", id, "/validate"),
      request_id = attr(validation, "request_id")
    ))
  }
  result
}

# The `errors` of a publication validation as a data frame, with `record`
# (1-based) next to the API's 0-based `row`.
publication_errors <- function(errors) {
  frame <- validation_errors_frame(list(errors = errors %||% list()))
  if ("row" %in% names(frame)) {
    frame$record <- suppressWarnings(as.integer(frame$row)) + 1L
  }
  frame
}

publication_conflict_advice <- function() {
  paste0(
    "The idempotency key was already used with other content: a retry must send the ",
    "same records with the same key; new or corrected records need a new key."
  )
}

new_soil_publication <- function(fields) {
  structure(fields, class = "soil_publication")
}

sync_publication <- function(receipt, n, validation, extra = list()) {
  new_soil_publication(c(
    list(
      transport = "sync",
      run_id = receipt$run_id,
      status = receipt$status,
      record_count = n,
      received_count = receipt$received_count,
      published_count = receipt$published_count,
      publication_id = receipt$publication_id,
      idempotent_replay = isTRUE(receipt$idempotent_replay),
      validation = validation
    ),
    extra,
    list(request_id = attr(receipt, "request_id"))
  ))
}

# Records sent vs received and published (ops runbook: every receipt has
# received_count == published_count before the run is completed).
reconcile_publication <- function(soil, x, extra = NULL) {
  if (isTRUE(x$idempotent_replay)) {
    soil_inform(soil, 1, sprintf(
      "soilhub: publication %s was already made with this key and content (idempotent replay).",
      x$publication_id
    ))
  }
  counts <- c(received = x$received_count, published = x$published_count, extra)
  counts <- counts[!is.na(counts)]
  off <- counts[counts != x$record_count]
  if (length(off)) {
    soilhub_warning(sprintf(
      paste0(
        "The receipt of run %s does not reconcile with the %s record(s) sent: %s. ",
        "Do not complete the run before the difference is understood."
      ),
      format(x$run_id), format_count(x$record_count),
      paste(paste(names(off), format_count(off)), collapse = ", ")
    ), "soilhub_reconciliation_warning")
  }
  invisible(x)
}

# Upload the records as an NDJSON job (never retried), then wait.
publish_job <- function(soil, records, path, idempotency_key, detail, wait,
                        timeout, poll, progress) {
  file <- write_ndjson(records)
  on.exit(unlink(file$path), add = TRUE)
  submitted <- with_conflict_advice(
    soil_request(
      soil, "POST", path,
      query = list(
        idempotency_key = idempotency_key, input_format = "ndjson",
        expected_checksum = file$checksum_sha256
      ),
      body = upload_body(file$path), timeout = Inf, retry = FALSE,
      right = "soil:publish"
    ),
    paste0(
      publication_conflict_advice(),
      " (A 409 also reports a run that is not open, a file above the size limit or a ",
      "checksum that does not match.)"
    )
  )
  job <- new_soil_job(submitted, detail)
  soil_inform(soil, 1, sprintf(
    "soilhub: %s record(s) uploaded (%s bytes, sha256 %s) as job %s; keep this id.",
    format_count(file$row_count), format_count(file$byte_size),
    file$checksum_sha256, job$job_id
  ))
  if (!identical(job$checksum_sha256, file$checksum_sha256)) {
    abort(soilhub_api_error(
      sprintf(
        "The API recorded the checksum %s for job %s, not the checksum of the file sent (%s).",
        job$checksum_sha256, job$job_id, file$checksum_sha256
      ),
      endpoint = path, method = "POST", code = "checksum_mismatch",
      request_id = attr(job, "request_id")
    ))
  }
  out <- list(
    transport = "ndjson", run_id = job$run_id, status = job$status,
    record_count = file$row_count, received_count = NA_real_,
    published_count = NA_real_, publication_id = NA_character_,
    idempotent_replay = FALSE, validation = NULL, job_id = job$job_id,
    job = job, checksum_sha256 = file$checksum_sha256,
    byte_size = file$byte_size, request_id = attr(job, "request_id")
  )
  if (!isTRUE(wait)) return(new_soil_publication(out))

  final <- tryCatch(
    wait_job(soil, job$job_id, timeout, poll, progress),
    soilhub_job_error = function(e) {
      if (!identical(e$reason, "timeout")) {
        view <- tryCatch(fetch_job(soil, job$job_id, detail), soilhub_error = function(err) NULL)
        if (!is.null(view)) {
          e$job_detail <- view
          rejected <- view$diagnostics$errors
          if (length(rejected)) {
            e$errors <- publication_errors(rejected)
            e$message <- paste0(conditionMessage(e), errors_summary(e$errors))
          }
        }
      }
      abort(e)
    }
  )
  out$job <- final
  out$status <- final$status
  out$received_count <- final$received_count
  out$published_count <- final$published_count
  out$publication_id <- final$receipt_id
  out$staged_count <- final$staged_count
  out <- new_soil_publication(out)
  reconcile_publication(soil, out, c(staged = final$staged_count))
  out
}

#' @export
print.soil_publication <- function(x, ...) {
  cat("<soil_publication> run ", format(x$run_id), ", ", x$transport, "\n", sep = "")
  cat("  Status:    ", x$status %||% NA, if (isTRUE(x$idempotent_replay)) " (idempotent replay)", "\n", sep = "")
  shown <- c(sent = x$record_count, received = x$received_count,
             published = x$published_count, scores = x$score_count)
  shown <- shown[!is.na(shown)]
  cat("  Records:   ", paste(names(shown), format_count(shown), collapse = ", "), "\n", sep = "")
  if (!is.null(x$publication_id) && !is.na(x$publication_id)) {
    cat("  Receipt:   ", x$publication_id, "\n", sep = "")
  }
  if (!is.null(x$job_id)) {
    cat("  Job:       ", x$job_id, "\n", sep = "")
    cat("  File:      ", format_count(x$byte_size), " bytes, sha256 ", x$checksum_sha256, "\n", sep = "")
  }
  invisible(x)
}

# ---------------------------------------------------------------------------
# Local checks (no network).

check_value_records <- function(records) {
  if (length(records) == 0L) {
    abort(soilhub_argument_error("`values` holds no record.", "values"))
  }
  problems <- lapply(seq_along(records), function(i) {
    record <- records[[i]]
    issues <- character()
    for (field in c("variable_code", "target_level", "target_id")) {
      if (!is_string(record[[field]])) issues <- c(issues, paste0(field, "_missing"))
    }
    if (is_string(record[["target_level"]]) && !record[["target_level"]] %in% target_levels) {
      issues <- c(issues, "invalid_target_level")
    }
    if (is_string(record[["target_id"]]) && !grepl(uuid_pattern, record[["target_id"]])) {
      issues <- c(issues, "target_id_not_uuid")
    }
    status <- record[["value_status"]] %||% "published"
    if (!is_string(status) || !status %in% value_statuses) {
      issues <- c(issues, "invalid_value_status")
    } else if (identical(status, "published") && is.null(record[["value"]])) {
      issues <- c(issues, "published_value_missing")
    } else if (!identical(status, "published") && !is.null(record[["value"]])) {
      issues <- c(issues, "non_published_status_must_not_have_value")
    }
    issues <- c(issues, lineage_issues(record[["lineage"]]))
    issues <- c(issues, interval_issues(record))
    issues
  })
  records_problems(problems, records, "values", "variable_code")
}

lineage_issues <- function(lineage) {
  if (is.null(lineage)) return("lineage_missing")
  if (!is.list(lineage) || is.null(names(lineage))) return("lineage_not_a_list")
  unknown <- setdiff(names(lineage), lineage_groups)
  issues <- if (length(unknown)) paste0("unknown_lineage_group_", unknown) else character()
  items <- sum(vapply(lineage[intersect(names(lineage), lineage_groups)], function(group) {
    if (is.data.frame(group)) nrow(group) else length(group)
  }, numeric(1)))
  if (items == 0) issues <- c(issues, "lineage_required")
  issues
}

interval_issues <- function(record) {
  issues <- character()
  top <- record[["depth_top_cm"]]
  bottom <- record[["depth_bottom_cm"]]
  if (is.numeric(top) && is.numeric(bottom) && top > bottom) {
    issues <- c(issues, "invalid_depth_interval")
  }
  start <- record[["valid_time_start"]]
  end <- record[["valid_time_end"]]
  if (is_string(start) && is_string(end)) {
    times <- parse_api_time(c(start, end))
    if (!anyNA(times) && times[1] > times[2]) issues <- c(issues, "invalid_time_interval")
  }
  issues
}

# Raise the local problems of the records, if any, as one argument error
# with an `errors` data frame (`record`, `<key>`, `errors`).
records_problems <- function(problems, records, argument, key) {
  bad <- which(lengths(problems) > 0L)
  if (length(bad) == 0L) return(invisible(TRUE))
  keys <- vapply(records[bad], function(r) {
    value <- r[[key]]
    if (is.null(value) || length(value) != 1L) NA_character_ else as.character(value)
  }, character(1))
  errors <- data.frame(record = bad, stringsAsFactors = FALSE)
  errors[[key]] <- keys
  errors$errors <- vapply(problems[bad], paste, character(1), collapse = ", ")
  abort(new_soilhub_error(
    "soilhub_argument_error",
    paste0(
      sprintf(
        "%s of the %s record(s) of `%s` fail the local checks; nothing was sent.",
        format_count(length(bad)), format_count(length(records)), argument
      ),
      errors_summary(errors)
    ),
    argument = argument, errors = errors
  ))
}

# Before an upload: every variable code must be registered (the job would
# only find it after the upload). Skipped when the catalog cannot be read
# with the session's rights (the API decides).
check_variables_exist <- function(soil, records) {
  codes <- unique(vapply(records, function(r) r[["variable_code"]], character(1)))
  known <- tryCatch(
    soil_variables(soil, code = codes)$variable_code,
    soilhub_permission_error = function(e) NULL
  )
  if (is.null(known)) return(invisible(NA))
  missing <- setdiff(codes, known)
  if (length(missing)) {
    abort(soilhub_argument_error(
      sprintf(
        paste0(
          "The variable(s) %s are not registered: register them with ",
          "soil_register_variable() and declare them in the product version; nothing was sent."
        ),
        paste0("`", missing, "`", collapse = ", ")
      ),
      "values"
    ))
  }
  invisible(TRUE)
}
