# Sessions: device login, renewal, default session, print (design 3, 4.2)
# against a fake Keycloak realm and API (helper-fake-keycloak.R), on a
# controllable clock. No real login, no network.

server <- fake_session_server()

test_that("the device login uses PKCE S256 and stores the tokens in memory", {
  local_no_default_session()
  clock <- local_fake_clock()
  msgs <- testthat::capture_messages(
    soil <- soil_connect(
      api_url = server$url("/api/v1"), keycloak_url = server$url("/realms/ams"),
      client_id = "ams-r", open_browser = FALSE, verbose = 0
    )
  )
  expect_s3_class(soil, "soil_session")
  # instructions: address and code, always shown
  expect_true(any(grepl("open http://127.0.0.1:[0-9]+/realms/ams/device and enter the code WDJB-MJHT", msgs)))
  expect_true(any(grepl("valid for 10m", msgs, fixed = TRUE)))

  state <- server_state(server)
  request <- state$device_requests[[length(state$device_requests)]]
  expect_identical(request$code_challenge_method, "S256")
  expect_identical(request$scope, "openid soil")
  expect_identical(request$client_id, "ams-r")
  expect_match(request$code_challenge, "^[A-Za-z0-9_-]{43}$")

  # one pending poll, then the token: two waits of the advertised interval
  expect_identical(clock$waits, c(5, 5))
  expect_identical(soil$state$expires_at, clock$now + 7200)
  expect_identical(soil$state$refresh_expires_at, clock$now + 28800)
  expect_identical(soil$state$refresh_token, state$current_refresh)
  expect_identical(soil$state$endpoints$source, "fixed")

  # capabilities read after the login, identity from the token
  expect_identical(soil$state$capabilities$api_version, "0.5.0")
  expect_identical(soil$state$identity$username, "user-ams-r")
  expect_identical(soil$state$identity$roles, c("soil:read", "soil:summary"))
  expect_true(soil_request(soil, "GET", "/protected")$ok)
})

test_that("PKCE challenge is the base64url SHA-256 of the verifier", {
  pair <- pkce_pair()
  expect_match(pair$verifier, "^[A-Za-z0-9_-]{43}$")
  expect_identical(pair$method, "S256")
  expect_identical(
    pair$challenge,
    sub("=+$", "", chartr("+/", "-_", jsonlite::base64_enc(openssl::sha256(charToRaw(pair$verifier)))))
  )
  expect_false(identical(pkce_pair()$verifier, pair$verifier))
})

test_that("the realm endpoints come from the discovery document when served", {
  local_no_default_session()
  local_fake_clock()
  soil <- fake_connect(server, realm = "disc")
  expect_identical(soil$state$endpoints$source, "discovery")
  expect_match(soil$state$endpoints$token, "/realms/ams/protocol/openid-connect/token$")
  expect_true(soil_request(soil, "GET", "/protected")$ok)
})

test_that("a denied, expired or abandoned device login is a soilhub_auth_error", {
  local_no_default_session()
  clock <- local_fake_clock()
  e <- expect_error(fake_connect(server, "deny"), class = "soilhub_auth_error")
  expect_identical(e$reason, "login_denied")
  expect_match(conditionMessage(e), "access_denied")
  expect_null(getOption("soilhub.session"))

  e <- expect_error(fake_connect(server, "expire"), class = "soilhub_auth_error")
  expect_identical(e$reason, "login_timeout")

  clock$waits <- numeric()
  e <- expect_error(fake_connect(server, "never"), class = "soilhub_auth_error")
  expect_identical(e$reason, "login_timeout")
  expect_match(conditionMessage(e), "valid for 20s")
  expect_identical(sum(clock$waits), 20)
})

test_that("slow_down lengthens the polling interval by 5 s", {
  local_no_default_session()
  clock <- local_fake_clock()
  soil <- fake_connect(server, "slow")
  expect_identical(clock$waits, c(5, 10, 10))
  expect_true(is_string(soil$state$access_token))
})

