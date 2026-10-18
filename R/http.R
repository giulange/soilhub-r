# HTTP layer (design 2.4): one function, `soil_request()`, sends a request to
# the API and returns the parsed body, or signals a `soilhub_error` (2.5).
#
# The session `soil` is a list (later a `soil_session`, WP2) with at least
# `api_url` and `timeout` (from `soil_config()`), optionally `verbose`,
# `identity` (rights, for 403 messages) and `auth`. A `soil_session` (WP2)
# keeps `identity` and `capabilities` in its `state` environment
# (`session_cached()`); its `auth` is `session_auth()` (auth-device.R).
#
# Authentication seam (WP2). When `soil$auth` is a function
# `function(soil, renew = FALSE)`, it is called before every attempt and
# returns the access token to send as `Authorization: Bearer <token>` (or
# NULL for an anonymous request). The function owns the proactive renewal
# (refresh when the token expires within 60 s, design 3.3) and the token
# store; `renew = TRUE` is passed once after a 401 to invalidate the token and
# refresh it (reactive renewal); the request is then repeated once. A refresh
# failure is signalled by the function itself as
# `soilhub_auth_error(reason = "session_expired" | "no_refresh_token")`. Without
# `soil$auth` requests are anonymous and a 401 is a `soilhub_auth_error` with
# `reason = "not_logged_in"`.

http_max_tries <- 3L
http_retry_after_cap <- 10
http_connect_timeout <- 10
http_transient_status <- c(429L, 502L, 503L, 504L)

#' Send a request to the API
#'
#' @param soil The session: a list with `api_url`, `timeout`, and optionally
#'   `verbose`, `identity` and the authentication hook `auth` (see the comment
#'   at the top of `http.R`).
#' @param method HTTP method.
#' @param path Path below `soil$api_url`, starting with `/`.
#' @param body A list sent as JSON (`auto_unbox = TRUE`; wrap a length-one
#'   array in [I()]), or `NULL`.
#' @param query A named list of query parameters (`NULL` elements dropped,
#'   vectors repeated).
#' @param timeout Total seconds allowed for the request; `NULL` uses
#'   `soil$timeout`, `Inf` none.
#' @param retry `FALSE` disables the retries (multipart uploads).
#' @param right The right the request needs (e.g. `"soil:admin"`), named in
#'   the `soilhub_permission_error` of a 403; `NULL` when not stated.
#' @return The parsed JSON body (`simplifyVector = FALSE`), `NULL` for an
#'   empty body, with the attributes `request_id` and `status`.
#' @keywords internal
#' @noRd
soil_request <- function(soil, method, path, body = NULL, query = NULL,
                         timeout = NULL, retry = TRUE, right = NULL) {
  method <- toupper(method)
  timeout <- check_timeout(timeout %||% soil$timeout %||% config_defaults$timeout)
  request_id <- new_request_id()
  context <- list(method = method, endpoint = path, request_id = request_id,
                  timeout = timeout,
                  right = if (is.null(right)) NULL else normalise_right(right))

  renewed <- FALSE
  repeat {
    token <- auth_token(soil, renew = renewed)
    req <- build_request(soil, method, path, body, query, timeout, token, request_id)
    outcome <- perform_with_retries(soil, req, context, max_tries = if (isTRUE(retry)) http_max_tries else 1L)
    if (!is.null(outcome$response) &&
        httr2::resp_status(outcome$response) == 401L &&
        !renewed && is.function(soil$auth) && !is.null(token)) {
      renewed <- TRUE
      soil_inform(soil, 1, "soilhub: access token refused (HTTP 401), renewing the session.")
      next
    }
    break
  }

  if (is.null(outcome$response)) {
    abort(transport_error(outcome, soil, context))
  }
  handle_response(soil, outcome$response, context, body, token, outcome$attempts)
}

# Authentication seam (see the top of this file).
auth_token <- function(soil, renew = FALSE) {
  hook <- soil$auth
  if (!is.function(hook)) return(NULL)
  hook(soil, renew = renew)
}

