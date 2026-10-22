# Country inventory, code lists and the SOTWIS flag legend (design 4.3)
# against the fake API.

api <- fake_catalog_api()

test_that("soil_countries() types the inventory and keeps the assignment rule", {
  soil <- catalog_session(api)
  countries <- soil_countries(soil)
  expect_identical(countries$iso_a3, c("ATA", "KEN", "TUN"))
  expect_identical(names(countries), c(
    "iso_a2", "iso_a3", "name", "dataset_count", "feature_count", "point_count",
    "polygon_count", "profile_count", "horizon_count", "original_observation_count",
    "value_count", "observation_count", "variable_count", "as_of"
  ))
  expect_true(all(vapply(countries[4:13], is.double, logical(1))))
  expect_s3_class(countries$as_of, "POSIXct")
  expect_true(is.na(countries$as_of[1]))
  expect_identical(countries$profile_count[2], 9214)
  expect_identical(attr(countries, "country_assignment"), "intersects")
  expect_identical(attr(countries, "soil_metadata")$total_count, 3L)
})

test_that("soil_country() returns the country, its datasets and variables", {
  soil <- catalog_session(api)
  kenya <- soil_country(soil, "ken")
  expect_named(kenya, c("country", "datasets", "variables", "as_of", "country_assignment"))
  expect_identical(nrow(kenya$country), 1L)
  expect_identical(kenya$country$name, "Kenya")
  expect_s3_class(kenya$country$refreshed_at, "POSIXct")
  expect_identical(kenya$datasets$dataset_code, c("sotwis_polygons", "wosis_points"))
  expect_identical(kenya$datasets$polygon_count, c(6109, 0))
  expect_true(is.na(kenya$datasets$refresh_job_id[2]))
  expect_identical(kenya$variables$observation_count, c(40210, 9817))
  expect_identical(format(kenya$as_of, "%Y-%m-%d %H:%M"), "2026-10-18 02:15")
  expect_identical(kenya$country_assignment, "intersects")

  withr::local_options(soilhub.session = soil)
  expect_identical(soil_country("KE")$country$iso_a3, "KEN")
  expect_error(soil_country(soil, "Kenya"), class = "soilhub_argument_error")
  expect_error(soil_country(soil, "BRA"), class = "soilhub_not_found_error")
})

test_that("country functions need the country inventory capability", {
  soil <- catalog_session(api, capabilities = capabilities_with(country_inventory = FALSE))
  expect_error(soil_countries(soil), class = "soilhub_capability_error")
  expect_error(soil_country(soil, "KEN"), class = "soilhub_capability_error")
})

test_that("code lists are listed and read verbatim", {
  soil <- catalog_session(api)
  lists <- soil_code_lists(soil)
  expect_identical(lists$code_list, "SOTWIS_codes")
  expect_identical(lists$row_count, 1527)
  expect_identical(lists$attributes[[1]], c("CLAF", "CLAF_m", "DRAI", "ISOC", "LITH", "LNDF", "PHAS"))
  expect_s3_class(lists$source_datasets[[1]], "data.frame")
  expect_identical(nrow(lists$source_datasets[[1]]), 3L)

  codes <- soil_code_list(soil, "SOTWIS_codes", attribute = "LNDF", source_dataset = "sotwis_senegal_gambia")
  expect_identical(names(codes), c(
    "attribute", "code", "description", "source_record_id", "source_dataset_name",
    "source_table", "source_row_number", "provider_code"
  ))
  expect_identical(codes$code, c("LP", "SM"))
  expect_identical(codes$description[2], "medium-gradient mountain")
  expect_type(codes$source_row_number, "integer")
  expect_identical(attr(codes, "soil_metadata")$received_query, "attribute=LNDF&source_dataset=sotwis_senegal_gambia")

  withr::local_options(soilhub.session = soil)
  expect_identical(nrow(soil_code_list("SOTWIS_codes")), 2L)
  expect_error(soil_code_list(soil, "SOTER_codes"), class = "soilhub_not_found_error")
  expect_error(soil_code_list(soil, "SOTWIS_codes", code = "ALL"), class = "soilhub_argument_error")
})

test_that("the TTR flag legend is typed, undocumented codes kept", {
  soil <- catalog_session(api)
  legend <- soil_ttr_flag_legend(soil)
  expect_identical(legend$symbol, c("A", "Z", "X"))
  expect_identical(legend$flag_columns[[1]], c("TTRsub", "TTRmain"))
  expect_identical(legend$documented, c(TRUE, TRUE, FALSE))
  expect_true(is.na(legend$meaning[3]))
  expect_null(legend$applies_to[[1]])
  expect_s3_class(legend$applies_to[[2]], "data.frame")
  expect_identical(legend$applies_to[[2]]$source_dataset_name, "sotwis_central_africa")
  expect_identical(attr(legend, "soil_metadata")$source_table, "SOTERflagTTRrules")
})
