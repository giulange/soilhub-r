# Variable registration (design 4.6): validate, then register, through the
# API (never the database). Right `soil:admin`, capability
# `variable_registration`.

target_levels <- c("feature", "profile", "component", "horizon")
variable_value_types <- c("numeric", "text", "boolean", "json")

variable_registration_schema <- list(
  variable_id = "dbl", variable_code = "chr", name = "chr",
  description = "chr", domain_code = "chr", value_type = "chr",
  measurement_kind_code = "chr", allowed_target_levels = "chr_list",
  idempotent_replay = "lgl"
)

#' Register a variable
#'
#' Declares a new variable that products may publish (an output of an
#' external model, e.g. a soil-health score). The definition is first
#' validated by the API (`POST /variables/validate`: the domain and the
#' measurement kind must exist in the controlled vocabulary), then registered
#' (`POST /variables`). Variables carry no unit: the hub mirrors its sources
#' and converts nothing.
#'
#' Registration is idempotent: the same `idempotency_key` with the same
#' definition returns the variable already registered
#' (`idempotent_replay = TRUE`). A different definition under a key already
#' used, or a `variable_code` already registered with another definition, is
#' a `soilhub_conflict_error` (HTTP 409): choose a new key, or a new code.
#'
#' Rights: `soil:admin`. Capability: `variable_registration`.
#'
#' @param soil A session; the default session when omitted.
#' @param variable_code Code of the variable: lowercase letters, digits and
#'   `_` (e.g. `"soil_health_physical_score"`).
#' @param name Human name.
#' @param domain_code Domain of the controlled vocabulary (e.g. `"soil"`).
#' @param value_type Type of the published values: `"numeric"`, `"text"`,
#'   `"boolean"` or `"json"`.
#' @param measurement_kind_code Measurement kind of the controlled
#'   vocabulary (e.g. `"derived"`).
#' @param allowed_target_levels Levels a value may be attached to, one or
#'   more of `"feature"`, `"profile"`, `"component"`, `"horizon"`.
#' @param description Optional description.
#' @param idempotency_key Key of this registration (at most 200
#'   characters), stable for one definition.
#' @param validate_only Only validate: nothing is registered.
#' @return With `validate_only = TRUE`, the validation: a list `valid`,
#'   `variable_code`, `errors` (data frame). Otherwise the registered
#'   variable: a list `variable_id`, `variable_code`, `name`, `description`,
#'   `domain_code`, `value_type`, `measurement_kind_code`,
#'   `allowed_target_levels` (character), `idempotent_replay`. An invalid
#'   definition is a `soilhub_validation_error` whose `errors` lists the
#'   problems.
#' @family writing
#' @examples
#' \dontrun{
#' soil_register_variable(
#'   soil, "soil_health_physical_score", name = "Soil health, physical score",
#'   domain_code = "soil", value_type = "numeric",
#'   measurement_kind_code = "derived", allowed_target_levels = "horizon",
#'   idempotency_key = "var-soil-health-physical-v1"
#' )
#' }
#' @export
soil_register_variable <- function(soil = soil_session(), variable_code, name,
                                   domain_code,
                                   value_type = c("numeric", "text", "boolean", "json"),
                                   measurement_kind_code, allowed_target_levels,
                                   description = NULL, idempotency_key,
                                   validate_only = FALSE) {
  what <- "`soil_register_variable()`"
  check_session(soil)
  soil_require_right(soil, "soil:admin", what)
  body <- list(
    idempotency_key = check_idempotency_key(idempotency_key),
    variable_code = check_code(variable_code, "variable_code"),
    name = check_text(name, "name"),
    description = if (is.null(description)) NULL else check_text(description, "description"),
    domain_code = check_code(domain_code, "domain_code"),
    value_type = match_choice(value_type, variable_value_types, "value_type"),
    measurement_kind_code = check_code(measurement_kind_code, "measurement_kind_code"),
    allowed_target_levels = as.list(check_levels(allowed_target_levels, "allowed_target_levels"))
  )
  body <- body[!vapply(body, is.null, logical(1))]
  soil_require_capability(soil, "variable_registration", what)

  validation <- soil_request(soil, "POST", "/variables/validate", body = body, right = "soil:admin")
  errors <- validation_errors_frame(list(errors = validation$errors %||% list()))
  result <- list(
    valid = isTRUE(validation$valid),
    variable_code = validation$variable_code %||% variable_code,
    errors = errors
  )
  if (!result$valid) {
    abort(local_validation_error(
      sprintf("The definition of the variable `%s` is not valid.", variable_code),
      errors, endpoint = "/variables/validate",
      request_id = attr(validation, "request_id")
    ))
  }
  if (isTRUE(validate_only)) return(result)

  registered <- with_conflict_advice(
    soil_request(soil, "POST", "/variables", body = body, right = "soil:admin"),
    paste0(
      "The idempotency key was used for another definition, or `", variable_code,
      "` is registered with another definition: use a new idempotency key for a new ",
      "definition, or a new variable code (a registered variable is never redefined)."
    )
  )
  out <- typed_object(registered, variable_registration_schema, "POST /variables")
  if (isTRUE(out$idempotent_replay)) {
    soil_inform(soil, 1, sprintf(
      "soilhub: variable `%s` was already registered with this key and definition (idempotent replay).",
      out$variable_code
    ))
  }
  out
}

