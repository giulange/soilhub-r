# Fake long observations and features API for the WP5 tests (design 5.3,
# 5.5, 7.1).
#
# POST /api/v1/query/observations (layout = "long") serves the hand-made
# fixtures fixtures/long-*.json (built from python/soil_api/models.py and
# query.py until WP10 records them), chosen by the request body:
#   layout != "long" or geometry_format    422 (as the API: geometry_format
#                                          requires layout=wide)
#   no `datasets`                          422 load_limit_exceeded (sync)
#   view = "revised"                       long-soter-revised.json
#   datasets wosis_points                  long-wosis-page1.json at offset 0,
#                                          long-wosis-page2.json after it
#                                          (country "FAIL": HTTP 500 after
#                                          page 1)
# Without `include_geometry = true` the rows have `geometry` and
# `geometry_kind` null (as the API does); with it the metadata warns.
# POST /api/v1/query/features serves fixtures/features-*.json:
#   layout or geometry_format              422 (accepted only by observations)
#   no `datasets`                          422 load_limit_exceeded (sync)
#   datasets wosis_points                  features-points-page1.json at
#                                          offset 0, features-points-page2.json
#                                          after it (country "FAIL": 500 after
#                                          page 1)
#   datasets sotwis_polygons               features-polygons.json (with
#                                          soter_profiles points: mixed)
#   datasets wise_profiles                 features-nogeom.json
# Every page echoes the body in `metadata.filters` and the X-Request-ID in
# `metadata.request_id`. GET /api/v1/datasets serves fixtures/datasets.json;
# GET /test/requests counts the API requests received.

fake_long_api <- function(.local_envir = parent.frame()) {
  testthat::skip_if_not_installed("webfakes")
  app <- webfakes::new_app()
  app$use(webfakes::mw_json())
  app$locals$requests <- 0L
  app$locals$fixtures <- list(
    wosis1 = read_fixture("long-wosis-page1.json"),
    wosis2 = read_fixture("long-wosis-page2.json"),
    soter = read_fixture("long-soter-revised.json"),
    points1 = read_fixture("features-points-page1.json"),
    points2 = read_fixture("features-points-page2.json"),
    polygons = read_fixture("features-polygons.json"),
    nogeom = read_fixture("features-nogeom.json"),
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
  fail <- function(res, status, detail) {
    res$set_status(status)$send_json(list(detail = detail), auto_unbox = TRUE)
  }
  load_limit <- function(res) {
    res$set_status(422L)$send_json(list(detail = list(
      code = "load_limit_exceeded",
      message = paste0(
        "The selection holds more than 1,000,000 observations, above the limit of synchronous requests ",
        "(1,000,000): narrow the selection (bbox, country, datasets, variables, layer, profile_type) or ",
        "request an export (POST /exports)."
      ),
      channel = "sync", max_observations = 1000000L, observation_count = 1000001L,
      observation_count_exact = TRUE, exports_url = "/api/v1/exports"
    )), auto_unbox = TRUE)
  }
  stamp <- function(page, b, id, offset) {
    page$metadata$request_id <- id
    page$metadata$filters <- b
    page$metadata$limit <- b$limit
    page$metadata$offset <- offset
    page
  }
  assign("send", route(send), envir = env)
  assign("fail", route(fail), envir = env)
  assign("load_limit", route(load_limit), envir = env)
  assign("stamp", route(stamp), envir = env)

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
    if (!identical(b$layout, "long")) return(fail(res, 422L, "this fake serves layout=long only"))
    if (!is.null(b$geometry_format)) return(fail(res, 422L, "geometry_format requires layout=wide"))
    datasets <- unlist(b$datasets)
    if (is.null(datasets)) return(load_limit(res))
    offset <- if (is.null(b$offset)) 0 else b$offset
    page <- if (identical(b$view, "revised")) {
      fx$soter
    } else if (identical(datasets[[1]], "wosis_points")) {
      if (offset == 0) fx$wosis1 else fx$wosis2
    } else {
      NULL
    }
    if (is.null(page)) return(fail(res, 422L, "Unknown dataset(s)"))
    if (identical(unlist(b$country), "FAIL") && offset > 0) {
      return(fail(res, 500L, "canonical observation query failed"))
    }
    page <- stamp(page, b, id, offset)
    if (isTRUE(b$include_geometry)) {
      page$metadata$include_geometry <- TRUE
      page$metadata$warnings <- c(page$metadata$warnings, list("Observation geometry increases response payload size"))
    } else {
      page$observations <- lapply(page$observations, function(row) {
        row["geometry"] <- list(NULL)
        row["geometry_kind"] <- list(NULL)
        row
      })
    }
    send(res, page)
  }))

  app$post("/api/v1/query/features", route(function(req, res) {
    b <- req$json
    fx <- req$app$locals$fixtures
    id <- req$get_header("X-Request-ID")
    if (!is.null(id)) res$set_header("X-Request-ID", id)
    if (!is.null(b$layout) || !is.null(b$geometry_format)) {
      return(fail(res, 422L, "layout and geometry_format are accepted only by POST /query/observations"))
    }
    datasets <- unlist(b$datasets)
    if (is.null(datasets)) return(load_limit(res))
    offset <- if (is.null(b$offset)) 0 else b$offset
    page <- if ("sotwis_polygons" %in% datasets) {
      fx$polygons
    } else {
      switch(datasets[[1]],
        wosis_points = if (offset == 0) fx$points1 else fx$points2,
        wise_profiles = fx$nogeom,
        NULL
      )
    }
    if (is.null(page)) return(fail(res, 422L, "Unknown dataset(s)"))
    if (identical(unlist(b$country), "FAIL") && offset > 0) {
      return(fail(res, 500L, "canonical feature query failed"))
    }
    send(res, stamp(page, b, id, offset))
  }))
  webfakes::local_app_process(app, .local_envir = .local_envir)
}

