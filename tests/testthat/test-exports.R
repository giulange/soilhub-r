# Exports (WP7, design 4.5, 6): reading the zip of each format with and
# without sf, typed from metadata.json as the synchronous reads; the export
# lifecycle on the fake API of helper-fake-exports.R; too_large = "export"
# and soil_export_from_error().

zips_dir <- withr::local_tempdir(.local_envir = teardown_env())

# The zips of the formats, built once (a format whose tool is missing is
# skipped by the test that needs it).
zip_of <- local({
  built <- list()
  function(format, content = "all", layout = "wide") {
    key <- paste(format, content, layout, sep = "-")
    if (is.null(built[[key]])) built[[key]] <<- build_export_zip(zips_dir, format, content, layout)
    built[[key]]
  }
})

# The synchronous typing of the same rows (no geometry).
sync_wide <- function() {
  pages <- fixture_pages("wide-wosis-page1.json", "wide-wosis-page2.json")
  pages$items <- lapply(pages$items, function(row) {
    row$geometry_kind <- NULL
    row
  })
  list(frame = wide_frame(pages, merge_wide_variables(pages$page_metadata), "none"),
       variables = merge_wide_variables(pages$page_metadata))
}

sync_long <- function(with_geometry = "none") {
  pages <- list(read_fixture("long-wosis-page1.json"), read_fixture("long-wosis-page2.json"))
  items <- unlist(lapply(pages, `[[`, "observations"), recursive = FALSE)
  if (identical(with_geometry, "none")) {
    items <- lapply(items, function(row) {
      row["geometry"] <- list(NULL)
      row["geometry_kind"] <- list(NULL)
      row
    })
  }
  long_layout_frame(export_pages(items), with_geometry)
}

sync_features <- function(with_geometry) {
  items <- export_features()
  features_frame(export_pages(items), with_geometry)
}

attributes_of <- function(x) {
  frame <- as.data.frame(x)
  frame[setdiff(names(frame), c("geometry", "geometry_text", "geometry_wkt"))]
}

# ---------------------------------------------------------------------------
# Reading the zip of each format

test_that("wide observations of every format equal the synchronous typing", {
  sync <- sync_wide()
  for (format in c("csv", "tsv", "geojson", "gpkg")) {
    if (format == "gpkg" && !gdal_can_write("GPKG")) next
    x <- soil_export_read(zip_of(format))
    expect_s3_class(x, c("soil_table", "data.frame"), exact = TRUE)
    expect_identical(attr(x, "soil_layout"), "wide")
    expect_identical(as.data.frame(x), sync$frame, label = format)
    # typed from metadata.json: wide_columns give the numeric and multi-value columns
    expect_identical(soil_columns(x), sync$variables, label = format)
    expect_equal(x$coarse_fragments[1:3], c(1, 4, NA))
    expect_identical(x$coarse_fragments_values[[1]], c("0.9", "1.1"))
    expect_type(x$src_dens, "character")
    expect_identical(x$value_flags[[3]]$organic_carbon, c("extreme", "above_unit_maximum"))
    meta <- soil_metadata(x)
    expect_identical(meta$via_export, export_job_id)
    expect_identical(meta$endpoint, "/exports")
    expect_true(meta$complete)
    expect_identical(meta$total_count, NA_real_)
    expect_identical(meta$multi_value_rule, "mean")
    expect_identical(meta$export$format, format)
    expect_identical(meta$export$records$observation_rows, 5L)
    expect_identical(soil_warnings(x), "column 'coarse_fragments' has 2 multi-value cell(s) returned as JSON text")
    expect_identical(meta$selection$datasets, "wosis_points")
    expect_s3_class(meta$datasets, "data.frame")
    expect_identical(soil_citations(x)$dataset[1], "wosis_points")
  }
  if (!gdal_can_write("GPKG")) skip("sf/GDAL cannot write a GeoPackage")
})