new_request_id <- function() {
  sprintf(
    "soilhub-%s-%s",
    format(Sys.time(), "%Y%m%d%H%M%S", tz = "UTC"),
    paste(as.character(openssl::rand_bytes(4)), collapse = "")
  )
}

user_agent <- function() {
  sprintf(
    "soilhub/%s R/%s httr2/%s",
    utils::packageVersion("soilhub"), getRversion(),
    utils::packageVersion("httr2")
  )
}

request_url <- function(soil, path) {
  if (!is_string(soil$api_url)) {
    abort(soilhub_argument_error("The session has no `api_url`.", "soil"))
  }
  if (!startsWith(path, "/")) path <- paste0("/", path)
  paste0(sub("/+$", "", soil$api_url), path)
}

# "?a=x&a=y&b=1" from a named list (NULL dropped, vectors repeated).
query_string <- function(query) {
  query <- Filter(Negate(is.null), query %||% list())
  if (length(query) == 0L) return("")
  pairs <- unlist(Map(function(name, value) {
    # element by element: format() of a vector pads its elements to a
    # common width ("clay" -> "clay      ")
    value <- if (is.logical(value)) {
      tolower(as.character(value))
    } else if (is.numeric(value)) {
      vapply(value, format, character(1), scientific = FALSE, trim = TRUE, digits = 15)
    } else {
      as.character(value)
    }
    paste0(curl::curl_escape(name), "=", curl::curl_escape(value))
  }, names(query), query), use.names = FALSE)
  paste0("?", paste(pairs, collapse = "&"))
}

request_body_json <- function(body) {
  jsonlite::toJSON(
    body,
    auto_unbox = TRUE, null = "null", na = "null", digits = NA
  )
}

build_request <- function(soil, method, path, body, query, timeout, token,
                          request_id) {
  req <- httr2::request(paste0(request_url(soil, path), query_string(query)))
  req <- httr2::req_method(req, method)
  req <- httr2::req_headers(
    req,
    Accept = "application/json",
    `X-Request-ID` = request_id
  )
  req <- httr2::req_user_agent(req, user_agent())
  if (!is.null(token)) {
    req <- httr2::req_headers(req, Authorization = paste("Bearer", token))
  }
  if (!is.null(body)) {
    req <- httr2::req_body_raw(req, request_body_json(body), type = "application/json")
  }
  if (is.finite(timeout)) req <- httr2::req_timeout(req, timeout)
  req <- httr2::req_options(req, connecttimeout = http_connect_timeout)
  # Every status is returned to `handle_response()`; retries are done by
  # `perform_with_retries()`, so httr2 neither retries nor reads Retry-After.
  req <- httr2::req_retry(req, max_tries = 1, is_transient = function(resp) FALSE)
  httr2::req_error(req, is_error = function(resp) FALSE)
}

# Perform `req` up to `max_tries` times; retry on a transport failure and on
# 429, 502, 503, 504. Returns list(response, failure, attempts).
perform_with_retries <- function(soil, req, context, max_tries) {
  attempt <- 0L
  repeat {
    attempt <- attempt + 1L
    started <- Sys.time()
    response <- NULL
    failure <- NULL
    result <- tryCatch(
      httr2::req_perform(req),
      httr2_failure = function(e) e,
      curl_error = function(e) e
    )
    if (inherits(result, "httr2_response")) response <- result else failure <- result
    elapsed <- round(as.numeric(difftime(Sys.time(), started, units = "secs")) * 1000)
    status <- if (is.null(response)) NULL else httr2::resp_status(response)
    log_request(soil, context, status, elapsed, response)

    # A request that reached the total timeout is a heavy query: it is not
    # repeated (connection timeouts, DNS and reset errors are).
    timed_out <- is_total_timeout(failure)
    transient <- if (is.null(response)) !timed_out else status %in% http_transient_status
    if (!transient || attempt >= max_tries) {
      return(list(response = response, failure = failure, attempts = attempt,
                  timed_out = timed_out))
    }
    wait <- retry_wait(response, attempt)
    soil_inform(soil, 1, sprintf(
      "soilhub: %s %s %s, retrying in %s s (attempt %d of %d).",
      context$method, context$endpoint,
      if (is.null(status)) "could not be reached" else paste("returned HTTP", status),
      format(wait), attempt + 1L, max_tries
    ))
    http_sleep(wait)
  }
}

