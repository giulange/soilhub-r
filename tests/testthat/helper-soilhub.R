# Helpers for the HTTP, paging and configuration tests (WP1).

# A session-like list pointing at a fake API.
test_session <- function(server, verbose = 0, timeout = 30, ...) {
  c(
    list(
      api_url = server$url("/api/v1"),
      timeout = timeout,
      verbose = verbose
    ),
    list(...)
  )
}

# Replace the sleep between retries with a recorder for the calling test;
# returns an environment whose `waits` holds the requested waits (seconds).
local_fake_sleep <- function(.local_envir = parent.frame()) {
  recorder <- new.env(parent = emptyenv())
  recorder$waits <- numeric()
  old <- soilhub_env$sleep
  soilhub_env$sleep <- function(seconds) {
    recorder$waits <- c(recorder$waits, seconds)
  }
  withr::defer(soilhub_env$sleep <- old, envir = .local_envir)
  recorder
}

# Set options / environment variables (NA unsets) for the calling test.
local_opts <- function(..., .local_envir = parent.frame()) {
  withr::local_options(list(...), .local_envir = .local_envir)
}

local_env <- function(..., .local_envir = parent.frame()) {
  withr::local_envvar(c(...), .local_envir = .local_envir)
}

# A clean configuration: no soilhub option or environment variable set.
local_clean_config <- function(.local_envir = parent.frame()) {
  local_opts(
    soilhub.api_url = NULL, soilhub.keycloak_url = NULL,
    soilhub.client_id = NULL, soilhub.timeout = NULL,
    soilhub.verbose = NULL, soilhub.export_dir = NULL,
    soilhub.page_size = NULL,
    .local_envir = .local_envir
  )
  local_env(
    SOILHUB_API_URL = NA, SOILHUB_KEYCLOAK_URL = NA, SOILHUB_CLIENT_ID = NA,
    SOILHUB_TIMEOUT = NA, SOILHUB_VERBOSE = NA, SOILHUB_EXPORT_DIR = NA,
    SOIL_API_URL = NA, KEYCLOAK_TOKEN_URL = NA, KEYCLOAK_DEVICE_URL = NA,
    .local_envir = .local_envir
  )
}

request_id_pattern <- "^soilhub-[0-9]{14}-[0-9a-f]{8}$"
