#' Configuration of soilhub
#'
#' @description
#' Every setting is resolved with the precedence
#' **explicit argument > [options()] > environment variable > built-in default**.
#'
#' | Setting | Argument | Option | Environment variable | Default |
#' | --- | --- | --- | --- | --- |
#' | API base URL | `api_url` | `soilhub.api_url` | `SOILHUB_API_URL` | `https://soilhub.weatherprogapp.it/api/v1` |
#' | Keycloak realm | `keycloak_url` | `soilhub.keycloak_url` | `SOILHUB_KEYCLOAK_URL` | `https://kc.weatherprogapp.it/realms/ams` |
#' | OIDC client | `client_id` | `soilhub.client_id` | `SOILHUB_CLIENT_ID` | `ams-r` |
#' | Request timeout (seconds) | `timeout` | `soilhub.timeout` | `SOILHUB_TIMEOUT` | 300 |
#' | Verbosity | `verbose` | `soilhub.verbose` | `SOILHUB_VERBOSE` | 1 when interactive, else 0 |
#' | Export directory | `dir` | `soilhub.export_dir` | `SOILHUB_EXPORT_DIR` | `file.path(tempdir(), "soilhub-exports")` |
#' | Page size | `page_size` | `soilhub.page_size` | -- | the server's `max_page_size` (1000 when unknown) |
#' | Proactive refresh margin (seconds) | -- | `soilhub.refresh_margin` | `SOILHUB_REFRESH_MARGIN` | 60 |
#'
#' Verbosity levels: `0` silent; `1` user messages (pages read, retries,
#' session renewed, export progress); `2` also one line per HTTP request
#' (method, path, status, duration, request id), never headers, bodies or
#' tokens. `TRUE` means 1 and `FALSE` 0. Messages have class
#' `soilhub_message` and can be silenced with [suppressMessages()]. A session
#' created without an explicit `verbose` follows `soilhub.verbose` at each
#' call, so `options(soilhub.verbose = 2)` turns request logging on for an
#' existing session.
#'
#' The timeout is the total time allowed for one request (connection 10 s);
#' long pages over whole datasets take 40--90 s.
#'
#' The refresh margin is how long before the expiry of the access token the
#' next request renews it (see [soil_connect()]); it is read at each request,
#' so it applies to existing sessions too. A margin longer than the token
#' lifetime renews the token before every request.
#'
#' The variable names of soilhub 0.1.x are read as a fallback, with a
#' one-time message: `SOIL_API_URL` for the API base URL, `KEYCLOAK_TOKEN_URL`
#' and `KEYCLOAK_DEVICE_URL` for the Keycloak realm (the realm is the part
#' before `/protocol/openid-connect/`).
#'
#' @examples
#' # Use a test API for the rest of the R session
#' old <- options(soilhub.api_url = "http://localhost:8000/api/v1")
#' options(old)
#'
#' # Log every request
#' old <- options(soilhub.verbose = 2)
#' options(old)
#' @family configuration and errors
#' @name soilhub-config
NULL

config_defaults <- list(
  api_url = "https://soilhub.weatherprogapp.it/api/v1",
  keycloak_url = "https://kc.weatherprogapp.it/realms/ams",
  client_id = "ams-r",
  timeout = 300
)

# Resolve one setting: argument > option > environment variable > default.
# Returns list(value, source); `source` is "argument", "option", "env",
# "legacy_env" or "default".
config_value <- function(arg, option, env = NULL, default = NULL,
                         legacy = NULL) {
  if (!is.null(arg)) return(list(value = arg, source = "argument"))
  value <- getOption(option)
  if (!is.null(value)) return(list(value = value, source = "option"))
  if (!is.null(env)) {
    value <- Sys.getenv(env, unset = "")
    if (nzchar(value)) return(list(value = value, source = "env"))
  }
  if (!is.null(legacy)) {
    for (name in names(legacy)) {
      value <- Sys.getenv(name, unset = "")
      if (nzchar(value)) {
        inform_once(
          paste0("legacy_env_", name),
          sprintf(
            "soilhub: the 0.1.x variable %s is read as a fallback; set %s instead.",
            name, env
          )
        )
        return(list(value = legacy[[name]](value), source = "legacy_env"))
      }
    }
  }
  list(value = default, source = "default")
}

