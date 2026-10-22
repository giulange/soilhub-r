# Legend of the SOTWIS taxotransfer flags

What the codes of the `SOTERflagTTRrules` table mean
(`GET /sotwis/ttr-flags/legend`): per group of flag columns
(`flag_columns`, e.g. `TTRsub`, `TTRmain`) and symbol, the `meaning` and
the `source_reference` (report and page) where a report documents it;
`documented = FALSE` and no meaning otherwise. `applies_to` lists the
source datasets of an entry that holds for some of them only (`NULL`:
all).

## Usage

``` r
soil_ttr_flag_legend(soil = soil_session())
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

## Value

A data frame: `flag_table`, `flag_columns` (list of character),
`symbol`, `symbol_kind`, `applies_to` (list of data frames
`source_record_id`, `source_dataset_name`, or `NULL`), `meaning`,
`documented` (logical), `source_reference`, `note`, `provider_code`.

## Details

Rights: `soil:summary`. Capability: `sotwis_ttr_flags`.

## See also

Other discovery:
[`soil_api_info()`](https://giulange.github.io/soilhub-r/reference/soil_api_info.md),
[`soil_capabilities()`](https://giulange.github.io/soilhub-r/reference/soil_capabilities.md),
[`soil_citations()`](https://giulange.github.io/soilhub-r/reference/soil_citations.md),
[`soil_code_list()`](https://giulange.github.io/soilhub-r/reference/soil_code_list.md),
[`soil_code_lists()`](https://giulange.github.io/soilhub-r/reference/soil_code_lists.md),
[`soil_countries()`](https://giulange.github.io/soilhub-r/reference/soil_countries.md),
[`soil_country()`](https://giulange.github.io/soilhub-r/reference/soil_country.md),
[`soil_dataset()`](https://giulange.github.io/soilhub-r/reference/soil_dataset.md),
[`soil_datasets()`](https://giulange.github.io/soilhub-r/reference/soil_datasets.md),
[`soil_formats()`](https://giulange.github.io/soilhub-r/reference/soil_formats.md),
[`soil_variable_mappings()`](https://giulange.github.io/soilhub-r/reference/soil_variable_mappings.md),
[`soil_variables()`](https://giulange.github.io/soilhub-r/reference/soil_variables.md)

## Examples

``` r
if (FALSE) { # \dontrun{
legend <- soil_ttr_flag_legend(soil)
legend[!legend$documented, c("symbol", "note")]
} # }
```
