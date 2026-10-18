# The soil_table class and the result helpers (design 4.7, 5.1), no server.

results_table <- function(file = c("wide-wosis-page1.json", "wide-wosis-page2.json")) {
  soil <- new_soil_session(soil_config(api_url = "http://127.0.0.1:9/api/v1", timeout = 5, verbose = 0))
  observations_table(soil, do.call(fixture_pages, as.list(file)), fetch_catalog = FALSE)
}

test_that("[ keeps the class and the attributes; as.data.frame drops them", {
  x <- results_table()
  y <- x[x$dataset == "wosis_points" & !is.na(x$clay) & x$clay > 25, ]
  expect_s3_class(y, "soil_table")
  expect_identical(nrow(y), 3L)
  expect_identical(soil_metadata(y), soil_metadata(x))
  expect_identical(attr(y, "soil_layout"), "wide")
  z <- x[, c("horizon_id", "clay")]
  expect_s3_class(z, "soil_table")
  expect_identical(names(z), c("horizon_id", "clay"))
  expect_s3_class(x["clay"], "soil_table")
  # a single column with drop as data frames do
  expect_identical(x[, "clay"], x$clay)
  expect_identical(x[2, "horizon_id"], "h-2")
  d <- as.data.frame(x)
  expect_identical(class(d), "data.frame")
  expect_null(attr(d, "soil_metadata"))
  expect_null(attr(d, "soil_layout"))
})

test_that("print shows the header and list columns as <list>", {
  x <- results_table()
  out <- capture.output(print(x, n = 2))
  expect_identical(out[1], "# soilhub wide table: 5 horizons, 3 features, 5 variables | wosis_points | view raw, layer all")
  expect_identical(out[2], "# 2 API warnings (soil_warnings), typing (soil_columns), cite with soil_citations()")
  expect_true(any(grepl("<list>", out, fixed = TRUE)))
  expect_match(out[length(out)], "# ... 3 more row(s)", fixed = TRUE)
  empty <- x[0, ]
  expect_match(capture.output(print(empty))[3], "no rows")
})

test_that("summary shows the typing of the columns and the rows per dataset", {
  x <- results_table()
  s <- summary(x)
  expect_s3_class(s, "soil_table_summary")
  expect_identical(s$datasets$rows, 5L)
  expect_null(s$revised_rules)
  out <- capture.output(print(s))
  expect_true(any(grepl("Variable columns", out)))
  expect_true(any(grepl("coarse_fragments", out)))
  expect_true(any(grepl("g/cm3, kg/dm3", out, fixed = TRUE)))
})

test_that("soil_flags() and soil_markings() are long data frames", {
  x <- results_table()
  flags <- soil_flags(x)
  expect_identical(names(flags), c("row", "horizon_id", "column", "flag"))
  expect_identical(flags$row, c(1L, 3L, 3L, 3L))
  expect_identical(flags$flag, c("extreme", "trace_convention", "extreme", "above_unit_maximum"))
  m <- soil_markings(x)
  expect_identical(names(m), c("row", "horizon_id", "scope", "column", "marking", "value"))
  expect_identical(unique(m$scope), c("cell", "layer", "retired_cell"))
  cell <- m[m$scope == "cell" & m$row == 1L, ]
  expect_identical(cell$marking, c("value_count", "value_spread", "source_method_kind", "method_facets"))
  expect_identical(cell$value[1:3], c("2", "0.2", "field estimate"))
  layer <- m[m$scope == "layer" & m$row == 5L, ]
  expect_identical(layer$value, c("wg1500_gt_wg0033", "orgc_gt_totc"))
  retired <- m[m$scope == "retired_cell", ]
  expect_identical(retired$column, "clay")
  expect_identical(retired$value, "2026-10-01_isric")
  # a table without markings gives zero rows
  s <- results_table("wide-sotwis.json")
  expect_identical(nrow(soil_flags(s)), 0L)
  expect_identical(soil_markings(s)$value, "SOVEUR v2")
  f <- results_table("wide-first-layer.json")
  pm <- soil_markings(f)
  expect_identical(pm$marking, rep("profile_markings", 5))
  expect_identical(pm$value[1], "numbering_starts_at_2")
})

test_that("the helpers refuse objects that are not results", {
  expect_error(soil_metadata(data.frame(a = 1)), class = "soilhub_argument_error")
  expect_error(soil_columns(structure(list(), soil_metadata = list(variables = NULL))),
               class = "soilhub_argument_error")
  expect_error(soil_flags(list()), class = "soilhub_argument_error")
  # a list result with `metadata` (summaries, exports)
  expect_identical(soil_warnings(list(metadata = list(warnings = list("a", "b")))), c("a", "b"))
  expect_identical(soil_warnings(list(metadata = list())), character())
})