test_that("long observations of every format equal the synchronous typing", {
  sync <- sync_long()
  for (format in c("csv", "tsv", "geojson", "gpkg")) {
    if (format == "gpkg" && !gdal_can_write("GPKG")) next
    x <- soil_export_read(zip_of(format, layout = "long"))
    expect_identical(attr(x, "soil_layout"), "long")
    expect_identical(as.data.frame(x), sync, label = format)
    expect_equal(x$value[1], 1)  # multi-value cell: the mean of value_raw
    expect_identical(x$value_raw[[1]], list("0.9", "1.1"))
    expect_identical(soil_metadata(x)$total_count, 17)
    expect_null(soil_metadata(x)$variables)
  }
  if (!gdal_can_write("GPKG")) skip("sf/GDAL cannot write a GeoPackage")
})

test_that("features are an sf with sf, text without it", {
  skip_if_not_installed("sf")
  sync <- sync_features("sf")
  for (format in c("csv", "tsv", "geojson", "gpkg")) {
    if (format == "gpkg" && !gdal_can_write("GPKG")) next
    zip <- zip_of(format, content = "features")
    x <- soil_export_read(zip)  # content = "features": the features by default
    expect_s3_class(x, c("soil_table", "sf", "data.frame"), exact = TRUE)
    expect_identical(attr(x, "soil_layout"), "features")
    expect_identical(attributes_of(x), attributes_of(sync), label = format)
    expect_identical(sf::st_as_text(sf::st_geometry(x)), c("POINT (36.8 -1.3)", "POINT (37 -1)", "POINT (38.25 0.5)"))
    expect_identical(sf::st_crs(x)$epsg, 4326L)
    expect_identical(soil_metadata(x)$feature_count, 3L)
    expect_false(soil_metadata(x)$mixed_geometry)
    expect_error(soil_export_read(zip, "observations"), class = "soilhub_argument_error")
  }
  # the features of an export with observations
  x <- soil_export_read(zip_of("csv"), "features")
  expect_s3_class(x, "sf")
  expect_identical(nrow(x), 3L)
})

test_that("without sf: CSV/TSV keep geometry_wkt, GeoJSON gives geometry_text, GeoPackage needs sf", {
  csv <- zip_of("csv", content = "features")
  geojson <- zip_of("geojson", content = "features")
  gpkg <- if (gdal_can_write("GPKG")) zip_of("gpkg") else NULL
  local_mocked_bindings(soil_has_package = function(package) FALSE)
  x <- soil_export_read(csv)
  expect_s3_class(x, c("soil_table", "data.frame"), exact = TRUE)
  expect_identical(x$geometry_wkt, c("POINT (36.8 -1.3)", "POINT (37 -1)", "POINT (38.25 0.5)"))
  expect_identical(attributes_of(x), attributes_of(sync_features("text")))
  y <- soil_export_read(geojson)
  expect_identical(as.data.frame(y), sync_features("text"))
  expect_identical(y$geometry_text[1], "{\"type\":\"Point\",\"coordinates\":[36.8,-1.3]}")
  # observations of CSV/TSV and GeoJSON need no package
  expect_identical(as.data.frame(soil_export_read(zip_of("tsv"))), sync_wide()$frame)
  if (!is.null(gpkg)) {
    e <- expect_error(soil_export_read(gpkg), class = "soilhub_dependency_error")
    expect_identical(e$package, "sf")
    expect_match(conditionMessage(e), "\"gpkg\" needs the package 'sf'", fixed = TRUE)
  }
})

test_that("a Shapefile export: one sf with the names restored and the nested values as text", {
  zip <- zip_of("shp", content = "features")
  x <- soil_export_read(zip)
  expect_s3_class(x, "sf")
  expect_identical(nrow(x), 4L)
  expect_true(all(c("feature_key", "geometry_kind", "source_support", "profile_markings",
                    "retired_in_release", "components") %in% names(x)))
  expect_type(x$components, "character")
  expect_match(x$components[3], "^\\[\\{\"component_id\":\"c-1\"")
  expect_identical(sort(unique(sf::st_geometry_type(x, by_geometry = TRUE) == "POINT")), c(FALSE, TRUE))
  expect_true(soil_metadata(x)$mixed_geometry)
  local_mocked_bindings(soil_has_package = function(package) FALSE)
  expect_error(soil_export_read(zip), class = "soilhub_dependency_error")
})