test_that("open_browser opens the complete verification address", {
  local_no_default_session()
  local_fake_clock()
  opened <- character()
  old <- soilhub_env$browse
  soilhub_env$browse <- function(url) opened <<- c(opened, url)
  withr::defer(soilhub_env$browse <- old)
  suppressMessages(soil_connect(
    api_url = server$url("/api/v1"), keycloak_url = server$url("/realms/ams"),
    client_id = "ams-r", open_browser = TRUE, verbose = 0
  ))
  expect_length(opened, 1L)
  expect_match(opened, "/realms/ams/device\\?user_code=WDJB-MJHT$")
})

test_that("the token is renewed proactively within the margin, storing the rotated refresh token", {
  local_no_default_session()
  clock <- local_fake_clock()
  soil <- fake_connect(server)
  first_refresh <- soil$state$refresh_token
  log_before <- length(server_state(server)$refresh_log)

  # 2 minutes before expiry: outside the 60 s margin, no renewal
  advance_clock(clock, 7200 - 120)
  expect_true(soil_request(soil, "GET", "/protected")$ok)
  expect_length(server_state(server)$refresh_log, log_before)

  # 30 s before expiry: renewed before the request
  advance_clock(clock, 90)
  issued <- soil_request(soil, "GET", "/protected")$issued
  state <- server_state(server)
  expect_identical(unlist(state$refresh_log)[log_before + 1L], first_refresh)
  expect_identical(soil$state$refresh_token, state$current_refresh)
  expect_false(identical(soil$state$refresh_token, first_refresh))
  expect_identical(soil$state$last_renewed_at, clock$now)
  expect_identical(soil$state$expires_at, clock$now + 7200)
  expect_identical(soil$state$renewals, 1L)
  expect_identical(issued, state$issued)

  # the next renewal presents the rotated token (the old one is refused by
  # the fake realm, as Keycloak's reuse detection does)
  second_refresh <- soil$state$refresh_token
  advance_clock(clock, 7200 - 10)
  expect_true(soil_request(soil, "GET", "/protected")$ok)
  expect_identical(unlist(server_state(server)$refresh_log)[log_before + 2L], second_refresh)
  expect_identical(soil$state$renewals, 2L)
})

test_that("the refresh margin is configurable", {
  local_no_default_session()
  clock <- local_fake_clock()
  soil <- fake_connect(server)
  log_before <- length(server_state(server)$refresh_log)

  advance_clock(clock, 7200 - 300)
  withr::local_options(soilhub.refresh_margin = 600)
  expect_true(soil_request(soil, "GET", "/protected")$ok)
  expect_length(server_state(server)$refresh_log, log_before + 1L)

  withr::local_options(soilhub.refresh_margin = NULL)
  withr::local_envvar(SOILHUB_REFRESH_MARGIN = "0")
  advance_clock(clock, 7200 - 1)
  expect_true(soil_request(soil, "GET", "/protected")$ok)
  expect_length(server_state(server)$refresh_log, log_before + 1L)

  withr::local_options(soilhub.refresh_margin = -1)
  expect_error(soil_request(soil, "GET", "/protected"), class = "soilhub_argument_error")
})

test_that("a 401 renews the token once and repeats the request", {
  local_no_default_session()
  local_fake_clock()
  soil <- fake_connect(server, verbose = 1)
  log_before <- length(server_state(server)$refresh_log)
  old_token <- soil$state$access_token

  server_post(server, "/test/invalidate")
  msgs <- testthat::capture_messages(out <- soil_request(soil, "GET", "/protected"))
  expect_true(out$ok)
  expect_length(server_state(server)$refresh_log, log_before + 1L)
  expect_false(identical(soil$state$access_token, old_token))
  expect_true(any(grepl("HTTP 401", msgs)))
  expect_true(any(grepl("session renewed", msgs)))
})

