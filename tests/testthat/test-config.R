# Configuration precedence (design 2.6): argument > option > env > default.

test_that("built-in defaults apply when nothing is set", {
  local_clean_config()
  cfg <- soil_config()
  expect_identical(cfg$api_url, "https://soilhub.weatherprogapp.it/api/v1")
  expect_identical(cfg$keycloak_url, "https://kc.weatherprogapp.it/realms/ams")
  expect_identical(cfg$client_id, "ams-r")
  expect_identical(cfg$timeout, 300)
  expect_identical(cfg$dir, file.path(tempdir(), "soilhub-exports"))
  expect_null(cfg$page_size)
  expect_null(cfg$verbose)
  expect_identical(attr(cfg, "sources")[["api_url"]], "default")
})

test_that("argument > option > environment variable > default", {
  local_clean_config()
  local_env(SOILHUB_API_URL = "http://env.example/api/v1/", SOILHUB_TIMEOUT = "120",
            SOILHUB_CLIENT_ID = "env-client", SOILHUB_EXPORT_DIR = "/tmp/env-dir")
  cfg <- soil_config()
  expect_identical(cfg$api_url, "http://env.example/api/v1")
  expect_identical(cfg$timeout, 120)
  expect_identical(cfg$client_id, "env-client")
  expect_identical(cfg$dir, "/tmp/env-dir")
  expect_identical(attr(cfg, "sources")[["api_url"]], "env")

  local_opts(soilhub.api_url = "http://option.example/api/v1", soilhub.timeout = 60,
             soilhub.page_size = 250)
  cfg <- soil_config()
  expect_identical(cfg$api_url, "http://option.example/api/v1")
  expect_identical(cfg$timeout, 60)
  expect_identical(cfg$page_size, 250)
  expect_identical(cfg$client_id, "env-client")
  expect_identical(attr(cfg, "sources")[["api_url"]], "option")

  cfg <- soil_config(api_url = "http://arg.example/api/v1", timeout = 10, page_size = 50)
  expect_identical(cfg$api_url, "http://arg.example/api/v1")
  expect_identical(cfg$timeout, 10)
  expect_identical(cfg$page_size, 50)
  expect_identical(attr(cfg, "sources")[["api_url"]], "argument")
})

test_that("the 0.1.x variables are a fallback with a one-time message", {
  local_clean_config()
  local_env(SOIL_API_URL = "http://legacy.example/api/v1",
            KEYCLOAK_TOKEN_URL = "https://kc.example/realms/test/protocol/openid-connect/token")
  old_shown <- soilhub_env$shown
  soilhub_env$shown <- character()
  withr::defer(soilhub_env$shown <- old_shown)

  msgs <- testthat::capture_messages(cfg <- soil_config())
  expect_length(msgs, 2L)
  expect_match(msgs[1], "variable SOIL_API_URL is read as a fallback; set SOILHUB_API_URL")
  expect_match(msgs[2], "variable KEYCLOAK_TOKEN_URL is read as a fallback; set SOILHUB_KEYCLOAK_URL")
  expect_identical(cfg$api_url, "http://legacy.example/api/v1")
  expect_identical(cfg$keycloak_url, "https://kc.example/realms/test")
  expect_identical(attr(cfg, "sources")[["api_url"]], "legacy_env")
  expect_no_message(soil_config())

  # the new variable wins over the legacy one
  local_env(SOILHUB_API_URL = "http://new.example/api/v1")
  expect_identical(soil_config()$api_url, "http://new.example/api/v1")
})

test_that("invalid settings are argument errors", {
  local_clean_config()
  expect_error(soil_config(api_url = "soilhub.example"), class = "soilhub_argument_error")
  expect_error(soil_config(timeout = -1), class = "soilhub_argument_error")
  expect_error(soil_config(timeout = "abc"), class = "soilhub_argument_error")
  expect_error(soil_config(verbose = 3), class = "soilhub_argument_error")
  expect_error(soil_config(page_size = 0), class = "soilhub_argument_error")
  expect_error(soil_config(client_id = ""), class = "soilhub_argument_error")
  e <- expect_error(soil_config(timeout = 0))
  expect_identical(e$argument, "timeout")
  local_env(SOILHUB_TIMEOUT = "never")
  expect_error(soil_config(), class = "soilhub_argument_error")
  expect_identical(soil_config(timeout = Inf)$timeout, Inf)
})

test_that("verbosity: session value > option > env > interactive()", {
  local_clean_config()
  expect_identical(soil_verbosity(list()), as.integer(interactive()))
  local_env(SOILHUB_VERBOSE = "2")
  expect_identical(soil_verbosity(list()), 2L)
  local_env(SOILHUB_VERBOSE = "false")
  expect_identical(soil_verbosity(list()), 0L)
  local_opts(soilhub.verbose = TRUE)
  expect_identical(soil_verbosity(list()), 1L)
  expect_identical(soil_verbosity(list(verbose = 0)), 0L)
  expect_identical(soil_verbosity(list(verbose = 2L)), 2L)

  # a session without an explicit value follows the option at each call
  cfg <- soil_config()
  local_opts(soilhub.verbose = 2)
  expect_identical(soil_verbosity(cfg), 2L)
  expect_identical(soil_verbosity(soil_config(verbose = FALSE)), 0L)
})
