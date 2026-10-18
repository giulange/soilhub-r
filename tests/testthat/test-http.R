# HTTP layer (design 2.4) and error mapping (2.5) against a fake API.

# Route handlers run in the webfakes process: base R and webfakes only.
http_routes <- list(
  # Echo of what the client sent (headers and body).
  list(method = "all", path = "/api/v1/echo", handler = function(req, res) {
    id <- req$get_header("X-Request-ID")
    if (!is.null(id)) res$set_header("X-Request-ID", id)
    res$send_json(list(
      method = req$method,
      accept = req$get_header("Accept"),
      user_agent = req$get_header("User-Agent"),
      request_id = id,
      authorization = req$get_header("Authorization"),
      query = req$query_string,
      body = req$json
    ), auto_unbox = TRUE, null = "null", digits = NA)
  }),
  # Fails `n` times with `status` (and an optional Retry-After), then 200.
  list(method = "get", path = "/api/v1/flaky/:key/:status/:n", handler = function(req, res) {
    key <- req$params$key
    seen <- req$app$locals$seen
    if (is.null(seen)) seen <- list()
    seen[[key]] <- c(seen[[key]], req$get_header("X-Request-ID"))
    req$app$locals$seen <- seen
    attempts <- length(seen[[key]])
    if (attempts <= as.integer(req$params$n)) {
      if (!is.null(req$query$after)) res$set_header("Retry-After", req$query$after)
      return(res$set_status(as.integer(req$params$status))$send_json(
        list(detail = "Database unavailable"), auto_unbox = TRUE
      ))
    }
    res$send_json(list(ok = TRUE, attempts = attempts), auto_unbox = TRUE)
  }),
  # Request ids received for a key of /flaky.
  list(method = "get", path = "/api/v1/seen/:key", handler = function(req, res) {
    ids <- req$app$locals$seen[[req$params$key]]
    res$send_json(list(ids = as.list(ids)), auto_unbox = TRUE)
  }),
  # Error bodies of the API.
  list(method = "all", path = "/api/v1/error/:kind", handler = function(req, res) {
    id <- req$get_header("X-Request-ID")
    if (!is.null(id)) res$set_header("X-Request-ID", id)
    json <- function(status, text) {
      res$set_status(status)$set_type("application/json")$send(text)
    }
    switch(req$params$kind,
      not_found = json(404, '{"detail": "Dataset not found"}'),
      conflict = json(409, '{"detail": "product already exists with different content"}'),
      forbidden = json(403, '{"detail": "Missing required scope"}'),
      unauthorized = json(401, '{"detail": "Missing authentication token"}'),
      validation = json(422, '{"detail": "Unknown dataset(s): nope"}'),
      publication = json(422, paste0(
        '{"detail": {"message": "publication validation failed", "errors": [',
        '{"row": 0, "variable_code": "ORGC", "errors": ["unknown_or_undeclared_variable"]},',
        '{"row": 3, "variable_code": "CLAY", "errors": ["target_not_found", "invalid_depth_interval"]},',
        '{"code": "run_not_open", "message": "run status is completed"}]}}'
      )),
      bare = json(422, paste0(
        '{"message": "manifest invalid", "errors": [',
        '{"field": "crs", "message": "unsupported CRS"}]}'
      )),
      fastapi = json(422, paste0(
        '{"detail": [{"type": "missing", "loc": ["body", "datasets"], "msg": "Field required", "input": {}},',
        '{"type": "greater_than_equal", "loc": ["body", "limit"], "msg": "Input should be greater than or equal to 1", "input": 0}]}'
      )),
      load_limit = json(422, paste0(
        '{"detail": {"code": "load_limit_exceeded", "channel": "sync", ',
        '"message": "The selection holds more than 1,000,000 observations, above the limit of synchronous requests (1,000,000): narrow the selection (bbox, country, datasets, variables, layer, profile_type) or request an export (POST /exports).", ',
        '"max_observations": 1000000, "observation_count": 1000001, "observation_count_exact": false, ',
        '"exports_url": "/api/v1/exports"}}'
      )),
      load_limit_export = json(422, paste0(
        '{"detail": {"code": "load_limit_exceeded", "channel": "export", ',
        '"message": "The selection holds 12,000,000 observations, above the limit of exports (10,000,000): split it into several exports (bbox, country, datasets, variables, layer, profile_type).", ',
        '"max_observations": 10000000, "observation_count": 12000000, "observation_count_exact": true}}'
      )),
      server = res$set_status(500)$set_type("text/plain")$send("Internal Server Error"),
      bad_request = json(400, '{"detail": "bad request"}'),
      invalid_json = res$set_status(200)$set_type("application/json")$send("{not json"),
      empty = res$set_status(204)$send(""),
      res$set_status(500)$send_json(list(detail = "unknown kind"), auto_unbox = TRUE)
    )
  }),
  # 401 unless the token is "fresh".
  list(method = "get", path = "/api/v1/protected", handler = function(req, res) {
    if (identical(req$get_header("Authorization"), "Bearer fresh")) {
      return(res$send_json(list(ok = TRUE), auto_unbox = TRUE))
    }
    res$set_status(401)$send_json(list(detail = "Invalid authentication token"), auto_unbox = TRUE)
  }),
  list(method = "get", path = "/api/v1/slow", handler = function(req, res) {
    Sys.sleep(1.5)
    res$send_json(list(ok = TRUE), auto_unbox = TRUE)
  })
)

