# Contract suite (design 7.2, WP10). Not run by R CMD check (.Rbuildignore);
# run it from the package root with
#
#   Rscript tests/contract/run.R            # against tests/contract/openapi.json
#   Rscript tests/contract/run.R live       # against the live openapi.json
#
# How the list of client requests is derived (no hand-made list):
# `soil_request()` passes every request to the option `soilhub.exchange_hook`
# (R/http.R). `record_requests.R` runs the unit tests (tests/testthat, fake
# API) in a fresh R process with a hook that keeps the requests made from
# inside an exported function of soilhub (the requests a user can cause; the
# unit tests of the HTTP layer that call `soil_request()` on made-up paths
# are left out) with their method, path, query and JSON body as sent. A new
# call of the client is covered as soon as a unit test exercises it, and
# `test-endpoints.R` fails when a path literal of the package code is never
# requested by the unit tests.

contract_env <- new.env(parent = emptyenv())

contract_root <- function() {
  normalizePath(file.path(testthat::test_path(), "..", ".."), mustWork = TRUE)
}

live_openapi_url <- "https://soilhub.weatherprogapp.it/openapi.json"

# The OpenAPI document under test: SOILHUB_CONTRACT_OPENAPI = "snapshot"
# (default, tests/contract/openapi.json), "live", or a path or URL.
contract_openapi <- function() {
  if (is.null(contract_env$openapi)) {
    source <- Sys.getenv("SOILHUB_CONTRACT_OPENAPI", "snapshot")
    location <- switch(source,
      snapshot = file.path(contract_root(), "tests", "contract", "openapi.json"),
      live = live_openapi_url,
      source
    )
    contract_env$openapi_source <- location
    contract_env$openapi <- jsonlite::fromJSON(location, simplifyVector = FALSE)
  }
  contract_env$openapi
}

# The requests of the client, recorded from the unit tests (see the top of
# this file). SOILHUB_CONTRACT_REQUESTS may name an .rds file: read when it
# exists (a run of record_requests.R), else written by this run.
client_requests <- function() {
  if (is.null(contract_env$requests)) {
    path <- Sys.getenv("SOILHUB_CONTRACT_REQUESTS", "")
    if (!nzchar(path) || !file.exists(path)) {
      if (!nzchar(path)) path <- tempfile("soilhub-requests-", fileext = ".rds")
      script <- file.path(contract_root(), "tests", "contract", "record_requests.R")
      rscript <- file.path(R.home("bin"), "Rscript")
      log <- system2(rscript, c("--no-init-file", shQuote(script), shQuote(contract_root()), shQuote(path)),
                     stdout = TRUE, stderr = TRUE, env = "R_PROFILE_USER=/dev/null")
      if (!file.exists(path)) {
        stop("Recording the client requests failed:\n", paste(utils::tail(log, 40), collapse = "\n"), call. = FALSE)
      }
      Sys.setenv(SOILHUB_CONTRACT_REQUESTS = path)
    }
    contract_env$requests <- readRDS(path)
  }
  contract_env$requests
}

# A short label of the exported functions that made a request.
callers_label <- function(callers) {
  callers <- unique(unlist(callers))
  if (!length(callers)) return("")
  shown <- utils::head(callers, 3L)
  paste0(" [from ", paste0(shown, "()", collapse = ", "), if (length(callers) > 3L) ", ..." else "", "]")
}

# One expectation for a set of drift problems, with a readable message.
expect_no_drift <- function(problems, what) {
  problems <- unique(problems[nzchar(problems)])
  if (length(problems)) {
    testthat::fail(paste0(
      what, " (", length(problems), " problem(s), OpenAPI: ", contract_env$openapi_source, "):\n",
      paste0("  - ", problems, collapse = "\n")
    ))
  } else {
    testthat::succeed()
  }
}

# Path literals of the package that are not API paths of the client.
non_api_literals <- c(
  "/protocol/openid-connect/auth/device", # Keycloak (auth-device.R)
  "/protocol/openid-connect/token"
)

# ---------------------------------------------------------------------------
# Response models: where the API sends what each typing table of the client
# types (design 7.2). The tables are read from the package namespace (not
# copied); this map only says where they apply. `test-responses.R` fails
# when a typing table of the namespace (a `*_schema` list or a named
# `*_types` vector) is not listed here, so a new table must be placed.
# `at` = "METHOD path" (several when the same model answers several
# operations), `pointer` as in response_schema_at().

