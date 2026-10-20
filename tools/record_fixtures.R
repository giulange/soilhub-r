# Record and scrub API fixtures (design 7.1, 7.2), WP10.
#
# Run by the owner, from the package root, once per API release, with an
# account that has `soil:summary` and `soil:read` (device login in the
# browser: no secret is stored, nothing is written to the API):
#
#   Rscript tools/record_fixtures.R                 # read calls only
#   Rscript tools/record_fixtures.R --with-export   # plus one small export
#
# `--with-export` (or SOILHUB_RECORD_EXPORT=true) adds one export round trip
# (a CSV of WoSIS in a small bbox around Vancouver: submit, poll, download
# the zip). It is off by default: an export is a job written to the API's
# job table under the user's name, although no soil data is changed.
#
# (or `source("tools/record_fixtures.R")` in an R session at the root). Needs
# pkgload. SOILHUB_API_URL / SOILHUB_KEYCLOAK_URL select another deployment.
#
# What it does: signs in with soil_connect(), then runs a curated list of
# read calls of the client (`recordings` below; small pages: `max_rows = 5`)
# with the `soilhub.exchange_hook` option (R/http.R), which hands over every
# request and response. It writes
#
#   tests/contract/capabilities.json                 GET /capabilities
#   tests/testthat/fixtures/recorded/<call>-<n>.json the responses, one per request
#   tests/testthat/fixtures/recorded/manifest.json   per call: the R call, its
#                                                    outcome, and per request the
#                                                    method, path, query, JSON body,
#                                                    status and response file
#
# Scrubbing (scrub_json(), R/contract.R): the values of personal keys (`sub`,
# `preferred_username`, `email`, names, `created_by`, ...), of token keys, of
# request-scoped ids (`request_id`, `correlation_id`, ...) and of request
# times (`retrieved_at`, `generated_at`, ...) are replaced; then every
# occurrence of the signed-in user's subject, user name, e-mail and names and
# of the tokens, of any JWT and of client request ids inside strings. A final
# check reads every written file back and stops (deleting the recording)
# when one of those values is still present.
#
# The contract suite replays the recording (tests/contract/test-recorded.R):
# each call is run again against a local server that answers with the
# recorded responses, and must end the same way without a
# `soilhub_contract_warning` (a field the client does not know or misses).
# Review the diff of the recorded files before committing them.

if (!file.exists("DESCRIPTION") || !dir.exists(file.path("tests", "contract"))) {
  stop("Run tools/record_fixtures.R from the root of the soilhub package.", call. = FALSE)
}
suppressMessages(pkgload::load_all(".", helpers = FALSE, quiet = TRUE))
with_export <- "--with-export" %in% commandArgs(trailingOnly = TRUE) ||
  identical(tolower(Sys.getenv("SOILHUB_RECORD_EXPORT")), "true")

out_dir <- file.path("tests", "testthat", "fixtures", "recorded")
capabilities_file <- file.path("tests", "contract", "capabilities.json")

exchanges <- new.env(parent = emptyenv())
exchanges$items <- list()
old_hook <- options(soilhub.exchange_hook = function(exchange) {
  if (!is.null(exchange$download)) {
    # the streamed file exists only while the hook runs: keep a copy
    copy <- tempfile("soilhub-download-", fileext = ".zip")
    file.copy(exchange$download, copy)
    exchange$download <- copy
  }
  exchanges$items[[length(exchanges$items) + 1L]] <- exchange
})

# --- Login ------------------------------------------------------------------

soil <- soil_connect(set_default = FALSE)
anonymous <- soil_connect(login = FALSE, set_default = FALSE)
anonymous$state$capabilities <- NULL
connect_exchanges <- exchanges$items

payload <- jwt_payload(soil$state$access_token) %||% list()
secret_claims <- c("sub", "preferred_username", "email", "name", "given_name",
                   "family_name", "sid", "session_state")
secrets <- c(
  unlist(lapply(payload[intersect(secret_claims, names(payload))], function(v) if (is_string(v)) v)),
  soil$state$access_token, soil$state$refresh_token
)
secrets <- unique(as.character(secrets[nzchar(secrets)]))

# --- Calls ------------------------------------------------------------------

catalog <- soil_datasets(soil)
pick <- function(pattern) {
  hit <- grep(pattern, catalog$name, value = TRUE)
  if (length(hit)) hit[1] else NA_character_
}
wosis <- pick("^wosis")
wise <- pick("^wise")
soter <- pick("^soter")
sotwis <- pick("^sotwis_polygons$")
code_list <- tryCatch(soil_code_lists(soil)$code_list[1], error = function(e) NA_character_)
country <- "KEN"

