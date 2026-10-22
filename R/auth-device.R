# Device login, renewal and token store (design 3.2, 3.3; decisions 4, 4-bis).
#
# Human users only: the OAuth 2.0 device authorisation grant with PKCE (S256)
# on the public client (`ams-r`, no secret), renewal with the refresh token,
# tokens in memory only (the environment `soil$state`). There is no client
# credentials grant, no password grant and no token on disk.
#
# The flow is written with httr2 requests instead of
# `httr2::oauth_flow_device()` / `oauth_flow_refresh()`, for three reasons:
# the renewal must run on a clock and a sleep that tests control (design 3.3:
# `soil_now()` and `http_sleep()`), Keycloak rotates the refresh token at
# every renewal (httr2 warns "Refresh token has changed" each time), and the
# OAuth errors must become `soilhub_auth_error` with the reasons of design 2.5.
#
# Token store (`soil$state`):
#   access_token, refresh_token     the current tokens (never printed, logged
#                                   or put in a condition)
#   expires_at, refresh_expires_at  POSIXct, from `expires_in` and
#                                   `refresh_expires_in` of the token response
#   access_lifetime                 `expires_in` (seconds)
#   logged_in_at, last_renewed_at, renewals
#   identity                        what the token says (rights.R)
#   capabilities                    cached `GET /capabilities`
#   endpoints                       device and token URLs of the realm
#   ended                           the `soilhub_auth_error` that ended the
#                                   session (re-signalled until a new login)
#   renewal_failed                  the `session_expired` error of a refused
#                                   proactive renewal, raised when the still
#                                   valid access token expires or is refused
#   signed_out                      TRUE after `soil_logout()`

auth_scope <- "openid soil"
auth_default_margin <- 60
auth_request_timeout <- 30
device_default_interval <- 5
device_default_expires_in <- 600
device_grant_type <- "urn:ietf:params:oauth:grant-type:device_code"

# ---------------------------------------------------------------------------
# Endpoints of the realm: the discovery document when reachable, else the
# fixed Keycloak paths (design 2.6). Cached in the session.

auth_endpoints <- function(soil) {
  state <- soil$state
  if (!is.null(state$endpoints)) return(state$endpoints)
  realm <- soil$keycloak_url
  endpoints <- tryCatch(discover_endpoints(soil, realm), error = function(e) NULL)
  if (is.null(endpoints)) {
    endpoints <- list(
      device = paste0(realm, "/protocol/openid-connect/auth/device"),
      token = paste0(realm, "/protocol/openid-connect/token"),
      source = "fixed"
    )
  }
  state$endpoints <- endpoints
  endpoints
}

discover_endpoints <- function(soil, realm) {
  req <- httr2::request(paste0(realm, "/.well-known/openid-configuration"))
  req <- httr2::req_headers(req, Accept = "application/json")
  req <- httr2::req_user_agent(req, user_agent())
  req <- httr2::req_timeout(req, http_connect_timeout)
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  resp <- httr2::req_perform(req)
  if (httr2::resp_status(resp) != 200L) return(NULL)
  doc <- parse_body(resp)
  if (!is.list(doc) || !is_string(doc$device_authorization_endpoint) ||
      !is_string(doc$token_endpoint)) {
    return(NULL)
  }
  list(
    device = doc$device_authorization_endpoint,
    token = doc$token_endpoint,
    source = "discovery"
  )
}

# ---------------------------------------------------------------------------
# PKCE (RFC 7636, method S256): Keycloak requires it on the device endpoint
# of `ams-r` (measured 2026-10-18).

pkce_pair <- function() {
  verifier <- base64url_encode(openssl::rand_bytes(32))
  list(
    verifier = verifier,
    challenge = base64url_encode(openssl::sha256(charToRaw(verifier))),
    method = "S256"
  )
}

base64url_encode <- function(bytes) {
  text <- openssl::base64_encode(unclass(bytes))
  sub("=+$", "", chartr("+/", "-_", text))
}

base64url_decode <- function(text) {
  text <- chartr("-_", "+/", text)
  pad <- (4L - nchar(text) %% 4L) %% 4L
  openssl::base64_decode(paste0(text, strrep("=", pad)))
}

# ---------------------------------------------------------------------------
# One form POST to Keycloak. Returns list(status, body); a transport failure
# is a `soilhub_unavailable_error`. Logged at verbosity 2 without the body.

