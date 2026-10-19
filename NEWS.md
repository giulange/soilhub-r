# soilhub (development version)

* Contract tests and fixture recording (WP10): `tests/contract/` checks the
  client against the API's OpenAPI document (committed snapshot
  `tests/contract/openapi.json`, API 0.6.0, or the live one): every path and
  method the client calls, every query parameter, JSON body field and form
  field it sends (name, type, enum value, required fields), the enums it
  offers (`selection_values`, choices of the exported functions such as
  `layout`), the response fields of its typing tables where the OpenAPI
  types them, and the API version range. The client requests are not listed
  by hand: `soil_request()` hands every request to the development option
  `soilhub.exchange_hook`, and the suite records them from the unit tests.
  `Rscript tests/contract/run.R [live]` runs it (not part of `R CMD check`);
  `.github/workflows/contract.yml` runs it weekly with a diff of the live
  `openapi.json` against the snapshot (`tools/update_contract_snapshots.R
  --check`), without secrets. `tools/record_fixtures.R` (run by the owner
  with a device login) records scrubbed responses of a curated set of read
  calls and `tests/contract/capabilities.json`; the suite replays them
  through the client and skips until they exist. `tools/check_version.R`
  checks `MIN_API_VERSION` / `SUPPORTED_API_MAJOR` against an OpenAPI
  document. New constant `TESTED_API_VERSION` (0.6.0, the `info.version` of
  the snapshot, kept in step by `tools/update_contract_snapshots.R` and
  checked by the contract suite): the "API is newer than this client was
  tested with" message of `soil_connect()` now compares with it instead of
  `MIN_API_VERSION` (still 0.5.0, the oldest server accepted), so API 0.6.x
  gives no message.
* Long observations, features and geometry (WP5): `soil_observations(layout
  = "long")` reads one row per observation, typed per column family
  (`value` double, `value_raw` the source value verbatim as a list column,
  `release_id` and `value_count` integer, `lineage`, source descriptors and
  `method_facets` lists, marking columns, `revised_markings` with
  `hidden_values` as a data frame); `soil_metadata(x)$total_count` is the
  exact count of the selection. A multi-value WoSIS cell, for which the API
  extracts no number, gets the mean of its values in `value`, as the wide
  layout does. `soil_features()` reads the features (points and
  (multi)polygons) with `feature_key`, `components` (data frames),
  `profile_markings` and `retired_in_release`, and the metadata
  `feature_count`, `feature_count_by_dataset` and `mixed_geometry`.
  `with_geometry = "sf"` returns an `sf` `soil_table` (EPSG:4326) for the
  wide and long layouts and the features; `"text"` gives WKT (wide) or
  GeoJSON (long, features) without any package. `sf` stays in Suggests:
  without it `"sf"` raises a `soilhub_dependency_error` before any request.
  `soil_flags()` and `soil_markings()` read long tables too.
* Summaries and thematic reads (WP6): `soil_summary()` and
  `soil_availability()` take the selection of `soil_observations()`
  (validated the same way, sent as the same body without the layout fields)
  and check the same optional capabilities; `soil_summary()` returns a
  `soil_summary` with the counts by dataset (filled with the total when one
  dataset is selected), the variable semantics, the revised rules and a
  short print method, and works with `soil_metadata()`,
  `soil_revised_rules()` and `soil_citations()`. `soil_availability()`
  returns data frames by dataset (distinct totals), country, dataset and
  country, and variable (with the scoped `variants`). `soil_consistency()`
  sends its own request (no view, profile type or components) and returns
  the distinct totals with the calculation used. Thematic reads:
  `soil_values()` (typed `value` column, lineage on request),
  `soil_values_summary()`, `soil_health_scores()` (details on request; the
  arguments `run_ids` and `statuses` are the API fields `product_run_ids`
  and `score_statuses`), `soil_health_summary()`, `soil_resolve_targets()`
  (requests of 10,000 targets, reads `targets` of the response; `strict =
  TRUE` stops on missing or ambiguous targets) and `soil_ttr_flags()`
  (`GET /sotwis/ttr-flags`, paged, source columns verbatim). Geometry of
  values and scores as GeoJSON text with `with_geometry = "text"`; `"sf"`
  follows with the geometry module.

* Wide observations (WP4): `soil_observations()` reads the canonical wide
  layout (one row per horizon) page by page, with the selection of every
  canonical read (`datasets`, `variables`, `bbox`, `country`, `geometry`,
  `layer`, `view`, `profile_type`, `components`, `min_cumulative_percent`)
  validated before any request; `view = "raw"` is sent explicitly. The result
  is a `soil_table` (a data frame keeping its metadata through `[`), typed by
  column family: fixed, first-layer, component, source attribute and marking
  columns, `value_flags`, retirement, revised markings, WKT geometry text
  (`with_geometry = "text"`) and the variable groups `<key>`, `_units`,
  `_method`, `_n`. Multi-value WoSIS cells: `<key>` holds the mean of the
  listed values and `<key>_values` every original value
  (`multi_value_rule = "mean"`). Pages with different column sets are
  aligned. A refused selection raises `soilhub_load_limit_error` naming the
  `soil_export()` call of the same selection; a failure after some pages
  keeps them as a typed partial `soil_table` in `e$partial`. Result helpers:
  `soil_metadata()`, `soil_warnings()`, `soil_columns()`, `soil_flags()`,
  `soil_markings()`, `soil_revised_rules()`, `soil_first_layer()`, print and
  summary methods. `too_large = "export"` follows in a later work package.