# ---------------------------------------------------------------------------
# Argument checks shared by the write functions.

check_code <- function(value, argument) {
  if (!is_string(value) || !grepl("^[a-z0-9_]+$", value)) {
    abort(soilhub_argument_error(
      sprintf(
        "`%s` must be a code of lowercase letters, digits and `_`, not %s.",
        argument, deparse_argument(value)
      ),
      argument
    ))
  }
  value
}

check_text <- function(value, argument) {
  if (!is_string(value)) {
    abort(soilhub_argument_error(
      sprintf("`%s` must be a non-empty string, not %s.", argument, deparse_argument(value)),
      argument
    ))
  }
  value
}

check_levels <- function(value, argument) {
  if (!is.character(value) || length(value) == 0L || anyNA(value) ||
      !all(value %in% target_levels)) {
    abort(soilhub_argument_error(
      sprintf(
        "`%s` must hold one or more of %s, not %s.",
        argument, paste0("\"", target_levels, "\"", collapse = ", "),
        deparse_argument(value)
      ),
      argument
    ))
  }
  sort(unique(value))
}

check_id <- function(value, argument) {
  number <- suppressWarnings(as.numeric(value))
  if (length(value) != 1L || is.na(number) || number < 1 || number != round(number)) {
    abort(soilhub_argument_error(
      sprintf("`%s` must be a positive whole number, not %s.", argument, deparse_argument(value)),
      argument
    ))
  }
  format(number, scientific = FALSE, trim = TRUE)
}

match_choice <- function(value, choices, argument) {
  if (identical(value, choices)) return(choices[1])
  if (!is_string(value) || !value %in% choices) {
    abort(soilhub_argument_error(
      sprintf(
        "`%s` must be one of %s, not %s.",
        argument, paste0("\"", choices, "\"", collapse = ", "), deparse_argument(value)
      ),
      argument
    ))
  }
  value
}

# A validation error found without an HTTP error status: a `valid = false`
# answer of a validate endpoint, or the local checks of the records.
local_validation_error <- function(message, errors, endpoint = NULL,
                                   request_id = NULL) {
  soilhub_api_error(
    paste0(message, errors_summary(errors),
           request_suffix(NULL, if (is.null(endpoint)) NULL else "POST", endpoint, request_id)),
    status = NULL, endpoint = endpoint, request_id = request_id,
    code = "validation_failed", errors = errors, subclass = "validation"
  )
}
