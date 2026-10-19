# Source ingest (design 4.6, WP9): bundle from sf or GeoJSON, manifest,
# upload never retried (2.4), validate, staged-count verification, promote,
# wait; local checks of source_record_id, parents and CRS before any
# request; keep_file; rights pre-check and 403 mapping (1.3); sf optional
# (decision 6).

api <- fake_source_api()

upload_of <- function(job_id) fake_upload(api, job_id)
sent_records <- function(upload) {
  lines <- strsplit(upload$text, "\n", fixed = TRUE)[[1]]
  lapply(lines, jsonlite::fromJSON, simplifyVector = FALSE)
}
no_kept_bundles <- function() {
  expect_length(list.files(tempdir(), pattern = "^soilhub-source-.*\\.ndjson$"), 0L)
}

# ---------------------------------------------------------------------------
# Round trip

test_that("a source release round trip: bundle, upload, validate, promote", {
  fake_control(api, "reset")
  soil <- write_session(api)
  out <- publish_fixture(soil, "campania-1")

  expect_s3_class(out, "soil_source_ingest")
  expect_identical(out$status, "completed")
  expect_false(out$auto_promote)
  counts <- c(feature = 2, profile = 2, component = 2, horizon = 3, observation = 4)
  expect_identical(out$record_counts, counts)
  expect_identical(out$staged_counts, counts)
  expect_identical(out$record_count, 13L)
  expect_identical(out$published_count, 13)
  expect_identical(out$release_id, 31)
  expect_match(out$receipt_id, "^0{8}-")
  expect_s3_class(out$validation, "soil_source_validation")
  expect_true(out$validation$valid)
  expect_identical(nrow(out$validation$errors), 0L)
  expect_identical(out$unmapped_property_codes, character())
  expect_null(out$file)
  no_kept_bundles()

  id <- out$job_id
  expect_identical(fake_log(api), c(
    "POST /api/v1/source-ingests", paste0("POST /api/v1/source-ingests/", id, "/validate"),
    paste0("GET /api/v1/jobs/", id), paste0("POST /api/v1/source-ingests/", id, "/promote")
  ))

  # the multipart form: manifest and parameters as fields, then the file
  upload <- upload_of(id)
  expect_match(upload$content_type, "^multipart/form-data")
  expect_identical(upload$form$idempotency_key, "campania-1")
  expect_identical(upload$form$input_format, "ndjson")
  expect_identical(upload$form$auto_promote, "false")
  expect_identical(upload$form$expected_checksum, out$checksum_sha256)
  expect_identical(out$checksum_sha256, as.vector(as.character(openssl::sha256(charToRaw(upload$text)))))
  expect_equal(out$byte_size, nchar(upload$text, type = "bytes"))
  manifest <- jsonlite::fromJSON(upload$form$manifest, simplifyVector = FALSE)
  expect_identical(manifest$dataset_code, "campania_profiles")
  expect_identical(manifest$default_geometry_kind, "POINT")
  expect_identical(manifest$assets, list(list(asset_role = "profiles_table",
                                              source_url = "https://example.org/campania.csv")))

  # the bundle: one record per line, in hierarchy order, features in WGS84
  records <- sent_records(upload)
  expect_length(records, 13L)
  expect_identical(vapply(records, `[[`, "", "record_type"),
                   rep(names(counts), counts))
  first <- records[[1]]
  expect_identical(names(first), c("record_type", "source_record_id", "site_name", "geometry_kind", "geometry"))
  expect_identical(first$geometry_kind, "POINT")
  expect_identical(first$geometry$type, "Point")
  expected <- sf::st_coordinates(sf::st_transform(source_features_fixture(), 4326))
  expect_equal(unlist(first$geometry$coordinates), unname(expected[1, ]), tolerance = 1e-9)
  expect_null(first$geometry$crs)
  expect_identical(records[[5]], list(record_type = "component", source_record_id = "P1-c",
                                      profile_source_id = "P1", component_rank = 1L,
                                      proportion_percent = 100L))
  observation <- records[[13]]
  expect_identical(observation[c("record_type", "source_record_id", "horizon_source_id", "property_code",
                                 "unit", "status")],
                   list(record_type = "observation", source_record_id = "o4", horizon_source_id = "P2-1",
                        property_code = "clay", unit = "%", status = "observed"))

  expect_output(print(out), "completed (promoted by the client)", fixed = TRUE)
  expect_output(print(out), "Records:   feature 2, profile 2, component 2, horizon 3, observation 4 (sent 13)", fixed = TRUE)
  expect_output(print(out), "Published: 13, release 31", fixed = TRUE)
})

