# Identity and rights read from the token (design 1.3, 4.2): pure tests on
# fixture tokens, no server.

capabilities <- read_fixture("capabilities.json")

# A session with a token in its state, as after a login.
session_with_token <- function(token, capabilities = read_fixture("capabilities.json")) {
  config <- list(
    api_url = "http://127.0.0.1:9/api/v1", keycloak_url = "http://127.0.0.1:9/realms/ams",
    client_id = "ams-r", timeout = 30, verbose = 0L, dir = tempdir(), page_size = NULL
  )
  soil <- new_soil_session(config)
  soil$state$capabilities <- capabilities
  store_tokens(soil, list(access_token = token, expires_in = 7200, refresh_token = "rt-x",
                          refresh_expires_in = 28800))
  soil
}

test_that("the JWT payload is decoded from base64url without padding", {
  payload <- jwt_payload(fixture_jwt("jwt-reader.json"))
  expect_identical(payload$preferred_username, "student")
  expect_identical(payload$resource_access$`soil-api`$roles, list("soil:read", "soil:summary"))
  expect_null(jwt_payload("opaque-token"))
  expect_null(jwt_payload("a.%%%.c"))
  expect_null(jwt_payload(NULL))
  expect_identical(base64url_encode(charToRaw("?>?")), "Pz4_")
  expect_identical(rawToChar(base64url_decode("Pz4_")), "?>?")
})

test_that("roles are read for the audience advertised by /capabilities", {
  audience <- capabilities$authentication$audience
  expect_identical(audience, "soil-api")
  reader <- token_identity(fixture_jwt("jwt-reader.json"), audience)
  expect_identical(reader$username, "student")
  expect_identical(reader$subject, "00000000-0000-4000-8000-000000000001")
  expect_identical(reader$roles, c("soil:read", "soil:summary"))
  expect_true(reader$rights_known)
  expect_identical(reader$token_exp, as.POSIXct(1792332000, origin = "1970-01-01", tz = "UTC"))

  publisher <- token_identity(fixture_jwt("jwt-publisher.json"), audience)
  expect_identical(publisher$roles, c("soil:admin", "soil:publish", "soil:read", "soil:summary"))
  # another deployment with another audience reads other roles
  dev <- token_identity(fixture_jwt("jwt-publisher.json"), "soil-api-dev")
  expect_identical(dev$roles, "soil:summary")
})

test_that("rights are undeclared without a resource_access entry for the audience", {
  pdp <- token_identity(fixture_jwt("jwt-pdp.json"), "soil-api")
  expect_false(pdp$rights_known)
  expect_identical(pdp$roles, character())
  expect_identical(pdp$username, "pdp-user")

  # resource_access without the audience: undeclared (a PDP may grant them)
  guest <- token_identity(fixture_jwt("jwt-noroles.json"), "soil-api")
  expect_false(guest$rights_known)
  expect_identical(guest$roles, character())

  # an entry for the audience with no role: declared, none held
  visitor <- token_identity(fixture_jwt("jwt-emptyroles.json"), "soil-api")
  expect_true(visitor$rights_known)
  expect_identical(visitor$roles, character())

  # opaque token: nothing known
  opaque <- token_identity("opaque-token", "soil-api")
  expect_false(opaque$rights_known)
  expect_true(is.na(opaque$username))
})

test_that("the audience comes from the cached capabilities", {
  soil <- session_with_token(fixture_jwt("jwt-publisher.json"))
  expect_identical(session_audience(soil), "soil-api")
  expect_identical(soil$state$identity$roles, c("soil:admin", "soil:publish", "soil:read", "soil:summary"))

  dev <- capabilities
  dev$authentication$audience <- "soil-api-dev"
  soil <- session_with_token(fixture_jwt("jwt-publisher.json"), dev)
  expect_identical(soil$state$identity$roles, "soil:summary")

  # capabilities unknown: the default audience
  soil <- session_with_token(fixture_jwt("jwt-reader.json"), NULL)
  expect_identical(session_audience(soil), "soil-api")
  expect_identical(soil$state$identity$roles, c("soil:read", "soil:summary"))

  # authentication disabled: rights are not checked
  off <- capabilities
  off$authentication <- list(enabled = FALSE, type = "disabled", audience = NULL)
  soil <- session_with_token(fixture_jwt("jwt-reader.json"), off)
  expect_false(soil$state$identity$rights_known)
})