log_request <- function(soil, context, status, elapsed_ms, response) {
  if (soil_verbosity(soil) < 2) return(invisible(NULL))
  echoed <- if (is.null(response)) NULL else httr2::resp_header(response, "x-request-id")
  soilhub_message(sprintf(
    "soilhub: %s %s -> %s (%s ms, %s)",
    context$method, context$endpoint,
    if (is.null(status)) "transport error" else status,
    format(elapsed_ms), echoed %||% context$request_id
  ))
}

# Seconds to wait before the next attempt: `Retry-After` (seconds or an HTTP
# date) capped at 10 s, else 1 s x attempt.
retry_wait <- function(response, attempt) {
  header <- if (is.null(response)) NULL else httr2::resp_header(response, "retry-after")
  wait <- parse_retry_after(header)
  if (is.na(wait)) wait <- attempt
  min(max(wait, 0), http_retry_after_cap)
}

parse_retry_after <- function(header) {
  if (is.null(header) || !nzchar(trimws(header))) return(NA_real_)
  header <- trimws(header)
  if (grepl("^[0-9]+(\\.[0-9]+)?$", header)) return(as.numeric(header))
  when <- suppressWarnings(as.POSIXct(
    strptime(header, "%a, %d %b %Y %H:%M:%S", tz = "GMT")
  ))
  if (is.na(when)) return(NA_real_)
  as.numeric(difftime(when, Sys.time(), units = "secs"))
}

# TRUE when a transport failure is the total request timeout (curl error 28
# "Operation timed out"), FALSE for a connection or DNS timeout ("Failed to
# connect", "Connection timed out", "Resolving timed out") and other failures.
is_total_timeout <- function(failure) {
  if (is.null(failure)) return(FALSE)
  cause <- failure$parent %||% failure
  inherits(cause, "curl_error_operation_timedout") &&
    !grepl("connect|resolv", conditionMessage(cause), ignore.case = TRUE)
}

transport_error <- function(outcome, soil, context) {
  cause <- outcome$failure
  reason <- if (!is.null(cause$parent)) conditionMessage(cause$parent) else conditionMessage(cause)
  reason <- sub("^\\s+", "", reason)
  if (isTRUE(outcome$timed_out)) {
    return(soilhub_api_error(
      paste0(
        sprintf(
          "The request did not complete within the timeout of %s s and was not repeated: ",
          format(context$timeout)
        ),
        "narrow the selection (bbox, country, datasets, variables, layer, profile_type), ",
        "request an export with soil_export(), or raise `timeout`.",
        request_suffix(NULL, context$method, context$endpoint, context$request_id)
      ),
      status = NULL, endpoint = context$endpoint, method = context$method,
      request_id = context$request_id, code = "timeout", reason = "timeout",
      attempts = outcome$attempts, subclass = "unavailable"
    ))
  }
  soilhub_api_error(
    paste0(
      sprintf(
        "The API at %s could not be reached after %d attempt(s): %s",
        soil$api_url, outcome$attempts, reason
      ),
      request_suffix(NULL, context$method, context$endpoint, context$request_id)
    ),
    status = NULL, endpoint = context$endpoint, method = context$method,
    request_id = context$request_id, code = "transport_error",
    reason = "transport_error", attempts = outcome$attempts,
    subclass = "unavailable"
  )
}

# Parse a response body as JSON; `NULL` for an empty body.
parse_body <- function(response) {
  if (!httr2::resp_has_body(response)) return(NULL)
  text <- httr2::resp_body_string(response)
  if (!nzchar(trimws(text))) return(NULL)
  jsonlite::fromJSON(text, simplifyVector = FALSE)
}

