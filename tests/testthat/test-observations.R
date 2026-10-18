# soil_observations() wide (design 4.4, 5.2, 5.4, 6.3) against the fake wide
# API (helper-fake-wide.R).

api <- fake_wide_api()

test_that("a wide read sends the selection and pages to the end", {
  soil <- wide_session(api)
  x <- soil_observations(soil, datasets = "wosis_points", country = "KEN", page_size = 3,
                         progress = FALSE)
  expect_s3_class(x, "soil_table")
  expect_identical(nrow(x), 5L)
  meta <- soil_metadata(x)
  expect_identical(meta$pages, 2L)
  expect_true(meta$complete)
  expect_true(is.na(meta$next_offset))
  expect_true(is.na(meta$total_count))
  expect_length(meta$request_ids, 2L)
  expect_true(all(grepl(request_id_pattern, meta$request_ids)))
  expect_identical(meta$endpoint, "/query/observations")
  # the body sent (filters echoed by the fake API)
  sent <- meta$filters
  expect_identical(sent$datasets, list("wosis_points"))
  expect_identical(sent$country, list("KEN"))
  expect_identical(sent$view, "raw")
  expect_identical(sent$layer, "all")
  expect_identical(sent$geometry, "any")
  expect_true(sent$canonical)
  expect_identical(sent$layout, "wide")
  expect_identical(sent$geometry_format, "none")
  expect_identical(sent$limit, 3L)
  expect_identical(meta$request$datasets, I("wosis_points"))
  expect_null(meta$request$limit)
  expect_identical(meta$selection, list(datasets = "wosis_points", country = "KEN"))
  # metadata of 5.4
  expect_identical(meta$view, "raw")
  expect_identical(meta$crs, "EPSG:4326")
  expect_identical(meta$api_version, "0.5.0")
  expect_identical(meta$schema_version, "1.0")
  expect_identical(meta$client_version, as.character(utils::packageVersion("soilhub")))
  expect_identical(meta$multi_value_rule, "mean")
  expect_setequal(soil_warnings(x), c(
    "column 'coarse_fragments' has 2 multi-value cell(s) returned as JSON text",
    "column 'src_dens' mixes units ['g/cm3', 'kg/dm3']"
  ))
  # catalog rows of the datasets read: what soil_citations() reads
  expect_s3_class(meta$datasets, "data.frame")
  expect_identical(meta$datasets$name, "wosis_points")
  expect_identical(soil_citations(x)$dataset, "wosis_points")
  # no geometry asked: none returned
  expect_false("geometry_kind" %in% names(x))
  expect_identical(x$coarse_fragments_values[[1]], c("0.9", "1.1"))
})

test_that("with_geometry = \"text\" asks for WKT and copies it to the rows", {
  soil <- wide_session(api)
  x <- soil_observations(soil, datasets = "wosis_points", with_geometry = "text", progress = FALSE)
  expect_identical(soil_metadata(x)$filters$geometry_format, "wkt")
  expect_identical(x$geometry_text[4:5], rep("POINT(38.25 0.5)", 2))
  expect_identical(x$geometry_kind[1], "POINT")
})

test_that("max_rows and offset bound the read", {
  soil <- wide_session(api)
  x <- soil_observations(soil, datasets = "wosis_points", max_rows = 2, progress = FALSE)
  expect_identical(nrow(x), 2L)
  meta <- soil_metadata(x)
  expect_false(meta$complete)
  expect_identical(meta$next_offset, 2)
  expect_match(capture.output(print(x))[3], "incomplete read: continue with offset = 2")
  y <- soil_observations(soil, datasets = "wosis_points", offset = 3, progress = FALSE)
  expect_identical(y$horizon_id, c("h-4", "h-5"))
  expect_identical(soil_metadata(y)$filters$offset, 3L)
})

test_that("argument errors come before any request", {
  soil <- wide_session(api)
  before <- api_requests(api)
  bad <- list(
    list(datasets = "ALL"), list(bbox = c(0, 0, 0, 0)), list(view = "fixed"),
    list(layer = "top"), list(profile_type = "measured"),
    list(components = "cumulative"), list(min_cumulative_percent = 10),
    list(layout = "tall"), list(with_geometry = "wkb"), list(too_large = "split"),
    list(max_rows = 0), list(offset = -1), list(offset = 1.5), list(page_size = 0),
    list(timeout = -1), list(progress = NA),
    list(layout = "long"), list(with_geometry = "sf")
  )
  for (args in bad) {
    call_args <- utils::modifyList(list(soil, datasets = "wosis_points"), args)
    e <- expect_error(do.call(soil_observations, call_args),
                      class = "soilhub_argument_error")
    expect_false(is.null(e$argument))
  }
  expect_identical(api_requests(api), before)
})

test_that("a missing right or capability stops before the request", {
  soil <- wide_session(api)
  soil$state$identity <- list(rights_known = TRUE, roles = "soil:summary", audience = "soil-api")
  before <- api_requests(api)
  e <- expect_error(soil_observations(soil, datasets = "wosis_points"), class = "soilhub_permission_error")
  expect_identical(e$required_right, "soil:read")
  soil <- wide_session(api, capabilities = capabilities_with(revised_view = FALSE))
  e <- expect_error(soil_observations(soil, datasets = "wosis_points", view = "revised"),
                    class = "soilhub_capability_error")
  expect_identical(e$capability, "revised_view")
  expect_identical(api_requests(api), before)
})

