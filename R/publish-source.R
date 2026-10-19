#' @include jobs.R ndjson.R publish-values.R publish-health.R
NULL

# Source ingest (design 4.6, decision 6): a provider-neutral source bundle --
# features (an `sf` object or a GeoJSON file), profiles, components, horizons
# and original observations, one NDJSON record each -- uploaded with its
# manifest and SHA-256 checksum (`POST /source-ingests`, multipart, never
# retried: design 2.4), validated (`POST /source-ingests/{id}/validate`) and
# promoted (`POST /source-ingests/{id}/promote`) as an immutable release.
#
# The API stages the file, checks identities, hierarchy, geometry and
# observation declarations, and reports bounded row errors and the property
# codes it cannot map (mappings are resolved on the server from its
# property mappings of the provider: the manifest has no `property_mappings`
# field, API fact 12.2.14). With `auto_promote = TRUE` the server's ingest
# worker validates and promotes the job; the client only waits.
#
# Everything checkable without the API is checked before any request:
# manifest fields, `source_record_id` present and unique per record type,
# parent references, observation declarations, CRS (transformed to WGS84)
# and geometry types. The counts staged and published by the API are
# verified against the records sent.

source_record_types <- c("feature", "profile", "component", "horizon", "observation")
source_parent_fields <- c(
  profile = "feature_source_id", component = "profile_source_id",
  horizon = "component_source_id", observation = "horizon_source_id"
)
source_parent_types <- c(
  profile = "feature", component = "profile", horizon = "component",
  observation = "horizon"
)
source_tables <- c(
  feature = "features", profile = "profiles", component = "components",
  horizon = "horizons", observation = "observations"
)
source_geometry_kinds <- c("POINT", "POLYGON", "MULTIPOLYGON", "NONE")
source_geojson_types <- c(Point = "POINT", Polygon = "POLYGON", MultiPolygon = "MULTIPOLYGON")
source_observation_statuses <- c("observed", "computed")
source_manifest_required <- c(
  "provider_code", "provider_name", "dataset_code", "dataset_name",
  "release_code", "support_type", "default_geometry_kind"
)
source_manifest_optional <- c(
  "provider_website_url", "dataset_description", "source_url",
  "release_checksum_sha256", "licence_text", "citation_text",
  "source_table_prefix", "assets"
)
sha256_pattern <- "^[a-f0-9]{64}$"
source_code_pattern <- "^[a-z0-9_]+$"

