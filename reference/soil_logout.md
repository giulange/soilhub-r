# Sign out

Drops the tokens of the session from memory (nothing is sent to
Keycloak) and, if it is the default session, unregisters it. The session
object can be signed in again with
[`soil_login()`](https://giulange.github.io/soilhub-r/reference/soil_login.md).

## Usage

``` r
soil_logout(soil = soil_session())
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

## Value

`NULL`, invisibly.

## See also

[`soil_connect()`](https://giulange.github.io/soilhub-r/reference/soil_connect.md),
[`soil_session()`](https://giulange.github.io/soilhub-r/reference/soil_session.md)

Other session:
[`soil_connect()`](https://giulange.github.io/soilhub-r/reference/soil_connect.md),
[`soil_login()`](https://giulange.github.io/soilhub-r/reference/soil_login.md),
[`soil_session()`](https://giulange.github.io/soilhub-r/reference/soil_session.md),
[`soil_whoami()`](https://giulange.github.io/soilhub-r/reference/soil_whoami.md)

## Examples

``` r
if (FALSE) { # \dontrun{
soil_logout(soil)
} # }
```
