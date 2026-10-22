# Variable catalog and source mappings (design 4.3) against the fake API.

api <- fake_catalog_api()

test_that("soil_variables() types every field and keeps the metadata", {
  soil <- catalog_session(api)
  v <- soil_variables(soil, include_unmapped = TRUE)
  expect_identical(v$variable_code, c("carbon_nitrogen_ratio", "organic_carbon"))
  types <- vapply(v, function(column) class(column)[1], character(1))
  expect_identical(unname(types[c("variable_code", "name", "domain_code", "property_family", "documentation_url")]), rep("character", 5))
  expect_identical(unname(types[c("value_count", "feature_count", "min_depth_cm", "max_depth_cm")]), rep("numeric", 4))
  expect_identical(unname(types[c("valid_time_start", "valid_time_end")]), rep("POSIXct", 2))
  expect_identical(unname(types[c("allowed_target_levels", "datasets", "providers", "statuses",
                                  "product_versions", "coverage", "source_mappings")]), rep("list", 7))
  expect_identical(v$allowed_target_levels[[2]], c("horizon", "profile"))
  expect_identical(v$datasets[[1]], character())
  expect_null(v$coverage[[1]])
  expect_identical(v$coverage[[2]]$type, "Polygon")
  expect_identical(format(v$valid_time_end[2], "%Y-%m-%d"), "2025-01-01")
  expect_true(is.na(v$min_depth_cm[1]))

  mappings <- v$source_mappings[[2]]
  expect_s3_class(mappings, "data.frame")
  expect_identical(mappings$dataset_code, c("wise_profiles", "wosis_points"))
  facets <- mappings$method_facets[[2]]
  expect_s3_class(facets, "data.frame")
  expect_identical(facets$element_count, c(61204, 48890))
  expect_identical(facets$source_dataset_counts[[1]]$`US-NCSS`, 40211L)

  meta <- attr(v, "soil_metadata")
  expect_identical(meta$variable_count, 2L)
  expect_s3_class(meta$unmapped_source_codes, "data.frame")
  expect_identical(meta$unmapped_source_codes$source_code, "TAWK")
  expect_identical(meta$request, list(include_unmapped = TRUE))
  expect_identical(meta$received_query, "include_unmapped=true")
})

test_that("filters are sent with the API names, repeated, never \"ALL\"", {
  soil <- catalog_session(api)
  v <- soil_variables(soil, code = c("organic_carbon", "clay"), dataset = "wosis_points",
                      available_only = TRUE)
  expect_identical(
    attr(v, "soil_metadata")$received_query,
    "code=organic_carbon&code=clay&dataset=wosis_points&available_only=true"
  )
  err <- tryCatch(soil_variables(soil, domain = "ALL"), soilhub_argument_error = function(e) e)
  expect_s3_class(err, "soilhub_argument_error")
  expect_identical(err$argument, "domain")
  expect_match(conditionMessage(err), "use `domain = NULL`", fixed = TRUE)
  expect_error(soil_variables(soil, code = NA_character_), class = "soilhub_argument_error")
  expect_error(soil_variables(soil, available_only = NA), class = "soilhub_argument_error")
})

test_that("soil_variable_mappings() lists one row per mapping, original terms kept", {
  soil <- catalog_session(api)
  m <- soil_variable_mappings(soil)
  expect_identical(nrow(m), 3L)
  expect_identical(names(m), c(
    "variable_code", "provider_code", "dataset_code", "source_code", "source_official_code",
    "source_label", "source_unit", "procedure_code", "procedure_description",
    "source_value_kind", "mapping_status", "documentation_url", "semantic_status",
    "unit_status", "unit_evidence", "source_notes", "source_scope", "method_facets"
  ))
  expect_identical(m$variable_code, c("carbon_nitrogen_ratio", "organic_carbon", "organic_carbon"))
  cnrt <- m[m$source_code == "CNrt", ]
  expect_true(is.na(cnrt$source_unit))
  expect_identical(cnrt$unit_status, "not_recorded")
  expect_identical(cnrt$unit_evidence[[1]]$reason, "The source gives no unit for CNrt.")
  expect_identical(m$source_code[3], "orgc_value_avg")
  expect_identical(m$source_official_code[3], "ORGC")
  expect_identical(nrow(m$method_facets[[3]]), 2L)

  # on a soil_variables() result, without a request
  v <- soil_variables(soil)
  expect_identical(soil_variable_mappings(v), m)
  empty <- soil_variable_mappings(v[0, ])
  expect_identical(nrow(empty), 0L)
  expect_identical(names(empty), names(m))
  expect_error(soil_variable_mappings(data.frame(x = 1)), class = "soilhub_argument_error")
})