test_that("soil_export_read() reads directories, metadata and everything; refuses what is not an export", {
  zip <- zip_of("csv")
  dir <- withr::local_tempdir()
  utils::unzip(zip, exdir = dir)
  meta <- soil_export_read(dir, "metadata")
  expect_identical(meta$format, "csv")
  expect_identical(meta$records$features, 3L)
  all <- soil_export_read(dir, "all")
  expect_named(all, c("features", "observations", "metadata"))
  expect_identical(attr(all$observations, "soil_layout"), "wide")
  expect_identical(attr(all$features, "soil_layout"), "features")
  features_only <- soil_export_read(zip_of("geojson", content = "features"), "all")
  expect_null(features_only$observations)

  err <- function(x, ...) expect_error(soil_export_read(x, ...), class = "soilhub_argument_error")
  err(file.path(dir, "nothing-here"))
  err(file.path(dir, "metadata.json"))
  empty <- withr::local_tempdir()
  err(empty)
  err(42)
  err(zip, what = "rows")
  err(new_soil_export(list(job_id = "exp_1", status = "completed")))
})

test_that("an export without records reads as empty typed tables", {
  zip <- build_export_zip(withr::local_tempdir(), "csv", empty = TRUE)
  x <- soil_export_read(zip)
  expect_identical(nrow(x), 0L)
  expect_true(all(c("dataset", "feature_id", "horizon_id", "upper_depth_cm") %in% names(x)))
  f <- soil_export_read(zip, "features")
  expect_identical(nrow(f), 0L)
})

# ---------------------------------------------------------------------------
# The export lifecycle on the fake API

api <- fake_export_api(list(
  `csv-all-wide` = zip_of("csv"),
  `csv-all-long` = zip_of("csv", layout = "long"),
  `geojson-all-long` = zip_of("geojson", layout = "long"),
  `geojson-features-wide` = zip_of("geojson", content = "features")
))

test_that("soil_export(wait = FALSE) submits the selection and returns the job id", {
  soil <- export_session(api, verbose = 1)
  out <- collect_messages(soil_export(soil, datasets = "wosis_points", country = "KEN",
                                     variables = "clay", format = "csv", wait = FALSE))
  x <- out$value
  expect_s3_class(x, "soil_export")
  expect_match(x$job_id, "^exp_20261019_080000_[0-9a-f]{8}$")
  # one status read after the submission: running, with the expiry
  expect_identical(x$status, "running")
  expect_identical(x$progress, 5)
  expect_identical(x$observation_count, 4656)
  expect_identical(format(x$expires_at, tz = "UTC"), "2026-10-26 08:00:00")
  expect_identical(x$format, "csv")
  expect_identical(x$content, "all")
  expect_identical(x$layout, "wide")
  expect_identical(x$selection, list(datasets = "wosis_points", variables = "clay", country = "KEN"))
  expect_match(out$messages, paste0("export ", x$job_id, " running (4,656 observations). Keep this id"), fixed = TRUE)
  expect_match(out$messages, "the zip is kept until 2026-10-26 08:00:00 UTC", fixed = TRUE)
  body <- submitted_exports(api)
  body <- body[[length(body)]]
  expect_identical(body$format, "csv")
  expect_identical(body$content, "all")
  expect_identical(body$layout, "wide")
  expect_true(body$canonical)
  expect_identical(body$datasets, list("wosis_points"))
  expect_identical(body$variables, list("clay"))
  expect_identical(body$view, "raw")
  expect_null(body$limit)
  expect_output(print(x), "Keep the job id: resume with soil_export_wait", fixed = TRUE)
})

