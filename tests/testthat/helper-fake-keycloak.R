# Fake Keycloak realm and API for the session tests (design 3.3, 7.1).
#
# One webfakes app serves both, so that the API accepts exactly the access
# token Keycloak issued last. No real login and no network call: every URL
# is local. The client id selects the behaviour of the realm:
#
#   ams-r      reader (soil:summary, soil:read), refresh tokens rotate
#   publisher  reader + soil:publish
#   pdp        a token without a `resource_access` block
#   noroles    `resource_access` without the audience (no soil right)
#   norefresh  reader, no refresh token issued
#   deny       the user denies the device login (access_denied)
#   expire     the device code expires (expired_token)
#   slow       slow_down, then authorization_pending, then the token
#   never      authorization_pending until the device code expires (20 s)
#
# Realm paths: /realms/ams/protocol/openid-connect/{auth/device,token} (the
# fixed paths, no discovery document) and /realms/disc/.well-known/
# openid-configuration (a discovery document pointing to the /realms/ams
# endpoints). Test controls: POST /test/invalidate (the API stops accepting
# the current access token), POST /test/revoke (Keycloak ends the SSO
# session: refresh -> invalid_grant), GET /test/state.

fake_session_server <- function(capabilities = read_fixture("capabilities.json"),
                                .local_envir = parent.frame()) {
  testthat::skip_if_not_installed("webfakes")
  app <- webfakes::new_app()
  app$use(webfakes::mw_json())
  app$use(webfakes::mw_urlencoded())
  app$locals$capabilities <- capabilities
  app$locals$issued <- 0L
  app$locals$valid_access <- character()
  app$locals$current_refresh <- NULL
  app$locals$refresh_log <- character()
  app$locals$devices <- list()
  app$locals$revoked <- FALSE
  app$locals$scenario <- NULL
  app$locals$device_requests <- list()

  # Handlers run in the webfakes process: they and their helpers get a clean
  # environment (base R, plus jsonlite, openssl and webfakes by `::`).
  env <- new.env(parent = baseenv())
  route <- function(handler) {
    environment(handler) <- env
    handler
  }

  oauth_fail <- function(res, error, description = NULL, status = 400L) {
    res$set_status(status)$send_json(
      list(error = error, error_description = description),
      auto_unbox = TRUE
    )
  }

  b64url <- function(x) {
    if (is.character(x)) x <- charToRaw(x)
    sub("=+$", "", chartr("+/", "-_", openssl::base64_encode(x)))
  }

  issue <- function(req, res, client) {
    locals <- req$app$locals
    n <- locals$issued + 1L
    payload <- list(
      exp = as.integer(Sys.time()) + 7200L, iat = as.integer(Sys.time()),
      jti = paste0("jti-", n), iss = "http://fake/realms/ams",
      sub = "4b3c2a10-0000-4000-8000-00000000c0de", typ = "Bearer",
      azp = client, preferred_username = paste0("user-", client),
      scope = "openid soil"
    )
    roles <- switch(client,
      publisher = c("soil:summary", "soil:read", "soil:publish"),
      c("soil:summary", "soil:read")
    )
    if (identical(client, "noroles")) {
      payload$resource_access <- list(account = list(roles = list("view-profile")))
    } else if (!identical(client, "pdp")) {
      payload$resource_access <- list(
        `soil-api` = list(roles = as.list(roles)),
        account = list(roles = list("view-profile"))
      )
    }
    access <- paste(
      b64url('{"alg":"RS256","typ":"JWT"}'),
      b64url(jsonlite::toJSON(payload, auto_unbox = TRUE)),
      "c2lnbmF0dXJl",
      sep = "."
    )
    req$app$locals$issued <- n
    req$app$locals$valid_access <- access
    req$app$locals$scenario <- client
    req$app$locals$revoked <- FALSE
    body <- list(
      access_token = access, expires_in = 7200L, token_type = "Bearer",
      scope = "openid soil", `not-before-policy` = 0L
    )
    if (!identical(client, "norefresh")) {
      refresh <- paste0("rt-", n)
      req$app$locals$current_refresh <- refresh
      body$refresh_token <- refresh
      body$refresh_expires_in <- 28800L
    } else {
      req$app$locals$current_refresh <- NULL
      body$refresh_expires_in <- 0L
    }
    res$send_json(body, auto_unbox = TRUE)
  }

  app$post("/realms/ams/protocol/openid-connect/auth/device", route(function(req, res) {
    form <- req$form
    req$app$locals$device_requests <- c(req$app$locals$device_requests, list(form))
    if (is.null(form$code_challenge) || !identical(form$code_challenge_method, "S256")) {
      return(oauth_fail(res, "invalid_request", "Missing parameter: code_challenge_method"))
    }
    code <- paste0("dc-", length(req$app$locals$devices) + 1L)
    devices <- req$app$locals$devices
    devices[[code]] <- list(challenge = form$code_challenge, client = form$client_id, polls = 0L)
    req$app$locals$devices <- devices
    base <- paste0("http://", req$get_header("Host"), "/realms/ams/device")
    res$send_json(list(
      device_code = code, user_code = "WDJB-MJHT",
      verification_uri = base,
      verification_uri_complete = paste0(base, "?user_code=WDJB-MJHT"),
      expires_in = if (identical(form$client_id, "never")) 20L else 600L,
      interval = 5L
    ), auto_unbox = TRUE)
  }))

  app$post("/realms/ams/protocol/openid-connect/token", route(function(req, res) {
    form <- req$form
    if (identical(form$grant_type, "urn:ietf:params:oauth:grant-type:device_code")) {
      devices <- req$app$locals$devices
      device <- devices[[form$device_code]]
      if (is.null(device)) return(oauth_fail(res, "invalid_grant", "Device code not valid"))
      device$polls <- device$polls + 1L
      devices[[form$device_code]] <- device
      req$app$locals$devices <- devices
      client <- device$client
      if (identical(client, "deny")) return(oauth_fail(res, "access_denied", "The end user denied the authorization request."))
      if (identical(client, "expire")) return(oauth_fail(res, "expired_token", "Device code is expired"))
      if (identical(client, "never")) return(oauth_fail(res, "authorization_pending", "The authorization request is still pending"))
      if (identical(client, "slow") && device$polls == 1L) return(oauth_fail(res, "slow_down", "Slow down"))
      if (device$polls < if (identical(client, "slow")) 3L else 2L) {
        return(oauth_fail(res, "authorization_pending", "The authorization request is still pending"))
      }
      verifier <- if (is.null(form$code_verifier)) "" else form$code_verifier
      expected <- b64url(openssl::sha256(charToRaw(verifier)))
      if (is.null(form$code_verifier) || !identical(expected, device$challenge)) {
        return(oauth_fail(res, "invalid_grant", "PKCE verification failed"))
      }
      return(issue(req, res, client))
    }
    if (identical(form$grant_type, "refresh_token")) {
      req$app$locals$refresh_log <- c(req$app$locals$refresh_log, form$refresh_token)
      if (isTRUE(req$app$locals$revoked)) return(oauth_fail(res, "invalid_grant", "Session not active"))
      if (!identical(form$refresh_token, req$app$locals$current_refresh)) {
        return(oauth_fail(res, "invalid_grant", "Stale token"))
      }
      return(issue(req, res, form$client_id))
    }
    oauth_fail(res, "unsupported_grant_type", "Unsupported grant_type")
  }))

  app$get("/realms/disc/.well-known/openid-configuration", route(function(req, res) {
    base <- paste0("http://", req$get_header("Host"), "/realms/ams/protocol/openid-connect")
    res$send_json(list(
      issuer = "http://fake/realms/ams",
      device_authorization_endpoint = paste0(base, "/auth/device"),
      token_endpoint = paste0(base, "/token")
    ), auto_unbox = TRUE)
  }))

  authorised <- function(req) {
    header <- req$get_header("Authorization")
    !is.null(header) && length(req$app$locals$valid_access) == 1L &&
      identical(header, paste("Bearer", req$app$locals$valid_access))
  }
  unauthorised <- function(res) {
    res$set_status(401L)$send_json(list(detail = "Invalid authentication token"), auto_unbox = TRUE)
  }

  app$get("/api/v1/capabilities", route(function(req, res) {
    if (!authorised(req)) return(unauthorised(res))
    if (identical(req$app$locals$scenario, "noroles")) {
      return(res$set_status(403L)$send_json(list(detail = "Missing required scope"), auto_unbox = TRUE))
    }
    res$send_json(req$app$locals$capabilities, auto_unbox = TRUE, null = "null")
  }))

  app$get("/api/v1/protected", route(function(req, res) {
    if (!authorised(req)) return(unauthorised(res))
    res$send_json(list(ok = TRUE, issued = req$app$locals$issued), auto_unbox = TRUE)
  }))

  app$get("/api/v1/forbidden", route(function(req, res) {
    res$set_status(403L)$send_json(list(detail = "Missing required scope"), auto_unbox = TRUE)
  }))

  # Two pages; after the first one Keycloak ends the session (mid-download
  # expiry, design 3.4).
  app$post("/api/v1/pages", route(function(req, res) {
    if (!authorised(req)) return(unauthorised(res))
    offset <- req$json$offset
    if (offset == 0) {
      req$app$locals$valid_access <- character()
      req$app$locals$revoked <- TRUE
    }
    res$send_json(list(
      rows = list(list(id = offset + 1), list(id = offset + 2)),
      metadata = list(limit = 2L, offset = offset, returned_count = 2L, has_more = TRUE)
    ), auto_unbox = TRUE)
  }))

  app$post("/test/invalidate", route(function(req, res) {
    req$app$locals$valid_access <- character()
    res$send_json(list(ok = TRUE), auto_unbox = TRUE)
  }))
  app$post("/test/revoke", route(function(req, res) {
    req$app$locals$valid_access <- character()
    req$app$locals$revoked <- TRUE
    res$send_json(list(ok = TRUE), auto_unbox = TRUE)
  }))
  app$get("/test/state", route(function(req, res) {
    locals <- req$app$locals
    res$send_json(list(
      issued = locals$issued,
      refresh_log = as.list(locals$refresh_log),
      current_refresh = locals$current_refresh,
      device_requests = locals$device_requests
    ), auto_unbox = TRUE, null = "null")
  }))

  for (name in c("oauth_fail", "b64url", "issue", "authorised", "unauthorised")) {
    assign(name, route(get(name)), envir = env)
  }
  webfakes::local_app_process(app, .local_envir = .local_envir)
}

