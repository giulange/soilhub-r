# Thematic reads (WP6, design 4.4, 5.5): soil_values(), soil_values_summary(),
# soil_health_scores(), soil_health_summary(), soil_resolve_targets(),
# soil_ttr_flags() on the fake API of helper-fake-thematic.R.

server <- fake_thematic_api()

# ---------------------------------------------------------------------------
# Values

test_that("soil_values() reads every page and types the values", {
  soil <- thematic_session(server, page_size = 2)
  thematic_reset(server)
  v <- soil_values(soil, variables = c("soc_stock_0_30", "texture_fractions"),
                   target_levels = c("horizon", "profile"), run_ids = 42,
                   valid_at = as.Date("2024-01-01"), depth_top_cm = 0, depth_bottom_cm = 30,
                   progress = FALSE)
  expect_s3_class(v, c("soil_table", "data.frame"))
  expect_identical(attr(v, "soil_layout"), "values")
  expect_identical(nrow(v), 4L)
  calls <- thematic_calls(server, "/query/values")
  expect_length(calls, 2L)
  body <- calls[[1]]$body
  expect_identical(body$variables, list("soc_stock_0_30", "texture_fractions"))
  expect_identical(body$target_levels, list("horizon", "profile"))
  expect_identical(body$run_ids, list(42L))
  expect_identical(body$valid_at, "2024-01-01T00:00:00Z")
  expect_identical(body$depth_top_cm, 0L)
  expect_false(body$include_geometry)
  expect_false(body$include_lineage)
  expect_identical(c(body$limit, body$offset, calls[[2]]$body$offset), c(2L, 0L, 2L))
  # types
  expect_type(v$numeric_value, "double")
  expect_type(v$boolean_value, "logical")
  expect_type(v$json_value, "list")
  expect_type(v$run_id, "double")
  expect_s3_class(v$valid_time_start, "POSIXct")
  expect_identical(format(v$valid_time_start[1], "%Y-%m-%d", tz = "UTC"), "2020-01-01")
  expect_true(all(is.na(v$valid_time_end)))
  expect_false("geometry" %in% names(v))
  expect_false("geometry_text" %in% names(v))
  # value: mixed types -> list column, each in its type, placed before numeric_value
  expect_identical(match("value", names(v)) + 1L, match("numeric_value", names(v)))
  expect_type(v$value, "list")
  expect_identical(v$value[[1]], 41.5)
  expect_identical(v$value[[3]], "good structure")
  expect_identical(v$value[[4]], list(sand = 40L, silt = 35L, clay = 25L))
  meta <- soil_metadata(v)
  expect_identical(meta$total_count, 4)
  expect_true(meta$complete)
  expect_identical(meta$pages, 2L)
  expect_identical(meta$endpoint, "/query/values")
  out <- capture.output(print(v))
  expect_match(out[1], "^# soilhub values table: 4 rows, 1 features \\| wosis_points$")
  expect_match(out[2], "cite with soil_citations\\(\\)$")
  expect_false(any(grepl("soil_columns", out)))
})

test_that("soil_values() with one value type gives a typed value column, geometry text and lineage", {
  soil <- thematic_session(server)
  v <- soil_values(soil, max_rows = 2, with_geometry = "text", include_lineage = TRUE, progress = FALSE)
  expect_identical(nrow(v), 2L)
  expect_identical(v$value, c(41.5, 38.25))
  expect_identical(v$geometry_text[1], "{\"type\":\"Point\",\"coordinates\":[36.8,-1.3]}")
  expect_identical(match("geometry_text", names(v)), match("geometry_kind", names(v)) + 1L)
  expect_identical(soil_metadata(v)$crs, "EPSG:4326")
  expect_true(all(c("observation_inputs", "value_inputs", "release_inputs", "asset_inputs") %in% names(v)))
  expect_identical(v$observation_inputs[[1]][[1]]$input_role, "organic_carbon")
  body <- thematic_calls(server, "/query/values")
  body <- body[[length(body)]]$body
  expect_true(body$include_geometry)
  expect_true(body$include_lineage)
  # summary() works on a values table
  expect_output(print(summary(v)), "Rows per dataset")
})

