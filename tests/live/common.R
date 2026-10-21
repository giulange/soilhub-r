# Shared code of the live acceptance scripts (design 7.3, 10; WP12).
#
# Sourced by smoke.R, exports.R, session-hours.R and write-acceptance.R. Not a
# test file: R CMD check never runs tests/live (excluded in .Rbuildignore).
#
# What it provides:
#   - options: `--name=value` / `--flag` arguments (also from the environment
#     variable SOILHUB_LIVE_ARGS, for runs started without a command line);
#   - loading of soilhub: the source tree (pkgload::load_all) when the
#     working directory is the package root, else the installed package
#     (`--installed` forces the installed package);
#   - a log under tests/live/logs/<script>-<UTC stamp>[-fake].log, every line
#     redacted: JWTs (access and refresh tokens) and the identity claims of
#     the signed-in users (user name, subject, e-mail, names) never reach it;
#   - checks with a verdict (PASS, FAIL, WARN, SKIP) and the final summary;
#   - `--fake` (alias `--dry-run`): local fake servers built from the unit-test
#     helpers (tests/testthat/helper-fake-*.R) instead of the API and
#     Keycloak, so the code of the scripts runs without any login or network.
#     Each fake serves one part of the API: `live_route(soil, kind)` points
#     the session at the server of that part (same tokens, same state); in a
#     live run it returns the session unchanged.

live <- new.env(parent = emptyenv())

production_api_url <- "https://soilhub.weatherprogapp.it/api/v1"

`%||%` <- function(x, y) if (is.null(x)) y else x

# ---------------------------------------------------------------------------
# Start, options, package.

live_init <- function(name, dir, defaults, usage) {
  live$name <- name
  live$dir <- dir
  live$checks <- list()
  live$secrets <- character()
  live$sessions <- list()
  live$servers <- list()
  live$usage <- usage
  opts <- live_parse_args(defaults, usage)
  live$opts <- opts
  live$fake <- isTRUE(opts$fake)
  live$loaded <- live_load_package(opts)
  live_open_log(name)
  live_log(sprintf("soilhub live acceptance: %s (%s run)", name, if (live$fake) "FAKE" else "LIVE"))
  live_log(sprintf("package: %s; %s; %s", live$loaded, R.version.string, R.version$platform))
  shown <- opts[setdiff(names(opts), "help")]
  live_log(sprintf("options: %s", paste(sprintf("%s=%s", names(shown), vapply(shown, function(v) paste(v, collapse = ","), "")), collapse = " ")))
  if (live$fake) {
    live_log("FAKE run: local fake servers built from the hand-made unit-test fixtures; no login, no network.")
    live_log("Outcomes test the code of this script, not the API: see tests/live/README.md.")
  }
  opts
}

live_parse_args <- function(defaults, usage) {
  args <- commandArgs(trailingOnly = TRUE)
  extra <- trimws(Sys.getenv("SOILHUB_LIVE_ARGS"))
  if (nzchar(extra)) args <- c(args, strsplit(extra, "[[:space:]]+")[[1]])
  common <- list(fake = FALSE, installed = FALSE, help = FALSE)
  defaults <- c(defaults, common[setdiff(names(common), names(defaults))])
  opts <- defaults
  for (arg in args) {
    if (!grepl("^--[A-Za-z]", arg)) live_usage_error(sprintf("unexpected argument `%s`", arg))
    body <- sub("^--", "", arg)
    key <- gsub("-", "_", sub("=.*$", "", body))
    if (identical(key, "dry_run")) key <- "fake"
    value <- if (grepl("=", body, fixed = TRUE)) sub("^[^=]*=", "", body) else NA_character_
    if (!key %in% names(defaults)) live_usage_error(sprintf("unknown option `--%s`", gsub("_", "-", key)))
    default <- defaults[[key]]
    opts[[key]] <- if (is.logical(default)) {
      is.na(value) || tolower(value) %in% c("true", "yes", "1")
    } else if (is.numeric(default)) {
      number <- suppressWarnings(as.numeric(value))
      if (is.na(number)) live_usage_error(sprintf("`--%s` needs a number", gsub("_", "-", key)))
      number
    } else {
      if (is.na(value)) live_usage_error(sprintf("`--%s` needs a value (`--%s=...`)", gsub("_", "-", key), gsub("_", "-", key)))
      value
    }
  }
  if (isTRUE(opts$help)) {
    cat(usage, sep = "\n")
    if (!interactive()) quit(save = "no", status = 0)
    stop("help shown", call. = FALSE)
  }
  opts
}

