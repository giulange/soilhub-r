# Export zips and a fake export API for the WP7 tests (design 6, 7.1).
#
# build_export_zip() writes a small real export zip, laid out as the API's
# export writer (python/soil_api/export_writer.py) lays it out, from the
# synchronous fixtures: the features of features-points-page1/2.json (or of
# features-polygons.json for the Shapefile), the wide rows of
# wide-wosis-page1/2.json (one column set for the whole export, no
# geometry_kind: exports carry no geometry in the observations) or the long
# records of long-wosis-page1/2.json (geometry null), and a metadata.json
# with `wide_columns` merged over the pages as the writer merges them.
#   geojson   features.geojson, observations.geojson (nested values as JSON)
#   csv, tsv  features.<ext> with geometry_wkt, observations.<ext>; nested
#             values as JSON text, null as an empty field, booleans true/false
#   gpkg      export.gpkg (layers features, observations) written by GDAL
#             from GeoJSON sequence files, as the writer does with ogr2ogr
#   shp       features_points.*, features_polygons.* (content = "features")
#
# fake_export_api() serves POST /exports, GET /exports/{id} (queued ->
# running 5% -> running 45% -> completed), GET /exports/{id}/download (the
# zip built for the format, content and layout of the job), POST
# /jobs/{id}/cancel, and refuses every synchronous read with a sync
# load-limit 422. The `country` of the selection picks a scenario:
#   "WORLD"   422 load_limit_exceeded of the export channel at submission
#   "FAIL"    the export fails at the second poll
#   "SLOW"    the export stays running
#   "GONE"    completed, but the download answers 404 (expired file)
# GET /test/exports returns the bodies of the submissions.

export_job_id <- "exp_20261019_080000_0000beef"

wide_fixture_pages <- function() {
  list(read_fixture("wide-wosis-page1.json"), read_fixture("wide-wosis-page2.json"))
}

# The wide rows of an export: one column set (the union of the variable
# groups, sorted), without geometry_kind.
export_wide_rows <- function(pages = wide_fixture_pages()) {
  vars <- sort(unique(unlist(lapply(pages, function(p) vapply(p$metadata$variables, `[[`, "", "column")))))
  groups <- unlist(lapply(vars, function(v) paste0(v, c("", "_units", "_method", "_n"))))
  rows <- unlist(lapply(pages, `[[`, "rows"), recursive = FALSE)
  fixed <- setdiff(names(rows[[1]]), c(groups, "geometry_kind"))
  lapply(rows, function(row) {
    out <- row[fixed]
    for (name in groups) out[name] <- list(row[[name]])
    out
  })
}

# metadata.variables of the pages merged as the writer's _VariableTotals.
export_wide_columns <- function(pages = wide_fixture_pages()) {
  items <- unlist(lapply(pages, function(p) p$metadata$variables), recursive = FALSE)
  columns <- vapply(items, `[[`, "", "column")
  lapply(sort(unique(columns)), function(column) {
    its <- items[columns == column]
    with_cells <- Filter(function(i) isTRUE(i$horizon_count > 0), its)
    methods <- stats::setNames(list(), character())
    facets <- stats::setNames(list(), character())
    for (i in its) {
      for (code in names(i$methods)) methods[[code]] <- i$methods[[code]]
      for (key in names(i$method_facets)) {
        facets[[key]] <- as.list(sort(unique(c(unlist(facets[[key]]), unlist(i$method_facets[[key]])))))
      }
    }
    notes <- unique(unlist(lapply(its, `[[`, "source_notes"), recursive = FALSE))
    list(
      column = column,
      property_key = its[[1]]$property_key,
      numeric = all(vapply(with_cells, function(i) isTRUE(i$numeric), logical(1))),
      units = as.list(sort(unique(unlist(lapply(its, `[[`, "units"))))),
      source_codes = as.list(sort(unique(unlist(lapply(its, `[[`, "source_codes"))))),
      horizon_count = sum(vapply(its, function(i) as.numeric(i$horizon_count), 0)),
      multi_value_cells = sum(vapply(its, function(i) as.numeric(i$multi_value_cells), 0)),
      methods = methods[sort(names(methods))],
      source_notes = if (length(notes)) notes else list(),
      method_facets = facets[sort(names(facets))]
    )
  })
}