test_that("soil_values() keeps the typed pages read before a failure", {
  soil <- thematic_session(server, page_size = 2)
  e <- expect_error(soil_values(soil, datasets = "FAIL", progress = FALSE), class = "soilhub_api_error")
  expect_s3_class(e$partial, "soil_table")
  expect_identical(nrow(e$partial), 2L)
  expect_false(soil_metadata(e$partial)$complete)
  expect_identical(soil_metadata(e$partial)$next_offset, 2)
})

test_that("soil_values() validates its filters before any request", {
  soil <- thematic_session(server)
  thematic_reset(server)
  err <- function(expr, argument) {
    e <- expect_error(expr, class = "soilhub_argument_error")
    expect_identical(e$argument, argument)
  }
  err(soil_values(soil, target_levels = "plot"), "target_levels")
  err(soil_values(soil, statuses = "scored"), "statuses")
  err(soil_values(soil, run_ids = 1.5), "run_ids")
  err(soil_values(soil, valid_at = "yesterday"), "valid_at")
  err(soil_values(soil, depth_top_cm = c(0, 10)), "depth_top_cm")
  err(soil_values(soil, bbox = c(0, 0, 0, 0)), "bbox")
  err(soil_values(soil, datasets = "ALL"), "datasets")
  err(soil_values(soil, with_geometry = "shape"), "with_geometry")
  err(soil_values(soil, include_lineage = NA), "include_lineage")
  err(soil_values_summary(soil, statuses = "bad"), "statuses")
  expect_length(thematic_calls(server), 0L)
})

test_that("soil_values_summary() types the counts", {
  soil <- thematic_session(server)
  s <- soil_values_summary(soil, country = "KEN", statuses = c("published", "insufficient_data"))
  expect_s3_class(s, "soil_values_summary")
  expect_identical(s$total_value_count, 4)
  expect_identical(s$variables$code, c("soc_stock_0_30", "soil_quality_note", "texture_fractions"))
  expect_identical(s$by_dataset$value_count, 4)
  expect_identical(s$by_target_level, c(horizon = 3, profile = 1))
  expect_identical(s$by_status, c(published = 3, insufficient_data = 1))
  expect_identical(soil_metadata(s)$endpoint, "/query/values/summary")
  body <- thematic_calls(server, "/query/values/summary")[[1]]$body
  expect_identical(body, list(country = list("KEN"), statuses = list("published", "insufficient_data")))
  expect_match(capture.output(print(s))[1], "^# soilhub values summary: 4 values on 1 features, 3 variable\\(s\\)$")
})

# ---------------------------------------------------------------------------
# Soil health

test_that("soil_health_scores() types the scores and maps run_ids and statuses", {
  soil <- thematic_session(server)
  thematic_reset(server)
  h <- soil_health_scores(soil, datasets = "sotwis_polygons", run_ids = c(42, 43),
                          statuses = "scored", release_ids = 12, progress = FALSE)
  expect_s3_class(h, "soil_table")
  expect_identical(attr(h, "soil_layout"), "health")
  body <- thematic_calls(server, "/query/soil-health")[[1]]$body
  expect_identical(body$product_run_ids, list(42L, 43L))
  expect_identical(body$score_statuses, list("scored"))
  expect_identical(body$release_ids, list(12L))
  expect_false(any(c("run_ids", "statuses") %in% names(body)))
  expect_false(body$include_details)
  expect_identical(h$score, c(72.5, NA))
  expect_identical(h$score_class, c("good", NA))
  expect_type(h$model_version_id, "double")
  expect_s3_class(h$created_at, "POSIXct")
  expect_false(any(c("geometry", "geometry_text", "inputs") %in% names(h)))
  expect_identical(soil_metadata(h)$total_count, 2)
  expect_match(capture.output(print(h))[1], "^# soilhub health table: 2 rows, 1 features \\| sotwis_polygons$")
})