# The source column of the wide layout for a long row (wide_layout.py):
# the canonical property key, else `src_<code>` (lower case, other
# characters as `_`).
wide_column_of <- function(property_code, canonical_property_key) {
  ifelse(
    is.na(canonical_property_key),
    paste0("src_", gsub("[^a-z0-9_]", "_", tolower(property_code))),
    canonical_property_key
  )
}

# Wide/long equivalence (design 5.3, acceptance 10.4) of two soil_tables of
# the same selection: the keys of the wide rows equal the distinct keys of
# the long rows; per key and property, the wide `<key>` equals the first long
# value (numeric columns: `value`, multi-value cells their mean; text columns:
# the source text of `value_raw`) and `<key>_n` the number of long rows.
# Returns the mismatches (character, empty when equivalent).
wide_long_mismatches <- function(wide, long) {
  out <- character()
  key <- function(x) paste(x$dataset, x$feature_id, x$component_id, x$horizon_id, sep = "|")
  wide_keys <- key(wide)
  long_keys <- key(long)
  if (anyDuplicated(wide_keys)) out <- c(out, "duplicated wide keys")
  if (!setequal(unique(long_keys), wide_keys)) out <- c(out, "different key sets")
  column <- wide_column_of(long$property_code, long$canonical_property_key)
  columns <- soil_columns(wide)
  if (!setequal(unique(column), columns$column)) out <- c(out, "different property sets")
  for (i in seq_len(nrow(columns))) {
    name <- columns$column[[i]]
    for (k in seq_along(wide_keys)) {
      rows <- which(long_keys == wide_keys[[k]] & column == name)
      first <- if (length(rows)) rows[[1]] else NA_integer_
      expected_n <- if (length(rows)) length(rows) else NA_integer_
      expected <- if (columns$numeric[[i]]) {
        if (is.na(first)) NA_real_ else long$value[[first]]
      } else {
        if (is.na(first)) NA_character_ else scalar_chr(long$value_raw[[first]])
      }
      if (!identical(wide[[paste0(name, "_n")]][[k]], expected_n)) {
        out <- c(out, sprintf("%s_n of %s", name, wide_keys[[k]]))
      }
      if (!identical(wide[[name]][[k]], expected)) {
        out <- c(out, sprintf("%s of %s", name, wide_keys[[k]]))
      }
    }
  }
  out
}

# Pages (a soilhub_pages) from long or features fixture files, without a
# server; `items` is the page array ("observations" or "features").
fixture_item_pages <- function(..., items = "observations", complete = TRUE) {
  pages <- lapply(c(...), read_fixture)
  metadata <- pages[[1]]$metadata
  metadata[c("limit", "offset", "returned_count", "has_more", "request_id", "total_count", "warnings")] <- NULL
  metadata$endpoint <- if (identical(items, "features")) "/query/features" else "/query/observations"
  metadata$request <- list(datasets = I(unlist(metadata$datasets)), view = metadata$view %||% "raw",
                           canonical = TRUE)
  metadata$request_ids <- paste0("soilhub-test-", seq_along(pages))
  metadata$pages <- length(pages)
  metadata$complete <- complete
  metadata$next_offset <- if (complete) NA_real_ else sum(vapply(pages, function(p) length(p[[items]]), numeric(1)))
  metadata$total_count <- pages[[1]]$metadata$total_count %||% NA_real_
  metadata$warnings <- unique(unlist(lapply(pages, function(p) p$metadata$warnings)))
  structure(
    list(
      items = unlist(lapply(pages, `[[`, items), recursive = FALSE),
      metadata = metadata,
      page_metadata = lapply(pages, `[[`, "metadata"),
      extras = lapply(pages, function(p) p[setdiff(names(p), c(items, "metadata"))])
    ),
    class = "soilhub_pages"
  )
}