test_that("the lifecycle: queued, running, completed with the controlled clock, then download", {
  clock <- local_fake_clock()
  dir <- withr::local_tempdir()
  soil <- export_session(api)
  x <- soil_export(soil, datasets = "wosis_points", format = "csv", wait = FALSE)
  expect_identical(soil_export_status(soil, x$job_id)$progress, 45)
  out <- collect_messages(soil_export_wait(soil, x, poll = 5, progress = TRUE))
  x <- out$value
  expect_identical(x$status, "completed")
  expect_identical(x$progress, 100)
  expect_identical(x$records$observation_rows, 5L)
  expect_identical(clock$waits, numeric())
  expect_match(out$messages[1], paste0("export ", x$job_id, " completed (100%)"), fixed = TRUE)
  expect_match(out$messages[2], "written: 3 features, 5 observation rows", fixed = TRUE)
  expect_error(soil_export_wait(soil, x, poll = 1), class = "soilhub_argument_error")

  out <- collect_messages(soil_export_download(soil, x$job_id, dir = dir, progress = TRUE))
  y <- out$value
  expect_identical(y$zip, normalizePath(file.path(dir, paste0(x$job_id, ".zip")), winslash = "/"))
  expect_identical(y$dir, normalizePath(file.path(dir, x$job_id), winslash = "/"))
  expect_identical(y$files, c("features.csv", "metadata.json", "observations.csv"))
  expect_identical(y$metadata$format, "csv")
  expect_match(out$messages, "downloaded to", fixed = TRUE)
  # the soil_export works with the result helpers
  expect_identical(soil_columns(y), sync_wide()$variables)
  expect_identical(soil_citations(y)$dataset[1], "wosis_points")
  expect_identical(soil_warnings(y), "column 'coarse_fragments' has 2 multi-value cell(s) returned as JSON text")
  expect_identical(as.data.frame(soil_export_read(y)), sync_wide()$frame)
  printed <- capture.output(print(y))
  expect_match(printed[1], paste0("<soil_export> ", x$job_id), fixed = TRUE)
  expect_true(any(grepl("Written:  3 features, 5 observation rows, 17 observations", printed, fixed = TRUE)))
  expect_true(any(grepl("Read with soil_export_read(x)", printed, fixed = TRUE)))

  # files are never overwritten unless asked
  e <- expect_error(soil_export_download(soil, y, dir = dir), class = "soilhub_argument_error")
  expect_identical(e$argument, "overwrite")
  z <- soil_export_download(soil, y, dir = dir, overwrite = TRUE, unzip = FALSE)
  expect_identical(z$files, c("features.csv", "metadata.json", "observations.csv"))
  # the zip alone reads too
  expect_identical(as.data.frame(soil_export_read(z$zip)), sync_wide()$frame)
})

test_that("soil_export(wait = TRUE) polls, downloads and unzips; progress is reported", {
  clock <- local_fake_clock()
  dir <- withr::local_tempdir()
  soil <- export_session(api)
  out <- collect_messages(soil_export(soil, datasets = "wosis_points", format = "csv",
                                     layout = "long", dir = dir, poll = 5, progress = TRUE))
  x <- out$value
  expect_identical(x$status, "completed")
  expect_identical(clock$waits, c(5, 5))
  expect_identical(length(out$messages), 6L)
  expect_match(out$messages[1], "submitted (4,656 observations, format csv)", fixed = TRUE)
  expect_match(out$messages[2], "running (5%)", fixed = TRUE)
  expect_match(out$messages[3], "running (45%)", fixed = TRUE)
  expect_match(out$messages[4], "completed (100%)", fixed = TRUE)
  expect_match(out$messages[5], "written", fixed = TRUE)
  expect_match(out$messages[6], "downloaded to", fixed = TRUE)
  expect_true(dir.exists(x$dir))
  expect_identical(as.data.frame(soil_export_read(x)), sync_long())
  # progress = FALSE: silent
  out <- collect_messages(soil_export(soil, datasets = "wosis_points", format = "csv", dir = dir,
                                     progress = FALSE))
  expect_length(out$messages, 0L)
  # the export directory option
  withr::local_options(soilhub.export_dir = file.path(dir, "by-option"))
  x <- soil_export(soil, datasets = "wosis_points", format = "csv", progress = FALSE)
  expect_identical(dirname(x$zip), normalizePath(file.path(dir, "by-option"), winslash = "/"))
})

