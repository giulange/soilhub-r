# Check the API version range of the client (design 9.1) against an OpenAPI
# document: the committed snapshot (default) or the live one. Run from the
# package root; needs pkgload. No token.
#
#   Rscript tools/check_version.R          # tests/contract/openapi.json
#   Rscript tools/check_version.R live     # https://soilhub.weatherprogapp.it/openapi.json
#
# Prints the client constants (MIN_API_VERSION, TESTED_API_VERSION,
# SUPPORTED_API_MAJOR) and the
# verdict of check_api_version() for `info.version`; exits with status 1 when
# the API version is not supported. The contract suite makes the same check
# (tests/contract/test-version.R).

args <- commandArgs(trailingOnly = TRUE)
source <- if (length(args) && identical(args[1], "live")) {
  "https://soilhub.weatherprogapp.it/openapi.json"
} else if (length(args)) {
  args[1]
} else {
  file.path("tests", "contract", "openapi.json")
}
suppressMessages(pkgload::load_all(".", helpers = FALSE, quiet = TRUE))
doc <- jsonlite::fromJSON(source, simplifyVector = FALSE)
version <- doc$info$version
verdict <- check_api_version(version)
cat(sprintf(
  "soilhub %s: MIN_API_VERSION %s, TESTED_API_VERSION %s, SUPPORTED_API_MAJOR %d\nAPI (%s): %s\nStatus: %s%s\n",
  client_version(), MIN_API_VERSION, TESTED_API_VERSION, SUPPORTED_API_MAJOR, source, version %||% "none",
  verdict$status, if (is.null(verdict$message)) "" else paste0(" -- ", verdict$message)
))
if (!isTRUE(verdict$compatible)) quit(status = 1)
