#' @include features.R
NULL

# Exports (design 4.5, 6): `POST /exports` submits the whole canonical
# selection as an asynchronous job, `GET /exports/{job_id}` follows it,
# `GET /exports/{job_id}/download` streams its zip; the files are read back
# into the same typed tables as the synchronous reads, typed from the
# `metadata.json` of the zip. A read refused as too large for a synchronous
# request becomes an export (`too_large = "export"`,
# `soil_export_from_error()`).
#
# Zip layout (API `export_writer.py`): `metadata.json` plus, by format,
#   geojson   features.geojson, observations.geojson (FeatureCollections; the
#             observation features have a null geometry, nested values as JSON)
#   csv, tsv  features.<ext> (geometry as WKT in `geometry_wkt`),
#             observations.<ext>; objects and lists as JSON text, null as an
#             empty field, booleans as true/false
#   gpkg      export.gpkg: layer `features` (EPSG:4326) and attribute table
#             `observations`; objects and lists as JSON text
#   shp       content = "features" only: features_points.*,
#             features_polygons.* (field names cut to 10 characters)
# The tables join on `feature_id`; observations carry no geometry.

export_formats <- c("gpkg", "geojson", "csv", "tsv", "shp")
export_contents <- c("all", "features")
export_layouts <- c("wide", "long")
export_terminal_states <- c("completed", "failed", "cancelled")
export_min_poll <- 2
export_retention_days <- 7

export_job_schema <- list(
  job_id = "chr", status = "chr", summary_url = "chr", download_url = "chr",
  progress = "dbl", file_size_bytes = "dbl", expires_at = "time",
  error_message = "chr", observation_count = "dbl", records = "json"
)
export_job_fields <- names(export_job_schema)

# Column types of the nested values (JSON text in the flat formats).
wide_nested_types <- c("chr_list", "cell_markings", "value_flags", "retired_cells", "revised_markings")
long_nested_types <- c("chr_list", "object", "revised_markings")

# The truncated (10-character) Shapefile field names of the feature
# properties, back to the API names.
shapefile_names <- function() {
  full <- names(feature_property_types)
  stats::setNames(full, substr(full, 1L, 10L))
}

#' Export a selection
#'
#' Submits the selection as an export (`POST /exports`): the API writes
#' **every record** of the selection, up to `limits$max_export_observations`
#' observations (10,000,000; [soil_capabilities()]), into a zip of files,
#' then keeps it for 7 days. Exports are the way to large selections: the
#' synchronous reads ([soil_observations()], [soil_features()]) are refused
#' above `limits$max_sync_observations` (1,000,000). Rule of thumb: size the
#' selection with [soil_summary()]; below about 200,000 observations read
#' synchronously, above it export (a whole-WoSIS wide CSV export takes about
#' 9 minutes on the server, 88 MB zipped). Exports also give GeoPackage and
#' Shapefile files for GIS.
#'
#' The zip holds `metadata.json` (the request, the record counts, the
#' datasets with citation and licence, the variables, the typing of the wide
#' columns, the warnings and the revised rules) and two tables joined on
#' `feature_id`: `features` (one record per feature, with its geometry) and,
#' with `content = "all"`, `observations` in the `layout` asked (wide: one
#' row per horizon, every variable column on every row; long: one row per
#' observation), without geometry. Files by format: `"gpkg"` `export.gpkg`
#' (layers `features` and `observations`); `"geojson"` `features.geojson`,
#' `observations.geojson`; `"csv"`/`"tsv"` `features.csv` (geometry as WKT
#' in `geometry_wkt`), `observations.csv` (nested values as JSON text);
#' `"shp"` (features only) `features_points.*` and `features_polygons.*`.
#'
#' With `wait = TRUE` (the default) the function polls the export every
#' `poll` seconds until it ends, downloads the zip into `dir` and unzips it
#' into `<dir>/<job_id>/`; read the tables with [soil_export_read()]. With
#' `wait = FALSE` it returns at once: **keep the `job_id`**, the API keeps no
#' list of a user's exports, and resume later, also in another R session,
#' with `soil_export_wait(soil, job_id)` then [soil_export_download()].
#'
#' Rights: `soil:read`. Capabilities: `complete_exports` (checked at
#' [soil_connect()]); `revised_view`, `profile_type_filter`,
#' `component_selection` as for the reads.
#'
#' @inheritParams soil_observations
#' @param format File format: `"gpkg"` (GeoPackage, the default), `"geojson"`,
#'   `"csv"`, `"tsv"`, or `"shp"` (Shapefile: only with `content =
#'   "features"`). The formats are those of `soil_capabilities()$exports`. API
#'   field `format`.
#' @param content `"all"` (the features and their observations) or
#'   `"features"` (the features only). API field `content`.
#' @param layout Shape of the observations table: `"wide"` (one row per
#'   horizon) or `"long"` (one row per observation); not sent with `content =
#'   "features"`. API field `layout`.
#' @param wait Wait for the export to end (`TRUE`), or return at once with
#'   its `job_id` (`FALSE`). Client-side: not sent to the API.
#' @param timeout Seconds to wait for the export (default one hour); the
#'   export continues on the server after a timeout. Client-side: not sent to the API.
#' @param poll Seconds between two polls of the export (at least 2). Client-side: not sent to the
#'   API.
#' @param download Download the zip once the export is completed (needs
#'   `wait = TRUE`). Client-side: not sent to the API.
#' @param dir Directory of the downloads; `NULL` uses the option
#'   `soilhub.export_dir`, the environment variable `SOILHUB_EXPORT_DIR`, else
#'   `file.path(tempdir(), "soilhub-exports")`. Client-side: not sent to the API.
#' @param unzip Unzip the download into `<dir>/<job_id>/`. Client-side: not sent to the API.
#' @param progress Show the progress of the export (fraction written) and of
#'   the download: progress bars in an interactive session, else one message
#'   per change of status. Client-side: not sent to the API.
#' @return A `soil_export` (a list): `job_id`, `status` (`queued`,
#'   `running`, `completed`, `failed`, `cancelled`), `progress` (percent),
#'   `observation_count` (the observations of the selection, counted at
#'   submission), `records` (the records written per table, once completed),
#'   `file_size_bytes`, `expires_at` (POSIXct UTC), `error_message`,
#'   `format`, `content`, `layout`, `request` (the body sent), `selection`
#'   (the selection arguments), and after the download `zip` (path), `files`
#'   (names), `dir` (the unzipped directory) and `metadata` (the parsed
#'   `metadata.json`, read by [soil_metadata()], [soil_citations()],
#'   [soil_columns()], [soil_revised_rules()]).
#' @family exports
#' @seealso [soil_export_read()], [soil_summary()] to size a selection.
#' @examples
#' \dontrun{
#' soil <- soil_connect()
#' x <- soil_export(soil, datasets = "wosis_points", country = "BRA", format = "csv")
#' x
#' obs <- soil_export_read(x)
#' features <- soil_export_read(x, "features")
#' soil_citations(x)
#'
#' # submit now, collect later (keep the job id)
#' x <- soil_export(soil, datasets = "wosis_points", format = "gpkg", wait = FALSE)
#' x$job_id
#' x <- soil_export_wait(soil, x$job_id)
#' x <- soil_export_download(soil, x)
#' }
#' @export
soil_export <- function(soil = soil_session(), datasets = NULL, variables = NULL,
                        bbox = NULL, country = NULL, geometry = "any",
                        layer = "all", view = "raw", profile_type = NULL,
                        components = NULL, min_cumulative_percent = NULL,
                        format = c("gpkg", "geojson", "csv", "tsv", "shp"),
                        content = c("all", "features"),
                        layout = c("wide", "long"), wait = TRUE,
                        timeout = 3600, poll = 5, download = wait, dir = NULL,
                        unzip = TRUE, progress = interactive()) {
  check_session(soil)
  body <- soil_selection(
    soil, datasets = datasets, variables = variables, bbox = bbox,
    country = country, geometry = geometry, layer = layer, view = view,
    profile_type = profile_type, components = components,
    min_cumulative_percent = min_cumulative_percent
  )
  choices <- export_choices(soil)
  content <- check_export_option(content, export_contents, choices$content, "content")
  format <- check_export_option(format, export_formats, choices$all_formats, "format")
  allowed <- choices$formats[[content]] %||% choices$all_formats
  if (!format %in% allowed) {
    abort(soilhub_argument_error(
      sprintf(
        "`format = \"%s\"` is not available for exports with `content = \"%s\"`%s; use one of %s.",
        format, content,
        if (identical(format, "shp")) " (a Shapefile holds the features only: `content = \"features\"`)" else "",
        paste0("\"", allowed, "\"", collapse = ", ")
      ),
      "format"
    ))
  }
  layout <- check_export_option(layout, export_layouts, choices$layouts, "layout")
  wait <- check_flag(wait, "wait")
  download <- check_flag(download, "download")
  unzip <- check_flag(unzip, "unzip")
  progress <- check_flag(progress, "progress")
  timeout <- check_timeout(timeout)
  poll <- check_poll(poll)
  if (download && !wait) {
    abort(soilhub_argument_error(
      "`download = TRUE` needs `wait = TRUE`: an export can be downloaded once completed (soil_export_download()).",
      "download"
    ))
  }
  what <- "`soil_export()`"
  soil_require_right(soil, "soil:read", what)
  require_selection_capabilities(soil, body, what)

  selection <- attr(body, "selection")
  attr(body, "selection") <- NULL
  body$format <- format
  body$content <- content
  # `layout` applies to the observations only (the API refuses it with
  # content = "features").
  if (identical(content, "all")) body$layout <- layout

  response <- tryCatch(
    soil_request(soil, "POST", "/exports", body = body, right = "soil:read"),
    soilhub_load_limit_error = function(e) {
      e$selection <- selection
      abort(e)
    }
  )
  x <- new_soil_export(response, request = body, selection = selection, context = "POST /exports")
  if (!wait) {
    x <- tryCatch(fetch_export(soil, x), soilhub_error = function(e) x)
    soil_inform(soil, 1, sprintf(
      paste0(
        "soilhub: export %s %s (%s observations). Keep this id: resume with ",
        "soil_export_wait(soil, \"%s\"); the zip is kept until %s."
      ),
      x$job_id, x$status, format_number(x$observation_count), x$job_id,
      format_expiry(x$expires_at)
    ))
    return(x)
  }
  if (progress) {
    soilhub_message(sprintf(
      "soilhub: export %s submitted (%s observations, format %s).",
      x$job_id, format_number(x$observation_count), format
    ))
  }
  x <- wait_export(soil, x, timeout, poll, progress)
  if (download) x <- download_export(soil, x, dir, unzip, overwrite = FALSE, progress = progress)
  x
}

