# soil_features() (design 4.4, 5.5; decision 6) against the fake features
# API (helper-fake-long.R).

api <- fake_long_api()

test_that("features as text: GeoJSON, the body sent, the paging", {
  soil <- wide_session(api)
  x <- soil_features(soil, datasets = "wosis_points", country = "KEN", with_geometry = "text",
                     page_size = 2, progress = FALSE)
  expect_s3_class(x, c("soil_table", "data.frame"), exact = TRUE)
  expect_identical(attr(x, "soil_layout"), "features")
  expect_identical(x$feature_id, c("f-1", "f-2", "f-3"))
  expect_identical(x$geometry_text[[3]], "{\"type\":\"Point\",\"coordinates\":[38.25,0.5]}")
  expect_identical(x$retired_in_release, c(NA, NA, "2026-10-01_isric"))
  meta <- soil_metadata(x)
  expect_identical(meta$pages, 2L)
  expect_true(meta$complete)
  expect_identical(meta$endpoint, "/query/features")
  expect_identical(meta$feature_count, 3L)
  expect_null(meta$feature_count_by_dataset)
  expect_false(meta$mixed_geometry)
  expect_true(is.na(meta$total_count))
  expect_identical(meta$crs, "EPSG:4326")
  expect_identical(meta$datasets$name, "wosis_points")
  expect_identical(soil_citations(x)$dataset, "wosis_points")
  sent <- meta$filters
  expect_true(sent$canonical)
  expect_identical(sent$view, "raw")
  expect_identical(sent$datasets, list("wosis_points"))
  expect_null(sent$layer)
  expect_null(sent$layout)
  expect_null(sent$geometry_format)
  expect_null(sent$include_geometry)
  expect_identical(sent$limit, 2L)
  expect_identical(meta$selection, list(datasets = "wosis_points", country = "KEN"))
})

test_that("features as sf (the default): points and polygons, components", {
  skip_if_not_installed("sf")
  soil <- wide_session(api)
  x <- soil_features(soil, datasets = c("sotwis_polygons", "soter_profiles"), progress = FALSE)
  expect_s3_class(x, c("soil_table", "sf", "data.frame"), exact = TRUE)
  expect_identical(attr(x, "sf_column"), "geometry")
  expect_identical(sf::st_crs(x)$epsg, 4326L)
  expect_identical(as.character(sf::st_geometry_type(x)), x$geometry_kind)
  expect_identical(x$components[[2]]$component_id, "c-3")
  expect_identical(x$profile_markings[[4]], "no_horizons_in_source")
  meta <- soil_metadata(x)
  expect_true(meta$mixed_geometry)
  expect_identical(meta$feature_count_by_dataset, list(soter_profiles = 2L, sotwis_polygons = 2L))
  expect_true("Mixed POINT and MULTIPOLYGON geometries" %in% soil_warnings(x))
  sub <- x[x$dataset == "soter_profiles", ]
  expect_s3_class(sub, c("soil_table", "sf", "data.frame"), exact = TRUE)
  expect_identical(nrow(sub), 2L)
  expect_identical(attr(sub, "soil_layout"), "features")
})

test_that("features without geometry get NA or an empty geometry, with one warning", {
  soil <- wide_session(api)
  expect_warning(
    x <- soil_features(soil, datasets = "wise_profiles", with_geometry = "text", progress = FALSE),
    "1 row\\(s\\) of 1 feature\\(s\\) have no geometry.*geometry_text is NA", class = "soilhub_geometry_warning"
  )
  expect_identical(is.na(x$geometry_text), c(TRUE, FALSE))
  skip_if_not_installed("sf")
  expect_warning(
    y <- soil_features(soil, datasets = "wise_profiles", progress = FALSE),
    "their geometry is empty", class = "soilhub_geometry_warning"
  )
  expect_identical(sf::st_is_empty(y$geometry), c(TRUE, FALSE))
  expect_s3_class(y$geometry, "sfc_POINT")
})

test_that("without sf the default stops before any request with a dependency error", {
  local_mocked_bindings(soil_has_package = function(package) FALSE)
  soil <- wide_session(api)
  before <- api_requests(api)
  e <- expect_error(soil_features(soil, datasets = "wosis_points"), class = "soilhub_dependency_error")
  expect_identical(e$package, "sf")
  expect_match(conditionMessage(e), "`soil_features()` with `with_geometry = \"sf\"`", fixed = TRUE)
  expect_identical(api_requests(api), before)
  x <- soil_features(soil, datasets = "wosis_points", with_geometry = "text", progress = FALSE)
  expect_identical(nrow(x), 3L)
})

test_that("argument, right and capability errors come before any request", {
  soil <- wide_session(api)
  before <- api_requests(api)
  bad <- list(
    list(with_geometry = "wkt"), list(view = "fixed"), list(bbox = c(1, 1, 0, 0)),
    list(max_rows = 0), list(page_size = 0), list(too_large = "split"), list(progress = NA),
    list(components = "cumulative")
  )
  for (args in bad) {
    call_args <- utils::modifyList(list(soil, datasets = "wosis_points", with_geometry = "text"), args)
    e <- expect_error(do.call(soil_features, call_args), class = "soilhub_argument_error")
    expect_false(is.null(e$argument))
  }
  reader <- wide_session(api)
  reader$state$identity <- list(rights_known = TRUE, roles = "soil:summary", audience = "soil-api")
  e <- expect_error(soil_features(reader, datasets = "wosis_points", with_geometry = "text"),
                    class = "soilhub_permission_error")
  expect_identical(e$required_right, "soil:read")
  old <- wide_session(api, capabilities = capabilities_with(canonical_features = FALSE))
  e <- expect_error(soil_features(old, datasets = "wosis_points", with_geometry = "text"),
                    class = "soilhub_capability_error")
  expect_identical(e$capability, "canonical_features")
  expect_identical(api_requests(api), before)
})

test_that("a failure after some feature pages keeps them as a typed partial", {
  soil <- wide_session(api)
  e <- expect_error(
    soil_features(soil, datasets = "wosis_points", country = "FAIL", with_geometry = "text",
                  progress = FALSE),
    class = "soilhub_api_error"
  )
  expect_identical(e$status, 500L)
  expect_s3_class(e$partial, "soil_table")
  expect_identical(attr(e$partial, "soil_layout"), "features")
  expect_identical(e$partial$feature_id, c("f-1", "f-2"))
  expect_false(soil_metadata(e$partial)$complete)
  expect_identical(soil_metadata(e$partial)$next_offset, 2)
})

test_that("max_rows bounds the read", {
  soil <- wide_session(api)
  x <- soil_features(soil, datasets = "wosis_points", with_geometry = "text", max_rows = 1,
                     progress = FALSE)
  expect_identical(nrow(x), 1L)
  expect_false(soil_metadata(x)$complete)
})

test_that("a refused selection names the export of the features", {
  soil <- wide_session(api)
  e <- expect_error(soil_features(soil, country = "BRA", with_geometry = "text", progress = FALSE),
                    class = "soilhub_load_limit_error")
  expect_identical(e$selection, list(country = "BRA"))
  expect_match(conditionMessage(e),
               "soil_export(soil, country = \"BRA\", content = \"features\", format = \"gpkg\")", fixed = TRUE)
  # too_large = "export" is tested end to end in test-exports.R
})