response_tables <- list(
  unified_job_schema = list(at = "GET /jobs/{job_id}"),
  export_job_schema = list(at = c("POST /exports", "GET /exports/{job_id}")),
  publication_job_schema = list(at = "GET /publication-jobs/{job_id}"),
  health_job_schema = list(at = "GET /soil-health-publication-jobs/{job_id}"),
  availability_dataset_schema = list(at = "POST /query/availability", pointer = "by_dataset[]"),
  availability_country_schema = list(at = "POST /query/availability", pointer = "by_country[]"),
  availability_variable_schema = list(at = "POST /query/availability", pointer = "by_dataset[].variables[]"),
  variant_schema = list(at = "POST /query/availability", pointer = "by_dataset[].variables[].variants[]"),
  consistency_schema = list(at = "POST /query/consistency", pointer = "countries[]"),
  country_count_schema = list(at = "GET /countries", pointer = "countries[]"),
  country_list_schema = list(at = "GET /countries", pointer = "countries[]"),
  country_detail_schema = list(at = "GET /countries/{code}", pointer = "country"),
  country_dataset_schema = list(at = "GET /countries/{code}", pointer = "datasets[]"),
  country_variable_schema = list(at = "GET /countries/{code}", pointer = "variables[]"),
  dataset_schema = list(at = "GET /datasets/{dataset_name}"),
  note_schema = list(at = "GET /datasets/{dataset_name}", pointer = "notes[]"),
  source_asset_schema = list(at = "GET /datasets/{dataset_name}", pointer = "source_assets[]"),
  code_lists_schema = list(at = "GET /code-lists", pointer = "code_lists[]"),
  code_list_schema = list(at = "GET /code-lists/{code_list}", pointer = "codes[]"),
  code_list_source_schema = list(at = "GET /code-lists", pointer = "code_lists[].source_datasets[]"),
  ttr_legend_schema = list(at = "GET /sotwis/ttr-flags/legend", pointer = "legend[]"),
  ttr_flags_schema = list(at = "GET /sotwis/ttr-flags", pointer = "flags[]"),
  variable_schema = list(at = "GET /variables", pointer = "variables[]"),
  source_mapping_schema = list(at = "GET /variables", pointer = "variables[].source_mappings[]"),
  method_facet_schema = list(at = "GET /variables", pointer = "variables[].source_mappings[].method_facets[]"),
  unmapped_schema = list(at = "GET /variables", pointer = "metadata.unmapped_source_codes[]"),
  variable_registration_schema = list(at = "POST /variables"),
  publication_receipt_schema = list(at = "POST /publications/{run_id}/values"),
  health_receipt_schema = list(at = "POST /publications/{run_id}/soil-health"),
  product_schema = list(at = "POST /products"),
  product_version_schema = list(at = "POST /products/{product_code}/versions"),
  declared_variable_schema = list(at = "POST /products/{product_code}/versions", pointer = "declared_variables[]"),
  run_schema = list(at = "POST /product-versions/{product_version_id}/runs"),
  target_result_schema = list(at = "POST /query/targets/resolve", pointer = "targets[]"),
  values_schema = list(at = "POST /query/values", pointer = "values[]"),
  values_lineage_schema = list(at = "POST /query/values", pointer = "values[]"),
  health_schema = list(at = "POST /query/soil-health", pointer = "scores[]"),
  health_details_schema = list(at = "POST /query/soil-health", pointer = "scores[]"),
  semantics_schema = list(at = "POST /query/summary", pointer = "variable_semantics_by_dataset{}[]"),
  hidden_values_schema = list(at = "POST /query/observations", pointer = "rows[]"),
  wide_column_types = list(at = "POST /query/observations", pointer = "rows[]"),
  long_column_types = list(at = "POST /query/observations", pointer = "observations[]"),
  feature_property_types = list(at = "POST /query/features", pointer = "features[]"),
  feature_component_types = list(at = "POST /query/features", pointer = "features[]")
)

# Functions that read fields of a response body directly (`response$field`),
# checked by name against the response of their endpoint. `test-responses.R`
# fails when a function of the namespace reads `response$...` and is listed
# neither here nor in `response_readers_other`.
response_readers <- list(
  summary_result = "POST /query/summary",
  availability_result = "POST /query/availability",
  consistency_result = "POST /query/consistency",
  soil_countries = "GET /countries",
  soil_country = "GET /countries/{code}",
  soil_health_summary = "POST /query/soil-health/summary",
  soil_values_summary = "POST /query/values/summary",
  soil_resolve_targets = "POST /query/targets/resolve",
  soil_variables = "GET /variables",
  soil_datasets = "GET /datasets",
  soil_formats = "GET /formats",
  soil_code_lists = "GET /code-lists",
  soil_code_list = "GET /code-lists/{code_list}",
  soil_ttr_flag_legend = "GET /sotwis/ttr-flags/legend"
)

# `response` is not an API JSON body in these (an httr2 response of Keycloak,
# or the generic `metadata` of any response).
response_readers_other <- c(
  "keycloak_unavailable", "oauth_error", "oauth_error_text", "refresh_session",
  "response_metadata"
)

split_at <- function(at) {
  parts <- strsplit(at, " ", fixed = TRUE)[[1]]
  list(method = parts[1], path = parts[2])
}
