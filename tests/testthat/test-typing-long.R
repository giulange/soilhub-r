# Typing of the long layout (design 5.3; decision 8), the features (5.5) and
# the geometry helpers (decision 6): pure functions on the fixture pages, no
# server.

offline_long_session <- function() {
  soil <- new_soil_session(soil_config(api_url = "http://127.0.0.1:9/api/v1", timeout = 5, verbose = 0))
  soil$state$capabilities <- read_fixture("capabilities.json")
  soil
}

wosis_long <- function(with_geometry = "none") {
  observations_table(offline_long_session(),
                     fixture_item_pages("long-wosis-page1.json", "long-wosis-page2.json"),
                     with_geometry = with_geometry, fetch_catalog = FALSE, layout = "long")
}

classes_of <- function(x) vapply(as.data.frame(x), function(column) class(column)[1], character(1))

test_that("long rows are typed per design 5.3, in API order", {
  x <- wosis_long()
  expect_s3_class(x, c("soil_table", "data.frame"), exact = TRUE)
  expect_identical(attr(x, "soil_layout"), "long")
  expect_identical(nrow(x), 17L)
  expect_identical(names(x)[1:8], c("dataset", "observation_id", "feature_id", "source_code",
                                    "component_id", "component_rank", "representative_profile_id", "horizon_id"))
  # no geometry asked: the geometry column is dropped, geometry_kind kept as served
  expect_false("geometry" %in% names(x))
  expect_false("geometry_text" %in% names(x))
  types <- classes_of(x)
  expect_identical(unname(types[c("dataset", "observation_id", "property_code", "unit", "canonical_property_key",
                                  "method_code", "retired_in_release", "geometry_kind")]), rep("character", 8))
  expect_identical(unname(types[c("release_id", "value_count", "component_rank")]), rep("integer", 3))
  expect_identical(unname(types[c("value", "upper_depth_cm", "texture_sum", "value_spread", "method_tension_kpa")]),
                   rep("numeric", 5))
  expect_identical(unname(types["methods_differ"]), "logical")
  expect_identical(unname(types[c("value_raw", "lineage", "profile_attributes", "horizon_attributes",
                                  "method_facets", "source_method_kind", "consistency_flags",
                                  "also_in_datasets", "value_flags")]), rep("list", 9))
  # lineage and source descriptors are named lists
  expect_identical(x$lineage[[2]]$source_record_id, "p-1:1:CLAY")
  expect_identical(x$lineage[[2]]$release_id, 11L)
  expect_identical(x$horizon_attributes[[1]], list(organic_surface = "false"))
  # markings of the cell, layer and profile
  expect_identical(x$value_flags[[4]], "extreme")
  expect_null(x$value_flags[[5]])
  expect_identical(x$source_method_kind[[1]], "field estimate")
  expect_identical(x$method_facets[[1]], list(sample_pretreatment = "sieved 2 mm"))
  expect_identical(x$consistency_flags[[1]], "orgc_gt_totc")
  expect_identical(x$texture_sum[1:5], rep(100.2, 5))
  expect_identical(x$retired_in_release[[7]], "2026-10-01_isric")
  # metadata: exact total, no variable typing, the multi-value rule
  meta <- soil_metadata(x)
  expect_identical(meta$total_count, 17)
  expect_null(meta$variables)
  expect_identical(meta$multi_value_rule, "mean")
  expect_error(soil_columns(x), class = "soilhub_argument_error")
})

test_that("value_raw is verbatim and multi-value cells get the mean in value", {
  x <- wosis_long()
  # one-element WoSIS array: the API extracts the number
  expect_identical(x$value_raw[[2]], list("23.5"))
  expect_identical(x$value[[2]], 23.5)
  # plain number and text values
  expect_identical(x$value_raw[[3]], 1.3)
  expect_identical(x$value_raw[[12]], "n.d.")
  expect_true(is.na(x$value[[12]]))
  # multi-value cell: the API extracts none; the client takes the mean (decision 8)
  expect_identical(x$value_raw[[1]], list("0.9", "1.1"))
  expect_equal(x$value[[1]], 1)
  expect_identical(x$value_count[[1]], 2L)
  # an element that is not a number: NA, originals kept
  expect_identical(x$value_raw[[8]], list("2", "<1"))
  expect_true(is.na(x$value[[8]]))
  expect_true(x$methods_differ[[8]])
})

