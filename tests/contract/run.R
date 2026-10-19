# Run the contract suite (design 7.2) from the package root:
#
#   Rscript tests/contract/run.R             # against tests/contract/openapi.json
#   Rscript tests/contract/run.R live        # against the live openapi.json
#   Rscript tests/contract/run.R <path|URL>  # against another document
#
# Needs pkgload, testthat, webfakes and withr. Exits with status 1 on a
# failure. No token is needed: capabilities.json and the recorded fixtures
# are read from the repository (tools/record_fixtures.R), and the tests that
# need them skip until the owner has recorded them.

args <- commandArgs(trailingOnly = TRUE)
file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
here <- if (length(file_arg)) dirname(normalizePath(sub("^--file=", "", file_arg))) else file.path("tests", "contract")
root <- normalizePath(file.path(here, "..", ".."), mustWork = TRUE)

Sys.setenv(SOILHUB_CONTRACT_OPENAPI = if (length(args)) args[1] else "snapshot")
cat("Contract suite against the OpenAPI document:", Sys.getenv("SOILHUB_CONTRACT_OPENAPI"), "\n")
suppressMessages(pkgload::load_all(root, helpers = FALSE, quiet = TRUE))
results <- testthat::test_dir(
  file.path(root, "tests", "contract"), package = "soilhub",
  load_package = "none", stop_on_failure = FALSE
)
frame <- as.data.frame(results)
if (sum(frame$failed) > 0 || any(frame$error)) quit(status = 1)