test_that("a failed, cancelled, unknown or slow export is a soilhub_job_error", {
  clock <- local_fake_clock()
  soil <- export_session(api)
  e <- expect_error(soil_export(soil, datasets = "wosis_points", country = "FAIL", format = "csv",
                                progress = FALSE),
                    class = "soilhub_job_error")
  expect_identical(e$reason, "failed")
  expect_match(conditionMessage(e), "ended failed: export_failed: ogr2ogr failed", fixed = TRUE)
  expect_s3_class(e$job, "soil_export")
  expect_identical(e$job$status, "failed")

  e <- expect_error(soil_export_status(soil, "exp_20261019_000000_deadbeef"), class = "soilhub_job_error")
  expect_identical(e$reason, "unknown_job")
  expect_match(conditionMessage(e), "is unknown to the API", fixed = TRUE)
  expect_error(soil_export_wait(soil, "exp_20261019_000000_deadbeef", progress = FALSE),
               class = "soilhub_job_error")
  expect_error(soil_export_download(soil, "exp_20261019_000000_deadbeef"), class = "soilhub_job_error")

  clock$waits <- numeric()
  x <- soil_export(soil, datasets = "wosis_points", country = "SLOW", format = "csv", wait = FALSE)
  e <- expect_error(soil_export_wait(soil, x, timeout = 12, poll = 5, progress = FALSE),
                    class = "soilhub_job_error")
  expect_identical(e$reason, "timeout")
  expect_identical(clock$waits, c(5, 5, 2))
  expect_match(conditionMessage(e), "still running after 12 s: it continues on the server", fixed = TRUE)
  # a download before completion
  e <- expect_error(soil_export_download(soil, x), class = "soilhub_job_error")
  expect_identical(e$reason, "not_completed")
})

test_that("an expired export cannot be downloaded (controlled clock)", {
  clock <- local_fake_clock(as.POSIXct("2026-10-19 08:00:00", tz = "UTC"))
  soil <- export_session(api)
  x <- soil_export(soil, datasets = "wosis_points", country = "GONE", format = "csv", progress = FALSE,
                   download = FALSE)
  expect_identical(x$status, "completed")
  dir <- withr::local_tempdir()
  e <- expect_error(soil_export_download(soil, x, dir = dir), class = "soilhub_not_found_error")
  expect_null(e$reason)
  advance_clock(clock, 8 * 86400)
  e <- expect_error(soil_export_download(soil, x, dir = dir), class = "soilhub_not_found_error")
  expect_identical(e$reason, "expired")
  expect_match(conditionMessage(e), "The export expired on 2026-10-26 08:00:00 UTC", fixed = TRUE)
  expect_length(list.files(dir), 0L)  # no partial file left
})

test_that("a selection above the export limit is refused at submission (422)", {
  soil <- export_session(api)
  e <- expect_error(soil_export(soil, datasets = "wosis_points", country = "WORLD"),
                    class = "soilhub_load_limit_error")
  expect_identical(e$status, 422L)
  expect_identical(e$channel, "export")
  expect_identical(e$max_observations, 10000000L)
  expect_identical(e$selection, list(datasets = "wosis_points", country = "WORLD"))
  expect_match(conditionMessage(e), "above the limit of exports (10,000,000): split it", fixed = TRUE)
  expect_false(grepl("too_large", conditionMessage(e)))
  expect_error(soil_export_from_error(soil, e), class = "soilhub_argument_error")
})

