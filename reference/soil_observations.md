# Soil observations: one row per horizon or per observation

Reads the measurements of a selection from the canonical layer of the
Global Soil Data Hub (`POST /query/observations`, always
`canonical = true`), page by page, and returns them as a typed table:
with `layout = "wide"` (the default) **one row per horizon** and one
group of columns per soil variable; with `layout = "long"` **one row per
observation** (one measured value).

## Usage

``` r
soil_observations(
  soil = soil_session(),
  datasets = NULL,
  variables = NULL,
  bbox = NULL,
  country = NULL,
  geometry = "any",
  layer = "all",
  view = "raw",
  profile_type = NULL,
  components = NULL,
  min_cumulative_percent = NULL,
  layout = c("wide", "long"),
  with_geometry = c("none", "sf", "text"),
  max_rows = Inf,
  offset = 0,
  page_size = NULL,
  too_large = c("stop", "export"),
  progress = interactive(),
  timeout = NULL
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

- layer:

  `"all"` horizons, or `"first"`: the first horizon(s) of each profile
  with `first_layer_status` and `profile_markings` (see
  [`soil_first_layer()`](https://giulange.github.io/soilhub-r/reference/soil_first_layer.md)).
  API field `layer`.

- view:

  `"raw"`: the ISRIC mirror as stored (sent explicitly); `"revised"`:
  the decided rules of the revised view applied by the API in the
  response (see
  [`soil_revised_rules()`](https://giulange.github.io/soilhub-r/reference/soil_revised_rules.md)).
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

- layout:

  `"wide"` (one row per horizon, the default) or `"long"` (one row per
  observation). API field `layout`.

- with_geometry:

  The geometry of each row's feature (EPSG:4326): `"none"` (the
  default), `"text"` (wide: `geometry_kind` and `geometry_text` as WKT,
  sent once per feature by the API; long: `geometry_text` as GeoJSON,
  sent on every row) or `"sf"` (an `sf` object with a `geometry` column;
  needs the package `sf`, else a `soilhub_dependency_error`). Rows
  without geometry (WISE profiles without coordinates) get `NA` (text)
  or an empty geometry (sf) and one warning. For polygons prefer the
  wide layout: the long layout repeats the geometry on every
  observation. API fields `geometry_format` (wide) and
  `include_geometry` (long).

- max_rows:

  Maximum number of rows to read (`Inf`: the whole selection).
  Client-side; caps the API field `limit` of each page request.

- offset:

  Rows of the selection to skip (to continue a partial read). API field
  `offset` (of the first page request).

- page_size:

  Rows per request; `NULL` uses the session's, the `soilhub.page_size`
  option or the server's `max_page_size`. Client-side; sets the API
  field `limit` of each page request.

- too_large:

  What to do when the API refuses the selection as too large for a
  synchronous read: `"stop"` raises `soilhub_load_limit_error`, whose
  message names the equivalent
  [`soil_export()`](https://giulange.github.io/soilhub-r/reference/soil_export.md)
  call; `"export"` exports the same selection (CSV; GeoJSON for the long
  layout with geometry), waits, downloads it into the export directory,
  reads it back and returns the same shape as the synchronous read, with
  `soil_metadata(x)$via_export` the job id (the whole selection is
  exported; `offset` and `max_rows` select its rows). Client-side: not
  sent to the API.

- progress:

  Report the pages read (messages at verbosity 1 or more). Client-side:
  not sent to the API.

- timeout:

  Seconds allowed for each page request; `NULL` uses the session's (300
  s by default). Client-side: not sent to the API.

## Value

A `soil_table` (see
[soil_table](https://giulange.github.io/soilhub-r/reference/soil_table.md)):
a data frame (an `sf` object with `with_geometry = "sf"`) with the
attributes `soil_metadata` (see
[`soil_metadata()`](https://giulange.github.io/soilhub-r/reference/soil_metadata.md))
and `soil_layout` (`"wide"` or `"long"`).

## Details

Terms: a **feature** is where a profile or map unit is (`feature_id`); a
**profile** a described soil profile (SOTER `PRID`); a **component** a
soil component of a multi-component map unit (SOTWIS and SOTER polygons;
`component_rank` is the SOTER `SCID`); a **horizon** a layer of a
profile (SOTER `HONU`); an **observation** one measured value. A wide
row is one horizon of one feature and component: its key is `dataset`,
`feature_id`, `component_id`, `horizon_id` (a SOTER horizon appears once
per polygon component linked to its profile).

**Columns** (design 5.2), in the API's order: the fixed columns
(`dataset`, `provider_code`, `feature_id`, `profile_id`, `component_id`,
`component_rank` integer, `horizon_id`, `horizon_name`,
`upper_depth_cm`, `lower_depth_cm` double, `source_support`,
`release_code`); with `layer = "first"` `first_layer_status` and
`profile_markings` (list of character); the component columns when
SOTWIS or SOTER polygons are selected (`proportion_percent`,
`cumulative_proportion_percent`, `terrain_proportion_percent` double,
`is_representative`, `profile_inside_polygon` logical, `suid`, `tcid`,
`scid` integer, the others character); the source columns
`source_profile_type` (SOTER: `synthetic`, `virtual`),
`source_record_note`, `profile_attr_<key>` and `horizon_attr_<key>`
(verbatim text: `horizon_attr_organic_surface` is `"true"`/`"false"` as
served); the raw markings (`texture_sum` double, `consistency_flags` and
`also_in_datasets` lists of character, `possible_profile`,
`superseded_by`, `cell_markings` a list of named lists: variable column
-\> markings); `value_flags` (list of named lists: variable column -\>
flags, `NULL` where none); `retired_in_release` (the release in which
the row's source left ISRIC, still served) and `retired_cells` (named
character: the cells retired while the row is not); with
`view = "revised"` `revised_markings` (named lists: horizon markings,
`hidden_values` a data frame `property_code`, `rule`, `source_value`,
and `cells`); with `with_geometry = "text"` `geometry_kind` and
`geometry_text` (WKT, EPSG:4326, the geometry of the row's feature);
then, sorted by name, one group per variable: `<key>` (double when the
column is numeric on every page, else the original text), `<key>_units`,
`<key>_method` (the laboratory method code of the value), `<key>_n`
(integer: measurements collapsed into the cell, the first by ingestion
order is kept) and, for columns with multi-value cells, `<key>_values`.
`<key>` is the canonical property key (`organic_carbon`); source codes
without a canonical mapping are `src_<code>`. With
`with_geometry = "sf"` the result is an `sf` object whose `geometry`
column replaces `geometry_text`.

**Long layout** (design 5.3): one row per observation, the columns of
the API's `ObservationRecord` in its order: `dataset`, `observation_id`,
`feature_id`, `component_id`, `component_rank` (integer), `horizon_id`,
`horizon_name`, `upper_depth_cm`, `lower_depth_cm` (double),
`property_code` (the source code, `ORGC`), `value` (double: the number
the API extracted from the source value), `value_raw` (list: the source
value verbatim, a number, a string or a list of strings), `unit`,
`provider_code`, `release_code`, `release_id` (integer),
`canonical_feature_id`, `canonical_horizon_id`, `canonical_property_key`
(`organic_carbon`), `source_support`, `lineage` (list), `geometry_kind`;
the laboratory method (`method_code`, `method_description`,
`method_tension_kpa`); the source descriptors `profile_attributes`,
`horizon_attributes`, `component_attributes` (lists),
`source_profile_type`, `source_record_note`; the raw markings of the
cell (`value_count` integer, `methods_differ` logical, `value_spread`
double, `source_method_kind` list of character, `method_facets` list),
of the layer (`texture_sum`, `consistency_flags`) and of the profile
(`also_in_datasets`, `possible_profile`, `superseded_by`); `value_flags`
(list of character); `retired_in_release`; with `view = "revised"`
`revised_markings` (named lists, `hidden_values` a data frame); with
`layer = "first"` `first_layer_status` and `profile_markings`; the
component columns when SOTWIS or SOTER polygons are selected. Fields the
API sends only for some selections are present only then.
`soil_metadata(x)$total_count` is the exact number of observations of
the selection (the long layout counts it on every page).

The wide and the long layout of the same selection hold the same
horizons (keys `dataset`, `feature_id`, `component_id`, `horizon_id`);
the wide `<key>` is the first long `value` of that property by ingestion
order and `<key>_n` the number of long rows of it.

**Multi-value cells.** About 6 % of the WoSIS measurements hold several
values in one cell (a JSON list of 2 to 10 values); the API returns the
list as text. `<key>` receives the **mean** of the listed values (the
value WoSIS publishes; `NA` when an element is not a number) and
`<key>_values` every original value verbatim (character; `NULL` for the
single-value cells); `soil_metadata(x)$multi_value_rule` is `"mean"` and
[`soil_columns()`](https://giulange.github.io/soilhub-r/reference/soil_columns.md)
counts the multi-value cells. The other markings of the cell
(`value_count`, `methods_differ`, `value_spread`, `source_method_kind`,
`method_facets`) are in `cell_markings`. In the long layout the API
extracts no number from such a cell: `value` receives the same mean,
computed by the client, and `value_raw` keeps the listed values.

**Pages.** The API returns at most `max_page_size` horizons per request
(1000; see
[`soil_capabilities()`](https://giulange.github.io/soilhub-r/reference/soil_capabilities.md));
the pages are read until the selection is exhausted or `max_rows` rows
are read, and their columns are aligned (a variable absent from a page
is `NA` there). A failure after some pages raises the error with the
rows already read in `e$partial` (a `soil_table` whose metadata has
`complete = FALSE` and `next_offset`): continue with
`offset = soil_metadata(e$partial)$next_offset`.

**Large selections.** The API refuses a synchronous read above its limit
(`limits$max_sync_observations`, 1,000,000 observations today) with
`soilhub_load_limit_error`; its message prints the
[`soil_export()`](https://giulange.github.io/soilhub-r/reference/soil_export.md)
call of the same selection; `too_large = "export"` exports it and reads
it back. Run
[`soil_summary()`](https://giulange.github.io/soilhub-r/reference/soil_summary.md)
first to size a selection.

Rights: `soil:read`. Capabilities: `revised_view` for
`view = "revised"`, `profile_type_filter` for `profile_type`,
`component_selection` for `components`, `observation_geometry` for the
geometry of the long layout.

## See also

[`soil_features()`](https://giulange.github.io/soilhub-r/reference/soil_features.md),
[`soil_columns()`](https://giulange.github.io/soilhub-r/reference/soil_columns.md),
[`soil_flags()`](https://giulange.github.io/soilhub-r/reference/soil_flags.md),
[`soil_markings()`](https://giulange.github.io/soilhub-r/reference/soil_markings.md),
[`soil_revised_rules()`](https://giulange.github.io/soilhub-r/reference/soil_revised_rules.md),
[`soil_first_layer()`](https://giulange.github.io/soilhub-r/reference/soil_first_layer.md),
[`soil_citations()`](https://giulange.github.io/soilhub-r/reference/soil_citations.md)

Other reads:
[`soil_features()`](https://giulange.github.io/soilhub-r/reference/soil_features.md)

## Examples

``` r
if (FALSE) { # \dontrun{
soil <- soil_connect()
x <- soil_observations(soil, datasets = "wosis_points", country = "KEN",
                       variables = c("organic_carbon", "clay"), max_rows = 100)
x
soil_columns(x)
soil_citations(x)

# first horizons of SOTER, revised view
y <- soil_observations(soil, datasets = "soter_profiles", layer = "first",
                       view = "revised", country = "KEN")
table(y$first_layer_status)
soil_revised_rules(y)

# a refused selection names the export call
tryCatch(soil_observations(soil), soilhub_load_limit_error = function(e) e)

# one row per observation, with the geometry as sf
z <- soil_observations(soil, datasets = "wosis_points", country = "KEN",
                       variables = "organic_carbon", layout = "long",
                       with_geometry = "sf", max_rows = 100)
soil_metadata(z)$total_count
} # }
```