test_that("an empty long page has the base columns; unknown fields are kept and reported", {
  empty <- fixture_item_pages("long-wosis-page1.json")
  empty$items <- list()
  x <- observations_table(offline_long_session(), empty, fetch_catalog = FALSE, layout = "long")
  expect_identical(nrow(x), 0L)
  expect_true(all(setdiff(long_base_columns, "geometry") %in% names(x)))
  pages <- fixture_item_pages("long-wosis-page2.json")
  pages$items <- lapply(pages$items, function(row) c(row, list(new_marking = list("a"))))
  soilhub_env$shown <- setdiff(soilhub_env$shown, grep("^contract:", soilhub_env$shown, value = TRUE))
  expect_warning(
    y <- observations_table(offline_long_session(), pages, fetch_catalog = FALSE, layout = "long"),
    "new_marking", class = "soilhub_contract_warning"
  )
  expect_identical(y$new_marking[[1]], list("a"))
})

test_that("the revised long view of SOTER keeps the hidden values and the cell markings", {
  pages <- fixture_item_pages("long-soter-revised.json")
  x <- observations_table(offline_long_session(), pages, fetch_catalog = FALSE, layout = "long")
  expect_identical(nrow(x), 3L)
  expect_identical(soil_metadata(x)$view, "revised")
  hidden <- x$revised_markings[[1]]$hidden_values
  expect_s3_class(hidden, "data.frame")
  expect_identical(hidden$property_code, "CLPC")
  expect_identical(hidden$rule, "R12")
  expect_identical(hidden$source_value, list(140L))
  expect_identical(x$revised_markings[[1]]$kept_from_copy, "SOTERSAF")
  expect_null(x$revised_markings[[3]])
  expect_identical(x$method_tension_kpa, c(10, NA, NA))
  expect_identical(x$source_profile_type, c("synthetic", "synthetic", NA))
  expect_identical(x$source_record_note[[3]], "profile row absent in the source")
  expect_identical(x$profile_attributes[[1]], list(prid = "KE-syn-0042", drai = "W"))
  expect_identical(x$horizon_attributes[[1]]$honu, 1L)
  expect_identical(x$also_in_datasets[[1]], "SOTERSAF")
  expect_identical(x$value_raw[[3]], "12")
  rules <- soil_revised_rules(x)
  expect_identical(rules$id, c("R8", "R12", "R12"))
  expect_identical(rules$effect, c("values_kept_from_copy", "values_flagged:extreme", "values_hidden"))
  # markings: cell markings named by the property code, hidden values once per row
  m <- soil_markings(x)
  expect_identical(m$scope[m$row == 1], c("profile", "profile", "revised_cell", "hidden_value"))
  expect_identical(m$column[m$scope == "revised_cell"], "MCT2")
  expect_identical(m$marking[m$scope == "hidden_value"], c("R12", "R12"))
  expect_identical(m$value[m$scope == "hidden_value"], c("140", "140"))
  flags <- soil_flags(x)
  expect_identical(flags$column, "PHAQ")
  expect_identical(flags$flag, "extreme")
  expect_identical(flags$row, 2L)
})

test_that("soil_markings() of a long table lists only informative cell markings", {
  x <- wosis_long()
  m <- soil_markings(x)
  cell <- m[m$scope == "cell", ]
  expect_identical(unique(cell$column), "CFVO")
  expect_identical(cell$marking[cell$row == 1], c("value_count", "value_spread", "source_method_kind", "method_facets"))
  expect_identical(cell$marking[cell$row == 8], c("value_count", "methods_differ"))
  flags <- soil_flags(x)
  expect_identical(flags$column, c("ORGC", "CLAY", "ORGC", "ORGC"))
  expect_identical(flags$flag, c("extreme", "trace_convention", "extreme", "above_unit_maximum"))
})

