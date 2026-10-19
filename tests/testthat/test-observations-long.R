# soil_observations(layout = "long") and with_geometry (design 4.4, 5.3,
# 5.4; decision 6) against the fake long API (helper-fake-long.R); the wide
# side of the equivalence against the fake wide API (helper-fake-wide.R).

api <- fake_long_api()
wide_api <- fake_wide_api()

test_that("a long read sends layout long, pages to the end and keeps the exact total", {
  soil <- wide_session(api)
  x <- soil_observations(soil, datasets = "wosis_points", country = "KEN", layout = "long",
                         progress = FALSE)
  expect_s3_class(x, c("soil_table", "data.frame"), exact = TRUE)
  expect_identical(attr(x, "soil_layout"), "long")
  expect_identical(nrow(x), 17L)
  meta <- soil_metadata(x)
  expect_identical(meta$pages, 2L)
  expect_true(meta$complete)
  expect_identical(meta$total_count, 17)
  expect_true(all(grepl(request_id_pattern, meta$request_ids)))
  sent <- meta$filters
  expect_identical(sent$layout, "long")
  expect_null(sent$geometry_format)
  expect_null(sent$include_geometry)
  expect_true(sent$canonical)
  expect_identical(sent$view, "raw")
  expect_identical(meta$request$layout, "long")
  expect_identical(meta$selection, list(datasets = "wosis_points", country = "KEN"))
  expect_identical(meta$datasets$name, "wosis_points")
  expect_identical(meta$multi_value_rule, "mean")
  expect_null(meta$variables)
  expect_false("geometry" %in% names(x))
  expect_true(all(is.na(x$geometry_kind)))
  expect_equal(x$value[[1]], 1)
  out <- capture.output(print(x))
  expect_identical(out[1], "# soilhub long table: 17 observations, 3 features | wosis_points | view raw, layer all | 17 in the selection")
  expect_identical(out[2], "# no API warnings (soil_warnings), markings (soil_markings), cite with soil_citations()")
  s <- summary(x)
  expect_null(s$columns)
  expect_identical(s$datasets$rows, 17L)
})

test_that("wide and long reads of the same selection are equivalent (acceptance 10.4)", {
  wide <- soil_observations(wide_session(wide_api), datasets = "wosis_points", progress = FALSE)
  long <- soil_observations(wide_session(api), datasets = "wosis_points", layout = "long", progress = FALSE)
  expect_identical(wide_long_mismatches(wide, long), character())
  # same horizons, same features
  expect_setequal(unique(long$horizon_id), wide$horizon_id)
  expect_setequal(unique(long$feature_id), unique(wide$feature_id))
})

test_that("with_geometry = \"text\" asks for include_geometry and returns GeoJSON", {
  soil <- wide_session(api)
  x <- soil_observations(soil, datasets = "wosis_points", layout = "long", with_geometry = "text",
                         progress = FALSE)
  meta <- soil_metadata(x)
  expect_true(meta$filters$include_geometry)
  expect_null(meta$filters$geometry_format)
  expect_true("Observation geometry increases response payload size" %in% soil_warnings(x))
  expect_identical(x$geometry_text[[17]], "{\"type\":\"Point\",\"coordinates\":[38.25,0.5]}")
  expect_identical(unique(x$geometry_kind), "POINT")
  expect_false("geometry" %in% names(x))
})

test_that("with_geometry = \"sf\" returns an sf soil_table (long and wide)", {
  skip_if_not_installed("sf")
  soil <- wide_session(api)
  x <- soil_observations(soil, datasets = "wosis_points", layout = "long", with_geometry = "sf",
                         progress = FALSE)
  expect_s3_class(x, c("soil_table", "sf", "data.frame"), exact = TRUE)
  expect_identical(attr(x, "sf_column"), "geometry")
  expect_identical(sf::st_crs(x)$epsg, 4326L)
  expect_identical(nrow(x), 17L)
  expect_false("geometry_text" %in% names(x))
  expect_equal(unname(sf::st_coordinates(x)[17, ]), c(38.25, 0.5))
  # wide: WKT asked once per feature, turned into the geometry column
  w <- soil_observations(wide_session(wide_api), datasets = "wosis_points", with_geometry = "sf",
                         progress = FALSE)
  expect_identical(soil_metadata(w)$filters$geometry_format, "wkt")
  expect_s3_class(w, c("soil_table", "sf", "data.frame"), exact = TRUE)
  expect_false("geometry_text" %in% names(w))
  expect_identical(match("geometry", names(w)), match("clay", names(w)) - 1L)
  expect_s3_class(w$geometry, "sfc_POINT")
  expect_equal(unname(sf::st_coordinates(w)[4, ]), c(38.25, 0.5))
  expect_identical(nrow(soil_flags(w)), 4L)
})

