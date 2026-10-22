# Fake source-ingest API (WP9, design 7.1): `POST /source-ingests` (multipart
# form: idempotency_key, input_format, manifest, expected_checksum,
# auto_promote, file), `POST /source-ingests/{id}/validate`,
# `POST /source-ingests/{id}/promote` and `GET /jobs/{id}`, with the response
# models of python/soil_api/models.py (UnifiedJobResponse,
# SourceIngestValidationResponse) and the lifecycle of
# python/soil_api/source_ingest.py. Hand-made until WP10 records fixtures.
#
# Behaviour is chosen by the idempotency key:
#   "flaky"     upload -> 503
#   "busy"      the server's worker holds the job (status running): every
#               validation is a 409 until the second GET /jobs/{id}, which
#               ends the worker's validation (status validating)
#   "reject"    validation rejects record 3 (parent_not_found)
#   "drop"      the API stages one observation fewer than received
#   "short"     the promotion publishes one observation fewer
#   "taken"     promotion refused: the release_code exists (409, job failed)
# A key already used with the same file returns the job; with another file
# it is a 409. Observations whose property_code is not "orgc" or "clay" are
# reported as unmapped. With auto_promote = "true" each GET /jobs/{id}
# moves the job one step as the worker does: queued, running, validated
# (validating or failed), promoted (completed).
# Test controls: GET /test/log, POST /test/reset, POST /test/deny,
# GET /test/upload/{job_id} (file text and form fields).