test_that("wide and long fixtures of the same selection are equivalent", {
  wide <- observations_table(offline_long_session(),
                             fixture_pages("wide-wosis-page1.json", "wide-wosis-page2.json"),
                             fetch_catalog = FALSE)
  expect_identical(wide_long_mismatches(wide, wosis_long()), character())
  # the check is not vacuous: a different value or count breaks it
  long <- wosis_long()
  long$value[[2]] <- 99
  expect_identical(wide_long_mismatches(wide, long), "clay of wosis_points|f-1|NA|h-1")
  long <- wosis_long()[-5, ]
  expect_identical(wide_long_mismatches(wide, long), "organic_carbon_n of wosis_points|f-1|NA|h-1")
})

test_that("GeoJSON geometries become WKT, GeoJSON text is kept verbatim", {
  expect_identical(geojson_to_wkt(list(type = "Point", coordinates = list(36.8, -1.3))), "POINT (36.8 -1.3)")
  expect_identical(geojson_to_wkt(list(type = "Point", coordinates = list())), "POINT EMPTY")
  expect_identical(
    geojson_to_wkt(list(type = "MultiPoint", coordinates = list(list(1, 2), list(3, 4)))),
    "MULTIPOINT ((1 2), (3 4))"
  )
  expect_identical(
    geojson_to_wkt(list(type = "LineString", coordinates = list(list(1, 2), list(3, 4)))),
    "LINESTRING (1 2, 3 4)"
  )
  expect_identical(
    geojson_to_wkt(list(type = "MultiLineString", coordinates = list(list(list(1, 2), list(3, 4))))),
    "MULTILINESTRING ((1 2, 3 4))"
  )
  ring <- list(list(9, 33), list(10, 33), list(10, 34), list(9, 33))
  expect_identical(geojson_to_wkt(list(type = "Polygon", coordinates = list(ring))),
                   "POLYGON ((9 33, 10 33, 10 34, 9 33))")
  expect_identical(geojson_to_wkt(list(type = "MultiPolygon", coordinates = list(list(ring), list(ring)))),
                   "MULTIPOLYGON (((9 33, 10 33, 10 34, 9 33)), ((9 33, 10 33, 10 34, 9 33)))")
  expect_identical(
    geojson_to_wkt(list(type = "GeometryCollection", geometries = list(
      list(type = "Point", coordinates = list(1, 2)),
      list(type = "LineString", coordinates = list(list(1, 2), list(3, 4)))
    ))),
    "GEOMETRYCOLLECTION (POINT (1 2), LINESTRING (1 2, 3 4))"
  )
  # third coordinate dropped (2D), full precision kept
  expect_identical(geojson_to_wkt(list(type = "Point", coordinates = list(1.123456789012, 2, 300))),
                   "POINT (1.123456789012 2)")
  expect_true(is.na(geojson_to_wkt(NULL)))
  expect_true(is.na(geojson_to_wkt(list(type = "Curve", coordinates = list()))))
  expect_identical(geojson_text(list(type = "Point", coordinates = list(36.8, -1.3))),
                   "{\"type\":\"Point\",\"coordinates\":[36.8,-1.3]}")
  expect_true(is.na(geojson_text(NULL)))
})

