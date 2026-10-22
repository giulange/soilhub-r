# Connect to the Global Soil Data Hub

Creates a session: resolves the settings
([soilhub-config](https://giulange.github.io/soilhub-r/reference/soilhub-config.md)),
signs in with the device login of Keycloak (unless `login = FALSE`),
reads `/capabilities` and the identity carried by the token, and
registers the session as the default one so that `soil` can be omitted
in later calls.

## Usage

``` r
soil_connect(
  api_url = NULL,
  keycloak_url = NULL,
  client_id = NULL,
  login = TRUE,
  open_browser = interactive(),
  timeout = NULL,
  verbose = NULL,
  set_default = TRUE
)
```

## Arguments

- api_url:

  Base URL of the API (see
  [soilhub-config](https://giulange.github.io/soilhub-r/reference/soilhub-config.md)).
  Client-side: the base URL of every request, not sent to the API.

- keycloak_url:

  Keycloak realm URL. Client-side: used for the sign-in, not sent to the
  API.

- client_id:

  OIDC public client (`ams-r`). Client-side: used for the sign-in, not
  sent to the API.

- login:

  Sign in now (`TRUE`) or later with
  [`soil_login()`](https://giulange.github.io/soilhub-r/reference/soil_login.md).
  Client-side: not sent to the API.

- open_browser:

  Open the verification address in the browser. Client-side: not sent to
  the API.

- timeout:

  Total seconds allowed for each request. Client-side: not sent to the
  API.

- verbose:

  Verbosity: 0, 1 or 2 (see
  [soilhub-config](https://giulange.github.io/soilhub-r/reference/soilhub-config.md)).
  Client-side: not sent to the API.

- set_default:

  Register the session as the default session
  ([`soil_session()`](https://giulange.github.io/soilhub-r/reference/soil_session.md)).
  Client-side: not sent to the API.

## Value

A `soil_session`: a list with `api_url`, `keycloak_url`, `client_id`,
`timeout`, `verbose`, `dir`, `page_size`, `open_browser`, `created_at`
and `state`, an environment holding the tokens and their expiry, the
identity read from the token and the cached capabilities. Several
sessions can be used side by side by passing them explicitly.

## Details

**Device login.** The function prints a web address and a short code:
open the address in any browser (on the same computer or another one),
enter the code and sign in with your Global Soil Data Hub account. R
waits until the browser step is done. With `open_browser = TRUE` (the
default in interactive sessions) the address is also opened for you.

**Renewal.** The access token lasts a limited time (2 h for `ams-r`);
the session renews it automatically before it expires (by default 60 s
before, option `soilhub.refresh_margin`) and once more if the API
refuses it, so a session lasts hours without a new browser step. It ends
when Keycloak no longer renews it (idle or maximum session time reached,
session revoked): the next call then fails with `soilhub_auth_error`
(`reason = "session_expired"`) and `soil_login(soil)` signs in again on
the same session. When a renewal before the expiry is refused, a warning
(`soilhub_renewal_warning`) says when the session ends and the current
access token is used until then.

**Tokens.** Tokens are kept in memory only, never written to disk or
printed. Saving the session object
([`saveRDS()`](https://rdrr.io/r/base/readRDS.html), `.RData`) would
save them: do not save it;
[`soil_logout()`](https://giulange.github.io/soilhub-r/reference/soil_logout.md)
empties it.

Rights: none needed to connect. A user without `soil:summary` is warned
that discovery calls will be refused.

**Version check.** After the login the capabilities of the server are
read
([`soil_capabilities()`](https://giulange.github.io/soilhub-r/reference/soil_capabilities.md))
and checked: an API older than 0.5.0 or of another major version, or a
server lacking a capability every session needs, stops with a
`soilhub_capability_error`: no default session is registered and the
session, signed out, is in `e$session` for
[`soil_api_info()`](https://giulange.github.io/soilhub-r/reference/soil_api_info.md).
A minor version newer than the one the client is tested against
(`TESTED_API_VERSION`) only prints a message.

## See also

[`soil_login()`](https://giulange.github.io/soilhub-r/reference/soil_login.md),
[`soil_whoami()`](https://giulange.github.io/soilhub-r/reference/soil_whoami.md),
[`soil_session()`](https://giulange.github.io/soilhub-r/reference/soil_session.md),
[`soil_logout()`](https://giulange.github.io/soilhub-r/reference/soil_logout.md)

Other session:
[`soil_login()`](https://giulange.github.io/soilhub-r/reference/soil_login.md),
[`soil_logout()`](https://giulange.github.io/soilhub-r/reference/soil_logout.md),
[`soil_session()`](https://giulange.github.io/soilhub-r/reference/soil_session.md),
[`soil_whoami()`](https://giulange.github.io/soilhub-r/reference/soil_whoami.md)

## Examples

``` r
if (FALSE) { # \dontrun{
soil <- soil_connect()     # prints the address and the code, waits
soil
soil_whoami(soil)

# two steps
soil <- soil_connect(login = FALSE)
soil_login(soil)
} # }
```