fake_source_api <- function(.local_envir = parent.frame()) {
  testthat::skip_if_not_installed("webfakes")
  app <- webfakes::new_app()
  app$use(webfakes::mw_json())
  app$use(webfakes::mw_multipart())
  app$locals$log <- list()
  app$locals$jobs <- list()
  app$locals$deny <- FALSE

  env <- new.env(parent = baseenv())
  route <- function(handler) {
    environment(handler) <- env
    handler
  }
  helpers <- list(
    send = function(res, body, status = 200L) {
      res$set_status(status)$send_json(body, auto_unbox = TRUE, null = "null", na = "null", digits = NA)
    },
    fail = function(res, status, detail) {
      res$set_status(status)$send_json(list(detail = detail), auto_unbox = TRUE, null = "null")
    },
    obj = function(x = list()) if (length(x)) x else structure(list(), names = character()),
    now = function() "2026-10-18T08:00:00Z",
    uuid = function(n) sprintf("00000000-0000-4000-8000-%012d", n),
    types = c("component", "feature", "horizon", "observation", "profile"),
    unified = function(job) {
      list(
        job_id = job$job_id, job_type = "source_ingest", status = job$status,
        progress_percent = c(queued = 0, running = 5, validating = 15, promoting = 70,
                             completed = 100, failed = 100, cancelled = 100)[[job$status]],
        received_count = job$received, staged_count = job$staged,
        accepted_count = job$accepted, rejected_count = job$rejected,
        published_count = job$published, checksum_sha256 = job$checksum,
        byte_size = job$byte_size, receipt_id = job$receipt,
        correlation_id = uuid(800), diagnostics = obj(job$diagnostics), error = job$error,
        retry_count = 0L, cancel_requested = FALSE,
        worker_id = if (job$auto) "source-ingest-worker" else NULL,
        lease_expires_at = NULL, heartbeat_at = NULL, created_at = now(),
        started_at = if (job$status == "queued") NULL else now(),
        finished_at = if (job$status %in% c("completed", "failed", "cancelled")) now() else NULL,
        updated_at = now()
      )
    },
    validate = function(job) {
      records <- job$records
      counts <- stats::setNames(as.list(rep(0L, 5)), types)
      for (record in records) {
        if (is.character(record$record_type) && record$record_type %in% types) {
          counts[[record$record_type]] <- counts[[record$record_type]] + 1L
        }
      }
      staged <- length(records)
      if (grepl("drop", job$key)) {
        counts$observation <- counts$observation - 1L
        staged <- staged - 1L
      }
      errors <- if (grepl("reject", job$key)) {
        list(list(record_number = 3L, source_record_id = records[[3]]$source_record_id,
                  errors = list("parent_not_found")))
      } else {
        list()
      }
      codes <- unique(unlist(lapply(records, function(r) {
        if (identical(r$record_type, "observation")) r$property_code else NULL
      })))
      unmapped <- sort(setdiff(codes, c("orgc", "clay")))
      report <- list(counts = counts, errors = errors, diagnostics_truncated = FALSE,
                     unmapped_property_codes = as.list(unmapped))
      job$received <- length(records)
      job$staged <- staged
      job$rejected <- length(errors)
      job$accepted <- length(records) - length(errors)
      job$diagnostics <- utils::modifyList(job$diagnostics %||% list(), report)
      job$report <- report
      job$valid <- length(errors) == 0L
      if (job$valid) {
        job$status <- "validating"
      } else {
        job$status <- "failed"
        job$error <- list(code = "validation_failed", message = "source ingest validation failed")
      }
      job
    },
    promote = function(job) {
      if (identical(job$manifest$release_code, "taken")) {
        job$status <- "failed"
        job$error <- list(code = "promotion_failed",
                          message = "release_code already exists; publish a new immutable release code")
        return(job)
      }
      counts <- job$report$counts
      if (grepl("short", job$key)) counts$observation <- counts$observation - 1L
      job$status <- "completed"
      job$published <- sum(unlist(counts))
      job$receipt <- uuid(950)
      job$diagnostics <- utils::modifyList(job$diagnostics, list(release_id = 31L, counts = counts))
      job
    },
    save = function(req, job) {
      jobs <- req$app$locals$jobs
      jobs[[job$job_id]] <- job
      req$app$locals$jobs <- jobs
      job
    }
  )
  for (name in names(helpers)) {
    value <- helpers[[name]]
    assign(name, if (is.function(value)) route(value) else value, envir = env)
  }
  assign("%||%", function(x, y) if (is.null(x)) y else x, envir = env)

  app$use(route(function(req, res) {
    if (!startsWith(req$path, "/test/")) {
      req$app$locals$log <- c(req$app$locals$log, list(list(
        method = req$method, path = req$path, query = req$query_string
      )))
      if (isTRUE(req$app$locals$deny)) return(fail(res, 403L, "Missing required scope"))
    }
    "next"
  }))
  app$get("/test/log", route(function(req, res) send(res, list(log = req$app$locals$log))))
  app$post("/test/reset", route(function(req, res) {
    req$app$locals$log <- list()
    req$app$locals$deny <- FALSE
    send(res, list(ok = TRUE))
  }))
  app$post("/test/deny", route(function(req, res) {
    req$app$locals$deny <- TRUE
    send(res, list(ok = TRUE))
  }))
  app$get("/test/upload/:id", route(function(req, res) {
    job <- req$app$locals$jobs[[req$params$id]]
    send(res, list(text = job$text, form = job$form, content_type = job$content_type))
  }))

  app$post("/api/v1/source-ingests", route(function(req, res) {
    form <- req$form
    key <- form$idempotency_key
    if (identical(key, "flaky")) return(fail(res, 503L, "Database unavailable"))
    file <- req$files$file
    if (is.null(file) || is.null(key) || is.null(form$manifest) || is.null(form$input_format)) {
      return(fail(res, 422L, list(list(loc = list("body", "file"), msg = "Field required", type = "missing"))))
    }
    if (!identical(form$input_format, "ndjson")) {
      return(fail(res, 409L, paste("unsupported source ingest format:", form$input_format)))
    }
    manifest <- jsonlite::fromJSON(form$manifest, simplifyVector = FALSE)
    if (is.null(manifest$provider_code)) {
      return(fail(res, 409L, "1 validation error for SourceIngestManifest\nprovider_code\n  Field required"))
    }
    checksum <- as.vector(as.character(openssl::sha256(file$value)))
    if (!is.null(form$expected_checksum) && !identical(form$expected_checksum, checksum)) {
      return(fail(res, 409L, "uploaded file checksum does not match expected_checksum"))
    }
    for (existing in req$app$locals$jobs) {
      if (identical(existing$key, key)) {
        if (!identical(existing$checksum, checksum)) {
          return(fail(res, 409L, "idempotency key was already used with a different file"))
        }
        return(send(res, unified(existing)))
      }
    }
    text <- rawToChar(file$value)
    lines <- strsplit(text, "\n", fixed = TRUE)[[1]]
    records <- lapply(lines[nzchar(lines)], jsonlite::fromJSON, simplifyVector = FALSE)
    job <- list(
      job_id = uuid(length(req$app$locals$jobs) + 1L), key = key,
      status = if (grepl("busy", key)) "running" else "queued",
      holds = if (grepl("busy", key)) 1L else 0L,
      auto = identical(form$auto_promote, "true"), manifest = manifest,
      records = records, text = text, form = form[setdiff(names(form), "file")],
      content_type = req$get_header("Content-Type"), checksum = checksum,
      byte_size = length(file$value), received = 0L, staged = 0L, accepted = 0L,
      rejected = 0L, published = 0L, receipt = NULL, diagnostics = list(), error = NULL
    )
    job <- save(req, job)
    send(res, unified(job))
  }))

  app$post("/api/v1/source-ingests/:id/validate", route(function(req, res) {
    job <- req$app$locals$jobs[[req$params$id]]
    if (is.null(job)) return(fail(res, 404L, "job not found"))
    if (!job$status %in% c("queued", "validating")) {
      return(fail(res, 409L, paste("source ingest cannot be validated from status", job$status)))
    }
    job <- save(req, validate(job))
    send(res, c(list(job_id = job$job_id, valid = job$valid), job$report))
  }))

  app$post("/api/v1/source-ingests/:id/promote", route(function(req, res) {
    job <- req$app$locals$jobs[[req$params$id]]
    if (is.null(job)) return(fail(res, 404L, "job not found"))
    if (job$status == "completed") return(send(res, unified(job)))
    if (job$status != "validating") {
      return(fail(res, 409L, paste("source ingest cannot be promoted from status", job$status)))
    }
    job <- save(req, promote(job))
    if (job$status == "failed") return(fail(res, 409L, job$error$message))
    send(res, unified(job))
  }))

  app$get("/api/v1/jobs/:id", route(function(req, res) {
    job <- req$app$locals$jobs[[req$params$id]]
    if (is.null(job)) return(fail(res, 404L, "job not found"))
    if (job$auto && job$status == "queued") {
      job$status <- "running"
    } else if (job$status == "running" && isTRUE(job$holds > 0L)) {
      job$holds <- job$holds - 1L
    } else if (job$status == "running") {
      job <- validate(job)
    } else if (job$auto && job$status == "validating") {
      job <- promote(job)
    }
    job <- save(req, job)
    send(res, unified(job))
  }))

  webfakes::local_app_process(app, .local_envir = .local_envir)
}

