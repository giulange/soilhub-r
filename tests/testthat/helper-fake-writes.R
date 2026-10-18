# Fake write API for the publication and job tests (WP8, design 7.1): the
# routes of variables registration, products, versions, runs, value and
# soil-health publication (synchronous and NDJSON jobs), the unified job
# registry and the country refresh, with the response models of
# python/soil_api/models.py. Hand-made until WP10 records fixtures.
#
# Behaviour is chosen by the request content:
#   variables/validate  domain_code "unknown_domain" -> valid = false
#   variables           variable_code "taken" -> 409; "race" -> 409 whose
#                       detail is the JSON text of semantic errors;
#                       idempotency_key "replay" -> idempotent_replay
#   products            product_code "taken" -> 409
#   .../versions        product "nope" -> 404; version_code "taken" -> 409
#   .../runs            idempotency_key "taken" -> 409
#   complete / fail     run 99 -> 409 (illegal transition)
#   validate            records with variable_code "undeclared" are invalid
#   values, soil-health run 77 -> 422 {message, errors}; key "conflict" ->
#                       409; "replay" -> idempotent replay; "short" -> one
#                       row fewer published
#   jobs uploads        key "flaky" -> 503; "conflict" -> 409; a file whose
#                       SHA-256 differs from expected_checksum -> 409; the
#                       job lifecycle follows the key: "fail" (validation
#                       failure with rejected rows), "cancel", "slow" (never
#                       ends), "short" (one row fewer published), else
#                       queued, running, validating, promoting, completed.
#                       Each GET /jobs/{id} moves the job one step.
#   jobs/{id}/cancel    "conflict-job" -> 409; unknown -> 404
# Test controls: GET /test/log (requests received, method path query),
# POST /test/reset (clears the log), POST /test/deny (every API route answers
# 403 until POST /test/allow), GET /test/upload/{job_id} (the uploaded file).