test_that("soil_export() validates its arguments before any request", {
  soil <- export_session(api)
  before <- length(submitted_exports(api))
  err <- function(..., argument) {
    e <- expect_error(soil_export(soil, datasets = "wosis_points", ...), class = "soilhub_argument_error")
    expect_identical(e$argument, argument)
  }
  err(format = "shp", argument = "format")
  err(format = "parquet", argument = "format")
  err(content = "everything", argument = "content")
  err(layout = "tall", argument = "layout")
  err(poll = 1, argument = "poll")
  err(timeout = 0, argument = "timeout")
  err(wait = FALSE, download = TRUE, argument = "download")
  err(wait = NA, argument = "wait")
  err(bbox = c(1, 2, 3), argument = "bbox")
  expect_identical(length(submitted_exports(api)), before)
  expect_error(soil_export_status(soil, 42), class = "soilhub_argument_error")
  # shp with features: accepted, no layout sent
  x <- soil_export(soil, datasets = "wosis_points", format = "shp", content = "features", wait = FALSE)
  body <- submitted_exports(api)
  body <- body[[length(body)]]
  expect_identical(body$content, "features")
  expect_null(body$layout)
  expect_true(is.na(x$layout))
})

test_that("soil_export_cancel() needs soil:publish and cancels", {
  local_fake_clock()
  publisher <- write_session(api)
  x <- soil_export(publisher, datasets = "wosis_points", country = "SLOW", format = "csv", wait = FALSE)
  job <- soil_export_cancel(publisher, x)
  expect_s3_class(job, "soil_job")
  expect_identical(job$status, "cancelled")
  expect_true(job$cancel_requested)
  e <- expect_error(soil_export_wait(publisher, x, progress = FALSE), class = "soilhub_job_error")
  expect_identical(e$reason, "cancelled")

  reader <- write_session(api, jwt = "jwt-reader.json")
  e <- expect_error(soil_export_cancel(reader, x), class = "soilhub_permission_error")
  expect_identical(e$required_right, "soil:publish")
  # a reader may export
  expect_s3_class(soil_export(reader, datasets = "wosis_points", format = "csv", wait = FALSE), "soil_export")
})

# ---------------------------------------------------------------------------
# A refused read: too_large = "export" and soil_export_from_error()

test_that("too_large = \"export\": soil_observations() returns the same wide shape via an export", {
  local_fake_clock()
  soil <- export_session(api, dir = withr::local_tempdir())
  e <- expect_error(soil_observations(soil, country = "BRA", progress = FALSE), class = "soilhub_load_limit_error")
  x <- soil_observations(soil, country = "BRA", too_large = "export", progress = FALSE)
  expect_s3_class(x, c("soil_table", "data.frame"), exact = TRUE)
  expect_identical(as.data.frame(x), sync_wide()$frame)
  meta <- soil_metadata(x)
  expect_match(meta$via_export, "^exp_20261019_080000_")
  body <- submitted_exports(api)
  body <- body[[length(body)]]
  expect_identical(body$format, "csv")
  expect_identical(body$layout, "wide")
  expect_identical(body$country, list("BRA"))
  expect_null(body$datasets)
  # offset and max_rows select rows of the export
  y <- soil_observations(soil, country = "BRA", too_large = "export", offset = 1, max_rows = 2, progress = FALSE)
  expect_identical(y$horizon_id, c("h-2", "h-3"))
  expect_identical(rownames(y), c("1", "2"))
  # the geometry of the features, as WKT text (wide)
  z <- soil_observations(soil, country = "BRA", too_large = "export", with_geometry = "text", progress = FALSE)
  expect_identical(z$geometry_text[c(1, 4)], c("POINT (36.8 -1.3)", "POINT (38.25 0.5)"))
  expect_identical(unique(z$geometry_kind), "POINT")
  expect_identical(match("geometry_text", names(z)), match("geometry_kind", names(z)) + 1L)
  expect_identical(match("clay", names(z)), match("geometry_text", names(z)) + 1L)
  skip_if_not_installed("sf")
  s <- soil_observations(soil, country = "BRA", too_large = "export", with_geometry = "sf", progress = FALSE)
  expect_s3_class(s, c("soil_table", "sf", "data.frame"), exact = TRUE)
  expect_identical(sf::st_as_text(sf::st_geometry(s))[5], "POINT (38.25 0.5)")
})

