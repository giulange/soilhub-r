# Refresh or check the contract snapshots of tests/contract (design 7.2).
# Run from the package root; needs pkgload. No token.
#
#   Rscript tools/update_contract_snapshots.R           # write tests/contract/openapi.json
#   Rscript tools/update_contract_snapshots.R --check   # diff the live document against it
#
# `--check` prints the differences between the live `openapi.json` of the
# API and the committed snapshot and exits with status 1 when there are any
# (the scheduled job of .github/workflows/contract.yml). The owner then
# decides whether the client follows: refresh the snapshot with this script,
# run the contract suite (`Rscript tests/contract/run.R`) and fix the client
# where it fails.
#
# The snapshot and the constant TESTED_API_VERSION (R/capabilities.R, the API
# version the client is tested against) go together: writing the snapshot
# sets the constant to its `info.version`; `--check` also fails when they
# differ (as does tests/contract/test-version.R).
#
# `capabilities.json` needs a login (`soil:summary`): it is written by
# tools/record_fixtures.R together with the recorded fixtures.
#
# Set SOILHUB_OPENAPI_URL to read another deployment.

url <- Sys.getenv("SOILHUB_OPENAPI_URL", "https://soilhub.weatherprogapp.it/openapi.json")
snapshot <- file.path("tests", "contract", "openapi.json")
if (!file.exists("DESCRIPTION") || !dir.exists(dirname(snapshot))) {
  stop("Run tools/update_contract_snapshots.R from the root of the soilhub package.", call. = FALSE)
}
suppressMessages(pkgload::load_all(".", helpers = FALSE, quiet = TRUE))
check <- "--check" %in% commandArgs(trailingOnly = TRUE)
constants_file <- file.path("R", "capabilities.R")
constant_pattern <- '^TESTED_API_VERSION <- "[^"]*"$'

response <- httr2::req_perform(httr2::req_timeout(httr2::request(url), 60))
text <- httr2::resp_body_string(response)
live <- jsonlite::fromJSON(text, simplifyVector = FALSE)
if (!is.list(live$paths) || !is.list(live$info)) {
  stop(url, " did not return an OpenAPI document.", call. = FALSE)
}

if (check) {
  if (!file.exists(snapshot)) stop(snapshot, " does not exist: run this script without --check.", call. = FALSE)
  old <- jsonlite::fromJSON(snapshot, simplifyVector = FALSE)
  differences <- openapi_diff(old, live)
  cat(sprintf("Snapshot: %s (API %s)\nLive:     %s (API %s)\nTESTED_API_VERSION: %s\n",
              snapshot, old$info$version, url, live$info$version, TESTED_API_VERSION))
  if (!identical(TESTED_API_VERSION, old$info$version)) {
    differences <- c(differences, sprintf(
      "TESTED_API_VERSION (%s, R/capabilities.R) differs from the snapshot's info.version (%s): run this script without --check",
      TESTED_API_VERSION, old$info$version
    ))
  }
  if (!length(differences)) {
    cat("No difference.\n")
    quit(status = 0)
  }
  cat(sprintf("%d difference(s):\n", length(differences)))
  cat(paste0("  - ", differences, "\n"), sep = "")
  quit(status = 1)
}

version <- live$info$version
if (!is_string(version) || is.null(parse_api_version(version))) {
  stop(url, " has no readable info.version.", call. = FALSE)
}
lines <- readLines(constants_file, warn = FALSE)
at <- grep(constant_pattern, lines)
if (length(at) != 1L) stop("No single `TESTED_API_VERSION <- \"...\"` line in ", constants_file, call. = FALSE)
writeLines(as.character(jsonlite::prettify(text, indent = 2)), snapshot, useBytes = TRUE)
lines[at] <- sprintf('TESTED_API_VERSION <- "%s"', version)
writeLines(lines, constants_file)
cat(sprintf("Wrote %s (API %s, %d paths) and TESTED_API_VERSION <- \"%s\" in %s (was %s).\n",
            snapshot, version, length(live$paths), version, constants_file, TESTED_API_VERSION))
cat("Next: Rscript tests/contract/run.R, then the unit tests (they derive the newer-minor cases from the constant).\n")