#' Follow, download and cancel an export
#'
#' `soil_export_status()` reads the state of an export once
#' (`GET /exports/{job_id}`). `soil_export_wait()` polls it every `poll`
#' seconds until it ends: a `completed` export is returned; a `failed` or
#' `cancelled` export, an unknown job id (the API answers `status =
#' "unknown"` for an id it does not know, e.g. an expired export) or an
#' export still running after `timeout` seconds is a `soilhub_job_error`
#' with the last state in `e$job` and `e$reason` (`failed`, `cancelled`,
#' `unknown_job`, `timeout`). `soil_export_download()` streams the zip of a
#' completed export to `<dir>/<job_id>.zip` (the server's name) and unzips
#' it into `<dir>/<job_id>/`; existing files are never replaced unless
#' `overwrite = TRUE`. An export is kept 7 days after submission
#' (`expires_at`): a later download is a `soilhub_not_found_error`.
#' `soil_export_cancel()` asks the API to stop an export that has not ended
#' (`POST /jobs/{job_id}/cancel`); the worker stops at its next heartbeat.
#'
#' The job id is the only handle on an export (the API lists no exports),
#' so each function accepts the `soil_export` returned by [soil_export()] or
#' the job id alone, also in a later R session.
#'
#' Rights: `soil:read`; `soil_export_cancel()` needs `soil:publish` (the
#' API controls every job through the unified job registry, which needs that
#' right).
#'
#' @param soil A session; the default session when omitted. Client-side: not sent to the API.
#' @param x A `soil_export` or a job id (`"exp_<stamp>_<hex>"`). API path parameter `{job_id}` of
#'   `GET /exports/{job_id}`, `GET /exports/{job_id}/download` and `POST /jobs/{job_id}/cancel`.
#' @param timeout Seconds to wait before giving up (default one hour). Client-side: not sent to the
#'   API.
#' @param poll Seconds between two polls (at least 2). Client-side: not sent to the API.
#' @param progress Show the progress (a bar in an interactive session, else
#'   one message per change). Client-side: not sent to the API.
#' @param dir Directory of the download; `NULL` uses the option
#'   `soilhub.export_dir`, the environment variable `SOILHUB_EXPORT_DIR`, else
#'   `file.path(tempdir(), "soilhub-exports")`. Client-side: not sent to the API.
#' @param unzip Unzip the download into `<dir>/<job_id>/`. Client-side: not sent to the API.
#' @param overwrite Replace an existing zip or directory of the same export. Client-side: not sent
#'   to the API.
#' @return `soil_export_status()`, `soil_export_wait()`,
#'   `soil_export_download()`: the updated `soil_export` (see
#'   [soil_export()]). `soil_export_cancel()`: the job after the request (a
#'   `soil_job`, see [soil_job()]).
#' @family exports
#' @examples
#' \dontrun{
#' x <- soil_export(soil, datasets = "wosis_points", wait = FALSE)
#' soil_export_status(soil, x)$status
#' x <- soil_export_wait(soil, x, timeout = 1800)
#' x <- soil_export_download(soil, x, dir = "exports")
#' x$files
#'
#' # in a later session, from the id alone
#' x <- soil_export_download(soil, "exp_20261019_101500_1a2b3c4d")
#' }
#' @export
soil_export_status <- function(soil = soil_session(), x) {
  check_session(soil)
  x <- as_soil_export(x)
  soil_require_right(soil, "soil:read", "`soil_export_status()`")
  fetch_export(soil, x)
}

#' @rdname soil_export_status
#' @export
soil_export_wait <- function(soil = soil_session(), x, timeout = 3600, poll = 5,
                             progress = interactive()) {
  check_session(soil)
  x <- as_soil_export(x)
  timeout <- check_timeout(timeout)
  poll <- check_poll(poll)
  progress <- check_flag(progress, "progress")
  soil_require_right(soil, "soil:read", "`soil_export_wait()`")
  wait_export(soil, x, timeout, poll, progress)
}

#' @rdname soil_export_status
#' @export
soil_export_download <- function(soil = soil_session(), x, dir = NULL, unzip = TRUE,
                                 overwrite = FALSE, progress = interactive()) {
  check_session(soil)
  x <- as_soil_export(x)
  unzip <- check_flag(unzip, "unzip")
  overwrite <- check_flag(overwrite, "overwrite")
  progress <- check_flag(progress, "progress")
  soil_require_right(soil, "soil:read", "`soil_export_download()`")
  download_export(soil, x, dir, unzip, overwrite, progress)
}

#' @rdname soil_export_status
#' @export
soil_export_cancel <- function(soil = soil_session(), x) {
  check_session(soil)
  x <- as_soil_export(x)
  what <- "`soil_export_cancel()` (the API cancels jobs through the unified job registry)"
  soil_require_right(soil, "soil:publish", what)
  body <- with_conflict_advice(
    soil_request(
      soil, "POST", paste0("/jobs/", url_segment(x$job_id), "/cancel"),
      right = "soil:publish"
    ),
    "An export that has ended cannot be cancelled: read it with soil_export_status()."
  )
  job <- new_soil_job(body)
  if (!isTRUE(job$cancel_requested) && job$status %in% export_terminal_states) {
    soil_inform(soil, 1, sprintf(
      "soilhub: export %s had already ended (%s); nothing was cancelled.", x$job_id, job$status
    ))
  }
  job
}

