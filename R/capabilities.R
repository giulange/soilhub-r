# Capabilities, API version and capability gates (design 4.2, 9.1, 9.2).
#
# `GET /capabilities` is read once after the login and cached in the session
# (`soil$state$capabilities`). The version gate runs on it:
#   - API version below MIN_API_VERSION, or of another major ->
#     `soilhub_capability_error` (soil_connect() returns no default session;
#     the session is attached to the error, signed out, for soil_api_info());
#   - a newer minor -> a message (the client still works);
#   - a required capability missing or FALSE -> `soilhub_capability_error`
#     naming it.
# Optional capabilities are checked by the functions that need them
# (`soil_require_capability()`): FALSE -> `soilhub_capability_error`; not
# advertised at all (an older or newer server) -> a warning when the
# function is used, and the request is sent (drift degrades, 9.2).

#' API versions and capabilities supported by this client
#'
#' Package constants (design 9.1): the lowest API version supported, the
#' supported major version, the capabilities every session needs and the
#' optional capabilities checked by the functions that use them.
#' @keywords internal
#' @noRd
MIN_API_VERSION <- "0.5.0"
SUPPORTED_API_MAJOR <- 0L
REQUIRED_CAPABILITIES <- c(
  "query_canonical_observations", "wide_layout", "canonical_features",
  "canonical_summary", "load_limits", "complete_exports", "first_layer_status"
)
OPTIONAL_CAPABILITIES <- c(
  "revised_view", "profile_type_filter", "raw_markings", "source_ingest",
  "variable_registration", "bulk_soil_health", "code_lists",
  "sotwis_ttr_flags", "dataset_notes", "sotwis_estimates", "country_inventory",
  "publish_generic_values", "generic_bulk_publication", "publish_soil_health_sync"
)

# "0.5.0" -> c(0, 5, 0); NULL when the text is not a version.
parse_api_version <- function(version) {
  if (!is_string(version)) return(NULL)
  match <- regmatches(version, regexpr("^[0-9]+(\\.[0-9]+){1,2}", version))
  if (length(match) == 0L) return(NULL)
  parts <- as.integer(strsplit(match, ".", fixed = TRUE)[[1]])
  c(parts, 0L)[1:3]
}

#' Compare an API version with the range supported by the client
#'
#' @param version The `api_version` of `/capabilities`.
#' @return A list: `status` (`"supported"`, `"newer_minor"`, `"too_old"`,
#'   `"other_major"`, `"unknown"`), `compatible` (logical; `NA` when the
#'   version is unknown) and `message`.
#' @keywords internal
#' @noRd
check_api_version <- function(version) {
  minimum <- parse_api_version(MIN_API_VERSION)
  tested <- sprintf("%d.%d.x", minimum[1], minimum[2])
  parsed <- parse_api_version(version)
  if (is.null(parsed)) {
    return(list(status = "unknown", compatible = NA, message = sprintf(
      "The API did not report a version this client can read (%s); soilhub %s supports API %s and later %d.x versions.",
      if (is_string(version)) paste0("\"", version, "\"") else "none",
      client_version(), MIN_API_VERSION, SUPPORTED_API_MAJOR
    )))
  }
  if (parsed[1] != SUPPORTED_API_MAJOR) {
    return(list(status = "other_major", compatible = FALSE, message = sprintf(
      "The API version %s is not supported by soilhub %s, which supports API %s and later %d.x versions: install the soilhub version made for API %d.x.",
      version, client_version(), MIN_API_VERSION, SUPPORTED_API_MAJOR, parsed[1]
    )))
  }
  if (compare_versions(parsed, minimum) < 0) {
    return(list(status = "too_old", compatible = FALSE, message = sprintf(
      "The API version %s is older than the minimum supported by soilhub %s (%s): use the soilhub release made for that API, or a server with API %s or later.",
      version, client_version(), MIN_API_VERSION, MIN_API_VERSION
    )))
  }
  if (parsed[2] > minimum[2]) {
    return(list(status = "newer_minor", compatible = TRUE, message = sprintf(
      "API %d.%d.x is newer than this client was tested with (%s); update soilhub when available.",
      parsed[1], parsed[2], tested
    )))
  }
  list(status = "supported", compatible = TRUE, message = NULL)
}

