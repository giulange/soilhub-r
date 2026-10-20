# Identity and rights (design 1.3, 4.2, 4.6).
#
# The API has no "who am I" endpoint: the client decodes the payload of its
# own access token (a JWT; base64url, no signature check: it only reads what
# the API will read) and takes `resource_access[[audience]]$roles`,
# `preferred_username`, `sub` and `exp`. The audience comes from
# `GET /capabilities` `authentication.audience` (`soil-api` when unknown).
#
# Rights are "known" only when the token carries a `resource_access` block
# with an entry for the API audience (Keycloak client roles today). A token
# without it -- no `resource_access` at all (a future shape under the PDP) or
# no entry for the audience (a PDP may grant rights that are not Keycloak
# client roles) -- leaves the rights undeclared: the advisory pre-check is
# skipped and the API decides, so no code change is needed the day the token
# changes shape.

default_audience <- "soil-api"

#' Rights and the functions that need them
#'
#' The package constant mapping each right of the Global Soil Data Hub API to
#' the functions that need it (design 4.6); used by [soil_whoami()] and by
#' the permission pre-check of the write functions.
#' @keywords internal
#' @noRd
.rights <- list(
  "soil:summary" = c(
    "soil_capabilities", "soil_datasets", "soil_dataset", "soil_citations",
    "soil_licences", "soil_formats", "soil_variables",
    "soil_variable_mappings", "soil_countries", "soil_country",
    "soil_code_lists", "soil_code_list", "soil_ttr_flag_legend",
    "soil_summary", "soil_availability", "soil_consistency",
    "soil_values_summary", "soil_health_summary"
  ),
  "soil:read" = c(
    "soil_observations", "soil_features", "soil_values",
    "soil_health_scores", "soil_resolve_targets", "soil_ttr_flags",
    "soil_export", "soil_export_status", "soil_export_wait",
    "soil_export_download", "soil_export_from_error"
  ),
  "soil:publish" = c(
    "soil_run_open", "soil_run_complete", "soil_run_fail",
    "soil_publish_values", "soil_publish_health", "soil_publish_source",
    "soil_source_validate", "soil_source_promote", "soil_job",
    "soil_job_wait", "soil_job_cancel", "soil_export_cancel"
  ),
  "soil:admin" = c(
    "soil_register_variable", "soil_product", "soil_product_version",
    "soil_refresh_countries"
  )
)

# ---------------------------------------------------------------------------
# JWT payload and identity.