oauth_post <- function(soil, url, fields) {
  fields <- Filter(Negate(is.null), fields)
  req <- httr2::request(url)
  req <- do.call(httr2::req_body_form, c(list(req), fields))
  req <- httr2::req_headers(req, Accept = "application/json")
  req <- httr2::req_user_agent(req, user_agent())
  req <- httr2::req_timeout(req, auth_request_timeout)
  req <- httr2::req_options(req, connecttimeout = http_connect_timeout)
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  started <- Sys.time()
  resp <- tryCatch(httr2::req_perform(req), error = function(e) e)
  elapsed <- round(as.numeric(difftime(Sys.time(), started, units = "secs")) * 1000)
  if (!inherits(resp, "httr2_response")) {
    soil_inform(soil, 2, sprintf("soilhub: POST %s -> transport error (%s ms)", url_path(url), format(elapsed)))
    reason <- if (!is.null(resp$parent)) conditionMessage(resp$parent) else conditionMessage(resp)
    abort(soilhub_api_error(
      sprintf(
        "Keycloak at %s could not be reached: %s",
        soil$keycloak_url, sub("^\\s+", "", reason)
      ),
      status = NULL, endpoint = url_path(url), method = "POST",
      code = "transport_error", reason = "transport_error", attempts = 1L,
      subclass = "unavailable"
    ))
  }
  status <- httr2::resp_status(resp)
  soil_inform(soil, 2, sprintf("soilhub: POST %s -> %s (%s ms)", url_path(url), status, format(elapsed)))
  body <- tryCatch(parse_body(resp), error = function(e) NULL)
  list(status = status, body = if (is.list(body)) body else NULL, url = url)
}

url_path <- function(url) sub("^https?://[^/]+", "", url)

# The OAuth error of a Keycloak response (`error`, `error_description`).
oauth_error <- function(response) {
  body <- response$body
  code <- if (is.list(body) && is_string(body$error)) body$error else NULL
  description <- if (is.list(body) && is_string(body$error_description)) body$error_description else NULL
  list(code = code, description = description)
}

oauth_error_text <- function(response) {
  error <- oauth_error(response)
  if (is.null(error$code)) return(paste("HTTP", response$status))
  paste(c(error$code, error$description), collapse = ": ")
}

keycloak_unavailable <- function(response) {
  soilhub_api_error(
    sprintf(
      "Keycloak answered HTTP %s at %s; try again later.",
      response$status, url_path(response$url)
    ),
    status = response$status, endpoint = url_path(response$url),
    method = "POST", code = oauth_error(response)$code,
    subclass = "unavailable"
  )
}

# ---------------------------------------------------------------------------
# Device login (design 3.2): returns the token response (a list).

device_login <- function(soil, open_browser = FALSE) {
  endpoints <- auth_endpoints(soil)
  pkce <- pkce_pair()
  start <- oauth_post(soil, endpoints$device, list(
    client_id = soil$client_id,
    scope = auth_scope,
    code_challenge = pkce$challenge,
    code_challenge_method = pkce$method
  ))
  grant <- start$body
  if (start$status >= 500L) abort(keycloak_unavailable(start))
  if (start$status != 200L || !is_string(grant$device_code)) {
    abort(soilhub_auth_error(
      sprintf(
        "Keycloak refused to start the device login for client `%s` (%s).",
        soil$client_id, oauth_error_text(start)
      ),
      reason = "login_denied", status = start$status,
      endpoint = url_path(endpoints$device), detail = oauth_error(start)
    ))
  }

  expires_in <- as.numeric(grant$expires_in %||% device_default_expires_in)
  interval <- as.numeric(grant$interval %||% device_default_interval)
  url <- grant$verification_uri_complete %||% grant$verification_uri %||%
    grant$verification_url
  show_device_instructions(grant, expires_in)
  if (isTRUE(open_browser) && is_string(url)) {
    try(soilhub_env$browse(url), silent = TRUE)
  }

  deadline <- soil_now() + expires_in
  repeat {
    if (soil_now() >= deadline) abort(login_timeout_error(expires_in))
    http_sleep(interval)
    poll <- oauth_post(soil, endpoints$token, list(
      grant_type = device_grant_type,
      device_code = grant$device_code,
      client_id = soil$client_id,
      code_verifier = pkce$verifier
    ))
    if (poll$status == 200L && is_string(poll$body$access_token)) {
      return(poll$body)
    }
    if (poll$status >= 500L) abort(keycloak_unavailable(poll))
    code <- oauth_error(poll)$code
    if (identical(code, "authorization_pending")) next
    if (identical(code, "slow_down")) {
      interval <- interval + 5
      next
    }
    if (identical(code, "expired_token")) abort(login_timeout_error(expires_in))
    abort(soilhub_auth_error(
      sprintf(
        "The login was not completed (%s): run `soil_login(soil)` to try again.",
        oauth_error_text(poll)
      ),
      reason = "login_denied", status = poll$status,
      endpoint = url_path(endpoints$token), detail = oauth_error(poll)
    ))
  }
}

