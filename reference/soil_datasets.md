# The datasets of the catalog

One row per dataset of the Global Soil Data Hub (`GET /datasets`), with
the release mirrored now and its provenance, the licence and the
citation of the provider, and the catalog notes. Texts are the
provider's own, verbatim: use
[`soil_citations()`](https://giulange.github.io/soilhub-r/reference/soil_citations.md)
and
[`soil_licences()`](https://giulange.github.io/soilhub-r/reference/soil_citations.md)
for what to cite and under which terms.

## Usage

``` r
soil_datasets(soil = soil_session())
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

## Value

A data frame, one row per dataset: `name`, `title`, `provider_code`,
`description`, `support_type`, `geometry_class`, `release_code`,
`release_status`, the counts `feature_count`, `profile_count`,
`horizon_count`, `observation_count` (double), `country_codes` (list of
character), `licence_text`, `licence_url`, `licence_source_url`,
`licence_retrieved_on` (Date), `licence_note`, `citation_text`,
`citation_source_url`, `citation_retrieved_on` (Date), `citation_note`,
the provenance of the release `release_acquired_at`,
`release_released_at` (POSIXct, UTC), `release_source_url`,
`release_source_version`, `release_source_doi`, `release_reconstructed`
(logical), `release_note`, `retired_row_count` (rows whose source left
the provider, still served), `source_assets` (list of data frames: the
files kept for the release, `asset_role`, `local_path`, `source_url`,
`checksum_sha256`, `byte_size`, `media_type`, `source_record_id`,
`source_title`, `source_version`, `source_published_on`,
`file_modified_at`), `notes` (list of data frames: `key`, `kind`
(`note`, `raw_only`, `citation`, `licence`), `source_record_id`,
`source_dataset_name`, `title`, `body`, `details` (list), `decision`),
and `default_geometry_kind`, `geometry_available`, `schema_name`. Fields
the API adds later are kept as list columns (with a
`soilhub_contract_warning`).

## Details

Terms: a **dataset** is a hub collection of one provider
(`wosis_points`, `wise_profiles`, `soter_profiles`, `soter_polygons`,
`sotwis_polygons`, `sotwis_components`, `sotwis_estimates`); a
**release** is one download of it from the provider (`release_code`,
`legacy_materialized` for the data loaded before the provenance was
recorded, then `release_reconstructed = TRUE`); a **source dataset** is
one record of the provider inside a hub dataset (a SOTER country
database, a SOTWIS package), named in the notes by `source_record_id`
(ISRIC data hub record) and `source_dataset_name`.

Rights: `soil:summary`.

## See also

[`soil_dataset()`](https://giulange.github.io/soilhub-r/reference/soil_dataset.md),
[`soil_citations()`](https://giulange.github.io/soilhub-r/reference/soil_citations.md),
[`soil_licences()`](https://giulange.github.io/soilhub-r/reference/soil_citations.md)

Other discovery:
[`soil_api_info()`](https://giulange.github.io/soilhub-r/reference/soil_api_info.md),
[`soil_capabilities()`](https://giulange.github.io/soilhub-r/reference/soil_capabilities.md),
[`soil_citations()`](https://giulange.github.io/soilhub-r/reference/soil_citations.md),
[`soil_code_list()`](https://giulange.github.io/soilhub-r/reference/soil_code_list.md),
[`soil_code_lists()`](https://giulange.github.io/soilhub-r/reference/soil_code_lists.md),
[`soil_countries()`](https://giulange.github.io/soilhub-r/reference/soil_countries.md),
[`soil_country()`](https://giulange.github.io/soilhub-r/reference/soil_country.md),
[`soil_dataset()`](https://giulange.github.io/soilhub-r/reference/soil_dataset.md),
[`soil_formats()`](https://giulange.github.io/soilhub-r/reference/soil_formats.md),
[`soil_ttr_flag_legend()`](https://giulange.github.io/soilhub-r/reference/soil_ttr_flag_legend.md),
[`soil_variable_mappings()`](https://giulange.github.io/soilhub-r/reference/soil_variable_mappings.md),
[`soil_variables()`](https://giulange.github.io/soilhub-r/reference/soil_variables.md)

## Examples

``` r
if (FALSE) { # \dontrun{
ds <- soil_datasets(soil)
ds[, c("name", "release_code", "profile_count", "observation_count")]
ds$notes[[which(ds$name == "sotwis_polygons")]][, c("kind", "title")]
} # }
```