# A minimal source release: two point sites in UTM 33N (EPSG:32633), their
# profiles, components, horizons and observations.
source_manifest_fixture <- function(...) {
  utils::modifyList(list(
    provider_code = "unina", provider_name = "University of Naples Federico II",
    dataset_code = "campania_profiles", dataset_name = "Campania soil profiles",
    release_code = "2026-10", support_type = "observed_point_profile",
    default_geometry_kind = "POINT", licence_text = "CC-BY 4.0",
    assets = data.frame(asset_role = "profiles_table", source_url = "https://example.org/campania.csv",
                        stringsAsFactors = FALSE)
  ), list(...))
}

source_features_fixture <- function() {
  testthat::skip_if_not_installed("sf")
  sf::st_as_sf(
    data.frame(source_record_id = c("P1", "P2"), site_name = c("Portici", "Eboli"),
               x = c(447000, 497000), y = c(4517000, 4490000)),
    coords = c("x", "y"), crs = 32633
  )
}

source_tables_fixture <- function() {
  list(
    profiles = data.frame(source_record_id = c("P1", "P2"), feature_source_id = c("P1", "P2")),
    components = data.frame(source_record_id = c("P1-c", "P2-c"), profile_source_id = c("P1", "P2"),
                            component_rank = 1L, proportion_percent = 100),
    horizons = data.frame(source_record_id = c("P1-1", "P1-2", "P2-1"),
                          component_source_id = c("P1-c", "P1-c", "P2-c"),
                          top_depth_cm = c(0, 30, 0), bottom_depth_cm = c(30, 60, 25),
                          horizon_name = c("Ap", "Bw", "Ap")),
    observations = data.frame(source_record_id = c("o1", "o2", "o3", "o4"),
                              horizon_source_id = c("P1-1", "P1-2", "P2-1", "P2-1"),
                              property_code = c("orgc", "orgc", "orgc", "clay"),
                              value = c(12.1, 6.3, 8.4, 21), unit = c("g/kg", "g/kg", "g/kg", "%"),
                              status = "observed")
  )
}

# soil_publish_source() on the fixture release, the tables overridable.
publish_fixture <- function(soil, key, ..., features = source_features_fixture(),
                            manifest = source_manifest_fixture(), tables = source_tables_fixture()) {
  soil_publish_source(
    soil, manifest, features, tables$profiles, tables$components, tables$horizons,
    tables$observations, idempotency_key = key, progress = FALSE, ...
  )
}
