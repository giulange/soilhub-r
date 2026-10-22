# Typing of the wide layout (design 5.2; decision 8): pure functions on the
# fixture pages, no server.

offline_session <- function() {
  soil <- new_soil_session(soil_config(api_url = "http://127.0.0.1:9/api/v1", timeout = 5, verbose = 0))
  soil$state$capabilities <- read_fixture("capabilities.json")
  soil
}

wosis_table <- function(with_geometry = "none") {
  observations_table(offline_session(), fixture_pages("wide-wosis-page1.json", "wide-wosis-page2.json"),
                     with_geometry = with_geometry, fetch_catalog = FALSE)
}

column_classes <- function(x) vapply(as.data.frame(x), function(column) class(column)[1], character(1))

test_that("fixed columns, source attributes and raw markings of WoSIS are typed", {
  x <- wosis_table()
  expect_s3_class(x, c("soil_table", "data.frame"), exact = TRUE)
  expect_identical(attr(x, "soil_layout"), "wide")
  expect_identical(nrow(x), 5L)
  expect_identical(names(x)[1:12], wide_fixed_columns)
  types <- column_classes(x)
  expect_identical(unname(types[c("dataset", "feature_id", "component_id", "horizon_id", "release_code")]), rep("character", 5))
  expect_identical(unname(types["component_rank"]), "integer")
  expect_identical(unname(types[c("upper_depth_cm", "lower_depth_cm", "texture_sum")]), rep("numeric", 3))
  expect_identical(x$lower_depth_cm, c(20, 45.5, 5, 10, NA))
  # source attribute: verbatim text, not logical
  expect_identical(x$horizon_attr_organic_surface, c("false", "false", "true", "false", "false"))
  # layer markings
  expect_identical(x$consistency_flags[[1]], "orgc_gt_totc")
  expect_null(x$consistency_flags[[2]])
  expect_identical(x$consistency_flags[[5]], c("wg1500_gt_wg0033", "orgc_gt_totc"))
  # cell markings: column -> markings
  cell <- x$cell_markings[[1]]$coarse_fragments
  expect_identical(cell$value_count, 2L)
  expect_identical(cell$value_spread, 0.2)
  expect_identical(cell$source_method_kind, "field estimate")
  expect_identical(cell$method_facets, list(sample_pretreatment = "sieved 2 mm"))
  expect_true(x$cell_markings[[3]]$coarse_fragments$methods_differ)
  expect_null(x$cell_markings[[2]])
  # without geometry: no geometry column
  expect_null(x$geometry_text)
})

test_that("value flags and retirement are list and character columns", {
  x <- wosis_table()
  expect_identical(x$value_flags[[1]], list(organic_carbon = "extreme"))
  expect_identical(x$value_flags[[3]], list(clay = "trace_convention", organic_carbon = c("extreme", "above_unit_maximum")))
  expect_null(x$value_flags[[2]])
  expect_identical(x$retired_in_release, c(NA, NA, NA, "2026-10-01_isric", "2026-10-01_isric"))
  expect_identical(x$retired_cells[[2]], c(clay = "2026-10-01_isric"))
  expect_null(x$retired_cells[[4]])
})

test_that("variable groups are typed and multi-value cells parsed (mean and originals)", {
  x <- wosis_table()
  types <- column_classes(x)
  expect_identical(unname(types[c("clay", "coarse_fragments", "organic_carbon")]), rep("numeric", 3))
  expect_identical(unname(types[c("clay_units", "clay_method", "organic_carbon_units")]), rep("character", 3))
  expect_identical(unname(types[c("clay_n", "organic_carbon_n", "src_dens_n")]), rep("integer", 3))
  expect_identical(x$clay, c(23.5, 30, 12, 41, 44.25))
  expect_identical(x$organic_carbon_n, c(2L, NA, 1L, NA, 1L))
  # ["0.9", "1.1"] -> mean 1; ["2", "<1"] -> NA (an element is not a number)
  expect_identical(x$coarse_fragments, c(mean(c(0.9, 1.1)), 4, NA, NA, NA))
  expect_type(x$coarse_fragments_values, "list")
  expect_identical(x$coarse_fragments_values[[1]], c("0.9", "1.1"))
  expect_null(x$coarse_fragments_values[[2]])
  expect_identical(x$coarse_fragments_values[[3]], c("2", "<1"))
  expect_null(x$coarse_fragments_values[[4]])
  expect_identical(soil_metadata(x)$multi_value_rule, "mean")
  # _values only for columns with multi-value cells, right after the group
  expect_false("clay_values" %in% names(x))
  group <- grep("^coarse_fragments", names(x), value = TRUE)
  expect_identical(group, paste0("coarse_fragments", c("", "_units", "_method", "_n", "_values")))
})