compare_versions <- function(a, b) {
  for (i in seq_along(a)) {
    if (a[i] != b[i]) return(if (a[i] < b[i]) -1L else 1L)
  }
  0L
}

client_version <- function() {
  as.character(utils::packageVersion("soilhub"))
}

# Required capabilities that the server does not report as TRUE.
missing_required <- function(capabilities) {
  flags <- if (is.list(capabilities)) capabilities$capabilities else NULL
  if (!is.list(flags)) flags <- list()
  REQUIRED_CAPABILITIES[!vapply(REQUIRED_CAPABILITIES, function(name) isTRUE(flags[[name]]), logical(1))]
}

#' The version gate (design 9.1)
#'
#' Checks the cached `/capabilities` of a session: version range and required
#' capabilities. Signals `soilhub_capability_error` when the server is
#' incompatible, a `soilhub_message` for a newer minor version and a
#' `soilhub_capability_warning` when the version is not readable. Records
#' the outcome in `soil$state$compatibility`.
#'
#' @param soil The session (capabilities cached).
#' @return The compatibility list, invisibly.
#' @keywords internal
#' @noRd
version_gate <- function(soil, capabilities = session_cached(soil, "capabilities")) {
  version <- if (is.list(capabilities)) capabilities$api_version else NULL
  check <- check_api_version(version)
  missing <- missing_required(capabilities)
  compatible <- if (identical(check$compatible, FALSE) || length(missing)) FALSE else check$compatible
  compatibility <- list(
    api_version = if (is_string(version)) version else NA_character_,
    status = check$status,
    compatible = compatible,
    missing_capabilities = missing,
    message = check$message
  )
  if (is.environment(soil$state)) soil$state$compatibility <- compatibility

  if (identical(check$compatible, FALSE)) {
    abort(soilhub_capability_error(
      check$message,
      api_version = compatibility$api_version, minimum = MIN_API_VERSION
    ))
  }
  if (length(missing)) {
    abort(soilhub_capability_error(
      sprintf(
        "The API at %s (version %s) lacks the required capabilit%s %s: soilhub %s cannot work with this server.",
        soil$api_url, compatibility$api_version,
        if (length(missing) > 1L) "ies" else "y",
        paste0("`", missing, "`", collapse = ", "), client_version()
      ),
      capability = missing, api_version = compatibility$api_version,
      minimum = MIN_API_VERSION
    ))
  }
  if (identical(check$status, "newer_minor")) {
    cond <- structure(
      class = c("soilhub_version_message", "soilhub_message", "message", "condition"),
      list(message = paste0("soilhub: ", check$message, "\n"), call = NULL)
    )
    message(cond)
  } else if (identical(check$status, "unknown")) {
    soilhub_warning(check$message, "soilhub_capability_warning")
  }
  invisible(compatibility)
}

