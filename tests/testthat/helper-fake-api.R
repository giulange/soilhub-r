# Fake Global Soil Data Hub API for unit tests (design 7.1).
#
# `fake_api()` starts a local webfakes server whose routes are filled by later
# work packages from recorded fixtures (tests/testthat/fixtures/*.json). It
# returns the running server; use `server$url()` as the API base URL. The
# server is stopped automatically when the calling test (or test file) ends.

fake_api <- function(routes = list(), .local_envir = parent.frame()) {
  testthat::skip_if_not_installed("webfakes")
  app <- webfakes::new_app()
  app$get("/health", function(req, res) {
    res$send_json(list(status = "ok"), auto_unbox = TRUE)
  })
  for (route in routes) {
    app[[route$method]](route$path, route$handler)
  }
  webfakes::local_app_process(app, .local_envir = .local_envir)
}

# Read a recorded fixture; fixtures are added by later work packages.
read_fixture <- function(name) {
  path <- testthat::test_path("fixtures", name)
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}