test_that("too_large = \"export\": the long layout, with GeoJSON geometry from a GeoJSON export", {
  local_fake_clock()
  soil <- export_session(api, dir = withr::local_tempdir())
  x <- soil_observations(soil, country = "BRA", layout = "long", too_large = "export", progress = FALSE)
  expect_identical(as.data.frame(x), sync_long())
  expect_identical(soil_metadata(x)$total_count, 17)
  expect_identical(submitted_exports(api)[[length(submitted_exports(api))]]$format, "csv")
  y <- soil_observations(soil, country = "BRA", layout = "long", with_geometry = "text",
                         too_large = "export", progress = FALSE)
  body <- submitted_exports(api)
  expect_identical(body[[length(body)]]$format, "geojson")
  expect_identical(y$geometry_text[1], "{\"type\":\"Point\",\"coordinates\":[36.8,-1.3]}")
  expect_identical(as.data.frame(y), sync_long("text"))
})

test_that("too_large = \"export\": soil_features() returns the features via a GeoJSON export", {
  local_fake_clock()
  soil <- export_session(api, dir = withr::local_tempdir())
  x <- soil_features(soil, country = "BRA", with_geometry = "text", too_large = "export", progress = FALSE)
  expect_identical(as.data.frame(x), sync_features("text"))
  expect_identical(attr(x, "soil_layout"), "features")
  expect_match(soil_metadata(x)$via_export, "^exp_")
  body <- submitted_exports(api)
  body <- body[[length(body)]]
  expect_identical(body$content, "features")
  expect_identical(body$format, "geojson")
  expect_null(body$layout)
  skip_if_not_installed("sf")
  y <- soil_features(soil, country = "BRA", too_large = "export", max_rows = 2, progress = FALSE)
  expect_s3_class(y, "sf")
  expect_identical(nrow(y), 2L)
})

test_that("soil_export_from_error() exports the selection of a refused read", {
  soil <- export_session(api)
  e <- expect_error(soil_observations(soil, country = "BRA", layer = "first", layout = "long", progress = FALSE),
                    class = "soilhub_load_limit_error")
  x <- soil_export_from_error(soil, e, wait = FALSE)
  expect_s3_class(x, "soil_export")
  body <- submitted_exports(api)
  body <- body[[length(body)]]
  expect_identical(body$country, list("BRA"))
  expect_identical(body$layer, "first")
  expect_identical(body$format, "gpkg")
  expect_identical(body$content, "all")
  expect_identical(body$layout, "long")
  # arguments in `...` replace the error's
  soil_export_from_error(soil, e, format = "csv", country = "KEN", layout = "wide", wait = FALSE)
  body <- submitted_exports(api)
  body <- body[[length(body)]]
  expect_identical(body$country, list("KEN"))
  expect_identical(body$layout, "wide")
  expect_identical(body$format, "csv")

  e <- expect_error(soil_features(soil, country = "BRA", with_geometry = "text", progress = FALSE),
                    class = "soilhub_load_limit_error")
  soil_export_from_error(soil, e, format = "shp", wait = FALSE)
  body <- submitted_exports(api)
  body <- body[[length(body)]]
  expect_identical(body$content, "features")
  expect_identical(body$format, "shp")
  expect_null(body$layout)

  expect_error(soil_export_from_error(soil, simpleError("no")), class = "soilhub_argument_error")
})