#' Publish a source release: features, profiles, horizons, observations
#'
#' Admits a provider dataset release into the hub as new canonical
#' geography and original observations: builds a provider-neutral source
#' bundle (one NDJSON record per feature, profile, component, horizon and
#' observation), uploads it with its manifest and SHA-256 checksum, has the
#' API validate it and promotes it as an immutable release. New geography
#' never goes through the publication of derived values
#' ([soil_publish_values()]).
#'
#' Before any request the client checks, and lists by record in the
#' `errors` of a `soilhub_argument_error`:
#' * the manifest (required fields, codes of lowercase letters, digits and
#'   `_`, `support_type`, `default_geometry_kind`, checksums, assets);
#' * every record has a `source_record_id`, unique within its record type
#'   (text, or whole numbers turned into text);
#' * every profile, component, horizon and observation names an existing
#'   parent (`feature_source_id`, `profile_source_id`, `component_source_id`,
#'   `horizon_source_id`);
#' * every observation has `property_code`, a `unit` declaration and a
#'   `status` `"observed"` or `"computed"`;
#' * features have a CRS (an `sf` object without one is refused; any other
#'   CRS is transformed to WGS84, EPSG:4326, the only CRS of the API) and
#'   `POINT`, `POLYGON` or `MULTIPOLYGON` geometries, neither empty nor with
#'   missing coordinates.
#'
#' Steps, with `wait = TRUE`:
#' 1. upload (`POST /source-ingests`, never repeated automatically, no total
#'    timeout); the API records the checksum of the file received, compared
#'    with the checksum of the file sent;
#' 2. with `auto_promote = FALSE` (default) the client validates
#'    (`POST /source-ingests/{job_id}/validate`): an invalid bundle is a
#'    `soilhub_validation_error` whose `errors` lists the rejected records
#'    (`record_number` in the bundle, `record_type`, `row` of its table) and
#'    the job fails; the counts staged by the API, per record type and in
#'    all, must equal the records sent, else a `soilhub_api_error` (code
#'    `staged_count_mismatch`) and nothing is promoted; then it promotes
#'    (`POST /source-ingests/{job_id}/promote`);
#' 3. with `auto_promote = TRUE` the server's ingest worker validates and
#'    promotes the job, and the client waits for it ([soil_job_wait()]);
#'    a failed job is a `soilhub_job_error` with the rejected records in
#'    `errors`;
#' 4. the published counts are reconciled with the records sent (a
#'    difference is a `soilhub_reconciliation_warning`).
#'
#' Property codes that the API cannot map to a variable of the hub are a
#' `soilhub_unmapped_properties_warning`: their observations are stored
#' with the original code and do not appear under a canonical variable
#' until a mapping exists (see [soil_variable_mappings()]).
#'
#' With `wait = FALSE` the function returns after the upload: follow the job
#' with [soil_source_validate()] and [soil_source_promote()] (or
#' [soil_job_wait()] when `auto_promote = TRUE`). The API keeps no list of a
#' user's jobs: keep the `job_id`.
#'
#' The same `idempotency_key` with the same file returns the job already
#' submitted (a completed job is returned as it is, an ended one is a
#' `soilhub_job_error`); the same key with another file is a
#' `soilhub_conflict_error` (HTTP 409): use a new key. Releases are
#' immutable: a `release_code` already promoted for the dataset makes the
#' promotion fail.
#'
#' Rights: `soil:publish`. Capability: `source_ingest`.
#'
#' @param soil A session; the default session when omitted.
#' @param manifest A named list describing the release: `provider_code`,
#'   `provider_name`, `dataset_code`, `dataset_name`, `release_code`,
#'   `support_type` (`"observed_point_profile"`, `"polygon_estimate"`,
#'   `"map_unit_profile_relation"`, `"non_spatial_profile"`,
#'   `"non_spatial_estimate"`), `default_geometry_kind` (`"POINT"`,
#'   `"POLYGON"`, `"MULTIPOLYGON"`, `"NONE"`), and optionally
#'   `provider_website_url`, `dataset_description`, `source_url`,
#'   `release_checksum_sha256`, `licence_text`, `citation_text`,
#'   `source_table_prefix` and `assets` (a data frame or list of records
#'   with `asset_role`, `source_url`, `checksum_sha256`, `media_type`,
#'   `byte_size`). Property mappings are not part of the manifest: the API
#'   resolves them from its own mappings of the provider.
#' @param features The features of the release, each with a
#'   `source_record_id` column: an `sf` object (needs the package `sf`), or
#'   the path of a spatial file -- a GeoJSON file (`.geojson`, `.json`) is
#'   read without `sf` when in WGS84, any other format is read with
#'   [sf::st_read()]. The other columns travel as attributes of the feature
#'   record (`source_support`, ...). For a non-spatial dataset
#'   (`default_geometry_kind = "NONE"`), a plain data frame.
#' @param profiles,components,horizons,observations Optional data frames (or
#'   lists of records) of the other record types, each with its
#'   `source_record_id` and the `source_record_id` of its parent
#'   (`feature_source_id`, `profile_source_id`, `component_source_id`,
#'   `horizon_source_id`). Horizons carry `top_depth_cm`,
#'   `bottom_depth_cm`, `horizon_name`; components `component_rank`,
#'   `proportion_percent`; observations `property_code`, `value`, `unit`,
#'   `status`, and optionally `method` and `quality`. `NA` fields are left
#'   out (an observation needs its `unit` declared).
#' @param idempotency_key Key of this ingest (at most 200 characters), stable
#'   for one bundle.
#' @param auto_promote Let the server validate and promote the job (`TRUE`),
#'   or validate and promote from the client (`FALSE`).
#' @param wait Validate, promote and wait for the end of the job; `FALSE`
#'   returns after the upload.
#' @param keep_file Keep the NDJSON bundle written for the upload: its path
#'   is in `file` (a temporary file, removed when the R session ends; copy
#'   it to keep it longer). By default it is deleted.
#' @param timeout,poll Seconds to wait for the job, and between two polls.
#' @param progress Print the progress of the job.
#' @return A `soil_source_ingest` list: `job_id`, `status`, `provider_code`,
#'   `dataset_code`, `release_code`, `auto_promote`, `record_count` (records
#'   sent), `record_counts` (sent, by record type), `staged_counts` (staged
#'   by the API, by record type), `published_count`, `release_id`,
#'   `receipt_id`, `validation` (a `soil_source_validation`, or `NULL`),
#'   `unmapped_property_codes`, `job` (the last `soil_job`),
#'   `checksum_sha256`, `byte_size` and `file` (the bundle path with
#'   `keep_file = TRUE`, else `NULL`).
#' @family writing
#' @seealso [soil_source_validate()], [soil_source_promote()], [soil_job()]
#' @examples
#' \dontrun{
#' library(sf)
#' sites <- st_as_sf(
#'   data.frame(source_record_id = c("P1", "P2"), x = c(500100, 501200), y = c(4520300, 4521900)),
#'   coords = c("x", "y"), crs = 32633
#' )
#' manifest <- list(
#'   provider_code = "unina", provider_name = "University of Naples Federico II",
#'   dataset_code = "campania_profiles", dataset_name = "Campania soil profiles",
#'   release_code = "2026-10", support_type = "observed_point_profile",
#'   default_geometry_kind = "POINT", licence_text = "CC-BY 4.0"
#' )
#' profiles <- data.frame(source_record_id = c("P1", "P2"), feature_source_id = c("P1", "P2"))
#' components <- data.frame(source_record_id = c("P1", "P2"), profile_source_id = c("P1", "P2"))
#' horizons <- data.frame(
#'   source_record_id = c("P1-1", "P2-1"), component_source_id = c("P1", "P2"),
#'   top_depth_cm = 0, bottom_depth_cm = 30
#' )
#' observations <- data.frame(
#'   source_record_id = c("P1-1-orgc", "P2-1-orgc"), horizon_source_id = c("P1-1", "P2-1"),
#'   property_code = "orgc", value = c(12.1, 8.4), unit = "g/kg", status = "observed"
#' )
#' ingest <- soil_publish_source(
#'   soil, manifest, sites, profiles, components, horizons, observations,
#'   idempotency_key = "campania-2026-10"
#' )
#' ingest$release_id
#' }
#' @export
soil_publish_source <- function(soil = soil_session(), manifest, features,
                                profiles = NULL, components = NULL,
                                horizons = NULL, observations = NULL,
                                idempotency_key, auto_promote = FALSE,
                                wait = TRUE, keep_file = FALSE, timeout = 3600,
                                poll = 5, progress = interactive()) {
  what <- "`soil_publish_source()`"
  check_session(soil)
  soil_require_right(soil, "soil:publish", what)
  check_idempotency_key(idempotency_key)
  auto_promote <- check_flag(auto_promote, "auto_promote")
  wait <- check_flag(wait, "wait")
  keep_file <- check_flag(keep_file, "keep_file")
  timeout <- check_timeout(timeout)
  poll <- check_timeout(poll, "poll")
  progress <- isTRUE(progress)
  manifest <- source_manifest(manifest)
  bundle <- source_bundle(manifest, features, profiles, components, horizons, observations)
  soil_require_capability(soil, "source_ingest", what)

  path <- tempfile("soilhub-source-", fileext = ".ndjson")
  if (!keep_file) on.exit(unlink(path), add = TRUE)
  file <- write_ndjson(bundle$records, path)
  if (keep_file) {
    soil_inform(soil, 1, sprintf("soilhub: source bundle kept at %s", path))
  }
  job <- source_upload(soil, file, manifest, idempotency_key, auto_promote)

  out <- list(
    job_id = job$job_id, status = job$status,
    provider_code = manifest$provider_code, dataset_code = manifest$dataset_code,
    release_code = manifest$release_code, auto_promote = auto_promote,
    record_count = file$row_count, record_counts = bundle$counts,
    staged_counts = NULL, published_count = NA_real_, release_id = NA_real_,
    receipt_id = NA_character_, validation = NULL,
    unmapped_property_codes = character(), job = job,
    checksum_sha256 = file$checksum_sha256, byte_size = file$byte_size,
    file = if (keep_file) path else NULL,
    request_id = attr(job, "request_id")
  )
  if (!wait) return(new_soil_source_ingest(out))

  validation <- NULL
  if (identical(job$status, "completed")) {
    soil_inform(soil, 1, sprintf(
      "soilhub: source ingest %s was already completed with this key and file (idempotent replay).",
      job$job_id
    ))
    final <- job
  } else if (job$status %in% c("failed", "cancelled")) {
    abort(soilhub_job_error(
      sprintf(
        paste0(
          "Source ingest %s, submitted before with this key and file, ended %s: ",
          "submit the corrected bundle with a new idempotency_key."
        ),
        job$job_id, job$status
      ),
      job = job, job_id = job$job_id, reason = job$status
    ))
  } else if (auto_promote || identical(job$status, "promoting")) {
    final <- source_wait(soil, job$job_id, timeout, poll, progress, bundle)
    source_check_staged(job$job_id, bundle, final, promoted = TRUE)
  } else {
    validation <- source_validate_when_ready(soil, job$job_id, timeout, poll, bundle)
    if (!validation$valid) {
      rejected <- length(unique(validation$errors$record_number))
      err <- local_validation_error(
        sprintf(
          paste0(
            "The API rejected the source bundle of job %s: %s of %s record(s) fail validation; ",
            "nothing was promoted and the job failed. Correct the records and submit them ",
            "with a new idempotency_key."
          ),
          job$job_id, format_count(rejected), format_count(file$row_count)
        ),
        validation$errors,
        endpoint = paste0("/source-ingests/", job$job_id, "/validate"),
        request_id = validation$request_id
      )
      err$job_id <- job$job_id
      err$validation <- validation
      abort(err)
    }
    source_check_staged(
      job$job_id, bundle, fetch_job(soil, job$job_id), validation$counts,
      promoted = FALSE
    )
    out$staged_counts <- validation$counts
    source_warn_unmapped(validation$unmapped_property_codes, manifest)
    final <- source_promote_request(soil, job$job_id)
    if (!final$status %in% job_terminal_states) {
      final <- source_wait(soil, job$job_id, timeout, poll, progress, bundle)
    }
  }

  diagnostics <- if (is.list(final$diagnostics)) final$diagnostics else list()
  if (is.null(validation)) {
    validation <- source_validation_from_job(final, bundle)
    if (length(validation$unmapped_property_codes)) {
      source_warn_unmapped(validation$unmapped_property_codes, manifest)
    }
  }
  out$validation <- validation
  out$unmapped_property_codes <- validation$unmapped_property_codes
  out$staged_counts <- out$staged_counts %||% source_counts(diagnostics$counts)
  out$job <- final
  out$status <- final$status
  out$published_count <- final$published_count %||% NA_real_
  out$receipt_id <- final$receipt_id %||% NA_character_
  out$release_id <- if (is.numeric(diagnostics$release_id)) as.numeric(diagnostics$release_id) else NA_real_
  out <- new_soil_source_ingest(out)
  source_reconcile(out, source_counts(diagnostics$counts))
  out
}