test_that("pages are aligned: union of columns, NA where a page lacks one, stable types", {
  x <- wosis_table()
  vars <- c("clay", "coarse_fragments", "organic_carbon", "src_dens", "src_lab_note")
  # variable groups after the other columns, sorted by name
  first_var <- match("clay", names(x))
  expect_true(all(match(c("retired_cells", "value_flags"), names(x)) < first_var))
  expect_identical(intersect(names(x), vars), vars)
  # coarse_fragments only on page 1, src_lab_note only on page 2
  expect_identical(x$coarse_fragments_units, c(rep("cm3/100cm3", 3), NA, NA))
  expect_identical(x$src_lab_note, c(NA, NA, NA, "sample lost", NA))
  # numeric on page 1, not on page 2: character, the numbers as text
  expect_type(x$src_dens, "character")
  expect_identical(x$src_dens, c("1.3", NA, NA, "n.d.", "1.41"))
  cols <- soil_columns(x)
  expect_identical(cols$column, vars)
  expect_identical(cols$numeric, c(TRUE, TRUE, TRUE, FALSE, FALSE))
  expect_identical(cols$horizon_count, c(5L, 3L, 3L, 3L, 1L))
  expect_identical(cols$multi_value_cells, c(0L, 2L, 0L, 0L, 0L))
  expect_identical(cols$units[[4]], c("g/cm3", "kg/dm3"))
  expect_identical(cols$methods[[1]], c(CLAY_HYDRO = "Hydrometer method", CLAY_PIPETTE = "Pipette method"))
  expect_identical(cols$source_notes[[3]]$source_code, "ORGC")
  expect_identical(nrow(cols$source_notes[[3]]), 1L)
  expect_identical(cols$method_facets[[2]], list(sample_pretreatment = "sieved 2 mm"))
  # one page alone has the same column types for the shared columns
  one <- observations_table(offline_session(), fixture_pages("wide-wosis-page1.json"), fetch_catalog = FALSE)
  shared <- intersect(names(one), names(x))
  shared <- setdiff(shared, "src_dens")
  expect_identical(column_classes(one)[shared], column_classes(x)[shared])
})

test_that("geometry text is the WKT of the row's feature; rows without one warn once", {
  x <- wosis_table("text")
  expect_identical(x$geometry_kind, rep("POINT", 5))
  expect_identical(x$geometry_text, c("POINT(36.8 -1.3)", "POINT(36.8 -1.3)", "POINT(37 -1)",
                                       "POINT(38.25 0.5)", "POINT(38.25 0.5)"))
  expect_identical(match("geometry_text", names(x)), match("clay", names(x)) - 1L)
  pages <- fixture_pages("wide-wise.json")
  expect_warning(
    w <- observations_table(offline_session(), pages, with_geometry = "text", fetch_catalog = FALSE),
    "1 row\\(s\\) of 1 feature\\(s\\) have no geometry", class = "soilhub_geometry_warning"
  )
  expect_identical(w$geometry_kind, c("POINT", "NONE"))
  expect_identical(w$geometry_text, c("POINT(9.5 35.25)", NA))
})

test_that("WISE source attributes and SOTER profile columns are character", {
  w <- observations_table(offline_session(), fixture_pages("wide-wise.json"), fetch_catalog = FALSE)
  expect_identical(w$profile_attr_iso, c("TN", "TN"))
  expect_identical(w$profile_attr_lab_id, c("TN-01", NA))
  expect_identical(w$horizon_attr_mcolor, c("10YR3/3", "7.5YR4/4"))
  expect_identical(soil_columns(w)$methods[[1]], c(GY01 = "Dissolved in water and precipitated by acetone"))
  expect_identical(soil_columns(w)$method_facets[[1]], stats::setNames(list(), character()))

  s <- observations_table(offline_session(), fixture_pages("wide-soter.json"), fetch_catalog = FALSE)
  expect_identical(s$source_profile_type, c("synthetic", NA))
  expect_identical(s$source_record_note, c(NA, "profile row absent in the source"))
  expect_identical(s$also_in_datasets, list("SOTERSAF", NULL))
  expect_identical(s$possible_profile, c("KE-0042", NA))
  expect_identical(s$upper_depth_cm, c(NA_real_, NA_real_))
  expect_identical(s$ph_water, c(6.4, 7.1))
})