# The long records of an export: geometry and geometry_kind null.
export_long_rows <- function() {
  pages <- list(read_fixture("long-wosis-page1.json"), read_fixture("long-wosis-page2.json"))
  rows <- unlist(lapply(pages, `[[`, "observations"), recursive = FALSE)
  lapply(rows, function(row) {
    row["geometry"] <- list(NULL)
    row["geometry_kind"] <- list(NULL)
    row
  })
}

export_features <- function(polygons = FALSE) {
  if (polygons) return(read_fixture("features-polygons.json")$features)
  c(read_fixture("features-points-page1.json")$features, read_fixture("features-points-page2.json")$features)
}

to_json <- function(x, pretty = FALSE) {
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", na = "null", digits = NA, pretty = pretty))
}

# A cell of the flat formats: objects and lists as JSON text.
flat_cell <- function(v) if (is.list(v)) to_json(v) else v

# A cell of CSV/TSV as the Python csv module writes it.
delimited_cell <- function(v) {
  v <- flat_cell(v)
  if (is.null(v) || (length(v) == 1L && is.na(v))) return("")
  if (is.logical(v)) return(tolower(as.character(v)))
  if (is.numeric(v)) return(format(v, digits = 15, scientific = FALSE, trim = TRUE))
  as.character(v)
}

write_delimited <- function(path, rows, sep, extra = NULL) {
  header <- c(names(rows[[1]]), names(extra))
  quote <- function(x) {
    need <- grepl(sep, x, fixed = TRUE) | grepl("[\"\r\n]", x)
    x[need] <- paste0("\"", gsub("\"", "\"\"", x[need], fixed = TRUE), "\"")
    x
  }
  lines <- vapply(seq_along(rows), function(i) {
    cells <- vapply(rows[[i]], delimited_cell, character(1))
    if (!is.null(extra)) cells <- c(cells, vapply(extra, function(e) e[[i]], character(1)))
    paste(quote(cells), collapse = sep)
  }, character(1))
  text <- paste0(paste(c(paste(quote(header), collapse = sep), lines), collapse = "\r\n"), "\r\n")
  writeBin(charToRaw(enc2utf8(text)), path)
}

write_geojson <- function(path, features) {
  writeLines(to_json(list(type = "FeatureCollection", features = features)), path, useBytes = TRUE)
}

feature_of_row <- function(row) list(type = "Feature", geometry = NULL, properties = row)

# A GeoJSON sequence (one feature per line, nested values as JSON text), then
# GDAL as ogr2ogr: `options` the arguments after the source and target.
write_with_gdal <- function(features, workdir, name, target, options) {
  source <- file.path(workdir, paste0(name, ".geojsonl"))
  lines <- vapply(features, function(f) {
    f$properties <- lapply(f$properties, function(v) if (is.list(v)) to_json(v) else v)
    to_json(list(type = "Feature", geometry = f$geometry, properties = f$properties))
  }, character(1))
  writeLines(lines, source, useBytes = TRUE)
  suppressWarnings(sf::gdal_utils("vectortranslate", source, target, options = options, quiet = TRUE))
  unlink(source)
}

gdal_can_write <- function(driver) {
  if (!requireNamespace("sf", quietly = TRUE)) return(FALSE)
  drivers <- sf::st_drivers()
  isTRUE(drivers$write[drivers$name == driver]) && "GeoJSONSeq" %in% drivers$name
}

skip_if_no_zip <- function() {
  testthat::skip_if(!nzchar(Sys.which(Sys.getenv("R_ZIPCMD", "zip"))), "no zip program")
}