handle_response <- function(soil, response, context, body, token, attempts) {
  status <- httr2::resp_status(response)
  context$request_id <- httr2::resp_header(response, "x-request-id") %||% context$request_id
  if (status >= 200L && status < 300L) {
    parsed <- tryCatch(parse_body(response), error = function(e) e)
    if (inherits(parsed, "error")) {
      abort(soilhub_api_error(
        paste0(
          "The API returned a response that is not valid JSON.",
          request_suffix(status, context$method, context$endpoint, context$request_id)
        ),
        status = status, endpoint = context$endpoint, method = context$method,
        request_id = context$request_id, code = "invalid_json",
        attempts = attempts
      ))
    }
    if (!is.null(parsed)) {
      attr(parsed, "request_id") <- context$request_id
      attr(parsed, "status") <- status
    }
    return(parsed)
  }
  abort(response_error(soil, response, context, body, token, attempts))
}

# Map a non-2xx response to a condition (2.5).
response_error <- function(soil, response, context, body, token, attempts) {
  status <- httr2::resp_status(response)
  parsed <- tryCatch(parse_body(response), error = function(e) NULL)
  detail <- if (is.list(parsed) && "detail" %in% names(parsed)) {
    parsed$detail
  } else if (is.list(parsed) && !is.null(parsed$message)) {
    parsed # a bare `{message, errors}` body
  } else if (is.null(parsed) && httr2::resp_has_body(response)) {
    substr(httr2::resp_body_string(response), 1L, 500L)
  } else {
    parsed
  }
  text <- detail_message(detail) %||%
    paste0("HTTP ", status, " ", httr2::resp_status_desc(response) %||% "")
  suffix <- request_suffix(status, context$method, context$endpoint, context$request_id)
  code <- if (is.list(detail) && is.character(detail$code)) detail$code else NULL
  common <- list(
    status = status, endpoint = context$endpoint, method = context$method,
    request_id = context$request_id, attempts = attempts
  )

  if (status == 401L) {
    reason <- if (is.null(token)) "not_logged_in" else "session_expired"
    advice <- if (is.null(token)) {
      "This request needs a login: run `soil_login(soil)`."
    } else {
      "The API refused the access token after a renewal: run `soil_login(soil)` to sign in again."
    }
    return(do.call(soilhub_auth_error, c(
      list(message = paste0(advice, " (", text, ")", suffix), reason = reason,
           detail = detail),
      common
    )))
  }
  if (status == 403L) {
    rights <- tryCatch(session_rights(soil), error = function(e) NULL)
    needs <- if (is.null(context$right)) {
      ""
    } else if (is.null(rights)) {
      sprintf(" (this request needs the right `%s`)", context$right)
    } else {
      sprintf(
        " (this request needs the right `%s`; your session has %s)",
        context$right, format_rights(rights)
      )
    }
    return(soilhub_permission_error(
      paste0("Permission denied: ", text, needs, suffix),
      required_right = context$right, rights = rights, status = status,
      endpoint = context$endpoint, request_id = context$request_id,
      method = context$method, detail = detail
    ))
  }
  if (status == 422L && identical(code, "load_limit_exceeded")) {
    return(load_limit_error(
      detail, request = body, status = status, endpoint = context$endpoint,
      method = context$method, request_id = context$request_id,
      attempts = attempts
    ))
  }
  if (status == 422L) {
    errors <- validation_errors_frame(detail)
    return(do.call(soilhub_api_error, c(
      list(message = paste0(text, errors_summary(errors), suffix),
           detail = detail, code = code, errors = errors,
           subclass = "validation"),
      common
    )))
  }
  subclass <- switch(as.character(status),
    "404" = "not_found",
    "409" = "conflict",
    "503" = "unavailable",
    NULL
  )
  if (status %in% http_transient_status && attempts > 1L) {
    text <- sprintf("%s (after %d attempts)", text, attempts)
  }
  do.call(soilhub_api_error, c(
    list(message = paste0(text, suffix), detail = detail, code = code,
         subclass = subclass),
    common
  ))
}
