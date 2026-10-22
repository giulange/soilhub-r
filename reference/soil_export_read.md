# Read the files of an export

Reads the tables of an export back into R, typed as the synchronous
reads type them: `metadata.json` is read first and drives the typing.
The wide observations are typed as
[`soil_observations()`](https://giulange.github.io/soilhub-r/reference/soil_observations.md)
types them (fixed columns, markings and list columns; a variable column
is numeric when `wide_columns` says so, `<key>_n` integer, a multi-value
WoSIS cell gives the mean of its values in `<key>` and the values in
`<key>_values`); the long observations as the long layout; the features
as
[`soil_features()`](https://giulange.github.io/soilhub-r/reference/soil_features.md).
Values written as JSON text by the flat formats (CSV, TSV, GeoPackage:
`value_flags`, `cell_markings`, `profile_markings`, `components`, ...)
are parsed back to list columns. The result is a `soil_table` whose
metadata has the shape of a synchronous read (with `via_export`, the job
id, and `export`: format, content, layout, records, files, the variables
of the selection), so
[`soil_citations()`](https://giulange.github.io/soilhub-r/reference/soil_citations.md),
[`soil_revised_rules()`](https://giulange.github.io/soilhub-r/reference/soil_revised_rules.md)
and
[`soil_columns()`](https://giulange.github.io/soilhub-r/reference/soil_columns.md)
work on it.

## Usage

``` r
soil_export_read(x, what = c("observations", "features", "metadata", "all"))
```

## Arguments

- x:

  A `soil_export` (downloaded), the path of an export zip, or the
  directory it was unzipped into. Client-side: not sent to the API.

- what:

  `"observations"` (the default; for an export of `content = "features"`
  the features), `"features"`, `"metadata"` (the parsed `metadata.json`)
  or `"all"` (a list `features`, `observations`, `metadata`).
  Client-side: not sent to the API.

## Value

A `soil_table` (`soil_layout` `"wide"`, `"long"` or `"features"`; an
`sf` object for the features when `sf` is installed), the metadata list,
or a list of them.

## Details

Formats and packages: CSV, TSV and GeoJSON need no package; GeoPackage
and Shapefile need `sf`. The features are an `sf` object (EPSG:4326)
when `sf` is installed; without it the features of a CSV/TSV export keep
their WKT in `geometry_wkt` and those of a GeoJSON export their GeoJSON
in `geometry_text`. Shapefile fields are cut to 10 characters and 254
characters of text by the format: the known names are restored, the
nested values stay text.

Empty fields of CSV and TSV are `NA` (the API writes null as an empty
field). In the long layout `value_raw` of a CSV/TSV export is the JSON
value of the cell text (a number when the text is a number).

No network, no right needed.

## See also

Other exports:
[`soil_export()`](https://giulange.github.io/soilhub-r/reference/soil_export.md),
[`soil_export_from_error()`](https://giulange.github.io/soilhub-r/reference/soil_export_from_error.md),
[`soil_export_status()`](https://giulange.github.io/soilhub-r/reference/soil_export_status.md)

## Examples

``` r
if (FALSE) { # \dontrun{
x <- soil_export(soil, datasets = "wosis_points", country = "KEN", format = "csv")
obs <- soil_export_read(x)
soil_columns(obs)
f <- soil_export_read(x, "features")
soil_export_read("exports/exp_20261019_101500_1a2b3c4d.zip", "metadata")$records
} # }
```