export_metadata <- function(job_id, format, content, layout, files, wide_columns = NULL,
                            warnings = list(), view = NULL, polygons = FALSE) {
  catalog <- read_fixture("datasets.json")$datasets
  dataset <- if (polygons) "sotwis_polygons" else "wosis_points"
  fields <- c("name", "title", "provider_code", "release_code", "description", "citation_text",
              "licence_text", "notes", "citation_source_url", "licence_url", "release_acquired_at")
  entry <- Filter(function(d) identical(d$name, dataset), catalog)
  entry <- lapply(entry, function(d) d[intersect(fields, names(d))])
  request <- list(datasets = list(dataset), geometry = "any", layer = "all", canonical = TRUE,
                  format = format, content = content)
  if (identical(content, "all")) request$layout <- layout
  if (!is.null(view)) request$view <- view
  records <- list(features = if (polygons) 4L else 3L, features_by_dataset = stats::setNames(list(if (polygons) 4L else 3L), dataset))
  if (identical(content, "all")) {
    rows <- if (identical(layout, "wide")) 5L else 17L
    records$observation_rows <- rows
    records$observation_rows_by_dataset <- list(wosis_points = rows)
    records$observations <- 17L
    records$observations_by_dataset <- list(wosis_points = 17L)
  }
  meta <- list(
    schema_version = "1.0", api_version = "0.6.0", job_id = job_id,
    generated_at = "2026-10-19T08:00:05+00:00", format = format, content = content,
    layout = if (identical(content, "all")) layout else NULL, crs = "EPSG:4326",
    request = request, files = as.list(files),
    tables = list(features = "one record per feature of the selection"),
    records = records, datasets = entry,
    variables = list(list(dataset = dataset, property_code = "CLAY", observation_count = 5L,
                          variants = list())),
    warnings = warnings
  )
  if (!is.null(wide_columns)) meta$wide_columns <- wide_columns
  if (!is.null(view)) meta$view <- view
  meta
}

# Build an export zip in `dir`; returns its path (skips when the format
# needs a missing tool).
build_export_zip <- function(dir, format, content = "all", layout = "wide",
                             job_id = export_job_id, empty = FALSE) {
  skip_if_no_zip()
  if (format %in% c("gpkg", "shp")) {
    testthat::skip_if_not(gdal_can_write(if (format == "gpkg") "GPKG" else "ESRI Shapefile"),
                          "sf/GDAL cannot write the format")
  }
  polygons <- identical(format, "shp")
  workdir <- file.path(dir, paste(format, content, layout, sep = "-"))
  unlink(workdir, recursive = TRUE)
  dir.create(workdir, recursive = TRUE)
  features <- if (empty) list() else export_features(polygons)
  wide <- identical(layout, "wide")
  rows <- if (!identical(content, "all") || empty) list() else if (wide) export_wide_rows() else export_long_rows()
  files <- character()
  if (format == "geojson") {
    write_geojson(file.path(workdir, "features.geojson"), features)
    files <- "features.geojson"
    if (content == "all") {
      write_geojson(file.path(workdir, "observations.geojson"), lapply(rows, feature_of_row))
      files <- c(files, "observations.geojson")
    }
  } else if (format %in% c("csv", "tsv")) {
    sep <- if (format == "tsv") "\t" else ","
    props <- lapply(features, `[[`, "properties")
    wkt <- vapply(features, function(f) {
      w <- geojson_to_wkt(f$geometry)
      if (is.na(w)) "" else w
    }, character(1))
    if (length(props)) {
      write_delimited(file.path(workdir, paste0("features.", format)), props, sep, list(geometry_wkt = wkt))
    } else {
      # the writer's empty header
      header <- c("dataset", "provider_code", "feature_id", "feature_key", "geometry_kind", "source_support", "geometry_wkt")
      writeBin(charToRaw(paste0(paste(header, collapse = sep), "\r\n")), file.path(workdir, paste0("features.", format)))
    }
    files <- paste0("features.", format)
    if (content == "all") {
      path <- file.path(workdir, paste0("observations.", format))
      if (length(rows)) write_delimited(path, rows, sep) else file.create(path)
      files <- c(files, paste0("observations.", format))
    }
  } else if (format == "gpkg") {
    target <- file.path(workdir, "export.gpkg")
    write_with_gdal(features, workdir, "features", target,
                    c("-f", "GPKG", "-nln", "features", "-gt", "65536", "-a_srs", "EPSG:4326"))
    if (content == "all" && length(rows)) {
      write_with_gdal(lapply(rows, feature_of_row), workdir, "observations", target,
                      c("-update", "-f", "GPKG", "-nln", "observations", "-gt", "65536", "-nlt", "NONE"))
    }
    files <- "export.gpkg"
  } else if (format == "shp") {
    kinds <- vapply(features, function(f) f$geometry$type, "")
    for (family in c("points", "polygons")) {
      part <- features[if (family == "polygons") kinds %in% c("Polygon", "MultiPolygon") else !kinds %in% c("Polygon", "MultiPolygon")]
      if (!length(part)) next
      write_with_gdal(part, workdir, paste0("features_", family), file.path(workdir, paste0("features_", family, ".shp")),
                      c("-f", "ESRI Shapefile", "-nln", paste0("features_", family), "-lco", "ENCODING=UTF-8",
                        "-a_srs", "EPSG:4326"))
    }
    files <- sort(setdiff(list.files(workdir), "metadata.json"))
  }
  warnings <- if (wide && content == "all") list("column 'coarse_fragments' has 2 multi-value cell(s) returned as JSON text") else list()
  meta <- export_metadata(job_id, format, content, layout, files,
                          wide_columns = if (wide && content == "all") export_wide_columns() else NULL,
                          warnings = warnings, polygons = polygons)
  writeLines(to_json(meta, pretty = TRUE), file.path(workdir, "metadata.json"), useBytes = TRUE)
  zip <- file.path(dir, paste0(paste(format, content, layout, sep = "-"), ".zip"))
  unlink(zip)
  utils::zip(zip, file.path(workdir, c("metadata.json", files)), flags = "-j -q")
  zip
}

