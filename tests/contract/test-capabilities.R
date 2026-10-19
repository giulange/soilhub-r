# The keys the client reads from GET /capabilities, against the snapshot
# recorded by the owner (tools/record_fixtures.R; design 7.2).

capabilities_snapshot <- function() {
  path <- file.path(contract_root(), "tests", "contract", "capabilities.json")
  if (!file.exists(path)) {
    testthat::skip(paste(
      "tests/contract/capabilities.json is not recorded yet:",
      "the owner runs `Rscript tools/record_fixtures.R` (device login) once"
    ))
  }
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

test_that("the recorded API version and required capabilities are supported", {
  caps <- capabilities_snapshot()
  verdict <- check_api_version(caps$api_version)
  expect_true(isTRUE(verdict$compatible), info = verdict$message %||% verdict$status)
  expect_no_drift(
    sprintf("required capability `%s` is not TRUE", missing_required(caps)),
    "Required capabilities"
  )
})

test_that("the optional capabilities the client checks are advertised", {
  caps <- capabilities_snapshot()
  absent <- setdiff(OPTIONAL_CAPABILITIES, names(caps$capabilities))
  expect_no_drift(
    sprintf("optional capability `%s` is not advertised: soilhub warns and lets the API decide", absent),
    "Optional capabilities"
  )
})

test_that("limits, views, profile types and exports have the keys the client reads", {
  caps <- capabilities_snapshot()
  problems <- character()
  for (key in "max_page_size") { # read by resolve_page_size() (config.R)
    if (!is.numeric(caps$limits[[key]])) problems <- c(problems, sprintf("limits$%s is not a number", key))
  }
  if (!identical(caps$authentication$audience, default_audience)) {
    problems <- c(problems, sprintf("authentication$audience is \"%s\", the client expects \"%s\"",
                                    caps$authentication$audience %||% "none", default_audience))
  }
  problems <- c(problems,
    contract_check_enum(selection_values$view, unlist(caps$views$values), "views$values (selection_values$view)"),
    contract_check_enum(selection_values$profile_type, unlist(caps$profile_types$values),
                        "profile_types$values (selection_values$profile_type)")
  )
  if (!identical(caps$profile_types$exclude_prefix, profile_type_exclude_prefix)) {
    problems <- c(problems, sprintf("profile_types$exclude_prefix is \"%s\", the client uses \"%s\"",
                                    caps$profile_types$exclude_prefix %||% "none", profile_type_exclude_prefix))
  }
  layouts <- eval(formals(soil_observations)$layout, baseenv())
  if (!is.null(caps$exports$layouts)) {
    problems <- c(problems, contract_check_enum(layouts, unlist(caps$exports$layouts), "exports$layouts (soil_observations(layout))"))
  }
  expect_no_drift(problems, "Capabilities read by the client")
})