#' Check an optional capability before a request
#'
#' Used by the functions that need an optional capability (design 9.1). When
#' the cached `/capabilities` reports it `FALSE`, raises
#' `soilhub_capability_error`. When the server does not advertise it at all
#' (or the capabilities could not be read), warns once per session
#' (`soilhub_capability_warning`) and lets the request go: the API decides.
#'
#' @param soil The session.
#' @param capability The capability name (a key of `capabilities`).
#' @param what The function, for the message (e.g. "`soil_code_lists()`").
#' @return `TRUE` invisibly when advertised, `NA` when not checked.
#' @keywords internal
#' @noRd
soil_require_capability <- function(soil, capability, what) {
  capabilities <- session_cached(soil, "capabilities")
  flags <- if (is.list(capabilities)) capabilities$capabilities else NULL
  value <- if (is.list(flags)) flags[[capability]] else NULL
  if (isTRUE(value)) return(invisible(TRUE))
  version <- if (is.list(capabilities) && is_string(capabilities$api_version)) capabilities$api_version else NA_character_
  if (is.null(value)) {
    key <- paste0("capability:", capability)
    state <- if (is.list(soil)) soil[["state"]] else NULL
    warned <- if (is.environment(state)) state$warned %||% character() else character()
    if (!key %in% warned) {
      if (is.environment(state)) state$warned <- c(warned, key)
      soilhub_warning(sprintf(
        "%s needs the capability `%s`, which %s: the request is sent and the API decides.",
        what, capability,
        if (is.list(capabilities)) {
          sprintf("the server (API %s) does not advertise", version)
        } else {
          "could not be checked (the capabilities of the server were not read)"
        }
      ), "soilhub_capability_warning")
    }
    return(invisible(NA))
  }
  abort(soilhub_capability_error(
    sprintf(
      "%s needs the capability `%s`, which the server (API %s) reports as not available.",
      what, capability, version
    ),
    capability = capability, api_version = version, minimum = MIN_API_VERSION
  ))
}

# Read /capabilities into the session cache.
fetch_capabilities <- function(soil) {
  capabilities <- soil_request(soil, "GET", "/capabilities", right = "soil:summary")
  if (!is.list(capabilities)) {
    abort(soilhub_api_error(
      "The API returned no capabilities object for GET /capabilities.",
      endpoint = "/capabilities", method = "GET", code = "invalid_capabilities"
    ))
  }
  attr(capabilities, "request_id") <- NULL
  attr(capabilities, "status") <- NULL
  if (is.environment(soil$state)) soil$state$capabilities <- capabilities
  capabilities
}

#' The capabilities of the server
#'
#' The deployment contract of the API, `GET /capabilities`: API and response
#' schema versions, authentication (the audience of the rights), the limits
#' advertised for this deployment (`max_page_size`, `max_sync_observations`,
#' `max_export_observations`, `max_publication_bytes`), formats, exports,
#' filters, the capability flags (`capabilities`), the profile types
#' (`profile_types`) and the views with their revised rules (`views`).
#'
#' The capabilities are read once after the login and kept in the session;
#' `refresh = TRUE` reads them again and repeats the version check of
#' [soil_connect()].
#'
#' Rights: `soil:summary`.
#'
#' @param soil A session; the default session when omitted.
#' @param refresh Read the capabilities from the server again.
#' @return The `/capabilities` object as a named list (as parsed, nothing
#'   renamed).
#' @family discovery
#' @seealso [soil_api_info()] for the versions and the compatibility of the
#'   server with this client.
#' @examples
#' \dontrun{
#' caps <- soil_capabilities(soil)
#' caps$api_version
#' caps$limits$max_sync_observations
#' names(Filter(isTRUE, caps$capabilities))
#' }
#' @export
soil_capabilities <- function(soil = soil_session(), refresh = FALSE) {
  check_session(soil)
  cached <- soil$state$capabilities
  if (!isTRUE(refresh) && is.list(cached)) return(cached)
  capabilities <- fetch_capabilities(soil)
  version_gate(soil, capabilities)
  capabilities
}