test_that("polygons, multipolygons and numeric ids travel as GeoJSON and text", {
  skip_if_not_installed("sf")
  fake_control(api, "reset")
  soil <- write_session(api)
  square <- sf::st_polygon(list(rbind(c(0, 0), c(1, 0), c(1, 1), c(0, 0))))
  multi <- sf::st_multipolygon(list(list(rbind(c(2, 2), c(3, 2), c(3, 3), c(2, 2)))))
  features <- sf::st_sf(source_record_id = c(101, 102), geometry = sf::st_sfc(square, multi, crs = 4326))
  manifest <- source_manifest_fixture(support_type = "polygon_estimate", default_geometry_kind = "multipolygon")
  out <- soil_publish_source(soil, manifest, features, idempotency_key = "polygons", progress = FALSE)
  records <- sent_records(upload_of(out$job_id))
  expect_identical(records[[1]]$source_record_id, "101")
  expect_identical(records[[1]]$geometry_kind, "POLYGON")
  expect_identical(records[[1]]$geometry$coordinates[[1]][[2]], list(1L, 0L))
  expect_identical(records[[2]]$geometry_kind, "MULTIPOLYGON")
  expect_length(records[[2]]$geometry$coordinates[[1]][[1]], 4L)
  manifest <- jsonlite::fromJSON(upload_of(out$job_id)$form$manifest, simplifyVector = FALSE)
  expect_identical(manifest$default_geometry_kind, "MULTIPOLYGON")
})

# ---------------------------------------------------------------------------
# Local checks: nothing is sent

test_that("source_record_id, parents and observations are checked before any request", {
  skip_if_not_installed("sf")
  fake_control(api, "reset")
  soil <- write_session(api)
  tables <- source_tables_fixture()
  features <- source_features_fixture()
  features$source_record_id <- c("P1", "P1")
  tables$horizons$source_record_id[2] <- NA
  tables$observations$horizon_source_id[1] <- "P9-1"
  tables$observations$unit[2] <- NA
  tables$observations$status[3] <- "estimated"
  tables$profiles$feature_source_id <- NULL

  err <- tryCatch(publish_fixture(soil, "k", features = features, tables = tables),
                  soilhub_argument_error = function(e) e)
  expect_s3_class(err, "soilhub_argument_error")
  expect_match(conditionMessage(err), "of the 13 record(s) of the source bundle fail the local checks; nothing was sent.", fixed = TRUE)
  errors <- err$errors
  expect_identical(names(errors), c("record_type", "row", "source_record_id", "errors"))
  expect_identical(errors$record_type[1:2], c("feature", "feature"))
  expect_identical(errors$errors[1:2], rep("duplicate_source_record_id", 2))
  expect_identical(errors$errors[errors$record_type == "profile"], rep("missing_feature_source_id", 2))
  horizon <- errors[errors$record_type == "horizon", ]
  expect_identical(horizon$row, 2L)
  expect_identical(horizon$errors, "missing_source_record_id")
  observations <- errors[errors$record_type == "observation", ]
  expect_identical(observations$row, 1:3)
  # o2 belongs to the horizon without an id
  expect_identical(observations$errors, c("parent_not_found", "parent_not_found, missing_unit_declaration",
                                          "invalid_observation_status"))
  expect_length(fake_log(api), 0L)

  # a child of an unknown parent: horizons of a component not sent
  tables <- source_tables_fixture()
  tables$components <- NULL
  err <- tryCatch(publish_fixture(soil, "k", tables = tables), soilhub_argument_error = function(e) e)
  expect_identical(unique(err$errors$errors), "parent_not_found")
  expect_identical(err$argument, "horizons")
  expect_length(fake_log(api), 0L)
})

