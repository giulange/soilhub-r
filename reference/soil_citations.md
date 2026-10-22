# What to cite, and under which terms

`soil_citations()` returns the citation texts of datasets,
`soil_licences()` their licences, both **verbatim** as the providers
publish them (never rewritten), with the address they were read from and
the date of reading.

## Usage

``` r
soil_citations(x, soil = soil_session())

soil_licences(x, soil = soil_session())
```

## Arguments

- x:

  What to cite: dataset names (character), rows of
  [`soil_datasets()`](https://giulange.github.io/soilhub-r/reference/soil_datasets.md),
  a
  [`soil_dataset()`](https://giulange.github.io/soilhub-r/reference/soil_dataset.md),
  or a result carrying the catalog rows of its datasets in its metadata
  (a `soil_table`, `soil_summary` or `soil_export`). Client-side: not
  sent to the API.

- soil:

  A session; the default session when omitted (needed only when `x`
  holds dataset names). Client-side: not sent to the API.

## Value

`soil_citations()`: a data frame `dataset`, `citation_text`,
`citation_source_url`, `citation_retrieved_on` (Date), `citation_note`,
`level`, `label`, `note_key`, `source_record_id`, `source_dataset_name`,
`record_title`.

`soil_licences()`: a data frame `dataset`, `licence_text`,
`licence_url`, `licence_source_url`, `licence_retrieved_on` (Date),
`licence_note`, `level`, `label`, `note_key`, `source_record_id`,
`source_dataset_name`, `record_title`.

## Details

When a dataset has one text (`citation_text`, `licence_text` of
[`soil_datasets()`](https://giulange.github.io/soilhub-r/reference/soil_datasets.md)),
it is one row with `level = "dataset"`. When it has none (SOTER: the
licence differs between source datasets and the records publish no
citation; SOTWIS: no citation text), the rows are the catalog notes of
kind `citation` / `licence`, one per source dataset, with
`level = "source dataset"` and `label` the title the API gives them
(e.g. "Citation proposal of the ISRIC data hub", a proposal built by the
ISRIC data hub from the record, not a text of the authors; "Licence
(ISRIC data hub record)"). The dataset's `citation_note` /
`licence_note` explains where the texts are. A dataset with neither text
nor notes gives one row with an `NA` text.

Rights: `soil:summary` (the catalog is read once per session).

## See also

Other discovery:
[`soil_api_info()`](https://giulange.github.io/soilhub-r/reference/soil_api_info.md),
[`soil_capabilities()`](https://giulange.github.io/soilhub-r/reference/soil_capabilities.md),
[`soil_code_list()`](https://giulange.github.io/soilhub-r/reference/soil_code_list.md),
[`soil_code_lists()`](https://giulange.github.io/soilhub-r/reference/soil_code_lists.md),
[`soil_countries()`](https://giulange.github.io/soilhub-r/reference/soil_countries.md),
[`soil_country()`](https://giulange.github.io/soilhub-r/reference/soil_country.md),
[`soil_dataset()`](https://giulange.github.io/soilhub-r/reference/soil_dataset.md),
[`soil_datasets()`](https://giulange.github.io/soilhub-r/reference/soil_datasets.md),
[`soil_formats()`](https://giulange.github.io/soilhub-r/reference/soil_formats.md),
[`soil_ttr_flag_legend()`](https://giulange.github.io/soilhub-r/reference/soil_ttr_flag_legend.md),
[`soil_variable_mappings()`](https://giulange.github.io/soilhub-r/reference/soil_variable_mappings.md),
[`soil_variables()`](https://giulange.github.io/soilhub-r/reference/soil_variables.md)

## Examples

``` r
if (FALSE) { # \dontrun{
soil_citations("wosis_points")
soil_citations(c("soter_profiles", "sotwis_polygons"))[, c("dataset", "label", "citation_text")]
soil_licences("soter_profiles")[, c("source_dataset_name", "licence_text")]
} # }
```