#' Validate or promote a source ingest job
#'
#' The two server steps of [soil_publish_source()], for a job uploaded with
#' `wait = FALSE`.
#'
#' `soil_source_validate()` (`POST /source-ingests/{job_id}/validate`) stages
#' the uploaded file and checks identities, hierarchy, geometry and
#' observation declarations; it can be repeated while the job is
#' `validating`. An invalid bundle is not an error here: the report has
#' `valid = FALSE`, the rejected records in `errors` (at most 1,000,
#' `diagnostics_truncated`), and the job fails.
#'
#' `soil_source_promote()` (`POST /source-ingests/{job_id}/promote`)
#' publishes a validated job in one transaction: provider, dataset, release
#' (immutable: an existing `release_code` makes it fail), assets, canonical
#' features, profiles, components, horizons and observations, coverage and
#' receipt. Promoting a completed job returns it unchanged. A job that has
#' not passed validation, or whose promotion is refused, is a
#' `soilhub_conflict_error` (HTTP 409) explaining why.
#'
#' Rights: `soil:publish`. Capability: `source_ingest`.
#'
#' @inheritParams soil_job
#' @return `soil_source_validate()`: a `soil_source_validation` list:
#'   `job_id`, `valid`, `counts` (staged records by type), `errors` (data
#'   frame: `record_number`, `source_record_id`, `errors`),
#'   `diagnostics_truncated`, `unmapped_property_codes`.
#'   `soil_source_promote()`: the `soil_job` (unified view), `completed`,
#'   with `published_count`, `receipt_id` and, in `diagnostics`, the
#'   `release_id` and the promoted `counts`.
#' @family writing
#' @examples
#' \dontrun{
#' ingest <- soil_publish_source(soil, manifest, sites, idempotency_key = "k", wait = FALSE)
#' report <- soil_source_validate(soil, ingest$job_id)
#' report$unmapped_property_codes
#' if (report$valid) soil_source_promote(soil, ingest$job_id)
#' }
#' @export
soil_source_validate <- function(soil = soil_session(), job_id) {
  what <- "`soil_source_validate()`"
  check_session(soil)
  soil_require_right(soil, "soil:publish", what)
  job_id <- check_job_id(job_id)
  soil_require_capability(soil, "source_ingest", what)
  source_validate_request(soil, job_id)
}

