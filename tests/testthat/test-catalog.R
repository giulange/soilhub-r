# Catalog, citations and licences (design 4.3, 5.5; decision 7) against the
# fake catalog API.

api <- fake_catalog_api()

test_that("soil_datasets() types every field of the catalog", {
  soil <- catalog_session(api)
  ds <- soil_datasets(soil)
  expect_s3_class(ds, "data.frame")
  expect_identical(nrow(ds), 4L)
  expect_identical(ds$name, c("soter_profiles", "sotwis_polygons", "wise_profiles", "wosis_points"))
  expect_identical(names(ds)[1:12], c(
    "name", "title", "provider_code", "description", "support_type", "geometry_class",
    "release_code", "release_status", "feature_count", "profile_count", "horizon_count",
    "observation_count"
  ))
  types <- vapply(ds, function(column) class(column)[1], character(1))
  expect_identical(unname(types[c("name", "title", "licence_text", "citation_note", "release_source_url")]), rep("character", 5))
  expect_identical(unname(types[c("feature_count", "observation_count", "retired_row_count")]), rep("numeric", 3))
  expect_identical(unname(types[c("licence_retrieved_on", "citation_retrieved_on")]), rep("Date", 2))
  expect_identical(unname(types[c("release_acquired_at", "release_released_at")]), rep("POSIXct", 2))
  expect_identical(unname(types[c("release_reconstructed", "geometry_available")]), rep("logical", 2))
  expect_identical(unname(types[c("country_codes", "source_assets", "notes")]), rep("list", 3))

  expect_identical(ds$observation_count[ds$name == "wosis_points"], 7012845)
  expect_identical(ds$country_codes[[3]], c("BRA", "KEN", "USA"))
  expect_identical(attr(ds$release_acquired_at, "tzone"), "UTC")
  expect_identical(format(ds$release_acquired_at[1], "%Y-%m-%d %H:%M:%S"), "2026-08-11 09:42:17")
  expect_true(is.na(ds$release_released_at[1]))
  expect_identical(ds$licence_retrieved_on[ds$name == "wise_profiles"], as.Date("2026-10-15"))
  expect_true(all(ds$release_reconstructed))

  # nested objects are typed data frames, empty arrays zero-row frames
  assets <- ds$source_assets[[1]]
  expect_s3_class(assets, "data.frame")
  expect_identical(nrow(assets), 2L)
  expect_identical(assets$byte_size, c(15873210, 2210947))
  expect_s3_class(assets$source_published_on, "Date")
  expect_s3_class(assets$file_modified_at, "POSIXct")
  expect_identical(nrow(ds$source_assets[[4]]), 0L)
  expect_identical(names(ds$source_assets[[4]]), names(assets))
  notes <- ds$notes[[1]]
  expect_identical(names(notes), c("key", "kind", "source_record_id", "source_dataset_name", "title", "body", "details", "decision"))
  expect_identical(notes$kind, c("licence", "licence", "citation", "citation"))
  expect_type(notes$details, "list")
  expect_identical(notes$details[[1]]$retrieved_on, "2026-10-15")
  expect_identical(nrow(ds$notes[[4]]), 0L)

  # cached for the session (citations by name need no second request)
  expect_identical(soil$state$datasets, ds)
})

test_that("licence and citation texts are kept verbatim", {
  soil <- catalog_session(api)
  ds <- soil_datasets(soil)
  wosis <- ds[ds$name == "wosis_points", ]
  # ISRIC's text keeps its non-breaking spaces
  expect_identical(
    wosis$citation_text,
    "Batjes NH, Calisto L and de Sousa LM, 2024. WoSIS-latest: Standardised world soil profile data. ISRIC Soil Data Hub resource identifier: https://tinyurl.com/39xhaa9d. Date downloaded: 15/01/2024."
  )
  expect_identical(wosis$licence_text, "Licenced per profile, as specified by data provider and indicated in the data")
  expect_match(ds$citation_text[ds$name == "wise_profiles"], "5:124–127", fixed = TRUE)
})