test_that("the CRS and the geometry are checked before any request", {
  skip_if_not_installed("sf")
  fake_control(api, "reset")
  soil <- write_session(api)
  features <- sf::st_set_crs(source_features_fixture(), NA)
  err <- tryCatch(publish_fixture(soil, "k", features = features), soilhub_argument_error = function(e) e)
  expect_identical(err$argument, "features")
  expect_match(conditionMessage(err), "`features` has no CRS: set the CRS of its coordinates with sf::st_set_crs()", fixed = TRUE)

  line <- sf::st_linestring(rbind(c(14, 40), c(15, 41)))
  odd <- sf::st_sf(source_record_id = c("L1", "E1"),
                   geometry = sf::st_sfc(line, sf::st_point(), crs = 4326))
  err <- tryCatch(soil_publish_source(soil, source_manifest_fixture(), odd, idempotency_key = "k"),
                  soilhub_argument_error = function(e) e)
  expect_identical(err$errors$errors, c("unsupported_geometry_type_LINESTRING", "empty_geometry"))

  # a plain data frame is a non-spatial feature table only
  plain <- data.frame(source_record_id = c("P1", "P2"), lon = 14, lat = 40)
  err <- tryCatch(soil_publish_source(soil, source_manifest_fixture(), plain, idempotency_key = "k"),
                  soilhub_argument_error = function(e) e)
  expect_match(conditionMessage(err), "only for a non-spatial dataset", fixed = TRUE)
  expect_error(soil_publish_source(soil, source_manifest_fixture(default_geometry_kind = "NONE"), plain[0, ],
                                   idempotency_key = "k"),
               "`features` holds no feature", class = "soilhub_argument_error")
  expect_error(soil_publish_source(soil, source_manifest_fixture(), "missing.gpkg", idempotency_key = "k"),
               "does not exist", class = "soilhub_argument_error")
  expect_length(fake_log(api), 0L)
})

test_that("the manifest is checked locally; property_mappings is flagged", {
  fake_control(api, "reset")
  soil <- write_session(api)
  manifest <- source_manifest_fixture(dataset_code = "Campania", support_type = "points",
                                      release_checksum_sha256 = "abc")
  manifest$release_code <- NULL
  err <- tryCatch(soil_publish_source(soil, manifest, "x.geojson", idempotency_key = "k"),
                  soilhub_argument_error = function(e) e)
  expect_identical(err$argument, "manifest")
  expect_identical(err$problems, c(
    "`release_code` is required (a non-empty string)",
    "`dataset_code` \"Campania\" may hold only lowercase letters, digits and `_`",
    "`support_type` \"points\" is not one of \"observed_point_profile\", \"polygon_estimate\", \"map_unit_profile_relation\", \"non_spatial_profile\", \"non_spatial_estimate\"",
    "`release_checksum_sha256` must be 64 lowercase hexadecimal characters"
  ))
  expect_error(soil_publish_source(soil, list("a"), "x.geojson", idempotency_key = "k"),
               class = "soilhub_argument_error")
  bad_asset <- source_manifest_fixture()
  bad_asset$assets <- list(list(asset_role = "table"))
  err <- tryCatch(soil_publish_source(soil, bad_asset, "x.geojson", idempotency_key = "k"),
                  soilhub_argument_error = function(e) e)
  expect_identical(err$problems, "asset 1: `source_url` is required")
  expect_length(fake_log(api), 0L)

  # fact 12.2.14: the API manifest has no property_mappings
  manifest <- source_manifest_fixture(property_mappings = list(list(source = "orgc", variable = "organic_carbon")))
  expect_warning(
    out <- soil_publish_source(soil, manifest, test_path("fixtures", "source-features.geojson"),
                               idempotency_key = "mappings", progress = FALSE),
    "is not read by the API", class = "soilhub_manifest_warning"
  )
  expect_identical(out$status, "completed")
})

# ---------------------------------------------------------------------------
# Server validation, staged counts, promotion

test_that("the staged counts are verified and nothing is promoted when they differ", {
  fake_control(api, "reset")
  soil <- write_session(api)
  err <- tryCatch(publish_fixture(soil, "campania-drop"), soilhub_api_error = function(e) e)
  expect_identical(err$code, "staged_count_mismatch")
  expect_match(conditionMessage(err), "observation 4 sent, 3 staged; staged 12 for 13 record(s) sent", fixed = TRUE)
  expect_match(conditionMessage(err), "nothing was promoted", fixed = TRUE)
  expect_identical(err$staged_counts[["observation"]], 3)
  expect_false(any(grepl("/promote$", fake_log(api))))
})