test_that("long geometry as text (GeoJSON) and as sf; missing geometry warns once", {
  x <- wosis_long("text")
  expect_identical(x$geometry_text[[1]], "{\"type\":\"Point\",\"coordinates\":[36.8,-1.3]}")
  expect_identical(match("geometry_text", names(x)), match("lineage", names(x)) + 1L)
  pages <- fixture_item_pages("long-soter-revised.json")
  expect_warning(
    y <- observations_table(offline_long_session(), pages, with_geometry = "text", fetch_catalog = FALSE, layout = "long"),
    "1 row\\(s\\) of 1 feature\\(s\\) have no geometry.*geometry_text is NA", class = "soilhub_geometry_warning"
  )
  expect_true(is.na(y$geometry_text[[3]]))
  skip_if_not_installed("sf")
  z <- wosis_long("sf")
  expect_s3_class(z, c("soil_table", "sf", "data.frame"), exact = TRUE)
  expect_s3_class(z$geometry, "sfc_POINT")
  expect_identical(sf::st_crs(z)$epsg, 4326L)
  expect_equal(unname(sf::st_coordinates(z$geometry[1])[1, ]), c(36.8, -1.3))
  expect_warning(
    s <- observations_table(offline_long_session(), pages, with_geometry = "sf", fetch_catalog = FALSE, layout = "long"),
    "their geometry is empty", class = "soilhub_geometry_warning"
  )
  expect_true(sf::st_is_empty(s$geometry[3]))
  expect_s3_class(s$geometry, "sfc_POINT")
  # subsetting keeps sf and soil_table; as.data.frame() drops both classes
  sub <- z[1:2, c("horizon_id", "value")]
  expect_s3_class(sub, c("soil_table", "sf", "data.frame"), exact = TRUE)
  expect_identical(attr(sub, "soil_layout"), "long")
  plain <- as.data.frame(z)
  expect_identical(class(plain), "data.frame")
  expect_s3_class(plain$geometry, "sfc")
  expect_output(print(z), "POINT \\(36.8 -1.3\\)")
})

test_that("features are typed: properties, components, markings, metadata", {
  pages <- fixture_item_pages("features-polygons.json", items = "features")
  x <- features_table(offline_long_session(), pages, with_geometry = "text", fetch_catalog = FALSE)
  expect_s3_class(x, c("soil_table", "data.frame"), exact = TRUE)
  expect_identical(attr(x, "soil_layout"), "features")
  expect_identical(names(x), c("dataset", "provider_code", "feature_id", "feature_key", "geometry_kind",
                               "source_support", "components", "profile_markings", "retired_in_release",
                               "geometry_text"))
  expect_identical(x$geometry_kind, c("POLYGON", "MULTIPOLYGON", "POINT", "POINT"))
  comp <- x$components[[1]]
  expect_s3_class(comp, "data.frame")
  expect_identical(comp$component_id, c("c-1", "c-2"))
  expect_identical(comp$component_rank, 1:2)
  expect_identical(comp$proportion_percent, c(60, 35))
  expect_identical(comp$is_representative, c(TRUE, FALSE))
  expect_identical(comp$scid, 1:2)
  expect_identical(comp$source_attributes[[1]], list(TCID = 1L, LANDFORM = "plain"))
  expect_null(x$components[[3]])
  expect_null(x$profile_markings[[1]])
  expect_identical(x$profile_markings[[3]], character())
  expect_identical(x$profile_markings[[4]], "no_horizons_in_source")
  meta <- soil_metadata(x)
  expect_identical(meta$feature_count, 4L)
  expect_identical(meta$feature_count_by_dataset, list(soter_profiles = 2L, sotwis_polygons = 2L))
  expect_true(meta$mixed_geometry)
  expect_true(is.na(meta$total_count))
  expect_null(meta$multi_value_rule)
  expect_match(x$geometry_text[[1]], "^\\{\"type\":\"Polygon\",\"coordinates\":\\[\\[\\[9,33\\]")
  expect_match(capture.output(print(x))[1], "^# soilhub features table: 4 features \\| sotwis_polygons, soter_profiles \\| view raw$")
  skip_if_not_installed("sf")
  y <- features_table(offline_long_session(), pages, with_geometry = "sf", fetch_catalog = FALSE)
  expect_s3_class(y, c("soil_table", "sf", "data.frame"), exact = TRUE)
  expect_identical(as.character(sf::st_geometry_type(y)), c("POLYGON", "MULTIPOLYGON", "POINT", "POINT"))
  expect_identical(sf::st_crs(y)$epsg, 4326L)
  expect_equal(sf::st_bbox(y[1, ])[["xmax"]], 10)
})