fake_write_api <- function(.local_envir = parent.frame()) {
  testthat::skip_if_not_installed("webfakes")
  app <- webfakes::new_app()
  app$use(webfakes::mw_json())
  app$use(webfakes::mw_multipart())
  app$locals$log <- list()
  app$locals$jobs <- list()
  app$locals$uploads <- list()
  app$locals$deny <- FALSE
  app$locals$variables <- read_fixture("variables.json")

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
    query_values = function(query_string, name) {
      pairs <- strsplit(strsplit(query_string, "&", fixed = TRUE)[[1]], "=", fixed = TRUE)
      values <- vapply(pairs, function(p) if (length(p) == 2L && p[1] == name) utils::URLdecode(p[2]) else NA_character_, character(1))
      values[!is.na(values)]
    },
    run = function(run_id, status = "running", diagnostics = NULL, body = NULL) {
      list(
        run_id = as.integer(run_id), product_version_id = 7L, product_code = "soil_health_fuzzy",
        version_code = "v1.0.0", status = status, idempotency_key = body$idempotency_key %||% "run-key",
        started_at = "2026-10-18T08:00:00Z",
        completed_at = if (status == "running") NULL else "2026-10-18T09:00:00Z",
        parameters = obj(body$parameters), diagnostics = obj(diagnostics),
        input_release_ids = body$input_release_ids %||% list()
      )
    },
    unified = function(job) {
      status <- job$script[min(job$step, length(job$script))]
      done <- status == "completed"
      list(
        job_id = job$job_id, job_type = job$job_type, status = status,
        progress_percent = c(queued = 0, running = 20, validating = 40, promoting = 75,
                             completed = 100, failed = 100, cancelled = 100)[[status]],
        received_count = job$rows, staged_count = if (status == "queued") 0L else job$rows,
        accepted_count = if (done) job$rows else 0L,
        rejected_count = if (status == "failed") 1L else 0L,
        published_count = if (done) job$rows - job$short else 0L,
        checksum_sha256 = job$checksum, byte_size = job$byte_size,
        receipt_id = if (done) uuid(900) else NULL,
        correlation_id = uuid(800), diagnostics = obj(),
        error = if (status == "failed") list(code = "validation_failed", message = "publication payload is invalid") else NULL,
        retry_count = 0L, cancel_requested = isTRUE(job$cancel_requested), worker_id = NULL,
        lease_expires_at = NULL, heartbeat_at = NULL, created_at = now(),
        started_at = if (status == "queued") NULL else now(),
        finished_at = if (status %in% c("completed", "failed", "cancelled")) now() else NULL,
        updated_at = now()
      )
    },
    view = function(job) {
      status <- job$script[min(job$step, length(job$script))]
      done <- status == "completed"
      diagnostics <- if (status == "failed") {
        list(errors = list(list(row = 2L, variable_code = "my_index", errors = list("target_not_found"))),
             diagnostics_truncated = FALSE)
      } else {
        obj()
      }
      out <- list(
        job_id = job$job_id, run_id = job$run_id, status = status, input_format = "ndjson",
        checksum_sha256 = job$checksum, byte_size = job$byte_size,
        staged_count = if (status == "queued") 0L else job$rows
      )
      if (job$job_type == "soil_health_publication") {
        c(out, list(accepted_count = if (done) job$rows else 0L, rejected_count = if (status == "failed") 1L else 0L,
                    published_count = if (done) job$rows - job$short else 0L,
                    publication_ids = if (done) list(uuid(900)) else list(), diagnostics = diagnostics))
      } else {
        c(out, list(published_count = if (done) job$rows - job$short else 0L,
                    rejected_count = if (status == "failed") 1L else 0L, diagnostics = diagnostics,
                    publication_id = if (done) uuid(900) else NULL))
      }
    },
    upload = function(req, res, job_type) {
      key <- req$query$idempotency_key
      if (identical(key, "flaky")) return(fail(res, 503L, "Database unavailable"))
      if (identical(key, "conflict")) return(fail(res, 409L, "idempotency key was already used with a different file"))
      if (!identical(req$query$input_format, "ndjson")) return(fail(res, 409L, "unsupported publication format"))
      file <- req$files$file
      if (is.null(file)) return(fail(res, 422L, "file missing"))
      checksum <- as.vector(as.character(openssl::sha256(file$value)))
      expected <- req$query$expected_checksum
      if (!is.null(expected) && !identical(expected, checksum)) {
        return(fail(res, 409L, "uploaded file checksum does not match expected_checksum"))
      }
      text <- rawToChar(file$value)
      rows <- length(strsplit(text, "\n", fixed = TRUE)[[1]])
      script <- if (grepl("fail", key)) {
        c("queued", "running", "validating", "failed")
      } else if (grepl("cancel", key)) {
        c("queued", "cancelled")
      } else if (grepl("slow", key)) {
        c("queued", "running")
      } else {
        c("queued", "running", "validating", "promoting", "completed")
      }
      jobs <- req$app$locals$jobs
      id <- uuid(length(jobs) + 1L)
      job <- list(job_id = id, job_type = job_type, run_id = as.integer(req$params$run),
                  script = script, step = 1L, rows = rows, short = if (grepl("short", key)) 1L else 0L,
                  checksum = checksum, byte_size = length(file$value), key = key)
      jobs[[id]] <- job
      req$app$locals$jobs <- jobs
      uploads <- req$app$locals$uploads
      uploads[[id]] <- list(text = text, filename = file$filename,
                            content_type = req$get_header("Content-Type"))
      req$app$locals$uploads <- uploads
      send(res, view(job))
    },
    receipt = function(req, res, n, extra = list()) {
      key <- req$json$idempotency_key
      if (identical(req$params$run, "77")) {
        return(fail(res, 422L, list(message = "publication validation failed", errors = list(
          list(row = 0L, variable_code = "my_index", errors = list("target_not_found"))
        ))))
      }
      if (identical(key, "conflict")) return(fail(res, 409L, "idempotency key was already used with a different payload"))
      published <- if (identical(key, "short")) n - 1L else n
      send(res, c(list(
        publication_id = uuid(900), run_id = as.integer(req$params$run), status = "published",
        received_count = n, published_count = published,
        idempotent_replay = identical(key, "replay")
      ), extra))
    }
  )
  for (name in names(helpers)) assign(name, route(helpers[[name]]), envir = env)
  assign("%||%", function(x, y) if (is.null(x)) y else x, envir = env)

  # Log every request; refuse API routes in deny mode.
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
  app$get("/test/upload/:id", route(function(req, res) send(res, req$app$locals$uploads[[req$params$id]])))

  app$post("/api/v1/variables/validate", route(function(req, res) {
    body <- req$json
    errors <- if (identical(body$domain_code, "unknown_domain")) {
      list(list(code = "unknown_domain", message = body$domain_code))
    } else {
      list()
    }
    send(res, list(valid = length(errors) == 0L, variable_code = body$variable_code, errors = errors))
  }))
  app$post("/api/v1/variables", route(function(req, res) {
    body <- req$json
    if (identical(body$variable_code, "taken")) {
      return(fail(res, 409L, "variable_code already exists with a different definition"))
    }
    if (identical(body$variable_code, "race")) {
      return(fail(res, 409L, '[{"code":"unknown_measurement_kind","message":"guessed"}]'))
    }
    send(res, list(
      variable_id = 501L, variable_code = body$variable_code, name = body$name,
      description = body$description, domain_code = body$domain_code,
      value_type = body$value_type, measurement_kind_code = body$measurement_kind_code,
      allowed_target_levels = body$allowed_target_levels,
      idempotent_replay = identical(body$idempotency_key, "replay")
    ))
  }))
  app$get("/api/v1/variables", route(function(req, res) {
    codes <- query_values(req$query_string, "code")
    body <- req$app$locals$variables
    body$variables <- Filter(function(v) v$variable_code %in% codes, body$variables)
    body$metadata$variable_count <- length(body$variables)
    send(res, body)
  }))
  app$post("/api/v1/products", route(function(req, res) {
    body <- req$json
    if (identical(body$product_code, "taken")) {
      return(fail(res, 409L, "product_code already exists with a different definition"))
    }
    send(res, list(product_code = body$product_code, name = body$name,
                   description = body$description, target_level = body$target_level))
  }))
  app$post("/api/v1/products/:code/versions", route(function(req, res) {
    body <- req$json
    if (identical(req$params$code, "nope")) return(fail(res, 404L, "product not found"))
    if (identical(body$version_code, "taken")) {
      return(fail(res, 409L, "version_code already exists with different immutable content"))
    }
    send(res, list(
      product_code = req$params$code, product_name = "Soil health (fuzzy)", description = NULL,
      product_version_id = 7L, version_code = body$version_code,
      algorithm_checksum = body$algorithm_checksum, configuration = obj(body$configuration),
      declared_variables = body$variables, created_at = now()
    ))
  }))
  app$post("/api/v1/product-versions/:id/runs", route(function(req, res) {
    body <- req$json
    if (identical(body$idempotency_key, "taken")) {
      return(fail(res, 409L, "idempotency key was already used with different parameters"))
    }
    send(res, run(42L, body = body))
  }))
  close_run <- route(function(req, res) {
    status <- if (grepl("/complete$", req$path)) "completed" else "failed"
    if (identical(req$params$run, "99")) {
      return(fail(res, 409L, sprintf("run cannot transition from completed to %s", status)))
    }
    send(res, run(req$params$run, status, req$json$diagnostics))
  })
  app$post("/api/v1/publications/:run/complete", close_run)
  app$post("/api/v1/publications/:run/fail", close_run)
  app$post("/api/v1/publications/:run/validate", route(function(req, res) {
    values <- req$json$values
    errors <- list()
    for (i in seq_along(values)) {
      if (identical(values[[i]]$variable_code, "undeclared")) {
        errors <- c(errors, list(list(row = i - 1L, variable_code = "undeclared",
                                      errors = list("unknown_or_undeclared_variable"))))
      }
    }
    send(res, list(valid = length(errors) == 0L, run_id = as.integer(req$params$run),
                   received_count = length(values), errors = errors))
  }))
  app$post("/api/v1/publications/:run/values", route(function(req, res) {
    receipt(req, res, length(req$json$values))
  }))
  app$post("/api/v1/publications/:run/soil-health", route(function(req, res) {
    n <- length(req$json$scores)
    receipt(req, res, n, list(score_count = n))
  }))
  app$post("/api/v1/publications/:run/jobs", route(function(req, res) upload(req, res, "value_publication")))
  app$post("/api/v1/publications/:run/soil-health/jobs", route(function(req, res) upload(req, res, "soil_health_publication")))
  get_view <- route(function(req, res) {
    job <- req$app$locals$jobs[[req$params$id]]
    if (is.null(job)) return(fail(res, 404L, "publication job not found"))
    send(res, view(job))
  })
  app$get("/api/v1/publication-jobs/:id", get_view)
  app$get("/api/v1/soil-health-publication-jobs/:id", get_view)
  app$get("/api/v1/jobs/:id", route(function(req, res) {
    jobs <- req$app$locals$jobs
    job <- jobs[[req$params$id]]
    if (is.null(job)) return(fail(res, 404L, "job not found"))
    job$step <- job$step + 1L
    jobs[[req$params$id]] <- job
    req$app$locals$jobs <- jobs
    send(res, unified(job))
  }))
  app$post("/api/v1/jobs/:id/cancel", route(function(req, res) {
    if (identical(req$params$id, "conflict-job")) {
      return(fail(res, 409L, "illegal job transition from completed to cancelled"))
    }
    jobs <- req$app$locals$jobs
    job <- jobs[[req$params$id]]
    if (is.null(job)) return(fail(res, 404L, "job not found"))
    status <- job$script[min(job$step, length(job$script))]
    if (!status %in% c("completed", "failed", "cancelled")) {
      job$script <- c(job$script[seq_len(job$step)], "cancelled")
      job$step <- job$step + 1L
      job$cancel_requested <- TRUE
      jobs[[req$params$id]] <- job
      req$app$locals$jobs <- jobs
    }
    send(res, unified(job))
  }))
  app$post("/api/v1/countries/refresh", route(function(req, res) {
    job <- list(job_id = uuid(700), job_type = "country_refresh", script = "queued", step = 1L,
                rows = 0L, short = 0L, checksum = NULL, byte_size = NULL)
    out <- unified(job)
    out$diagnostics <- obj(if (is.null(req$query$idempotency_key)) list() else list(idempotency_key = req$query$idempotency_key))
    send(res, out)
  }))

  webfakes::local_app_process(app, .local_envir = .local_envir)
}