live_usage_error <- function(text) {
  cat("Error: ", text, "\n\n", sep = "")
  cat(live$usage, sep = "\n")
  if (!interactive()) quit(save = "no", status = 2)
  stop(text, call. = FALSE)
}

live_load_package <- function(opts) {
  source_tree <- file.exists("DESCRIPTION") &&
    identical(unname(read.dcf("DESCRIPTION", fields = "Package")[1, 1]), "soilhub")
  live$source_tree <- source_tree
  if (source_tree && !isTRUE(opts$installed)) {
    if (!requireNamespace("pkgload", quietly = TRUE)) {
      stop("Running from the source tree needs the package pkgload (or use --installed).", call. = FALSE)
    }
    suppressMessages(pkgload::load_all(".", export_all = FALSE, helpers = FALSE, quiet = TRUE))
    return(sprintf("soilhub %s from the source tree (pkgload::load_all)", utils::packageVersion("soilhub")))
  }
  suppressPackageStartupMessages(library(soilhub))
  sprintf("soilhub %s installed", utils::packageVersion("soilhub"))
}

# ---------------------------------------------------------------------------
# Log (redacted) and checks.

live_open_log <- function(name) {
  logs <- file.path(live$dir, "logs")
  dir.create(logs, showWarnings = FALSE, recursive = TRUE)
  live$stamp <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
  live$log <- file.path(logs, sprintf("%s-%s%s.log", name, live$stamp, if (live$fake) "-fake" else ""))
  file.create(live$log)
  live$started <- Sys.time()
}

live_redact <- function(text) {
  text <- gsub("eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]*", "<token>", text, perl = TRUE)
  for (secret in live$secrets) text <- gsub(secret, "<user>", text, fixed = TRUE)
  text
}

# One or more lines, timestamped (UTC), redacted, to the log and the console.
live_log <- function(text) {
  lines <- unlist(strsplit(paste(text, collapse = "\n"), "\n", fixed = TRUE))
  if (!length(lines)) lines <- ""
  stamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%SZ", tz = "UTC")
  lines <- live_redact(paste0(stamp, "  ", lines))
  cat(lines, sep = "\n", file = live$log, append = TRUE)
  cat(lines, sep = "\n")
  invisible(NULL)
}

live_logf <- function(fmt, ...) live_log(sprintf(fmt, ...))

# A table (data frame) in the log, indented.
live_log_table <- function(x, max_rows = 30L) {
  if (!is.data.frame(x) || !nrow(x)) return(invisible(NULL))
  x <- utils::head(as.data.frame(x), max_rows)
  for (name in names(x)) if (is.list(x[[name]])) x[[name]] <- vapply(x[[name]], function(v) paste(unlist(v), collapse = ","), "")
  old <- options(width = 250)
  on.exit(options(old), add = TRUE)
  live_log(paste0("      ", utils::capture.output(print(x, row.names = FALSE))))
}

# Verdicts of a check: `value` travels back to the caller of live_check().
verdict <- function(status, detail = "", value = NULL) list(status = status, detail = detail, value = value)
v_pass <- function(detail = "", value = NULL) verdict("PASS", detail, value)
v_fail <- function(detail = "", value = NULL) verdict("FAIL", detail, value)
v_warn <- function(detail = "", value = NULL) verdict("WARN", detail, value)
v_skip <- function(detail = "", value = NULL) verdict("SKIP", detail, value)
v_expect <- function(ok, detail = "", value = NULL) if (isTRUE(ok)) v_pass(detail, value) else v_fail(detail, value)

