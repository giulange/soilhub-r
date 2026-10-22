# Live test of exports end to end (design 6, 7.3; acceptance criterion 10.5).
#
#   Rscript tests/live/exports.R               # from the package root
#   Rscript tests/live/exports.R --fake        # dry run on local fake servers
#
# Any account with soil:read. On the API it creates five small export jobs
# (zips kept by the server for 7 days, then deleted by it); no soil data is
# changed. Downloads go to a temporary directory, removed at the end.

.live_dir <- local({
  file <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(file)) dirname(normalizePath(file[1])) else normalizePath(file.path("tests", "live"))
})
source(file.path(.live_dir, "common.R"))

# WoSIS around Vancouver: 4 features, 12 horizons, 30 observations (recorded
# 2026-10-20): every export finishes in seconds.
selection <- list(datasets = "wosis_points", bbox = c(-123.3, 49.0, -122.9, 49.4))

usage <- c(
  "Usage: Rscript tests/live/exports.R [options]",
  "  --poll=S           seconds between two polls of an export (default 3)",
  "  --timeout=S        seconds to wait for each export (default 1800)",
  "  --keep             keep the downloaded files (default: removed at the end)",
  "  --installed        use the installed soilhub even in the source tree",
  "  --fake, --dry-run  run on local fake servers (no login, no network)"
)
opts <- live_init("exports", .live_dir, list(poll = 3, timeout = 1800, keep = FALSE), usage)