#' Export the selection of a refused read
#'
#' A synchronous read above the limit (`limits$max_sync_observations`)
#' raises a `soilhub_load_limit_error` that carries its selection. This
#' submits the same selection as an export: the observations in the layout
#' of the refused read for [soil_observations()], the features
#' (`content = "features"`) for [soil_features()]. It is the manual form of
#' `too_large = "export"`, for an error caught earlier.
#'
#' Rights: `soil:read`.
#'
#' @param soil A session; the default session when omitted. Client-side: not sent to the API.
#' @param error The `soilhub_load_limit_error` of a read (`channel =
#'   "sync"`). Client-side: not sent to the API.
#' @param format The export format (see [soil_export()]). API field `format`.
#' @param ... Other arguments of [soil_export()] (`content`, `layout`,
#'   `wait`, `timeout`, `dir`, ...; a selection argument given here replaces
#'   the error's). Each is sent, or not, as described for [soil_export()] (API fields of
#'   `POST /exports`, or client-side).
#' @return A `soil_export` (see [soil_export()]).
#' @family exports
#' @examples
#' \dontrun{
#' e <- tryCatch(soil_observations(soil, datasets = "wosis_points"),
#'               soilhub_load_limit_error = function(e) e)
#' x <- soil_export_from_error(soil, e, format = "csv")
#' obs <- soil_export_read(x)
#' }
#' @export
soil_export_from_error <- function(soil = soil_session(), error, format = "gpkg", ...) {
  check_session(soil)
  if (!inherits(error, "soilhub_load_limit_error")) {
    abort(soilhub_argument_error(
      "`error` must be the soilhub_load_limit_error of a refused read (soil_observations(), soil_features()).",
      "error"
    ))
  }
  if (identical(error$channel, "export")) {
    abort(soilhub_argument_error(
      paste0(
        "The selection is above the limit of exports too: split it into several exports ",
        "(bbox, country, datasets, variables, layer, profile_type)."
      ),
      "error"
    ))
  }
  selection <- error$selection %||% request_selection(error$request) %||% list()
  selection <- lapply(selection, function(value) if (inherits(value, "AsIs")) unclass(value) else value)
  args <- list(...)
  features <- identical(error$endpoint, "/query/features") || identical(selection$content, "features")
  selection$content <- NULL
  defaults <- list(content = if (features) "features" else "all")
  if (!features && is_string(error$request$layout)) defaults$layout <- error$request$layout
  call_args <- c(
    list(soil = soil),
    selection[setdiff(names(selection), names(args))],
    list(format = format),
    defaults[setdiff(names(defaults), names(args))],
    args
  )
  do.call(soil_export, call_args)
}

#' Read the files of an export
#'
#' Reads the tables of an export back into R, typed as the synchronous reads
#' type them: `metadata.json` is read first and drives the typing. The wide
#' observations are typed as [soil_observations()] types them (fixed columns,
#' markings and list columns; a variable column is numeric when
#' `wide_columns` says so, `<key>_n` integer, a multi-value WoSIS cell gives
#' the mean of its values in `<key>` and the values in `<key>_values`); the
#' long observations as the long layout; the features as [soil_features()].
#' Values written as JSON text by the flat formats (CSV, TSV, GeoPackage:
#' `value_flags`, `cell_markings`, `profile_markings`, `components`, ...) are
#' parsed back to list columns. The result is a `soil_table` whose metadata
#' has the shape of a synchronous read (with `via_export`, the job id, and
#' `export`: format, content, layout, records, files, the variables of the
#' selection), so [soil_citations()], [soil_revised_rules()] and
#' [soil_columns()] work on it.
#'
#' Formats and packages: CSV, TSV and GeoJSON need no package; GeoPackage
#' and Shapefile need `sf`. The features are an `sf` object (EPSG:4326) when
#' `sf` is installed; without it the features of a CSV/TSV export keep their
#' WKT in `geometry_wkt` and those of a GeoJSON export their GeoJSON in
#' `geometry_text`. Shapefile fields are cut to 10 characters and 254
#' characters of text by the format: the known names are restored, the
#' nested values stay text.
#'
#' Empty fields of CSV and TSV are `NA` (the API writes null as an empty
#' field). In the long layout `value_raw` of a CSV/TSV export is the JSON
#' value of the cell text (a number when the text is a number).
#'
#' No network, no right needed.
#'
#' @param x A `soil_export` (downloaded), the path of an export zip, or the
#'   directory it was unzipped into. Client-side: not sent to the API.
#' @param what `"observations"` (the default; for an export of `content =
#'   "features"` the features), `"features"`, `"metadata"` (the parsed
#'   `metadata.json`) or `"all"` (a list `features`, `observations`,
#'   `metadata`). Client-side: not sent to the API.
#' @return A `soil_table` (`soil_layout` `"wide"`, `"long"` or
#'   `"features"`; an `sf` object for the features when `sf` is installed),
#'   the metadata list, or a list of them.
#' @family exports
#' @examples
#' \dontrun{
#' x <- soil_export(soil, datasets = "wosis_points", country = "KEN", format = "csv")
#' obs <- soil_export_read(x)
#' soil_columns(obs)
#' f <- soil_export_read(x, "features")
#' soil_export_read("exports/exp_20261019_101500_1a2b3c4d.zip", "metadata")$records
#' }
#' @export
soil_export_read <- function(x, what = c("observations", "features", "metadata", "all")) {
  default_what <- identical(what, c("observations", "features", "metadata", "all"))
  what <- check_option(what, c("observations", "features", "metadata", "all"), "what")
  source <- export_source(x)
  meta <- source$metadata
  if (identical(what, "metadata")) return(meta)
  content <- scalar_chr(meta$content %||% if (has_observations(source)) "all" else "features")
  if (default_what && identical(content, "features")) what <- "features"
  if (identical(what, "observations") && identical(content, "features")) {
    abort(soilhub_argument_error(
      "This export holds the features only (`content = \"features\"`): read them with `what = \"features\"`.",
      "what"
    ))
  }
  with_geometry <- if (soil_has_package("sf")) "sf" else "text"
  switch(what,
    observations = read_export_observations(source),
    features = read_export_features(source, with_geometry),
    all = list(
      features = read_export_features(source, with_geometry),
      observations = if (identical(content, "features")) NULL else read_export_observations(source),
      metadata = meta
    )
  )
}

#' @export
print.soil_export <- function(x, ...) {
  cat("<soil_export> ", x$job_id, "\n", sep = "")
  status <- x$status %||% NA_character_
  if (!is.null(x$progress) && !is.na(x$progress)) {
    status <- sprintf("%s (%s%%)", status, format(round(x$progress)))
  }
  cat("  Status:   ", status, "\n", sep = "")
  request <- x$request %||% list()
  parts <- c(
    if (!is.null(x$format)) paste("format", x$format),
    if (!is.null(x$content)) paste("content", x$content),
    if (identical(x$content, "all") && !is.null(x$layout)) paste("layout", x$layout)
  )
  if (length(parts)) cat("  Export:   ", paste(parts, collapse = ", "), "\n", sep = "")
  if (length(x$selection)) {
    shown <- vapply(names(x$selection), function(name) {
      paste(name, paste(unlist(x$selection[[name]]), collapse = ", "))
    }, character(1))
    cat("  Selection:", paste0(" ", paste(shown, collapse = "; ")), "\n", sep = "")
  } else if (length(request$datasets)) {
    cat("  Selection: datasets ", paste(unlist(request$datasets), collapse = ", "), "\n", sep = "")
  }
  if (!is.null(x$observation_count) && !is.na(x$observation_count)) {
    cat("  Selected: ", format_number(x$observation_count), " observations\n", sep = "")
  }
  records <- x$records
  if (is.list(records) && length(records)) {
    counts <- c(
      if (!is.null(records$features)) paste(format_number(records$features), "features"),
      if (!is.null(records$observation_rows)) paste(format_number(records$observation_rows), "observation rows"),
      if (!is.null(records$observations)) paste(format_number(records$observations), "observations")
    )
    if (length(counts)) cat("  Written:  ", paste(counts, collapse = ", "), "\n", sep = "")
  }
  if (!is.null(x$expires_at) && !is.na(x$expires_at)) {
    cat("  Expires:  ", format_expiry(x$expires_at), "\n", sep = "")
  }
  if (!is.null(x$error_message) && !is.na(x$error_message)) {
    cat("  Error:    ", x$error_message, "\n", sep = "")
  }
  if (!is.null(x$zip)) cat("  Zip:      ", x$zip, "\n", sep = "")
  if (!is.null(x$dir)) cat("  Dir:      ", x$dir, "\n", sep = "")
  if (length(x$files)) cat("  Files:    ", paste(x$files, collapse = ", "), "\n", sep = "")
  if (!is.null(x$zip) || !is.null(x$dir)) {
    cat("  Read with soil_export_read(x); cite with soil_citations(x).\n")
  } else if (!(status %in% c("failed", "cancelled"))) {
    cat(sprintf(
      "  Keep the job id: resume with soil_export_wait(soil, \"%s\") and soil_export_download().\n",
      x$job_id
    ))
  }
  invisible(x)
}

