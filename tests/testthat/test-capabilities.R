# Version gate and capabilities (design 9.1, 9.2): pure checks, the gate at
# connection against the fake Keycloak realm and API, and the optional
# capabilities checked by the functions that need them.

test_that("API versions are compared with the supported range", {
  expect_identical(check_api_version("0.5.0")$status, "supported")
  expect_identical(check_api_version("0.5.7")$status, "supported")
  newer <- check_api_version("0.6.2")
  expect_identical(newer$status, "newer_minor")
  expect_true(newer$compatible)
  expect_match(newer$message, "API 0.6.x is newer than this client was tested with (0.5.x)", fixed = TRUE)
  old <- check_api_version("0.4.9")
  expect_identical(old$status, "too_old")
  expect_false(old$compatible)
  expect_identical(check_api_version("1.0.0")$status, "other_major")
  expect_identical(check_api_version("0.5")$status, "supported")
  unknown <- check_api_version(NULL)
  expect_identical(unknown$status, "unknown")
  expect_true(is.na(unknown$compatible))
  expect_identical(check_api_version("dev")$status, "unknown")
})

test_that("the package constants are those of the design", {
  expect_identical(MIN_API_VERSION, "0.5.0")
  expect_identical(SUPPORTED_API_MAJOR, 0L)
  expect_setequal(REQUIRED_CAPABILITIES, c(
    "query_canonical_observations", "wide_layout", "canonical_features",
    "canonical_summary", "load_limits", "complete_exports", "first_layer_status"
  ))
  expect_true(all(c("revised_view", "profile_type_filter", "code_lists", "sotwis_ttr_flags",
                    "dataset_notes", "sotwis_estimates") %in% OPTIONAL_CAPABILITIES))
  # the recorded capabilities advertise every capability the client knows
  flags <- read_fixture("capabilities.json")$capabilities
  expect_true(all(vapply(c(REQUIRED_CAPABILITIES, OPTIONAL_CAPABILITIES), function(n) isTRUE(flags[[n]]), logical(1))))
})

server <- fake_session_server()

test_that("soil_connect() reads the capabilities and passes the gate", {
  local_no_default_session()
  local_fake_clock()
  soil <- fake_connect(server)
  expect_identical(soil$state$compatibility$status, "supported")
  expect_true(soil$state$compatibility$compatible)
  expect_identical(soil_capabilities(soil)$api_version, "0.5.0")
  expect_identical(soil_capabilities()$limits$max_page_size, 1000L)
  expect_identical(soil_session()$state, soil$state)
})

test_that("a stripped capabilities document stops the connection with a capability error", {
  local_no_default_session()
  local_fake_clock()
  stripped <- fake_session_server(capabilities = read_fixture("capabilities-stripped.json"))
  err <- tryCatch(fake_connect(stripped), soilhub_capability_error = function(e) e)
  expect_s3_class(err, "soilhub_capability_error")
  expect_setequal(err$capability, c("load_limits", "complete_exports", "first_layer_status"))
  expect_identical(err$api_version, "0.5.0")
  expect_identical(err$minimum, "0.5.0")
  expect_match(conditionMessage(err), "lacks the required capabilities `load_limits`, `complete_exports`, `first_layer_status`", fixed = TRUE)
  expect_match(conditionMessage(err), "soil_api_info(e$session)", fixed = TRUE)
  # no default session; the session travels in the error, signed out
  expect_null(getOption("soilhub.session"))
  expect_s3_class(err$session, "soil_session")
  expect_null(err$session$state$access_token)
  expect_identical(session_status(err$session), "signed_out")
  info <- soil_api_info(err$session)
  expect_s3_class(info, "soil_api_info")
  expect_false(info$compatible)
  expect_identical(info$api_version, "0.5.0")
  expect_setequal(info$missing_capabilities, c("load_limits", "complete_exports", "first_layer_status"))
  expect_output(print(info), "Compatible:    no: missing")
})

test_that("an API older than the minimum, or of another major, is refused", {
  local_no_default_session()
  local_fake_clock()
  old <- fake_session_server(capabilities = capabilities_with(api_version = "0.4.2"))
  err <- tryCatch(fake_connect(old), soilhub_capability_error = function(e) e)
  expect_s3_class(err, "soilhub_capability_error")
  expect_identical(err$api_version, "0.4.2")
  expect_identical(err$minimum, "0.5.0")
  expect_null(err$capability)
  expect_match(conditionMessage(err), "older than the minimum supported")
  expect_null(getOption("soilhub.session"))
  expect_identical(soil_api_info(err$session)$status, "too_old")

  major <- fake_session_server(capabilities = capabilities_with(api_version = "1.0.0"))
  err <- tryCatch(fake_connect(major), soilhub_capability_error = function(e) e)
  expect_match(conditionMessage(err), "install the soilhub version made for API 1.x")
})

