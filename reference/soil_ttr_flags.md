# SOTWIS taxotransfer flags

Which taxotransfer rules produced each SOTWIS estimate: the rows of the
source table `SOTERflagTTRrules` (`GET /sotwis/ttr-flags`) linked to the
profiles and horizons of `sotwis_estimates`, with the source columns
verbatim (`CLAF`, `PRID`, `Layer`, `Newtopdep`, `Newbotdep`, `TTRsub`,
`TTRmain`, `TTRfinal`, `TTRexpert`). The codes are explained by
[`soil_ttr_flag_legend()`](https://giulange.github.io/soilhub-r/reference/soil_ttr_flag_legend.md).

## Usage

``` r
soil_ttr_flags(
  soil = soil_session(),
  source_dataset = NULL,
  prid = NULL,
  claf = NULL,
  layer = NULL,
  feature_id = NULL,
  horizon_id = NULL,
  view = "raw",
  max_rows = Inf
)
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

- source_dataset:

  One SOTWIS source dataset (record id or name). API query parameter
  `source_dataset`.

- prid:

  One profile id (`PRID`). API query parameter `prid`.

- claf:

  One soil unit code (`CLAF`). API query parameter `claf`.

- layer:

  One layer (`Layer`, e.g. `"D1"`). API query parameter `layer`.

- feature_id, horizon_id:

  One canonical feature or horizon id (UUID). API query parameters
  `feature_id` and `horizon_id`.

- view:

  `"raw"` (sent explicitly) or `"revised"`. API query parameter `view`.

- max_rows:

  Maximum number of rows to read (`Inf`: all). Client-side; caps the API
  query parameter `limit` of each page request.

## Value

A data frame: `flag_id`, `feature_id`, `profile_id`, `horizon_id`,
`source_record_id`, `source_dataset_name`, `source_table`,
`source_row_number`, `sub_layer_number` (integer), then the source
columns `CLAF`, `PRID`, `Layer`, `Newtopdep`, `Newbotdep` (double),
`TTRsub`, `TTRmain`, `TTRfinal`, `TTRexpert`. Attribute `soil_metadata`
(see
[`soil_metadata()`](https://giulange.github.io/soilhub-r/reference/soil_metadata.md)).

## Details

With `view = "revised"` a `prid` filter also matches the spellings of
the same profile id that differ only by case (rule R6); the spellings
linked are listed in `soil_metadata(x)$revised`.

Rights: `soil:read`. Capabilities: `sotwis_ttr_flags`; `revised_view`
for `view = "revised"`.

## See also

Other thematic reads:
[`soil_health_scores()`](https://giulange.github.io/soilhub-r/reference/soil_health_scores.md),
[`soil_health_summary()`](https://giulange.github.io/soilhub-r/reference/soil_health_summary.md),
[`soil_resolve_targets()`](https://giulange.github.io/soilhub-r/reference/soil_resolve_targets.md),
[`soil_values()`](https://giulange.github.io/soilhub-r/reference/soil_values.md),
[`soil_values_summary()`](https://giulange.github.io/soilhub-r/reference/soil_values_summary.md)

## Examples

``` r
if (FALSE) { # \dontrun{
f <- soil_ttr_flags(soil, claf = "LVh", layer = "D1")
table(f$TTRfinal)
legend <- soil_ttr_flag_legend(soil)
} # }
```