# ---------------------------------------------------------------------------
# The export object and its lifecycle.

new_soil_export <- function(job, request = NULL, selection = NULL, context = NULL) {
  x <- structure(
    list(
      job_id = NA_character_, status = NA_character_, progress = NA_real_,
      observation_count = NA_real_, records = NULL, file_size_bytes = NA_real_,
      expires_at = as_utc(NA_real_), download_url = NA_character_,
      error_message = NA_character_,
      format = scalar_chr(request$format %||% NA_character_),
      content = scalar_chr(request$content %||% NA_character_),
      layout = scalar_chr(request$layout %||% NA_character_),
      request = request, selection = selection,
      zip = NULL, files = NULL, dir = NULL, metadata = NULL
    ),
    class = "soil_export"
  )
  update_export(x, job, context)
}

# The fields of an ExportJobResponse into the object; a field the response
# leaves null keeps its value (the submission response has no `expires_at`,
# an unknown job no `observation_count`). `context` names the response for
# the contract warnings (NULL: a job id given by the user).
update_export <- function(x, job, context = "GET /exports/{job_id}") {
  typed <- typed_object(job, export_job_schema, context)
  for (name in export_job_fields) {
    value <- typed[[name]]
    absent <- is.null(value) || (length(value) == 1L && !is.list(value) && is.na(value))
    if (absent && !name %in% c("status", "progress")) next
    if (is.null(value)) {
      x[name] <- list(NULL)
    } else {
      x[[name]] <- value
    }
  }
  x
}

as_soil_export <- function(x) {
  if (inherits(x, "soil_export")) return(x)
  if (is_string(x)) return(new_soil_export(list(job_id = x), context = NULL))
  abort(soilhub_argument_error(
    "`x` must be a soil_export or the job id of an export (a string, as returned at submission).",
    "x"
  ))
}

check_export_option <- function(value, all, choices, argument) {
  if (identical(value, all)) value <- all[[1]]
  check_choice(value, choices, argument)
}

check_poll <- function(poll) {
  poll <- check_timeout(poll, "poll")
  if (poll < export_min_poll) {
    abort(soilhub_argument_error(
      sprintf("`poll` must be at least %s seconds, not %s.", export_min_poll, format(poll)),
      "poll"
    ))
  }
  poll
}

# The accepted values: the server's (`/capabilities` `exports`) when listed,
# so that new server values are not refused by the client.
export_choices <- function(soil) {
  out <- list(
    content = export_contents, layouts = export_layouts, all_formats = export_formats,
    formats = list(all = setdiff(export_formats, "shp"), features = export_formats)
  )
  capabilities <- tryCatch(session_cached(soil, "capabilities"), error = function(e) NULL)
  exports <- if (is.list(capabilities)) capabilities$exports else NULL
  if (!is.list(exports)) return(out)
  server_values <- function(v) {
    v <- unlist(v, use.names = FALSE)
    if (is.character(v) && length(v)) v else NULL
  }
  out$content <- server_values(exports$content) %||% out$content
  out$layouts <- server_values(exports$layouts) %||% out$layouts
  if (is.list(exports$formats) && length(exports$formats)) {
    formats <- lapply(exports$formats, server_values)
    formats <- formats[!vapply(formats, is.null, logical(1))]
    if (length(formats)) {
      out$formats <- formats
      out$all_formats <- unique(c(export_formats[export_formats %in% unlist(formats)], unlist(formats)))
    }
  }
  out
}

fetch_export <- function(soil, x) {
  body <- soil_request(
    soil, "GET", paste0("/exports/", url_segment(x$job_id)), right = "soil:read"
  )
  x <- update_export(x, body)
  if (identical(x$status, "unknown")) {
    abort(soilhub_job_error(
      sprintf(
        paste0(
          "Export %s is unknown to the API: the id is wrong, or the export expired and was removed ",
          "(exports are kept %d days). The API lists no exports: the id returned at submission is ",
          "the only handle."
        ),
        x$job_id, export_retention_days
      ),
      job = x, job_id = x$job_id, reason = "unknown_job"
    ))
  }
  x
}

# The polling loop: deadline on `soil_now()`, pauses through `http_sleep()`
# (both replaceable by tests).
wait_export <- function(soil, x, timeout, poll, progress) {
  deadline <- soil_now() + timeout
  bar <- NULL
  on.exit(if (!is.null(bar)) close(bar), add = TRUE)
  shown <- NULL
  repeat {
    x <- fetch_export(soil, x)
    if (progress && interactive()) {
      if (is.null(bar)) bar <- utils::txtProgressBar(min = 0, max = 100, style = 3)
      utils::setTxtProgressBar(bar, min(100, max(0, x$progress %||% 0, na.rm = TRUE)))
    } else if (progress) {
      line <- export_status_line(x)
      if (!identical(line, shown)) soilhub_message(line)
      shown <- line
    }
    if (x$status %in% export_terminal_states) break
    remaining <- as.numeric(difftime(deadline, soil_now(), units = "secs"))
    if (remaining <= 0) {
      abort(soilhub_job_error(
        sprintf(
          paste0(
            "Export %s is still %s after %s s: it continues on the server. ",
            "Wait again with soil_export_wait(soil, \"%s\") or cancel it with soil_export_cancel()."
          ),
          x$job_id, x$status, format(timeout), x$job_id
        ),
        job = x, job_id = x$job_id, reason = "timeout"
      ))
    }
    http_sleep(min(poll, remaining))
  }
  if (identical(x$status, "completed")) {
    if (progress && !interactive()) {
      records <- x$records %||% list()
      soilhub_message(sprintf(
        "soilhub: export %s written: %s features%s.",
        x$job_id, format_number(records$features),
        if (is.null(records$observation_rows)) "" else
          sprintf(", %s observation rows", format_number(records$observation_rows))
      ))
    }
    return(x)
  }
  why <- if (!is.null(x$error_message) && !is.na(x$error_message)) paste0(": ", x$error_message) else ""
  abort(soilhub_job_error(
    sprintf("Export %s ended %s%s.", x$job_id, x$status, why),
    job = x, job_id = x$job_id, reason = x$status
  ))
}

export_status_line <- function(x) {
  progress <- x$progress
  sprintf(
    "soilhub: export %s %s%s", x$job_id, x$status,
    if (is.null(progress) || is.na(progress)) "" else sprintf(" (%s%%)", format(round(progress)))
  )
}

format_number <- function(x) {
  if (is.null(x) || length(x) != 1L || is.na(x)) return("?")
  formatC(as.numeric(x), format = "d", big.mark = ",")
}

format_expiry <- function(expires_at) {
  if (is.null(expires_at) || length(expires_at) != 1L || is.na(expires_at)) {
    return(sprintf("%d days after submission", export_retention_days))
  }
  format(expires_at, "%Y-%m-%d %H:%M:%S UTC", tz = "UTC")
}

export_dir <- function(soil, dir) {
  value <- config_value(
    dir, "soilhub.export_dir", "SOILHUB_EXPORT_DIR",
    soil$dir %||% file.path(tempdir(), "soilhub-exports")
  )$value
  if (!is_string(value)) {
    abort(soilhub_argument_error("`dir` must be a directory path.", "dir"))
  }
  if (!dir.exists(value)) dir.create(value, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(value)) {
    abort(soilhub_argument_error(sprintf("The directory %s cannot be created.", value), "dir"))
  }
  value
}