test_that("a rejected bundle is a validation error naming the records", {
  fake_control(api, "reset")
  soil <- write_session(api)
  err <- tryCatch(publish_fixture(soil, "campania-reject"), soilhub_validation_error = function(e) e)
  expect_s3_class(err, "soilhub_api_error")
  expect_identical(err$code, "validation_failed")
  expect_identical(err$errors$record_number, 3L)
  expect_identical(err$errors$record_type, "profile")
  expect_identical(err$errors$row, 1L)
  expect_identical(err$errors$source_record_id, "P1")
  expect_identical(err$errors$errors, "parent_not_found")
  expect_match(conditionMessage(err), "1 of 13 record(s) fail validation; nothing was promoted", fixed = TRUE)
  expect_false(any(grepl("/promote$", fake_log(api))))
})

test_that("unmapped property codes are a warning; published counts are reconciled", {
  fake_control(api, "reset")
  soil <- write_session(api)
  tables <- source_tables_fixture()
  tables$observations$property_code[4] <- "phaq"
  expect_warning(
    out <- publish_fixture(soil, "campania-unmapped", tables = tables),
    "`phaq`", class = "soilhub_unmapped_properties_warning"
  )
  expect_identical(out$unmapped_property_codes, "phaq")
  expect_output(print(out), "Unmapped:  phaq", fixed = TRUE)

  expect_warning(
    out <- publish_fixture(soil, "campania-short"),
    "observation 4 sent, 3 promoted; 12 published for 13 record(s) sent",
    class = "soilhub_reconciliation_warning", fixed = TRUE
  )
  expect_identical(out$published_count, 12)
})

test_that("a refused promotion is a conflict that explains the way out", {
  fake_control(api, "reset")
  soil <- write_session(api)
  err <- tryCatch(publish_fixture(soil, "campania-taken", manifest = source_manifest_fixture(release_code = "taken")),
                  soilhub_conflict_error = function(e) e)
  expect_match(conditionMessage(err), "release_code already exists", fixed = TRUE)
  expect_match(conditionMessage(err), "releases are immutable: use a new release_code", fixed = TRUE)
})

test_that("auto_promote: the server validates and promotes, the client waits", {
  local_fake_clock()
  fake_control(api, "reset")
  soil <- write_session(api)
  out <- publish_fixture(soil, "campania-auto", auto_promote = TRUE, poll = 2)
  expect_identical(out$status, "completed")
  expect_true(out$auto_promote)
  expect_identical(out$release_id, 31)
  expect_identical(out$staged_counts, out$record_counts)
  expect_true(out$validation$valid)
  id <- out$job_id
  expect_identical(fake_log(api), c("POST /api/v1/source-ingests", rep(paste0("GET /api/v1/jobs/", id), 3)))
  expect_identical(upload_of(id)$form$auto_promote, "true")
  expect_output(print(out), "promoted by the server", fixed = TRUE)

  # a failed job carries the rejected records
  err <- tryCatch(publish_fixture(soil, "campania-auto-reject", auto_promote = TRUE),
                  soilhub_job_error = function(e) e)
  expect_identical(err$reason, "failed")
  expect_identical(err$errors$record_type, "profile")
  expect_match(conditionMessage(err), "record_number 3, record_type profile, row 1", fixed = TRUE)
})

test_that("a busy ingest worker: validation waits for it", {
  sleep <- local_fake_sleep()
  fake_control(api, "reset")
  soil <- write_session(api)
  out <- publish_fixture(soil, "campania-busy", poll = 3)
  expect_identical(out$status, "completed")
  id <- out$job_id
  validate <- paste0("POST /api/v1/source-ingests/", id, "/validate")
  get <- paste0("GET /api/v1/jobs/", id)
  expect_identical(fake_log(api), c(
    "POST /api/v1/source-ingests", validate, get, validate, get, validate, get,
    paste0("POST /api/v1/source-ingests/", id, "/promote")
  ))
  expect_identical(sleep$waits, 3)
})

