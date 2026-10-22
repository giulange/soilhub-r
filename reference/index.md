# Package index

## Session and identity

- [`soil_connect()`](https://giulange.github.io/soilhub-r/reference/soil_connect.md)
  : Connect to the Global Soil Data Hub
- [`soil_login()`](https://giulange.github.io/soilhub-r/reference/soil_login.md)
  : Sign in, or sign in again
- [`soil_logout()`](https://giulange.github.io/soilhub-r/reference/soil_logout.md)
  : Sign out
- [`soil_session()`](https://giulange.github.io/soilhub-r/reference/soil_session.md)
  : The default session
- [`soil_whoami()`](https://giulange.github.io/soilhub-r/reference/soil_whoami.md)
  : Who is signed in, and what they may do

## Discovery and catalog

- [`soil_capabilities()`](https://giulange.github.io/soilhub-r/reference/soil_capabilities.md)
  : The capabilities of the server
- [`soil_api_info()`](https://giulange.github.io/soilhub-r/reference/soil_api_info.md)
  : Versions, liveness and compatibility of the API
- [`soil_datasets()`](https://giulange.github.io/soilhub-r/reference/soil_datasets.md)
  : The datasets of the catalog
- [`soil_dataset()`](https://giulange.github.io/soilhub-r/reference/soil_dataset.md)
  : One dataset of the catalog
- [`soil_citations()`](https://giulange.github.io/soilhub-r/reference/soil_citations.md)
  [`soil_licences()`](https://giulange.github.io/soilhub-r/reference/soil_citations.md)
  : What to cite, and under which terms
- [`soil_formats()`](https://giulange.github.io/soilhub-r/reference/soil_formats.md)
  : Export formats
- [`soil_variables()`](https://giulange.github.io/soilhub-r/reference/soil_variables.md)
  : The variable catalog
- [`soil_variable_mappings()`](https://giulange.github.io/soilhub-r/reference/soil_variable_mappings.md)
  : What each source code means in each dataset
- [`soil_countries()`](https://giulange.github.io/soilhub-r/reference/soil_countries.md)
  : The country inventory
- [`soil_country()`](https://giulange.github.io/soilhub-r/reference/soil_country.md)
  : One country by dataset and variable
- [`soil_code_lists()`](https://giulange.github.io/soilhub-r/reference/soil_code_lists.md)
  : Source code lists
- [`soil_code_list()`](https://giulange.github.io/soilhub-r/reference/soil_code_list.md)
  : Rows of one source code list
- [`soil_ttr_flag_legend()`](https://giulange.github.io/soilhub-r/reference/soil_ttr_flag_legend.md)
  : Legend of the SOTWIS taxotransfer flags

## Reads

- [`soil_observations()`](https://giulange.github.io/soilhub-r/reference/soil_observations.md)
  : Soil observations: one row per horizon or per observation
- [`soil_features()`](https://giulange.github.io/soilhub-r/reference/soil_features.md)
  : Soil features: where the profiles and map units are

## Summaries

- [`soil_summary()`](https://giulange.github.io/soilhub-r/reference/soil_summary.md)
  : What a selection holds, before reading it
- [`soil_availability()`](https://giulange.github.io/soilhub-r/reference/soil_availability.md)
  : What exists by dataset, country and variable
- [`soil_consistency()`](https://giulange.github.io/soilhub-r/reference/soil_consistency.md)
  : Authoritative distinct totals

## Thematic reads

Published derived values, soil-health scores, the resolution of source
identities to canonical ids and the SOTWIS taxotransfer flags.

- [`soil_values()`](https://giulange.github.io/soilhub-r/reference/soil_values.md)
  : Published derived values
- [`soil_values_summary()`](https://giulange.github.io/soilhub-r/reference/soil_values_summary.md)
  : Counts of published derived values
- [`soil_health_scores()`](https://giulange.github.io/soilhub-r/reference/soil_health_scores.md)
  : Soil-health scores
- [`soil_health_summary()`](https://giulange.github.io/soilhub-r/reference/soil_health_summary.md)
  : Counts of soil-health scores
- [`soil_resolve_targets()`](https://giulange.github.io/soilhub-r/reference/soil_resolve_targets.md)
  : Canonical ids of source records
- [`soil_ttr_flags()`](https://giulange.github.io/soilhub-r/reference/soil_ttr_flags.md)
  : SOTWIS taxotransfer flags

## Exports

Whole selections as files (GeoPackage, GeoJSON, CSV, TSV, Shapefile),
followed, downloaded and read back as typed tables.

- [`soil_export()`](https://giulange.github.io/soilhub-r/reference/soil_export.md)
  : Export a selection
- [`soil_export_status()`](https://giulange.github.io/soilhub-r/reference/soil_export_status.md)
  [`soil_export_wait()`](https://giulange.github.io/soilhub-r/reference/soil_export_status.md)
  [`soil_export_download()`](https://giulange.github.io/soilhub-r/reference/soil_export_status.md)
  [`soil_export_cancel()`](https://giulange.github.io/soilhub-r/reference/soil_export_status.md)
  : Follow, download and cancel an export
- [`soil_export_read()`](https://giulange.github.io/soilhub-r/reference/soil_export_read.md)
  : Read the files of an export
- [`soil_export_from_error()`](https://giulange.github.io/soilhub-r/reference/soil_export_from_error.md)
  : Export the selection of a refused read

## Results

- [`` `[`( ``*`<soil_table>`*`)`](https://giulange.github.io/soilhub-r/reference/soil_table.md)
  [`as.data.frame(`*`<soil_table>`*`)`](https://giulange.github.io/soilhub-r/reference/soil_table.md)
  [`print(`*`<soil_table>`*`)`](https://giulange.github.io/soilhub-r/reference/soil_table.md)
  [`summary(`*`<soil_table>`*`)`](https://giulange.github.io/soilhub-r/reference/soil_table.md)
  : Tables returned by the reads
- [`soil_metadata()`](https://giulange.github.io/soilhub-r/reference/soil_metadata.md)
  [`soil_warnings()`](https://giulange.github.io/soilhub-r/reference/soil_metadata.md)
  : Metadata and warnings of a result
- [`soil_columns()`](https://giulange.github.io/soilhub-r/reference/soil_columns.md)
  : Typing of the variable columns of a wide table
- [`soil_flags()`](https://giulange.github.io/soilhub-r/reference/soil_flags.md)
  : Value flags of a table
- [`soil_markings()`](https://giulange.github.io/soilhub-r/reference/soil_markings.md)
  : Markings of a table
- [`soil_revised_rules()`](https://giulange.github.io/soilhub-r/reference/soil_revised_rules.md)
  : Revised rules applied to a result
- [`soil_first_layer()`](https://giulange.github.io/soilhub-r/reference/soil_first_layer.md)
  : First-layer vocabulary of a table

## Writing data

Variables, products, versions and runs, publication of derived values
and soil-health scores (rights `soil:publish`, `soil:admin`).

- [`soil_register_variable()`](https://giulange.github.io/soilhub-r/reference/soil_register_variable.md)
  : Register a variable
- [`soil_product()`](https://giulange.github.io/soilhub-r/reference/soil_product.md)
  : Register a product
- [`soil_product_version()`](https://giulange.github.io/soilhub-r/reference/soil_product_version.md)
  : Register an immutable product version
- [`soil_run_open()`](https://giulange.github.io/soilhub-r/reference/soil_run_open.md)
  [`soil_run_complete()`](https://giulange.github.io/soilhub-r/reference/soil_run_open.md)
  [`soil_run_fail()`](https://giulange.github.io/soilhub-r/reference/soil_run_open.md)
  : Open, complete or fail a run
- [`soil_publish_values()`](https://giulange.github.io/soilhub-r/reference/soil_publish_values.md)
  : Publish derived values
- [`soil_publish_health()`](https://giulange.github.io/soilhub-r/reference/soil_publish_health.md)
  : Publish soil-health scores
- [`soil_publish_source()`](https://giulange.github.io/soilhub-r/reference/soil_publish_source.md)
  : Publish a source release: features, profiles, horizons, observations
- [`soil_source_validate()`](https://giulange.github.io/soilhub-r/reference/soil_source_validate.md)
  [`soil_source_promote()`](https://giulange.github.io/soilhub-r/reference/soil_source_validate.md)
  : Validate or promote a source ingest job

## Jobs

- [`soil_job()`](https://giulange.github.io/soilhub-r/reference/soil_job.md)
  : The status of an asynchronous job
- [`soil_job_wait()`](https://giulange.github.io/soilhub-r/reference/soil_job_wait.md)
  : Wait for a job to end
- [`soil_job_cancel()`](https://giulange.github.io/soilhub-r/reference/soil_job_cancel.md)
  : Cancel a job
- [`soil_refresh_countries()`](https://giulange.github.io/soilhub-r/reference/soil_refresh_countries.md)
  : Refresh the country inventory

## Configuration and errors

- [`soilhub-config`](https://giulange.github.io/soilhub-r/reference/soilhub-config.md)
  : Configuration of soilhub
- [`soilhub-errors`](https://giulange.github.io/soilhub-r/reference/soilhub-errors.md)
  [`soilhub_error`](https://giulange.github.io/soilhub-r/reference/soilhub-errors.md)
  [`soilhub_argument_error`](https://giulange.github.io/soilhub-r/reference/soilhub-errors.md)
  [`soilhub_dependency_error`](https://giulange.github.io/soilhub-r/reference/soilhub-errors.md)
  [`soilhub_auth_error`](https://giulange.github.io/soilhub-r/reference/soilhub-errors.md)
  [`soilhub_permission_error`](https://giulange.github.io/soilhub-r/reference/soilhub-errors.md)
  [`soilhub_api_error`](https://giulange.github.io/soilhub-r/reference/soilhub-errors.md)
  [`soilhub_validation_error`](https://giulange.github.io/soilhub-r/reference/soilhub-errors.md)
  [`soilhub_load_limit_error`](https://giulange.github.io/soilhub-r/reference/soilhub-errors.md)
  [`soilhub_not_found_error`](https://giulange.github.io/soilhub-r/reference/soilhub-errors.md)
  [`soilhub_conflict_error`](https://giulange.github.io/soilhub-r/reference/soilhub-errors.md)
  [`soilhub_unavailable_error`](https://giulange.github.io/soilhub-r/reference/soilhub-errors.md)
  [`soilhub_capability_error`](https://giulange.github.io/soilhub-r/reference/soilhub-errors.md)
  [`soilhub_job_error`](https://giulange.github.io/soilhub-r/reference/soilhub-errors.md)
  : Errors signalled by soilhub

## Terms

The words of the hub and of its sources (feature, profile, component,
horizon, observation, PRID, HONU, SUID, CLAF, first_layer_status, …).

- [`soilhub-terms`](https://giulange.github.io/soilhub-r/reference/soilhub-terms.md)
  [`soilhub_terms`](https://giulange.github.io/soilhub-r/reference/soilhub-terms.md)
  : Terms used by soilhub
- [`soilhub`](https://giulange.github.io/soilhub-r/reference/soilhub-package.md)
  [`soilhub-package`](https://giulange.github.io/soilhub-r/reference/soilhub-package.md)
  : soilhub: R Client for the Global Soil Data Hub API
