# Configuration of soilhub

Every setting is resolved with the precedence **explicit argument \>
[`options()`](https://rdrr.io/r/base/options.html) \> environment
variable \> built-in default**.

|  |  |  |  |  |
|----|----|----|----|----|
| Setting | Argument | Option | Environment variable | Default |
| API base URL | `api_url` | `soilhub.api_url` | `SOILHUB_API_URL` | `https://soilhub.weatherprogapp.it/api/v1` |
| Keycloak realm | `keycloak_url` | `soilhub.keycloak_url` | `SOILHUB_KEYCLOAK_URL` | `https://kc.weatherprogapp.it/realms/ams` |
| OIDC client | `client_id` | `soilhub.client_id` | `SOILHUB_CLIENT_ID` | `ams-r` |
| Request timeout (seconds) | `timeout` | `soilhub.timeout` | `SOILHUB_TIMEOUT` | 300 |
| Verbosity | `verbose` | `soilhub.verbose` | `SOILHUB_VERBOSE` | 1 when interactive, else 0 |
| Export directory | `dir` | `soilhub.export_dir` | `SOILHUB_EXPORT_DIR` | `file.path(tempdir(), "soilhub-exports")` |
| Page size | `page_size` | `soilhub.page_size` | – | the server's `max_page_size` (1000 when unknown) |
| Proactive refresh margin (seconds) | – | `soilhub.refresh_margin` | `SOILHUB_REFRESH_MARGIN` | 60 |

Verbosity levels: `0` silent; `1` user messages (pages read, retries,
session renewed, export progress); `2` also one line per HTTP request
(method, path, status, duration, request id), never headers, bodies or
tokens. `TRUE` means 1 and `FALSE` 0. Messages have class
`soilhub_message` and can be silenced with
[`suppressMessages()`](https://rdrr.io/r/base/message.html). A session
created without an explicit `verbose` follows `soilhub.verbose` at each
call, so `options(soilhub.verbose = 2)` turns request logging on for an
existing session.

The timeout is the total time allowed for one request (connection 10 s);
long pages over whole datasets take 40–90 s.

The refresh margin is how long before the expiry of the access token the
next request renews it (see
[`soil_connect()`](https://giulange.github.io/soilhub-r/reference/soil_connect.md));
it is read at each request, so it applies to existing sessions too. A
margin longer than the token lifetime renews the token before every
request.

The variable names of soilhub 0.1.x are read as a fallback, with a
one-time message: `SOIL_API_URL` for the API base URL,
`KEYCLOAK_TOKEN_URL` and `KEYCLOAK_DEVICE_URL` for the Keycloak realm
(the realm is the part before `/protocol/openid-connect/`).

## See also

Other configuration and errors:
[`soilhub-errors`](https://giulange.github.io/soilhub-r/reference/soilhub-errors.md)

## Examples

``` r
# Use a test API for the rest of the R session
old <- options(soilhub.api_url = "http://localhost:8000/api/v1")
options(old)

# Log every request
old <- options(soilhub.verbose = 2)
options(old)
```
