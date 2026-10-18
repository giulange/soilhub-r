# Sessions (design 3.1, 3.2, 3.5, 4.2): soil_connect, soil_login,
# soil_logout, soil_session (the default session) and the print method.

#' Connect to the Global Soil Data Hub
#'
#' Creates a session: resolves the settings ([soilhub-config]), signs in with
#' the device login of Keycloak (unless `login = FALSE`), reads
#' `/capabilities` and the identity carried by the token, and registers the
#' session as the default one so that `soil` can be omitted in later calls.
#'
#' **Device login.** The function prints a web address and a short code:
#' open the address in any browser (on the same computer or another one),
#' enter the code and sign in with your Global Soil Data Hub account. R waits
#' until the browser step is done. With `open_browser = TRUE` (the default in
#' interactive sessions) the address is also opened for you.
#'
#' **Renewal.** The access token lasts a limited time (2 h for `ams-r`); the
#' session renews it automatically before it expires (by default 60 s before,
#' option `soilhub.refresh_margin`) and once more if the API refuses it, so a
#' session lasts hours without a new browser step. It ends when Keycloak no
#' longer renews it (idle or maximum session time reached, session revoked):
#' the next call then fails with `soilhub_auth_error` (`reason =
#' "session_expired"`) and `soil_login(soil)` signs in again on the same
#' session. When a renewal before the expiry is refused, a warning
#' (`soilhub_renewal_warning`) says when the session ends and the current
#' access token is used until then.
#'
#' **Tokens.** Tokens are kept in memory only, never written to disk or
#' printed. Saving the session object (`saveRDS()`, `.RData`) would save
#' them: do not save it; [soil_logout()] empties it.
#'
#' Rights: none needed to connect. A user without `soil:summary` is warned
#' that discovery calls will be refused.
#'
#' @param api_url Base URL of the API (see [soilhub-config]).
#' @param keycloak_url Keycloak realm URL.
#' @param client_id OIDC public client (`ams-r`).
#' @param login Sign in now (`TRUE`) or later with [soil_login()].
#' @param open_browser Open the verification address in the browser.
#' @param timeout Total seconds allowed for each request.
#' @param verbose Verbosity: 0, 1 or 2 (see [soilhub-config]).
#' @param set_default Register the session as the default session
#'   ([soil_session()]).
#' @return A `soil_session`: a list with `api_url`, `keycloak_url`,
#'   `client_id`, `timeout`, `verbose`, `dir`, `page_size`, `open_browser`,
#'   `created_at` and `state`, an environment holding the tokens and their
#'   expiry, the identity read from the token and the cached capabilities.
#'   Several sessions can be used side by side by passing them explicitly.
#' @seealso [soil_login()], [soil_whoami()], [soil_session()],
#'   [soil_logout()]
#' @examples
#' \dontrun{
#' soil <- soil_connect()     # prints the address and the code, waits
#' soil
#' soil_whoami(soil)
#'
#' # two steps
#' soil <- soil_connect(login = FALSE)
#' soil_login(soil)
#' }
#' @export
soil_connect <- function(api_url = NULL, keycloak_url = NULL, client_id = NULL,
                         login = TRUE, open_browser = interactive(),
                         timeout = NULL, verbose = NULL, set_default = TRUE) {
  config <- soil_config(
    api_url = api_url, keycloak_url = keycloak_url, client_id = client_id,
    timeout = timeout, verbose = verbose
  )
  soil <- new_soil_session(config, open_browser = isTRUE(open_browser))
  if (isTRUE(login)) soil_login(soil)
  if (isTRUE(set_default)) soil_session(soil)
  soil
}

new_soil_session <- function(config, open_browser = FALSE) {
  state <- new.env(parent = emptyenv())
  structure(
    list(
      api_url = config$api_url,
      keycloak_url = config$keycloak_url,
      client_id = config$client_id,
      timeout = config$timeout,
      verbose = config$verbose,
      dir = config$dir,
      page_size = config$page_size,
      open_browser = open_browser,
      created_at = soil_now(),
      auth = session_auth,
      state = state
    ),
    class = "soil_session"
  )
}

check_session <- function(soil) {
  if (!inherits(soil, "soil_session")) {
    abort(soilhub_argument_error(
      "`soil` must be a session created by `soil_connect()`.",
      "soil"
    ))
  }
  invisible(soil)
}

