# Getting started with soilhub

This guide shows the first steps with **soilhub**, the R package of the
Global Soil Data Hub. With it you can see which soil datasets the hub
holds (WoSIS, WISE, SOTER, SOTWIS), how many profiles and measurements
they have in your area, and read the measurements into R as an ordinary
data frame.

A few words used everywhere in the package (the help page
`?soilhub-terms` has the full list):

- a **feature** is a place: a soil profile site (a point) or a map unit
  (a polygon);
- a **profile** is the soil described at that place;
- a **horizon** is one layer of a profile, with an upper and a lower
  depth;
- an **observation** is one measured value (for example the organic
  carbon of one horizon).

**About the outputs shown here.** The results printed in this guide were
produced by the same functions on answers recorded from the Global Soil
Data Hub API (version 0.6.0) in October 2026. When you run the code
yourself the data come live from the hub, so some numbers may differ.

## 1. Install and load the package

If soilhub is not installed yet, follow the [installation
page](https://giulange.github.io/soilhub-r/articles/installation.md):
two lines in the R console, once.

Every time you start R, load the package:

``` r

library(soilhub)
```

## 2. Sign in

The hub needs to know who you are. You sign in with your university or
hub account through your web browser: R never sees your password.

``` r

soil <- soil_connect()
```

What happens, step by step:

1.  R prints a web address and a short code, like this:

        soilhub: to sign in, open https://kc.weatherprogapp.it/realms/ams/device and enter the code ABCD-EFGH
          The code is valid for 10m; waiting for the browser step...

2.  Open the address in your browser (R may open it for you), type the
    code and sign in with your usual account.

3.  Approve the request. Back in R,
    [`soil_connect()`](https://giulange.github.io/soilhub-r/reference/soil_connect.md)
    finishes by itself.

The object `soil` is your **session**: every function takes it as its
first argument. The session renews itself when needed, so you can keep
working for hours. If it expires (for example after a long pause), sign
in again with `soil_login(soil)`.

How long a session lasts is decided by the Keycloak server. Measured on
18 October 2026: the access token is valid for 2 hours and is renewed
automatically at your next call; a pause of 95 minutes without any call
did not end the session; a session lasts at most 9 hours from the
sign-in, then `soil_login(soil)` is needed.

## 3. What am I allowed to do?

Your account has **rights**. Most users have `soil:summary` (see what
exists) and `soil:read` (read the data).
[`soil_whoami()`](https://giulange.github.io/soilhub-r/reference/soil_whoami.md)
shows your rights and the functions they allow.

``` r

soil_whoami(soil)
```

The output looks like this (shortened; the user name is yours):

    #> <soil_identity> your-user-name
    #>   Rights:  soil:summary, soil:read (audience soil-api)
    #>   Token:   valid for 1h 59m (until ...)
    #>   Session: renewable
    #>   Functions by right:
    #>     soil:summary  yes soil_capabilities(), soil_datasets(), ...
    #>     soil:read     yes soil_observations(), soil_features(), ...
    #>     soil:publish  no  soil_run_open(), soil_publish_values(), ...
    #>     soil:admin    no  soil_register_variable(), soil_product(), ...

A “no” is normal for readers: publishing data is for a few accounts
only.

## 4. Which datasets are there?

[`soil_datasets()`](https://giulange.github.io/soilhub-r/reference/soil_datasets.md)
returns one row per dataset of the hub.

``` r

datasets <- soil_datasets(soil)
nrow(datasets)
#> [1] 8
```

The table has many columns (title, counts, licence, citation, release…).
Here we look at four of them:

``` r

datasets[, c("name", "title", "profile_count", "horizon_count")]
#>                name                       title profile_count horizon_count
#> 1     hurl_profiles               Hurl profiles             1             1
#> 2    soter_polygons SOTER polygons and profiles         15418             0
#> 3    soter_profiles    SOTER reference profiles         15908         39208
#> 4 sotwis_components      SOTWIS soil components         35581        176178
#> 5  sotwis_estimates    SOTWIS estimate profiles          5518         25433
#> 6   sotwis_polygons    SOTWIS polygon estimates         39345          8858
#> 7     wise_profiles        WISE global profiles         10253         47833
#> 8      wosis_points        WoSIS point profiles        226828        884909
```

The `name` column is the code you will use in the other functions (for
example `"wosis_points"`). `profile_count` and `horizon_count` tell you
how big each dataset is. The SOTER and SOTWIS **polygon** datasets are
soil map units: their horizons belong to the profiles that represent the
map units.

To see everything about one dataset, use
[`soil_dataset()`](https://giulange.github.io/soilhub-r/reference/soil_dataset.md)
with its name:

``` r

soil_dataset(soil, "wosis_points")
#> <soil_dataset> wosis_points: WoSIS point profiles
#>   Provider:  isric; observed_point_profile, geometry point
#>   Release:   legacy_materialized (active, acquired 2026-08-01, reconstructed)
#>   Counts:    226,828 features, 226,828 profiles, 884,909 horizons, 5,998,234 observations
#>   Licence:   Licenced per profile, as specified by data provider and indicated in the data
#>   Citation:  Batjes NH, Calisto L and de Sousa LM, 2024. WoSIS-latest: Standardised world soil profile data. ISRIC Soil Data Hub resource identifier: https://tinyurl.com/39xhaa9d. Date downloaded: 15/01/2024.
#>   See soil_citations() and soil_licences() for what to cite and the terms of use.
```

This tells you where the data come from (the release), how much there
is, under which licence you may use it and how to cite it.

## 5. Which soil properties are measured?

[`soil_variables()`](https://giulange.github.io/soilhub-r/reference/soil_variables.md)
lists the soil properties (the hub calls them **variables**). Here we
ask only for those of WoSIS:

``` r

variables <- soil_variables(soil, dataset = "wosis_points")
nrow(variables)
#> [1] 44
```

``` r

head(variables[, c("variable_code", "name")], 10)
#>                          variable_code                                      name
#> 1        bulk_density_fine_earth_33kpa      Bulk density of fine earth at 33 kPa
#> 2      bulk_density_fine_earth_air_dry        Bulk density of air-dry fine earth
#> 3  bulk_density_fine_earth_field_moist    Bulk density of field-moist fine earth
#> 4     bulk_density_fine_earth_oven_dry       Bulk density of oven-dry fine earth
#> 5     bulk_density_whole_soil_oven_dry       Bulk density of oven-dry whole soil
#> 6                              cec_ph7 Cation exchange capacity buffered at pH 7
#> 7                              cec_ph8 Cation exchange capacity buffered at pH 8
#> 8                         clay_content                              Clay content
#> 9         coarse_fragments_gravimetric             Coarse fragments, gravimetric
#> 10         coarse_fragments_volumetric              Coarse fragments, volumetric
```

The `variable_code` (for example `organic_carbon`) is the name of the
column you will find in your data. The `name` says what was measured,
with the method when it matters (pH in water or in CaCl2, bulk density
dry or moist).

## 6. How much data is in my area?

Before reading data, ask how much there is.
[`soil_summary()`](https://giulange.github.io/soilhub-r/reference/soil_summary.md)
counts features, horizons and observations of a selection without
transferring them. Here: WoSIS profiles in Kenya.

``` r

kenya <- soil_summary(soil, datasets = "wosis_points", country = "KEN")
kenya
#> # soilhub summary: 2,318 features, 6,663 horizons, 46,429 observations | wosis_points | view raw, layer all
#> 
#> Counts per dataset:
#>       dataset features horizons observations observed_features horizons/feature
#>  wosis_points    2,318    6,663       46,429             2,304             2.89
#> 
#> Variables (35): bdfi33l, bdfiod, bdwsod, cecph7, cfgr, cfvo, clay, ecec, elco20, elco25, elcosp, nitkjd, orgc, orgm, phaq, phca, phetb1, phetol, phkc, phnf, ... (15 more)
#> 
#> # variable meanings in x$variable_semantics; cite with soil_citations(x)
```

WoSIS has about 2,300 profiles in Kenya with some 46,000 measured
values: a size you can read directly. For very large selections (more
than a million observations) you would use an export instead (see
[`vignette("exports", package = "soilhub")`](https://giulange.github.io/soilhub-r/articles/exports.md)).

## 7. Read the measurements

[`soil_observations()`](https://giulange.github.io/soilhub-r/reference/soil_observations.md)
reads the data. You choose the dataset and the area. Here the area is a
box around Vancouver (Canada), given as `c(west, south, east, north)` in
degrees, and `max_rows = 5` keeps only the first five rows for this
example (leave it out to read everything).

``` r

vancouver <- c(-123.3, 49.0, -122.9, 49.4)
x <- soil_observations(soil, datasets = "wosis_points", bbox = vancouver, max_rows = 5)
nrow(x)
#> [1] 5
```

The result is a data frame with **one row per horizon**. First the
columns that say where the horizon is:

``` r

x[, c("feature_id", "horizon_name", "upper_depth_cm", "lower_depth_cm")]
#> # soilhub wide table: 5 horizons, 2 features, 5 variables | wosis_points | view raw, layer all
#> # no API warnings (soil_warnings), typing (soil_columns), cite with soil_citations()
#> # incomplete read: continue with offset = 5 (soil_metadata(x)$next_offset)
#>                             feature_id horizon_name upper_depth_cm lower_depth_cm
#> 1 38ed7f8d-35b2-4afd-b4a8-08fc5e8f4f81            F              0              1
#> 2 38ed7f8d-35b2-4afd-b4a8-08fc5e8f4f81           Ae              1              2
#> 3 38ed7f8d-35b2-4afd-b4a8-08fc5e8f4f81           Bf              2             17
#> 4 623b5139-52b0-40cc-9750-933440e50d57            F              0              1
#> 5 623b5139-52b0-40cc-9750-933440e50d57           Ae              1              2
```

Each `feature_id` is one profile site: here the first three rows are the
horizons F, Ae and Bf of one profile, from 0 to 17 cm. The first two
lines printed above the table (starting with `#`) are a short report of
the package: how many horizons and profiles were read, and the reminder
that the read is incomplete because we asked for 5 rows only.

Then the measurements. Each soil property has a group of columns: the
value, its unit, its method and `_n`.

``` r

x[, c("horizon_name", "organic_carbon", "organic_carbon_units", "organic_carbon_n")]
#> # soilhub wide table: 5 horizons, 5 variables | wosis_points | view raw, layer all
#> # no API warnings (soil_warnings), typing (soil_columns), cite with soil_citations()
#> # incomplete read: continue with offset = 5 (soil_metadata(x)$next_offset)
#>   horizon_name organic_carbon organic_carbon_units organic_carbon_n
#> 1            F          410.0                 g/kg                1
#> 2           Ae           80.0                 g/kg                1
#> 3           Bf           80.0                 g/kg                1
#> 4            F          412.0                 g/kg                1
#> 5           Ae           83.7                 g/kg                1
```

`organic_carbon` is the measured value, `organic_carbon_units` its unit
(g/kg here), and `organic_carbon_n` how many measurements the source
holds for that horizon (1 here: one value per horizon).

A column is an ordinary R vector, so the usual functions work:

``` r

x$ph_cacl2
#> [1] 3.9 3.5 4.2 3.9 3.5
mean(x$ph_cacl2)
#> [1] 3.8
```

`ph_cacl2` is the pH measured in a CaCl2 solution: these soils are very
acid (pH 3.5 to 4.2).

## 8. What does each column mean?

[`soil_columns()`](https://giulange.github.io/soilhub-r/reference/soil_columns.md)
describes the measurement columns of your table: unit, original code of
the source, how many horizons have a value.

``` r

info <- soil_columns(x)
info[, c("column", "units", "source_codes", "horizon_count", "multi_value_cells")]
#>                                column      units source_codes horizon_count
#> 1 bulk_density_fine_earth_field_moist     kg/dm³       bdfifm             1
#> 2                             cec_ph7 cmol(c)/kg       cecph7             3
#> 3                      organic_carbon       g/kg         orgc             5
#> 4                            ph_cacl2                    phca             5
#> 5             total_nitrogen_kjeldahl       g/kg       nitkjd             3
#>   multi_value_cells
#> 1                 0
#> 2                 0
#> 3                 0
#> 4                 0
#> 5                 0
```

`source_codes` is the original WoSIS code (`orgc` for organic carbon):
the package keeps the original terms of the source. `horizon_count` says
how many of the horizons read have a value: here bulk density was
measured in one horizon only.

**Cells with several values.** In WoSIS a few cells hold more than one
measurement of the same horizon (for example two clay contents from two
analyses). Then the column (for example `clay`) holds the **mean** of
the values, as WoSIS publishes it, and an extra column `clay_values`
keeps all the original values. `multi_value_cells` above counts such
cells: there are none in this small example, so there is no `_values`
column.

## 9. Save your data

Save the table with [`saveRDS()`](https://rdrr.io/r/base/readRDS.html)
and read it back later with
[`readRDS()`](https://rdrr.io/r/base/readRDS.html). Here we use a
temporary folder; use your own folder in practice.

``` r

file <- file.path(tempdir(), "vancouver-horizons.rds")
saveRDS(x, file)
y <- readRDS(file)
nrow(y)
#> [1] 5
```

Save your **data**, never the session object `soil`: it contains your
sign-in, which must not end up in a file or in a shared project.

## 10. Cite the data

Every dataset has its own citation and licence.
[`soil_citations()`](https://giulange.github.io/soilhub-r/reference/soil_citations.md)
tells you what to cite for the data you read:

``` r

citations <- soil_citations(x)
citations$citation_text
#> [1] "Batjes NH, Calisto L and de Sousa LM, 2024. WoSIS-latest: Standardised world soil profile data. ISRIC Soil Data Hub resource identifier: https://tinyurl.com/39xhaa9d. Date downloaded: 15/01/2024."
```

`soil_licences(x)` gives the terms of use in the same way. The page [How
to cite](https://giulange.github.io/soilhub-r/articles/how-to-cite.md)
explains what to cite (the data and the hub) and what the licences
allow.

## 11. Sign out

At the end you can sign out; this forgets the sign-in kept in memory.

``` r

soil_logout(soil)
```

## Where to go next

- [`vignette("raw-vs-revised", package = "soilhub")`](https://giulange.github.io/soilhub-r/articles/raw-vs-revised.md):
  the data as published by ISRIC, and the documented corrections you can
  ask for.
- [`vignette("first-layer", package = "soilhub")`](https://giulange.github.io/soilhub-r/articles/first-layer.md):
  the first (surface) layer of each profile, and the soil map components
  of SOTER and SOTWIS.
- [`vignette("exports", package = "soilhub")`](https://giulange.github.io/soilhub-r/articles/exports.md):
  large selections and files for GIS.
- [`vignette("writing-data", package = "soilhub")`](https://giulange.github.io/soilhub-r/articles/writing-data.md):
  publishing derived values (special rights needed).