#' Versions, liveness and compatibility of the API
#'
#' Asks the API whether it is alive (`GET /health`) and can reach its
#' database (`GET /ready`), and reports the API and response schema versions
#' and the authentication advertised by `/capabilities`, the version of this
#' client and whether the two are compatible (design 9.1: API
#' 0.5.0 or later, same major version, and every required
#' capability present).
#'
#' It also works on the session attached to the `soilhub_capability_error`
#' of an incompatible server (`e$session`), to inspect the versions.
#'
#' Rights: none for `health` and `ready`; the capabilities are those read at
#' the login (or read now, with `soil:summary`, when not cached).
#'
#' @param soil A session; the default session when omitted.
#' @return A `soil_api_info` list: `api_url`, `health` (`"ok"` or the
#'   error), `ready` (`"ready"`, or the reason the database is not
#'   reachable), `api_version`, `schema_version` (the
#'   `response_schema_version`), `authentication` (list), `client_version`,
#'   `supported_api` (the range supported by this client), `compatible`
#'   (logical, `NA` when unknown), `status` (`"supported"`, `"newer_minor"`,
#'   `"too_old"`, `"other_major"`, `"unknown"`) and
#'   `missing_capabilities`.
#' @family discovery
#' @examples
#' \dontrun{
#' soil_api_info(soil)
#'
#' # an incompatible server
#' soil <- tryCatch(soil_connect(), soilhub_capability_error = function(e) e$session)
#' soil_api_info(soil)
#' }
#' @export
soil_api_info <- function(soil = soil_session()) {
  check_session(soil)
  probe <- function(path) {
    tryCatch(
      soil_request(soil, "GET", path, retry = FALSE),
      soilhub_error = function(e) e
    )
  }
  health <- probe("/health")
  ready <- probe("/ready")
  capabilities <- soil$state$capabilities
  if (!is.list(capabilities) && is_string(soil$state$access_token)) {
    capabilities <- tryCatch(fetch_capabilities(soil), soilhub_error = function(e) NULL)
  }
  version <- if (is.list(capabilities) && is_string(capabilities$api_version)) capabilities$api_version else NA_character_
  check <- if (is.list(capabilities)) check_api_version(version) else list(status = "unknown", compatible = NA)
  missing <- if (is.list(capabilities)) missing_required(capabilities) else character()
  compatible <- if (identical(check$compatible, FALSE) || length(missing)) FALSE else check$compatible
  structure(
    list(
      api_url = soil$api_url,
      health = if (inherits(health, "soilhub_error")) conditionMessage(health) else health$status %||% NA_character_,
      ready = if (inherits(ready, "soilhub_error")) conditionMessage(ready) else ready$status %||% NA_character_,
      api_version = version,
      schema_version = if (is.list(capabilities)) capabilities$response_schema_version %||% NA_character_ else NA_character_,
      authentication = if (is.list(capabilities)) capabilities$authentication else NULL,
      client_version = client_version(),
      supported_api = sprintf(">= %s, < %d.0.0", MIN_API_VERSION, SUPPORTED_API_MAJOR + 1L),
      compatible = compatible,
      status = check$status,
      missing_capabilities = missing
    ),
    class = "soil_api_info"
  )
}

#' @export
print.soil_api_info <- function(x, ...) {
  first_line <- function(text) if (is.character(text)) strsplit(text, "\n", fixed = TRUE)[[1]][1] else text
  cat("<soil_api_info> ", x$api_url, "\n", sep = "")
  cat("  Health:        ", first_line(x$health), "\n", sep = "")
  cat("  Ready:         ", first_line(x$ready), "\n", sep = "")
  cat("  API version:   ", if (is.na(x$api_version)) "unknown" else x$api_version,
      if (!is.na(x$schema_version)) paste0(" (response schema ", x$schema_version, ")") else "", "\n", sep = "")
  auth <- x$authentication
  if (is.list(auth)) {
    cat("  Authentication: ", if (isTRUE(auth$enabled)) paste0(auth$type %||% "enabled", ", audience ", auth$audience %||% "?") else "disabled", "\n", sep = "")
  }
  cat("  Client:        soilhub ", x$client_version, " (API ", x$supported_api, ")\n", sep = "")
  verdict <- if (is.na(x$compatible)) {
    "unknown (capabilities not read)"
  } else if (isTRUE(x$compatible)) {
    if (identical(x$status, "newer_minor")) "yes (the API is newer than the client was tested with)" else "yes"
  } else if (length(x$missing_capabilities)) {
    paste0("no: missing ", paste(x$missing_capabilities, collapse = ", "))
  } else {
    paste0("no (", x$status, ")")
  }
  cat("  Compatible:    ", verdict, "\n", sep = "")
  invisible(x)
}
