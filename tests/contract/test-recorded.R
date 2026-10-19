# The recorded responses of the API (tools/record_fixtures.R, design 7.1,
# 7.2) replayed through the client: every recorded call is run again against
# a local server that answers each request with its recorded response, and
# must end as it did against the API (a result, or the same error class)
# without a `soilhub_contract_warning`. This covers what the OpenAPI cannot
# describe: `metadata`, the wide rows and long observations, the features.

recorded_dir <- function() file.path(contract_root(), "tests", "testthat", "fixtures", "recorded")

recorded_manifest <- function() {
  path <- file.path(recorded_dir(), "manifest.json")
  if (!file.exists(path)) {
    testthat::skip(paste(
      "No recorded fixtures yet (tests/testthat/fixtures/recorded/manifest.json):",
      "the owner runs `Rscript tools/record_fixtures.R` (device login) once"
    ))
  }
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

# A local server answering the recorded requests (method, path, query, body);
# an unrecorded request gets HTTP 501 naming it.
replay_api <- function(manifest, .local_envir = parent.frame()) {
  testthat::skip_if_not_installed("webfakes")
  entries <- list()
  for (call in manifest$calls) {
    for (x in call$exchanges) {
      file <- file.path(recorded_dir(), x$file)
      entries[[length(entries) + 1L]] <- list(
        key = paste(x$method, paste0(openapi_prefix(), x$path), sub("^\\?", "", query_string(x$query)), x$body %||% ""),
        status = as.integer(x$status),
        json = grepl("\\.json$", x$file),
        text = if (file.exists(file)) paste(readLines(file, warn = FALSE), collapse = "\n") else ""
      )
    }
  }
  app <- webfakes::new_app()
  app$locals$entries <- entries
  app$all(webfakes::new_regexp("^/"), function(req, res) {
    body <- if (is.raw(req$.body) && length(req$.body)) rawToChar(req$.body) else ""
    key <- paste(toupper(req$method), req$path, req$query_string %||% "", body)
    for (entry in req$app$locals$entries) {
      if (identical(entry$key, key)) {
        res$set_status(entry$status)
        if (entry$json) res$set_type("application/json")
        return(res$send(entry$text))
      }
    }
    res$set_status(501L)$send_json(list(detail = paste("no recorded response for", key)), auto_unbox = TRUE)
  })
  webfakes::local_app_process(app, .local_envir = .local_envir)
}

local({
  manifest <- tryCatch(
    jsonlite::fromJSON(file.path(recorded_dir(), "manifest.json"), simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (is.null(manifest)) {
    test_that("the recorded fixtures replay through the client", {
      recorded_manifest()
    })
    return(invisible())
  }
  caps_path <- file.path(contract_root(), "tests", "contract", "capabilities.json")
  server <- NULL
  for (call in manifest$calls) {
    test_that(sprintf("recorded call %s replays (%s)", call$name, call$outcome), {
      if (is.null(server)) server <<- replay_api(manifest, .local_envir = teardown_env())
      soil <- new_soil_session(soil_config(api_url = server$url("/api/v1"), timeout = 30, verbose = 0))
      if (file.exists(caps_path) && !identical(call$session, "anonymous")) {
        soil$state$capabilities <- jsonlite::fromJSON(caps_path, simplifyVector = FALSE)
      }
      soilhub_env$shown <- character()
      drift <- character()
      env <- new.env(parent = asNamespace("soilhub"))
      env$soil <- soil
      outcome <- withCallingHandlers(
        tryCatch({
          eval(parse(text = call$call)[[1]], envir = env)
          "ok"
        }, error = function(e) e),
        soilhub_contract_warning = function(w) {
          drift <<- c(drift, conditionMessage(w))
          invokeRestart("muffleWarning")
        },
        warning = function(w) invokeRestart("muffleWarning")
      )
      problems <- drift
      if (identical(call$outcome, "ok") && !identical(outcome, "ok")) {
        problems <- c(problems, sprintf("%s failed on the replay: %s", call$call, conditionMessage(outcome)))
      } else if (!identical(call$outcome, "ok") && !inherits(outcome, call$outcome)) {
        problems <- c(problems, sprintf(
          "%s ended with %s against the API, %s on the replay", call$call, call$outcome,
          if (identical(outcome, "ok")) "a result" else paste(class(outcome)[1], conditionMessage(outcome))
        ))
      }
      expect_no_drift(problems, sprintf("Recorded call %s", call$name))
    })
  }
})