server <- fake_api(http_routes)

test_that("a request sends the standard headers and returns the parsed body", {
  soil <- test_session(server)
  out <- soil_request(soil, "GET", "/echo")
  expect_identical(toupper(out$method), "GET")
  expect_identical(out$accept, "application/json")
  expect_match(out$user_agent, "^soilhub/[0-9.]+ R/[0-9.]+ httr2/[0-9.]+$")
  expect_match(out$request_id, request_id_pattern)
  expect_identical(attr(out, "request_id"), out$request_id)
  expect_identical(attr(out, "status"), 200L)
  expect_null(out$authorization)
})

test_that("JSON bodies keep nulls, digits and length-one arrays; query vectors repeat", {
  soil <- test_session(server)
  body <- list(datasets = I("wosis_points"), bbox = c(-123.3, 49.1, -122.9, 49.4),
               country = NULL, value = 0.123456789012, flag = NA)
  out <- soil_request(soil, "POST", "/echo", body = body,
                      query = list(a = c("x", "y"), b = NULL, c = 1))
  expect_identical(out$body$datasets, list("wosis_points"))
  expect_equal(unlist(out$body$bbox), c(-123.3, 49.1, -122.9, 49.4))
  expect_null(out$body$country)
  expect_true("country" %in% names(out$body))
  expect_identical(out$body$value, 0.123456789012)
  expect_null(out$body$flag)
  expect_identical(out$query, "a=x&a=y&c=1")
})

test_that("an empty body returns NULL; invalid JSON is an api error", {
  soil <- test_session(server)
  expect_null(soil_request(soil, "GET", "/error/empty"))
  e <- expect_error(soil_request(soil, "GET", "/error/invalid_json"), class = "soilhub_api_error")
  expect_identical(e$code, "invalid_json")
  expect_identical(e$status, 200L)
})

test_that("the client request id is sent, echoed and kept across retries", {
  sleeps <- local_fake_sleep()
  soil <- test_session(server)
  out <- soil_request(soil, "GET", "/flaky/ids/503/2")
  expect_identical(out$attempts, 3L)
  seen <- unlist(soil_request(soil, "GET", "/seen/ids")$ids)
  expect_length(seen, 3L)
  expect_match(seen[1], request_id_pattern)
  expect_identical(unique(seen), seen[1])
  expect_identical(attr(out, "request_id"), seen[1])
  # a new request gets a new id
  other <- soil_request(soil, "GET", "/echo")
  expect_false(identical(other$request_id, seen[1]))
})

test_that("transient statuses are retried with 1 s x attempt backoff", {
  sleeps <- local_fake_sleep()
  soil <- test_session(server)
  for (status in c(429, 502, 503, 504)) {
    sleeps$waits <- numeric()
    out <- soil_request(soil, "GET", sprintf("/flaky/backoff%d/%d/2", status, status))
    expect_true(out$ok)
    expect_identical(out$attempts, 3L)
    expect_identical(sleeps$waits, c(1, 2))
  }
})