download_export <- function(soil, x, dir, unzip, overwrite, progress) {
  if (!identical(x$status, "completed")) x <- fetch_export(soil, x)
  if (!identical(x$status, "completed")) {
    abort(soilhub_job_error(
      sprintf(
        "Export %s is %s: it can be downloaded once completed (soil_export_wait(soil, \"%s\")).",
        x$job_id, x$status, x$job_id
      ),
      job = x, job_id = x$job_id, reason = "not_completed"
    ))
  }
  dir <- export_dir(soil, dir)
  zip <- file.path(dir, paste0(x$job_id, ".zip"))
  exdir <- file.path(dir, x$job_id)
  if (file.exists(zip) && !overwrite) {
    abort(soilhub_argument_error(
      sprintf(
        "The file %s exists: pass `overwrite = TRUE` to download it again, or read it with soil_export_read(\"%s\").",
        zip, zip
      ),
      "overwrite"
    ))
  }
  if (unzip && dir.exists(exdir) && length(list.files(exdir, all.files = TRUE, no.. = TRUE)) && !overwrite) {
    abort(soilhub_argument_error(
      sprintf("The directory %s exists: pass `overwrite = TRUE` to replace it.", exdir),
      "overwrite"
    ))
  }
  path <- paste0("/exports/", url_segment(x$job_id), "/download")
  tryCatch(
    soil_download(soil, path, zip, progress = progress, right = "soil:read"),
    soilhub_not_found_error = function(e) {
      expires <- x$expires_at
      if (!is.null(expires) && !is.na(expires) && soil_now() > expires) {
        e$message <- paste0(
          conditionMessage(e),
          sprintf(
            "\nThe export expired on %s (exports are kept %d days): submit it again with soil_export().",
            format_expiry(expires), export_retention_days
          )
        )
        e$reason <- "expired"
      }
      abort(e)
    }
  )
  x$zip <- normalizePath(zip, winslash = "/")
  x$metadata <- read_zip_metadata(zip)
  if (unzip) {
    if (dir.exists(exdir)) unlink(exdir, recursive = TRUE)
    files <- utils::unzip(zip, exdir = exdir, junkpaths = TRUE)
    x$dir <- normalizePath(exdir, winslash = "/")
    x$files <- sort(basename(files))
  } else {
    x$files <- sort(basename(utils::unzip(zip, list = TRUE)$Name))
  }
  if (progress && !interactive()) {
    soilhub_message(sprintf(
      "soilhub: export %s downloaded to %s (%s bytes).",
      x$job_id, if (unzip) x$dir else x$zip, format_number(file.size(zip))
    ))
  }
  x
}

#' Stream a response to a file
#'
#' As `soil_request()` (headers, authentication and one renewal after a 401,
#' retries, error mapping), for a binary response written to `dest`: no
#' total timeout, the body goes to `<dest>.part`, renamed when complete.
#' @keywords internal
#' @noRd
soil_download <- function(soil, path, dest, progress = FALSE, right = NULL) {
  request_id <- new_request_id()
  context <- list(method = "GET", endpoint = path, request_id = request_id, timeout = Inf,
                  right = if (is.null(right)) NULL else normalise_right(right))
  part <- paste0(dest, ".part")
  on.exit(unlink(part), add = TRUE)
  bar <- new.env(parent = emptyenv())
  on.exit(if (!is.null(bar$bar)) close(bar$bar), add = TRUE)
  renewed <- FALSE
  repeat {
    token <- auth_token(soil, renew = renewed)
    req <- build_request(soil, "GET", path, NULL, NULL, Inf, token, request_id)
    req <- httr2::req_headers(req, Accept = "application/zip, application/json")
    if (progress && interactive()) {
      req <- httr2::req_options(req, noprogress = FALSE, xferinfofunction = download_progress(bar))
    }
    outcome <- perform_with_retries(soil, req, context, max_tries = http_max_tries, path = part)
    if (!is.null(outcome$response) &&
        httr2::resp_status(outcome$response) == 401L &&
        !renewed && is.function(soil$auth) && !is.null(token)) {
      renewed <- TRUE
      soil_inform(soil, 1, "soilhub: access token refused (HTTP 401), renewing the session.")
      next
    }
    break
  }
  record_exchange("GET", path, NULL, NULL, outcome$response, download = part)
  if (is.null(outcome$response)) abort(transport_error(outcome, soil, context))
  response <- outcome$response
  context$request_id <- httr2::resp_header(response, "x-request-id") %||% context$request_id
  status <- httr2::resp_status(response)
  if (status < 200L || status >= 300L) {
    abort(response_error(soil, response, context, NULL, token, outcome$attempts))
  }
  if (!file.rename(part, dest)) {
    file.copy(part, dest, overwrite = TRUE)
  }
  invisible(dest)
}

# A curl transfer callback drawing a byte progress bar (txtProgressBar).
download_progress <- function(state) {
  function(down, up) {
    total <- down[[1]]
    now <- down[[2]]
    if (total > 0) {
      if (is.null(state$bar)) state$bar <- utils::txtProgressBar(min = 0, max = total, style = 3)
      utils::setTxtProgressBar(state$bar, min(now, total))
    }
    TRUE
  }
}

read_zip_metadata <- function(zip) {
  exdir <- tempfile("soilhub-metadata-")
  on.exit(unlink(exdir, recursive = TRUE), add = TRUE)
  listed <- utils::unzip(zip, list = TRUE)$Name
  if (!"metadata.json" %in% basename(listed)) return(NULL)
  entry <- listed[basename(listed) == "metadata.json"][[1]]
  utils::unzip(zip, files = entry, exdir = exdir, junkpaths = TRUE)
  jsonlite::fromJSON(file.path(exdir, "metadata.json"), simplifyVector = FALSE)
}

# ---------------------------------------------------------------------------
# Reading the files.

# Where the files of `x` are: a directory with metadata.json (a zip is
# unzipped into a temporary directory).
export_source <- function(x) {
  path <- NULL
  if (inherits(x, "soil_export")) {
    if (!is.null(x$dir) && dir.exists(x$dir)) {
      path <- x$dir
    } else if (!is.null(x$zip) && file.exists(x$zip)) {
      path <- x$zip
    } else {
      abort(soilhub_argument_error(
        sprintf(
          "Export %s has not been downloaded: soil_export_download(soil, x) first.",
          x$job_id %||% ""
        ),
        "x"
      ))
    }
  } else if (is_string(x)) {
    if (!file.exists(x)) {
      abort(soilhub_argument_error(sprintf("No file or directory %s.", x), "x"))
    }
    path <- x
  } else {
    abort(soilhub_argument_error(
      "`x` must be a soil_export, the path of an export zip or of its unzipped directory.",
      "x"
    ))
  }
  dir <- path
  if (!dir.exists(path)) {
    dir <- tempfile("soilhub-export-")
    files <- tryCatch(utils::unzip(path, exdir = dir, junkpaths = TRUE), error = function(e) character(), warning = function(w) character())
    if (!length(files)) {
      abort(soilhub_argument_error(sprintf("%s is not a zip file of an export.", path), "x"))
    }
  }
  metadata_file <- file.path(dir, "metadata.json")
  if (!file.exists(metadata_file)) {
    abort(soilhub_argument_error(
      sprintf("%s holds no metadata.json: it is not an export of the Global Soil Data Hub.", path),
      "x"
    ))
  }
  metadata <- jsonlite::fromJSON(metadata_file, simplifyVector = FALSE)
  files <- list.files(dir)
  format <- scalar_chr(metadata$format)
  if (is.na(format)) format <- infer_export_format(files)
  list(dir = dir, metadata = metadata, files = files, format = format)
}

infer_export_format <- function(files) {
  if ("export.gpkg" %in% files) return("gpkg")
  if (any(grepl("^features_(points|polygons)\\.shp$", files))) return("shp")
  for (format in c("geojson", "csv", "tsv")) {
    if (paste0("features.", format) %in% files) return(format)
  }
  NA_character_
}

has_observations <- function(source) {
  any(startsWith(source$files, "observations.")) ||
    (identical(source$format, "gpkg") && "observations" %in% gpkg_layers(file.path(source$dir, "export.gpkg")))
}