test_that("soil_dataset() returns one dataset in full, by name", {
  soil <- catalog_session(api)
  soter <- soil_dataset(soil, "soter_profiles")
  expect_s3_class(soter, "soil_dataset")
  expect_identical(soter$name, "soter_profiles")
  expect_s3_class(soter$notes, "data.frame")
  expect_s3_class(soter$source_assets, "data.frame")
  expect_identical(soter$country_codes, c("ARG", "CHN", "CUB", "KEN", "MWI", "TUN"))
  expect_true(is.na(soter$licence_text))
  expect_true(soter$release_reconstructed)
  out <- capture.output(print(soter))
  expect_true(any(grepl("SOTER reference profiles", out, fixed = TRUE)))
  expect_true(any(grepl("Release:   legacy_materialized (active, acquired 2026-08-11, reconstructed)", out, fixed = TRUE)))
  expect_true(any(grepl("[citation] Citation proposal of the ISRIC data hub", out, fixed = TRUE)))
  expect_true(any(grepl("(none at dataset level) The licence differs", out, fixed = TRUE)))

  # the default session and the name first
  withr::local_options(soilhub.session = soil)
  expect_identical(soil_dataset("wise_profiles")$name, "wise_profiles")

  err <- tryCatch(soil_dataset(soil, "nope"), soilhub_not_found_error = function(e) e)
  expect_s3_class(err, "soilhub_not_found_error")
  expect_match(conditionMessage(err), "Unknown dataset `nope`: soil_datasets() lists the catalog.", fixed = TRUE)
  expect_error(soil_dataset(soil), class = "soilhub_argument_error")
  expect_error(soil_dataset(soil, c("a", "b")), class = "soilhub_argument_error")
})

test_that("citations come from the dataset text when there is one", {
  soil <- catalog_session(api)
  cit <- soil_citations(c("wosis_points", "wise_profiles"), soil)
  expect_identical(names(cit), c(
    "dataset", "citation_text", "citation_source_url", "citation_retrieved_on", "citation_note",
    "level", "label", "note_key", "source_record_id", "source_dataset_name", "record_title"
  ))
  expect_identical(cit$dataset, c("wosis_points", "wise_profiles"))
  expect_identical(cit$level, c("dataset", "dataset"))
  expect_identical(cit$citation_source_url[1], "https://www.isric.org/explore/wosis/faq-wosis")
  expect_identical(cit$citation_retrieved_on, as.Date(c("2026-10-15", "2026-10-15")))
  expect_match(cit$citation_text[1], "Calisto L", fixed = TRUE)
  expect_true(grepl(" ", cit$citation_text[1], fixed = TRUE))
  expect_match(cit$citation_note[1], "acquired_at of the active release", fixed = TRUE)
})

test_that("datasets without a citation text return the notes, labelled as the API labels them", {
  soil <- catalog_session(api)
  cit <- soil_citations("soter_profiles", soil)
  expect_identical(nrow(cit), 2L)
  expect_identical(cit$level, rep("source dataset", 2))
  expect_identical(cit$label, rep("Citation proposal of the ISRIC data hub", 2))
  expect_identical(cit$note_key, rep("isric_citation", 2))
  expect_identical(cit$record_title, c(
    "Soil and Terrain Database (SOTER) for China", "Soil and Terrain Database (SOTER) for Malawi"
  ))
  expect_identical(cit$citation_text[1], "(2008). Soil and Terrain Database (SOTER) for China. https://data.isric.org/srv/api/records/2919b1e3-6a79-4162-9d3a-e640a1dc5aef")
  expect_match(cit$citation_source_url[2], "/formatters/citation\\?format=text$")
  expect_identical(cit$citation_retrieved_on[1], as.Date("2026-10-15"))
  expect_match(cit$citation_note[1], "^No citation text in the SOTER records")

  # SOTWIS: notes with the source dataset names
  sotwis <- soil_citations("sotwis_polygons", soil)
  expect_identical(sotwis$source_dataset_name, c("sotwis_central_africa", "sotwis_kenya"))
  expect_false(any(sotwis$note_key == "sotwis_codes"))
})

test_that("soil_citations() accepts catalog rows, a soil_dataset and metadata", {
  soil <- catalog_session(api)
  ds <- soil_datasets(soil)
  all <- soil_citations(ds)
  expect_identical(nrow(all), 6L)
  expect_identical(unique(all$dataset), ds$name)
  expect_identical(soil_citations(ds[ds$name == "wise_profiles", ])$level, "dataset")

  one <- soil_citations(soil_dataset(soil, "soter_profiles"))
  expect_identical(one, soil_citations("soter_profiles", soil))

  # a result carrying catalog rows in its metadata (read, summary, export)
  table <- structure(data.frame(dataset = "wise_profiles"), soil_metadata = list(datasets = ds[ds$name == "wise_profiles", ]))
  expect_identical(soil_citations(table)$dataset, "wise_profiles")
  summary <- list(metadata = list(request = list(datasets = list("wosis_points"))))
  expect_identical(soil_citations(summary, soil)$dataset, "wosis_points")

  expect_error(soil_citations("nope", soil), class = "soilhub_argument_error")
  expect_error(soil_citations(42, soil), class = "soilhub_argument_error")
})