# Run one check: `fun` is a function returning a verdict; an error is a FAIL
# naming the condition class; warnings are logged. Returns the verdict's
# value (NULL when the check failed with an error).
live_check <- function(id, title, fun) {
  live_logf("[%s] %s", id, title)
  started <- Sys.time()
  result <- tryCatch(
    withCallingHandlers(
      fun(),
      warning = function(w) {
        live_logf("      warning (%s): %s", class(w)[1], conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) v_fail(sprintf("%s: %s", class(e)[1], conditionMessage(e)))
  )
  if (!is.list(result) || is.null(result$status)) result <- v_fail("the check returned no verdict")
  seconds <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  live$checks[[length(live$checks) + 1L]] <- list(
    id = id, title = title, status = result$status, detail = result$detail, seconds = seconds
  )
  live_logf("      -> %s%s (%.1f s)", result$status,
            if (nzchar(result$detail)) paste0(": ", result$detail) else "", seconds)
  invisible(result$value)
}

# Run the body of a script; an error outside the checks is recorded as a
# FAIL; the summary is always written.
live_run <- function(body) {
  tryCatch(
    body(),
    error = function(e) {
      live$checks[[length(live$checks) + 1L]] <- list(
        id = "script", title = "the script ran to its end", status = "FAIL",
        detail = sprintf("%s: %s", class(e)[1], conditionMessage(e)), seconds = 0
      )
      live_logf("The script stopped: %s: %s", class(e)[1], conditionMessage(e))
    }
  )
  live_finish()
}

live_finish <- function() {
  for (server in live$servers) try(server$stop(), silent = TRUE)
  live$servers <- list()
  live_update_secrets()
  checks <- live$checks
  statuses <- vapply(checks, `[[`, "", "status")
  count <- function(s) sum(statuses == s)
  failed <- count("FAIL") > 0L
  live_log("")
  live_log("Summary")
  for (check in checks) {
    live_logf("  %-4s  %-8s %s%s", check$status, check$id, check$title,
              if (nzchar(check$detail) && check$status != "PASS") paste0(" -- ", check$detail) else "")
  }
  live_logf(
    "RESULT: %s (%d PASS, %d FAIL, %d WARN, %d SKIP; %.0f s)%s",
    if (failed) "FAIL" else "PASS", count("PASS"), count("FAIL"), count("WARN"), count("SKIP"),
    as.numeric(difftime(Sys.time(), live$started, units = "secs")),
    if (live$fake) " [FAKE run]" else ""
  )
  live_leak_check()
  cat("Log: ", live$log, "\n", sep = "")
  if (!interactive()) quit(save = "no", status = if (failed) 1L else 0L)
  invisible(!failed)
}

# The identity claims and the tokens of the sessions of the run, never to be
# written (tokens rotate at each renewal: re-read at the end).
live_track_session <- function(soil, label) {
  live$sessions[[label]] <- soil
  live_update_secrets()
  invisible(soil)
}

live_update_secrets <- function() {
  claims <- c("sub", "preferred_username", "email", "name", "given_name", "family_name", "sid", "session_state")
  values <- character()
  for (soil in live$sessions) {
    state <- soil$state
    if (!is.environment(state)) next
    payload <- soilhub:::jwt_payload(state$access_token) %||% list()
    for (claim in intersect(claims, names(payload))) {
      if (is.character(payload[[claim]]) && length(payload[[claim]]) == 1L) values <- c(values, payload[[claim]])
    }
    for (token in list(state$access_token, state$refresh_token)) {
      if (is.character(token) && length(token) == 1L) values <- c(values, token)
    }
  }
  values <- values[!is.na(values) & nchar(values) >= 3L]
  live$secrets <- unique(c(live$secrets, values))
}

# Final check of the log: no token and no identity value; if one is found
# the log is rewritten redacted (and the fact recorded).
live_leak_check <- function() {
  text <- readLines(live$log, warn = FALSE)
  found <- soilhub:::scrub_leaks(paste(text, collapse = "\n"), live$secrets)
  if (length(found)) {
    writeLines(live_redact(text), live$log)
    cat("NOTE: identity values or tokens were found in the log and have been redacted.\n",
        file = live$log, append = TRUE)
  }
}

# ---------------------------------------------------------------------------
# Sessions.

# Sign in (live: the device login, a human step in the browser; fake: the
# fake Keycloak, or a fixture token for `jwt`).
live_connect <- function(label, api_url = NULL, client = "ams-r", jwt = NULL, kind = "auth") {
  if (live$fake) {
    if (!is.null(jwt)) {
      env <- live$fake_env
      soil <- env$write_session(live$servers[[kind]], jwt = jwt)
    } else {
      soil <- live$fake_env$fake_connect(live$servers$auth, client_id = client)
    }
  } else {
    live_logf("Sign in with the %s account: open the address printed below in a browser and enter the code.", label)
    soil <- soil_connect(api_url = api_url, set_default = FALSE, verbose = 1)
  }
  live_track_session(soil, label)
  live_logf("signed in (%s) on %s", label, soil$api_url)
  soil
}

# soil_whoami() printed in the log (user name and subject redacted).
live_log_whoami <- function(soil) {
  me <- soil_whoami(soil)
  live_log(paste0("      ", utils::capture.output(print(me))))
  me
}

# The session pointed at the fake server of one part of the API (fake run),
# or unchanged (live run). The copy shares the tokens and caches.
live_route <- function(soil, kind) {
  if (!live$fake) return(soil)
  server <- live$servers[[kind]]
  if (is.null(server)) stop(sprintf("no fake server `%s` in this run", kind), call. = FALSE)
  soil$api_url <- server$url("/api/v1")
  soil
}

# Ask the owner to do something and press Enter (works under Rscript in a
# terminal; there is no keyboard in an RStudio background job).
live_prompt <- function(text) {
  live_log(paste("ACTION:", text))
  if (live$fake) return(invisible(""))
  if (interactive()) return(invisible(readline("Press Enter when done: ")))
  cat("Press Enter when done: ")
  answer <- readLines(file("stdin"), n = 1L)
  invisible(if (length(answer)) answer else "")
}

# Requests sent to the API while `expr` runs (the exchange hook of http.R),
# and the value or the error of `expr`.
live_count_requests <- function(expr) {
  n <- 0L
  old <- options(soilhub.exchange_hook = function(exchange) n <<- n + 1L)
  on.exit(options(old), add = TRUE)
  value <- tryCatch(expr, error = function(e) e)
  list(value = value, requests = n)
}

live_now <- function() soilhub:::soil_now()

# Wait `seconds` (the fake clock in a fake session-hours run).
live_wait <- function(seconds) soilhub:::http_sleep(seconds)

# ---------------------------------------------------------------------------
# Fake servers (--fake): the unit-test helpers, sourced from the source tree.

# The helpers of the unit tests, sourced once into an environment whose
# parent is the soilhub namespace (they use its internal functions).
live_fake_env <- function() {
  if (!is.null(live$fake_env)) return(live$fake_env)
  if (!isTRUE(live$source_tree)) {
    stop("--fake needs the package source tree (tests/testthat/helper-fake-*.R): run it from the package root.", call. = FALSE)
  }
  if (!requireNamespace("webfakes", quietly = TRUE)) stop("--fake needs the package webfakes.", call. = FALSE)
  env <- new.env(parent = asNamespace("soilhub"))
  for (file in sort(list.files(file.path("tests", "testthat"), "^helper.*\\.R$", full.names = TRUE))) {
    sys.source(file, envir = env)
  }
  live$fake_env <- env
  env
}

live_fake_start <- function(kinds, zips = list()) {
  env <- live_fake_env()
  scope <- new.env()
  for (kind in kinds) {
    live$servers[[kind]] <- switch(kind,
      auth = env$fake_session_server(.local_envir = scope),
      catalog = env$fake_catalog_api(.local_envir = scope),
      wide = env$fake_wide_api(.local_envir = scope),
      long = env$fake_long_api(.local_envir = scope),
      thematic = env$fake_thematic_api(.local_envir = scope),
      write = env$fake_write_api(.local_envir = scope),
      source = env$fake_source_api(.local_envir = scope),
      export = env$fake_export_api(zips, .local_envir = scope),
      stop("unknown fake server ", kind)
    )
  }
  live_logf("fake servers: %s", paste(kinds, collapse = ", "))
  invisible(env)
}

# ---------------------------------------------------------------------------
# Tables: description and comparisons.

live_key <- function(x, component = TRUE) {
  column <- function(name) if (is.null(x[[name]])) rep(NA_character_, nrow(x)) else as.character(x[[name]])
  if (!component) return(paste(column("dataset"), column("feature_id"), column("horizon_id"), sep = "|"))
  paste(column("dataset"), column("feature_id"), column("component_id"), column("horizon_id"), sep = "|")
}

live_describe <- function(x) {
  md <- soil_metadata(x)
  sprintf(
    "%d rows, %d columns, %s page(s), complete %s, total_count %s, request ids %s, first key %s",
    nrow(x), ncol(x), format(md$pages %||% NA), format(md$complete %||% NA),
    format(md$total_count %||% NA), paste(md$request_ids %||% "none", collapse = " "),
    if (nrow(x)) live_key(x)[1] else "none"
  )
}

# The wide column of a long row (wide_layout.py): the canonical property key,
# else `src_<code>` (lower case, other characters as `_`).
live_wide_column <- function(property_code, canonical_property_key) {
  ifelse(
    is.na(canonical_property_key),
    paste0("src_", gsub("[^a-z0-9_]", "_", tolower(property_code))),
    canonical_property_key
  )
}

live_same_number <- function(a, b) {
  if (is.na(a) && is.na(b)) return(TRUE)
  if (is.na(a) || is.na(b)) return(FALSE)
  abs(a - b) <= 1e-9 * max(1, abs(a), abs(b))
}

# Wide/long equivalence (design 5.3, acceptance 10.4) of two reads of the
# same selection. Reads bounded by `max_rows` cover different parts of the
# selection (200 horizons against 200 observations): the comparison is made
# on the keys of the long rows, the last one dropped when the long read was
# cut (it may be partial); those keys must be wide rows. When both reads are
# complete the key sets must be equal. Per compared key and property: the
# wide `<key>` equals the first long value (numeric: `value`, a multi-value
# cell the mean of `value_raw`; text: the source text), `<key>_n` the number
# of long rows. Returns list(ok, compared, detail, mismatches).
live_equivalence <- function(wide, long) {
  if (!nrow(wide) || !nrow(long)) return(list(ok = FALSE, compared = 0L, detail = "an empty read", mismatches = character()))
  # The API fills component_id on long rows only for datasets with map-unit
  # components (SOTER/SOTWIS polygons); for profile datasets it is null on
  # long rows and set on wide rows: there the key is dataset|feature|horizon.
  with_component <- !is.null(long$component_id) && any(!is.na(long$component_id))
  wide_keys <- live_key(wide, with_component)
  long_keys <- live_key(long, with_component)
  wide_complete <- isTRUE(soil_metadata(wide)$complete)
  long_complete <- isTRUE(soil_metadata(long)$complete)
  out <- character()
  if (anyDuplicated(wide_keys)) out <- c(out, "duplicated wide keys")
  keys <- unique(long_keys)
  if (!long_complete && length(keys) > 1L) keys <- keys[-length(keys)]
  if (wide_complete && long_complete && !setequal(unique(long_keys), wide_keys)) {
    out <- c(out, sprintf("different key sets (%d wide, %d long)", length(wide_keys), length(unique(long_keys))))
  }
  absent <- setdiff(keys, wide_keys)
  if (length(absent)) {
    out <- c(out, sprintf("%d long key(s) not among the wide rows read (first: %s)", length(absent), absent[1]))
  }
  keys <- intersect(keys, wide_keys)
  columns <- soil_columns(wide)
  long_column <- live_wide_column(long$property_code, long$canonical_property_key)
  missing_columns <- setdiff(unique(long_column[long_keys %in% keys]), columns$column)
  if (length(missing_columns)) out <- c(out, sprintf("long properties without a wide column: %s", paste(missing_columns, collapse = ", ")))
  for (k in keys) {
    w <- match(k, wide_keys)
    for (i in seq_len(nrow(columns))) {
      name <- columns$column[[i]]
      rows <- which(long_keys == k & long_column == name)
      n_column <- wide[[paste0(name, "_n")]]
      n_wide <- if (is.null(n_column)) NA_integer_ else n_column[[w]]
      if (!length(rows)) {
        if (!is.na(n_wide) && n_wide > 0) out <- c(out, sprintf("%s_n of %s: wide %s, long none", name, k, n_wide))
        next
      }
      if (!identical(as.integer(n_wide), length(rows))) {
        out <- c(out, sprintf("%s_n of %s: wide %s, long %d", name, k, format(n_wide), length(rows)))
      }
      first <- rows[[1]]
      wide_value <- wide[[name]][[w]]
      multi <- wide[[paste0(name, "_values")]]
      if (isTRUE(columns$numeric[[i]])) {
        expected <- if (!is.null(multi) && length(multi[[w]]) > 1L) {
          mean(suppressWarnings(as.numeric(unlist(long$value_raw[[first]]))))
        } else {
          long$value[[first]]
        }
        if (!live_same_number(as.numeric(wide_value), as.numeric(expected))) {
          out <- c(out, sprintf("%s of %s: wide %s, long %s", name, k, format(wide_value), format(expected)))
        }
      } else {
        expected <- soilhub:::scalar_chr(long$value_raw[[first]])
        if (!identical(as.character(wide_value), as.character(expected))) {
          out <- c(out, sprintf("%s of %s: wide %s, long %s", name, k, format(wide_value), format(expected)))
        }
      }
    }
  }
  detail <- sprintf(
    "%d key(s) compared (wide %d rows%s, long %d rows%s), %d mismatch(es)",
    length(keys), nrow(wide), if (wide_complete) " complete" else " cut", nrow(long),
    if (long_complete) " complete" else " cut", length(out)
  )
  list(ok = length(keys) > 0L && !length(out), compared = length(keys), detail = detail, mismatches = out)
}

# Two wide tables of the same selection (a synchronous read and an export
# read back): the same keys, and per key the same value and count in every
# variable column of the synchronous read. Returns list(ok, detail,
# mismatches).
live_compare_wide <- function(sync, other) {
  out <- character()
  sync_keys <- live_key(sync)
  other_keys <- live_key(other)
  if (nrow(sync) != nrow(other)) out <- c(out, sprintf("rows: synchronous %d, export %d", nrow(sync), nrow(other)))
  if (!setequal(sync_keys, other_keys)) {
    out <- c(out, sprintf("different keys (%d only synchronous, %d only export)",
                          length(setdiff(sync_keys, other_keys)), length(setdiff(other_keys, sync_keys))))
  }
  columns <- soil_columns(sync)
  absent <- setdiff(c(columns$column, paste0(columns$column, "_n")), names(other))
  if (length(absent)) out <- c(out, sprintf("columns missing in the export: %s", paste(utils::head(absent, 10), collapse = ", ")))
  common <- intersect(sync_keys, other_keys)
  index <- match(common, other_keys)
  sync_index <- match(common, sync_keys)
  for (i in seq_len(nrow(columns))) {
    name <- columns$column[[i]]
    for (suffix in c("", "_n")) {
      column <- paste0(name, suffix)
      if (is.null(other[[column]])) next
      a <- sync[[column]][sync_index]
      b <- other[[column]][index]
      same <- if (is.numeric(a) && is.numeric(b)) {
        mapply(live_same_number, as.numeric(a), as.numeric(b))
      } else {
        (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & as.character(a) == as.character(b))
      }
      if (!all(same)) out <- c(out, sprintf("%s differs on %d row(s)", column, sum(!same)))
    }
  }
  list(
    ok = !length(out),
    detail = sprintf("%d rows, %d variable columns compared, %d mismatch(es)", length(common), nrow(columns), length(out)),
    mismatches = out
  )
}

# ---------------------------------------------------------------------------
# Rights of a reader (criterion 7), shared by smoke.R and write-acceptance.R.

live_reader_checks <- function(soil, me, prefix, jobs_soil = soil) {
  live_check(paste0(prefix, ".pre"), "a reader calling a write function gets the local permission error before any request", function() {
    if (!isTRUE(me$rights_known)) return(v_skip("the token does not declare its rights: the local pre-check does not run"))
    if (isTRUE(me$can[["admin"]])) return(v_skip("this account has soil:admin: not a reader"))
    calls <- list(
      "soil_register_variable()" = quote(soil_register_variable(
        soil, variable_code = "zz_soilhub_never_registered", name = "never registered",
        domain_code = "soil", value_type = "numeric", measurement_kind_code = "derived",
        allowed_target_levels = "feature", idempotency_key = "zz-soilhub-never"
      ))
    )
    if (!isTRUE(me$can[["publish"]])) {
      calls[["soil_run_open()"]] <- quote(soil_run_open(soil, 1L, idempotency_key = "zz-soilhub-never"))
    }
    problems <- character()
    for (name in names(calls)) {
      out <- live_count_requests(eval(calls[[name]]))
      e <- out$value
      live_logf("      %s -> %s, %d request(s): %s", name, class(e)[1], out$requests,
                if (inherits(e, "condition")) conditionMessage(e) else "returned a value")
      if (!inherits(e, "soilhub_permission_error")) problems <- c(problems, sprintf("%s did not raise soilhub_permission_error", name))
      if (out$requests > 0L) problems <- c(problems, sprintf("%s sent %d request(s)", name, out$requests))
    }
    v_expect(!length(problems), if (length(problems)) paste(problems, collapse = "; ") else
      sprintf("%d write function(s) refused locally, no request sent", length(calls)))
  })

  live_check(paste0(prefix, ".403"), "with the local pre-check disabled, the API's 403 maps to soilhub_permission_error", function() {
    if (isTRUE(me$can[["publish"]])) return(v_skip("this account has soil:publish: the API would not refuse soil_job()"))
    state <- soil$state
    saved <- state$identity
    on.exit(state$identity <- saved, add = TRUE)
    identity <- saved
    identity$rights_known <- FALSE
    state$identity <- identity
    # GET /jobs/{id} needs soil:publish and changes nothing.
    out <- live_count_requests(soil_job(jobs_soil, "00000000-0000-4000-8000-000000000000"))
    e <- out$value
    live_logf("      soil_job() without the pre-check -> %s (status %s, request id %s), %d request(s)",
              class(e)[1], format(e$status %||% NA), format(e$request_id %||% NA), out$requests)
    if (inherits(e, "soilhub_permission_error") && identical(as.integer(e$status), 403L)) {
      v_pass(sprintf("403 mapped to soilhub_permission_error (required right %s)", format(e$required_right %||% NA)))
    } else if (inherits(e, "soilhub_not_found_error")) {
      v_skip("the API answered 404: this account may hold soil:publish (or the API does not check rights)")
    } else {
      v_fail(sprintf("expected soilhub_permission_error with status 403, got %s", class(e)[1]))
    }
  })
}