gpkg_layers <- function(path) {
  if (!file.exists(path) || !soil_has_package("sf")) return(character())
  tryCatch(sf::st_layers(path)$name, error = function(e) character())
}

require_sf_format <- function(format) {
  if (soil_has_package("sf")) return(invisible(TRUE))
  abort(soilhub_dependency_error("sf", sprintf(
    paste0(
      "Reading an export in format \"%s\" needs the package 'sf', which is not installed: ",
      "install.packages(\"sf\"), or export as \"csv\", \"tsv\" or \"geojson\" (no package needed)."
    ),
    format
  )))
}

# A CSV or TSV table of an export as text columns (`NA` for an empty field,
# the API's null); NULL for an empty file.
read_delimited <- function(path, sep) {
  if (!file.exists(path) || file.size(path) == 0L) return(NULL)
  utils::read.table(
    path, header = TRUE, sep = sep, quote = "\"", colClasses = "character",
    na.strings = "", check.names = FALSE, comment.char = "", encoding = "UTF-8",
    stringsAsFactors = FALSE, strip.white = FALSE, blank.lines.skip = TRUE
  )
}

# A layer of the GeoPackage (NULL when absent); `geometry = FALSE` drops it.
read_gpkg_layer <- function(path, layer) {
  if (!layer %in% gpkg_layers(path)) return(NULL)
  suppressWarnings(sf::st_read(path, layer = layer, quiet = TRUE, stringsAsFactors = FALSE))
}

# The items of a GeoJSON FeatureCollection file (NULL when absent).
read_geojson_features <- function(path) {
  if (!file.exists(path)) return(NULL)
  parsed <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  lapply(parsed$features %||% list(), function(item) if (is.list(item)) item else list())
}

# Items as the `soilhub_pages` the typing functions take.
export_pages <- function(items, variables = NULL) {
  structure(
    list(
      items = items, metadata = list(),
      page_metadata = list(list(variables = variables)),
      extras = list()
    ),
    class = "soilhub_pages"
  )
}

# `lookup` (export_feature_geometries()): the geometries of the features,
# set on the long rows of a GeoJSON export (`with_geometry` "text" or "sf").
read_export_observations <- function(source, with_geometry = "none", lookup = NULL) {
  meta <- source$metadata
  layout <- scalar_chr(meta$layout %||% "wide")
  if (is.na(layout)) layout <- "wide"
  wide <- identical(layout, "wide")
  variables <- if (wide) merge_wide_variables(list(list(variables = meta$wide_columns))) else NULL
  format <- source$format
  frame <- switch(format,
    geojson = {
      items <- lapply(read_geojson_features(file.path(source$dir, "observations.geojson")) %||% list(),
                      function(item) if (is.list(item$properties)) item$properties else list())
      if (!wide && !identical(with_geometry, "none") && !is.null(lookup)) {
        items <- lapply(items, function(row) {
          id <- scalar_chr(row$feature_id)
          known <- !is.na(id) && !is.null(lookup$geometries[[id]])
          row["geometry"] <- list(if (known) lookup$geometries[[id]] else NULL)
          if (known && is.null(row$geometry_kind)) row["geometry_kind"] <- list(unname(lookup$kinds[id]))
          row
        })
      }
      pages <- export_pages(items, meta$wide_columns)
      if (wide) wide_frame(pages, variables, "none") else long_layout_frame(pages, with_geometry)
    },
    csv = , tsv = {
      raw <- read_delimited(
        file.path(source$dir, paste0("observations.", format)),
        if (identical(format, "tsv")) "\t" else ","
      )
      flat_observations(raw, layout, variables)
    },
    gpkg = {
      require_sf_format(format)
      layer <- read_gpkg_layer(file.path(source$dir, "export.gpkg"), "observations")
      if (inherits(layer, "sf")) layer <- sf::st_drop_geometry(layer)
      flat_observations(if (is.null(layer)) NULL else as.data.frame(layer), layout, variables)
    },
    abort(soilhub_argument_error(
      sprintf("This export (format \"%s\") holds no observations table.", format),
      "x"
    ))
  )
  if (identical(with_geometry, "sf") && !wide && !is.null(frame$geometry)) {
    frame <- frame_as_sf(frame, wkt_sfc(frame$geometry))
  }
  metadata <- export_table_metadata(meta, layout, variables)
  new_soil_table(frame, metadata, layout)
}

read_export_features <- function(source, with_geometry) {
  meta <- source$metadata
  format <- source$format
  sf <- identical(with_geometry, "sf")
  frame <- switch(format,
    geojson = {
      items <- read_geojson_features(file.path(source$dir, "features.geojson")) %||% list()
      typed <- features_frame(export_pages(items), with_geometry)
      if (sf) frame_as_sf(typed, wkt_sfc(typed$geometry)) else typed
    },
    csv = , tsv = {
      raw <- read_delimited(
        file.path(source$dir, paste0("features.", format)),
        if (identical(format, "tsv")) "\t" else ","
      )
      wkt <- if (is.null(raw)) character() else raw$geometry_wkt %||% rep(NA_character_, nrow(raw))
      if (!is.null(raw)) raw$geometry_wkt <- NULL
      typed <- flat_features(raw)
      warn_missing_geometry(
        is.na(wkt), typed$feature_id %||% character(),
        if (sf) missing_geometry_text("sf") else "their geometry_wkt is NA"
      )
      if (sf) {
        frame_as_sf(typed, wkt_sfc(wkt))
      } else {
        typed$geometry_wkt <- as.character(wkt)
        typed
      }
    },
    gpkg = {
      require_sf_format(format)
      layer <- read_gpkg_layer(file.path(source$dir, "export.gpkg"), "features")
      sf_layer_frame(layer)
    },
    shp = {
      require_sf_format(format)
      parts <- lapply(c("points", "polygons"), function(family) {
        path <- file.path(source$dir, paste0("features_", family, ".shp"))
        if (!file.exists(path)) return(NULL)
        layer <- suppressWarnings(sf::st_read(path, quiet = TRUE, stringsAsFactors = FALSE))
        names(layer)[names(layer) != attr(layer, "sf_column")] <- restore_shapefile_names(
          names(layer)[names(layer) != attr(layer, "sf_column")]
        )
        layer
      })
      parts <- parts[!vapply(parts, is.null, logical(1))]
      sf_layer_frame(bind_sf_layers(parts), nested = FALSE)
    },
    abort(soilhub_argument_error(sprintf("Unknown export format \"%s\".", format), "x"))
  )
  metadata <- export_table_metadata(meta, "features", NULL)
  metadata$multi_value_rule <- NULL
  records <- meta$records %||% list()
  datasets <- as.character(unlist(meta$request$datasets))
  counts <- records$features_by_dataset
  metadata["feature_count"] <- list(nrow(frame))
  metadata["feature_count_by_dataset"] <- list(if (length(datasets) > 1L && is.list(counts)) counts else NULL)
  kinds <- unique(ifelse(toupper(frame$geometry_kind %||% character()) %in% polygon_kinds, "polygon", "point"))
  metadata["mixed_geometry"] <- list(length(kinds) > 1L)
  new_soil_table(frame, metadata, "features")
}

# An sf layer (GeoPackage, Shapefile) as the features of a read: the
# attributes typed, the geometry column named `geometry` (last).
sf_layer_frame <- function(layer, nested = TRUE) {
  if (is.null(layer) || !nrow(layer)) {
    empty <- flat_features(NULL)
    return(frame_as_sf(empty, sf::st_sfc(crs = geometry_crs)))
  }
  geometry <- sf::st_geometry(layer)
  if (is.na(sf::st_crs(geometry))) geometry <- sf::st_set_crs(geometry, geometry_crs)
  raw <- as.data.frame(sf::st_drop_geometry(layer))
  typed <- flat_features(raw, nested = nested)
  frame_as_sf(typed, geometry)
}

restore_shapefile_names <- function(names) {
  known <- shapefile_names()
  ifelse(names %in% names(known), unname(known[names]), names)
}