test_that("Retry-After is honoured in seconds and as an HTTP date, capped at 10 s", {
  sleeps <- local_fake_sleep()
  soil <- test_session(server)
  out <- soil_request(soil, "GET", "/flaky/after3/429/1?after=3")
  expect_true(out$ok)
  expect_identical(sleeps$waits, 3)

  sleeps$waits <- numeric()
  soil_request(soil, "GET", "/flaky/after60/503/2?after=60")
  expect_identical(sleeps$waits, c(10, 10))

  sleeps$waits <- numeric()
  date <- format(Sys.time() + 5, "%a, %d %b %Y %H:%M:%S GMT", tz = "GMT")
  soil_request(soil, "GET", "/flaky/afterdate/503/1",
               query = list(after = date))
  expect_length(sleeps$waits, 1L)
  expect_true(sleeps$waits > 2 && sleeps$waits <= 5)
})

test_that("Retry-After parsing", {
  expect_identical(parse_retry_after("7"), 7)
  expect_identical(parse_retry_after(" 2.5 "), 2.5)
  expect_true(is.na(parse_retry_after("soon")))
  expect_true(is.na(parse_retry_after(NULL)))
  expect_identical(retry_wait(NULL, 2L), 2)
  expect_identical(retry_wait(NULL, 30L), 10)
})

test_that("retries stop after 3 tries: 503 is unavailable, 502 an api error", {
  sleeps <- local_fake_sleep()
  soil <- test_session(server)
  e <- expect_error(soil_request(soil, "GET", "/flaky/down503/503/99"),
                    class = "soilhub_unavailable_error")
  expect_s3_class(e, "soilhub_api_error")
  expect_s3_class(e, "soilhub_error")
  expect_identical(e$attempts, 3L)
  expect_identical(e$status, 503L)
  expect_identical(sleeps$waits, c(1, 2))
  expect_match(conditionMessage(e), "Database unavailable \\(after 3 attempts\\)")

  e <- expect_error(soil_request(soil, "GET", "/flaky/down502/502/99"),
                    class = "soilhub_api_error")
  expect_false(inherits(e, "soilhub_unavailable_error"))
  expect_identical(e$status, 502L)
  expect_identical(e$attempts, 3L)
})

test_that("retry = FALSE (uploads) makes a single attempt", {
  sleeps <- local_fake_sleep()
  soil <- test_session(server)
  e <- expect_error(soil_request(soil, "GET", "/flaky/upload/503/1", retry = FALSE),
                    class = "soilhub_unavailable_error")
  expect_identical(e$attempts, 1L)
  expect_length(sleeps$waits, 0L)
  expect_length(unlist(soil_request(soil, "GET", "/seen/upload")$ids), 1L)
})

test_that("validation and server errors are not retried", {
  sleeps <- local_fake_sleep()
  soil <- test_session(server)
  e <- expect_error(soil_request(soil, "GET", "/flaky/v422/422/1"),
                    class = "soilhub_validation_error")
  expect_identical(e$attempts, 1L)
  e <- expect_error(soil_request(soil, "GET", "/flaky/v500/500/1"),
                    class = "soilhub_api_error")
  expect_identical(e$attempts, 1L)
  expect_length(sleeps$waits, 0L)
})

test_that("a transport failure is retried, then unavailable", {
  sleeps <- local_fake_sleep()
  soil <- list(api_url = "http://127.0.0.1:9/api/v1", timeout = 5, verbose = 0)
  e <- expect_error(soil_request(soil, "GET", "/health"),
                    class = "soilhub_unavailable_error")
  expect_identical(e$code, "transport_error")
  expect_identical(e$attempts, 3L)
  expect_null(e$status)
  expect_match(e$request_id, request_id_pattern)
  expect_identical(sleeps$waits, c(1, 2))
  expect_match(conditionMessage(e), "could not be reached after 3 attempt")
})

test_that("the total timeout applies per request", {
  sleeps <- local_fake_sleep()
  slow <- fake_api(http_routes)
  soil <- test_session(slow, timeout = 0.3)
  e <- expect_error(soil_request(soil, "GET", "/slow", retry = FALSE),
                    class = "soilhub_unavailable_error")
  expect_identical(e$code, "transport_error")
  expect_match(conditionMessage(e), "[Tt]imeout|timed out")
})

