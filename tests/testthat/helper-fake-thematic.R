# Fake summaries and thematic reads API for the WP6 tests (design 7.1):
# hand-made fixtures (fixtures/summary*.json, availability.json,
# consistency*.json, values-*.json, health*.json, ttr-flags-*.json) built from
# the models of python/soil_api until WP10 records them.
#
#   POST /query/summary        summary-sotwis-revised.json when the body has
#                              `view = "revised"` or datasets sotwis_polygons,
#                              else summary.json; a body with `layout` or
#                              `geometry_format` is refused with 422, as the
#                              API does
#   POST /query/availability   availability.json (same 422 rule)
#   POST /query/consistency    consistency-global.json without any filter,
#                              else consistency.json
#   POST /query/values         values-page1.json at offset 0, values-page2.json
#                              after it (`include_geometry = false` empties
#                              `geometry`; `include_lineage = true` adds the
#                              lineage fields); datasets "FAIL" -> HTTP 500
#                              after page 1
#   POST /query/values/summary values-summary.json
#   POST /query/soil-health    health.json, or health-details.json with
#                              `include_details = true`
#   POST /query/soil-health/summary  health-summary.json
#   POST /query/targets/resolve  built from the request: source_record_id
#                              "missing*" -> missing, "dup*" -> ambiguous (2
#                              candidates), else resolved; more than 10,000
#                              targets -> 422
#   GET  /sotwis/ttr-flags     ttr-flags-page1.json at offset 0, page 2 after
#   GET  /datasets             datasets.json
# Test controls: GET /test/log (requests received: method, path, body as
# JSON text, query string), POST /test/reset.