fake_export_api <- function(zips, .local_envir = parent.frame()) {
  testthat::skip_if_not_installed("webfakes")
  app <- webfakes::new_app()
  app$use(webfakes::mw_json())
  app$locals$zips <- zips
  app$locals$jobs <- list()
  app$locals$submitted <- list()
  app$locals$downloads <- 0L
  app$locals$datasets <- read_fixture("datasets.json")
  app$locals$job_fields <- names(unified_job_schema)
  env <- new.env(parent = baseenv())
  route <- function(handler) {
    environment(handler) <- env
    handler
  }
  send <- function(res, body) {
    res$send_json(body, auto_unbox = TRUE, null = "null", na = "null", digits = NA)
  }
  job_body <- function(id, status, progress = NULL, job = NULL, zip = NULL) {
    completed <- identical(status, "completed")
    list(
      job_id = id, status = status, summary_url = paste0("/api/v1/exports/", id),
      download_url = if (completed) paste0("/api/v1/exports/", id, "/download") else NULL,
      progress = progress,
      file_size_bytes = if (completed && !is.null(zip)) file.size(zip) else NULL,
      expires_at = if (is.null(job)) NULL else "2026-10-26T08:00:00+00:00",
      error_message = if (identical(status, "failed")) "export_failed: ogr2ogr failed" else NULL,
      observation_count = if (is.null(job)) NULL else 4656L,
      records = if (completed) list(features = 3L, features_by_dataset = list(wosis_points = 3L),
                                    observation_rows = 5L, observations = 17L) else NULL
    )
  }
  state_of <- function(job) {
    if (isTRUE(job$cancelled)) return(list("cancelled", 5))
    polls <- job$polls
    if (identical(job$scenario, "SLOW")) return(list("running", 45))
    if (identical(job$scenario, "FAIL") && polls >= 2) return(list("failed", 5))
    if (polls <= 1) return(list("running", 5))
    if (polls == 2) return(list("running", 45))
    list("completed", 100)
  }
  load_limit <- function(res, channel) {
    detail <- if (identical(channel, "sync")) {
      list(code = "load_limit_exceeded",
           message = paste0("The selection holds more than 1,000,000 observations, above the limit of synchronous ",
                            "requests (1,000,000): narrow the selection (bbox, country, datasets, variables, layer, ",
                            "profile_type) or request an export (POST /exports)."),
           channel = "sync", max_observations = 1000000L, observation_count = 1000001L,
           observation_count_exact = FALSE, exports_url = "/api/v1/exports")
    } else {
      list(code = "load_limit_exceeded",
           message = paste0("The selection holds more than 10,000,000 observations, above the limit of exports ",
                            "(10,000,000): split it into several exports (bbox, country, datasets, variables, ",
                            "layer, profile_type)."),
           channel = "export", max_observations = 10000000L, observation_count = 10000001L,
           observation_count_exact = FALSE)
    }
    res$set_status(422L)$send_json(list(detail = detail), auto_unbox = TRUE)
  }
  for (name in c("send", "job_body", "state_of", "load_limit")) assign(name, route(get(name)), envir = env)

  app$get("/api/v1/datasets", route(function(req, res) send(res, req$app$locals$datasets)))
  app$post("/api/v1/query/observations", route(function(req, res) load_limit(res, "sync")))
  app$post("/api/v1/query/features", route(function(req, res) load_limit(res, "sync")))
  app$get("/test/exports", route(function(req, res) send(res, list(bodies = req$app$locals$submitted))))
  app$post("/api/v1/exports", route(function(req, res) {
    b <- req$json
    req$app$locals$submitted <- c(req$app$locals$submitted, list(b))
    country <- unlist(b$country)
    if (identical(country, "WORLD")) return(load_limit(res, "export"))
    if (identical(b$format, "shp") && !identical(b$content, "features")) {
      return(res$set_status(422L)$send_json(list(
        detail = "format=shp is available for features-only exports (content=features); export observations as gpkg, geojson, csv or tsv"
      ), auto_unbox = TRUE))
    }
    n <- length(req$app$locals$jobs) + 1L
    id <- sprintf("exp_20261019_080000_%08x", n)
    key <- paste(b$format, b$content, if (is.null(b$layout)) "wide" else b$layout, sep = "-")
    req$app$locals$jobs[[id]] <- list(
      polls = 0L, scenario = if (is.null(country)) "OK" else country, key = key, cancelled = FALSE
    )
    out <- job_body(id, "queued")
    out$observation_count <- 4656L
    send(res, out)
  }))
  app$get("/api/v1/exports/:id", route(function(req, res) {
    id <- req$params$id
    job <- req$app$locals$jobs[[id]]
    if (is.null(job)) return(send(res, job_body(id, "unknown", 0)))
    job$polls <- job$polls + 1L
    req$app$locals$jobs[[id]] <- job
    state <- state_of(job)
    send(res, job_body(id, state[[1]], state[[2]], job, req$app$locals$zips[[job$key]]))
  }))
  app$get("/api/v1/exports/:id/download", route(function(req, res) {
    id <- req$params$id
    rid <- req$get_header("X-Request-ID")
    if (!is.null(rid)) res$set_header("X-Request-ID", rid)
    job <- req$app$locals$jobs[[id]]
    zip <- if (is.null(job)) NULL else req$app$locals$zips[[job$key]]
    if (is.null(job) || !identical(state_of(job)[[1]], "completed") || identical(job$scenario, "GONE") || is.null(zip)) {
      return(res$set_status(404L)$send_json(list(detail = "Export file not found"), auto_unbox = TRUE))
    }
    req$app$locals$downloads <- req$app$locals$downloads + 1L
    res$set_type("application/zip")
    res$set_header("Content-Disposition", paste0("attachment; filename=\"", id, ".zip\""))
    res$send(readBin(zip, "raw", file.size(zip)))
  }))
  app$post("/api/v1/jobs/:id/cancel", route(function(req, res) {
    id <- req$params$id
    job <- req$app$locals$jobs[[id]]
    if (is.null(job)) return(res$set_status(404L)$send_json(list(detail = "Job not found"), auto_unbox = TRUE))
    job$cancelled <- TRUE
    req$app$locals$jobs[[id]] <- job
    out <- stats::setNames(rep(list(NULL), length(req$app$locals$job_fields)), req$app$locals$job_fields)
    out[c("job_id", "job_type", "status", "progress_percent", "cancel_requested", "retry_count")] <-
      list(id, "export", "cancelled", 5, TRUE, 0L)
    send(res, out)
  }))
  webfakes::local_app_process(app, .local_envir = .local_envir)
}

# A signed-out session on the fake export API, the capabilities cached.
export_session <- function(server, verbose = 0, dir = NULL) {
  soil <- new_soil_session(soil_config(api_url = server$url("/api/v1"), timeout = 30, verbose = verbose, dir = dir))
  soil$state$capabilities <- read_fixture("capabilities.json")
  soil
}

submitted_exports <- function(server) {
  httr2::resp_body_json(httr2::req_perform(httr2::request(server$url("/test/exports"))))$bodies
}

# Messages of class soilhub_message emitted by `expr`, and its value.
collect_messages <- function(expr) {
  msgs <- character()
  value <- withCallingHandlers(expr, soilhub_message = function(m) {
    msgs <<- c(msgs, conditionMessage(m))
    invokeRestart("muffleMessage")
  })
  list(value = value, messages = msgs)
}
