#' @include typing.R
NULL

# Products, immutable versions and runs (design 4.6). Products and versions
# need `soil:admin`, runs `soil:publish`.
#
# The API is idempotent by content: registering the same product, the same
# version or opening a run with the same key and parameters returns the
# existing object (HTTP 200). A 409 is therefore always a real conflict
# (same code or key, different content). The API has no GET for products,
# versions or runs (fact 12.2.6): the conflict cannot be resolved by reading
# the existing object, and the error says what to do instead.

product_schema <- list(
  product_code = "chr", name = "chr", description = "chr", target_level = "chr"
)

declared_variable_schema <- list(variable_code = "chr", target_levels = "chr_list")

product_version_schema <- list(
  product_code = "chr", product_name = "chr", description = "chr",
  product_version_id = "dbl", version_code = "chr", algorithm_checksum = "chr",
  configuration = "json", declared_variables = frames(declared_variable_schema),
  created_at = "time"
)

run_schema <- list(
  run_id = "dbl", product_version_id = "dbl", product_code = "chr",
  version_code = "chr", status = "chr", idempotency_key = "chr",
  started_at = "time", completed_at = "time", parameters = "json",
  diagnostics = "json", input_release_ids = "json"
)

#' Register a product
#'
#' A product is the family of results of one external model (e.g. a soil
#' health index), attached to one canonical target level. Its scientific
#' content lives in immutable versions ([soil_product_version()]); results
#' are published in runs of a version ([soil_run_open()]).
#'
#' Registering the same definition again returns it unchanged. A
#' `product_code` already registered with another name, description or
#' target level is a `soilhub_conflict_error` (HTTP 409); the API offers no
#' way to read the existing product, so keep using its code if it is yours,
#' or choose another code.
#'
#' Rights: `soil:admin`.
#'
#' @param soil A session; the default session when omitted. Client-side: not sent to the API.
#' @param product_code Code of the product: lowercase letters, digits, `_`. API field `product_code`
#'   of `POST /products`; for [soil_product_version()], API path parameter `{product_code}` of
#'   `POST /products/{product_code}/versions`.
#' @param name Human name. API field `name` of `POST /products`.
#' @param target_level The canonical level of its results: `"feature"`,
#'   `"profile"`, `"component"` or `"horizon"`. API field `target_level` of `POST /products`.
#' @param description Optional description. API field `description` of `POST /products`.
#' @return The product: a list `product_code`, `name`, `description`,
#'   `target_level`.
#' @family writing
#' @examples
#' \dontrun{
#' soil_product(soil, "soil_health_fuzzy", "Soil health (fuzzy model)", "horizon")
#' }
#' @export
soil_product <- function(soil = soil_session(), product_code, name, target_level,
                         description = NULL) {
  check_session(soil)
  soil_require_right(soil, "soil:admin", "`soil_product()`")
  body <- list(
    product_code = check_code(product_code, "product_code"),
    name = check_text(name, "name"),
    description = if (is.null(description)) NULL else check_text(description, "description"),
    target_level = match_choice(target_level, target_levels, "target_level")
  )
  body <- body[!vapply(body, is.null, logical(1))]
  product <- with_conflict_advice(
    soil_request(soil, "POST", "/products", body = body, right = "soil:admin"),
    sprintf(
      paste0(
        "The product `%s` is already registered with another definition. The API cannot ",
        "show it: if it is yours, keep its code and register a version with ",
        "soil_product_version(); otherwise choose another product code."
      ),
      product_code
    )
  )
  typed_object(product, product_schema, "POST /products")
}

