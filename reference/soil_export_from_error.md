# Export the selection of a refused read

A synchronous read above the limit (`limits$max_sync_observations`)
raises a `soilhub_load_limit_error` that carries its selection. This
submits the same selection as an export: the observations in the layout
of the refused read for
[`soil_observations()`](https://giulange.github.io/soilhub-r/reference/soil_observations.md),
the features (`content = "features"`) for
[`soil_features()`](https://giulange.github.io/soilhub-r/reference/soil_features.md).
It is the manual form of `too_large = "export"`, for an error caught
earlier.

## Usage

``` r
soil_export_from_error(soil = soil_session(), error, format = "gpkg", ...)
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

- error:

  The `soilhub_load_limit_error` of a read (`channel = "sync"`).
  Client-side: not sent to the API.

- format:

  The export format (see
  [`soil_export()`](https://giulange.github.io/soilhub-r/reference/soil_export.md)).
  API field `format`.

- ...:

  Other arguments of
  [`soil_export()`](https://giulange.github.io/soilhub-r/reference/soil_export.md)
  (`content`, `layout`, `wait`, `timeout`, `dir`, ...; a selection
  argument given here replaces the error's). Each is sent, or not, as
  described for
  [`soil_export()`](https://giulange.github.io/soilhub-r/reference/soil_export.md)
  (API fields of `POST /exports`, or client-side).

## Value

A `soil_export` (see
[`soil_export()`](https://giulange.github.io/soilhub-r/reference/soil_export.md)).

## Details

Rights: `soil:read`.

## See also

Other exports:
[`soil_export()`](https://giulange.github.io/soilhub-r/reference/soil_export.md),
[`soil_export_read()`](https://giulange.github.io/soilhub-r/reference/soil_export_read.md),
[`soil_export_status()`](https://giulange.github.io/soilhub-r/reference/soil_export_status.md)

## Examples

``` r
if (FALSE) { # \dontrun{
e <- tryCatch(soil_observations(soil, datasets = "wosis_points"),
              soilhub_load_limit_error = function(e) e)
x <- soil_export_from_error(soil, e, format = "csv")
obs <- soil_export_read(x)
} # }
```