#' @rdname soil_source_validate
#' @export
soil_source_promote <- function(soil = soil_session(), job_id) {
  what <- "`soil_source_promote()`"
  check_session(soil)
  soil_require_right(soil, "soil:publish", what)
  job_id <- check_job_id(job_id)
  soil_require_capability(soil, "source_ingest", what)
  source_promote_request(soil, job_id)
}

# ---------------------------------------------------------------------------
# Requests.

source_upload <- function(soil, file, manifest, idempotency_key, auto_promote) {
  manifest_json <- as.character(jsonlite::toJSON(
    manifest, auto_unbox = TRUE, null = "null", na = "null", digits = NA
  ))
  submitted <- with_conflict_advice(
    soil_request(
      soil, "POST", "/source-ingests",
      body = upload_body(file$path, fields = list(
        idempotency_key = idempotency_key, input_format = "ndjson",
        manifest = manifest_json, expected_checksum = file$checksum_sha256,
        auto_promote = if (auto_promote) "true" else "false"
      )),
      timeout = Inf, retry = FALSE, right = "soil:publish"
    ),
    paste0(
      "The API refused the bundle: an idempotency key already used with another file ",
      "(a retry of the same bundle keeps its key; a new bundle needs a new key), a checksum ",
      "that does not match, a file above the size limit, or a manifest it cannot read ",
      "(see its message above)."
    )
  )
  job <- new_soil_job(submitted)
  soil_inform(soil, 1, sprintf(
    "soilhub: source bundle of %s record(s) uploaded (%s bytes, sha256 %s) as job %s; keep this id.",
    format_count(file$row_count), format_count(file$byte_size),
    file$checksum_sha256, job$job_id
  ))
  if (!identical(job$checksum_sha256, file$checksum_sha256)) {
    abort(soilhub_api_error(
      sprintf(
        "The API recorded the checksum %s for job %s, not the checksum of the file sent (%s).",
        job$checksum_sha256 %||% "none", job$job_id, file$checksum_sha256
      ),
      endpoint = "/source-ingests", method = "POST", code = "checksum_mismatch",
      request_id = attr(job, "request_id"), job_id = job$job_id
    ))
  }
  job
}

source_validate_request <- function(soil, job_id, bundle = NULL) {
  path <- paste0("/source-ingests/", url_segment(job_id), "/validate")
  body <- with_conflict_advice(
    soil_request(soil, "POST", path, right = "soil:publish"),
    paste0(
      "A source ingest can be validated while it is queued or validating; ",
      "read its status with soil_job()."
    )
  )
  new_source_validation(body, job_id, bundle)
}

# Validate; when the server's ingest worker holds the job (status
# `running`: a 409 on validation), wait for it to end its own validation
# (status `validating`) and validate again.
source_validate_when_ready <- function(soil, job_id, timeout, poll, bundle) {
  deadline <- soil_now() + timeout
  repeat {
    result <- tryCatch(
      source_validate_request(soil, job_id, bundle),
      soilhub_conflict_error = function(e) e
    )
    if (!inherits(result, "soilhub_conflict_error")) return(result)
    job <- tryCatch(fetch_job(soil, job_id), soilhub_error = function(e) NULL)
    if (is.null(job) || !job$status %in% c("queued", "running", "validating")) abort(result)
    if (identical(job$status, "validating")) next
    remaining <- as.numeric(difftime(deadline, soil_now(), units = "secs"))
    if (remaining <= 0) abort(result)
    http_sleep(min(poll, remaining))
  }
}

source_promote_request <- function(soil, job_id) {
  body <- with_conflict_advice(
    soil_request(
      soil, "POST", paste0("/source-ingests/", url_segment(job_id), "/promote"),
      right = "soil:publish"
    ),
    paste0(
      "Promotion needs a job that passed validation (status validating). It is refused, ",
      "and the job fails, when the release_code already exists for the dataset (releases ",
      "are immutable: use a new release_code), when the provider_code exists with another ",
      "provider_name, or when the dataset_code exists with another support_type or ",
      "default_geometry_kind."
    )
  )
  new_soil_job(body)
}

# Wait for the end of the job; a failed job carries the rejected records.
source_wait <- function(soil, job_id, timeout, poll, progress, bundle) {
  tryCatch(
    wait_job(soil, job_id, timeout, poll, progress),
    soilhub_job_error = function(e) {
      rejected <- if (is.list(e$job$diagnostics)) e$job$diagnostics$errors else NULL
      if (length(rejected)) {
        e$errors <- source_errors_frame(rejected, bundle)
        e$message <- paste0(conditionMessage(e), errors_summary(e$errors))
      }
      abort(e)
    }
  )
}

# ---------------------------------------------------------------------------
# Results.

new_source_validation <- function(x, job_id = NULL, bundle = NULL) {
  structure(
    list(
      job_id = if (is_string(x$job_id)) x$job_id else job_id %||% NA_character_,
      valid = isTRUE(x$valid),
      counts = source_counts(x$counts),
      errors = source_errors_frame(x$errors, bundle),
      diagnostics_truncated = isTRUE(x$diagnostics_truncated),
      unmapped_property_codes = as.character(unlist(x$unmapped_property_codes)),
      request_id = attr(x, "request_id")
    ),
    class = "soil_source_validation"
  )
}

# The validation report merged into the diagnostics of a job validated by
# the server's worker (auto_promote).
source_validation_from_job <- function(job, bundle) {
  diagnostics <- if (is.list(job$diagnostics)) job$diagnostics else list()
  new_source_validation(list(
    job_id = job$job_id, valid = identical(job$status, "completed"),
    counts = diagnostics$counts, errors = diagnostics$errors,
    diagnostics_truncated = diagnostics$diagnostics_truncated,
    unmapped_property_codes = diagnostics$unmapped_property_codes
  ), job$job_id, bundle)
}

# Counts by record type (named numeric over the five types), NULL when
# the API gave none.
source_counts <- function(counts) {
  if (!is.list(counts) && !is.numeric(counts)) return(NULL)
  vapply(source_record_types, function(type) {
    value <- counts[[type]]
    if (is.null(value)) 0 else as.numeric(value)
  }, numeric(1))
}