test_that("soil_health_scores() adds the details and the geometry text on request", {
  soil <- thematic_session(server)
  h <- soil_health_scores(soil, include_details = TRUE, with_geometry = "text", progress = FALSE)
  expect_true(all(c("inputs", "derived_variables", "memberships", "activated_rules",
                    "diagnostics", "input_observations") %in% names(h)))
  expect_identical(h$memberships[[1]]$good, 0.8)
  expect_identical(h$activated_rules[[1]][[1]]$rule, "physical_r4")
  expect_false(anyNA(h$geometry_text))
  h <- soil_health_scores(soil, with_geometry = "text", progress = FALSE)
  expect_match(h$geometry_text[1], "^\\{\"type\":\"MultiPolygon\",\"coordinates\":\\[\\[\\[\\[10,36\\]")
})

test_that("soil_health_summary() types the counts", {
  soil <- thematic_session(server)
  s <- soil_health_summary(soil, categories = "physical")
  expect_s3_class(s, "soil_health_summary")
  expect_identical(s$total_score_count, 2)
  expect_identical(s$horizon_count, 2)
  expect_identical(s$by_release$release_code, "2024-01")
  expect_identical(s$by_category$category, c("chemical", "physical"))
  expect_identical(s$by_status$score_count, c(1, 1))
  expect_output(print(s), "By class")
  expect_error(soil_health_summary(soil, statuses = "published"), class = "soilhub_argument_error")
})

# ---------------------------------------------------------------------------
# Target resolution

target_keys <- function(ids, level = "profile") {
  data.frame(provider_code = "isric", dataset_code = "wosis_points",
             release_code = "2023-12", target_level = level,
             source_record_id = ids, stringsAsFactors = FALSE)
}

test_that("soil_resolve_targets() reads `targets` of the response", {
  soil <- thematic_session(server)
  thematic_reset(server)
  res <- soil_resolve_targets(soil, target_keys(c("101", "102")))
  expect_identical(res$status, c("resolved", "resolved"))
  expect_identical(res$target_id, c("uuid-profile-101", "uuid-profile-102"))
  expect_identical(res$input_index, c(0, 1))
  expect_type(res$candidate_count, "integer")
  expect_true(all(is.na(res$horizon_id)))
  body <- thematic_calls(server, "/query/targets/resolve")[[1]]$body
  expect_identical(body$targets[[1]], list(provider_code = "isric", dataset_code = "wosis_points",
                                           release_code = "2023-12", target_level = "profile",
                                           source_record_id = "101"))
  expect_identical(soil_metadata(res)$status_counts, c(resolved = 2, missing = 0, ambiguous = 0))
})

test_that("strict resolution stops on missing or ambiguous targets", {
  soil <- thematic_session(server)
  keys <- target_keys(c("101", "missing-1", "dup-1"))
  e <- expect_error(soil_resolve_targets(soil, keys), class = "soilhub_argument_error")
  expect_identical(e$argument, "targets")
  expect_match(conditionMessage(e), "2 of 3 target(s) did not resolve to one canonical record (1 missing, 1 ambiguous)", fixed = TRUE)
  expect_match(conditionMessage(e), "row 2: isric/wosis_points/2023-12 profile missing-1: missing", fixed = TRUE)
  expect_match(conditionMessage(e), "row 3: .* dup-1: ambiguous \\(2 candidates: give `source_table`\\)")
  expect_identical(e$resolution$status, c("resolved", "missing", "ambiguous"))
  # strict = FALSE returns the statuses
  res <- soil_resolve_targets(soil, keys, strict = FALSE)
  expect_identical(res$status, c("resolved", "missing", "ambiguous"))
  expect_identical(res$candidate_count, c(1L, 0L, 2L))
})

test_that("soil_resolve_targets() sends chunks of 10,000 and keeps the input order", {
  soil <- thematic_session(server)
  thematic_reset(server)
  keys <- target_keys(as.character(seq_len(10001)), level = "horizon")
  keys$source_table[10001] <- "horizons"
  res <- soil_resolve_targets(soil, keys)
  calls <- thematic_calls(server, "/query/targets/resolve")
  expect_identical(vapply(calls, function(call) length(call$body$targets), integer(1)), c(10000L, 1L))
  expect_identical(nrow(res), 10001L)
  expect_identical(res$input_index[c(1, 10000, 10001)], c(0, 9999, 10000))
  expect_identical(res$source_record_id[10001], "10001")
  expect_identical(res$source_table[c(1, 10001)], c(NA, "horizons"))
  expect_identical(calls[[2]]$body$targets[[1]]$source_table, "horizons")
  expect_null(calls[[1]]$body$targets[[1]]$source_table)
  expect_length(soil_metadata(res)$request_ids, 2L)
})