test_that("SOTWIS component columns are typed", {
  u <- observations_table(offline_session(), fixture_pages("wide-sotwis.json"), fetch_catalog = FALSE)
  types <- column_classes(u)
  expect_identical(unname(types[c("proportion_percent", "cumulative_proportion_percent")]), c("numeric", "numeric"))
  expect_identical(unname(types[c("suid", "tcid", "scid", "component_rank")]), rep("integer", 4))
  expect_identical(unname(types["is_representative"]), "logical")
  expect_identical(unname(types[c("soil_code", "newsuid", "isoc", "soil_map_unit", "representative_profile_id")]), rep("character", 5))
  expect_identical(u$is_representative, c(TRUE, FALSE))
  expect_identical(u$tcid, c(1L, NA))
  expect_identical(u$superseded_by, c(NA, "SOVEUR v2"))
  expect_identical(soil_metadata(u)$components, "all")
  expect_match(soil_warnings(u), "more than one component with the largest proportion_percent")
})

test_that("revised markings: hidden values as a data frame, cells as a named list", {
  r <- observations_table(offline_session(), fixture_pages("wide-revised.json"), fetch_catalog = FALSE)
  m <- r$revised_markings[[1]]
  expect_s3_class(m$hidden_values, "data.frame")
  expect_identical(m$hidden_values$property_code, c("BDFIFM", "PHPRTN"))
  expect_identical(m$hidden_values$rule, c("R17", "R12"))
  expect_identical(m$hidden_values$source_value[[1]], list("1.2", "guessed value, expert field estimate"))
  expect_identical(m$hidden_values$source_value[[2]], 140L)
  expect_identical(m$cells$sand$texture_normalized$original_sum, 102)
  expect_null(r$revised_markings[[2]])
})

test_that("first-layer columns are typed", {
  f <- observations_table(offline_session(), fixture_pages("wide-first-layer.json"), fetch_catalog = FALSE)
  expect_identical(match(c("first_layer_status", "profile_markings"), names(f)), 13:14)
  expect_identical(f$first_layer_status, c("surface", "tie", "tie"))
  expect_identical(f$profile_markings[[1]], "numbering_starts_at_2")
  expect_identical(f$profile_markings[[2]], c("depth_order_conflict:1,2", "numbering_gap"))
})

test_that("columns unknown to the client are kept as list columns with a contract warning", {
  pages <- fixture_pages("wide-soter.json")
  pages$items[[1]]$new_marking <- "x"
  soilhub_env$shown <- character()
  expect_warning(
    s <- observations_table(offline_session(), pages, fetch_catalog = FALSE),
    "new_marking", class = "soilhub_contract_warning"
  )
  expect_identical(s$new_marking, list("x", NULL))
})

test_that("an empty read keeps the fixed columns", {
  pages <- fixture_pages("wide-soter.json")
  pages$items <- list()
  pages$page_metadata[[1]]$variables <- list()
  e <- observations_table(offline_session(), pages, fetch_catalog = FALSE)
  expect_identical(nrow(e), 0L)
  expect_identical(names(e), wide_fixed_columns)
  expect_identical(column_classes(e)[["component_rank"]], "integer")
  expect_identical(nrow(soil_columns(e)), 0L)
})

test_that("multi-value helpers follow the API's number rule", {
  expect_identical(multi_value_elements("[\"0.9\", \"0.9\"]"), c("0.9", "0.9"))
  expect_identical(multi_value_elements("[1.5, 2.5, null]"), c("1.5", "2.5", NA))
  expect_null(multi_value_elements("[\"12.8\"]"))
  expect_null(multi_value_elements("sample lost"))
  expect_null(multi_value_elements("[not json"))
  expect_identical(multi_value_mean(c("1", "2", "3e0")), 2)
  expect_true(is.na(multi_value_mean(c("1", NA))))
  expect_true(is.na(multi_value_mean(c("1", " 2"))))
})