# The rejected records as a data frame; with the bundle, the record type
# and the row of its table next to the API's 1-based `record_number`.
source_errors_frame <- function(errors, bundle = NULL) {
  if (length(errors) == 0L) {
    frame <- data.frame(
      record_number = integer(), source_record_id = character(),
      errors = character(), stringsAsFactors = FALSE
    )
  } else {
    frame <- validation_errors_frame(list(errors = errors))
  }
  if ("record_number" %in% names(frame)) {
    frame$record_number <- suppressWarnings(as.integer(frame$record_number))
    if (!is.null(bundle)) {
      known <- !is.na(frame$record_number) & frame$record_number <= length(bundle$types)
      frame$record_type <- ifelse(known, bundle$types[frame$record_number], NA_character_)
      frame$row <- ifelse(known, bundle$rows[frame$record_number], NA_integer_)
      first <- c("record_number", "record_type", "row")
      frame <- frame[c(first, setdiff(names(frame), first))]
    }
  }
  frame
}

new_soil_source_ingest <- function(fields) {
  structure(fields, class = "soil_source_ingest")
}

#' @export
print.soil_source_ingest <- function(x, ...) {
  cat("<soil_source_ingest> ", x$provider_code, "/", x$dataset_code, " release ",
      x$release_code, "\n", sep = "")
  status <- x$status
  if (identical(status, "completed")) {
    status <- paste0(status, if (isTRUE(x$auto_promote)) " (promoted by the server)" else " (promoted by the client)")
  }
  cat("  Status:    ", status, "\n", sep = "")
  cat("  Job:       ", x$job_id, "\n", sep = "")
  cat("  Records:   ", source_counts_text(x$record_counts), " (sent ",
      format_count(x$record_count), ")\n", sep = "")
  if (!is.null(x$staged_counts)) {
    cat("  Staged:    ", source_counts_text(x$staged_counts), "\n", sep = "")
  }
  if (!is.na(x$published_count) && identical(x$status, "completed")) {
    cat("  Published: ", format_count(x$published_count),
        if (!is.na(x$release_id)) paste0(", release ", format(x$release_id)), "\n", sep = "")
  }
  if (!is.na(x$receipt_id)) cat("  Receipt:   ", x$receipt_id, "\n", sep = "")
  if (length(x$unmapped_property_codes)) {
    cat("  Unmapped:  ", paste(x$unmapped_property_codes, collapse = ", "), "\n", sep = "")
  }
  cat("  File:      ", format_count(x$byte_size), " bytes, sha256 ", x$checksum_sha256,
      if (!is.null(x$file)) paste0(", kept at ", x$file), "\n", sep = "")
  invisible(x)
}

#' @export
print.soil_source_validation <- function(x, ...) {
  cat("<soil_source_validation> job ", x$job_id, ": ",
      if (x$valid) "valid" else "invalid", "\n", sep = "")
  if (!is.null(x$counts)) cat("  Staged:   ", source_counts_text(x$counts), "\n", sep = "")
  if (nrow(x$errors)) {
    cat("  Rejected: ", format_count(length(unique(x$errors$record_number))), " record(s)",
        if (x$diagnostics_truncated) " (first 1,000 errors)", "\n", sep = "")
    cat(sub("^\n", "", errors_summary(x$errors)), "\n", sep = "")
  }
  if (length(x$unmapped_property_codes)) {
    cat("  Unmapped property codes: ", paste(x$unmapped_property_codes, collapse = ", "), "\n", sep = "")
  }
  invisible(x)
}

source_counts_text <- function(counts) {
  counts <- counts[counts > 0]
  if (length(counts) == 0L) return("none")
  paste(names(counts), format_count(counts), collapse = ", ")
}

# ---------------------------------------------------------------------------
# Count verification.

# "observation 4 sent, 3 staged" for the types that differ; empty when equal.
source_count_differences <- function(sent, observed, label) {
  if (is.null(observed)) return(character())
  observed <- observed[names(sent)]
  off <- is.na(observed) | observed != sent
  if (!any(off)) return(character())
  sprintf("%s %s sent, %s %s", names(sent)[off], format_count(sent[off]),
          format_count(observed[off]), label)
}

# Before promotion (promoted = FALSE): the counts staged by validation and
# the received/staged counts of the job must equal the records sent, else
# nothing is promoted. After a promotion by the server (promoted = TRUE)
# the same differences are a reconciliation warning.
source_check_staged <- function(job_id, bundle, job, staged = NULL,
                                promoted = FALSE) {
  sent <- sum(bundle$counts)
  problems <- source_count_differences(bundle$counts, staged, "staged")
  for (field in c("received_count", "staged_count")) {
    value <- job[[field]]
    if (!is.null(value) && !is.na(value) && value != sent) {
      problems <- c(problems, sprintf(
        "%s %s for %s record(s) sent", sub("_count$", "", field), format_count(value),
        format_count(sent)
      ))
    }
  }
  if (length(problems) == 0L) return(invisible(TRUE))
  if (promoted) {
    soilhub_warning(sprintf(
      "Source ingest %s does not reconcile with the bundle sent: %s.",
      job_id, paste(problems, collapse = "; ")
    ), "soilhub_reconciliation_warning")
    return(invisible(FALSE))
  }
  abort(soilhub_api_error(
    sprintf(
      paste0(
        "The API staged for job %s other records than the bundle sent (%s): nothing was ",
        "promoted. Cancel the job with soil_job_cancel(soil, \"%s\") and submit the ",
        "bundle again with a new idempotency_key."
      ),
      job_id, paste(problems, collapse = "; "), job_id
    ),
    endpoint = paste0("/source-ingests/", job_id, "/validate"),
    code = "staged_count_mismatch", job_id = job_id,
    record_counts = bundle$counts, staged_counts = staged
  ))
}