test_that("bad targets are refused before any request", {
  soil <- thematic_session(server)
  thematic_reset(server)
  err <- function(targets, pattern) {
    e <- expect_error(soil_resolve_targets(soil, targets), class = "soilhub_argument_error")
    expect_identical(e$argument, "targets")
    expect_match(conditionMessage(e), pattern)
  }
  err(list(a = 1), "must be a data frame")
  err(target_keys("1")[0, ], "has no rows")
  err(target_keys("1")[, -1], "lacks the column\\(s\\) `provider_code`")
  err(target_keys(c("1", NA)), "`source_record_id` has missing values \\(row 2\\)")
  bad <- target_keys("1")
  bad$dataset_code <- "WoSIS"
  err(bad, "lower-case codes")
  err(target_keys("1", level = "plot"), "unknown level\\(s\\) \"plot\"")
  expect_error(soil_resolve_targets(soil, target_keys("1"), strict = NA), class = "soilhub_argument_error")
  expect_length(thematic_calls(server), 0L)
})

# ---------------------------------------------------------------------------
# TTR flags

test_that("soil_ttr_flags() pages through GET /sotwis/ttr-flags with the source columns verbatim", {
  soil <- thematic_session(server, page_size = 2)
  thematic_reset(server)
  f <- soil_ttr_flags(soil, claf = "CMe", layer = "D1")
  expect_s3_class(f, "data.frame")
  expect_identical(nrow(f), 3L)
  expect_identical(names(f)[10:18], c("CLAF", "PRID", "Layer", "Newtopdep", "Newbotdep",
                                      "TTRsub", "TTRmain", "TTRfinal", "TTRexpert"))
  expect_type(f$source_row_number, "integer")
  expect_type(f$Newbotdep, "double")
  expect_identical(f$TTRexpert, rep(NA_character_, 3))
  calls <- thematic_calls(server, "/sotwis/ttr-flags")
  expect_identical(vapply(calls, `[[`, "", "method"), c("get", "get"))
  expect_identical(calls[[1]]$query, "claf=CMe&layer=D1&view=raw&limit=2&offset=0")
  expect_identical(calls[[2]]$query, "claf=CMe&layer=D1&view=raw&limit=2&offset=2")
  meta <- soil_metadata(f)
  expect_identical(meta$view, "raw")
  expect_identical(meta$total_count, 3)
  expect_true(meta$complete)
  expect_identical(nrow(soil_ttr_flags(soil, max_rows = 1)), 1L)
})

test_that("soil_ttr_flags() with the revised view and its gates", {
  soil <- thematic_session(server)
  f <- soil_ttr_flags(soil, prid = "TN-AB1", view = "revised")
  expect_identical(soil_metadata(f)$view, "revised")
  expect_identical(soil_metadata(f)$revised$rules[[1]]$id, "R6")
  thematic_reset(server)
  expect_error(soil_ttr_flags(soil, prid = c("a", "b")), class = "soilhub_argument_error")
  expect_error(soil_ttr_flags(soil, view = "fixed"), class = "soilhub_argument_error")
  soil <- thematic_session(server, capabilities_with(revised_view = FALSE))
  e <- expect_error(soil_ttr_flags(soil, view = "revised"), class = "soilhub_capability_error")
  expect_identical(e$capability, "revised_view")
  soil <- thematic_session(server, capabilities_with(sotwis_ttr_flags = FALSE))
  e <- expect_error(soil_ttr_flags(soil), class = "soilhub_capability_error")
  expect_identical(e$capability, "sotwis_ttr_flags")
  expect_length(thematic_calls(server), 0L)
})

# ---------------------------------------------------------------------------
# Capability and rights gates

