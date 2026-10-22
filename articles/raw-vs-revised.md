# Raw and revised data

``` r

library(soilhub)
```

This guide explains the two **views** of the data: `view = "raw"` and
`view = "revised"`. It assumes you have signed in as shown in
[`vignette("soilhub", package = "soilhub")`](https://giulange.github.io/soilhub-r/articles/soilhub.md)
(`soil <- soil_connect()`). The outputs were recorded from the Global
Soil Data Hub API in October 2026.

## The principle

The hub is a **mirror** of the ISRIC databases (WoSIS, WISE, SOTER,
SOTWIS): the values, units and codes are kept **as ISRIC published
them**, including their known defects (an impossible value, a duplicated
layer, an estimate stored as a measurement). This is the **raw** view,
the default.

Some defects are documented and have a clear rule. The **revised** view
applies those rules on the server: it hides or flags values and rows,
and tells you, in the answer, which rules it applied and how many values
each one touched. Nothing is changed in the database, and the R package
never corrects a value by itself: it only shows what the server did.

## A raw read

We read the first five horizons of WoSIS around Vancouver (Canada), in
the raw view (the default).

``` r

vancouver <- c(-123.3, 49.0, -122.9, 49.4)
raw <- soil_observations(soil, datasets = "wosis_points", bbox = vancouver, max_rows = 5)
```

We look at the depths and at the bulk density of the field-moist fine
earth:

``` r

raw[, c("horizon_name", "upper_depth_cm", "lower_depth_cm", "bulk_density_fine_earth_field_moist")]
#> # soilhub wide table: 5 horizons, 5 variables | wosis_points | view raw, layer all
#> # no API warnings (soil_warnings), typing (soil_columns), cite with soil_citations()
#> # incomplete read: continue with offset = 5 (soil_metadata(x)$next_offset)
#>   horizon_name upper_depth_cm lower_depth_cm bulk_density_fine_earth_field_moist
#> 1            F              0              1                                  NA
#> 2           Ae              1              2                                  NA
#> 3           Bf              2             17                                  NA
#> 4            F              0              1                                 1.6
#> 5           Ae              1              2                                  NA
```

Only the fourth horizon (an organic F layer) has a bulk density: 1.6
kg/dm³.

## The same read, revised

The same selection with `view = "revised"`:

``` r

revised <- soil_observations(soil, datasets = "wosis_points", bbox = vancouver,
                             view = "revised", max_rows = 5)
```

Is the bulk density column still there?

``` r

"bulk_density_fine_earth_field_moist" %in% names(revised)
#> [1] FALSE
```

No: in the revised view the value 1.6 is hidden, and since no other
horizon of these five has a value, the whole column disappears.

## Which rules were applied?

[`soil_revised_rules()`](https://giulange.github.io/soilhub-r/reference/soil_revised_rules.md)
lists the rules applied to your selection:

``` r

soil_revised_rules(revised)
#>    id
#> 1 R17
#>                                                                                                           title
#> 1 WoSIS BDFIFM elements 'guessed value, expert field estimate' excluded (the cell disappears when none remains)
#>   issue        effect n
#> 1   #70 values_hidden 1
```

How to read it:

- `id` is the number of the rule (R17);
- `title` says what the rule does: WoSIS bulk densities recorded as a
  “guessed value, expert field estimate” are not measurements, so they
  are excluded;
- `issue` is the issue of the API project where the rule was discussed;
- `effect` is what it did (`values_hidden`: values removed from the
  answer);
- `n` is how many values it touched.

## Where exactly? The markings

The package collects every marking of the rows in one long table, with
[`soil_markings()`](https://giulange.github.io/soilhub-r/reference/soil_markings.md).
We keep only the markings of the revised view (`scope` equal to
`"hidden_value"`):

``` r

marks <- soil_markings(revised)
marks[marks$scope == "hidden_value", ]
#>    row                           horizon_id        scope column marking    value
#> 15   4 43763a16-03f3-4ee1-9892-a6bd646c5fc7 hidden_value bdfifm     R17 ["1.60"]
```

Row 4 of the table, column `bdfifm` (the WoSIS code of this bulk
density): the value `1.60` was hidden by rule R17. The original value
stays visible here, so you always know what was removed.

The raw view already carried the reason. In the markings of the raw
table, the cell has `source_method_kind` “guessed value, expert field
estimate”, as recorded by WoSIS:

``` r

raw_marks <- soil_markings(raw)
raw_marks[raw_marks$marking == "source_method_kind", ]
#>    row                           horizon_id scope                              column
#> 13   4 43763a16-03f3-4ee1-9892-a6bd646c5fc7  cell bulk_density_fine_earth_field_moist
#>               marking                                value
#> 13 source_method_kind guessed value, expert field estimate
```

The other markings (`method_facets`) describe the laboratory method of
each value, for example “sieved over 2 mm sieve” or “buffered at 7.0”
for the cation exchange capacity.

## Value flags

Some rules do not hide a value but **flag** it (for example an extreme
value). The flags are in the column `value_flags`, and
[`soil_flags()`](https://giulange.github.io/soilhub-r/reference/soil_flags.md)
lists them in a long table:

``` r

soil_flags(revised)
#> [1] row        horizon_id column     flag      
#> <0 rows> (or 0-length row.names)
```

None of these five horizons has a flag: the table is empty.

## Retired rows

When ISRIC removes a profile or a value from a new release, the hub
keeps it and says so: the column `retired_in_release` holds the release
in which the row left the source (`NA` when it is still current).

``` r

raw$retired_in_release
#> [1] NA NA NA NA NA
```

All five horizons are current.

## Counts are over the whole selection

The counts `n` of
[`soil_revised_rules()`](https://giulange.github.io/soilhub-r/reference/soil_revised_rules.md)
are computed over your **whole selection**, not only over the rows you
read. Here we read five observations of the SOTER polygons in the long
layout (one row per measured value) and the revised view:

``` r

soter <- soil_observations(soil, datasets = "soter_polygons", layout = "long",
                           view = "revised", max_rows = 5)
soter[, c("horizon_name", "property_code", "value", "unit")]
#> # soilhub long table: 5 observations | soter_polygons | view revised, layer all | 364,051 in the selection
#> # no API warnings (soil_warnings), markings (soil_markings), cite with soil_citations()
#> # incomplete read: continue with offset = 5 (soil_metadata(x)$next_offset)
#>   horizon_name property_code value       unit
#> 1           Aa          cecs  25.0 cmol(c)/kg
#> 2           Aa          clpc  39.0      % w/w
#> 3           Aa          fede   1.0      % w/w
#> 4           Aa          p2o5 300.0      mg/kg
#> 5           Aa          phaq   7.8       <NA>
```

``` r

soil_revised_rules(soter)
#>    id
#> 1 R12
#> 2 R12
#> 3 R14
#> 4 R15
#>                                                                                                                                            title
#> 1                  values impossible for the declared unit excluded; extremes flagged extreme; WoSIS PHPRTN above 100 flagged above_unit_maximum
#> 2                  values impossible for the declared unit excluded; extremes flagged extreme; WoSIS PHPRTN above 100 flagged above_unit_maximum
#> 3 SOTER: empty rows skipped by layer=first; Nepal top_depth_cm from the first number of HBDE_ORIGINAL (top_depth_from_hbde_original, open_ended)
#> 4                                                           SOTER orphan horizons whose PRID differs only by case joined to the existing profile
#>           issue                 effect  n
#> 1 #54, #70, #71 values_flagged:extreme 92
#> 2 #54, #70, #71          values_hidden  2
#> 3           #53  rows_top_depth_filled 53
#> 4           #53            rows_joined  6
```

Three rules acted on the SOTER polygons (R12 appears twice, once per
effect): for example R12 flagged 92 extreme values and hid 2 impossible
values in the whole dataset, although our five rows show none of them.
The header line also says how big the selection is: 364,051
observations.

## The list of rules

The rules the server knows are listed in its capabilities. This loop
prints the number and the title of each one:

``` r

rules <- soil_capabilities(soil)$views$revised_rules
for (rule in rules) {
  cat(rule$id, ":", rule$title, "\n")
}
#> R2 : layer=first: a first horizon starting within 5 cm counts as surface (surface_within_5cm); beyond 5 cm no first horizon (WoSIS, WISE) 
#> R3 : layer=first: first mineral horizon (WoSIS organic_surface false; SOTER HBDE >= 0 or null), first_mineral 
#> R4 : SOTWIS identical source rows (CAF RW41): one layer, the copies hidden 
#> R5 : SOTWIS SOTERsummaryFile_T1S1D1 layers hidden (declared copy of the D1 layer) 
#> R6 : SOTWIS PRID linked without case between summary and estimates (and the TTR flags of /sotwis/ttr-flags) where no estimate profile has the same spelling; pairs listed 
#> R7 : SOTWIS CECc and ELCO of the SN-GM, TN, UT summary rows read from the estimates (value_from_estimates) 
#> R8 : SOTER profile repeated in a national or more specific dataset: when the original (ZA, AR/CU, UT) is in the selection, the values of the copy (SAF, LAC, KE) that the original holds with the same value are hidden; values only in the copy stay (kept_from_copy), differing values stay on both (values_differ) 
#> R9 : negative value of a non-negative quantity = missing (SOTWIS codes, WISE CACO3 -1); the code in revised_markings.hidden_values 
#> R10 : WISE 'Not measured' per laboratory and property: zeros of group 1 = nodata (groups 2 and 3 only flagged) 
#> R11 : WISE ECE 0.1 in profiles all at 0.1: flag uniform_profile_value (no exclusion) 
#> R12 : values impossible for the declared unit excluded; extremes flagged extreme; WoSIS PHPRTN above 100 flagged above_unit_maximum 
#> R14 : SOTER: empty rows skipped by layer=first; Nepal top_depth_cm from the first number of HBDE_ORIGINAL (top_depth_from_hbde_original, open_ended) 
#> R15 : SOTER orphan horizons whose PRID differs only by case joined to the existing profile 
#> R16 : WoSIS sand + silt + clay rescaled to 100 (texture_normalized with the original sum) 
#> R17 : WoSIS BDFIFM elements 'guessed value, expert field estimate' excluded (the cell disappears when none remains) 
#> R18 : SOVEUR v1 layers equal to the v2 T1S1D1 layer of the same unit hidden (both versions are in sotwis_polygons) 
#> R19 : SOTWIS TCEQ above 120 where declared g C kg-1: flag impossible_for_declared_unit (no exclusion)
```

The full documentation of each rule is in the [API
documentation](https://soilhub.weatherprogapp.it/docs).

## In short

- Use `view = "raw"` (the default) to work with the data exactly as
  ISRIC published them.
- Use `view = "revised"` to let the server apply the documented rules.
- Always look at
  [`soil_revised_rules()`](https://giulange.github.io/soilhub-r/reference/soil_revised_rules.md)
  and, if needed,
  [`soil_markings()`](https://giulange.github.io/soilhub-r/reference/soil_markings.md)
  to know what changed.
