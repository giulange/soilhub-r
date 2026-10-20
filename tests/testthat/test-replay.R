# Internal replay of the recorded API responses (R/replay.R), used by the
# vignettes and by the contract suite.

test_that("replay_dir() finds the recorded fixtures from inside the package", {
  dir <- replay_dir(test_path())
  skip_if(is.null(dir), "no recorded fixtures")
  expect_true(file.exists(file.path(dir, "manifest.json")))
  expect_null(replay_dir(tempdir()))
})

test_that("a replay session answers recorded requests and refuses the others", {
  skip_if_not_installed("webfakes")
  dir <- replay_dir(test_path())
  skip_if(is.null(dir), "no recorded fixtures")
  soil <- replay_session(dir, set_default = FALSE)
  on.exit(replay_stop(soil), add = TRUE)
  expect_s3_class(soil, "soil_session")
  expect_identical(soil_formats(soil), c("geojson", "gpkg", "csv", "tsv", "shp"))
  x <- soil_observations(soil, datasets = "wosis_points", bbox = c(-123.3, 49.0, -122.9, 49.4),
                         max_rows = 5, progress = FALSE)
  expect_identical(nrow(x), 5L)
  expect_error(soil_dataset(soil, "not_recorded"), class = "soilhub_api_error")
})

test_that("replay_session() needs recorded fixtures", {
  expect_error(replay_session(tempdir()), class = "soilhub_argument_error")
})