test_that("too_large = \"stop\": the load-limit error names the export call", {
  soil <- wide_session(api)
  e <- expect_error(soil_observations(soil, country = "BRA", layer = "first", progress = FALSE),
                    class = "soilhub_load_limit_error")
  expect_identical(e$status, 422L)
  expect_identical(e$channel, "sync")
  expect_identical(e$max_observations, 1000000L)
  expect_false(e$observation_count_exact)
  expect_identical(e$exports_url, "/api/v1/exports")
  expect_identical(e$selection, list(country = "BRA", layer = "first"))
  expect_identical(e$request$layout, "wide")
  expect_true(e$request$canonical)
  msg <- conditionMessage(e)
  expect_match(msg, "^The selection holds more than 1,000,000 observations, above the limit of synchronous requests")
  expect_match(msg, paste0(
    "To export the same selection: soil_export(soil, country = \"BRA\", layer = \"first\", format = \"gpkg\")\n",
    "or rerun with too_large = \"export\"."
  ), fixed = TRUE)
  expect_match(msg, "request id soilhub-", fixed = TRUE)
  # too_large = "export" is not available yet: same error, with a note
  e <- expect_error(soil_observations(soil, too_large = "export", progress = FALSE),
                    class = "soilhub_load_limit_error")
  expect_match(conditionMessage(e), "soil_export(soil, format = \"gpkg\")", fixed = TRUE)
  expect_match(conditionMessage(e), "too_large = \"export\"` is not available", fixed = TRUE)
})

test_that("a failure after some pages keeps them as a typed partial soil_table", {
  soil <- wide_session(api)
  e <- expect_error(
    soil_observations(soil, datasets = "wosis_points", country = "FAIL", page_size = 3, progress = FALSE),
    class = "soilhub_api_error"
  )
  expect_identical(e$status, 500L)
  partial <- e$partial
  expect_s3_class(partial, "soil_table")
  expect_identical(nrow(partial), 3L)
  meta <- soil_metadata(partial)
  expect_false(meta$complete)
  expect_identical(meta$next_offset, 3)
  expect_identical(meta$stop_reason, "error")
  expect_identical(partial$coarse_fragments, c(1, 4, NA))
  expect_match(conditionMessage(e), "continue from offset 3", fixed = TRUE)
  expect_output(print(e), "partial: 3 row\\(s\\) read, next_offset = 3")
  # continue from the offset
  rest <- soil_observations(soil, datasets = "wosis_points", offset = meta$next_offset, progress = FALSE)
  expect_identical(rest$horizon_id, c("h-4", "h-5"))
})

test_that("view = \"revised\" reports the rules with their counts", {
  soil <- wide_session(api)
  x <- soil_observations(soil, datasets = c("wosis_points", "sotwis_polygons"), view = "revised",
                         progress = FALSE)
  meta <- soil_metadata(x)
  expect_identical(meta$view, "revised")
  expect_identical(meta$filters$view, "revised")
  rules <- soil_revised_rules(x)
  expect_identical(names(rules), c("id", "title", "issue", "effect", "n"))
  expect_identical(rules$id, c("R6", "R12", "R12", "R16", "R17"))
  expect_identical(rules$effect, c(NA, "values_flagged:extreme", "values_hidden", "values_changed", "values_hidden"))
  expect_identical(rules$n, c(NA, 12, 3, 40, 1))
  pairs <- attr(rules, "pairs")
  expect_identical(pairs$summary_prid, "TN-ab1")
  expect_identical(pairs$estimate_prid, "TN-AB1")
  expect_identical(pairs$CLAF, "CMe")
  expect_match(attr(rules, "scope"), "counts over the selection")
  expect_length(attr(rules, "unchanged"), 2L)
  markings <- soil_markings(x)
  hidden <- markings[markings$scope == "hidden_value", ]
  expect_identical(hidden$column, c("BDFIFM", "PHPRTN"))
  expect_identical(hidden$marking, c("R17", "R12"))
  expect_identical(hidden$value, c("[\"1.2\",\"guessed value, expert field estimate\"]", "140"))
  cell <- markings[markings$scope == "revised_cell", ]
  expect_identical(cell$column, "sand")
  expect_identical(cell$marking, "texture_normalized")
  expect_identical(cell$value, "{\"original_sum\":102}")
  out <- capture.output(summary(x))
  expect_true(any(grepl("Revised rules applied", out)))
  expect_true(any(grepl("values_flagged:extreme", out)))
  # the raw view has no rules
  y <- soil_observations(soil, datasets = "wise_profiles", progress = FALSE)
  expect_identical(nrow(soil_revised_rules(y)), 0L)
})

test_that("layer = \"first\" reports the first-layer vocabulary", {
  soil <- wide_session(api)
  x <- soil_observations(soil, datasets = "soter_profiles", layer = "first", progress = FALSE)
  expect_identical(soil_metadata(x)$filters$layer, "first")
  first <- soil_first_layer(x)
  expect_identical(first$view, "raw")
  expect_identical(first$statuses, c("surface", "tie", "not_surface", "depth_missing"))
  expect_true("numbering_starts_at_N" %in% first$profile_markings)
  expect_identical(x$first_layer_status, c("surface", "tie", "tie"))
  expect_match(capture.output(print(x))[1], "layer first")
  y <- soil_observations(soil, datasets = "soter_profiles", progress = FALSE)
  expect_null(soil_first_layer(y))
  expect_identical(y$source_profile_type, c("synthetic", NA))
})

test_that("components and profile_type are sent as the API expects", {
  soil <- wide_session(api)
  x <- soil_observations(soil, datasets = "sotwis_polygons", components = "cumulative",
                         min_cumulative_percent = 70, profile_type = "!synthetic", progress = FALSE)
  sent <- soil_metadata(x)$filters
  expect_identical(sent$components, "cumulative")
  expect_identical(sent$min_cumulative_percent, 70L)
  expect_identical(sent$profile_type, list("!synthetic"))
  expect_identical(x$proportion_percent, c(60, 40))
})
