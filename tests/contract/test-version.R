# The version range of the client against `info.version` (design 7.2, 9.1).

test_that("the API version of the document is supported by the client", {
  doc <- contract_openapi()
  version <- doc$info$version
  expect_true(is_string(version), info = "the OpenAPI document has no info.version")
  verdict <- check_api_version(version)
  expect_true(
    isTRUE(verdict$compatible),
    info = sprintf("API %s: %s", version, verdict$message %||% verdict$status)
  )
  if (identical(verdict$status, "newer_minor")) {
    # compatible; users see the message at soil_connect()
    warning(sprintf(
      "API %s is a newer minor than TESTED_API_VERSION %s: soil_connect() tells users \"%s\"",
      version, TESTED_API_VERSION, verdict$message
    ), call. = FALSE)
  }
})

test_that("TESTED_API_VERSION is the version of the committed snapshot", {
  snapshot <- jsonlite::fromJSON(
    file.path(contract_root(), "tests", "contract", "openapi.json"), simplifyVector = FALSE
  )
  expect_true(
    identical(TESTED_API_VERSION, snapshot$info$version),
    info = sprintf(
      "TESTED_API_VERSION is %s (R/capabilities.R), the snapshot is API %s: refresh both with tools/update_contract_snapshots.R",
      TESTED_API_VERSION, snapshot$info$version %||% "none"
    )
  )
})

test_that("the document describes the API under the client prefix", {
  doc <- contract_openapi()
  prefix <- openapi_prefix()
  paths <- names(doc$paths)
  expect_gt(length(paths), 0L)
  expect_no_drift(
    sprintf("path %s is not under the client prefix %s", paths[!startsWith(paths, prefix)], prefix),
    "OpenAPI paths outside the client api_url"
  )
})