server_state <- function(server) {
  jsonlite::fromJSON(
    httr2::resp_body_string(httr2::req_perform(httr2::request(server$url("/test/state")))),
    simplifyVector = FALSE
  )
}

server_post <- function(server, path) {
  httr2::req_perform(httr2::req_method(httr2::request(server$url(path)), "POST"))
  invisible(NULL)
}

# A controllable clock for the calling test: `soil_now()` returns `clock$now`
# and every sleep advances it (and is recorded in `clock$waits`).
local_fake_clock <- function(start = as.POSIXct("2026-10-18 08:00:00", tz = "UTC"),
                             .local_envir = parent.frame()) {
  clock <- new.env(parent = emptyenv())
  clock$now <- start
  clock$waits <- numeric()
  old_now <- soilhub_env$now
  old_sleep <- soilhub_env$sleep
  soilhub_env$now <- function() clock$now
  soilhub_env$sleep <- function(seconds) {
    clock$waits <- c(clock$waits, seconds)
    clock$now <- clock$now + seconds
  }
  withr::defer({
    soilhub_env$now <- old_now
    soilhub_env$sleep <- old_sleep
  }, envir = .local_envir)
  clock
}

advance_clock <- function(clock, seconds) {
  clock$now <- clock$now + seconds
  invisible(clock$now)
}