# After the promotion: published records and promoted counts by type.
source_reconcile <- function(x, promoted) {
  if (!identical(x$status, "completed")) return(invisible(x))
  problems <- source_count_differences(x$record_counts, promoted, "promoted")
  if (!is.na(x$published_count) && x$published_count != x$record_count) {
    problems <- c(problems, sprintf(
      "%s published for %s record(s) sent", format_count(x$published_count),
      format_count(x$record_count)
    ))
  }
  if (length(problems)) {
    soilhub_warning(sprintf(
      "The receipt of source ingest %s does not reconcile with the bundle sent: %s.",
      x$job_id, paste(problems, collapse = "; ")
    ), "soilhub_reconciliation_warning")
  }
  invisible(x)
}

source_warn_unmapped <- function(codes, manifest) {
  if (length(codes) == 0L) return(invisible(NULL))
  soilhub_warning(sprintf(
    paste0(
      "%s property code(s) of the bundle have no mapping for provider `%s` and dataset ",
      "`%s`: %s. Their observations are stored with the original code and appear under ",
      "no canonical variable until a mapping exists (see soil_variable_mappings())."
    ),
    format_count(length(codes)), manifest$provider_code, manifest$dataset_code,
    paste0("`", codes, "`", collapse = ", ")
  ), "soilhub_unmapped_properties_warning")
}

# ---------------------------------------------------------------------------
# Manifest (local checks, no network).

source_manifest <- function(manifest) {
  if (!is.list(manifest) || length(manifest) == 0L || is.null(names(manifest)) ||
      any(!nzchar(names(manifest)))) {
    abort(soilhub_argument_error(
      "`manifest` must be a named list describing the provider, dataset and release.",
      "manifest"
    ))
  }
  assets <- manifest$assets
  manifest$assets <- NULL
  manifest <- compact_record(lapply(manifest, record_value))
  problems <- character()
  for (field in source_manifest_required) {
    if (!is_string(manifest[[field]])) {
      problems <- c(problems, sprintf("`%s` is required (a non-empty string)", field))
    }
  }
  for (field in c("provider_code", "dataset_code")) {
    value <- manifest[[field]]
    if (is_string(value) && !grepl(source_code_pattern, value)) {
      problems <- c(problems, sprintf(
        "`%s` \"%s\" may hold only lowercase letters, digits and `_`", field, value
      ))
    }
  }
  if (is_string(manifest$support_type) && !manifest$support_type %in% health_source_supports) {
    problems <- c(problems, sprintf(
      "`support_type` \"%s\" is not one of %s", manifest$support_type,
      paste0("\"", health_source_supports, "\"", collapse = ", ")
    ))
  }
  if (is_string(manifest$default_geometry_kind)) {
    manifest$default_geometry_kind <- toupper(manifest$default_geometry_kind)
    if (!manifest$default_geometry_kind %in% source_geometry_kinds) {
      problems <- c(problems, sprintf(
        "`default_geometry_kind` \"%s\" is not one of %s", manifest$default_geometry_kind,
        paste0("\"", source_geometry_kinds, "\"", collapse = ", ")
      ))
    }
  }
  checksum <- manifest$release_checksum_sha256
  if (!is.null(checksum) && !(is_string(checksum) && grepl(sha256_pattern, checksum))) {
    problems <- c(problems, "`release_checksum_sha256` must be 64 lowercase hexadecimal characters")
  }
  for (field in setdiff(names(manifest), c(source_manifest_required, "release_checksum_sha256"))) {
    if (field %in% source_manifest_optional && !is_string(manifest[[field]])) {
      problems <- c(problems, sprintf("`%s` must be a string", field))
    }
  }
  if (!is.null(assets)) {
    assets <- if (is.data.frame(assets) && nrow(assets) == 0L) list() else as_records(assets, "manifest$assets")
    for (i in seq_along(assets)) {
      asset <- assets[[i]]
      if (!is_string(asset$asset_role)) problems <- c(problems, sprintf("asset %d: `asset_role` is required", i))
      if (!is_string(asset$source_url)) problems <- c(problems, sprintf("asset %d: `source_url` is required", i))
      if (!is.null(asset$checksum_sha256) &&
          !(is_string(asset$checksum_sha256) && grepl(sha256_pattern, asset$checksum_sha256))) {
        problems <- c(problems, sprintf("asset %d: `checksum_sha256` must be 64 lowercase hexadecimal characters", i))
      }
      if (!is.null(asset$byte_size) && !(is.numeric(asset$byte_size) && asset$byte_size >= 0)) {
        problems <- c(problems, sprintf("asset %d: `byte_size` must be a number >= 0", i))
      }
    }
    manifest$assets <- assets
  }
  if (length(problems)) {
    abort(new_soilhub_error(
      "soilhub_argument_error",
      paste0("`manifest` fails the local checks; nothing was sent:\n",
             paste0("- ", problems, collapse = "\n")),
      argument = "manifest", problems = problems
    ))
  }
  unknown <- setdiff(names(manifest), c(source_manifest_required, source_manifest_optional))
  if ("property_mappings" %in% unknown) {
    soilhub_warning(paste0(
      "`manifest$property_mappings` is not read by the API: property mappings are resolved ",
      "on the server from its mappings of the provider (see soil_variable_mappings()); ",
      "unmapped property codes are reported by the validation."
    ), "soilhub_manifest_warning")
    unknown <- setdiff(unknown, "property_mappings")
  }
  if (length(unknown)) {
    soilhub_warning(sprintf(
      "`manifest` field(s) %s are not part of the source manifest of the API and are ignored by the server.",
      paste0("`", unknown, "`", collapse = ", ")
    ), "soilhub_manifest_warning")
  }
  manifest
}

# ---------------------------------------------------------------------------
# Bundle (local checks, no network).