show_device_instructions <- function(grant, expires_in) {
  where <- grant$verification_uri %||% grant$verification_url
  direct <- grant$verification_uri_complete
  lines <- sprintf(
    "soilhub: to sign in, open %s and enter the code %s",
    where %||% direct, grant$user_code %||% "(none)"
  )
  if (is_string(direct) && !identical(direct, where)) {
    lines <- c(lines, sprintf("  (or open %s directly).", direct))
  }
  lines <- c(lines, sprintf(
    "  The code is valid for %s; waiting for the browser step...",
    format_duration(expires_in)
  ))
  soilhub_message(paste(lines, collapse = "\n"))
}

login_timeout_error <- function(expires_in) {
  soilhub_auth_error(
    sprintf(
      "The login code expired (valid for %s) before the browser step was completed: run `soil_login(soil)` to try again.",
      format_duration(expires_in)
    ),
    reason = "login_timeout"
  )
}

# ---------------------------------------------------------------------------
# Token store.

store_tokens <- function(soil, token, renewed = FALSE) {
  state <- soil$state
  now <- soil_now()
  expires_in <- suppressWarnings(as.numeric(token$expires_in %||% NA))
  refresh_in <- suppressWarnings(as.numeric(token$refresh_expires_in %||% NA))

  state$access_token <- token$access_token
  if (is_string(token$refresh_token)) {
    # Keycloak rotates the refresh token: the new one replaces the old one.
    state$refresh_token <- token$refresh_token
  } else if (!renewed) {
    state$refresh_token <- NULL
  }
  if (length(expires_in) == 1L && !is.na(expires_in)) {
    state$expires_at <- now + expires_in
    state$access_lifetime <- expires_in
  } else {
    exp <- jwt_payload(token$access_token)$exp
    state$expires_at <- if (is.numeric(exp)) as_utc(exp) else NA
    state$access_lifetime <- if (is.numeric(exp)) as.numeric(as_utc(exp) - now, units = "secs") else NA_real_
  }
  # `refresh_expires_in = 0` is Keycloak's "no expiry" (offline tokens).
  if (length(refresh_in) == 1L && !is.na(refresh_in) && refresh_in > 0) {
    state$refresh_expires_at <- now + refresh_in
  } else if (!renewed || !is_string(state$refresh_token)) {
    state$refresh_expires_at <- NA
  }
  state$ended <- NULL
  state$renewal_failed <- NULL
  state$signed_out <- NULL
  if (renewed) {
    state$last_renewed_at <- now
    state$renewals <- (state$renewals %||% 0L) + 1L
  } else {
    state$logged_in_at <- now
    state$last_renewed_at <- NULL
    state$renewals <- 0L
  }
  update_identity(soil)
  invisible(soil)
}

clear_tokens <- function(state) {
  state$access_token <- NULL
  state$refresh_token <- NULL
  state$expires_at <- NULL
  state$refresh_expires_at <- NULL
  invisible(state)
}

# End the session with `condition` (kept and re-signalled until a new login).
end_session <- function(soil, condition) {
  state <- soil$state
  clear_tokens(state)
  state$ended <- condition
  abort(condition)
}

# Seconds of validity left to the access token (NA when unknown).
token_remaining <- function(state, now = soil_now()) {
  if (is.null(state$expires_at) || all(is.na(state$expires_at))) return(NA_real_)
  as.numeric(difftime(state$expires_at, now, units = "secs"))
}

#' Proactive refresh margin
#'
#' Seconds before the expiry of the access token at which the next request
#' renews it: option `soilhub.refresh_margin`, else `SOILHUB_REFRESH_MARGIN`,
#' else 60.
#' @return A non-negative number of seconds.
#' @keywords internal
#' @noRd
refresh_margin <- function() {
  setting <- config_value(
    NULL, "soilhub.refresh_margin", "SOILHUB_REFRESH_MARGIN",
    auth_default_margin
  )
  value <- suppressWarnings(as.numeric(setting$value))
  if (length(value) != 1L || is.na(value) || value < 0 || is.infinite(value)) {
    abort(soilhub_argument_error(
      sprintf(
        "The refresh margin (`soilhub.refresh_margin`) must be a non-negative number of seconds, not %s.",
        deparse_argument(setting$value)
      ),
      "soilhub.refresh_margin"
    ))
  }
  value
}

# ---------------------------------------------------------------------------
# Renewal (design 3.3).

