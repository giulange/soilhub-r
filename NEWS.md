# soilhub (development version)

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
  summary methods. The long layout, `with_geometry = "sf"` and
  `too_large = "export"` follow in the next work packages.
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