test_that("404, 409, 403, 400 and 500 map to their classes with safe fields", {
  soil <- test_session(server, identity = list(rights = c("soil:summary")))
  e <- expect_error(soil_request(soil, "GET", "/error/not_found"), class = "soilhub_not_found_error")
  expect_s3_class(e, "soilhub_api_error")
  expect_identical(e$status, 404L)
  expect_identical(e$endpoint, "/error/not_found")
  expect_identical(e$method, "GET")
  expect_identical(e$detail, "Dataset not found")
  expect_match(e$request_id, request_id_pattern)
  expect_match(conditionMessage(e), "Dataset not found")
  expect_match(conditionMessage(e), "HTTP 404, GET /error/not_found, request id soilhub-", fixed = TRUE)

  e <- expect_error(soil_request(soil, "POST", "/error/conflict", body = list(a = 1)),
                    class = "soilhub_conflict_error")
  expect_identical(e$status, 409L)

  e <- expect_error(soil_request(soil, "GET", "/error/forbidden"), class = "soilhub_permission_error")
  expect_false(inherits(e, "soilhub_api_error"))
  expect_identical(e$status, 403L)
  expect_identical(e$rights, "soil:summary")
  expect_null(e$required_right)
  expect_match(conditionMessage(e), "Permission denied: Missing required scope")

  e <- expect_error(soil_request(soil, "GET", "/error/bad_request"), class = "soilhub_api_error")
  expect_identical(class(e)[1], "soilhub_api_error")
  expect_identical(e$status, 400L)

  e <- expect_error(soil_request(soil, "GET", "/error/server"), class = "soilhub_api_error")
  expect_identical(e$status, 500L)
  expect_identical(e$detail, "Internal Server Error")
})

test_that("422 with a string detail is a validation error", {
  soil <- test_session(server)
  e <- expect_error(soil_request(soil, "POST", "/error/validation", body = list(datasets = I("nope"))),
                    class = "soilhub_validation_error")
  expect_s3_class(e, "soilhub_api_error")
  expect_identical(e$errors, data.frame(message = "Unknown dataset(s): nope"))
  expect_match(conditionMessage(e), "Unknown dataset\\(s\\): nope")
})

test_that("422 {message, errors} (publications) gives an errors data frame", {
  soil <- test_session(server)
  e <- expect_error(soil_request(soil, "POST", "/error/publication", body = list()),
                    class = "soilhub_validation_error")
  expect_identical(e$detail$message, "publication validation failed")
  expect_s3_class(e$errors, "data.frame")
  expect_identical(nrow(e$errors), 3L)
  expect_identical(e$errors$variable_code, c("ORGC", "CLAY", NA))
  expect_identical(e$errors$errors[2], "target_not_found, invalid_depth_interval")
  expect_identical(e$errors$code[3], "run_not_open")
  expect_match(conditionMessage(e), "publication validation failed")
  expect_match(conditionMessage(e), "variable_code CLAY", fixed = TRUE)

  # the same shape without the `detail` wrapper
  e <- expect_error(soil_request(soil, "POST", "/error/bare", body = list()),
                    class = "soilhub_validation_error")
  expect_identical(e$errors$field, "crs")
  expect_match(conditionMessage(e), "manifest invalid")
})

test_that("422 FastAPI request validation lists the fields", {
  soil <- test_session(server)
  e <- expect_error(soil_request(soil, "POST", "/error/fastapi", body = list(limit = 0)),
                    class = "soilhub_validation_error")
  expect_identical(e$errors$loc, c("body.datasets", "body.limit"))
  expect_identical(e$errors$msg[1], "Field required")
  expect_match(conditionMessage(e), "Invalid request: body.datasets: Field required; body.limit:")
})

test_that("422 load_limit_exceeded is a load-limit error with the export way out", {
  soil <- test_session(server)
  body <- list(datasets = I("wosis_points"), country = "BRA", layer = "all",
               view = "raw", layout = "wide", canonical = TRUE)
  e <- expect_error(soil_request(soil, "POST", "/error/load_limit", body = body),
                    class = "soilhub_load_limit_error")
  expect_s3_class(e, "soilhub_api_error")
  expect_false(inherits(e, "soilhub_validation_error"))
  expect_identical(e$status, 422L)
  expect_identical(e$code, "load_limit_exceeded")
  expect_identical(e$channel, "sync")
  expect_identical(e$max_observations, 1000000L)
  expect_identical(e$observation_count, 1000001L)
  expect_false(e$observation_count_exact)
  expect_identical(e$exports_url, "/api/v1/exports")
  expect_identical(e$request, body)
  expect_identical(names(e$selection), c("datasets", "country", "layer", "view"))
  msg <- conditionMessage(e)
  expect_match(msg, "^The selection holds more than 1,000,000 observations")
  expect_match(msg, paste0(
    "To export the same selection: soil_export(soil, datasets = \"wosis_points\", ",
    "country = \"BRA\", layer = \"all\", view = \"raw\", format = \"gpkg\")\n",
    "or rerun with too_large = \"export\"."
  ), fixed = TRUE)

  e <- expect_error(soil_request(soil, "POST", "/error/load_limit_export", body = body),
                    class = "soilhub_load_limit_error")
  expect_identical(e$channel, "export")
  expect_null(e$exports_url)
  expect_true(e$observation_count_exact)
  expect_no_match(conditionMessage(e), "soil_export")
  expect_match(conditionMessage(e), "split it into several exports")
})

