# Who is signed in, and what they may do

Reads the identity of the session from its access token, without any
request: user name, subject, the rights (Keycloak client roles of the
API audience, e.g. `soil:read`), what they allow, the limits advertised
by the server and how long the session lasts.

## Usage

``` r
soil_whoami(soil = soil_session())
```

## Arguments

- soil:

  A session from
  [`soil_connect()`](https://giulange.github.io/soilhub-r/reference/soil_connect.md);
  the default session when omitted. Client-side: not sent to the API.

## Value

A `soil_identity` list: `username`, `subject`, `audience`, `roles`
(character), `rights_known`, `can` (named logical: `summary`, `read`,
`publish`, `admin`; `NA` when the rights are not declared in the token),
`limits` (the `limits` of `/capabilities`, advertised by the server for
this deployment, `NULL` when not read), `token_expires_at`,
`session_expires_at` (expiry of the refresh token, `NA` when unknown),
`session_renewable`, `last_renewed_at`, `renewals` and `status`
(`"signed_in"` or `"expired"`).

## Details

The API has no identity endpoint: rights are read from the token payload
(`resource_access[[audience]]$roles`), as the API reads them; the
audience comes from
[`soil_connect()`](https://giulange.github.io/soilhub-r/reference/soil_connect.md)'s
reading of `/capabilities` (`authentication.audience`, `soil-api`). When
the token has no `resource_access` entry for the audience (no block at
all, or a block without the audience, as with rights granted by a policy
decision point) the rights are "not declared in the token; the API
decides" (`can` is `NA`), and no local check is made before a request.

Rights and functions:

- `soil:summary` – discovery and catalog, summaries, availability,
  consistency;

- `soil:read` – observations, features, values, health scores, exports;

- `soil:publish` – runs, publications, source ingest, jobs;

- `soil:admin` – variables, products, versions, country refresh.

## See also

[`soil_connect()`](https://giulange.github.io/soilhub-r/reference/soil_connect.md),
[`soil_session()`](https://giulange.github.io/soilhub-r/reference/soil_session.md)

Other session:
[`soil_connect()`](https://giulange.github.io/soilhub-r/reference/soil_connect.md),
[`soil_login()`](https://giulange.github.io/soilhub-r/reference/soil_login.md),
[`soil_logout()`](https://giulange.github.io/soilhub-r/reference/soil_logout.md),
[`soil_session()`](https://giulange.github.io/soilhub-r/reference/soil_session.md)

## Examples

``` r
if (FALSE) { # \dontrun{
soil <- soil_connect()
me <- soil_whoami(soil)
me$can
me$token_expires_at
} # }
```