test_that("the permission pre-check refuses a missing right before any request", {
  reader <- session_with_token(fixture_jwt("jwt-reader.json"))
  expect_true(soil_require_right(reader, "soil:read"))
  expect_true(soil_require_right(reader, "summary"))
  e <- expect_error(
    soil_require_right(reader, "soil:admin", "`soil_register_variable()`"),
    class = "soilhub_permission_error"
  )
  expect_identical(
    conditionMessage(e),
    "`soil_register_variable()` needs the right `soil:admin`; your session has `soil:read`, `soil:summary`."
  )
  expect_identical(e$required_right, "soil:admin")
  expect_identical(e$rights, c("soil:read", "soil:summary"))
  expect_null(e$status)

  visitor <- session_with_token(fixture_jwt("jwt-emptyroles.json"))
  e <- expect_error(soil_require_right(visitor, "read"), class = "soilhub_permission_error")
  expect_match(conditionMessage(e), "your session has no right of `soil-api`", fixed = TRUE)

  publisher <- session_with_token(fixture_jwt("jwt-publisher.json"))
  expect_true(soil_require_right(publisher, "soil:admin"))
})

test_that("the pre-check is skipped when the token carries no rights", {
  pdp <- session_with_token(fixture_jwt("jwt-pdp.json"))
  expect_identical(soil_require_right(pdp, "soil:admin"), NA)
  # resource_access without the audience: the API decides
  guest <- session_with_token(fixture_jwt("jwt-noroles.json"))
  expect_identical(soil_require_right(guest, "soil:read"), NA)
  # no identity at all (a session never signed in, or a plain list)
  expect_identical(soil_require_right(list(api_url = "http://x"), "soil:admin"), NA)
  expect_error(soil_require_right(pdp, NA_character_), class = "soilhub_argument_error")
})

test_that("soil_whoami() reports user, rights, limits and the session lifetime", {
  clock <- local_fake_clock()
  soil <- session_with_token(fixture_jwt("jwt-reader.json"))
  me <- soil_whoami(soil)
  expect_s3_class(me, "soil_identity")
  expect_identical(me$username, "student")
  expect_identical(me$roles, c("soil:read", "soil:summary"))
  expect_identical(me$can, c(summary = TRUE, read = TRUE, publish = FALSE, admin = FALSE))
  expect_identical(me$limits$max_page_size, 1000L)
  expect_identical(me$token_expires_at, clock$now + 7200)
  expect_identical(me$session_expires_at, clock$now + 28800)
  expect_true(me$session_renewable)
  expect_identical(me$status, "signed_in")

  out <- capture.output(print(me))
  expect_identical(out[1], "<soil_identity> student")
  expect_true(any(grepl("Rights:  soil:read, soil:summary (audience soil-api)", out, fixed = TRUE)))
  expect_true(any(grepl("valid for 2h 0m", out, fixed = TRUE)))
  expect_true(any(grepl("soil:admin +no +soil_register_variable\\(\\)", out)))
  expect_true(any(grepl("Limits advertised by the server for this deployment", out, fixed = TRUE)))
  expect_true(any(grepl("max_sync_observations: 1,000,000", out, fixed = TRUE)))

  pdp <- soil_whoami(session_with_token(fixture_jwt("jwt-pdp.json")))
  expect_identical(pdp$can, c(summary = NA, read = NA, publish = NA, admin = NA))
  out <- capture.output(print(pdp))
  expect_true(any(grepl("Rights:  not declared in the token; the API decides", out, fixed = TRUE)))
  guest <- soil_whoami(session_with_token(fixture_jwt("jwt-noroles.json")))
  expect_identical(guest$can, c(summary = NA, read = NA, publish = NA, admin = NA))
})

test_that("the rights table names functions for the four rights", {
  expect_named(.rights, c("soil:summary", "soil:read", "soil:publish", "soil:admin"))
  expect_true("soil_register_variable" %in% .rights[["soil:admin"]])
  expect_true("soil_export_cancel" %in% .rights[["soil:publish"]])
  expect_false(anyDuplicated(unlist(.rights)) > 0)
})

test_that("durations are formatted for people", {
  expect_identical(format_duration(7200), "2h 0m")
  expect_identical(format_duration(6120), "1h 42m")
  expect_identical(format_duration(59 * 60), "59m")
  expect_identical(format_duration(30), "30s")
  expect_identical(format_duration(-5), "0s")
  expect_identical(format_duration(NA), "unknown")
})