#' Sign in, or sign in again
#'
#' Runs the device login of Keycloak on an existing session (see
#' [soil_connect()]): prints a web address and a code, waits for the browser
#' step, then reads `/capabilities` and the identity carried by the token.
#' Use it after `soil_connect(login = FALSE)`, or when a session has expired
#' (`soilhub_auth_error` with `reason = "session_expired"`): the session
#' object, and the default session, stay the same.
#'
#' When the session is still valid (or can be renewed) nothing is done unless
#' `force = TRUE`, which always opens a new browser login (for instance to
#' sign in as another user).
#'
#' @param soil A session; the default session when omitted.
#' @param force Open a new browser login even if the session is valid.
#' @return `soil`, invisibly.
#' @seealso [soil_connect()], [soil_logout()]
#' @examples
#' \dontrun{
#' soil <- soil_connect(login = FALSE)
#' soil_login(soil)
#' }
#' @export
soil_login <- function(soil = soil_session(), force = FALSE) {
  check_session(soil)
  state <- soil$state
  if (!isTRUE(force) && is_string(state$access_token)) {
    valid <- tryCatch(
      is_string(session_auth(soil)),
      soilhub_auth_error = function(e) FALSE
    )
    if (valid) {
      soil_inform(soil, 1, sprintf(
        "soilhub: already signed in as %s; use `force = TRUE` for a new login.",
        display_user(state$identity)
      ))
      return(invisible(soil))
    }
  }
  token <- tryCatch(
    device_login(soil, open_browser = isTRUE(soil$open_browser)),
    interrupt = function(e) {
      abort(soilhub_auth_error(
        "The login was interrupted before the browser step was completed: run `soil_login(soil)` to try again.",
        reason = "login_denied"
      ))
    }
  )
  store_tokens(soil, token)
  after_login(soil)
  invisible(soil)
}

# After a device login: read /capabilities (the audience of the rights; the
# version gate is added with capabilities.R), decode the identity, warn a
# user without `soil:summary`.
after_login <- function(soil) {
  state <- soil$state
  capabilities <- tryCatch(
    soil_request(soil, "GET", "/capabilities"),
    soilhub_error = function(e) e
  )
  failure <- NULL
  if (inherits(capabilities, "soilhub_error")) {
    failure <- capabilities
  } else if (is.list(capabilities)) {
    state$capabilities <- capabilities
  }
  identity <- update_identity(soil)

  if (isTRUE(identity$rights_known) && !"soil:summary" %in% identity$roles) {
    soilhub_warning(sprintf(
      paste0(
        "Your account has no right `soil:summary` (rights: %s): discovery calls ",
        "(soil_datasets(), soil_variables(), soil_summary(), ...) will be refused."
      ),
      if (length(identity$roles)) paste(identity$roles, collapse = ", ") else "none"
    ), "soilhub_rights_warning")
  } else if (!is.null(failure)) {
    soilhub_warning(sprintf(
      "Could not read /capabilities after the login (%s); rights are read for the audience `%s`.",
      conditionMessage(failure), identity$audience
    ), "soilhub_capabilities_warning")
  }
  soil_inform(soil, 1, sprintf(
    "soilhub: signed in as %s (rights: %s); the access token is valid for %s.",
    display_user(identity),
    if (!isTRUE(identity$rights_known)) "decided by the server" else if (length(identity$roles)) paste(identity$roles, collapse = ", ") else "none",
    format_duration(token_remaining(state))
  ))
  invisible(soil)
}

display_user <- function(identity) {
  name <- if (is.list(identity)) identity$username else NA
  if (is_string(name)) name else "(unnamed user)"
}

#' Sign out
#'
#' Drops the tokens of the session from memory (nothing is sent to Keycloak)
#' and, if it is the default session, unregisters it. The session object can
#' be signed in again with [soil_login()].
#'
#' @param soil A session; the default session when omitted.
#' @return `NULL`, invisibly.
#' @seealso [soil_connect()], [soil_session()]
#' @examples
#' \dontrun{
#' soil_logout(soil)
#' }
#' @export
soil_logout <- function(soil = soil_session()) {
  check_session(soil)
  state <- soil$state
  clear_tokens(state)
  state$identity <- NULL
  state$ended <- NULL
  state$renewal_failed <- NULL
  state$last_renewed_at <- NULL
  state$renewals <- NULL
  state$signed_out <- TRUE
  if (is_default_session(soil)) options(soilhub.session = NULL)
  invisible(NULL)
}