# `proactive = TRUE`: a refused renewal while the access token is still
# valid does not end the session at once: the refresh token is dropped, one
# `soilhub_renewal_warning` says when the session ends, and the access token
# is used until it expires or the API refuses it (then `session_expired`).
refresh_session <- function(soil, proactive = FALSE) {
  state <- soil$state
  if (!is_string(state$refresh_token)) {
    end_session(soil, state$renewal_failed %||% no_refresh_token_error(state))
  }
  endpoints <- auth_endpoints(soil)
  response <- oauth_post(soil, endpoints$token, list(
    grant_type = "refresh_token",
    refresh_token = state$refresh_token,
    client_id = soil$client_id
  ))
  if (response$status == 200L && is_string(response$body$access_token)) {
    store_tokens(soil, response$body, renewed = TRUE)
    soil_inform(soil, 1, sprintf(
      "soilhub: session renewed; the access token is valid for %s.",
      format_duration(token_remaining(state))
    ))
    return(invisible(state$access_token))
  }
  if (response$status >= 500L) abort(keycloak_unavailable(response))
  # `invalid_grant` (SSO session idle or max reached, token revoked or
  # reused) and any other refusal: the session cannot be renewed.
  expired <- soilhub_auth_error(
    sprintf(
      paste0(
        "Your Keycloak session has expired and cannot be renewed (%s): ",
        "run `soil_login(soil)` to sign in again (the browser step), ",
        "or `soil_connect()` for a new session."
      ),
      oauth_error_text(response)
    ),
    reason = "session_expired", status = response$status,
    endpoint = url_path(response$url), detail = oauth_error(response)
  )
  remaining <- token_remaining(state)
  if (isTRUE(proactive) && !is.na(remaining) && remaining > 0) {
    state$refresh_token <- NULL
    state$renewal_failed <- expired
    soilhub_warning(sprintf(
      paste0(
        "Keycloak no longer renews this session (%s): the current access token ",
        "stays valid for %s, until %s; then run `soil_login(soil)` to sign in again."
      ),
      oauth_error_text(response), format_duration(remaining),
      format_time(state$expires_at)
    ), "soilhub_renewal_warning")
    return(invisible(state$access_token))
  }
  end_session(soil, expired)
}

no_refresh_token_error <- function(state) {
  lifetime <- state$access_lifetime %||% NA_real_
  soilhub_auth_error(
    sprintf(
      paste0(
        "The access token has expired (lifetime %s) and Keycloak issued no ",
        "refresh token, so the session cannot be renewed: run `soil_login(soil)` ",
        "to sign in again, or `soil_connect()` for a new session."
      ),
      if (is.na(lifetime)) "unknown" else format_duration(lifetime)
    ),
    reason = "no_refresh_token", lifetime = lifetime
  )
}

# The authentication hook of a session (the seam of http.R): returns the
# access token to send, renewing it when it expires within the refresh margin
# (proactive) or when `renew = TRUE` after a 401 (reactive); NULL for an
# anonymous request (never signed in, or signed out).
session_auth <- function(soil, renew = FALSE) {
  state <- soil$state
  if (!is.environment(state)) return(NULL)
  if (!is_string(state$access_token)) {
    if (!is.null(state$ended)) abort(state$ended)
    return(NULL)
  }
  if (isTRUE(renew)) {
    state$expires_at <- soil_now()
    refresh_session(soil)
    return(state$access_token)
  }
  remaining <- token_remaining(state)
  if (!is.na(remaining) && remaining < refresh_margin()) {
    if (!is_string(state$refresh_token)) {
      # Without a refresh token (none issued, or the renewal was refused)
      # the access token is used to its expiry.
      if (remaining > 0) return(state$access_token)
      end_session(soil, state$renewal_failed %||% no_refresh_token_error(state))
    }
    refresh_session(soil, proactive = TRUE)
  }
  state$access_token
}

# ---------------------------------------------------------------------------
# Time formatting.

as_utc <- function(seconds) {
  as.POSIXct(as.numeric(seconds), origin = "1970-01-01", tz = "UTC")
}

# "2h 0m", "45m", "30s"; negative values are formatted as 0s.
format_duration <- function(seconds) {
  seconds <- as.numeric(seconds)
  if (length(seconds) != 1L || is.na(seconds)) return("unknown")
  seconds <- max(0, round(seconds))
  hours <- seconds %/% 3600
  minutes <- (seconds %% 3600) %/% 60
  if (hours > 0) return(sprintf("%dh %dm", as.integer(hours), as.integer(minutes)))
  if (minutes > 0) return(sprintf("%dm", as.integer(minutes)))
  sprintf("%ds", as.integer(seconds))
}

format_time <- function(time) {
  if (is.null(time) || all(is.na(time))) return("unknown")
  format(time, "%Y-%m-%d %H:%M:%S %Z", tz = "UTC")
}
