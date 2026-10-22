# What exists by dataset, country and variable

Counts the features, horizons and observations of a selection by
dataset, by country and by variable, with the meaning of each source
variable in each dataset (`POST /query/availability`,
`canonical = true`). A feature assigned to several countries (the
country filter of the API selects the features that intersect a country)
counts under each of them, so the country rows must not be summed: the
dataset totals count every feature once. Features without a country are
grouped under an `NA` country.

## Usage

``` r
soil_availability(
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

A `soil_availability` list of data frames:

- `datasets`: one row per dataset, `dataset`, `geometry` (`"point"`,
  `"polygon"`), `feature_count`, `horizon_count`, `observation_count`
  (distinct totals of the dataset);

- `countries`: `country_code`, `country_name`, `feature_count`,
  `horizon_count`, `observation_count`;

- `dataset_countries`: one row per dataset and country, the same counts
  (`by_dataset` of the API);

- `variables`: one row per dataset, country and source variable:
  `dataset`, `country_code`, `country_name`, `property_code` (the source
  code), `canonical_property_key`, `canonical_name`, `property_family`,
  `source_unit`, `procedure_code`, `procedure_description`,
  `source_value_kind`, `mapping_status`, `documentation_url`,
  `source_notes`, `variants` (list of data frames `source_scope`,
  `canonical_property_key`, `source_unit`, `source_notes`: the meanings
  of the code in parts of the dataset), `feature_count`,
  `horizon_count`, `observation_count`;

and `metadata` (see
[`soil_metadata()`](https://giulange.github.io/soilhub-r/reference/soil_metadata.md)).

## Details

The arguments are the selection of
[`soil_observations()`](https://giulange.github.io/soilhub-r/reference/soil_observations.md),
validated the same way before any request.

Rights: `soil:summary`. Capabilities: `canonical_summary`;
`revised_view` for `view = "revised"`, `profile_type_filter` for
`profile_type`, `component_selection` for `components`.

## See also

Other summaries:
[`soil_consistency()`](https://giulange.github.io/soilhub-r/reference/soil_consistency.md),
[`soil_summary()`](https://giulange.github.io/soilhub-r/reference/soil_summary.md)

## Examples

``` r
if (FALSE) { # \dontrun{
a <- soil_availability(soil, datasets = "soter_profiles", country = "KEN")
a$datasets
totc <- a$variables[a$variables$property_code == "TOTC", ]
totc[, c("country_code", "source_unit", "observation_count")]
} # }
```
