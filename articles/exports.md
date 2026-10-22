# Large selections and exports

``` r

library(soilhub)
```

[`soil_observations()`](https://giulange.github.io/soilhub-r/reference/soil_observations.md)
reads data directly into R. For very large selections (a whole dataset,
a continent) the hub prepares a **file** instead: an **export**. This
guide shows how to size a selection, what happens when it is too large,
and how to export, download and read the files. It assumes you have
signed in as shown in
[`vignette("soilhub", package = "soilhub")`](https://giulange.github.io/soilhub-r/articles/soilhub.md).
The outputs were recorded from the Global Soil Data Hub API in October
2026.

## The limits of the server

The server says how much it accepts in its capabilities:

``` r

limits <- soil_capabilities(soil)$limits
limits$max_sync_observations
#> [1] 1000000
limits$max_export_observations
#> [1] 10000000
```

- a direct read
  ([`soil_observations()`](https://giulange.github.io/soilhub-r/reference/soil_observations.md))
  may hold up to 1,000,000 observations (measured values);
- an export may hold up to 10,000,000.

## Size the selection first

[`soil_summary()`](https://giulange.github.io/soilhub-r/reference/soil_summary.md)
counts a selection without transferring it. For WoSIS in Kenya:

``` r

kenya <- soil_summary(soil, datasets = "wosis_points", country = "KEN")
kenya$observation_count
#> [1] 46429
```

About 46,000 observations: well below the limit, so a direct read works.
A rule of thumb: below about 200,000 observations read directly; above,
use an export (it is also the way to get files for a GIS).

## When a selection is too large

If you ask for too much, the server refuses and the package stops with
an error that explains what to do. Here we ask for every dataset of the
hub, with no filter. We use
[`tryCatch()`](https://rdrr.io/r/base/conditions.html) to keep the error
in a variable instead of stopping:

``` r

result <- tryCatch(
  soil_observations(soil, max_rows = 5),
  error = function(e) e
)
class(result)[1]
#> [1] "soilhub_load_limit_error"
```

The error is a `soilhub_load_limit_error`. Its message says why and
gives the way out:

``` r

cat(conditionMessage(result))
#> The selection holds more than 1,000,000 observations, above the limit of synchronous requests (1,000,000): narrow the selection (bbox, country, datasets, variables, layer, profile_type) or request an export (POST /exports).
#> To export the same selection: soil_export(soil, format = "gpkg")
#> or rerun with too_large = "export".
#> [HTTP 422, POST /query/observations, request id soilhub-20261022172750-70f03b98]
```

The selection holds more than a million observations. You can narrow it
(an area with `bbox` or `country`, fewer `datasets` or `variables`) or
export it.

## Export a selection

[`soil_export()`](https://giulange.github.io/soilhub-r/reference/soil_export.md)
sends the selection to the server, waits while the file is written,
downloads it and unzips it in a folder (`dir`). Here: WoSIS around
Vancouver (Canada) as CSV, checked every 2 seconds, saved in a temporary
folder (use your own folder, for example `dir = "exports"`).

``` r

vancouver <- c(-123.3, 49.0, -122.9, 49.4)
e <- soil_export(soil, datasets = "wosis_points", bbox = vancouver,
                 format = "csv", poll = 2, dir = tempdir())
```

``` r

e
#> <soil_export> exp_20261020_064345_9c0b4cf2
#>   Status:   completed (100%)
#>   Export:   format csv, content all, layout wide
#>   Selection: datasets wosis_points; bbox -123.3, 49, -122.9, 49.4
#>   Selected: 30 observations
#>   Written:  4 features, 12 observation rows, 30 observations
#>   Expires:  2026-10-27 06:43:45 UTC
#>   Zip:      /tmp/RtmpHIHIV0/exp_20261020_064345_9c0b4cf2.zip
#>   Dir:      /tmp/RtmpHIHIV0/exp_20261020_064345_9c0b4cf2
#>   Files:    features.csv, metadata.json, observations.csv
#>   Read with soil_export_read(x); cite with soil_citations(x).
```

The export is `completed`. It holds 4 features (profile sites) and 12
horizon rows, with 30 observations, in three files: the places
(`features.csv`), the measurements (`observations.csv`) and a
description (`metadata.json`). The **job id** (`exp_...`) identifies the
export; the file stays on the server for a week (`Expires`).

## Read the files back

[`soil_export_read()`](https://giulange.github.io/soilhub-r/reference/soil_export_read.md)
reads the measurements into a table, with the same columns as
[`soil_observations()`](https://giulange.github.io/soilhub-r/reference/soil_observations.md):

``` r

horizons <- soil_export_read(e)
nrow(horizons)
#> [1] 12
```

``` r

horizons[, c("horizon_name", "upper_depth_cm", "lower_depth_cm", "organic_carbon")]
#> # soilhub wide table: 12 horizons, 6 variables | wosis_points | view raw, layer all
#> # no API warnings (soil_warnings), typing (soil_columns), cite with soil_citations()
#>    horizon_name upper_depth_cm lower_depth_cm organic_carbon
#> 1             F              0              1          410.0
#> 2            Ae              1              2           80.0
#> 3            Bf              2             17           80.0
#> 4             F              0              1          412.0
#> 5            Ae              1              2           83.7
#> 6            Bf              2             17           79.8
#> 7             R             17            101            0.0
#> 8            Ap              0             20           20.3
#> 9            Bg             20             38            5.2
#> 10           Bc             38             53            4.6
#> # ... 2 more row(s)
```

Unlike the direct read of the other guides (limited to 5 rows), the
export holds **every** horizon of the selection: 12 horizons of 3
profiles.

The places are read with `what = "features"`:

``` r

places <- soil_export_read(e, what = "features")
nrow(places)
#> [1] 4
```

Four places but only three profiles with horizons: one site has no
measurements (see
[`vignette("first-layer", package = "soilhub")`](https://giulange.github.io/soilhub-r/articles/first-layer.md)).

As for any read,
[`soil_citations()`](https://giulange.github.io/soilhub-r/reference/soil_citations.md)
tells you what to cite:

``` r

soil_citations(horizons)$citation_text
#> [1] "Batjes NH, Calisto L and de Sousa LM, 2024. WoSIS-latest: Standardised world soil profile data. ISRIC Soil Data Hub resource identifier: https://tinyurl.com/39xhaa9d. Date downloaded: 15/01/2024."
```

## Export now, download later

A large export can take minutes. With `wait = FALSE` the function
returns at once; keep the job id, it is the only way to find the export
again (these calls are not run here).

``` r

e <- soil_export(soil, datasets = "wosis_points", country = "BRA",
                 format = "gpkg", wait = FALSE)
e$job_id
#> [1] "exp_20261020_..."
```

Later, even in another R session:

``` r

e <- soil_export_wait(soil, "exp_20261020_...")
e <- soil_export_download(soil, e, dir = "exports")
horizons <- soil_export_read(e)
```

## Files for a GIS

The formats are `"csv"`, `"tsv"`, `"geojson"`, `"gpkg"` (GeoPackage) and
`"shp"` (Shapefile, only for the places: `content = "features"`). The
GeoPackage and Shapefile need the package `sf` to be read in R, and open
directly in QGIS or ArcGIS (these calls are not run here):

``` r

gpkg <- soil_export(soil, datasets = "wosis_points", country = "KEN",
                    format = "gpkg", dir = "exports")

shp <- soil_export(soil, datasets = "wosis_points", country = "KEN",
                   format = "shp", content = "features", dir = "exports")
```

## Let the package switch to an export

With `too_large = "export"` a read that the server refuses as too large
is exported, downloaded and read back for you, with the same result as a
direct read (this call is not run here):

``` r

x <- soil_observations(soil, datasets = "wosis_points", too_large = "export")
```

If you already have the error,
[`soil_export_from_error()`](https://giulange.github.io/soilhub-r/reference/soil_export_from_error.md)
exports the same selection:

``` r

e <- soil_export_from_error(soil, result, format = "gpkg", dir = "exports")
```
