# Record the requests the client sends, by running the unit tests
# (tests/testthat, fake API) with the `soilhub.exchange_hook` option (R/http.R).
# Called by helper-contract.R in a fresh R process:
#
#   Rscript tests/contract/record_requests.R <package root> <output .rds>
#
# Kept: the requests made from inside an exported function of soilhub, with
# `callers` (the exported functions on the call stack, outermost first).

args <- commandArgs(trailingOnly = TRUE)
root <- normalizePath(args[1], mustWork = TRUE)
out <- args[2]

suppressMessages(pkgload::load_all(root, helpers = FALSE, quiet = TRUE))
exports <- getNamespaceExports("soilhub")
recorded <- new.env(parent = emptyenv())
recorded$requests <- list()
recorded$all <- 0L

call_name <- function(call) {
  f <- call[[1]]
  if (is.name(f)) return(as.character(f))
  if (is.call(f) && is.name(f[[1]]) && as.character(f[[1]]) %in% c("::", ":::")) {
    return(as.character(f[[3]]))
  }
  ""
}

options(soilhub.exchange_hook = function(exchange) {
  recorded$all <- recorded$all + 1L
  callers <- intersect(vapply(sys.calls(), call_name, character(1)), exports)
  if (!length(callers)) return(invisible(NULL))
  exchange$response <- NULL
  exchange$callers <- callers
  recorded$requests[[length(recorded$requests) + 1L]] <- exchange
  invisible(NULL)
})

results <- testthat::test_dir(
  file.path(root, "tests", "testthat"), package = "soilhub",
  load_package = "none", reporter = "silent", stop_on_failure = FALSE
)
failed <- sum(as.data.frame(results)$failed)
if (failed > 0) message("record_requests.R: ", failed, " unit test expectation(s) failed")
attr(recorded$requests, "all") <- recorded$all
saveRDS(recorded$requests, out)