test_that("without sf, with_geometry = \"sf\" stops before any request; text works", {
  local_mocked_bindings(soil_has_package = function(package) FALSE)
  soil <- wide_session(api)
  before <- api_requests(api)
  e <- expect_error(
    soil_observations(soil, datasets = "wosis_points", layout = "long", with_geometry = "sf"),
    class = "soilhub_dependency_error"
  )
  expect_identical(e$package, "sf")
  expect_match(conditionMessage(e), "install.packages(\"sf\")", fixed = TRUE)
  expect_match(conditionMessage(e), "with_geometry = \"text\"", fixed = TRUE)
  expect_error(
    soil_observations(wide_session(wide_api), datasets = "wosis_points", with_geometry = "sf"),
    class = "soilhub_dependency_error"
  )
  expect_identical(api_requests(api), before)
  # every read without sf geometry works
  x <- soil_observations(soil, datasets = "wosis_points", layout = "long", with_geometry = "text",
                         progress = FALSE)
  expect_s3_class(x, c("soil_table", "data.frame"), exact = TRUE)
  y <- soil_observations(soil, datasets = "wosis_points", layout = "long", progress = FALSE)
  expect_identical(nrow(y), 17L)
})

test_that("a long geometry read needs the observation_geometry capability", {
  soil <- wide_session(api, capabilities = capabilities_with(observation_geometry = FALSE))
  before <- api_requests(api)
  e <- expect_error(
    soil_observations(soil, datasets = "wosis_points", layout = "long", with_geometry = "text"),
    class = "soilhub_capability_error"
  )
  expect_identical(e$capability, "observation_geometry")
  expect_identical(api_requests(api), before)
  # without geometry the capability is not needed
  x <- soil_observations(soil, datasets = "wosis_points", layout = "long", progress = FALSE)
  expect_identical(nrow(x), 17L)
})

test_that("a failure after some long pages keeps them as a typed partial soil_table", {
  soil <- wide_session(api)
  e <- expect_error(
    soil_observations(soil, datasets = "wosis_points", country = "FAIL", layout = "long",
                      with_geometry = "text", progress = FALSE),
    class = "soilhub_api_error"
  )
  expect_identical(e$status, 500L)
  partial <- e$partial
  expect_s3_class(partial, "soil_table")
  expect_identical(attr(partial, "soil_layout"), "long")
  expect_identical(nrow(partial), 10L)
  meta <- soil_metadata(partial)
  expect_false(meta$complete)
  expect_identical(meta$next_offset, 10)
  expect_identical(meta$total_count, 17)
  expect_identical(partial$geometry_text[[1]], "{\"type\":\"Point\",\"coordinates\":[36.8,-1.3]}")
  expect_equal(partial$value[[1]], 1)
  expect_match(conditionMessage(e), "continue from offset 10", fixed = TRUE)
  expect_match(capture.output(print(partial))[3], "incomplete read: continue with offset = 10")
  rest <- soil_observations(soil, datasets = "wosis_points", layout = "long",
                            offset = meta$next_offset, progress = FALSE)
  expect_identical(unique(rest$horizon_id), c("h-4", "h-5"))
  expect_identical(soil_metadata(rest)$filters$offset, 10L)
})

test_that("a refused long selection names the export call", {
  soil <- wide_session(api)
  e <- expect_error(soil_observations(soil, country = "BRA", layout = "long", progress = FALSE),
                    class = "soilhub_load_limit_error")
  expect_identical(e$request$layout, "long")
  expect_match(conditionMessage(e), "soil_export(soil, country = \"BRA\", format = \"gpkg\")", fixed = TRUE)
})

test_that("view = \"revised\" in the long layout: rules, hidden values, missing geometry", {
  soil <- wide_session(api)
  expect_warning(
    x <- soil_observations(soil, datasets = "soter_profiles", view = "revised", layout = "long",
                           with_geometry = "text", progress = FALSE),
    "1 row\\(s\\) of 1 feature\\(s\\) have no geometry", class = "soilhub_geometry_warning"
  )
  expect_identical(soil_metadata(x)$filters$view, "revised")
  expect_identical(soil_revised_rules(x)$id, c("R8", "R12", "R12"))
  m <- soil_markings(x)
  expect_identical(unique(m$column[m$scope == "hidden_value"]), "CLPC")
  expect_true(is.na(x$geometry_text[[3]]))
  skip_if_not_installed("sf")
  expect_warning(
    y <- soil_observations(soil, datasets = "soter_profiles", view = "revised", layout = "long",
                           with_geometry = "sf", progress = FALSE),
    "their geometry is empty", class = "soilhub_geometry_warning"
  )
  expect_identical(sf::st_is_empty(y$geometry), c(FALSE, FALSE, TRUE))
})