* Writes and jobs (WP8), gated by the rights of the session (checked
  locally when the token declares them, else decided by the API; a 403 is a
  `soilhub_permission_error` naming the right): `soil_register_variable()`
  (validate then register, capability `variable_registration`),
  `soil_product()`, `soil_product_version()`, `soil_run_open()`,
  `soil_run_complete()`, `soil_run_fail()`, `soil_publish_values()` and
  `soil_publish_health()` (local checks of every record, server validation,
  synchronous up to 10,000 records, else an NDJSON file uploaded with its
  SHA-256 checksum as a job, never retried; receipts reconciled with the
  records sent, `soilhub_reconciliation_warning`), `soil_job()`,
  `soil_job_wait()`, `soil_job_cancel()` and `soil_refresh_countries()`.
  A 409 is a `soilhub_conflict_error` that says what to do (the API has no
  GET for products, versions or runs); a job that fails or is cancelled is a
  `soilhub_job_error` with the rejected rows in `e$errors`.
* Source ingest (WP9): `soil_publish_source()` builds a provider-neutral
  NDJSON bundle (features from an `sf` object or a spatial file -- a WGS84
  GeoJSON file is read without `sf` -- then profiles, components, horizons and
  observations), checks before any request the manifest, `source_record_id`
  (present, unique per record type), parent references, observation
  declarations, the CRS (transformed to EPSG:4326) and the geometry types,
  uploads it with its manifest and SHA-256 checksum (never retried),
  validates, verifies the counts staged by the API against the records sent
  (a difference stops before promotion), promotes and reconciles the
  published counts; `auto_promote = TRUE` lets the server's ingest worker
  validate and promote while the client waits; `keep_file = TRUE` keeps the
  bundle. Unmapped property codes are a `soilhub_unmapped_properties_warning`.
  `soil_source_validate()` and `soil_source_promote()` run the two server
  steps separately.
* A 403 on a session whose token does not declare its rights no longer
  reports the rights as `FALSE`.

* Discovery and version check (WP3): after the login `soil_connect()` reads
  `/capabilities` and checks the API version (0.5.0 or later, major 0) and
  the required capabilities; an incompatible server stops with
  `soilhub_capability_error` (the signed-out session in `e$session`), a newer
  minor version prints a message. Optional capabilities are checked by the
  functions that need them (`FALSE` is an error, not advertised a warning).
  New: `soil_capabilities()`, `soil_api_info()`, `soil_datasets()` and
  `soil_dataset()` (catalog with the provenance of the release, source assets
  and notes), `soil_citations()` and `soil_licences()` (provider texts
  verbatim, per source dataset from the notes when no dataset-level text
  exists), `soil_formats()`, `soil_variables()`, `soil_variable_mappings()`,
  `soil_countries()`, `soil_country()`, `soil_code_lists()`,
  `soil_code_list()`, `soil_ttr_flag_legend()`. Every result is a typed data
  frame; nested objects are list columns of data frames; fields unknown to
  the client are kept as list columns with a `soilhub_contract_warning`.
* Query strings no longer pad repeated character values to a common width.

* Sessions (WP2): `soil_connect()` signs in with the Keycloak device login
  (PKCE, human users only, tokens in memory only), `soil_login()`,
  `soil_logout()`, the default session `soil_session()` and `soil_whoami()`
  (user, rights read from the token, advertised limits, session lifetime).
  The access token is renewed automatically before it expires (margin
  `soilhub.refresh_margin`, default 60 s) and once after an HTTP 401, storing
  the rotated refresh token; a session Keycloak no longer renews fails with
  `soilhub_auth_error(reason = "session_expired")` once the current access
  token has expired (a warning announces it). Rights are checked locally only
  when the token declares them for the API audience. The print method of a
  session never shows a token. A 403 names the right the request needs.

* HTTP layer, errors and paging (WP1): one internal request function with
  client request ids (`X-Request-ID`), retries on transport failures and HTTP
  429/502/503/504 honouring `Retry-After` (capped at 10 s), connect timeout
  10 s and total timeout 300 s; the condition classes of `?soilhub-errors`
  (including `soilhub_load_limit_error` with the equivalent `soil_export()`
  call); an offset page collector with partial results on failure; the
  configuration precedence and verbosity levels of `?soilhub-config`.

* Package skeleton of the 0.2.0 redesign: DESCRIPTION, tests with a fake-API
  helper, CI matrix and pkgdown configuration. No user-facing functions yet.
  The 0.1.x client documented in `docs/legacy/TUTORIAL-0.1.md` is superseded.