# The records of the bundle in the order feature, profile, component,
# horizon, observation, with their type and the row of their table;
# problems found locally stop everything (no request is sent).
source_bundle <- function(manifest, features, profiles, components, horizons,
                          observations) {
  feature_part <- source_feature_records(features, manifest)
  tables <- list(
    feature = feature_part$records,
    profile = source_table_records(profiles, "profile"),
    component = source_table_records(components, "component"),
    horizon = source_table_records(horizons, "horizon"),
    observation = source_table_records(observations, "observation")
  )
  if (length(tables$feature) == 0L) {
    abort(soilhub_argument_error(
      "`features` holds no feature: a source bundle needs at least one.", "features"
    ))
  }
  issues <- lapply(source_record_types, function(type) {
    if (type == "feature") feature_part$issues else rep(list(character()), length(tables[[type]]))
  })
  names(issues) <- source_record_types

  ids <- list()
  for (type in source_record_types) {
    fields <- c("source_record_id", if (type %in% names(source_parent_fields)) source_parent_fields[[type]])
    tables[[type]] <- lapply(tables[[type]], source_normalise_ids, fields)
    values <- vapply(tables[[type]], function(r) {
      if (is_string(r$source_record_id)) r$source_record_id else NA_character_
    }, character(1))
    ids[[type]] <- values
    duplicated_ids <- unique(values[!is.na(values) & duplicated(values)])
    for (i in seq_along(values)) {
      record <- tables[[type]][[i]]
      found <- character()
      if (is.na(values[i])) {
        found <- if (is.null(record$source_record_id)) "missing_source_record_id" else "invalid_source_record_id"
      } else if (values[i] %in% duplicated_ids) {
        found <- "duplicate_source_record_id"
      }
      if (type %in% names(source_parent_fields)) {
        field <- source_parent_fields[[type]]
        parent <- record[[field]]
        if (!is_string(parent)) {
          found <- c(found, paste0("missing_", field))
        } else if (!parent %in% ids[[source_parent_types[[type]]]]) {
          found <- c(found, "parent_not_found")
        }
      }
      if (type == "observation") {
        if (!is_string(record$property_code)) found <- c(found, "missing_property_code")
        if (is.null(record$unit)) found <- c(found, "missing_unit_declaration")
        if (!is_string(record$status) || !record$status %in% source_observation_statuses) {
          found <- c(found, "invalid_observation_status")
        }
      }
      issues[[type]][[i]] <- c(issues[[type]][[i]], found)
    }
  }

  counts <- vapply(tables, length, numeric(1))
  types <- rep(source_record_types, counts)
  rows <- unlist(lapply(counts, seq_len), use.names = FALSE)
  records <- unlist(unname(tables), recursive = FALSE)
  problems <- unlist(unname(issues), recursive = FALSE)
  bad <- which(lengths(problems) > 0L)
  if (length(bad)) {
    errors <- data.frame(
      record_type = types[bad], row = rows[bad],
      source_record_id = unlist(ids, use.names = FALSE)[bad],
      errors = vapply(problems[bad], paste, character(1), collapse = ", "),
      stringsAsFactors = FALSE
    )
    abort(new_soilhub_error(
      "soilhub_argument_error",
      paste0(
        sprintf(
          "%s of the %s record(s) of the source bundle fail the local checks; nothing was sent.",
          format_count(length(bad)), format_count(length(records))
        ),
        errors_summary(errors)
      ),
      argument = source_tables[[types[bad[1]]]], errors = errors
    ))
  }
  list(records = records, counts = counts, types = types, rows = rows)
}

# The records of one table with their `record_type` first.
source_table_records <- function(x, type) {
  if (is.null(x) || (is.data.frame(x) && nrow(x) == 0L)) return(list())
  argument <- source_tables[[type]]
  if (inherits(x, "sf")) {
    abort(soilhub_argument_error(
      sprintf("`%s` must be a plain data frame: only `features` carry geometry.", argument),
      argument
    ))
  }
  records <- as_records(x, argument)
  lapply(records, function(record) {
    c(list(record_type = type), record[setdiff(names(record), "record_type")])
  })
}

# Identifiers as text: whole numbers become text ("12"), other values are
# left as they are and reported.
source_normalise_ids <- function(record, fields) {
  for (field in fields) {
    value <- record[[field]]
    if (is.null(value)) next
    if (is.numeric(value) && length(value) == 1L && is.finite(value) && value == round(value)) {
      record[[field]] <- format(value, scientific = FALSE, trim = TRUE)
    } else if (is.character(value) && length(value) == 1L && !nzchar(value)) {
      record[field] <- list(NULL)
    }
  }
  record
}

# ---------------------------------------------------------------------------
# Features: sf object, GeoJSON file (read without sf) or other spatial file.

source_sf_available <- function() requireNamespace("sf", quietly = TRUE)

source_need_sf <- function(what) {
  if (!source_sf_available()) {
    abort(soilhub_dependency_error("sf", sprintf(
      paste0(
        "%s needs the package 'sf': install.packages(\"sf\"). Without it, give the ",
        "features as a GeoJSON file in WGS84 (EPSG:4326)."
      ),
      what
    )))
  }
  invisible(TRUE)
}

source_feature_records <- function(features, manifest) {
  if (is.character(features) && length(features) == 1L && !is.na(features)) {
    features <- source_read_features(features)
  }
  if (inherits(features, "soilhub_geojson")) return(source_geojson_records(features))
  if (inherits(features, "sf")) return(source_sf_records(features))
  if (is.data.frame(features)) {
    if (!identical(manifest$default_geometry_kind, "NONE")) {
      abort(soilhub_argument_error(
        paste0(
          "`features` must be an `sf` object or the path of a spatial file; a plain data ",
          "frame is accepted only for a non-spatial dataset (`default_geometry_kind = \"NONE\"`)."
        ),
        "features"
      ))
    }
    records <- if (nrow(features) == 0L) list() else as_records(features, "features")
    records <- lapply(records, function(record) {
      source_feature_record(record[setdiff(names(record), c("geometry", "geometry_kind"))], "NONE", NULL)
    })
    return(list(records = records, issues = rep(list(character()), length(records))))
  }
  if (is.null(features) || (is.list(features) && length(features) == 0L)) {
    return(list(records = list(), issues = list()))
  }
  abort(soilhub_argument_error(
    "`features` must be an `sf` object or the path of a spatial file (GeoJSON, GeoPackage, ...).",
    "features"
  ))
}