live_run(function() {
  tmp <- file.path(tempdir(), paste0("soilhub-live-exports-", live$stamp))
  dir.create(tmp, recursive = TRUE, showWarnings = FALSE)
  has_sf <- requireNamespace("sf", quietly = TRUE)
  if (live$fake) {
    env <- live_fake_env()
    zips <- list()
    for (spec in list(c("csv", "all"), c("gpkg", "all"), c("geojson", "all"), c("shp", "features"))) {
      zip <- tryCatch(env$build_export_zip(file.path(tmp, "fixtures"), spec[1], spec[2], "wide"), error = function(e) NULL, skip = function(e) NULL)
      if (!is.null(zip)) zips[[paste(spec[1], spec[2], "wide", sep = "-")]] <- zip
    }
    live_fake_start(c("auth", "wide", "long", "export"), zips = zips)
  }

  soil <- live_connect("reader")
  me <- soil_whoami(soil)
  live_logf("      rights: %s", if (isTRUE(me$rights_known)) paste(me$roles, collapse = ", ") else "not declared in the token")

  sync <- live_check("5.0", "synchronous wide read of the selection (WoSIS, Vancouver bbox)", function() {
    x <- soil_observations(live_route(soil, "wide"), datasets = selection$datasets, bbox = selection$bbox, progress = FALSE)
    live_logf("      %s", live_describe(x))
    v_expect(nrow(x) > 0L && isTRUE(soil_metadata(x)$complete), sprintf("%d horizon rows", nrow(x)), value = x)
  })
  sync_features <- live_check("5.0f", "synchronous features of the selection", function() {
    f <- soil_features(live_route(soil, "long"), datasets = selection$datasets, bbox = selection$bbox,
                       with_geometry = "text", progress = FALSE)
    live_logf("      %d features, request ids %s", nrow(f), paste(soil_metadata(f)$request_ids, collapse = " "))
    v_expect(nrow(f) > 0L, sprintf("%d features", nrow(f)), value = f)
  })

  log_export <- function(x) {
    records <- x$records
    live_logf("      job %s: status %s, %s observations, records %s, %s bytes, files %s, expires %s",
              x$job_id, x$status, format(x$observation_count %||% NA),
              if (is.list(records)) paste(sprintf("%s=%s", names(records), vapply(records, function(v) paste(unlist(v), collapse = "/"), "")), collapse = " ") else "none",
              format(x$file_size_bytes %||% NA), paste(x$files %||% "none", collapse = ","),
              format(x$expires_at %||% NA))
  }

  for (format in c("csv", "gpkg", "geojson")) {
    live_check(sprintf("5.%s", format), sprintf("export %s: submitted, waited, downloaded, unzipped, read; rows equal to the synchronous read", format), function() {
      if (format == "gpkg" && !has_sf) return(v_skip("reading a GeoPackage needs the package sf"))
      if (is.null(sync)) return(v_skip("needs the synchronous read (5.0)"))
      started <- Sys.time()
      x <- soil_export(live_route(soil, "export"), datasets = selection$datasets, bbox = selection$bbox,
                       format = format, content = "all", layout = "wide", dir = tmp,
                       poll = opts$poll, timeout = opts$timeout, progress = FALSE)
      log_export(x)
      live_logf("      export round trip %.1f s; unzipped in %s", as.numeric(difftime(Sys.time(), started, units = "secs")), basename(x$dir %||% ""))
      obs <- soil_export_read(x)
      features <- soil_export_read(x, "features")
      live_logf("      read back: %d observation rows (%d columns), %d features", nrow(obs), ncol(obs), nrow(features))
      cmp <- live_compare_wide(sync, obs)
      for (m in utils::head(cmp$mismatches, 10)) live_logf("      mismatch: %s", m)
      rows_recorded <- x$records$observation_rows %||% soil_metadata(obs)$export$records$observation_rows
      problems <- c(
        if (!identical(x$status, "completed")) sprintf("status %s", x$status),
        if (!cmp$ok) "observation rows differ from the synchronous read",
        if (!identical(as.numeric(rows_recorded), as.numeric(nrow(sync)))) sprintf("metadata.json observation_rows %s, synchronous rows %d", format(rows_recorded), nrow(sync)),
        if (!is.null(sync_features) && nrow(features) != nrow(sync_features)) sprintf("features: export %d, synchronous %d", nrow(features), nrow(sync_features))
      )
      v_expect(!length(problems), if (length(problems)) paste(problems, collapse = "; ") else cmp$detail)
    })
  }

  live_check("5.shp", "Shapefile export of the features only, read back", function() {
    if (!has_sf) return(v_skip("reading a Shapefile needs the package sf"))
    x <- soil_export(live_route(soil, "export"), datasets = selection$datasets, bbox = selection$bbox,
                     format = "shp", content = "features", dir = tmp,
                     poll = opts$poll, timeout = opts$timeout, progress = FALSE)
    log_export(x)
    features <- soil_export_read(x, "features")
    live_logf("      read back: %d features, %d columns", nrow(features), ncol(features))
    problems <- c(
      if (!identical(x$status, "completed")) sprintf("status %s", x$status),
      if (!is.null(sync_features) && nrow(features) != nrow(sync_features)) sprintf("features: export %d, synchronous %d", nrow(features), nrow(sync_features)),
      if (!is.null(sync_features) && !is.null(features$feature_id) && !setequal(features$feature_id, sync_features$feature_id)) "different feature ids"
    )
    v_expect(!length(problems), if (length(problems)) paste(problems, collapse = "; ") else sprintf("%d features", nrow(features)))
  })

  # The refused read: the whole catalogue (`datasets = NULL`) is above the
  # synchronous limit. Converted with soil_export_from_error() but with the
  # Vancouver bbox given as an override, so the export stays small (all
  # datasets inside the bbox). The alternative, submitting the whole
  # catalogue and cancelling it, would start a multi-million-row job on the
  # server and needs soil:publish to cancel it (API fact 12.2.3).
  live_check("5.refused", "a refused synchronous read (datasets = NULL) converted with soil_export_from_error()", function() {
    e <- tryCatch(soil_observations(live_route(soil, "export"), max_rows = 5, progress = FALSE),
                  soilhub_load_limit_error = function(e) e)
    if (!inherits(e, "soilhub_load_limit_error")) return(v_fail("the unfiltered read was not refused with soilhub_load_limit_error"))
    live_logf("      refused: channel %s, observation_count %s (exact %s), limit %s, request id %s",
              format(e$channel %||% NA), format(e$observation_count %||% NA), format(e$observation_count_exact %||% NA),
              format(e$max_observations %||% NA), format(e$request_id %||% NA))
    x <- soil_export_from_error(live_route(soil, "export"), e, format = "csv", bbox = selection$bbox, dir = tmp,
                                poll = opts$poll, timeout = opts$timeout, progress = FALSE)
    log_export(x)
    obs <- soil_export_read(x)
    request <- x$request
    live_logf("      export request: %s", as.character(jsonlite::toJSON(request, auto_unbox = TRUE)))
    problems <- c(
      if (!identical(x$status, "completed")) sprintf("status %s", x$status),
      if (!is.null(request$datasets)) "the export names datasets (the refused read had none)",
      if (!isTRUE(all.equal(as.numeric(unlist(request$bbox)), selection$bbox))) "the bbox override was not applied",
      if (!nrow(obs)) "no observation row read back"
    )
    v_expect(!length(problems), if (length(problems)) paste(problems, collapse = "; ") else
      sprintf("%d observation rows from %s", nrow(obs), paste(unique(obs$dataset), collapse = ", ")))
  })

  live_check("5.clean", "temporary files removed", function() {
    if (isTRUE(opts$keep)) return(v_skip(sprintf("--keep: files kept in %s", tmp)))
    unlink(tmp, recursive = TRUE)
    v_expect(!dir.exists(tmp), "temporary directory removed")
  })
})