# name, R call (evaluated with `soil`), and the datasets it needs (skipped
# when the catalog lacks one). `session = "anonymous"` runs signed out.
call_of <- function(name, call, needs = character(), session = "user") {
  list(name = name, call = call, needs = needs, session = session)
}
q <- function(x) deparse(x)
# Small areas keep every selection below the synchronous load limit: WoSIS around
# Vancouver, SOTWIS polygons near Tunis (the whole datasets answer 422, recorded once by
# "unfiltered-observations").
bb_wosis <- "bbox = c(-123.3, 49.0, -122.9, 49.4)"
bb_sotwis <- "bbox = c(10.0, 36.5, 10.5, 37.0)"
recordings <- list(
  call_of("capabilities", "soil_capabilities(soil, refresh = TRUE)"),
  call_of("api-info", "soil_api_info(soil)"),
  call_of("unauthorized", "soil_capabilities(soil, refresh = TRUE)", session = "anonymous"),
  call_of("datasets", "soil_datasets(soil)"),
  call_of("dataset", sprintf("soil_dataset(soil, %s)", q(wosis)), wosis),
  call_of("dataset-not-found", "soil_dataset(soil, \"no_such_dataset\")"),
  call_of("formats", "soil_formats(soil)"),
  call_of("variables", sprintf("soil_variables(soil, dataset = %s)", q(wosis)), wosis),
  call_of("countries", "soil_countries(soil)"),
  call_of("country", sprintf("soil_country(soil, %s)", q(country))),
  call_of("code-lists", "soil_code_lists(soil)"),
  call_of("code-list", sprintf("soil_code_list(soil, %s)", q(code_list)), code_list),
  call_of("ttr-flag-legend", "soil_ttr_flag_legend(soil)"),
  call_of("ttr-flags", "soil_ttr_flags(soil, max_rows = 5)"),
  call_of("wide-wosis", sprintf("soil_observations(soil, datasets = %s, %s, max_rows = 5, progress = FALSE)", q(wosis), bb_wosis), wosis),
  call_of("wide-wise", sprintf("soil_observations(soil, datasets = %s, max_rows = 5, progress = FALSE)", q(wise)), wise),
  call_of("wide-soter", sprintf("soil_observations(soil, datasets = %s, max_rows = 5, progress = FALSE)", q(soter)), soter),
  call_of("wide-sotwis", sprintf("soil_observations(soil, datasets = %s, %s, components = \"all\", max_rows = 5, progress = FALSE)", q(sotwis), bb_sotwis), sotwis),
  call_of("wide-revised", sprintf("soil_observations(soil, datasets = %s, %s, view = \"revised\", max_rows = 5, progress = FALSE)", q(wosis), bb_wosis), wosis),
  call_of("wide-first-layer", sprintf("soil_observations(soil, datasets = %s, %s, layer = \"first\", max_rows = 5, progress = FALSE)", q(wosis), bb_wosis), wosis),
  call_of("wide-geometry", sprintf("soil_observations(soil, datasets = %s, %s, with_geometry = \"text\", max_rows = 5, progress = FALSE)", q(wosis), bb_wosis), wosis),
  call_of("long-wosis", sprintf("soil_observations(soil, datasets = %s, %s, layout = \"long\", max_rows = 5, progress = FALSE)", q(wosis), bb_wosis), wosis),
  call_of("long-soter-revised", sprintf("soil_observations(soil, datasets = %s, layout = \"long\", view = \"revised\", max_rows = 5, progress = FALSE)", q(soter)), soter),
  call_of("unknown-dataset", "soil_observations(soil, datasets = \"no_such_dataset\", max_rows = 5, progress = FALSE)"),
  call_of("unfiltered-observations", "soil_observations(soil, max_rows = 5, progress = FALSE)"),
  call_of("features-points", sprintf("soil_features(soil, datasets = %s, %s, max_rows = 3, progress = FALSE)", q(wosis), bb_wosis), wosis),
  call_of("features-polygons", sprintf("soil_features(soil, datasets = %s, %s, max_rows = 3, progress = FALSE)", q(sotwis), bb_sotwis), sotwis),
  call_of("summary", sprintf("soil_summary(soil, datasets = %s, country = %s)", q(wosis), q(country)), wosis),
  call_of("availability", sprintf("soil_availability(soil, datasets = %s, country = %s)", q(wosis), q(country)), wosis),
  call_of("consistency", sprintf("soil_consistency(soil, country = %s)", q(country))),
  call_of("values", "soil_values(soil, max_rows = 5, progress = FALSE)"),
  call_of("values-summary", "soil_values_summary(soil)"),
  call_of("health-scores", "soil_health_scores(soil, max_rows = 5, progress = FALSE)"),
  call_of("health-summary", "soil_health_summary(soil)")
)
if (with_export) {
  recordings <- c(recordings, list(call_of(
    "export-csv",
    sprintf(paste0(
      "soil_export(soil, datasets = %s, bbox = c(-123.3, 49.0, -122.9, 49.4), ",
      "format = \"csv\", poll = 2, timeout = 600, dir = tempdir(), progress = FALSE)"
    ), q(wosis)),
    wosis
  )))
}