is_default_session <- function(soil) {
  current <- getOption("soilhub.session")
  inherits(current, "soil_session") && identical(current$state, soil$state)
}

#' The default session
#'
#' `soil_session()` returns the default session, the one used by every
#' function when `soil` is omitted; `soil_session(soil)` makes `soil` the
#' default. [soil_connect()] registers its session as the default unless
#' `set_default = FALSE`; [soil_logout()] unregisters it. To work with two
#' sessions at once (two users, or production and a test API), pass them
#' explicitly as the first argument.
#'
#' @param soil A session to make the default, or `NULL` to get the current
#'   default.
#' @return The default session (`soil`, invisibly, when setting). Without a
#'   default session, an error of class `soilhub_auth_error` with
#'   `reason = "no_session"`.
#' @seealso [soil_connect()]
#' @examples
#' \dontrun{
#' a <- soil_connect()                      # default
#' b <- soil_connect(api_url = "https://test.example.org/api/v1",
#'                   set_default = FALSE)   # explicit only
#' soil_whoami()                            # uses a
#' soil_whoami(b)
#' soil_session(b)                          # b becomes the default
#' }
#' @export
soil_session <- function(soil = NULL) {
  if (!is.null(soil)) {
    check_session(soil)
    options(soilhub.session = soil)
    return(invisible(soil))
  }
  current <- getOption("soilhub.session")
  if (inherits(current, "soil_session")) return(current)
  abort(soilhub_auth_error(
    "There is no default session: run `soil <- soil_connect()` first, or pass a session as `soil`.",
    reason = "no_session"
  ))
}

#' @export
format.soil_session <- function(x, ...) {
  state <- x$state
  identity <- if (is.environment(state)) state$identity else NULL
  capabilities <- if (is.environment(state)) state$capabilities else NULL
  version <- if (is.list(capabilities) && is_string(capabilities$api_version)) {
    sprintf(" (API %s)", capabilities$api_version)
  } else {
    ""
  }
  lines <- c(
    "<soil_session>",
    sprintf("  API:      %s%s", x$api_url, version),
    sprintf("  Keycloak: %s, client %s", x$keycloak_url, x$client_id)
  )
  status <- session_status(x)
  if (status == "signed_in") {
    rights <- if (!isTRUE(identity$rights_known)) {
      "not declared in the token; the API decides"
    } else if (length(identity$roles)) {
      paste(identity$roles, collapse = ", ")
    } else {
      "none"
    }
    remaining <- token_remaining(state)
    token <- if (is.na(remaining)) {
      "valid (expiry unknown)"
    } else if (remaining > 0) {
      sprintf("valid for %s", format_duration(remaining))
    } else {
      "expired"
    }
    if (!is_string(state$refresh_token)) {
      token <- paste0(token, ", not renewable")
    } else if (!is.null(state$refresh_expires_at) && !all(is.na(state$refresh_expires_at))) {
      token <- paste0(token, sprintf(
        ", renewable for %s",
        format_duration(as.numeric(difftime(state$refresh_expires_at, soil_now(), units = "secs")))
      ))
    }
    if ((state$renewals %||% 0L) > 0L) {
      token <- paste0(token, sprintf(", renewed %d time(s)", state$renewals))
    }
    lines <- c(lines,
      sprintf("  User:     %s", display_user(identity)),
      sprintf("  Rights:   %s", rights),
      sprintf("  Token:    %s", token)
    )
  } else {
    lines <- c(lines, sprintf("  Status:   %s", switch(status,
      expired = "session expired; run soil_login(soil) to sign in again",
      signed_out = "signed out; run soil_login(soil) to sign in",
      "not signed in; run soil_login(soil)"
    )))
  }
  lines <- c(lines, sprintf("  Default:  %s", if (is_default_session(x)) "yes" else "no"))
  lines
}

#' @export
print.soil_session <- function(x, ...) {
  cat(format(x, ...), sep = "\n")
  invisible(x)
}

session_status <- function(soil) {
  state <- soil$state
  if (!is.environment(state)) return("not_signed_in")
  if (is_string(state$access_token)) return("signed_in")
  if (!is.null(state$ended)) return("expired")
  if (isTRUE(state$signed_out)) return("signed_out")
  "not_signed_in"
}