test_that("licences: one text, or one per source dataset when they differ", {
  soil <- catalog_session(api)
  lic <- soil_licences(c("wosis_points", "soter_profiles", "sotwis_polygons"), soil)
  expect_identical(names(lic), c(
    "dataset", "licence_text", "licence_url", "licence_source_url", "licence_retrieved_on",
    "licence_note", "level", "label", "note_key", "source_record_id", "source_dataset_name",
    "record_title"
  ))
  expect_identical(lic$dataset, c("wosis_points", "soter_profiles", "soter_profiles", "sotwis_polygons"))
  # WoSIS: licence per profile, verbatim
  expect_identical(lic$licence_text[1], "Licenced per profile, as specified by data provider and indicated in the data")
  expect_true(is.na(lic$licence_url[1]))
  # SOTER: two different licences, labelled as the API labels them
  soter <- lic[lic$dataset == "soter_profiles", ]
  expect_identical(soter$licence_text, c(
    "Attribution 3.0 International (CC BY 3.0)",
    "Attribution-NonCommercial 3.0 International (CC BY-NC 3.0), https://creativecommons.org/licenses/by-nc/3.0/"
  ))
  expect_identical(soter$licence_url, c("https://creativecommons.org/licenses/by/3.0/", NA))
  expect_identical(soter$label, rep("Licence (ISRIC data hub record)", 2))
  expect_identical(soter$level, rep("source dataset", 2))
  expect_match(soter$licence_note[1], "differs between the SOTER source datasets")
  # SOTWIS: one dataset-level text
  expect_identical(lic$level[4], "dataset")
  expect_identical(lic$licence_retrieved_on[4], as.Date("2026-08-03"))
})

test_that("a dataset with neither text nor notes gives one row with an NA text", {
  bare <- read_fixture("datasets.json")
  bare$datasets[[1]]$notes <- list()
  local_api <- fake_catalog_api(datasets = bare)
  soil <- catalog_session(local_api)
  cit <- soil_citations("soter_profiles", soil)
  expect_identical(nrow(cit), 1L)
  expect_true(is.na(cit$citation_text))
  expect_match(cit$citation_note, "No citation text in the SOTER records")
})

test_that("fields unknown to the client pass through with a contract warning", {
  drift <- read_fixture("datasets.json")
  drift$datasets <- lapply(drift$datasets, function(d) {
    d$future_field_wp3 <- list(a = 1)
    d$release_note <- NULL
    d
  })
  local_api <- fake_catalog_api(datasets = drift)
  soil <- catalog_session(local_api)
  warnings <- character()
  ds <- withCallingHandlers(
    soil_datasets(soil),
    soilhub_contract_warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  expect_length(warnings, 2L)
  expect_match(warnings[1], "`future_field_wp3`")
  expect_match(warnings[2], "lacks field(s) this version of soilhub expects: `release_note`", fixed = TRUE)
  expect_type(ds$future_field_wp3, "list")
  expect_identical(ds$future_field_wp3[[1]]$a, 1L)
  expect_true(all(is.na(ds$release_note)))
  # once per R session
  expect_no_warning(soil_datasets(soil))
})

test_that("soil_formats() returns the export formats", {
  soil <- catalog_session(api)
  expect_identical(soil_formats(soil), c("geojson", "gpkg", "csv", "tsv", "shp"))
})

test_that("ISO times of the API are parsed to UTC", {
  parsed <- parse_api_time(c(
    "2026-08-11T09:42:17Z", "2026-08-11T11:42:17+02:00", "2026-08-11T09:42:17.5",
    "2026-08-11", "2026-08-11 04:42:17-0500", "not a time", NA
  ))
  expect_identical(format(parsed[1:5], "%Y-%m-%d %H:%M:%S"), c(
    "2026-08-11 09:42:17", "2026-08-11 09:42:17", "2026-08-11 09:42:17",
    "2026-08-11 00:00:00", "2026-08-11 09:42:17"
  ))
  expect_equal(as.numeric(parsed[3]) %% 1, 0.5)
  expect_true(all(is.na(parsed[6:7])))
  expect_identical(parse_api_date(c("2026-10-15", "2026-08-03 10:00:00+00", NA, "x")),
                   as.Date(c("2026-10-15", "2026-08-03", NA, NA)))
})