test_that("a refused renewal ends the session with reason session_expired", {
  local_no_default_session()
  clock <- local_fake_clock()
  soil <- fake_connect(server)

  # proactive renewal refused (Keycloak SSO session ended)
  server_post(server, "/test/revoke")
  advance_clock(clock, 7200)
  e <- expect_error(soil_request(soil, "GET", "/protected"), class = "soilhub_auth_error")
  expect_identical(e$reason, "session_expired")
  expect_match(conditionMessage(e), "invalid_grant: Session not active", fixed = TRUE)
  expect_match(conditionMessage(e), "soil_login(soil)", fixed = TRUE)
  expect_match(conditionMessage(e), "soil_connect()", fixed = TRUE)
  expect_null(soil$state$access_token)
  expect_null(soil$state$refresh_token)

  # every later call says the same, without contacting Keycloak
  n <- length(server_state(server)$refresh_log)
  e2 <- expect_error(soil_request(soil, "GET", "/protected"), class = "soilhub_auth_error")
  expect_identical(e2$reason, "session_expired")
  expect_length(server_state(server)$refresh_log, n)
  expect_match(format(soil)[4], "session expired")

  # soil_login() on the same session recovers
  suppressMessages(soil_login(soil))
  expect_true(soil_request(soil, "GET", "/protected")$ok)

  # reactive renewal refused: the 401 leads to session_expired, not not_logged_in
  server_post(server, "/test/revoke")
  e <- expect_error(soil_request(soil, "GET", "/protected"), class = "soilhub_auth_error")
  expect_identical(e$reason, "session_expired")
})

test_that("a refused proactive renewal keeps the valid access token until it expires", {
  local_no_default_session()
  clock <- local_fake_clock()
  soil <- fake_connect(server)
  expires_at <- soil$state$expires_at

  # Keycloak ends the SSO session; the access token is still valid for 30 s
  server_post(server, "/test/revoke-sso")
  advance_clock(clock, 7200 - 30)
  n <- length(server_state(server)$refresh_log)
  w <- expect_warning(out <- soil_request(soil, "GET", "/protected"), class = "soilhub_renewal_warning")
  expect_s3_class(w, "soilhub_warning")
  expect_true(out$ok)
  expect_match(conditionMessage(w), "invalid_grant: Session not active", fixed = TRUE)
  expect_match(conditionMessage(w), "stays valid for 30s, until 2026-10-18 10:00:10 UTC", fixed = TRUE)
  expect_match(conditionMessage(w), "soil_login(soil)", fixed = TRUE)
  expect_length(server_state(server)$refresh_log, n + 1L)
  expect_identical(soil$state$expires_at, expires_at)
  expect_false(soil_whoami(soil)$session_renewable)

  # until the expiry: no further warning and no further renewal attempt
  advance_clock(clock, 20)
  expect_no_warning(out <- soil_request(soil, "GET", "/protected"))
  expect_true(out$ok)
  expect_length(server_state(server)$refresh_log, n + 1L)

  # at the expiry: session_expired (not no_refresh_token)
  advance_clock(clock, 10)
  e <- expect_error(soil_request(soil, "GET", "/protected"), class = "soilhub_auth_error")
  expect_identical(e$reason, "session_expired")
  expect_match(conditionMessage(e), "soil_login(soil)", fixed = TRUE)
  expect_null(soil$state$access_token)
  expect_length(server_state(server)$refresh_log, n + 1L)

  # a 401 before the expiry also ends it with session_expired
  suppressMessages(soil_login(soil))
  server_post(server, "/test/revoke-sso")
  advance_clock(clock, 7200 - 30)
  expect_warning(soil_request(soil, "GET", "/protected"), class = "soilhub_renewal_warning")
  server_post(server, "/test/invalidate")
  e <- expect_error(soil_request(soil, "GET", "/protected"), class = "soilhub_auth_error")
  expect_identical(e$reason, "session_expired")
})

test_that("Keycloak unreachable during a renewal keeps the session", {
  local_no_default_session()
  clock <- local_fake_clock()
  soil <- fake_connect(server)
  token <- soil$state$refresh_token
  soil$state$endpoints$token <- "http://127.0.0.1:9/token"
  advance_clock(clock, 7200 - 10)
  e <- expect_error(soil_request(soil, "GET", "/protected"), class = "soilhub_unavailable_error")
  expect_match(conditionMessage(e), "could not be reached")
  expect_identical(soil$state$refresh_token, token)
})