#' Resolve the settings of a session
#'
#' Applies the precedence of [soilhub-config] to every setting and validates
#' the values. `verbose` stays `NULL` when not given, so that the session
#' follows `soilhub.verbose` at each call (see [soil_verbosity()]).
#'
#' @param api_url,keycloak_url,client_id,timeout,verbose,dir,page_size
#'   Explicit values, or `NULL` to use options, environment variables and
#'   defaults.
#' @return A list with one element per setting and the attribute `sources`
#'   (where each value came from).
#' @keywords internal
#' @noRd
soil_config <- function(api_url = NULL, keycloak_url = NULL, client_id = NULL,
                        timeout = NULL, verbose = NULL, dir = NULL,
                        page_size = NULL) {
  realm_from_endpoint <- function(url) {
    sub("/protocol/openid-connect/.*$", "", url)
  }
  settings <- list(
    api_url = config_value(
      api_url, "soilhub.api_url", "SOILHUB_API_URL", config_defaults$api_url,
      legacy = list(SOIL_API_URL = identity)
    ),
    keycloak_url = config_value(
      keycloak_url, "soilhub.keycloak_url", "SOILHUB_KEYCLOAK_URL",
      config_defaults$keycloak_url,
      legacy = list(
        KEYCLOAK_TOKEN_URL = realm_from_endpoint,
        KEYCLOAK_DEVICE_URL = realm_from_endpoint
      )
    ),
    client_id = config_value(
      client_id, "soilhub.client_id", "SOILHUB_CLIENT_ID",
      config_defaults$client_id
    ),
    timeout = config_value(
      timeout, "soilhub.timeout", "SOILHUB_TIMEOUT", config_defaults$timeout
    ),
    dir = config_value(
      dir, "soilhub.export_dir", "SOILHUB_EXPORT_DIR",
      file.path(tempdir(), "soilhub-exports")
    ),
    page_size = config_value(page_size, "soilhub.page_size")
  )
  values <- lapply(settings, `[[`, "value")
  sources <- vapply(settings, `[[`, character(1), "source")

  values$api_url <- check_url(values$api_url, "api_url")
  values$keycloak_url <- check_url(values$keycloak_url, "keycloak_url")
  if (!is_string(values$client_id)) {
    abort(soilhub_argument_error("`client_id` must be a non-empty string.", "client_id"))
  }
  values$timeout <- check_timeout(values$timeout)
  if (!is_string(values$dir)) {
    abort(soilhub_argument_error("`dir` must be a directory path.", "dir"))
  }
  if (!is.null(values$page_size)) {
    values$page_size <- check_page_size(values$page_size)
  }
  values$verbose <- if (is.null(verbose)) NULL else check_verbose(verbose)
  sources["verbose"] <- if (is.null(verbose)) "follow" else "argument"
  values <- values[c(
    "api_url", "keycloak_url", "client_id", "timeout", "verbose", "dir",
    "page_size"
  )]
  attr(values, "sources") <- sources
  values
}

check_url <- function(url, argument) {
  if (!is_string(url) || !grepl("^https?://", url)) {
    abort(soilhub_argument_error(
      sprintf("`%s` must be an http(s) URL, not %s.", argument, deparse_argument(url)),
      argument
    ))
  }
  sub("/+$", "", url)
}

check_timeout <- function(timeout, argument = "timeout") {
  value <- suppressWarnings(as.numeric(timeout))
  if (length(value) != 1L || is.na(value) || value <= 0) {
    abort(soilhub_argument_error(
      sprintf(
        "`%s` must be a positive number of seconds (Inf for no limit), not %s.",
        argument, deparse_argument(timeout)
      ),
      argument
    ))
  }
  value
}

check_page_size <- function(page_size, argument = "page_size") {
  value <- suppressWarnings(as.numeric(page_size))
  if (length(value) != 1L || is.na(value) || value < 1 ||
      value != round(value) || is.infinite(value)) {
    abort(soilhub_argument_error(
      sprintf(
        "`%s` must be a positive whole number, not %s.",
        argument, deparse_argument(page_size)
      ),
      argument
    ))
  }
  value
}

# 0, 1, 2; TRUE = 1, FALSE = 0; strings from environment variables accepted.
check_verbose <- function(verbose, argument = "verbose") {
  value <- verbose
  if (is.character(value) && length(value) == 1L) {
    lower <- tolower(value)
    value <- if (lower %in% c("true", "yes")) {
      1
    } else if (lower %in% c("false", "no")) {
      0
    } else {
      suppressWarnings(as.numeric(value))
    }
  }
  if (is.logical(value) && length(value) == 1L && !is.na(value)) {
    value <- as.numeric(value)
  }
  if (!is.numeric(value) || length(value) != 1L || is.na(value) ||
      !value %in% c(0, 1, 2)) {
    abort(soilhub_argument_error(
      sprintf(
        "`%s` must be 0, 1, 2, TRUE or FALSE, not %s.",
        argument, deparse_argument(verbose)
      ),
      argument
    ))
  }
  as.integer(value)
}

#' Verbosity of a session
#'
#' The session's own `verbose` when set, else `soilhub.verbose`, else
#' `SOILHUB_VERBOSE`, else 1 in interactive sessions and 0 otherwise.
#' @param soil A session (or any list with a `verbose` element).
#' @return An integer 0, 1 or 2.
#' @keywords internal
#' @noRd
soil_verbosity <- function(soil = NULL) {
  explicit <- if (is.list(soil) || is.environment(soil)) soil$verbose else NULL
  setting <- config_value(
    explicit, "soilhub.verbose", "SOILHUB_VERBOSE", default = interactive()
  )
  check_verbose(setting$value)
}

# Page size of a paged read: the call's value, else the session's, else the
# option, else the server's `max_page_size`, else 1000; never above the
# server's `max_page_size` when it is known (capabilities, WP3).
resolve_page_size <- function(soil, page_size = NULL) {
  server_max <- tryCatch(
    session_cached(soil, "capabilities")$limits$max_page_size,
    error = function(e) NULL
  )
  value <- page_size %||% soil$page_size %||% getOption("soilhub.page_size") %||%
    server_max %||% 1000
  value <- check_page_size(value)
  if (!is.null(server_max)) value <- min(value, as.numeric(server_max))
  value
}