#' Register an immutable product version
#'
#' A version freezes the scientific content of a product: the SHA-256
#' checksum of the algorithm (code, model artifact), its configuration and
#' the variables it publishes with their target levels. Every variable must
#' be registered ([soil_register_variable()]) and allow the declared levels.
#' Any scientific change is a new version.
#'
#' Registering the same version again returns it (with its
#' `product_version_id`). A `version_code` already registered with another
#' checksum, configuration or variables is a `soilhub_conflict_error`
#' (HTTP 409): register a new version code. An unknown product is a
#' `soilhub_not_found_error`.
#'
#' Rights: `soil:admin`.
#'
#' @inheritParams soil_product
#' @param version_code Code of the version (e.g. `"v1.0.0"`). API field `version_code`.
#' @param algorithm_checksum SHA-256 of the algorithm: 64 lowercase
#'   hexadecimal characters (e.g. `openssl::sha256(file("model.R"))`). API field
#'   `algorithm_checksum`.
#' @param variables The variables published by the version: a data frame
#'   with `variable_code` and `target_levels` (a character column, one level
#'   per row, or a list column of character vectors), or a list of
#'   `list(variable_code =, target_levels =)`. API field `variables`.
#' @param configuration The configuration of the model, a named list (a
#'   JSON object). API field `configuration`.
#' @return The version: a list `product_code`, `product_name`,
#'   `description`, `product_version_id` (the id to open runs),
#'   `version_code`, `algorithm_checksum`, `configuration` (list),
#'   `declared_variables` (data frame `variable_code`, `target_levels`),
#'   `created_at`.
#' @family writing
#' @examples
#' \dontrun{
#' v <- soil_product_version(
#'   soil, "soil_health_fuzzy", "v1.0.0",
#'   algorithm_checksum = as.character(openssl::sha256(file("model.R"))),
#'   variables = data.frame(variable_code = "soil_health_physical_score",
#'                          target_levels = "horizon"),
#'   configuration = list(rule_base = "physical-v1")
#' )
#' v$product_version_id
#' }
#' @export
soil_product_version <- function(soil = soil_session(), product_code, version_code,
                                 algorithm_checksum, variables,
                                 configuration = list()) {
  check_session(soil)
  soil_require_right(soil, "soil:admin", "`soil_product_version()`")
  product_code <- check_code(product_code, "product_code")
  if (!is_string(algorithm_checksum) || !grepl("^[a-f0-9]{64}$", algorithm_checksum)) {
    abort(soilhub_argument_error(
      sprintf(
        "`algorithm_checksum` must be a SHA-256 digest (64 lowercase hexadecimal characters), not %s.",
        deparse_argument(algorithm_checksum)
      ),
      "algorithm_checksum"
    ))
  }
  body <- list(
    version_code = check_text(version_code, "version_code"),
    algorithm_checksum = algorithm_checksum,
    configuration = json_object(configuration, "configuration"),
    variables = declared_variables(variables)
  )
  version <- with_conflict_advice(
    soil_request(
      soil, "POST", paste0("/products/", url_segment(product_code), "/versions"),
      body = body, right = "soil:admin"
    ),
    sprintf(
      paste0(
        "The version `%s` of `%s` exists with another checksum, configuration or ",
        "variables (versions are immutable), or a variable is unknown or does not ",
        "allow a declared level: register a new version code, or fix the variables."
      ),
      version_code, product_code
    )
  )
  typed_object(version, product_version_schema, "POST /products/{product_code}/versions")
}

declared_variables <- function(variables) {
  argument <- "variables"
  items <- if (is.data.frame(variables)) {
    if (!all(c("variable_code", "target_levels") %in% names(variables))) {
      abort(soilhub_argument_error(
        "`variables` must have the columns `variable_code` and `target_levels`.",
        argument
      ))
    }
    lapply(seq_len(nrow(variables)), function(i) list(
      variable_code = variables$variable_code[[i]],
      target_levels = variables$target_levels[[i]]
    ))
  } else if (is.list(variables) && is.null(names(variables))) {
    variables
  } else {
    NULL
  }
  if (length(items) == 0L) {
    abort(soilhub_argument_error(
      "`variables` must declare at least one variable (a data frame or a list of records).",
      argument
    ))
  }
  lapply(items, function(item) {
    if (!is.list(item)) {
      abort(soilhub_argument_error("Each element of `variables` must be a list.", argument))
    }
    list(
      variable_code = check_code(item$variable_code, "variables$variable_code"),
      target_levels = as.list(check_levels(unlist(item$target_levels), "variables$target_levels"))
    )
  })
}