test_that("wait = FALSE returns the job; validation and promotion as separate steps", {
  fake_control(api, "reset")
  soil <- write_session(api)
  queued <- publish_fixture(soil, "campania-later", wait = FALSE)
  expect_identical(queued$status, "queued")
  expect_null(queued$validation)
  expect_identical(fake_log(api), "POST /api/v1/source-ingests")

  report <- soil_source_validate(soil, queued$job_id)
  expect_s3_class(report, "soil_source_validation")
  expect_true(report$valid)
  expect_identical(report$counts[["horizon"]], 3)
  expect_output(print(report), "valid", fixed = TRUE)
  job <- soil_source_promote(soil, queued$job_id)
  expect_s3_class(job, "soil_job")
  expect_identical(job$status, "completed")
  expect_identical(job$diagnostics$release_id, 31L)

  # the same key and file after the end: the completed job is returned
  replay <- publish_fixture(soil, "campania-later")
  expect_identical(replay$job_id, queued$job_id)
  expect_identical(replay$status, "completed")

  # an invalid job: the report says so, the promotion is refused
  rejected <- publish_fixture(soil, "campania-reject-later", wait = FALSE)
  report <- soil_source_validate(soil, rejected$job_id)
  expect_false(report$valid)
  expect_identical(report$errors$errors, "parent_not_found")
  expect_output(print(report), "Rejected: 1 record(s)", fixed = TRUE)
  err <- tryCatch(soil_source_promote(soil, rejected$job_id), soilhub_conflict_error = function(e) e)
  expect_match(conditionMessage(err), "cannot be promoted from status failed", fixed = TRUE)
  err <- tryCatch(publish_fixture(soil, "campania-reject-later"), soilhub_job_error = function(e) e)
  expect_match(conditionMessage(err), "ended failed: submit the corrected bundle with a new idempotency_key", fixed = TRUE)
})

# ---------------------------------------------------------------------------
# keep_file, uploads, rights, capability, sf

test_that("keep_file keeps the bundle and returns its path", {
  fake_control(api, "reset")
  soil <- write_session(api)
  out <- publish_fixture(soil, "campania-keep", keep_file = TRUE)
  withr::defer(unlink(out$file))
  expect_true(file.exists(out$file))
  expect_match(basename(out$file), "^soilhub-source-.*\\.ndjson$")
  expect_identical(sha256_file(out$file), out$checksum_sha256)
  expect_identical(readChar(out$file, file.size(out$file), useBytes = TRUE), upload_of(out$job_id)$text)
  expect_output(print(out), paste0("kept at ", out$file), fixed = TRUE)

  # kept also when the API refuses it
  err <- tryCatch(publish_fixture(soil, "campania-keep-reject", keep_file = TRUE),
                  soilhub_validation_error = function(e) e)
  kept <- list.files(tempdir(), pattern = "^soilhub-source-.*\\.ndjson$", full.names = TRUE)
  expect_length(kept, 2L)
  unlink(setdiff(kept, out$file))
})

test_that("an upload is never retried; a key holds one file", {
  fake_control(api, "reset")
  soil <- write_session(api)
  err <- tryCatch(publish_fixture(soil, "flaky"), soilhub_unavailable_error = function(e) e)
  expect_identical(err$status, 503L)
  expect_identical(err$attempts, 1L)
  expect_identical(fake_log(api), "POST /api/v1/source-ingests")
  no_kept_bundles()

  publish_fixture(soil, "campania-once", wait = FALSE)
  tables <- source_tables_fixture()
  tables$observations$value[1] <- 99
  err <- tryCatch(publish_fixture(soil, "campania-once", tables = tables), soilhub_conflict_error = function(e) e)
  expect_match(conditionMessage(err), "idempotency key was already used with a different file", fixed = TRUE)
  expect_match(conditionMessage(err), "a new bundle needs a new key", fixed = TRUE)
})

test_that("rights are pre-checked; a 403 is mapped to soil:publish", {
  fake_control(api, "reset")
  reader <- write_session(api, "jwt-reader.json")
  calls <- list(
    soil_publish_source = function() publish_fixture(reader, "k"),
    soil_source_validate = function() soil_source_validate(reader, "job-1"),
    soil_source_promote = function() soil_source_promote(reader, "job-1")
  )
  for (name in names(calls)) {
    err <- tryCatch(calls[[name]](), soilhub_permission_error = function(e) e)
    expect_identical(err$required_right, "soil:publish")
    expect_true(name %in% .rights[["soil:publish"]])
    expect_match(conditionMessage(err), sprintf("`%s()` needs the right `soil:publish`", name), fixed = TRUE)
  }
  expect_length(fake_log(api), 0L)

  fake_control(api, "deny")
  undeclared <- write_session(api, "jwt-noroles.json")
  err <- tryCatch(publish_fixture(undeclared, "k"), soilhub_permission_error = function(e) e)
  expect_identical(err$status, 403L)
  expect_identical(err$required_right, "soil:publish")
  expect_identical(err$endpoint, "/source-ingests")
  err <- tryCatch(soil_source_promote(undeclared, "job-1"), soilhub_permission_error = function(e) e)
  expect_identical(err$endpoint, "/source-ingests/job-1/promote")
  expect_identical(fake_log(api), c("POST /api/v1/source-ingests", "POST /api/v1/source-ingests/job-1/promote"))
  fake_control(api, "reset")
})