# Points and polygons of a Shapefile export as one sf (union of the columns).
bind_sf_layers <- function(parts) {
  if (!length(parts)) return(NULL)
  if (length(parts) == 1L) return(parts[[1]])
  columns <- unique(unlist(lapply(parts, function(p) setdiff(names(p), attr(p, "sf_column")))))
  frames <- lapply(parts, function(p) {
    attrs <- as.data.frame(sf::st_drop_geometry(p))
    for (name in setdiff(columns, names(attrs))) attrs[[name]] <- rep(NA, nrow(attrs))
    attrs[columns]
  })
  geometry <- do.call(c, lapply(parts, sf::st_geometry))
  sf::st_sf(do.call(rbind, frames), geometry = geometry)
}

# The metadata of a table read from an export, in the shape of a
# synchronous read (design 5.4), with `via_export` and `export`.
export_table_metadata <- function(meta, layout, variables) {
  request <- meta$request %||% list()
  selection <- lapply(request_selection(request) %||% list(), function(value) {
    if (is.list(value)) unlist(value) else value
  })
  records <- meta$records %||% list()
  datasets <- meta$datasets
  datasets <- if (is.list(datasets) && length(datasets) && is.list(datasets[[1]])) {
    datasets_frame(datasets, context = NULL)
  } else {
    as.character(unlist(request$datasets)) %||% NULL
  }
  list(
    endpoint = "/exports",
    request = request,
    selection = selection,
    request_ids = character(),
    complete = TRUE,
    next_offset = NA_real_,
    api_version = scalar_chr(meta$api_version),
    schema_version = scalar_chr(meta$schema_version),
    client_version = client_version(),
    retrieved_at = scalar_chr(meta$generated_at),
    total_count = if (identical(layout, "long")) as.numeric(records$observation_rows %||% NA_real_) else NA_real_,
    warnings = as.character(unlist(meta$warnings)) %||% character(),
    variables = variables,
    view = scalar_chr(meta$view %||% request$view %||% "raw"),
    revised = meta$revised,
    first_layer = meta$first_layer,
    components = meta$components,
    min_cumulative_percent = meta$min_cumulative_percent,
    crs = scalar_chr(meta$crs %||% "EPSG:4326"),
    datasets = datasets,
    multi_value_rule = "mean",
    via_export = scalar_chr(meta$job_id),
    export = list(
      job_id = scalar_chr(meta$job_id), format = scalar_chr(meta$format),
      content = scalar_chr(meta$content), layout = scalar_chr(meta$layout),
      generated_at = scalar_chr(meta$generated_at), records = records,
      files = as.character(unlist(meta$files)), tables = meta$tables,
      variables = meta$variables
    )
  )
}

# ---------------------------------------------------------------------------
# Typing of the flat formats (CSV, TSV, GeoPackage, Shapefile): column by
# column, with the types of the synchronous reads. Nested values are JSON
# text in these files: they are parsed, then typed by the functions of the
# synchronous reads (typing-wide.R, typing-long.R, features.R).

# A scalar column (text from CSV/TSV, as read by GDAL from GeoPackage) in the
# type a synchronous read gives the same JSON value.
flat_scalar <- function(x, type, n = length(x)) {
  if (is.null(x)) x <- rep(NA_character_, n)
  if (is.factor(x)) x <- as.character(x)
  switch(type,
    chr = {
      if (is.character(x)) return(x)
      out <- rep(NA_character_, length(x))
      ok <- !is.na(x)
      out[ok] <- vapply(as.list(x[ok]), function(v) scalar_chr(if (inherits(v, c("Date", "POSIXt"))) as.character(v) else v), character(1))
      out
    },
    dbl = if (is.numeric(x)) as.numeric(x) else suppressWarnings(as.numeric(as.character(x))),
    int = {
      number <- if (is.numeric(x)) as.numeric(x) else suppressWarnings(as.numeric(as.character(x)))
      suppressWarnings(as.integer(number))
    },
    lgl = {
      if (is.logical(x)) return(x)
      if (is.numeric(x)) return(as.numeric(x) != 0)
      c(TRUE, FALSE)[match(tolower(as.character(x)), c("true", "false"))]
    },
    time = parse_api_time(as.character(x)),
    date = parse_api_date(as.character(x)),
    flat_scalar(x, "chr")
  )
}

# JSON text cells parsed (`NULL` for a missing cell; a text that is not JSON
# stays text).
parse_json_cells <- function(x, n = length(x)) {
  out <- vector("list", n)
  if (is.null(x)) return(out)
  x <- as.character(x)
  ok <- which(!is.na(x) & nzchar(x))
  out[ok] <- lapply(x[ok], function(text) {
    tryCatch(jsonlite::fromJSON(text, simplifyVector = FALSE), error = function(e) text)
  })
  out
}

# `value_raw` of the long layout: a JSON value written as text when it is a
# list or an object, as the number or the string itself otherwise.
parse_raw_cells <- function(x, n = length(x)) {
  out <- vector("list", n)
  if (is.null(x)) return(out)
  if (is.numeric(x)) {
    ok <- which(!is.na(x))
    out[ok] <- as.list(x[ok])
    return(out)
  }
  x <- as.character(x)
  ok <- which(!is.na(x))
  out[ok] <- lapply(x[ok], function(text) {
    if (grepl("^\\s*[\\[{]", text) || grepl(numeric_text_pattern, text)) {
      return(tryCatch(jsonlite::fromJSON(text, simplifyVector = FALSE), error = function(e) text))
    }
    text
  })
  out
}

# A variable column of the wide layout, vectorised: as type_variable_values()
# on the JSON values (a number or numeric text gives the number, a
# multi-value cell the mean of its values).
flat_variable <- function(x, numeric, multi, n = length(x)) {
  if (is.null(x)) x <- rep(NA_character_, n)
  text <- if (is.character(x)) x else NULL
  elements <- NULL
  if (multi && !is.null(text)) {
    elements <- vector("list", n)
    candidates <- which(!is.na(text) & grepl("^\\s*\\[", text))
    elements[candidates] <- lapply(text[candidates], multi_value_elements)
  }
  if (numeric) {
    if (is.numeric(x)) {
      value <- as.numeric(x)
    } else {
      x <- as.character(x)
      value <- rep(NA_real_, n)
      ok <- !is.na(x) & grepl(numeric_text_pattern, x)
      value[ok] <- as.numeric(x[ok])
    }
    if (!is.null(elements)) {
      listed <- which(!vapply(elements, is.null, logical(1)))
      value[listed] <- vapply(elements[listed], multi_value_mean, numeric(1))
    }
  } else {
    value <- flat_scalar(x, "chr")
  }
  list(value = value, values = if (multi) elements %||% vector("list", n) else NULL)
}

# The observations table of a flat export (`raw`: a data frame of columns as
# read; NULL for an empty table) typed as the synchronous layout.
flat_observations <- function(raw, layout, variables) {
  if (is.null(raw) || !ncol(raw)) {
    pages <- export_pages(list())
    if (identical(layout, "wide")) return(wide_frame(pages, variables, "none"))
    return(long_layout_frame(pages, "none"))
  }
  raw <- as.data.frame(raw, stringsAsFactors = FALSE)
  if (identical(layout, "wide")) flat_wide(raw, variables) else flat_long(raw)
}

flat_wide <- function(raw, variables) {
  n <- nrow(raw)
  var_columns <- variables$column
  group_names <- c(var_columns, unlist(lapply(wide_companion_suffixes, function(s) paste0(var_columns, s))))
  other <- setdiff(names(raw), group_names)
  unknown <- other[vapply(other, function(name) is.null(wide_column_type(name)), logical(1))]
  if (length(unknown)) report_drift("the observations of an export (wide)", unknown, character())
  columns <- list()
  for (name in other) {
    type <- wide_column_type(name) %||% "chr"
    columns[[name]] <- if (type %in% wide_nested_types) {
      type_wide_values(parse_json_cells(raw[[name]]), type)
    } else {
      flat_scalar(raw[[name]], type)
    }
  }
  for (i in seq_along(var_columns)) {
    column <- var_columns[[i]]
    multi <- isTRUE(variables$multi_value_cells[[i]] > 0)
    typed <- flat_variable(raw[[column]], numeric = isTRUE(variables$numeric[[i]]), multi = multi, n = n)
    columns[[column]] <- typed$value
    columns[[paste0(column, "_units")]] <- flat_scalar(raw[[paste0(column, "_units")]], "chr", n)
    columns[[paste0(column, "_method")]] <- flat_scalar(raw[[paste0(column, "_method")]], "chr", n)
    columns[[paste0(column, "_n")]] <- flat_scalar(raw[[paste0(column, "_n")]], "int", n)
    if (multi) columns[[paste0(column, "_values")]] <- typed$values
  }
  new_frame(columns, n)
}