# --- Record -----------------------------------------------------------------

scrub_body <- function(text) {
  if (is.null(text) || !nzchar(text)) return(list(json = FALSE, text = ""))
  parsed <- tryCatch(jsonlite::fromJSON(text, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(parsed)) return(list(json = FALSE, text = scrub_text(text, secrets)))
  list(json = TRUE, value = scrub_json(parsed, secrets))
}
write_json_file <- function(value, path) {
  writeLines(as.character(jsonlite::toJSON(
    value, auto_unbox = TRUE, null = "null", na = "null", digits = NA, pretty = TRUE
  )), path, useBytes = TRUE)
}

unlink(out_dir, recursive = TRUE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
manifest <- list()
for (recording in recordings) {
  if (length(recording$needs) && anyNA(recording$needs)) {
    message("skipped ", recording$name, ": the catalog has no such dataset")
    next
  }
  exchanges$items <- list()
  session <- if (identical(recording$session, "anonymous")) anonymous else soil
  env <- new.env(parent = asNamespace("soilhub"))
  env$soil <- session
  outcome <- tryCatch({
    suppressWarnings(eval(parse(text = recording$call)[[1]], envir = env))
    "ok"
  }, error = function(e) class(e)[1])
  files <- list()
  for (i in seq_along(exchanges$items)) {
    exchange <- exchanges$items[[i]]
    if (!is.null(exchange$download)) {
      # a streamed download (the export zip): kept as is
      file <- sprintf("%s-%d.zip", recording$name, i)
      file.copy(exchange$download, file.path(out_dir, file), overwrite = TRUE)
    } else {
      response <- scrub_body(exchange$response)
      file <- if (response$json) sprintf("%s-%d.json", recording$name, i) else sprintf("%s-%d.txt", recording$name, i)
      if (response$json) {
        write_json_file(response$value, file.path(out_dir, file))
      } else {
        writeLines(response$text, file.path(out_dir, file), useBytes = TRUE)
      }
    }
    files[[i]] <- list(
      method = exchange$method, path = exchange$path,
      query = lapply(exchange$query, function(v) scrub_text(as.character(v), secrets)),
      body = if (is.null(exchange$body)) NULL else scrub_text(exchange$body, secrets),
      status = exchange$status, file = file
    )
  }
  manifest[[length(manifest) + 1L]] <- list(
    name = recording$name, call = recording$call, session = recording$session,
    outcome = outcome, exchanges = files
  )
  message(sprintf("%-26s %-28s %d request(s)", recording$name, outcome, length(files)))
}

capabilities <- Find(function(x) identical(x$path, "/capabilities") && identical(x$status, 200L), connect_exchanges)
if (is.null(capabilities)) stop("soil_connect() did not read GET /capabilities.", call. = FALSE)
caps <- scrub_body(capabilities$response)$value
write_json_file(caps, capabilities_file)
write_json_file(list(
  recorded_on = format(Sys.Date()),
  api_url = soil$api_url,
  api_version = caps$api_version,
  soilhub_version = client_version(),
  calls = manifest
), file.path(out_dir, "manifest.json"))

# --- Leak check ---------------------------------------------------------------

written <- c(grep("\\.zip$", list.files(out_dir, full.names = TRUE), value = TRUE, invert = TRUE),
             capabilities_file)
leaks <- character()
for (path in written) {
  found <- scrub_leaks(paste(readLines(path, warn = FALSE), collapse = "\n"), secrets)
  if (length(found)) leaks <- c(leaks, sprintf("%s: %d value(s)", path, length(found)))
}
options(old_hook)
if (length(leaks)) {
  unlink(out_dir, recursive = TRUE)
  unlink(capabilities_file)
  stop("Personal values or tokens survived the scrubbing; nothing was kept:\n",
       paste0("  ", leaks, collapse = "\n"), call. = FALSE)
}
soil_logout(soil)
message(sprintf(
  "Recorded %d call(s) in %s and %s (API %s). Review the diff, then run Rscript tests/contract/run.R.",
  length(manifest), out_dir, capabilities_file, caps$api_version
))