test_that("each thematic read checks its own capability before any request", {
  thematic_reset(server)
  gates <- list(
    query_generic_values = function(soil) soil_values(soil, progress = FALSE),
    query_soil_health = function(soil) soil_health_summary(soil),
    target_resolution = function(soil) soil_resolve_targets(soil, target_keys("1"))
  )
  for (name in names(gates)) {
    soil <- thematic_session(server, do.call(capabilities_with, stats::setNames(list(FALSE), name)))
    e <- expect_error(gates[[name]](soil), class = "soilhub_capability_error")
    expect_identical(e$capability, name)
  }
  soil <- thematic_session(server, capabilities_with(query_soil_health = FALSE))
  expect_error(soil_health_scores(soil, progress = FALSE), class = "soilhub_capability_error")
  soil <- thematic_session(server, capabilities_with(query_generic_values = FALSE))
  expect_error(soil_values_summary(soil), class = "soilhub_capability_error")
  soil <- thematic_session(server, capabilities_with(country_filtering = FALSE))
  e <- expect_error(soil_values(soil, country = "KEN", progress = FALSE), class = "soilhub_capability_error")
  expect_identical(e$capability, "country_filtering")
  expect_error(soil_health_scores(soil, country = "KEN", progress = FALSE), class = "soilhub_capability_error")
  expect_length(thematic_calls(server), 0L)
  # a capability the server does not advertise: a warning, the request goes
  soil <- thematic_session(server, capabilities_with(target_resolution = NULL))
  expect_warning(res <- soil_resolve_targets(soil, target_keys("1")), class = "soilhub_capability_warning")
  expect_identical(res$status, "resolved")
})

test_that("reads need soil:read and summaries soil:summary when the token declares its rights", {
  soil <- write_session(server, "jwt-emptyroles.json")
  thematic_reset(server)
  for (call in list(
    function() soil_values(soil, progress = FALSE),
    function() soil_health_scores(soil, progress = FALSE),
    function() soil_resolve_targets(soil, target_keys("1")),
    function() soil_ttr_flags(soil)
  )) {
    e <- expect_error(call(), class = "soilhub_permission_error")
    expect_identical(e$required_right, "soil:read")
  }
  for (call in list(
    function() soil_summary(soil, datasets = "wosis_points"),
    function() soil_availability(soil, datasets = "wosis_points"),
    function() soil_consistency(soil),
    function() soil_values_summary(soil),
    function() soil_health_summary(soil)
  )) {
    e <- expect_error(call(), class = "soilhub_permission_error")
    expect_identical(e$required_right, "soil:summary")
  }
  expect_length(thematic_calls(server), 0L)
})

test_that("with_geometry = \"sf\" gives sf values and health tables, and needs sf", {
  skip_if_not_installed("sf")
  soil <- thematic_session(server)
  v <- soil_values(soil, max_rows = 2, with_geometry = "sf", progress = FALSE)
  expect_s3_class(v, c("soil_table", "sf", "data.frame"), exact = TRUE)
  expect_identical(attr(v, "sf_column"), "geometry")
  expect_identical(sf::st_crs(v)$epsg, 4326L)
  expect_identical(sf::st_as_text(sf::st_geometry(v))[1], "POINT (36.8 -1.3)")
  expect_identical(match("geometry", names(v)), match("geometry_kind", names(v)) + 1L)
  expect_identical(v$value, c(41.5, 38.25))
  expect_identical(soil_metadata(v)$crs, "EPSG:4326")
  h <- soil_health_scores(soil, with_geometry = "sf", progress = FALSE)
  expect_s3_class(h, c("soil_table", "sf", "data.frame"), exact = TRUE)
  expect_match(sf::st_as_text(sf::st_geometry(h))[1], "^MULTIPOLYGON")

  local_mocked_bindings(soil_has_package = function(package) FALSE)
  thematic_reset(server)
  e <- expect_error(soil_values(soil, with_geometry = "sf"), class = "soilhub_dependency_error")
  expect_match(conditionMessage(e), "`soil_values()`", fixed = TRUE)
  expect_error(soil_health_scores(soil, with_geometry = "sf"), class = "soilhub_dependency_error")
  expect_length(thematic_calls(server), 0L)
})