#' Decode the payload of a JWT
#'
#' @param token An access token.
#' @return The payload as a named list, or `NULL` when `token` is not a JWT
#'   with a JSON payload (an opaque token).
#' @keywords internal
#' @noRd
jwt_payload <- function(token) {
  if (!is_string(token)) return(NULL)
  parts <- strsplit(token, ".", fixed = TRUE)[[1]]
  if (length(parts) < 2L || !nzchar(parts[2])) return(NULL)
  payload <- tryCatch(
    jsonlite::fromJSON(rawToChar(base64url_decode(parts[2])), simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (!is.list(payload) || is.null(names(payload))) return(NULL)
  payload
}

#' What an access token says about its user
#'
#' @param token An access token.
#' @param audience The API audience (client id of the resource server), or
#'   `NA` when rights are not carried by the token (authentication disabled).
#' @return A list: `username`, `subject`, `audience`, `roles` (character,
#'   sorted), `rights_known` (TRUE when the token has a `resource_access`
#'   entry for `audience`), `token_exp` (the `exp` claim, POSIXct).
#' @keywords internal
#' @noRd
token_identity <- function(token, audience = default_audience) {
  payload <- jwt_payload(token)
  access <- payload$resource_access
  rights_known <- is.list(access) && is_string(audience) &&
    is.list(access[[audience]])
  roles <- if (rights_known) {
    sort(unique(as.character(unlist(access[[audience]]$roles))))
  } else {
    character()
  }
  claim <- function(name) {
    value <- payload[[name]]
    if (is_string(value)) value else NA_character_
  }
  list(
    username = claim("preferred_username"),
    subject = claim("sub"),
    audience = if (is_string(audience)) audience else NA_character_,
    roles = roles,
    rights_known = rights_known,
    token_exp = if (is.numeric(payload$exp)) as_utc(payload$exp) else as_utc(NA)
  )
}

# The audience of the API: `authentication.audience` of the cached
# capabilities, NA when the deployment has authentication disabled, else the
# default `soil-api`.
session_audience <- function(soil) {
  capabilities <- session_cached(soil, "capabilities")
  authentication <- if (is.list(capabilities)) capabilities$authentication else NULL
  if (is.list(authentication)) {
    if (isFALSE(authentication$enabled)) return(NA_character_)
    if (is_string(authentication$audience)) return(authentication$audience)
  }
  default_audience
}

update_identity <- function(soil) {
  state <- soil$state
  state$identity <- token_identity(state$access_token, session_audience(soil))
  invisible(state$identity)
}

# A cached element of a session: from its state environment (a
# `soil_session`), else from the list itself (the session-like lists of the
# HTTP tests).
session_cached <- function(soil, name) {
  if (!is.list(soil)) return(NULL)
  state <- soil[["state"]]
  if (is.environment(state) && !is.null(state[[name]])) return(state[[name]])
  soil[[name]]
}

# The rights of a session when known (character), else NULL.
session_rights <- function(soil) {
  identity <- session_cached(soil, "identity")
  if (!is.list(identity)) return(NULL)
  if (isTRUE(identity$rights_known)) return(identity$roles)
  # `[[` (not `$`): `$rights` would partially match `rights_known`
  identity[["rights"]]
}

normalise_right <- function(right) {
  if (!is_string(right)) {
    abort(soilhub_argument_error("`right` must be a right name such as \"soil:read\".", "right"))
  }
  if (!grepl(":", right, fixed = TRUE)) right <- paste0("soil:", right)
  right
}

format_rights <- function(rights, audience = default_audience) {
  if (length(rights) == 0L) {
    return(sprintf("no right of `%s`", if (is_string(audience)) audience else default_audience))
  }
  paste0("`", rights, "`", collapse = ", ")
}

#' Pre-check a right before a request
#'
#' Advisory (design 1.3): when the session's token carries its rights, a
#' missing right raises `soilhub_permission_error` before anything is sent;
#' when the token does not declare them (no `resource_access` entry for the
#' API audience, or no identity) nothing is checked and the API decides.
#'
#' @param soil The session.
#' @param right The right, `"soil:admin"` or `"admin"`.
#' @param what The operation, for the message (e.g. "`soil_product()`").
#' @return `TRUE` invisibly when the right is held, `NA` when not checked.
#' @keywords internal
#' @noRd
soil_require_right <- function(soil, right, what = NULL) {
  right <- normalise_right(right)
  identity <- session_cached(soil, "identity")
  if (!is.list(identity) || !isTRUE(identity$rights_known)) {
    return(invisible(NA))
  }
  if (right %in% identity$roles) return(invisible(TRUE))
  abort(soilhub_permission_error(
    sprintf(
      "%s needs the right `%s`; your session has %s.",
      what %||% "This operation", right,
      format_rights(identity$roles, identity$audience)
    ),
    required_right = right, rights = identity$roles
  ))
}

# ---------------------------------------------------------------------------
# soil_whoami()

#' Who is signed in, and what they may do
#'
#' Reads the identity of the session from its access token, without any
#' request: user name, subject, the rights (Keycloak client roles of the
#' API audience, e.g. `soil:read`), what they allow, the limits advertised by
#' the server and how long the session lasts.
#'
#' The API has no identity endpoint: rights are read from the token payload
#' (`resource_access[[audience]]$roles`), as the API reads them; the audience
#' comes from [soil_connect()]'s reading of `/capabilities`
#' (`authentication.audience`, `soil-api`). When the token has no
#' `resource_access` entry for the audience (no block at all, or a block
#' without the audience, as with rights granted by a policy decision point)
#' the rights are "not declared in the token; the API decides" (`can` is
#' `NA`), and no local check is made before a request.
#'
#' Rights and functions:
#' * `soil:summary` -- discovery and catalog, summaries, availability,
#'   consistency;
#' * `soil:read` -- observations, features, values, health scores, exports;
#' * `soil:publish` -- runs, publications, source ingest, jobs;
#' * `soil:admin` -- variables, products, versions, country refresh.
#'
#' @param soil A session from [soil_connect()]; the default session when
#'   omitted. Client-side: not sent to the API.
#' @return A `soil_identity` list: `username`, `subject`, `audience`, `roles`
#'   (character), `rights_known`, `can` (named logical: `summary`, `read`,
#'   `publish`, `admin`; `NA` when the rights are not declared in the
#'   token), `limits` (the
#'   `limits` of `/capabilities`, advertised by the server for this
#'   deployment, `NULL` when not read), `token_expires_at`,
#'   `session_expires_at` (expiry of the refresh token, `NA` when unknown),
#'   `session_renewable`, `last_renewed_at`, `renewals` and `status`
#'   (`"signed_in"` or `"expired"`).
#' @family session
#' @seealso [soil_connect()], [soil_session()]
#' @examples
#' \dontrun{
#' soil <- soil_connect()
#' me <- soil_whoami(soil)
#' me$can
#' me$token_expires_at
#' }
#' @export
soil_whoami <- function(soil = soil_session()) {
  check_session(soil)
  state <- soil$state
  identity <- state$identity
  if (!is.list(identity)) {
    abort(soilhub_auth_error(
      "This session is not signed in: run `soil_login(soil)`.",
      reason = "not_logged_in"
    ))
  }
  can <- vapply(
    c(summary = "soil:summary", read = "soil:read", publish = "soil:publish", admin = "soil:admin"),
    function(right) if (isTRUE(identity$rights_known)) right %in% identity$roles else NA,
    logical(1)
  )
  signed_in <- is_string(state$access_token)
  now <- soil_now()
  session_expires_at <- if (signed_in) state$refresh_expires_at %||% NA else NA
  renewable <- signed_in && is_string(state$refresh_token) &&
    (all(is.na(session_expires_at)) || session_expires_at > now)
  capabilities <- state$capabilities
  structure(
    list(
      username = identity$username,
      subject = identity$subject,
      audience = identity$audience,
      roles = identity$roles,
      rights_known = identity$rights_known,
      can = can,
      limits = if (is.list(capabilities)) capabilities$limits else NULL,
      token_expires_at = if (signed_in) as_utc(as.numeric(state$expires_at)) else as_utc(NA),
      session_expires_at = as_utc(as.numeric(session_expires_at)),
      session_renewable = renewable,
      last_renewed_at = if (is.null(state$last_renewed_at)) as_utc(NA) else as_utc(as.numeric(state$last_renewed_at)),
      renewals = state$renewals %||% 0L,
      status = if (signed_in) "signed_in" else "expired"
    ),
    class = "soil_identity"
  )
}

#' @export
print.soil_identity <- function(x, ...) {
  now <- soil_now()
  cat("<soil_identity> ", if (is.na(x$username)) "(no user name in the token)" else x$username, "\n", sep = "")
  if (!is.na(x$subject)) cat("  Subject: ", x$subject, "\n", sep = "")
  if (isTRUE(x$rights_known)) {
    cat("  Rights:  ", if (length(x$roles)) paste(x$roles, collapse = ", ") else "none",
        " (audience ", x$audience, ")\n", sep = "")
  } else {
    cat("  Rights:  not declared in the token; the API decides\n")
  }
  if (identical(x$status, "signed_in")) {
    cat("  Token:   valid for ", format_duration(as.numeric(difftime(x$token_expires_at, now, units = "secs"))),
        " (until ", format_time(x$token_expires_at), ")\n", sep = "")
    renew <- if (!isTRUE(x$session_renewable)) {
      "not renewable: sign in again with soil_login() at expiry"
    } else if (is.na(x$session_expires_at)) {
      "renewable"
    } else {
      sprintf("renewable until %s", format_time(x$session_expires_at))
    }
    cat("  Session: ", renew, if (x$renewals > 0) sprintf(", renewed %d time(s)", x$renewals) else "", "\n", sep = "")
  } else {
    cat("  Session: expired; run soil_login(soil) to sign in again\n")
  }
  cat("  Functions by right:\n")
  for (right in names(.rights)) {
    short <- sub("^soil:", "", right)
    allowed <- x$can[[short]]
    mark <- if (is.na(allowed)) "?  " else if (allowed) "yes" else "no "
    text <- paste0(.rights[[right]], "()", collapse = ", ")
    lines <- strwrap(text, width = 76, initial = sprintf("    %-13s %s ", right, mark), exdent = 22)
    cat(lines, sep = "\n")
  }
  if (is.list(x$limits) && length(x$limits)) {
    cat("  Limits advertised by the server for this deployment:\n")
    for (name in names(x$limits)) {
      value <- x$limits[[name]]
      if (is.null(value) || length(value) != 1L) next
      shown <- if (is.numeric(value)) format_count(value) else format(value)
      cat(sprintf("    %s: %s\n", name, shown))
    }
  }
  invisible(x)
}