fake_thematic_api <- function(.local_envir = parent.frame()) {
  testthat::skip_if_not_installed("webfakes")
  app <- webfakes::new_app()
  app$use(webfakes::mw_json())
  app$locals$log <- list()
  app$locals$fixtures <- lapply(
    c(summary = "summary.json", summary_revised = "summary-sotwis-revised.json",
      availability = "availability.json", consistency = "consistency.json",
      consistency_global = "consistency-global.json", values1 = "values-page1.json",
      values2 = "values-page2.json", values_summary = "values-summary.json",
      health = "health.json", health_details = "health-details.json",
      health_summary = "health-summary.json", ttr1 = "ttr-flags-page1.json",
      ttr2 = "ttr-flags-page2.json", datasets = "datasets.json"),
    read_fixture
  )
  env <- new.env(parent = baseenv())
  route <- function(handler) {
    environment(handler) <- env
    handler
  }
  send <- function(req, res, body) {
    id <- req$get_header("X-Request-ID")
    if (!is.null(id)) {
      res$set_header("X-Request-ID", id)
      if (is.list(body$metadata)) body$metadata$request_id <- id
    }
    res$send_json(body, auto_unbox = TRUE, null = "null", na = "null", digits = NA)
  }
  refuse <- function(res, status, detail) {
    res$set_status(status)$send_json(list(detail = detail), auto_unbox = TRUE)
  }
  layout_refused <- function(req, res) {
    b <- req$json
    if (!is.null(b$layout) || !is.null(b$geometry_format)) {
      refuse(res, 422L, "layout and geometry_format are accepted only by POST /query/observations")
      return(TRUE)
    }
    FALSE
  }
  assign("send", route(send), envir = env)
  assign("refuse", route(refuse), envir = env)
  assign("layout_refused", route(layout_refused), envir = env)

  app$use(route(function(req, res) {
    if (startsWith(req$path, "/api/")) {
      body <- if (is.null(req$json)) "" else {
        as.character(jsonlite::toJSON(req$json, auto_unbox = TRUE, null = "null", digits = NA))
      }
      req$app$locals$log[[length(req$app$locals$log) + 1L]] <- list(
        method = req$method, path = sub("^/api/v1", "", req$path),
        body = body, query = req$query_string
      )
    }
    "next"
  }))
  app$get("/test/log", route(function(req, res) {
    res$send_json(list(log = req$app$locals$log), auto_unbox = TRUE, null = "null")
  }))
  app$post("/test/reset", route(function(req, res) {
    req$app$locals$log <- list()
    res$send_json(list(ok = TRUE), auto_unbox = TRUE)
  }))
  app$get("/api/v1/datasets", route(function(req, res) send(req, res, req$app$locals$fixtures$datasets)))

  app$post("/api/v1/query/summary", route(function(req, res) {
    if (layout_refused(req, res)) return()
    b <- req$json
    fx <- req$app$locals$fixtures
    revised <- identical(b$view, "revised") || identical(unlist(b$datasets), "sotwis_polygons")
    send(req, res, if (revised) fx$summary_revised else fx$summary)
  }))
  app$post("/api/v1/query/availability", route(function(req, res) {
    if (layout_refused(req, res)) return()
    send(req, res, req$app$locals$fixtures$availability)
  }))
  app$post("/api/v1/query/consistency", route(function(req, res) {
    b <- req$json
    fx <- req$app$locals$fixtures
    send(req, res, if (length(b) == 0L) fx$consistency_global else fx$consistency)
  }))
  app$post("/api/v1/query/values", route(function(req, res) {
    b <- req$json
    fx <- req$app$locals$fixtures
    offset <- if (is.null(b$offset)) 0 else b$offset
    if (identical(unlist(b$datasets), "FAIL") && offset > 0) {
      return(refuse(res, 500L, "generic value query failed"))
    }
    page <- if (offset == 0) fx$values1 else fx$values2
    page$values <- lapply(page$values, function(row) {
      if (isFALSE(b$include_geometry)) row["geometry"] <- list(NULL)
      if (isTRUE(b$include_lineage)) {
        row$observation_inputs <- list(list(observation_id = "obs-1", input_role = "organic_carbon"))
        row$value_inputs <- list()
        row$release_inputs <- list(list(release_id = 12))
        row$asset_inputs <- list()
      }
      row
    })
    page$metadata$filters <- b
    send(req, res, page)
  }))
  app$post("/api/v1/query/values/summary", route(function(req, res) {
    send(req, res, req$app$locals$fixtures$values_summary)
  }))
  app$post("/api/v1/query/soil-health", route(function(req, res) {
    b <- req$json
    fx <- req$app$locals$fixtures
    page <- if (isTRUE(b$include_details)) fx$health_details else fx$health
    if (isFALSE(b$include_geometry)) {
      page$scores <- lapply(page$scores, function(row) {
        row["geometry"] <- list(NULL)
        row
      })
    }
    send(req, res, page)
  }))
  app$post("/api/v1/query/soil-health/summary", route(function(req, res) {
    send(req, res, req$app$locals$fixtures$health_summary)
  }))
  app$post("/api/v1/query/targets/resolve", route(function(req, res) {
    targets <- req$json$targets
    if (length(targets) > 10000L) {
      return(refuse(res, 422L, "List should have at most 10000 items after validation"))
    }
    results <- lapply(seq_along(targets), function(i) {
      key <- targets[[i]]
      id <- key$source_record_id
      status <- if (startsWith(id, "missing")) "missing" else if (startsWith(id, "dup")) "ambiguous" else "resolved"
      out <- list(
        input_index = i - 1L, status = status, provider_code = key$provider_code,
        dataset_code = key$dataset_code, release_code = key$release_code,
        target_level = key$target_level, source_record_id = id,
        source_table = if (is.null(key$source_table)) NULL else key$source_table,
        release_status = NULL, target_id = NULL, feature_id = NULL,
        profile_id = NULL, component_id = NULL, horizon_id = NULL,
        source_support = NULL, geometry_kind = NULL, top_depth_cm = NULL,
        bottom_depth_cm = NULL,
        candidate_count = switch(status, missing = 0L, ambiguous = 2L, resolved = 1L)
      )
      if (status == "resolved") {
        out$release_status <- "current"
        out$target_id <- paste0("uuid-", key$target_level, "-", id)
        out$feature_id <- paste0("uuid-feature-", id)
        out$source_support <- "point_observation"
        out$geometry_kind <- "POINT"
      }
      out
    })
    counts <- table(factor(vapply(results, `[[`, "", "status"), c("resolved", "missing", "ambiguous")))
    send(req, res, list(
      metadata = list(schema_version = "1.0", total_count = length(results),
                      returned_count = length(results),
                      status_counts = as.list(stats::setNames(as.integer(counts), names(counts)))),
      targets = results
    ))
  }))
  app$get("/api/v1/sotwis/ttr-flags", route(function(req, res) {
    fx <- req$app$locals$fixtures
    offset <- if (is.null(req$query$offset)) 0 else as.numeric(req$query$offset)
    page <- if (offset == 0) fx$ttr1 else fx$ttr2
    if (identical(req$query$view, "revised")) {
      page$metadata$view <- "revised"
      page$metadata$revised <- list(rules = list(list(id = "R6", linked_prids = list("TN-ab1"))))
    }
    send(req, res, page)
  }))
  webfakes::local_app_process(app, .local_envir = .local_envir)
}

# A signed-out session on the fake API with the capabilities cached.
thematic_session <- function(server, capabilities = read_fixture("capabilities.json"), page_size = NULL) {
  soil <- new_soil_session(soil_config(api_url = server$url("/api/v1"), timeout = 30, verbose = 0,
                                       page_size = page_size))
  soil$state$capabilities <- capabilities
  soil
}

# Requests received since the last reset: a list of method, path, body
# (parsed JSON or NULL), query string.
thematic_log <- function(server) {
  log <- httr2::resp_body_json(httr2::req_perform(httr2::request(server$url("/test/log"))))$log
  lapply(log, function(entry) {
    entry$body <- if (nzchar(entry$body)) jsonlite::fromJSON(entry$body, simplifyVector = FALSE) else NULL
    entry
  })
}

thematic_reset <- function(server) {
  httr2::req_perform(httr2::req_method(httr2::request(server$url("/test/reset")), "POST"))
  invisible(NULL)
}

# The API requests (not the catalog) of the log.
thematic_calls <- function(server, path = NULL) {
  log <- Filter(function(entry) !identical(entry$path, "/datasets"), thematic_log(server))
  if (!is.null(path)) log <- Filter(function(entry) identical(entry$path, path), log)
  log
}
