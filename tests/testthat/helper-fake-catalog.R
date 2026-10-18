# Fake catalog API for the discovery tests (WP3): the fixtures of
# tests/testthat/fixtures served at their paths, by an anonymous webfakes app
# (the session tests cover authentication). Fixtures are hand-made from the
# API models (python/soil_api) until WP10 records them.
#
# GET /api/v1/datasets, /datasets/:name (404 "Dataset not found" when not in
# the fixture), /formats, /variables (the raw query string is echoed in
# `metadata.received_query`), /countries, /countries/:code (KEN only),
# /code-lists, /code-lists/:name (SOTWIS_codes only), /sotwis/ttr-flags/legend,
# /health, /ready.

fake_catalog_api <- function(datasets = read_fixture("datasets.json"),
                             .local_envir = parent.frame()) {
  testthat::skip_if_not_installed("webfakes")
  app <- webfakes::new_app()
  app$use(webfakes::mw_json())
  app$locals$fixtures <- list(
    datasets = datasets,
    variables = read_fixture("variables.json"),
    countries = read_fixture("countries.json"),
    country = read_fixture("country-KEN.json"),
    code_lists = read_fixture("code-lists.json"),
    code_list = read_fixture("code-list-SOTWIS_codes.json"),
    legend = read_fixture("ttr-flag-legend.json")
  )
  env <- new.env(parent = baseenv())
  route <- function(handler) {
    environment(handler) <- env
    handler
  }
  send <- function(res, body) res$send_json(body, auto_unbox = TRUE, null = "null", na = "null", digits = NA)
  not_found <- function(res, detail) res$set_status(404L)$send_json(list(detail = detail), auto_unbox = TRUE)
  assign("send", route(send), envir = env)
  assign("not_found", route(not_found), envir = env)

  app$get("/api/v1/health", route(function(req, res) send(res, list(status = "ok"))))
  app$get("/api/v1/ready", route(function(req, res) send(res, list(status = "ready", database = "ok"))))
  app$get("/api/v1/formats", route(function(req, res) {
    send(res, list(formats = list("geojson", "gpkg", "csv", "tsv", "shp")))
  }))
  app$get("/api/v1/datasets", route(function(req, res) send(res, req$app$locals$fixtures$datasets)))
  app$get("/api/v1/datasets/:name", route(function(req, res) {
    for (item in req$app$locals$fixtures$datasets$datasets) {
      if (identical(item$name, req$params$name)) return(send(res, item))
    }
    not_found(res, "Dataset not found")
  }))
  app$get("/api/v1/variables", route(function(req, res) {
    body <- req$app$locals$fixtures$variables
    body$metadata$received_query <- req$query_string
    send(res, body)
  }))
  app$get("/api/v1/countries", route(function(req, res) send(res, req$app$locals$fixtures$countries)))
  app$get("/api/v1/countries/:code", route(function(req, res) {
    if (toupper(req$params$code) %in% c("KE", "KEN")) return(send(res, req$app$locals$fixtures$country))
    not_found(res, "country not found")
  }))
  app$get("/api/v1/code-lists", route(function(req, res) send(res, req$app$locals$fixtures$code_lists)))
  app$get("/api/v1/code-lists/:name", route(function(req, res) {
    if (!identical(req$params$name, "SOTWIS_codes")) {
      return(not_found(res, paste0("unknown code list: ", req$params$name)))
    }
    body <- req$app$locals$fixtures$code_list
    body$metadata$received_query <- req$query_string
    send(res, body)
  }))
  app$get("/api/v1/sotwis/ttr-flags/legend", route(function(req, res) send(res, req$app$locals$fixtures$legend)))
  webfakes::local_app_process(app, .local_envir = .local_envir)
}

# A signed-out session on the fake catalog API with the capabilities cached
# (as soil_connect() leaves them after the login).
catalog_session <- function(server, capabilities = read_fixture("capabilities.json")) {
  soil <- new_soil_session(soil_config(api_url = server$url("/api/v1"), timeout = 30, verbose = 0))
  soil$state$capabilities <- capabilities
  soil
}

# The capabilities fixture with some capability flags changed (NULL removes).
capabilities_with <- function(..., api_version = NULL) {
  capabilities <- read_fixture("capabilities.json")
  changes <- list(...)
  for (name in names(changes)) capabilities$capabilities[name] <- list(changes[[name]])
  capabilities$capabilities <- Filter(Negate(is.null), capabilities$capabilities)
  if (!is.null(api_version)) capabilities$api_version <- api_version
  capabilities
}