flat_long <- function(raw) {
  n <- nrow(raw)
  unknown <- setdiff(names(raw), names(long_column_types))
  if (length(unknown)) report_drift("the observations of an export (long)", unknown, character())
  columns <- list()
  for (name in names(raw)) {
    type <- long_column_types[name]
    type <- if (is.na(type)) "chr" else unname(type)
    if (identical(type, "geometry")) next
    columns[[name]] <- if (identical(type, "raw")) {
      parse_raw_cells(raw[[name]])
    } else if (type %in% long_nested_types) {
      type_long_values(parse_json_cells(raw[[name]]), type)
    } else {
      flat_scalar(raw[[name]], type)
    }
  }
  if (!is.null(columns$value) && !is.null(columns$value_raw)) {
    columns$value <- long_multi_value_means(columns$value, columns$value_raw)
  }
  new_frame(columns, n)
}

# The features table of a flat export, without its geometry. `nested =
# FALSE` (Shapefile: texts cut at 254 characters) keeps the nested values as
# text.
flat_features <- function(raw, nested = TRUE) {
  if (is.null(raw) || !nrow(raw)) {
    fields <- c("dataset", "provider_code", "feature_id", "feature_key", "geometry_kind", "source_support")
    if (!is.null(raw)) fields <- union(fields, names(raw))
    columns <- lapply(fields, function(name) {
      type <- feature_property_types[name]
      if (!is.na(type) && unname(type) %in% c("components", "chr_list")) list() else character()
    })
    names(columns) <- fields
    return(new_frame(columns, 0L))
  }
  raw <- as.data.frame(raw, stringsAsFactors = FALSE)
  unknown <- setdiff(names(raw), names(feature_property_types))
  if (length(unknown)) report_drift("the features of an export", unknown, character())
  columns <- list()
  for (name in names(raw)) {
    type <- feature_property_types[name]
    type <- if (is.na(type)) "chr" else unname(type)
    columns[[name]] <- if (identical(type, "components") && nested) {
      lapply(parse_json_cells(raw[[name]]), type_feature_components)
    } else if (identical(type, "chr_list") && nested) {
      type_column(parse_json_cells(raw[[name]]), "chr_list")
    } else if (type %in% c("components", "chr_list")) {
      flat_scalar(raw[[name]], "chr")
    } else {
      flat_scalar(raw[[name]], type)
    }
  }
  new_frame(columns, nrow(raw))
}

# ---------------------------------------------------------------------------
# A read refused as too large, exported and read back (design 6.3).

# The geometries of the features of an export by feature_id: parsed GeoJSON
# (geojson) or WKT (csv, tsv).
export_feature_geometries <- function(source) {
  if (identical(source$format, "geojson")) {
    items <- read_geojson_features(file.path(source$dir, "features.geojson")) %||% list()
    ids <- vapply(items, function(item) scalar_chr(item$properties$feature_id %||% item$id), character(1))
    out <- lapply(items, function(item) item$geometry)
    names(out) <- ids
    return(list(geometries = out, kinds = stats::setNames(
      vapply(items, function(item) scalar_chr(item$properties$geometry_kind), character(1)), ids
    )))
  }
  raw <- read_delimited(
    file.path(source$dir, paste0("features.", source$format)),
    if (identical(source$format, "tsv")) "\t" else ","
  )
  if (is.null(raw)) return(list(geometries = list(), kinds = character()))
  list(
    geometries = stats::setNames(as.list(raw$geometry_wkt), raw$feature_id),
    kinds = stats::setNames(raw$geometry_kind, raw$feature_id)
  )
}

# `geometry_kind` and `geometry_text` (WKT) of each wide row, placed before
# the variable groups (where the synchronous wide layout puts the geometry);
# `"sf"` turns `geometry_text` into the sfc `geometry`.
with_wide_geometry <- function(table, lookup, with_geometry) {
  frame <- as.data.frame(table)
  columns <- as.list(frame)
  variables <- soil_metadata(table)$variables
  feature_id <- frame$feature_id %||% character()
  text <- vapply(feature_id, function(id) {
    value <- if (is.na(id)) NULL else lookup$geometries[[id]]
    if (is.null(value)) NA_character_ else scalar_chr(value)
  }, character(1), USE.NAMES = FALSE)
  kind <- vapply(feature_id, function(id) {
    if (is.na(id) || is.na(lookup$kinds[id])) NA_character_ else unname(lookup$kinds[id])
  }, character(1), USE.NAMES = FALSE)
  warn_missing_geometry(is.na(text), feature_id, missing_geometry_text(with_geometry))
  positions <- match(variables$column %||% character(), names(columns))
  position <- if (any(!is.na(positions))) min(positions, na.rm = TRUE) else length(columns) + 1L
  before <- setdiff(names(columns)[seq_len(position - 1L)], "geometry_kind")
  after <- setdiff(names(columns)[seq.int(position, length.out = length(columns) - position + 1L)], "geometry_kind")
  frame <- new_frame(
    c(columns[before], list(geometry_kind = kind, geometry_text = text), columns[after]),
    nrow(frame)
  )
  if (identical(with_geometry, "sf")) frame <- wide_as_sf(frame)
  new_soil_table(frame, soil_metadata(table), "wide")
}

# Rows `offset + 1` to `offset + max_rows` of a table read back.
slice_rows <- function(table, offset, max_rows) {
  n <- nrow(table)
  if (offset == 0 && (is.infinite(max_rows) || max_rows >= n)) return(table)
  first <- min(offset, n) + 1
  last <- min(n, offset + max_rows)
  rows <- if (first > last) integer() else seq.int(first, last)
  out <- table[rows, , drop = FALSE]
  attr(out, "row.names") <- .set_row_names(length(rows))
  out
}

# `too_large = "export"` of soil_observations(): the same selection exported
# (CSV; GeoJSON for the long layout with geometry, whose rows carry GeoJSON),
# downloaded, read back in the shape of the synchronous read.
observations_via_export <- function(soil, selection, layout, with_geometry, max_rows,
                                    offset, progress) {
  long <- identical(layout, "long")
  format <- if (long && !identical(with_geometry, "none")) "geojson" else "csv"
  soil_inform(soil, 1, sprintf(
    paste0(
      "soilhub: the selection is above the limit of synchronous reads: exporting it ",
      "(format \"%s\") and reading the files back (too_large = \"export\")."
    ),
    format
  ))
  x <- do.call(soil_export, c(
    list(soil = soil), selection,
    list(format = format, content = "all", layout = layout, progress = progress)
  ))
  source <- export_source(x)
  geometries <- if (identical(with_geometry, "none")) NULL else export_feature_geometries(source)
  table <- read_export_observations(source, if (long) with_geometry else "none", geometries)
  if (!long && !identical(with_geometry, "none")) {
    table <- with_wide_geometry(table, geometries, with_geometry)
  }
  via_export(slice_rows(table, offset, max_rows), x)
}

# The job id of the export a table was read from.
via_export <- function(table, x) {
  meta <- attr(table, "soil_metadata")
  meta$via_export <- x$job_id
  attr(table, "soil_metadata") <- meta
  table
}

# `too_large = "export"` of soil_features(): the features exported as
# GeoJSON and read back.
features_via_export <- function(soil, selection, with_geometry, max_rows, progress) {
  soil_inform(soil, 1, paste0(
    "soilhub: the selection is above the limit of synchronous reads: exporting its features ",
    "(format \"geojson\") and reading the file back (too_large = \"export\")."
  ))
  x <- do.call(soil_export, c(
    list(soil = soil), selection,
    list(format = "geojson", content = "features", progress = progress)
  ))
  table <- read_export_features(export_source(x), with_geometry)
  via_export(slice_rows(table, 0, max_rows), x)
}