test_that("the source_ingest capability is checked before any request", {
  fake_control(api, "reset")
  capabilities <- read_fixture("capabilities.json")
  capabilities$capabilities$source_ingest <- FALSE
  soil <- write_session(api, capabilities = capabilities)
  expect_error(publish_fixture(soil, "k"), class = "soilhub_capability_error")
  expect_error(soil_source_validate(soil, "job-1"), class = "soilhub_capability_error")
  expect_length(fake_log(api), 0L)
})

test_that("without sf: a GeoJSON file is ingested, sf objects and other files need sf", {
  local_mocked_bindings(source_sf_available = function() FALSE)
  fake_control(api, "reset")
  soil <- write_session(api)
  path <- test_path("fixtures", "source-features.geojson")
  out <- soil_publish_source(soil, source_manifest_fixture(), path, idempotency_key = "geojson", progress = FALSE)
  expect_identical(out$status, "completed")
  records <- sent_records(upload_of(out$job_id))
  expect_identical(records[[1]], list(
    record_type = "feature", source_record_id = "P1", site_name = "Portici",
    geometry_kind = "POINT", geometry = list(type = "Point", coordinates = list(14.3712, 40.8031))
  ))
  expect_identical(records[[2]]$geometry_kind, "POLYGON")
  expect_null(records[[2]]$note)

  skip_if_not_installed("sf")
  err <- tryCatch(publish_fixture(soil, "k"), soilhub_dependency_error = function(e) e)
  expect_identical(err$package, "sf")
  expect_match(conditionMessage(err), "An `sf` object as `features` needs the package 'sf'", fixed = TRUE)
  gpkg <- withr::local_tempfile(fileext = ".gpkg")
  writeLines("x", gpkg)
  expect_error(soil_publish_source(soil, source_manifest_fixture(), gpkg, idempotency_key = "k"),
               "Reading `features` from a .gpkg file needs the package 'sf'",
               class = "soilhub_dependency_error", fixed = TRUE)
  legacy <- withr::local_tempfile(fileext = ".geojson")
  json <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  json$crs <- list(type = "name", properties = list(name = "urn:ogc:def:crs:EPSG::32633"))
  jsonlite::write_json(json, legacy, auto_unbox = TRUE, digits = NA)
  expect_error(soil_publish_source(soil, source_manifest_fixture(), legacy, idempotency_key = "k"),
               "A GeoJSON file in the CRS urn:ogc:def:crs:EPSG::32633 needs the package 'sf'",
               class = "soilhub_dependency_error", fixed = TRUE)
  expect_identical(fake_log(api), c("POST /api/v1/source-ingests",
                                    paste0("POST /api/v1/source-ingests/", out$job_id, "/validate"),
                                    paste0("GET /api/v1/jobs/", out$job_id),
                                    paste0("POST /api/v1/source-ingests/", out$job_id, "/promote")))
})

test_that("a GeoJSON file in another CRS is read and transformed with sf", {
  skip_if_not_installed("sf")
  fake_control(api, "reset")
  soil <- write_session(api)
  legacy <- withr::local_tempfile(fileext = ".geojson")
  sf::st_write(source_features_fixture(), legacy, driver = "GeoJSON", quiet = TRUE,
               layer_options = "RFC7946=NO")
  out <- soil_publish_source(soil, source_manifest_fixture(), legacy, idempotency_key = "legacy", progress = FALSE)
  first <- sent_records(upload_of(out$job_id))[[1]]
  expected <- sf::st_coordinates(sf::st_transform(source_features_fixture(), 4326))
  expect_equal(unlist(first$geometry$coordinates), unname(expected[1, ]), tolerance = 1e-6)
})
