# What a selection holds, before reading it

Counts the features, horizons and observations of a selection, the
variables it holds and what they mean, without transferring the data
(`POST /query/summary`, `canonical = true`). The counts are those the
reads return for the same selection: `feature_count` is the number of
features of
[`soil_features()`](https://giulange.github.io/soilhub-r/reference/soil_features.md)
(`layer` and `components` do not apply to it), `horizon_count` the rows
of the wide layout of
[`soil_observations()`](https://giulange.github.io/soilhub-r/reference/soil_observations.md),
`observation_count` the rows of its long layout. It is also the sizing
step before an export: a selection above the limit of synchronous reads
(`soil_capabilities()$limits$max_sync_observations`) is read with
[`soil_export()`](https://giulange.github.io/soilhub-r/reference/soil_export.md).

## Usage

``` r
soil_summary(
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
  min_cumulative_percent = NULL
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

## Value

A `soil_summary` list:

- `datasets` (character), `geometry`;

- `feature_count`, `horizon_count`, `observation_count`,
  `observed_feature_count` (features with at least one horizon row) and
  each `<count>_by_dataset` (named double; with one dataset its total);

- `avg_horizons_per_feature` (horizon rows per observed feature) and
  `avg_horizons_per_feature_by_dataset`;

- `by_dataset`: a data frame of the same counts, one row per dataset;

- `variables` (source codes, character), `variables_by_dataset` (named
  list of character), `variable_semantics` (data frame `dataset`,
  `source_code`, `canonical_property_key`, `canonical_name`,
  `property_family`, `source_unit`, `procedure_code`,
  `procedure_description`, `source_value_kind`, `mapping_status`,
  `documentation_url`, `source_notes`);

- `formats` (export formats), `warnings`;

- `view`, `revised` (with `view = "revised"`: the rules applied with
  their counts, see
  [`soil_revised_rules()`](https://giulange.github.io/soilhub-r/reference/soil_revised_rules.md)),
  `components` and `min_cumulative_percent` (when a component dataset is
  selected);

- `metadata` (see
  [`soil_metadata()`](https://giulange.github.io/soilhub-r/reference/soil_metadata.md)):
  the request, its id, versions and the catalog rows of the datasets for
  [`soil_citations()`](https://giulange.github.io/soilhub-r/reference/soil_citations.md).

Printing shows a short report: counts per dataset, the variables, the
warnings and the revised rules.

## Details

The arguments are the selection of
[`soil_observations()`](https://giulange.github.io/soilhub-r/reference/soil_observations.md),
validated the same way before any request and sent with the same API
names.

Rights: `soil:summary`. Capabilities: `canonical_summary`;
`revised_view` for `view = "revised"`, `profile_type_filter` for
`profile_type`, `component_selection` for `components`.

## See also

[`soil_availability()`](https://giulange.github.io/soilhub-r/reference/soil_availability.md)
for the counts by country and variable,
[`soil_consistency()`](https://giulange.github.io/soilhub-r/reference/soil_consistency.md)
for the distinct totals of the daily statistics.

Other summaries:
[`soil_availability()`](https://giulange.github.io/soilhub-r/reference/soil_availability.md),
[`soil_consistency()`](https://giulange.github.io/soilhub-r/reference/soil_consistency.md)

## Examples

``` r
if (FALSE) { # \dontrun{
s <- soil_summary(soil, datasets = c("wosis_points", "wise_profiles"), country = "KEN")
s
s$observation_count_by_dataset
s$variable_semantics[, c("dataset", "source_code", "canonical_property_key")]
soil_citations(s)

# the revised view lists the rules it applies to the selection
soil_revised_rules(soil_summary(soil, datasets = "sotwis_polygons", view = "revised"))
} # }
```