# No default session (and a clean configuration) for the calling test.
local_no_default_session <- function(.local_envir = parent.frame()) {
  withr::local_options(list(soilhub.session = NULL, soilhub.refresh_margin = NULL),
                       .local_envir = .local_envir)
  withr::local_envvar(c(SOILHUB_REFRESH_MARGIN = NA), .local_envir = .local_envir)
}

# Connect to the fake server as `client_id`, quietly (the device-login
# instructions are messages).
fake_connect <- function(server, client_id = "ams-r", realm = "ams", verbose = 0, ...) {
  suppressMessages(soil_connect(
    api_url = server$url("/api/v1"),
    keycloak_url = server$url(paste0("/realms/", realm)),
    client_id = client_id, open_browser = FALSE, verbose = verbose, timeout = 30,
    ...
  ))
}

# A JWT built from a payload fixture (unsigned: the client never checks it).
fixture_jwt <- function(name) {
  payload <- read_fixture(name)
  enc <- function(text) sub("=+$", "", chartr("+/", "-_", openssl::base64_encode(charToRaw(text))))
  paste(
    enc('{"alg":"RS256","typ":"JWT"}'),
    enc(as.character(jsonlite::toJSON(payload, auto_unbox = TRUE))),
    "c2lnbmF0dXJl",
    sep = "."
  )
}