# A session signed in with a fixture token on the fake write API, the
# capabilities cached (as soil_connect() leaves them).
write_session <- function(server, jwt = "jwt-publisher.json",
                          capabilities = read_fixture("capabilities.json")) {
  soil <- new_soil_session(soil_config(api_url = server$url("/api/v1"), timeout = 30, verbose = 0))
  soil$state$capabilities <- capabilities
  store_tokens(soil, list(access_token = fixture_jwt(jwt), expires_in = 7200,
                          refresh_token = "rt-x", refresh_expires_in = 28800))
  soil
}

# Requests received by the fake API since the last reset.
fake_log <- function(server) {
  log <- httr2::resp_body_json(httr2::req_perform(httr2::request(server$url("/test/log"))))$log
  vapply(log, function(entry) paste(toupper(entry$method), entry$path), character(1))
}

fake_control <- function(server, action) {
  httr2::req_perform(httr2::req_method(httr2::request(server$url(paste0("/test/", action))), "POST"))
  invisible(NULL)
}

fake_upload <- function(server, job_id) {
  httr2::resp_body_json(httr2::req_perform(httr2::request(server$url(paste0("/test/upload/", job_id)))))
}

# Records for the publication tests.
uuid_n <- function(n) sprintf("4fa5fbe3-8fd4-4fb1-94cf-%012d", n)

value_records <- function(n = 3L, variable_code = "organic_carbon") {
  values <- data.frame(
    variable_code = variable_code, target_level = "horizon",
    target_id = uuid_n(seq_len(n)), value = seq_len(n) / 10,
    depth_top_cm = 0, depth_bottom_cm = 30, release_id = 12L,
    stringsAsFactors = FALSE
  )
  values$lineage <- lapply(seq_len(n), function(i) {
    list(observations = list(list(id = uuid_n(1000 + i), role = "organic_carbon")))
  })
  values
}

health_records <- function(n = 2L) {
  lapply(seq_len(n), function(i) list(
    horizon_id = uuid_n(i), release_id = 12L, category_code = "physical",
    score_status = "scored", score = 70 + i, score_class = "good",
    source_support = "polygon_estimate",
    observation_inputs = list(list(observation_id = uuid_n(2000 + i), input_role = "bulk_density")),
    inputs = list(bulk_density = 1.31), memberships = list(poor = 0.1, good = 0.8),
    activated_rules = list(list(rule = "physical_r4", strength = 0.7))
  ))
}
