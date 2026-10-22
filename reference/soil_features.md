# Soil features: where the profiles and map units are

Reads the features of a selection from the canonical layer of the Global
Soil Data Hub (`POST /query/features`, always `canonical = true`), page
by page: one row per feature (a WoSIS, WISE or SOTER profile location, a
SOTER or SOTWIS map unit), with its geometry. The `feature_id` is the
one of
[`soil_observations()`](https://giulange.github.io/soilhub-r/reference/soil_observations.md)
read with the same selection, so features and measurements join by it
(`merge(features, observations, by = "feature_id")`).

## Usage

``` r
soil_features(
  soil = soil_session(),
  datasets = NULL,
  variables = NULL,
  bbox = NULL,
  country = NULL,
  geometry = "any",
  view = "raw",
  profile_type = NULL,
  components = NULL,
  min_cumulative_percent = NULL,
  with_geometry = c("sf", "text"),
  max_rows = Inf,
  page_size = NULL,
  too_large = c("stop", "export"),
  progress = interactive()
)
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

- datasets:

  Catalog dataset codes (`"wosis_points"`, `"wise_profiles"`,
  `"soter_profiles"`, `"soter_polygons"`, `"sotwis_polygons"`,
  `"sotwis_components"`, `"sotwis_estimates"`, see
  [`soil_datasets()`](https://giulange.github.io/soilhub-r/reference/soil_datasets.md));
  `NULL` (the API default) selects every dataset, usually above the
  limit of synchronous reads. API field `datasets`.

- variables:

  Source codes (`"ORGC"`, `"CLAY"`) or canonical property keys
  (`"organic_carbon"`), see
  [`soil_variables()`](https://giulange.github.io/soilhub-r/reference/soil_variables.md);
  `NULL` returns every variable. With `variables` the column set is
  fixed by the request, so every page has the same columns. API field
  `variables`.

- bbox:

  `c(xmin, ymin, xmax, ymax)` in WGS84 degrees (longitude, latitude).
  API field `bbox`.

- country:

  Countries as ISO 3166 alpha-2 or alpha-3 codes or names,
  case-insensitive (the API resolves them). API field `country`.

- geometry:

  `"any"`, `"point"` (profiles) or `"polygon"` (map units). API field
  `geometry`.

- view:

  `"raw"` or `"revised"`: with `"revised"` the features the rules of the
  revised view exclude (SOTER copy profiles whose original is in the
  selection, R8) are not returned, and the rules are listed in
  [`soil_revised_rules()`](https://giulange.github.io/soilhub-r/reference/soil_revised_rules.md).
  API field `view`.

- profile_type:

  Profiles by the source's own type term: `"synthetic"` (KENSOTER),
  `"virtual"` (Upper Tana), `"none"` (no type in the source record), all
  selecting or all excluded with a `"!"` prefix
  (`c("!synthetic", "!virtual")`); `NULL` keeps every profile. API field
  `profile_type`.

- components:

  Components of multi-component map units (SOTWIS, SOTER polygons):
  `NULL` (the API default, `"representative"`), `"representative"`
  (largest `proportion_percent`), `"all"`, or `"cumulative"` (by
  decreasing proportion until `min_cumulative_percent`). API field
  `components`.

- min_cumulative_percent:

  Threshold of `components = "cumulative"`, 0 to 100 (required with it,
  refused without it). API field `min_cumulative_percent`.

- with_geometry:

  `"sf"` (the default: an `sf` object, EPSG:4326; needs the package
  `sf`, else a `soilhub_dependency_error`) or `"text"` (a data frame
  with `geometry_text`, the GeoJSON of each feature: no package needed;
  [`sf::st_read()`](https://r-spatial.github.io/sf/reference/st_read.html)
  or `geojsonsf` read it). Client-side: not sent to the API (features
  always carry their GeoJSON geometry).

- max_rows:

  Maximum number of features to read (`Inf`: the whole selection).
  Client-side; caps the API field `limit` of each page request.

- page_size:

  Features per request; `NULL` uses the session's, the
  `soilhub.page_size` option or the server's `max_page_size`.
  Client-side; sets the API field `limit` of each page request.

- too_large:

  What to do when the API refuses the selection as too large for a
  synchronous read: `"stop"` raises `soilhub_load_limit_error`, whose
  message names the equivalent `soil_export(..., content = "features")`
  call; `"export"` exports the features of the selection (GeoJSON),
  waits, downloads, reads them back and returns the same shape, with
  `soil_metadata(x)$via_export` the job id. Client-side: not sent to the
  API.

- progress:

  Report the pages read (messages at verbosity 1 or more). Client-side:
  not sent to the API.

## Value

A `soil_table` with `soil_layout = "features"`: an `sf` object
(`with_geometry = "sf"`) or a data frame (`"text"`).

## Details

**Columns** (design 5.5), in the API's order: `dataset`,
`provider_code`, `feature_id`, `feature_key` (the canonical key: the
reference to the source record), `geometry_kind` (`POINT`, `POLYGON`,
`MULTIPOLYGON`), `source_support`; when SOTWIS or SOTER polygons are
selected `components` (a list of data frames, one row per selected soil
component of the map unit, in selection order: `component_id`,
`component_rank`, `proportion_percent`, `is_representative`, ..., and
`source_attributes`, the source descriptors of the component as a named
list); when `soter_profiles` is selected `profile_markings` (list of
character: `no_horizons_in_source` for a profile without horizons in the
source); `retired_in_release` (the release in which the feature left
ISRIC, still served); then the geometry: `geometry` (`sf`) or
`geometry_text` (GeoJSON text).

The API returns only features with a geometry; a feature served without
one gets an empty geometry (`sf`) or `NA` (`"text"`) and one warning.
`soil_metadata(x)` adds `feature_count`, `feature_count_by_dataset`
(when several datasets are selected) and `mixed_geometry` (points and
polygons in the result); `total_count` is `NA` (the API does not count
features; the summary of the selection does).

**Pages.** At most `max_page_size` features per request (1000, see
[`soil_capabilities()`](https://giulange.github.io/soilhub-r/reference/soil_capabilities.md));
a failure after some pages raises the error with the features already
read in `e$partial` (a `soil_table` whose metadata has
`complete = FALSE`).

Rights: `soil:read`. Capabilities: `canonical_features`; `revised_view`
for `view = "revised"`, `profile_type_filter` for `profile_type`,
`component_selection` for `components`.

## See also

[`soil_observations()`](https://giulange.github.io/soilhub-r/reference/soil_observations.md),
[`soil_citations()`](https://giulange.github.io/soilhub-r/reference/soil_citations.md)

Other reads:
[`soil_observations()`](https://giulange.github.io/soilhub-r/reference/soil_observations.md)

## Examples

``` r
if (FALSE) { # \dontrun{
soil <- soil_connect()
f <- soil_features(soil, datasets = "wosis_points", country = "KEN")
plot(sf::st_geometry(f))

# without sf: GeoJSON text
g <- soil_features(soil, datasets = "sotwis_polygons", country = "TUN",
                   with_geometry = "text")
g$components[[1]]
} # }
```