source_read_features <- function(path) {
  if (!file.exists(path)) {
    abort(soilhub_argument_error(sprintf("The features file %s does not exist.", path), "features"))
  }
  extension <- tolower(sub("^.*\\.", "", basename(path)))
  if (extension %in% c("geojson", "json")) {
    parsed <- tryCatch(
      jsonlite::fromJSON(path, simplifyVector = FALSE),
      error = function(e) {
        abort(soilhub_argument_error(
          sprintf("The features file %s is not valid JSON: %s", path, conditionMessage(e)),
          "features"
        ))
      }
    )
    crs <- source_geojson_crs(parsed)
    if (is.null(crs)) return(structure(parsed, class = "soilhub_geojson"))
    # A legacy GeoJSON in another CRS: read and transform it with sf.
    source_need_sf(sprintf("A GeoJSON file in the CRS %s", crs))
    return(sf::st_read(path, quiet = TRUE))
  }
  source_need_sf(sprintf("Reading `features` from a .%s file", extension))
  sf::st_read(path, quiet = TRUE)
}

# The name of a legacy `crs` member other than WGS84, NULL when WGS84 or
# absent (RFC 7946: GeoJSON coordinates are WGS84 longitude, latitude).
source_geojson_crs <- function(x) {
  crs <- if (is.list(x)) x$crs else NULL
  if (is.null(crs)) return(NULL)
  name <- if (is.list(crs$properties)) crs$properties$name else NULL
  if (is_string(name) && grepl("CRS84$|EPSG:{1,2}4326$", name)) return(NULL)
  if (is_string(name)) name else "declared in the file"
}

source_geojson_records <- function(collection) {
  if (!identical(collection$type, "FeatureCollection") || !is.list(collection$features)) {
    abort(soilhub_argument_error(
      "The features file is not a GeoJSON FeatureCollection.", "features"
    ))
  }
  parts <- lapply(collection$features, function(feature) {
    properties <- if (is.list(feature$properties)) compact_record(feature$properties) else list()
    geometry <- feature$geometry
    issues <- character()
    kind <- NA_character_
    if (!is.list(geometry)) {
      issues <- "missing_geometry"
      geometry <- NULL
    } else {
      type <- geometry$type
      kind <- if (is_string(type) && type %in% names(source_geojson_types)) source_geojson_types[[type]] else NA_character_
      if (is.na(kind)) {
        issues <- c(issues, paste0("unsupported_geometry_type_", if (is_string(type)) type else "unknown"))
      }
      if (!is.null(geometry$crs)) issues <- c(issues, "embedded_crs_not_allowed")
      coordinates <- unlist(geometry$coordinates)
      if (length(coordinates) == 0L) {
        issues <- c(issues, "empty_geometry")
      } else if (!is.numeric(coordinates) || anyNA(coordinates)) {
        issues <- c(issues, "invalid_coordinates")
      }
      geometry <- geometry[c("type", "coordinates")]
    }
    list(record = source_feature_record(properties, kind, geometry), issues = issues)
  })
  list(records = lapply(parts, `[[`, "record"), issues = lapply(parts, `[[`, "issues"))
}

source_sf_records <- function(features) {
  source_need_sf("An `sf` object as `features`")
  crs <- sf::st_crs(features)
  if (is.na(crs)) {
    abort(soilhub_argument_error(
      paste0(
        "`features` has no CRS: set the CRS of its coordinates with sf::st_set_crs() ",
        "(the API stores WGS84, EPSG:4326, and the client transforms any other CRS)."
      ),
      "features"
    ))
  }
  if (nrow(features) == 0L) return(list(records = list(), issues = list()))
  if (!isTRUE(crs == sf::st_crs(4326))) features <- sf::st_transform(features, 4326)
  geometry <- sf::st_geometry(features)
  types <- as.character(sf::st_geometry_type(geometry, by_geometry = TRUE))
  empty <- sf::st_is_empty(geometry)
  records <- as_records(sf::st_drop_geometry(features), "features")
  parts <- lapply(seq_along(records), function(i) {
    issues <- character()
    shape <- NULL
    kind <- types[i]
    if (empty[i]) {
      issues <- "empty_geometry"
    } else if (!kind %in% source_geometry_kinds) {
      issues <- paste0("unsupported_geometry_type_", kind)
    } else {
      shape <- source_sfg_geojson(geometry[[i]], kind)
      coordinates <- unlist(shape$coordinates)
      if (anyNA(coordinates) || !all(is.finite(coordinates))) issues <- "invalid_coordinates"
    }
    list(record = source_feature_record(records[[i]], if (length(issues)) NA_character_ else kind, shape),
         issues = issues)
  })
  list(records = lapply(parts, `[[`, "record"), issues = lapply(parts, `[[`, "issues"))
}

# GeoJSON geometry (longitude, latitude; Z and M dropped) of an sf geometry
# of type POINT, POLYGON or MULTIPOLYGON.
source_sfg_geojson <- function(g, kind) {
  xy <- function(m) unname(m[, 1:2, drop = FALSE])
  switch(
    kind,
    POINT = list(type = "Point", coordinates = as.numeric(unclass(g))[1:2]),
    POLYGON = list(type = "Polygon", coordinates = lapply(unclass(g), xy)),
    MULTIPOLYGON = list(type = "MultiPolygon", coordinates = lapply(unclass(g), function(p) lapply(p, xy)))
  )
}

# A feature record: type and id first, the attributes, then the geometry.
source_feature_record <- function(attributes, kind, geometry) {
  attributes <- attributes[setdiff(names(attributes), c("record_type", "geometry", "geometry_kind"))]
  first <- intersect("source_record_id", names(attributes))
  record <- c(
    list(record_type = "feature"), attributes[first],
    attributes[setdiff(names(attributes), first)]
  )
  if (!is.na(kind)) record$geometry_kind <- kind
  if (!is.null(geometry)) record$geometry <- geometry
  record
}
