# Replay of recorded API responses (design 7.1, 7.2; WP10, WP11). Internal.
#
# `tools/record_fixtures.R` records, for a curated list of read calls of the
# client, every request sent to the API and its response
# (tests/testthat/fixtures/recorded/: one file per response and a
# `manifest.json`). `replay_app()` builds a local web server (webfakes, a
# Suggests) that answers each recorded request with its recorded response;
# `replay_session()` starts it and returns a session pointed at it, with no
# login. Two users: the contract suite (tests/contract/test-recorded.R), which
# replays every recorded call through the client, and the vignettes, whose
# examples are evaluated against the replay so that they show real outputs of
# the API without network or Keycloak at build time.

# The directory of the recorded fixtures, found from a package source tree:
# `start` and its parents are searched for tests/testthat/fixtures/recorded.
# NULL when not found.
replay_dir <- function(start = getwd()) {
  dir <- normalizePath(start, mustWork = FALSE)
  repeat {
    candidate <- file.path(dir, "tests", "testthat", "fixtures", "recorded")
    if (file.exists(file.path(candidate, "manifest.json"))) return(candidate)
    parent <- dirname(dir)
    if (identical(parent, dir)) return(NULL)
    dir <- parent
  }
}

# A webfakes app answering the requests of `manifest.json` in `dir` (method,
# path below the API prefix, query string, JSON body as sent). The same
# request recorded several times (the polls of a job) is answered in the
# recorded order, the last answer repeated. An unrecorded request gets HTTP
# 501 naming it.
replay_app <- function(dir) {
  if (!requireNamespace("webfakes", quietly = TRUE)) {
    abort(soilhub_dependency_error("The replay of recorded responses needs the package webfakes.", "webfakes"))
  }
  manifest <- jsonlite::fromJSON(file.path(dir, "manifest.json"), simplifyVector = FALSE)
  entries <- list()
  for (call in manifest$calls) {
    for (x in call$exchanges) {
      file <- file.path(dir, x$file)
      entries[[length(entries) + 1L]] <- list(
        key = paste(x$method, paste0(openapi_prefix(), x$path), sub("^\\?", "", query_string(x$query)), x$body %||% ""),
        status = as.integer(x$status),
        type = if (grepl("\\.json$", x$file)) "application/json" else if (grepl("\\.zip$", x$file)) "application/zip" else "text/plain",
        body = if (!file.exists(file)) {
          ""
        } else if (grepl("\\.zip$", x$file)) {
          readBin(file, "raw", file.size(file))
        } else {
          paste(readLines(file, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
        }
      )
    }
  }
  app <- webfakes::new_app()
  app$locals$entries <- entries
  app$locals$served <- list()
  app$all(webfakes::new_regexp("^/"), function(req, res) {
    body <- if (is.raw(req$.body) && length(req$.body)) rawToChar(req$.body) else ""
    key <- paste(toupper(req$method), req$path, req$query_string %||% "", body)
    matches <- Filter(function(entry) identical(entry$key, key), req$app$locals$entries)
    if (length(matches)) {
      served <- req$app$locals$served
      n <- (served[[key]] %||% 0L) + 1L
      served[[key]] <- n
      req$app$locals$served <- served
      entry <- matches[[min(n, length(matches))]]
      res$set_status(entry$status)
      res$set_type(entry$type)
      return(res$send(entry$body))
    }
    res$set_status(501L)$send_json(list(detail = paste("no recorded response for", key)), auto_unbox = TRUE)
  })
  app
}

# A session on a replay of the recordings in `dir`: no login, the recorded
# capabilities cached, verbosity off, registered as the default session when
# `set_default`. The server process lives as long as the session (it is kept
# in the session state) and is stopped by `replay_stop()`.
replay_session <- function(dir = replay_dir(), set_default = TRUE) {
  if (is.null(dir) || !file.exists(file.path(dir, "manifest.json"))) {
    abort(soilhub_argument_error("No recorded fixtures (manifest.json) found.", "dir"))
  }
  server <- webfakes::new_app_process(replay_app(dir))
  soil <- new_soil_session(soil_config(api_url = server$url(openapi_prefix()), timeout = 60, verbose = 0))
  capabilities <- file.path(dir, "capabilities-1.json")
  if (file.exists(capabilities)) {
    soil$state$capabilities <- jsonlite::fromJSON(capabilities, simplifyVector = FALSE)
  }
  soil$state$replay <- server
  if (isTRUE(set_default)) soil_session(soil)
  soil
}

replay_stop <- function(soil) {
  server <- if (is.environment(soil$state)) soil$state$replay else NULL
  if (!is.null(server)) server$stop()
  if (identical(getOption("soilhub.session"), soil)) options(soilhub.session = NULL)
  invisible(NULL)
}
