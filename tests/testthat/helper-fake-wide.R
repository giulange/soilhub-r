# Fake wide observations API for the WP4 tests (design 5.2, 7.1).
#
# POST /api/v1/query/observations serves the hand-made fixtures
# fixtures/wide-*.json (built from python/soil_api/wide_layout.py until WP10
# records them), chosen by the request body:
#   no `datasets`                      422 load_limit_exceeded (sync)
#   view = "revised"                   wide-revised.json
#   layer = "first"                    wide-first-layer.json
#   datasets wosis_points              wide-wosis-page1.json at offset 0,
#                                      wide-wosis-page2.json after it
#                                      (country "FAIL": HTTP 500 after page 1)
#   datasets wise_profiles             wide-wise.json
#   datasets soter_profiles            wide-soter.json
#   datasets sotwis_polygons           wide-sotwis.json
# The page echoes the body in `metadata.filters` and the X-Request-ID in
# `metadata.request_id`; without `geometry_format = "wkt"` the rows lose
# `geometry_kind` and `geometries` is null (as the API does).
# GET /api/v1/datasets serves fixtures/datasets.json; GET /test/requests
# counts the API requests received.

fake_wide_api <- function(.local_envir = parent.frame()) {
  testthat::skip_if_not_installed("webfakes")
  app <- webfakes::new_app()
  app$use(webfakes::mw_json())
  app$locals$requests <- 0L
  app$locals$fixtures <- list(
    wosis1 = read_fixture("wide-wosis-page1.json"),
    wosis2 = read_fixture("wide-wosis-page2.json"),
    wise = read_fixture("wide-wise.json"),
    soter = read_fixture("wide-soter.json"),
    sotwis = read_fixture("wide-sotwis.json"),
    revised = read_fixture("wide-revised.json"),
    first = read_fixture("wide-first-layer.json"),
    datasets = read_fixture("datasets.json")
  )
  env <- new.env(parent = baseenv())
  route <- function(handler) {
    environment(handler) <- env
    handler
  }
  send <- function(res, body) {
    res$send_json(body, auto_unbox = TRUE, null = "null", na = "null", digits = NA)
  }
  assign("send", route(send), envir = env)

  app$use(route(function(req, res) {
    if (startsWith(req$path, "/api/")) req$app$locals$requests <- req$app$locals$requests + 1L
    "next"
  }))
  app$get("/test/requests", route(function(req, res) send(res, list(n = req$app$locals$requests))))
  app$get("/api/v1/datasets", route(function(req, res) send(res, req$app$locals$fixtures$datasets)))
  app$post("/api/v1/query/observations", route(function(req, res) {
    b <- req$json
    fx <- req$app$locals$fixtures
    id <- req$get_header("X-Request-ID")
    if (!is.null(id)) res$set_header("X-Request-ID", id)
    datasets <- unlist(b$datasets)
    if (is.null(datasets)) {
      return(res$set_status(422L)$send_json(list(detail = list(
        code = "load_limit_exceeded",
        message = paste0(
          "The selection holds more than 1,000,000 observations, above the limit of synchronous requests ",
          "(1,000,000): narrow the selection (bbox, country, datasets, variables, layer, profile_type) or ",
          "request an export (POST /exports)."
        ),
        channel = "sync", max_observations = 1000000L, observation_count = 1000001L,
        observation_count_exact = FALSE, exports_url = "/api/v1/exports"
      )), auto_unbox = TRUE))
    }
    offset <- if (is.null(b$offset)) 0 else b$offset
    page <- if (identical(b$view, "revised")) {
      fx$revised
    } else if (identical(b$layer, "first")) {
      fx$first
    } else {
      switch(datasets[[1]],
        wosis_points = if (offset == 0) fx$wosis1 else fx$wosis2,
        wise_profiles = fx$wise,
        soter_profiles = fx$soter,
        sotwis_polygons = fx$sotwis,
        NULL
      )
    }
    if (is.null(page)) {
      return(res$set_status(422L)$send_json(list(detail = "Unknown dataset(s)"), auto_unbox = TRUE))
    }
    if (identical(unlist(b$country), "FAIL") && offset > 0) {
      return(res$set_status(500L)$send_json(list(detail = "wide observation query failed"), auto_unbox = TRUE))
    }
    page$metadata$request_id <- id
    page$metadata$filters <- b
    page$metadata$limit <- b$limit
    page$metadata$offset <- offset
    if (!identical(b$geometry_format, "wkt")) {
      page$metadata$geometry_format <- "none"
      page$geometries <- NULL
      page["geometries"] <- list(NULL)
      page$rows <- lapply(page$rows, function(row) {
        row$geometry_kind <- NULL
        row
      })
    }
    send(res, page)
  }))
  webfakes::local_app_process(app, .local_envir = .local_envir)
}

# A signed-out session on the fake wide API with the capabilities cached.
wide_session <- function(server, capabilities = read_fixture("capabilities.json")) {
  soil <- new_soil_session(soil_config(api_url = server$url("/api/v1"), timeout = 30, verbose = 0))
  soil$state$capabilities <- capabilities
  soil
}

api_requests <- function(server) {
  jsonlite::fromJSON(paste(readLines(server$url("/test/requests"), warn = FALSE), collapse = ""))$n
}

# Pages (a soilhub_pages) from fixture files, without a server.
fixture_pages <- function(..., complete = TRUE) {
  pages <- lapply(c(...), read_fixture)
  metadata <- pages[[1]]$metadata
  metadata[c("limit", "offset", "returned_count", "has_more", "request_id", "total_count", "warnings")] <- NULL
  metadata$endpoint <- "/query/observations"
  metadata$request <- list(datasets = I(unlist(metadata$datasets)), view = "raw", layer = "all",
                           canonical = TRUE, layout = "wide", geometry_format = "wkt")
  metadata$request_ids <- paste0("soilhub-test-", seq_along(pages))
  metadata$pages <- length(pages)
  metadata$complete <- complete
  metadata$next_offset <- if (complete) NA_real_ else sum(vapply(pages, function(p) length(p$rows), numeric(1)))
  metadata$total_count <- NA_real_
  metadata$warnings <- unique(unlist(lapply(pages, function(p) p$metadata$warnings)))
  structure(
    list(
      items = unlist(lapply(pages, `[[`, "rows"), recursive = FALSE),
      metadata = metadata,
      page_metadata = lapply(pages, `[[`, "metadata"),
      extras = lapply(pages, function(p) list(geometries = p$geometries))
    ),
    class = "soilhub_pages"
  )
}
