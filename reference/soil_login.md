# Sign in, or sign in again

Runs the device login of Keycloak on an existing session (see
[`soil_connect()`](https://giulange.github.io/soilhub-r/reference/soil_connect.md)):
prints a web address and a code, waits for the browser step, then reads
`/capabilities` and the identity carried by the token. Use it after
`soil_connect(login = FALSE)`, or when a session has expired
(`soilhub_auth_error` with `reason = "session_expired"`): the session
object, and the default session, stay the same.

## Usage

``` r
soil_login(soil = soil_session(), force = FALSE)
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

- force:

  Open a new browser login even if the session is valid. Client-side:
  not sent to the API.

## Value

`soil`, invisibly.

## Details

When the session is still valid (or can be renewed) nothing is done
unless `force = TRUE`, which always opens a new browser login (for
instance to sign in as another user).

## See also

[`soil_connect()`](https://giulange.github.io/soilhub-r/reference/soil_connect.md),
[`soil_logout()`](https://giulange.github.io/soilhub-r/reference/soil_logout.md)

Other session:
[`soil_connect()`](https://giulange.github.io/soilhub-r/reference/soil_connect.md),
[`soil_logout()`](https://giulange.github.io/soilhub-r/reference/soil_logout.md),
[`soil_session()`](https://giulange.github.io/soilhub-r/reference/soil_session.md),
[`soil_whoami()`](https://giulange.github.io/soilhub-r/reference/soil_whoami.md)

## Examples

``` r
if (FALSE) { # \dontrun{
soil <- soil_connect(login = FALSE)
soil_login(soil)
} # }
```