test_that("a newer minor API version connects with a message", {
  local_no_default_session()
  local_fake_clock()
  newer <- fake_session_server(capabilities = capabilities_with(api_version = "0.6.1"))
  msgs <- testthat::capture_messages(soil <- soil_connect(
    api_url = newer$url("/api/v1"), keycloak_url = newer$url("/realms/ams"),
    client_id = "ams-r", open_browser = FALSE, verbose = 0, timeout = 30
  ))
  expect_true(any(grepl("API 0.6.x is newer than this client was tested with (0.5.x); update soilhub when available", msgs, fixed = TRUE)))
  expect_identical(soil$state$compatibility$status, "newer_minor")
  expect_true(soil_api_info(soil)$compatible)
  expect_identical(soil_session()$state, soil$state)
})

test_that("a missing optional capability does not stop the connection", {
  local_no_default_session()
  local_fake_clock()
  drift <- fake_session_server(capabilities = capabilities_with(code_lists = NULL, sotwis_ttr_flags = FALSE))
  expect_no_warning(soil <- fake_connect(drift))
  expect_true(soil$state$compatibility$compatible)
})

test_that("an unreadable API version connects with a warning", {
  local_no_default_session()
  local_fake_clock()
  unknown <- fake_session_server(capabilities = capabilities_with(api_version = "dev"))
  expect_warning(soil <- fake_connect(unknown), class = "soilhub_capability_warning")
  expect_identical(soil$state$compatibility$status, "unknown")
})

test_that("soil_capabilities(refresh = TRUE) reads the server again", {
  local_no_default_session()
  local_fake_clock()
  soil <- fake_connect(server)
  soil$state$capabilities$api_version <- "stale"
  expect_identical(soil_capabilities(soil)$api_version, "stale")
  expect_identical(soil_capabilities(soil, refresh = TRUE)$api_version, "0.5.0")
  expect_identical(soil$state$capabilities$api_version, "0.5.0")
})

test_that("soil_api_info() reports liveness, versions and compatibility", {
  local_no_default_session()
  local_fake_clock()
  api <- fake_catalog_api()
  soil <- catalog_session(api)
  info <- soil_api_info(soil)
  expect_identical(info$health, "ok")
  expect_identical(info$ready, "ready")
  expect_identical(info$api_version, "0.5.0")
  expect_identical(info$schema_version, "1.0")
  expect_identical(info$authentication$audience, "soil-api")
  expect_identical(info$client_version, as.character(utils::packageVersion("soilhub")))
  expect_identical(info$supported_api, ">= 0.5.0, < 1.0.0")
  expect_true(info$compatible)
  expect_output(print(info), "Compatible:    yes")

  # no capabilities read and none readable: compatibility unknown
  blind <- new_soil_session(soil_config(api_url = api$url("/api/v1"), timeout = 30, verbose = 0))
  info <- soil_api_info(blind)
  expect_true(is.na(info$compatible))
  expect_identical(info$status, "unknown")
})

test_that("optional capabilities: FALSE is an error, not advertised a warning at use", {
  soil <- list(api_url = "http://localhost", state = new.env())
  soil$state$capabilities <- capabilities_with(code_lists = FALSE, sotwis_ttr_flags = NULL)
  err <- tryCatch(soil_require_capability(soil, "code_lists", "`soil_code_lists()`"), soilhub_capability_error = function(e) e)
  expect_s3_class(err, "soilhub_capability_error")
  expect_identical(err$capability, "code_lists")
  expect_identical(err$api_version, "0.5.0")
  expect_match(conditionMessage(err), "`soil_code_lists()` needs the capability `code_lists`, which the server (API 0.5.0) reports as not available", fixed = TRUE)

  expect_warning(
    res <- soil_require_capability(soil, "sotwis_ttr_flags", "`soil_ttr_flag_legend()`"),
    class = "soilhub_capability_warning"
  )
  expect_true(is.na(res))
  # once per session
  expect_no_warning(soil_require_capability(soil, "sotwis_ttr_flags", "`soil_ttr_flag_legend()`"))
  expect_true(soil_require_capability(soil, "revised_view", "x"))
})

test_that("a missing optional capability warns only when the function is used", {
  api <- fake_catalog_api()
  soil <- catalog_session(api, capabilities = capabilities_with(code_lists = NULL, sotwis_ttr_flags = FALSE))
  # unrelated discovery: no warning
  expect_no_warning(soil_formats(soil))
  # not advertised: the request is sent, with a warning
  expect_warning(lists <- soil_code_lists(soil), class = "soilhub_capability_warning")
  expect_identical(lists$code_list, "SOTWIS_codes")
  # reported FALSE: refused before any request
  expect_error(soil_ttr_flag_legend(soil), class = "soilhub_capability_error")
})
