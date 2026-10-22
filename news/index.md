# Changelog

## soilhub 0.2.0

First release of the redesigned client: one library for every user of
the Global Soil Data Hub API, with what each user may do decided by the
rights of the account. It follows the API 0.6.0 (reads raw and revised,
first layer, profile types, components, summaries, exports, catalog with
provenance, citations and licences) and replaces the 0.1.x client.

Tested: R CMD check on Linux, macOS and Windows (R 4.1 and current, with
and without `sf`); contract tests against the API’s OpenAPI and recorded
responses of production; live acceptance on production with a read-only
account (reads of the 7 datasets, exports in 4 formats, session expiry
and recovery, a session of 4 hours of reads plus 90 minutes idle without
a new sign-in).

Known limitation: the write functions
([`soil_register_variable()`](https://giulange.github.io/soilhub-r/reference/soil_register_variable.md),
[`soil_publish_values()`](https://giulange.github.io/soilhub-r/reference/soil_publish_values.md),
[`soil_publish_health()`](https://giulange.github.io/soilhub-r/reference/soil_publish_health.md),
[`soil_publish_source()`](https://giulange.github.io/soilhub-r/reference/soil_publish_source.md),
runs and jobs) are tested against a simulated API only; the live write
acceptance with a publisher account is scheduled after this release
(giulange/soilhub-r#14).

### Changes in this release

- Documentation and site (WP11): six vignettes written for users with
  basic R, one small step per chunk with what it does and what the
  result means for a soil scientist: getting started (`soilhub`),
  `raw-vs-revised`, `first-layer`, `exports`, and `writing-data` (with
  the right each step needs). Their examples are evaluated when the
  vignettes are built, without network or login, against a local replay
  of the responses recorded from the production API
  (`tests/testthat/fixtures/recorded`; internal `replay_session()`, also
  used by the contract suite), so the outputs shown are real; sign-in,
  writes and large exports are shown but not run. New help page
  `?soilhub-terms` (feature, profile, component, horizon, observation,
  `PRID`, `HONU`, `SUID`, `TCID`, `SCID`, `CLAF`, `source_support`,
  `first_layer_status`, views, markings, rights). Every argument of the
  reference names the API field it fills (or says it is client-side);
  the session functions and the configuration and error topics have
  their `@family`. `_pkgdown.yml` lists the articles and every reference
  topic; README: install, first use, licences and
  [`soil_citations()`](https://giulange.github.io/soilhub-r/reference/soil_citations.md).

- Exports (WP7):
  [`soil_export()`](https://giulange.github.io/soilhub-r/reference/soil_export.md)
  submits a selection (the arguments of
  [`soil_observations()`](https://giulange.github.io/soilhub-r/reference/soil_observations.md),
  plus `format`, `content` and `layout`, checked against
  `soil_capabilities()$exports`: Shapefile only with
  `content = "features"`), polls it, downloads the zip into the export
  directory (`soilhub.export_dir`) and unzips it; `wait = FALSE` returns
  the job id at once.
  [`soil_export_status()`](https://giulange.github.io/soilhub-r/reference/soil_export_status.md),
  [`soil_export_wait()`](https://giulange.github.io/soilhub-r/reference/soil_export_status.md)
  (`failed`, `cancelled`, an unknown id and a timeout are
  `soilhub_job_error`s with `reason`),
  [`soil_export_download()`](https://giulange.github.io/soilhub-r/reference/soil_export_status.md)
  (streamed, never overwriting unless asked; an expired export is a
  `soilhub_not_found_error` with `reason = "expired"`) and
  [`soil_export_cancel()`](https://giulange.github.io/soilhub-r/reference/soil_export_status.md)
  (needs `soil:publish`) work from the object or the job id alone.
  [`soil_export_read()`](https://giulange.github.io/soilhub-r/reference/soil_export_read.md)
  reads the tables of every format back, typed from `metadata.json`
  exactly as the synchronous reads type them (wide, long, features; JSON
  text cells parsed back to list columns); CSV, TSV and GeoJSON need no
  package, GeoPackage and Shapefile need `sf`. `too_large = "export"` of
  [`soil_observations()`](https://giulange.github.io/soilhub-r/reference/soil_observations.md)
  and
  [`soil_features()`](https://giulange.github.io/soilhub-r/reference/soil_features.md)
  exports a refused selection and returns the same shape, with
  `soil_metadata(x)$via_export`;
  [`soil_export_from_error()`](https://giulange.github.io/soilhub-r/reference/soil_export_from_error.md)
  is its manual form.
  [`soil_columns()`](https://giulange.github.io/soilhub-r/reference/soil_columns.md),
  [`soil_citations()`](https://giulange.github.io/soilhub-r/reference/soil_citations.md)
  and
  [`soil_revised_rules()`](https://giulange.github.io/soilhub-r/reference/soil_revised_rules.md)
  work on a downloaded export.
  [`soil_values()`](https://giulange.github.io/soilhub-r/reference/soil_values.md)
  and
  [`soil_health_scores()`](https://giulange.github.io/soilhub-r/reference/soil_health_scores.md)
  accept `with_geometry = "sf"`.

- Contract tests and fixture recording (WP10): `tests/contract/` checks
  the client against the API’s OpenAPI document (committed snapshot
  `tests/contract/openapi.json`, API 0.6.0, or the live one): every path
  and method the client calls, every query parameter, JSON body field
  and form field it sends (name, type, enum value, required fields), the
  enums it offers (`selection_values`, choices of the exported functions
  such as `layout`), the response fields of its typing tables where the
  OpenAPI types them, and the API version range. The client requests are
  not listed by hand: `soil_request()` hands every request to the
  development option `soilhub.exchange_hook`, and the suite records them
  from the unit tests. `Rscript tests/contract/run.R [live]` runs it
  (not part of `R CMD check`); `.github/workflows/contract.yml` runs it
  weekly with a diff of the live `openapi.json` against the snapshot
  (`tools/update_contract_snapshots.R --check`), without secrets.
  `tools/record_fixtures.R` (run by the owner with a device login)
  records scrubbed responses of a curated set of read calls and
  `tests/contract/capabilities.json`; the suite replays them through the
  client and skips until they exist. `tools/check_version.R` checks
  `MIN_API_VERSION` / `SUPPORTED_API_MAJOR` against an OpenAPI document.
  New constant `TESTED_API_VERSION` (0.6.0, the `info.version` of the
  snapshot, kept in step by `tools/update_contract_snapshots.R` and
  checked by the contract suite): the “API is newer than this client was
  tested with” message of
  [`soil_connect()`](https://giulange.github.io/soilhub-r/reference/soil_connect.md)
  now compares with it instead of `MIN_API_VERSION` (still 0.5.0, the
  oldest server accepted), so API 0.6.x gives no message. Streamed
  downloads (the export zip) pass through the exchange hook too, so the
  contract suite sees `GET /exports/{job_id}/download`;
  `tools/record_fixtures.R --with-export` adds one small export round
  trip (off by default: an export is a job written under the user’s
  name).

- Long observations, features and geometry (WP5):
  `soil_observations(layout = "long")` reads one row per observation,
  typed per column family (`value` double, `value_raw` the source value
  verbatim as a list column, `release_id` and `value_count` integer,
  `lineage`, source descriptors and `method_facets` lists, marking
  columns, `revised_markings` with `hidden_values` as a data frame);
  `soil_metadata(x)$total_count` is the exact count of the selection. A
  multi-value WoSIS cell, for which the API extracts no number, gets the
  mean of its values in `value`, as the wide layout does.
  [`soil_features()`](https://giulange.github.io/soilhub-r/reference/soil_features.md)
  reads the features (points and (multi)polygons) with `feature_key`,
  `components` (data frames), `profile_markings` and
  `retired_in_release`, and the metadata `feature_count`,
  `feature_count_by_dataset` and `mixed_geometry`.
  `with_geometry = "sf"` returns an `sf` `soil_table` (EPSG:4326) for
  the wide and long layouts and the features; `"text"` gives WKT (wide)
  or GeoJSON (long, features) without any package. `sf` stays in
  Suggests: without it `"sf"` raises a `soilhub_dependency_error` before
  any request.
  [`soil_flags()`](https://giulange.github.io/soilhub-r/reference/soil_flags.md)
  and
  [`soil_markings()`](https://giulange.github.io/soilhub-r/reference/soil_markings.md)
  read long tables too.

- Summaries and thematic reads (WP6):
  [`soil_summary()`](https://giulange.github.io/soilhub-r/reference/soil_summary.md)
  and
  [`soil_availability()`](https://giulange.github.io/soilhub-r/reference/soil_availability.md)
  take the selection of
  [`soil_observations()`](https://giulange.github.io/soilhub-r/reference/soil_observations.md)
  (validated the same way, sent as the same body without the layout
  fields) and check the same optional capabilities;
  [`soil_summary()`](https://giulange.github.io/soilhub-r/reference/soil_summary.md)
  returns a `soil_summary` with the counts by dataset (filled with the
  total when one dataset is selected), the variable semantics, the
  revised rules and a short print method, and works with
  [`soil_metadata()`](https://giulange.github.io/soilhub-r/reference/soil_metadata.md),
  [`soil_revised_rules()`](https://giulange.github.io/soilhub-r/reference/soil_revised_rules.md)
  and
  [`soil_citations()`](https://giulange.github.io/soilhub-r/reference/soil_citations.md).
  [`soil_availability()`](https://giulange.github.io/soilhub-r/reference/soil_availability.md)
  returns data frames by dataset (distinct totals), country, dataset and
  country, and variable (with the scoped `variants`).
  [`soil_consistency()`](https://giulange.github.io/soilhub-r/reference/soil_consistency.md)
  sends its own request (no view, profile type or components) and
  returns the distinct totals with the calculation used. Thematic reads:
  [`soil_values()`](https://giulange.github.io/soilhub-r/reference/soil_values.md)
  (typed `value` column, lineage on request),
  [`soil_values_summary()`](https://giulange.github.io/soilhub-r/reference/soil_values_summary.md),
  [`soil_health_scores()`](https://giulange.github.io/soilhub-r/reference/soil_health_scores.md)
  (details on request; the arguments `run_ids` and `statuses` are the
  API fields `product_run_ids` and `score_statuses`),
  [`soil_health_summary()`](https://giulange.github.io/soilhub-r/reference/soil_health_summary.md),
  [`soil_resolve_targets()`](https://giulange.github.io/soilhub-r/reference/soil_resolve_targets.md)
  (requests of 10,000 targets, reads `targets` of the response;
  `strict = TRUE` stops on missing or ambiguous targets) and
  [`soil_ttr_flags()`](https://giulange.github.io/soilhub-r/reference/soil_ttr_flags.md)
  (`GET /sotwis/ttr-flags`, paged, source columns verbatim). Geometry of
  values and scores as GeoJSON text with `with_geometry = "text"`;
  `"sf"` follows with the geometry module.

- Wide observations (WP4):
  [`soil_observations()`](https://giulange.github.io/soilhub-r/reference/soil_observations.md)
  reads the canonical wide layout (one row per horizon) page by page,
  with the selection of every canonical read (`datasets`, `variables`,
  `bbox`, `country`, `geometry`, `layer`, `view`, `profile_type`,
  `components`, `min_cumulative_percent`) validated before any request;
  `view = "raw"` is sent explicitly. The result is a `soil_table` (a
  data frame keeping its metadata through `[`), typed by column family:
  fixed, first-layer, component, source attribute and marking columns,
  `value_flags`, retirement, revised markings, WKT geometry text
  (`with_geometry = "text"`) and the variable groups `<key>`, `_units`,
  `_method`, `_n`. Multi-value WoSIS cells: `<key>` holds the mean of
  the listed values and `<key>_values` every original value
  (`multi_value_rule = "mean"`). Pages with different column sets are
  aligned. A refused selection raises `soilhub_load_limit_error` naming
  the
  [`soil_export()`](https://giulange.github.io/soilhub-r/reference/soil_export.md)
  call of the same selection; a failure after some pages keeps them as a
  typed partial `soil_table` in `e$partial`. Result helpers:
  [`soil_metadata()`](https://giulange.github.io/soilhub-r/reference/soil_metadata.md),
  [`soil_warnings()`](https://giulange.github.io/soilhub-r/reference/soil_metadata.md),
  [`soil_columns()`](https://giulange.github.io/soilhub-r/reference/soil_columns.md),
  [`soil_flags()`](https://giulange.github.io/soilhub-r/reference/soil_flags.md),
  [`soil_markings()`](https://giulange.github.io/soilhub-r/reference/soil_markings.md),
  [`soil_revised_rules()`](https://giulange.github.io/soilhub-r/reference/soil_revised_rules.md),
  [`soil_first_layer()`](https://giulange.github.io/soilhub-r/reference/soil_first_layer.md),
  print and summary methods. `too_large = "export"` follows in a later
  work package.

- Writes and jobs (WP8), gated by the rights of the session (checked
  locally when the token declares them, else decided by the API; a 403
  is a `soilhub_permission_error` naming the right):
  [`soil_register_variable()`](https://giulange.github.io/soilhub-r/reference/soil_register_variable.md)
  (validate then register, capability `variable_registration`),
  [`soil_product()`](https://giulange.github.io/soilhub-r/reference/soil_product.md),
  [`soil_product_version()`](https://giulange.github.io/soilhub-r/reference/soil_product_version.md),
  [`soil_run_open()`](https://giulange.github.io/soilhub-r/reference/soil_run_open.md),
  [`soil_run_complete()`](https://giulange.github.io/soilhub-r/reference/soil_run_open.md),
  [`soil_run_fail()`](https://giulange.github.io/soilhub-r/reference/soil_run_open.md),
  [`soil_publish_values()`](https://giulange.github.io/soilhub-r/reference/soil_publish_values.md)
  and
  [`soil_publish_health()`](https://giulange.github.io/soilhub-r/reference/soil_publish_health.md)
  (local checks of every record, server validation, synchronous up to
  10,000 records, else an NDJSON file uploaded with its SHA-256 checksum
  as a job, never retried; receipts reconciled with the records sent,
  `soilhub_reconciliation_warning`),
  [`soil_job()`](https://giulange.github.io/soilhub-r/reference/soil_job.md),
  [`soil_job_wait()`](https://giulange.github.io/soilhub-r/reference/soil_job_wait.md),
  [`soil_job_cancel()`](https://giulange.github.io/soilhub-r/reference/soil_job_cancel.md)
  and
  [`soil_refresh_countries()`](https://giulange.github.io/soilhub-r/reference/soil_refresh_countries.md).
  A 409 is a `soilhub_conflict_error` that says what to do (the API has
  no GET for products, versions or runs); a job that fails or is
  cancelled is a `soilhub_job_error` with the rejected rows in
  `e$errors`.

- Source ingest (WP9):
  [`soil_publish_source()`](https://giulange.github.io/soilhub-r/reference/soil_publish_source.md)
  builds a provider-neutral NDJSON bundle (features from an `sf` object
  or a spatial file – a WGS84 GeoJSON file is read without `sf` – then
  profiles, components, horizons and observations), checks before any
  request the manifest, `source_record_id` (present, unique per record
  type), parent references, observation declarations, the CRS
  (transformed to EPSG:4326) and the geometry types, uploads it with its
  manifest and SHA-256 checksum (never retried), validates, verifies the
  counts staged by the API against the records sent (a difference stops
  before promotion), promotes and reconciles the published counts;
  `auto_promote = TRUE` lets the server’s ingest worker validate and
  promote while the client waits; `keep_file = TRUE` keeps the bundle.
  Unmapped property codes are a `soilhub_unmapped_properties_warning`.
  [`soil_source_validate()`](https://giulange.github.io/soilhub-r/reference/soil_source_validate.md)
  and
  [`soil_source_promote()`](https://giulange.github.io/soilhub-r/reference/soil_source_validate.md)
  run the two server steps separately.

- A 403 on a session whose token does not declare its rights no longer
  reports the rights as `FALSE`.

- Discovery and version check (WP3): after the login
  [`soil_connect()`](https://giulange.github.io/soilhub-r/reference/soil_connect.md)
  reads `/capabilities` and checks the API version (0.5.0 or later,
  major 0) and the required capabilities; an incompatible server stops
  with `soilhub_capability_error` (the signed-out session in
  `e$session`), a newer minor version prints a message. Optional
  capabilities are checked by the functions that need them (`FALSE` is
  an error, not advertised a warning). New:
  [`soil_capabilities()`](https://giulange.github.io/soilhub-r/reference/soil_capabilities.md),
  [`soil_api_info()`](https://giulange.github.io/soilhub-r/reference/soil_api_info.md),
  [`soil_datasets()`](https://giulange.github.io/soilhub-r/reference/soil_datasets.md)
  and
  [`soil_dataset()`](https://giulange.github.io/soilhub-r/reference/soil_dataset.md)
  (catalog with the provenance of the release, source assets and notes),
  [`soil_citations()`](https://giulange.github.io/soilhub-r/reference/soil_citations.md)
  and
  [`soil_licences()`](https://giulange.github.io/soilhub-r/reference/soil_citations.md)
  (provider texts verbatim, per source dataset from the notes when no
  dataset-level text exists),
  [`soil_formats()`](https://giulange.github.io/soilhub-r/reference/soil_formats.md),
  [`soil_variables()`](https://giulange.github.io/soilhub-r/reference/soil_variables.md),
  [`soil_variable_mappings()`](https://giulange.github.io/soilhub-r/reference/soil_variable_mappings.md),
  [`soil_countries()`](https://giulange.github.io/soilhub-r/reference/soil_countries.md),
  [`soil_country()`](https://giulange.github.io/soilhub-r/reference/soil_country.md),
  [`soil_code_lists()`](https://giulange.github.io/soilhub-r/reference/soil_code_lists.md),
  [`soil_code_list()`](https://giulange.github.io/soilhub-r/reference/soil_code_list.md),
  [`soil_ttr_flag_legend()`](https://giulange.github.io/soilhub-r/reference/soil_ttr_flag_legend.md).
  Every result is a typed data frame; nested objects are list columns of
  data frames; fields unknown to the client are kept as list columns
  with a `soilhub_contract_warning`.

- Query strings no longer pad repeated character values to a common
  width.

- Sessions (WP2):
  [`soil_connect()`](https://giulange.github.io/soilhub-r/reference/soil_connect.md)
  signs in with the Keycloak device login (PKCE, human users only,
  tokens in memory only),
  [`soil_login()`](https://giulange.github.io/soilhub-r/reference/soil_login.md),
  [`soil_logout()`](https://giulange.github.io/soilhub-r/reference/soil_logout.md),
  the default session
  [`soil_session()`](https://giulange.github.io/soilhub-r/reference/soil_session.md)
  and
  [`soil_whoami()`](https://giulange.github.io/soilhub-r/reference/soil_whoami.md)
  (user, rights read from the token, advertised limits, session
  lifetime). The access token is renewed automatically before it expires
  (margin `soilhub.refresh_margin`, default 60 s) and once after an HTTP
  401, storing the rotated refresh token; a session Keycloak no longer
  renews fails with `soilhub_auth_error(reason = "session_expired")`
  once the current access token has expired (a warning announces it).
  Rights are checked locally only when the token declares them for the
  API audience. The print method of a session never shows a token. A 403
  names the right the request needs.

- HTTP layer, errors and paging (WP1): one internal request function
  with client request ids (`X-Request-ID`), retries on transport
  failures and HTTP 429/502/503/504 honouring `Retry-After` (capped at
  10 s), connect timeout 10 s and total timeout 300 s; the condition
  classes of `?soilhub-errors` (including `soilhub_load_limit_error`
  with the equivalent
  [`soil_export()`](https://giulange.github.io/soilhub-r/reference/soil_export.md)
  call); an offset page collector with partial results on failure; the
  configuration precedence and verbosity levels of `?soilhub-config`.

- Package skeleton of the 0.2.0 redesign: DESCRIPTION, tests with a
  fake-API helper, CI matrix and pkgdown configuration. No user-facing
  functions yet. The 0.1.x client documented in
  `docs/legacy/TUTORIAL-0.1.md` is superseded.
