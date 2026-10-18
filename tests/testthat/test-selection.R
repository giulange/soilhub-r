# The selection (design 4.1): validation and translation to the request body,
# without any request.

test_that("the selection becomes the API body with arrays and canonical = TRUE", {
  body <- soil_selection(datasets = "wosis_points", variables = c("ORGC", "clay"),
                         bbox = c(10.5, 44, 11.2, 44.6), country = "ken")
  expect_identical(body$datasets, I("wosis_points"))
  expect_identical(body$variables, I(c("ORGC", "clay")))
  expect_identical(body$country, I("ken"))
  expect_identical(body$bbox, c(10.5, 44, 11.2, 44.6))
  expect_identical(body$geometry, "any")
  expect_identical(body$layer, "all")
  expect_identical(body$view, "raw")
  expect_true(body$canonical)
  expect_null(body$profile_type)
  expect_false("components" %in% names(body))
  json <- request_body_json(body)
  expect_match(json, "\"datasets\":[\"wosis_points\"]", fixed = TRUE)
  expect_match(json, "\"country\":[\"ken\"]", fixed = TRUE)
  expect_match(json, "\"view\":\"raw\"", fixed = TRUE)
  # the selection given (defaults left out), for messages and the export hint
  expect_identical(attr(body, "selection"), list(
    datasets = "wosis_points", variables = c("ORGC", "clay"),
    bbox = c(10.5, 44, 11.2, 44.6), country = "ken"
  ))
})

test_that("profile_type, components and min_cumulative_percent follow the API rules", {
  body <- soil_selection(datasets = "sotwis_polygons", profile_type = c("!synthetic", "!virtual"),
                         components = "cumulative", min_cumulative_percent = 80)
  expect_identical(body$profile_type, I(c("!synthetic", "!virtual")))
  expect_identical(body$components, "cumulative")
  expect_identical(body$min_cumulative_percent, 80)
  expect_identical(soil_selection(profile_type = "none")$profile_type, I("none"))
})

test_that("bad selection arguments are argument errors naming the argument", {
  expect_argument_error <- function(expr, argument, pattern) {
    e <- expect_error(expr, class = "soilhub_argument_error")
    expect_identical(e$argument, argument)
    expect_match(conditionMessage(e), pattern)
  }
  expect_argument_error(soil_selection(datasets = "ALL"), "datasets", "use `datasets = NULL`")
  expect_argument_error(soil_selection(datasets = c("wosis_points", NA)), "datasets", "without NA")
  expect_argument_error(soil_selection(variables = 1), "variables", "character vector")
  expect_argument_error(soil_selection(country = character()), "country", "NULL \\(no filter\\)")
  expect_argument_error(soil_selection(bbox = c(1, 2, 3)), "bbox", "four numbers")
  expect_argument_error(soil_selection(bbox = c(11, 44, 10, 45)), "bbox", "xmin < xmax")
  expect_argument_error(soil_selection(bbox = c(-200, 0, 10, 10)), "bbox", "WGS84 bounds")
  expect_argument_error(soil_selection(bbox = c(0, NA, 1, 1)), "bbox", "four numbers")
  expect_argument_error(soil_selection(geometry = "line"), "geometry", "\"any\", \"point\", \"polygon\"")
  expect_argument_error(soil_selection(layer = "top"), "layer", "\"all\", \"first\"")
  expect_argument_error(soil_selection(view = "fixed"), "view", "\"raw\", \"revised\"")
  expect_argument_error(soil_selection(view = c("raw", "revised")), "view", "must be one of")
  expect_argument_error(soil_selection(profile_type = c("synthetic", "!virtual")), "profile_type", "not both")
  expect_argument_error(soil_selection(profile_type = "measured"), "profile_type", "Unknown `profile_type`")
  expect_argument_error(soil_selection(profile_type = "ALL"), "profile_type", "profile_type = NULL")
  expect_argument_error(soil_selection(components = "largest"), "components", "\"representative\"")
  expect_argument_error(soil_selection(components = "cumulative"), "min_cumulative_percent", "needs `min_cumulative_percent`")
  expect_argument_error(soil_selection(min_cumulative_percent = 50), "min_cumulative_percent", "only with")
  expect_argument_error(soil_selection(components = "cumulative", min_cumulative_percent = 120),
                        "min_cumulative_percent", "0 to 100")
})

test_that("the accepted values come from the server's capabilities when listed", {
  caps <- read_fixture("capabilities.json")
  caps$views$values <- list("raw", "revised", "experimental")
  caps$profile_types$values <- list("synthetic", "virtual", "none", "reference")
  soil <- list(capabilities = caps)
  expect_identical(soil_selection(soil, view = "experimental")$view, "experimental")
  expect_identical(soil_selection(soil, profile_type = "!reference")$profile_type, I("!reference"))
  # without capabilities: the package constants
  expect_error(soil_selection(NULL, view = "experimental"), class = "soilhub_argument_error")
})
