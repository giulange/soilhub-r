# The default session

`soil_session()` returns the default session, the one used by every
function when `soil` is omitted; `soil_session(soil)` makes `soil` the
default.
[`soil_connect()`](https://giulange.github.io/soilhub-r/reference/soil_connect.md)
registers its session as the default unless `set_default = FALSE`;
[`soil_logout()`](https://giulange.github.io/soilhub-r/reference/soil_logout.md)
unregisters it. To work with two sessions at once (two users, or
production and a test API), pass them explicitly as the first argument.

## Usage

``` r
soil_session(soil = NULL)
```

## Arguments

- soil:

  A session to make the default, or `NULL` to get the current default.
  Client-side: not sent to the API.

## Value

The default session (`soil`, invisibly, when setting). Without a default
session, an error of class `soilhub_auth_error` with
`reason = "no_session"`.

## See also

[`soil_connect()`](https://giulange.github.io/soilhub-r/reference/soil_connect.md)

Other session:
[`soil_connect()`](https://giulange.github.io/soilhub-r/reference/soil_connect.md),
[`soil_login()`](https://giulange.github.io/soilhub-r/reference/soil_login.md),
[`soil_logout()`](https://giulange.github.io/soilhub-r/reference/soil_logout.md),
[`soil_whoami()`](https://giulange.github.io/soilhub-r/reference/soil_whoami.md)

## Examples

``` r
if (FALSE) { # \dontrun{
a <- soil_connect()                      # default
b <- soil_connect(api_url = "https://test.example.org/api/v1",
                  set_default = FALSE)   # explicit only
soil_whoami()                            # uses a
soil_whoami(b)
soil_session(b)                          # b becomes the default
} # }
```