test_that("the export hint deparses vectors", {
  hint <- export_hint(list(datasets = c("wosis_points", "wise_profiles"),
                           bbox = c(-10, 35, 5, 44)))
  expect_match(hint, "datasets = c(\"wosis_points\", \"wise_profiles\"), bbox = c(-10, 35, 5, 44), format = \"gpkg\"", fixed = TRUE)
})

test_that("401 without a session is not_logged_in", {
  soil <- test_session(server)
  e <- expect_error(soil_request(soil, "GET", "/error/unauthorized"), class = "soilhub_auth_error")
  expect_identical(e$reason, "not_logged_in")
  expect_identical(e$status, 401L)
  expect_match(conditionMessage(e), "soil_login(soil)", fixed = TRUE)
})

test_that("the auth seam sends the bearer token and renews once on 401", {
  calls <- new.env()
  calls$renew <- logical()
  auth <- function(soil, renew = FALSE) {
    calls$renew <- c(calls$renew, renew)
    if (renew) "fresh" else "stale"
  }
  soil <- test_session(server, auth = auth)
  out <- soil_request(soil, "GET", "/protected")
  expect_true(out$ok)
  expect_identical(calls$renew, c(FALSE, TRUE))

  # the token is sent as a bearer header
  echo <- soil_request(soil, "GET", "/echo")
  expect_identical(echo$authorization, "Bearer stale")

  # still refused after the renewal: session_expired, one renewal only
  calls$renew <- logical()
  soil$auth <- function(soil, renew = FALSE) {
    calls$renew <- c(calls$renew, renew)
    "revoked"
  }
  e <- expect_error(soil_request(soil, "GET", "/protected"), class = "soilhub_auth_error")
  expect_identical(e$reason, "session_expired")
  expect_identical(calls$renew, c(FALSE, TRUE))
  expect_no_match(conditionMessage(e), "revoked")
  expect_null(e$token)
})

test_that("verbosity 2 logs one line per attempt, never the token; 0 is silent", {
  sleeps <- local_fake_sleep()
  soil <- test_session(server, verbose = 2, auth = function(soil, renew = FALSE) "secret-token")
  msgs <- testthat::capture_messages(soil_request(soil, "GET", "/flaky/log/503/1"))
  lines <- grep("-> ", msgs, value = TRUE)
  expect_length(lines, 2L)
  expect_match(lines[1], "^soilhub: GET /flaky/log/503/1 -> 503 \\([0-9]+ ms, soilhub-[0-9]{14}-[0-9a-f]{8}\\)")
  expect_match(lines[2], "-> 200")
  expect_true(any(grepl("retrying in 1 s \\(attempt 2 of 3\\)", msgs)))
  expect_false(any(grepl("secret-token", msgs)))

  soil$verbose <- 1
  msgs <- testthat::capture_messages(soil_request(soil, "GET", "/flaky/log1/503/1"))
  expect_length(grep("-> ", msgs), 0L)
  expect_length(grep("retrying", msgs), 1L)

  soil$verbose <- 0
  expect_no_message(soil_request(soil, "GET", "/flaky/log0/503/1"))
})

test_that("messages have class soilhub_message", {
  soil <- test_session(server, verbose = 2)
  expect_message(soil_request(soil, "GET", "/echo"), class = "soilhub_message")
  expect_no_message(suppressMessages(soil_request(soil, "GET", "/echo")))
})

test_that("the print method shows the safe fields", {
  soil <- test_session(server)
  e <- tryCatch(soil_request(soil, "GET", "/error/not_found"), soilhub_error = function(e) e)
  out <- capture.output(print(e))
  expect_identical(out[1], "<soilhub_not_found_error>")
  expect_true(any(grepl("^  status: 404$", out)))
  expect_true(any(grepl("^  request_id: soilhub-", out)))
})