test_that("without a refresh token the session ends at the first expiry", {
  local_no_default_session()
  clock <- local_fake_clock()
  soil <- fake_connect(server, "norefresh")
  expect_null(soil$state$refresh_token)
  expect_false(soil_whoami(soil)$session_renewable)
  expect_match(format(soil)[6], "not renewable")

  # inside the margin, the token is used to its expiry
  advance_clock(clock, 7200 - 30)
  expect_true(soil_request(soil, "GET", "/protected")$ok)

  advance_clock(clock, 31)
  e <- expect_error(soil_request(soil, "GET", "/protected"), class = "soilhub_auth_error")
  expect_identical(e$reason, "no_refresh_token")
  expect_identical(e$lifetime, 7200)
  expect_match(conditionMessage(e), "lifetime 2h 0m")
  expect_match(conditionMessage(e), "soil_login(soil)", fixed = TRUE)

  # reactive path: a 401 with no refresh token
  suppressMessages(soil_login(soil))
  server_post(server, "/test/invalidate")
  e <- expect_error(soil_request(soil, "GET", "/protected"), class = "soilhub_auth_error")
  expect_identical(e$reason, "no_refresh_token")
})

test_that("an expiry mid-download keeps the pages already read", {
  local_no_default_session()
  local_fake_clock()
  soil <- fake_connect(server)
  e <- expect_error(
    soil_collect(soil, "/pages", list(), items = "rows", page_size = 2, progress = FALSE),
    class = "soilhub_auth_error"
  )
  expect_identical(e$reason, "session_expired")
  expect_length(e$partial$items, 2L)
  expect_false(e$partial$metadata$complete)
  expect_identical(e$partial$metadata$next_offset, 2)
})

test_that("soil_connect() registers the default session; explicit sessions are independent", {
  local_no_default_session()
  local_fake_clock()
  e <- expect_error(soil_session(), class = "soilhub_auth_error")
  expect_identical(e$reason, "no_session")

  reader <- fake_connect(server, "ams-r")
  expect_identical(soil_session()$state, reader$state)
  expect_identical(soil_whoami()$username, "user-ams-r")

  publisher <- fake_connect(server, "publisher", set_default = FALSE)
  expect_identical(soil_session()$state, reader$state)
  expect_identical(soil_whoami(publisher)$can[["publish"]], TRUE)
  expect_false(identical(publisher$state$refresh_token, reader$state$refresh_token))
  expect_match(format(publisher)[length(format(publisher))], "Default:  no")
  expect_match(format(reader)[length(format(reader))], "Default:  yes")

  # set the default explicitly
  soil_session(publisher)
  expect_identical(soil_whoami()$username, "user-publisher")

  # logging out a session that is not the default leaves the default alone
  soil_logout(reader)
  expect_identical(soil_session()$state, publisher$state)
  expect_null(reader$state$access_token)
  e <- expect_error(soil_whoami(reader), class = "soilhub_auth_error")
  expect_identical(e$reason, "not_logged_in")
  expect_match(format(reader)[4], "signed out")

  # logging out the default unregisters it
  soil_logout()
  e <- expect_error(soil_session(), class = "soilhub_auth_error")
  expect_identical(e$reason, "no_session")
  expect_error(soil_session("not a session"), class = "soilhub_argument_error")
})

test_that("login = FALSE creates a session to sign in later; soil_login() reuses a valid one", {
  local_no_default_session()
  local_fake_clock()
  soil <- soil_connect(
    api_url = server$url("/api/v1"), keycloak_url = server$url("/realms/ams"),
    client_id = "ams-r", login = FALSE, verbose = 0
  )
  expect_identical(session_status(soil), "not_signed_in")
  expect_match(format(soil)[4], "not signed in")
  # an anonymous request: the API's 401 is not_logged_in
  e <- expect_error(soil_request(soil, "GET", "/protected"), class = "soilhub_auth_error")
  expect_identical(e$reason, "not_logged_in")

  suppressMessages(soil_login())
  expect_identical(session_status(soil), "signed_in")
  issued <- server_state(server)$issued
  expect_no_message(soil_login(soil))
  expect_identical(server_state(server)$issued, issued)

  suppressMessages(soil_login(soil, force = TRUE))
  expect_identical(server_state(server)$issued, issued + 1L)
})

