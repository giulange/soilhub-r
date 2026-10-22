# The first layer and soil map components

``` r

library(soilhub)
```

Many studies need only the **topsoil**: the first horizon of each
profile. This guide shows how to ask for it with `layer = "first"`, how
to read the column `first_layer_status`, and how the soil map units of
SOTER and SOTWIS are split into **components**. It assumes you have
signed in as shown in
[`vignette("soilhub", package = "soilhub")`](https://giulange.github.io/soilhub-r/articles/soilhub.md).
The outputs were recorded from the Global Soil Data Hub API in October
2026.

## The first layer of each profile

With `layer = "first"` the hub returns, for each profile, only its first
horizon (or horizons, when several start at the same depth). Here: the
WoSIS profiles around Vancouver (Canada).

``` r

vancouver <- c(-123.3, 49.0, -122.9, 49.4)
first <- soil_observations(soil, datasets = "wosis_points", bbox = vancouver,
                           layer = "first", max_rows = 5)
nrow(first)
#> [1] 3
```

We asked for up to 5 rows and received 3: one row per profile, and there
are only three profiles with horizons in this box.

``` r

first[, c("feature_id", "horizon_name", "upper_depth_cm", "lower_depth_cm", "first_layer_status")]
#> # soilhub wide table: 3 horizons, 3 features, 6 variables | wosis_points | view raw, layer first
#> # no API warnings (soil_warnings), typing (soil_columns), cite with soil_citations()
#>                             feature_id horizon_name upper_depth_cm lower_depth_cm
#> 1 38ed7f8d-35b2-4afd-b4a8-08fc5e8f4f81            F              0              1
#> 2 623b5139-52b0-40cc-9750-933440e50d57            F              0              1
#> 3 bfe48b90-466a-4741-b079-ef95b687abd7           Ap              0             20
#>   first_layer_status
#> 1            surface
#> 2            surface
#> 3            surface
```

Each row is the first horizon of one profile. Two profiles start with an
organic F horizon (0 to 1 cm), one with a ploughed Ap horizon (0 to 20
cm). All three have the status `surface`.

## What the status means

`first_layer_status` says how the first horizon was found.
[`soil_first_layer()`](https://giulange.github.io/soilhub-r/reference/soil_first_layer.md)
lists the statuses the server can give:

``` r

soil_first_layer(first)
#> $view
#> [1] "raw"
#> 
#> $statuses
#> [1] "surface"       "tie"           "not_surface"   "depth_missing"
#> 
#> $profile_markings
#> [1] "negative_depth_above"  "empty_row"             "depth_order_conflict" 
#> [4] "numbering_starts_at_N" "numbering_gap"
```

In words:

- `surface`: the one horizon of the profile that starts at the soil
  surface (upper depth 0);
- `tie`: several horizons start at 0; all of them are returned (for
  example repeated samples of the same layer);
- `not_surface`: no horizon starts at the surface; the first available
  one is returned (look at its `upper_depth_cm`);
- `depth_missing`: SOTER only, the surface horizon has neither an upper
  nor a lower depth.

With `view = "revised"` (see
[`vignette("raw-vs-revised", package = "soilhub")`](https://giulange.github.io/soilhub-r/articles/raw-vs-revised.md))
two more statuses can appear: `surface_within_5cm` (rule R2: a first
horizon starting within 5 cm counts as surface) and `first_mineral`
(rule R3: the first mineral horizon, below the organic layers).

You can count the statuses with
[`table()`](https://rdrr.io/r/base/table.html):

``` r

table(first$first_layer_status)
#> 
#> surface 
#>       3
```

## Profile markings

The column `profile_markings` reports problems of the horizon sequence
of the profile in the source (SOTER profiles only; it is empty
elsewhere). The list of possible markings is in
`soil_first_layer(first)$profile_markings`:

- `negative_depth_above`: an organic (O) horizon with a negative depth
  lies above the first horizon;
- `empty_row`: the first row of the profile is empty (no name, depth or
  value);
- `depth_order_conflict`: some horizons are not deeper than the previous
  one;
- `numbering_starts_at_N`: the horizon numbers (SOTER `HONU`) do not
  start at 1;
- `numbering_gap`: some horizon numbers are missing.

Here the profiles are from WoSIS, so the markings are empty:

``` r

first$profile_markings
#> [[1]]
#> character(0)
#> 
#> [[2]]
#> character(0)
#> 
#> [[3]]
#> character(0)
```

## Why a profile may return nothing

[`soil_features()`](https://giulange.github.io/soilhub-r/reference/soil_features.md)
lists the places (features) of a selection, even those without
measurements. Here we read the first three features of the same box,
with their coordinates as text (GeoJSON):

``` r

places <- soil_features(soil, datasets = "wosis_points", bbox = vancouver,
                        with_geometry = "text", max_rows = 3)
places[, c("feature_id", "geometry_text")]
#> # soilhub features table: 3 features | wosis_points | view raw
#> # no API warnings (soil_warnings), cite with soil_citations()
#> # incomplete read: continue with offset = 3 (soil_metadata(x)$next_offset)
#>                             feature_id
#> 1 14f7a6b1-13c0-4c75-a7fb-dbc370ae5d44
#> 2 38ed7f8d-35b2-4afd-b4a8-08fc5e8f4f81
#> 3 623b5139-52b0-40cc-9750-933440e50d57
#>                                                  geometry_text
#> 1 {"type":"Point","coordinates":[-123.152777778,49.088888889]}
#> 2                  {"type":"Point","coordinates":[-123,49.38]}
#> 3                  {"type":"Point","coordinates":[-123,49.38]}
```

Is each of them among the profiles of the first-layer read?

``` r

places$feature_id %in% first$feature_id
#> [1] FALSE  TRUE  TRUE
```

The first place has no row: it is a profile site without any horizon
with measurements in WoSIS, so a read of observations (first layer or
all layers) returns nothing for it. A profile can also return nothing
with `layer = "first"` when its first horizon has no value of the
`variables` you asked for, or, in SOTER, when its first row is empty.

## Soil map units and their components

SOTER and SOTWIS describe the soil of **map units** (polygons). A map
unit holds several soils, the **components**, each covering a share of
its area and represented by a profile. We read five horizons of the
SOTER polygons:

``` r

soter <- soil_observations(soil, datasets = "soter_polygons", max_rows = 5)
soter[, c("component_rank", "proportion_percent", "is_representative", "suid",
          "horizon_name", "lower_depth_cm")]
#> # soilhub wide table: 5 horizons, 9 variables | soter_polygons | view raw, layer all
#> # no API warnings (soil_warnings), typing (soil_columns), cite with soil_citations()
#> # incomplete read: continue with offset = 5 (soil_metadata(x)$next_offset)
#>   component_rank proportion_percent is_representative suid horizon_name lower_depth_cm
#> 1              1                100              TRUE  866           Aa             12
#> 2              1                100              TRUE  866           Ap             21
#> 3              1                100              TRUE  866           W1             42
#> 4              1                100              TRUE  866           W1            100
#> 5              1                100              TRUE 1409          A11             31
```

The component columns:

- `component_rank`: the rank of the component in the map unit (1 is the
  largest);
- `proportion_percent`: the share of the map unit it covers (100 % here:
  these units have one soil);
- `is_representative`: `TRUE` for the component that represents the
  unit;
- `suid`: the SOTER unit identifier (SUID) of the map unit.

The upper depths of these SOTER horizons are missing in the source
(`upper_depth_cm` is `NA`): only the lower depth is recorded.

``` r

soter$upper_depth_cm
#> [1] NA NA NA NA NA
```

Which components were returned? By default only the representative one:

``` r

soil_metadata(soter)$components
#> [1] "representative"
```

## Choosing the components

The argument `components` chooses which components you get:

- `"representative"`: one component per map unit, the representative
  one;
- `"all"`: every component;
- `"cumulative"`: the largest components until their shares add up to
  `min_cumulative_percent`.

### A SOTWIS example near Tunis

SOTWIS map units have several soil components. We look at three SOTWIS
map units in a box near Tunis (Tunisia). First, the box:

``` r

tunis <- c(10.0, 36.5, 10.5, 37.0)
```

[`soil_features()`](https://giulange.github.io/soilhub-r/reference/soil_features.md)
lists the map units without reading their horizons (here with the shapes
as text; `with_geometry = "sf"`, the default, returns them as an `sf`
object for maps if the package `sf` is installed):

``` r

units <- soil_features(soil, datasets = "sotwis_polygons", bbox = tunis,
                       with_geometry = "text", max_rows = 3, progress = FALSE)
nrow(units)
#> [1] 3
```

Each of the three rows is one SOTWIS map unit (a polygon). The column
`components` holds, for each unit, a small table with its soil
components; here is the one of the first unit:

``` r

units$components[[1]][, c("soil_code", "component_rank", "proportion_percent",
                          "is_representative")]
#>   soil_code component_rank proportion_percent is_representative
#> 1       GLe              1                 55              TRUE
```

The first unit has a Gleysol (`GLe`) component covering 55 % of the
unit; it is the largest (`component_rank` 1) and represents the unit.
Its horizons are read with
[`soil_observations()`](https://giulange.github.io/soilhub-r/reference/soil_observations.md),
asking for all the components (`components = "all"`):

``` r

sotwis <- soil_observations(soil, datasets = "sotwis_polygons", bbox = tunis,
                            components = "all", max_rows = 5, progress = FALSE)
sotwis[, c("component_rank", "proportion_percent", "horizon_name",
           "upper_depth_cm", "lower_depth_cm")]
#> # soilhub wide table: 5 horizons, 18 variables | sotwis_polygons | view raw, layer all
#> # no API warnings (soil_warnings), typing (soil_columns), cite with soil_citations()
#> # incomplete read: continue with offset = 5 (soil_metadata(x)$next_offset)
#>   component_rank proportion_percent horizon_name upper_depth_cm lower_depth_cm
#> 1              1                 55           D1              0             20
#> 2              1                 55           D1              0             20
#> 3              1                 55           D2             20             40
#> 4              1                 55           D3             40             60
#> 5              1                 55           D4             60             80
```

These five rows are the horizons of the first component, from 0 to 80
cm. We stopped at 5 rows, so the other components of the unit are not
shown: raise `max_rows` to read them. The first horizon, D1, is listed
twice with the same values: the SOTWIS files of ISRIC carry a summary
copy of the first layer, and the hub keeps the source as ISRIC published
it. With `view = "revised"` the copy is hidden (rule R5, see the article
on the raw and revised views).

A few values of those horizons (SOTWIS values are estimates, not
measurements):

``` r

sotwis[, c("horizon_name", "clay_content", "organic_carbon", "ph_h2o")]
#> # soilhub wide table: 5 horizons, 18 variables | sotwis_polygons | view raw, layer all
#> # no API warnings (soil_warnings), typing (soil_columns), cite with soil_citations()
#> # incomplete read: continue with offset = 5 (soil_metadata(x)$next_offset)
#>   horizon_name clay_content organic_carbon ph_h2o
#> 1           D1           30          10.00    5.9
#> 2           D1           30          10.00    5.9
#> 3           D2           34           4.34    6.0
#> 4           D3           34           3.75    6.2
#> 5           D4           34           3.00    6.4
```

For a soil scientist: a SOTWIS polygon is a map unit made of several
soil components, each with a share of the area in percent, and the
layers of a component are **estimated** values for the representative
soil, not measurements of a profile at a site (`source_support` is
`"polygon_estimate"`). Here clay is 30 to 34 %, organic carbon decreases
with depth (from 10 to 3 g/kg) and the pH rises from 5.9 to 6.4.

### Other components

For example, all the components of the SOTWIS map units of Kenya, or the
largest ones covering at least 80 % of each unit (these calls are not
run here):

``` r

all_components <- soil_observations(soil, datasets = "sotwis_components",
                                    country = "KEN", components = "all")

main_components <- soil_observations(soil, datasets = "sotwis_components",
                                     country = "KEN", components = "cumulative",
                                     min_cumulative_percent = 80)
```

You can combine `components` with `layer = "first"` to get the topsoil
of each component.
