# Terms used by soilhub

The words of the Global Soil Data Hub and of its sources (WoSIS, WISE,
SOTER, SOTWIS) used in the arguments, the columns and the help pages of
the package. The sources' own terms (in capitals) are kept as the
sources write them.

## Levels of the data

- **dataset**: one collection of the catalog (`"wosis_points"`,
  `"wise_profiles"`, `"soter_profiles"`, `"soter_polygons"`,
  `"sotwis_polygons"`, `"sotwis_components"`, `"sotwis_estimates"`),
  from one **provider** (`provider_code`, e.g. `"isric"`) and one
  **release** (`release_code`); see
  [`soil_datasets()`](https://giulange.github.io/soilhub-r/reference/soil_datasets.md).

- **feature**: a place, with its geometry: a profile site (a point) or a
  soil map unit (a polygon). Column `feature_id`.

- **profile**: the soil described at a place (`profile_id`). In SOTER
  and SOTWIS a profile is identified by `PRID`.

- **component**: one of the soils of a multi-component map unit (SOTER
  and SOTWIS polygons), covering a share of it (`proportion_percent`);
  `component_id`, `component_rank`. Point profiles have one component.

- **horizon**: one layer of a profile, with an upper and a lower depth
  in cm (`horizon_id`, `horizon_name`, `upper_depth_cm`,
  `lower_depth_cm`). SOTER numbers the horizons of a profile with
  `HONU`.

- **observation**: one measured (or estimated) value of one property in
  one horizon. The **wide** layout has one row per horizon and one group
  of columns per property; the **long** layout one row per observation.

- **variable**: a soil property with a canonical key (`organic_carbon`),
  mapped from the source codes (`ORGC`, `orgc`); see
  [`soil_variables()`](https://giulange.github.io/soilhub-r/reference/soil_variables.md).

The ids (`feature_id`, `profile_id`, `component_id`, `horizon_id`) are
the canonical ids of the hub (UUIDs), the same in every read; the source
identifiers are kept in the source columns.

## Codes of SOTER and SOTWIS

- `PRID`: profile identifier.

- `HONU`: horizon number within a profile.

- `SUID`: SOTER unit identifier, the map unit (column `suid`).

- `TCID`: terrain component identifier within a SOTER unit (column
  `tcid`).

- `SCID`: soil component identifier within a terrain component (the
  `component_rank` of a SOTER component; column `scid` where served).

- `CLAF`: the FAO soil unit code of a profile or component (used by the
  SOTWIS taxotransfer rules,
  [`soil_ttr_flags()`](https://giulange.github.io/soilhub-r/reference/soil_ttr_flags.md)).

## Source support

`source_support` says what a row stands for in its source, for example
`observed_point_profile` (a profile described and sampled at a point),
`map_unit_profile_relation` (a profile linked to a soil map unit),
`polygon_estimate` (values estimated for a map unit),
`non_spatial_profile` and `non_spatial_estimate` (without their own
geometry).

## Views and the first layer

- `view = "raw"`: the ISRIC data as published, defects included;
  `view = "revised"`: the documented rules of the server applied,
  reported by
  [`soil_revised_rules()`](https://giulange.github.io/soilhub-r/reference/soil_revised_rules.md)
  and
  [`soil_markings()`](https://giulange.github.io/soilhub-r/reference/soil_markings.md).

- `layer = "first"`: the first horizon(s) of each profile, with
  `first_layer_status`: `surface` (the one horizon starting at 0), `tie`
  (several start at 0, all returned), `not_surface` (none starts at 0:
  the first available), `depth_missing` (SOTER: the surface horizon has
  no depth); with `view = "revised"` also `surface_within_5cm` and
  `first_mineral`. `profile_markings` reports problems of the SOTER
  horizon sequence. See
  [`soil_first_layer()`](https://giulange.github.io/soilhub-r/reference/soil_first_layer.md).

## Markings and flags

Markings are information the source or the server attaches to a value, a
layer or a profile (the laboratory method facets, a "guessed value",
duplicates in other datasets); flags (`value_flags`) are warnings such
as `extreme`. Neither changes a value. See
[`soil_markings()`](https://giulange.github.io/soilhub-r/reference/soil_markings.md),
[`soil_flags()`](https://giulange.github.io/soilhub-r/reference/soil_flags.md).

## Rights

`soil:summary` (catalog and counts), `soil:read` (data and exports),
`soil:publish` (runs, publications, jobs), `soil:admin` (variables,
products, country refresh); see
[`soil_whoami()`](https://giulange.github.io/soilhub-r/reference/soil_whoami.md).