test_that("rights: a user without soil:summary is warned; undeclared rights are left to the API", {
  local_no_default_session()
  local_fake_clock()
  expect_warning(reader <- fake_connect(server, "readonly"), class = "soilhub_rights_warning")
  expect_identical(soil_whoami(reader)$can, c(summary = FALSE, read = TRUE, publish = FALSE, admin = FALSE))
  expect_error(soil_require_right(reader, "soil:summary"), class = "soilhub_permission_error")

  # resource_access without the audience: no local check, the API decides
  # (here /capabilities answers 403, reported as a warning)
  expect_warning(guest <- fake_connect(server, "noroles"), class = "soilhub_capabilities_warning")
  expect_false(soil_whoami(guest)$rights_known)
  expect_identical(soil_whoami(guest)$can, c(summary = NA, read = NA, publish = NA, admin = NA))
  expect_identical(soil_require_right(guest, "soil:read"), NA)
  expect_match(format(guest)[5], "not declared in the token; the API decides", fixed = TRUE)

  pdp <- fake_connect(server, "pdp")
  expect_false(soil_whoami(pdp)$rights_known)
  expect_identical(soil_require_right(pdp, "soil:admin"), NA)
  expect_match(format(pdp)[5], "not declared in the token; the API decides", fixed = TRUE)
})

test_that("a 403 names the right the request needs and the session's rights", {
  local_no_default_session()
  local_fake_clock()
  soil <- fake_connect(server)
  e <- expect_error(soil_request(soil, "GET", "/forbidden", right = "admin"), class = "soilhub_permission_error")
  expect_identical(e$required_right, "soil:admin")
  expect_identical(e$rights, c("soil:read", "soil:summary"))
  expect_identical(e$status, 403L)
  expect_match(
    conditionMessage(e),
    "Permission denied: Missing required scope (this request needs the right `soil:admin`; your session has `soil:read`, `soil:summary`)",
    fixed = TRUE
  )
})

test_that("no token is ever printed, logged or put in a condition", {
  local_no_default_session()
  clock <- local_fake_clock()
  output <- character()
  msgs <- testthat::capture_messages({
    soil <- soil_connect(
      api_url = server$url("/api/v1"), keycloak_url = server$url("/realms/ams"),
      client_id = "ams-r", open_browser = FALSE, verbose = 2
    )
    secrets <- c(soil$state$access_token, soil$state$refresh_token)
    advance_clock(clock, 7200)
    soil_request(soil, "GET", "/protected")
    secrets <- c(secrets, soil$state$access_token, soil$state$refresh_token)
    output <- c(
      capture.output(print(soil)),
      capture.output(print(soil_whoami(soil))),
      capture.output(str(soil))
    )
    server_post(server, "/test/revoke")
    e <- tryCatch(soil_request(soil, "GET", "/protected"), soilhub_error = function(e) e)
    output <- c(output, conditionMessage(e), capture.output(print(e)),
                paste(capture.output(str(unclass(e))), collapse = "\n"))
  })
  expect_true(any(grepl("POST /realms/ams/protocol/openid-connect/token -> 200", msgs, fixed = TRUE)))
  expect_true(any(grepl("^<soil_session>$", output)))
  expect_true(any(grepl("User:     user-ams-r", output, fixed = TRUE)))
  expect_true(any(grepl("Token:    valid for 2h 0m, renewable for 8h 0m, renewed 1 time(s)", output, fixed = TRUE)))
  everything <- c(msgs, output)
  for (secret in secrets) {
    expect_false(any(grepl(secret, everything, fixed = TRUE)))
  }
})

test_that("the session functions refuse anything but a soil_session", {
  expect_error(soil_login("x"), class = "soilhub_argument_error")
  expect_error(soil_whoami(list()), class = "soilhub_argument_error")
  expect_error(soil_logout(1), class = "soilhub_argument_error")
})