#' Open, complete or fail a run
#'
#' A run is one execution of a product version: the results published in it
#' come from the exact source releases listed in `input_release_ids` (the
#' input snapshot) and the `parameters` of the execution (geographic scope,
#' options, external execution reference; never a secret).
#'
#' `soil_run_open()` is idempotent: the same `idempotency_key` with the same
#' parameters and input snapshot returns the run already open; with other
#' parameters it is a `soilhub_conflict_error` (HTTP 409). Keep the
#' `run_id`: there is no way to list runs.
#'
#' `soil_run_complete()` closes a run whose publications are all verified
#' (every receipt has `published_count == received_count`, no job left
#' `queued` or `running`); `soil_run_fail()` closes it as failed, with
#' structured `diagnostics`. Repeating the same closing is harmless; closing
#' a run already closed the other way is a `soilhub_conflict_error`, as is
#' completing a run with a soil-health job that did not complete.
#'
#' Rights: `soil:publish`.
#'
#' @param soil A session; the default session when omitted. Client-side: not sent to the API.
#' @param product_version_id The id of the version
#'   ([soil_product_version()]). API path parameter `{product_version_id}` of
#'   `POST /product-versions/{product_version_id}/runs`.
#' @param idempotency_key Key of the run (at most 200 characters), stable
#'   for one execution. API field `idempotency_key`.
#' @param input_release_ids Ids of the source releases used by the
#'   execution (integer). API field `input_release_ids`.
#' @param parameters Parameters of the execution, a named list. API field `parameters`.
#' @param run_id The id of the run. API path parameter `{run_id}` of
#'   `POST /publications/{run_id}/complete` and `POST /publications/{run_id}/fail`.
#' @param diagnostics Diagnostics recorded with the closing, a named list. API field `diagnostics`.
#' @return The run: a list `run_id`, `product_version_id`, `product_code`,
#'   `version_code`, `status` (`running`, `completed`, `failed`),
#'   `idempotency_key`, `started_at`, `completed_at`, `parameters`,
#'   `diagnostics`, `input_release_ids`.
#' @family writing
#' @examples
#' \dontrun{
#' run <- soil_run_open(soil, v$product_version_id, "run-india-2026-10",
#'                      input_release_ids = c(12L, 14L),
#'                      parameters = list(country = "IND"))
#' # ... soil_publish_values(soil, run$run_id, ...) ...
#' soil_run_complete(soil, run$run_id)
#' }
#' @export
soil_run_open <- function(soil = soil_session(), product_version_id, idempotency_key,
                          input_release_ids = integer(), parameters = list()) {
  check_session(soil)
  soil_require_right(soil, "soil:publish", "`soil_run_open()`")
  id <- check_id(product_version_id, "product_version_id")
  releases <- suppressWarnings(as.integer(input_release_ids))
  if (anyNA(releases) || any(releases < 1L)) {
    abort(soilhub_argument_error(
      "`input_release_ids` must be positive whole numbers (the source releases used).",
      "input_release_ids"
    ))
  }
  body <- list(
    idempotency_key = check_idempotency_key(idempotency_key),
    input_release_ids = as.list(releases),
    parameters = json_object(parameters, "parameters")
  )
  run <- with_conflict_advice(
    soil_request(
      soil, "POST", paste0("/product-versions/", id, "/runs"),
      body = body, right = "soil:publish"
    ),
    paste0(
      "The idempotency key was already used for a run with other parameters or another ",
      "input snapshot (or a release id is unknown): use a new key for a new execution."
    )
  )
  run_object(run, "POST /product-versions/{id}/runs")
}

run_object <- function(run, context) {
  out <- typed_object(run, run_schema, context)
  out["input_release_ids"] <- list(as.integer(unlist(out$input_release_ids)))
  out
}

#' @rdname soil_run_open
#' @export
soil_run_complete <- function(soil = soil_session(), run_id, diagnostics = list()) {
  close_run(soil, run_id, "complete", diagnostics, "`soil_run_complete()`")
}

#' @rdname soil_run_open
#' @export
soil_run_fail <- function(soil = soil_session(), run_id, diagnostics = list()) {
  close_run(soil, run_id, "fail", diagnostics, "`soil_run_fail()`")
}

close_run <- function(soil, run_id, action, diagnostics, what) {
  check_session(soil)
  soil_require_right(soil, "soil:publish", what)
  id <- check_id(run_id, "run_id")
  body <- list(diagnostics = json_object(diagnostics, "diagnostics"))
  run <- with_conflict_advice(
    soil_request(
      soil, "POST", paste0("/publications/", id, "/", action),
      body = body, right = "soil:publish"
    ),
    paste0(
      "A closed run cannot change state, and a run with soil-health jobs that did not ",
      "complete cannot be completed: check its jobs with soil_job()."
    )
  )
  run_object(run, paste0("POST /publications/{run_id}/", action))
}
