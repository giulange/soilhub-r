# soilhub 0.2.0 — design of the redesigned R client

Status: **draft for the owner's review** (2026-10-18). Not committed. Tracking issue:
giulange/soilhub-r#1. Binding inputs: [redesign-decisions.md](redesign-decisions.md) (decisions 1–12,
4-bis), [requirements-inventory.md](requirements-inventory.md) (RQ-01…RQ-67, gaps of section 4). The
API described here is the one on `develop` (API 0.5.0, `python/soil_api/*`, `docs/api-operations.md`);
nothing in this document asks the API to change (section 12 lists facts only).

Conventions: `soil` is the session object; "the selection" is the common set of filters of the
canonical data endpoints; "right" is a Keycloak client role of the audience `soil-api`
(`soil:summary`, `soil:read`, `soil:publish`, `soil:admin`) today, a PDP decision tomorrow.

---

## 1. Goals, non-goals, users and rights

### 1.1 Goals

1. One package, `library(soilhub)`, for **every human user** of the Global Soil Data Hub API:
   students, researchers, the owner as publisher. Rights, not packages, decide what a call may do.
2. Faithful presentation of the agnostic ISRIC mirror: original terms, values and units; the
   `view=revised` rules are applied by the API and reported by the client, never re-implemented or
   "fixed" in R.
3. Every capability of API 0.5.0 reachable with explicit, documented arguments (decision 7).
4. Readable by pedologists: function names are soil words (`soil_observations`, `soil_features`,
   `soil_summary`), arguments carry the API's terms, help pages define each original term (PRID,
   HONU, SUID, `first_layer_status`, …) at first use.
5. Robust sessions: device login once, automatic renewal for hours (#37), no token on disk.
6. Sized data: refused synchronous requests explain the way out (narrow or export) and the export
   path is a first-class feature with waiting, download and reading.

### 1.2 Non-goals

- No machine users (decision 4-bis): no client-credentials, password grant or secret; no token
  persistence or "offline" scope; unattended jobs are Python.
- No direct database access, no scientific computation (fuzzy models, unit conversion,
  harmonisation), no client-side revision of data.
- No legacy path (`canonical=false`): every read is canonical (decision 7).
- No Parquet transport (`arrow` removed, decision 6): bulk publications travel as NDJSON.
- No CRAN submission in 0.2.0 (section 9).

### 1.3 Users and the rights model

| User | Typical rights | What they do |
| --- | --- | --- |
| Student / reader | `soil:summary`, `soil:read` | discovery, reads, exports |
| Publisher (owner, collaborators) | + `soil:publish` | runs, publications, source ingest, job control |
| Administrator (owner) | + `soil:admin` | variables, products, versions, country refresh |

**How the library learns the current user's rights.** The API has no "who am I" endpoint
(section 12.2). The client decodes the payload of its own access token (JWT, base64url, no
signature check: it only reads what the API will read) and takes
`resource_access[[audience]]$roles`, `preferred_username`, `sub`, `exp`; `audience` comes from
`GET /capabilities` `authentication.audience` (today `soil-api`). `soil_whoami(soil)` returns this
with the advertised limits (`capabilities.limits`). The mapping right → function is a package
constant (section 4.6) used for messages and for the pre-check below.

**Behaviour when a right is missing.**

- A **write or admin function** pre-checks the required right before sending anything and raises
  `soilhub_permission_error` ("`soil_register_variable()` needs the right `soil:admin`; your
  session has `soil:summary`, `soil:read`"). The pre-check is *advisory*: it runs only when the
  token carries a `resource_access` block for the audience; when it does not (a future token shape
  under the PDP), the request is sent and the API decides.
- A **403** from the API is always mapped to the same `soilhub_permission_error`, with the API
  `detail` and the right the client believes is needed.
- A **401** after a failed renewal is `soilhub_auth_error` (section 3), never confused with a
  permission problem.
- `soil_connect()` works for a user without `soil:summary` but warns that discovery calls will be
  refused; nothing is cached as "allowed".

**PDP-driven limits without code changes.** The client never hard-codes a limit: page size comes
from `limits.max_page_size`; the synchronous and export thresholds are read from
`limits.max_sync_observations` / `max_export_observations` only to *explain*; a refusal is driven by
the API's `422 load_limit_exceeded` detail (`max_observations`, `observation_count`, `channel`,
`exports_url`), which already carries per-principal values the day the PDP sets them. `soil_whoami()`
labels the limits "advertised by the server for this deployment"; when the API starts returning
per-user limits in `/capabilities` or in an identity endpoint, only `soil_whoami()`'s reader changes.

---

## 2. Package architecture

### 2.1 Repository layout (`giulange/soilhub-r`)

```text
soilhub-r/
  DESCRIPTION  NAMESPACE  LICENSE  LICENSE.md  NEWS.md  README.md  _pkgdown.yml  .Rbuildignore
  .github/workflows/  check.yml  pkgdown.yml  contract.yml
  R/
    soilhub-package.R   package doc, options, .onLoad (user agent)
    config.R            URLs, env vars, options, precedence
    session.R           soil_connect, soil_login, soil_logout, soil_session (default session)
    auth-device.R       device flow, refresh, token store (httr2)
    rights.R            JWT payload decode, soil_whoami, role pre-check table
    http.R              request builder, retries, 401 renewal, error mapping, X-Request-ID
    errors.R            condition constructors, print methods, soil_export_from_error
    paging.R            page collector, progress, partial results
    capabilities.R      cached /capabilities, version and capability gates
    selection.R         selection arguments -> request body (validation, enums)
    catalog.R           soil_datasets, soil_dataset, soil_citations, soil_licences, soil_formats
    variables.R         soil_variables, soil_variable_mappings
    countries.R         soil_countries, soil_country
    code-lists.R        soil_code_lists, soil_code_list, soil_ttr_flags, soil_ttr_flag_legend
    observations.R      soil_observations (wide and long)
    typing.R            column typing rules, multi-value cells, list columns
    features.R          soil_features
    summary.R           soil_summary, soil_availability, soil_consistency
    values.R            soil_values, soil_values_summary
    health-read.R       soil_health_scores, soil_health_summary
    exports.R           soil_export, _status, _wait, _download, _read, _cancel
    jobs.R              soil_job, soil_job_wait, soil_job_cancel
    publish-variables.R soil_register_variable
    publish-products.R  soil_product, soil_product_version, soil_run_open/_complete/_fail
    publish-values.R    soil_publish_values, soil_resolve_targets
    publish-health.R    soil_publish_health
    publish-source.R    soil_publish_source, soil_source_validate, soil_source_promote
    ndjson.R            records -> NDJSON file + SHA-256
    results.R           soil_table class, soil_metadata, soil_warnings, soil_columns, soil_flags,
                        soil_markings, soil_revised_rules, print/summary methods
    geometry.R          sf / WKT / GeoJSON helpers (sf optional)
    utils.R
  tests/testthat/       unit tests against a webfakes API (fixtures/*.json recorded and scrubbed)
  tests/contract/       openapi.json + capabilities.json snapshots, contract tests
  tests/live/           opt-in smoke and acceptance scripts (never run by R CMD check)
  tools/                record_fixtures.R, update_contract_snapshots.R, check_version.R
  vignettes/            soilhub.Rmd, raw-vs-revised.Rmd, first-layer.Rmd, exports.Rmd,
                        writing-data.Rmd, migration-0.1.Rmd
  man/                  roxygen2 output
```

The API repository keeps no client code; `docs/r-client/` there holds only this design and the
decisions (an operations note may point to the package repo).

### 2.2 DESCRIPTION

```text
Package: soilhub
Title: R Client for the Global Soil Data Hub API
Version: 0.2.0
Authors@R: person("Giuliano", "Langella", email = "giuliano.langella@gmail.com", role = c("aut", "cre"))
Description: Discover, read and export harmonised soil profile data (WoSIS, WISE, SOTER, SOTWIS)
    from the Global Soil Data Hub API, and publish derived values with the appropriate rights.
License: MIT + file LICENSE
URL: https://github.com/giulange/soilhub-r, https://giulange.github.io/soilhub-r
BugReports: https://github.com/giulange/soilhub-r/issues
Depends: R (>= 4.1)
Imports: httr2 (>= 1.0.0), jsonlite (>= 1.8), curl, openssl, utils, stats
Suggests: sf (>= 1.0), testthat (>= 3.0), webfakes, knitr, rmarkdown
Config/testthat/edition: 3
Encoding: UTF-8
Roxygen: list(markdown = TRUE)
RoxygenNote: 7.x
```

Rationale: `httr2` (device flow, retries, multipart), `jsonlite` (parsing with
`simplifyVector = FALSE`, so nested structures survive), `openssl` (SHA-256 of upload files; already
a dependency of httr2), `curl` (`form_file` for multipart). `sf` is **Suggests** (decision 6): every
read without geometry works without it; `with_geometry = "sf"` errors with an install hint when it
is absent. No `arrow`, no `cli`, no `tibble`: outputs are base `data.frame` / `sf`.

### 2.3 Modules and responsibilities

| Module | Owns | Never does |
| --- | --- | --- |
| `http.R` | one function `soil_request(soil, method, path, body, query, timeout, retry)` returning the parsed body; headers, retries, 401 renewal, error mapping, request ids, verbose log | typing of data, paging |
| `paging.R` | `soil_collect(soil, path, body, items, max_rows, page_size, progress)`: offset loop on `has_more`, metadata accumulation, partial result on failure | knowledge of column names |
| `selection.R` | validation of the selection arguments and their translation to the request body (names exactly as the API: `datasets`, `geometry`, `bbox`, `country`, `variables`, `layer`, `view`, `profile_type`, `components`, `min_cumulative_percent`, `layout`, `geometry_format`, `canonical = TRUE`) | network |
| `typing.R` | pure functions page rows → typed data frame, driven by `metadata.variables` and fixed column tables | network |
| `results.R` | `soil_table` class, attributes, accessors, print/summary | network |
| `exports.R`, `jobs.R` | job submission, polling, download, zip handling, reading | typing beyond what metadata.json gives |
| `rights.R`, `capabilities.R` | identity, gates | data |

Every module exposing network calls takes `soil` as first argument; nothing is global except the
optional default session (section 3.5).

### 2.4 HTTP layer (httr2)

- **URL**: `soil$api_url` + path. **Headers**: `Accept: application/json`,
  `User-Agent: soilhub/<version> R/<R.version> httr2/<v>`, `X-Request-ID: soilhub-<yyyymmddHHMMSS>-<8 hex>`
  (client-generated, echoed by the API; kept in metadata and errors). Bearer token from the session.
- **Timeouts**: connect 10 s; total per request `soil$timeout` (default **300 s**: long pages over
  whole datasets take 40–90 s, summaries up to 20 s); per-call override `timeout =`; downloads of
  export zips have no total timeout (progress by bytes).
- **Retries** (`httr2::req_retry`): max 3 tries; transient = transport error, 429, 502, 503, 504;
  backoff honours `Retry-After` capped at 10 s, else 1 s × attempt. Never on 4xx validation. Multipart
  uploads (`POST /publications/{run}/jobs`, `/soil-health/jobs`, `/source-ingests`) are **not**
  retried (an idempotency key protects a deliberate re-submission by the user).
- **401**: once per request, after a proactive expiry check; see section 3.3.
- **JSON**: request bodies `jsonlite::toJSON(auto_unbox = TRUE, null = "null", digits = NA)`;
  responses `fromJSON(simplifyVector = FALSE)` then typed explicitly (no automatic simplification:
  it is what produced the list-column surprises of 0.1.x).
- **Pagination**: `page_size = min(user, capabilities$limits$max_page_size)` (default 1000); loop
  `offset += returned_count` until `has_more` is `FALSE` (always present on canonical endpoints) or
  `max_rows` reached; guard against an unchanged page (same offset + same `request_id`); long layout
  shows a progress bar with `total_count`, wide/features count pages.
- **Logging / verbosity**: `soil_connect(verbose =)` or `options(soilhub.verbose = 0|1|2)`:
  0 silent; 1 (default when interactive) user messages (pages read, session renewed, export
  progress); 2 one line per request (method, path, status, ms, request id) — never headers, bodies
  or tokens. Messages carry class `soilhub_message` (suppressible).

### 2.5 Error classes

Conditions inherit from `soilhub_error` → `error` → `condition`. Fields are safe (no token, no
body of uploads).

| Class | When | Extra fields |
| --- | --- | --- |
| `soilhub_argument_error` | bad argument caught client-side (bbox, enum, NA, `"ALL"`) | `argument` |
| `soilhub_dependency_error` | `sf` needed and absent | `package` |
| `soilhub_auth_error` | device login failed/denied/expired; renewal failed; session not renewable | `reason` (`login_denied`, `login_timeout`, `session_expired`, `no_refresh_token`), `partial` (data read before the failure, section 3.4) |
| `soilhub_permission_error` | local pre-check or HTTP 403 | `required_right`, `rights`, `status`, `endpoint`, `request_id` |
| `soilhub_api_error` | any non-2xx not mapped below, invalid JSON, retries exhausted | `status`, `endpoint`, `detail` (string or list), `request_id`, `code` |
| `soilhub_validation_error` (api) | 422 with a string detail or `{message, errors}` (publications) | `errors` (data frame) |
| `soilhub_load_limit_error` (api) | 422 `detail.code == "load_limit_exceeded"` | `channel`, `max_observations`, `observation_count`, `observation_count_exact`, `exports_url`, `request` (body sent), `selection` (R arguments) |
| `soilhub_not_found_error` (api) | 404 | — |
| `soilhub_conflict_error` (api) | 409 (idempotency replay with different content, duplicate product, illegal job transition) | — |
| `soilhub_unavailable_error` (api) | 503 after retries, transport failure | `attempts` |
| `soilhub_capability_error` | server lacks a capability or the API version is outside the supported range | `capability`, `api_version`, `minimum` |
| `soilhub_job_error` | job `failed`/`cancelled`, polling timeout, export `status == "unknown"` | `job` (last status), `job_id` |

Message of a `soilhub_load_limit_error` (the API text, then the way out):

```text
The selection holds more than 1,000,000 observations, above the limit of synchronous requests
(1,000,000): narrow the selection (bbox, country, datasets, variables, layer, profile_type) or
request an export (POST /exports).
To export the same selection: soil_export(soil, datasets = "wosis_points", country = "BRA", format = "gpkg")
or rerun with too_large = "export".
```

### 2.6 Configuration

Precedence: explicit argument > `options()` > environment variable > built-in default.

| Setting | Argument | Option | Env var | Default |
| --- | --- | --- | --- | --- |
| API base | `api_url` | `soilhub.api_url` | `SOILHUB_API_URL` | `https://soilhub.weatherprogapp.it/api/v1` |
| Keycloak realm | `keycloak_url` | `soilhub.keycloak_url` | `SOILHUB_KEYCLOAK_URL` | `https://kc.weatherprogapp.it/realms/ams` |
| OIDC client | `client_id` | `soilhub.client_id` | `SOILHUB_CLIENT_ID` | `ams-r` |
| Timeout (s) | `timeout` | `soilhub.timeout` | `SOILHUB_TIMEOUT` | 300 |
| Verbosity | `verbose` | `soilhub.verbose` | `SOILHUB_VERBOSE` | `interactive()` |
| Export dir | `dir` | `soilhub.export_dir` | `SOILHUB_EXPORT_DIR` | `file.path(tempdir(), "soilhub-exports")` |
| Page size | `page_size` | `soilhub.page_size` | — | server `max_page_size` |

Token and device endpoints are derived from the realm URL
(`/protocol/openid-connect/{token,auth/device}`); the realm's `.well-known/openid-configuration` is
read when reachable and the fixed paths are the fallback. The 0.1.x names (`SOIL_API_URL`,
`KEYCLOAK_TOKEN_URL`, `KEYCLOAK_DEVICE_URL`) are read as a fallback with a one-time message.

---

## 3. Authentication and session

### 3.1 Session object

`soil_connect()` returns a `soil_session` (S3 list) with `api_url`, `keycloak_url`, `client_id`,
`timeout`, `verbose`, `created_at`, `capabilities` (cached), `identity` (from the token) and
`state`, an environment holding `access_token`, `refresh_token`, `expires_at`,
`refresh_expires_at`, `last_renewed_at`. `print()` shows URLs, user name, rights, API version and
"token valid for 1h 42m"; never a token. Saving the object (`.RData`, `saveRDS`) saves tokens:
the vignette says not to, and `soil_logout()` empties the state.

### 3.2 Login (device flow only, decision 4)

```r
soil <- soil_connect()                        # prints the verification URL and code, waits
soil <- soil_connect(login = FALSE); soil_login(soil)   # two steps
```

`httr2::oauth_flow_device(client, device_url, scope = "openid soil", pkce = TRUE,
open_browser = open_browser)` with `open_browser = interactive()` (on RStudio Server `browseURL`
opens the user's browser; headless prints the URL). Denied, expired or interrupted login →
`soilhub_auth_error(reason = "login_denied" | "login_timeout")`. After login the client reads
`/capabilities` (version gate, section 9.1) and decodes the token (`soil_whoami()`).

### 3.3 Renewal (the #37 mechanism)

1. **Proactive**: before every request, if `expires_at - now < 60 s`, refresh with
   `httr2::oauth_flow_refresh(client, refresh_token)`; store the rotated refresh token.
2. **Reactive**: on a 401, invalidate the access token, refresh once, repeat the request once.
3. **Refresh failure** (Keycloak `invalid_grant`: SSO session idle/max reached, token revoked):
   `soilhub_auth_error(reason = "session_expired")` with the message
   "Your Keycloak session has expired; run `soil_login(soil)` to sign in again (the browser step)".
4. **No refresh token** (Keycloak configured without one): `reason = "no_refresh_token"` at the
   first expiry, with the lifetime observed.

Facts: the access token lifetime of `ams-r` was reported raised from 5 min to 2 h (2026-10-06,
unverified); refresh/SSO lifetimes are not known to the client (section 12.1 Q2). The client is
single-threaded: it cannot keep a session alive during idle time; a session lasts as long as
Keycloak's SSO idle/max settings allow, and the vignette states the observed values once measured.

### 3.4 Expiry mid-download

The page loop catches `soilhub_auth_error` from a page request: if the reason is renewable it has
already been handled by `http.R`; if not, the loop stops and raises the error **with the pages
already read attached** (`error$partial`, a typed `soil_table` with `soil_metadata()$complete = FALSE`
and `$next_offset`), so a two-hour read is not lost: `soil_login(soil)` then
`soil_observations(..., offset = soil_metadata(partial)$next_offset)` continues. Exports are
unaffected by expiry: the job runs server-side; `soil_export_wait()` re-authenticates on each poll.

### 3.5 Multiple sessions and the default session

Every `soil_session` is independent (its own tokens and cache). `soil_connect(set_default = TRUE)`
registers the session as the default (`options(soilhub.session)`); every function's first argument
is `soil = soil_session()` so `soil_datasets()` works without passing it, and two sessions (two
users, production and a test API) are used by passing them explicitly. `soil_session(x)` sets,
`soil_session()` gets, `soil_logout(soil)` clears tokens and unregisters.

---

## 4. Public API

Naming rules: prefix `soil_`; verb-less names for reads that return data (`soil_observations`),
verbs for actions (`soil_publish_values`, `soil_export`, `soil_run_open`); arguments use the API's
own names and values (`view = "revised"`, `layer = "first"`, `profile_type = "!synthetic"`,
`components = "cumulative"`), `NULL` means "no filter" (the API default), never `"ALL"`.
All functions take `soil = soil_session()` first and are documented with `@param` for every
argument, the original term, the right required and the capability required.

### 4.1 The selection (shared by reads, summaries and exports)

| Argument | Type / values | API field | Note |
| --- | --- | --- | --- |
| `datasets` | character, catalog codes (`wosis_points`, `wise_profiles`, `soter_profiles`, `soter_polygons`, `sotwis_polygons`, `sotwis_components`, `sotwis_estimates`, …) | `datasets` | `NULL` = every catalog dataset (then usually above the sync limit) |
| `variables` | character: source codes (`ORGC`, `CLAY`) or canonical keys (`organic_carbon`) | `variables` | validated against `soil_variables()` only in messages, never blocking |
| `bbox` | numeric(4) `c(xmin, ymin, xmax, ymax)` WGS84 | `bbox` | client validation mirrors the API's |
| `country` | character: ISO2, ISO3 or name, case-insensitive (API semantics) | `country` | no client-side expansion (0.1.x did; unnecessary) |
| `geometry` | `"any"`, `"point"`, `"polygon"` | `geometry` | |
| `layer` | `"all"`, `"first"` | `layer` | |
| `view` | `"raw"`, `"revised"` | `view` | `"raw"` is sent explicitly, so `metadata.view` is always present |
| `profile_type` | character: `"synthetic"`, `"virtual"`, `"none"`, or all prefixed `"!"` | `profile_type` | needs `capabilities.profile_type_filter` |
| `components` | `NULL`, `"representative"`, `"all"`, `"cumulative"` | `components` | |
| `min_cumulative_percent` | numeric 0–100 | `min_cumulative_percent` | required with `"cumulative"` |

Internal: `soil_selection(...)` returns the validated body (`canonical = TRUE` always), the enum
values are taken from `/capabilities` (`views$values`, `profile_types`, `exports$formats`) when
present, else from package constants, so new server values are not rejected by the client.

### 4.2 Session and identity

| Function | Signature | Returns | Purpose |
| --- | --- | --- | --- |
| `soil_connect` | `(api_url = NULL, keycloak_url = NULL, client_id = NULL, login = TRUE, open_browser = interactive(), timeout = NULL, verbose = NULL, set_default = TRUE)` | `soil_session` | create a session, device login, capability/version check |
| `soil_login` | `(soil = soil_session(), force = FALSE)` | `soil` (invisible) | (re)authenticate; `force` opens a new browser login even if a session is valid |
| `soil_logout` | `(soil = soil_session())` | `NULL` | drop tokens in memory, unregister default |
| `soil_session` | `(soil = NULL)` | current default or error `soilhub_auth_error(reason = "no_session")` | get/set the default session |
| `soil_whoami` | `(soil = soil_session())` | `soil_identity` list: `username`, `subject`, `roles`, `can` (named logical: `summary`, `read`, `publish`, `admin`), `limits` (from capabilities), `token_expires_at`, `session_renewable` | what this user may do |
| `soil_api_info` | `(soil = soil_session())` | list: `health`, `ready`, `api_version`, `schema_version`, `authentication`, `client_version`, `compatible` | liveness, readiness, versions |
| `soil_capabilities` | `(soil = soil_session(), refresh = FALSE)` | the `/capabilities` list (cached per session) | the deployment contract |

### 4.3 Discovery and catalog (right: `soil:summary`)

| Function | Signature | Returns | Purpose |
| --- | --- | --- | --- |
| `soil_datasets` | `(soil)` | data.frame, one row per dataset: `name`, `title`, `provider_code`, `description`, `support_type`, `geometry_class`, `release_code`, `release_status`, `feature_count`, `profile_count`, `horizon_count`, `observation_count`, `country_codes` (list), `licence_text`, `licence_url`, `citation_text`, provenance fields (`release_acquired_at`, `release_released_at`, `release_source_url`, `release_source_version`, `release_source_doi`, `release_reconstructed`, `release_note`, `retired_row_count`), `source_assets` (list of data.frames), `notes` (list of data.frames) | the catalog with provenance |
| `soil_dataset` | `(soil, name)` | `soil_dataset` list (same fields; `print` shows title, release, counts, licence, citation, notes titles) | one dataset in full |
| `soil_citations` | `(x, soil = soil_session())` where `x` is a dataset name, a `soil_datasets()` row set, a `soil_table`, a `soil_summary` or a `soil_export` | data.frame `dataset`, `citation_text`, `citation_source_url`, `citation_retrieved_on`, `citation_note`, plus the per-source `isric_citation` notes when the dataset text is null (SOTER, SOTWIS) | what to cite |
| `soil_licences` | same as above | data.frame `dataset`, `licence_text`, `licence_url`, `licence_source_url`, `licence_retrieved_on`, `licence_note`, per-source `isric_licence` notes | under which terms |
| `soil_formats` | `(soil)` | character | export formats |
| `soil_variables` | `(soil, code = NULL, domain = NULL, measurement_kind = NULL, target_level = NULL, dataset = NULL, provider = NULL, available_only = FALSE, include_unmapped = FALSE)` | data.frame one row per variable (`variable_code`, `name`, `description`, `domain_code`, `value_type`, `measurement_kind_code`, `allowed_target_levels` (list), `property_family`, `property_family_name`, `documentation_url`, counts, `datasets` (list), `providers` (list), `source_mappings` (list of data.frames), `coverage` (list)); attribute `soil_metadata` | the variable catalog |
| `soil_variable_mappings` | `(soil, ...)` same filters, or `(x)` on a `soil_variables()` result | data.frame one row per (variable, dataset, mapping): `variable_code`, `canonical_property_key`, `provider_code`, `dataset_code`, `source_code`, `source_official_code`, `source_label`, `source_unit`, `procedure_code`, `procedure_description`, `source_value_kind`, `semantic_status`, `unit_status`, `unit_evidence`, `source_scope`, `source_notes` | what a source code means in each dataset |
| `soil_countries` | `(soil)` | data.frame (`iso_a2`, `iso_a3`, `name`, counts, `as_of`); attribute `country_assignment = "intersects"` | daily inventory |
| `soil_country` | `(soil, code)` | list `country` (one-row df), `datasets` (df), `variables` (df), `as_of` | one country by dataset and variable |
| `soil_code_lists` | `(soil)` | data.frame | the source code lists kept (`SOTWIS_codes`) |
| `soil_code_list` | `(soil, name, attribute = NULL, code = NULL, source_dataset = NULL)` | data.frame | rows of one code list, verbatim |
| `soil_ttr_flag_legend` | `(soil)` | data.frame (`column_group`, `symbol`, `meaning`, `source_reference`, `documented`, `applies_to`) | SOTWIS taxotransfer flag legend |

### 4.4 Reads (right: `soil:read`; summaries `soil:summary`)

| Function | Signature | Returns | Purpose |
| --- | --- | --- | --- |
| `soil_observations` | `(soil, datasets = NULL, variables = NULL, bbox = NULL, country = NULL, geometry = "any", layer = "all", view = "raw", profile_type = NULL, components = NULL, min_cumulative_percent = NULL, layout = c("wide", "long"), with_geometry = c("none", "sf", "text"), max_rows = Inf, offset = 0, page_size = NULL, too_large = c("stop", "export"), progress = interactive(), timeout = NULL)` | `soil_table` (`data.frame` or `sf`), section 5 | horizon-level measurements: wide = one row per horizon, long = one row per observation |
| `soil_features` | `(soil, datasets = NULL, variables = NULL, bbox = NULL, country = NULL, geometry = "any", view = "raw", profile_type = NULL, components = NULL, min_cumulative_percent = NULL, with_geometry = c("sf", "text"), max_rows = Inf, page_size = NULL, too_large = c("stop", "export"), progress = interactive())` | `sf` (points and (multi)polygons, EPSG:4326) or data.frame with `geometry_text` (GeoJSON) | the features (where) with `feature_key`, `components`, `profile_markings`, `retired_in_release` |
| `soil_summary` | `(soil, <selection>)` | `soil_summary` list: `feature_count`, `feature_count_by_dataset`, `horizon_count`(+by), `observation_count`(+by), `observed_feature_count`(+by), `avg_horizons_per_feature`, `variables`, `variables_by_dataset`, `variable_semantics` (df), `formats`, `warnings`, `view`, `revised` (rules), `components`; `print` is a short report | what a selection holds before transferring it (also the sizing step before an export) |
| `soil_availability` | `(soil, <selection>)` | list of data.frames `datasets` (dataset, geometry, counts), `countries` (country_code, country_name, counts), `variables` (dataset, country_code, property_code, canonical_property_key, canonical_name, property_family, source_unit, procedure_*, mapping_status, source_notes, `variants` list, counts) | what exists by dataset, country and variable |
| `soil_consistency` | `(soil, providers = NULL, datasets = NULL, geometry = NULL, country = NULL, bbox = NULL, variables = NULL)` | list `totals` (list), `countries` (df), `datasets` (df), `variables` (df), `metadata` (`calculation`, `as_of`, `summary_scope`) | authoritative distinct totals (never sum countries) |
| `soil_ttr_flags` | `(soil, source_dataset = NULL, prid = NULL, claf = NULL, layer = NULL, feature_id = NULL, horizon_id = NULL, view = "raw", max_rows = Inf)` | data.frame, source columns verbatim (`CLAF`, `PRID`, `Layer`, `TTRsub`, …) | which taxotransfer rules produced the SOTWIS estimates |
| `soil_values` | `(soil, providers = NULL, datasets = NULL, variables = NULL, domains = NULL, measurement_kinds = NULL, target_levels = NULL, country = NULL, bbox = NULL, valid_at = NULL, depth_top_cm = NULL, depth_bottom_cm = NULL, product_versions = NULL, run_ids = NULL, statuses = NULL, with_geometry = c("none", "sf", "text"), include_lineage = FALSE, max_rows = Inf, progress = interactive())` | `soil_table`: `value_id`, `variable_code`, …, typed `value` (numeric/text/logical/json list) plus `numeric_value`, `text_value`, `boolean_value`, `json_value` as returned, lineage list columns | externally published (derived) values |
| `soil_values_summary` | same filters | list with `total_value_count`, `feature_count`, `variables`, `by_dataset`, `by_target_level`, `by_status` | counts before transfer |
| `soil_health_scores` | `(soil, providers = NULL, datasets = NULL, release_ids = NULL, release_codes = NULL, model_versions = NULL, run_ids = NULL, categories = NULL, score_classes = NULL, statuses = NULL, source_supports = NULL, country = NULL, bbox = NULL, depth_top_cm = NULL, depth_bottom_cm = NULL, with_geometry = c("none", "sf", "text"), include_details = FALSE, max_rows = Inf, progress = interactive())` | `soil_table` | soil-health scores |
| `soil_health_summary` | same filters | list | counts by dataset, release, support, category, class, status |
| `soil_resolve_targets` | `(soil, targets, strict = TRUE)` with `targets` a data.frame (`provider_code`, `dataset_code`, `release_code`, `target_level`, `source_record_id`, `source_table`) | data.frame of `TargetResolutionResult` (chunks of 10,000) | source identities → canonical UUIDs; `strict` errors on `missing`/`ambiguous` |

### 4.5 Exports (right: `soil:read`)

| Function | Signature | Returns | Purpose |
| --- | --- | --- | --- |
| `soil_export` | `(soil, <selection>, format = c("gpkg", "geojson", "csv", "tsv", "shp"), content = c("all", "features"), layout = c("wide", "long"), wait = TRUE, timeout = 3600, poll = 5, download = wait, dir = NULL, unzip = TRUE, progress = interactive())` | `soil_export` object: `job_id`, `status`, `observation_count`, `records`, `request`, `zip` (path), `files`, `dir`, `metadata` (parsed `metadata.json`), `expires_at` | submit; optionally wait, download and unzip |
| `soil_export_status` | `(soil, x)` (`x` job id or `soil_export`) | updated `soil_export` | poll once |
| `soil_export_wait` | `(soil, x, timeout = 3600, poll = 5, progress = interactive())` | `soil_export` (terminal) | wait with progress (`progress` fraction of observations written) |
| `soil_export_download` | `(soil, x, dir = NULL, unzip = TRUE, overwrite = FALSE)` | `soil_export` with `zip`, `files` | download the zip (streamed to disk) |
| `soil_export_read` | `(x, what = c("observations", "features", "metadata", "all"))` (`x` a `soil_export`, a zip path or an unzipped directory) | `soil_table` / `sf` / list, typed from `metadata.json` | read the files back into R |
| `soil_export_cancel` | `(soil, x)` | job | cancel (needs `soil:publish`: fact 12.2) |
| `soil_export_from_error` | `(soil, error, format = "gpkg", ...)` | `soil_export` | turn a `soilhub_load_limit_error` into the same selection as an export |

### 4.6 Writes (rights as noted; every function pre-checks, section 1.3)

| Function | Signature | Right | Purpose |
| --- | --- | --- | --- |
| `soil_register_variable` | `(soil, variable_code, name, domain_code, value_type = c("numeric", "text", "boolean", "json"), measurement_kind_code, allowed_target_levels, description = NULL, idempotency_key, validate_only = FALSE)` | `soil:admin`, capability `variable_registration` | validate (`/variables/validate`) then register |
| `soil_product` | `(soil, product_code, name, target_level, description = NULL)` | `soil:admin` | register a product (409 → `soilhub_conflict_error`, no GET to recover: fact 12.2) |
| `soil_product_version` | `(soil, product_code, version_code, algorithm_checksum, variables, configuration = list())` (`variables`: data.frame `variable_code`, `target_levels` list) | `soil:admin` | immutable version, returns `product_version_id` |
| `soil_run_open` | `(soil, product_version_id, idempotency_key, input_release_ids = integer(), parameters = list())` | `soil:publish` | open a run |
| `soil_run_complete` / `soil_run_fail` | `(soil, run_id, diagnostics = list())` | `soil:publish` | close a run |
| `soil_publish_values` | `(soil, run_id, values, idempotency_key, validate = TRUE, transport = c("auto", "sync", "ndjson"), wait = TRUE, timeout = 3600, poll = 5)` (`values` data.frame or list of records with `variable_code`, `target_level`, `target_id`, `value`, `value_status`, `release_id`, `quality_code`, `valid_time_*`, `depth_*`, `lineage` list) | `soil:publish` | local required-field check, server validate, publish; > 10,000 rows → NDJSON job |
| `soil_publish_health` | `(soil, run_id, scores, idempotency_key, transport = c("auto", "sync", "ndjson"), wait = TRUE, timeout = 3600, poll = 5)` | `soil:publish`, capability `bulk_soil_health` for jobs | scores and fuzzy details; local checks of required fields, `score_status`, score/class consistency |
| `soil_publish_source` | `(soil, manifest, features, profiles = NULL, components = NULL, horizons = NULL, observations = NULL, idempotency_key, auto_promote = FALSE, wait = TRUE, keep_file = FALSE, timeout = 3600, poll = 5)` (`features` an `sf` with `source_record_id`) | `soil:publish`, capability `source_ingest` | build the NDJSON bundle, upload with checksum, validate, promote, wait |
| `soil_source_validate` / `soil_source_promote` | `(soil, job_id)` | `soil:publish` | the two steps separately |
| `soil_job` | `(soil, job_id, detail = c("unified", "publication", "soil_health"))` | `soil:publish` | job status (unified or dataset-specific view) |
| `soil_job_wait` | `(soil, job_id, timeout = 3600, poll = 5, progress = interactive())` | `soil:publish` | wait to a terminal state; `failed`/`cancelled` → `soilhub_job_error` |
| `soil_job_cancel` | `(soil, job_id)` | `soil:publish` | cancel |
| `soil_refresh_countries` | `(soil, idempotency_key = NULL)` | `soil:admin` | queue the country refresh |

Right → function table (package constant `soilhub:::.rights`), also printed by `soil_whoami()`:
`summary`: 4.3, `soil_summary`, `soil_availability`, `soil_consistency`, `soil_values_summary`,
`soil_health_summary`, `soil_ttr_flag_legend`; `read`: the other reads, exports, `soil_ttr_flags`;
`publish`: runs, publications, source ingest, jobs; `admin`: variables, products, versions,
country refresh.

### 4.7 Result helpers (no network)

| Function | On | Returns |
| --- | --- | --- |
| `soil_metadata(x)` | `soil_table`, `soil_summary`, `soil_export` | the metadata list (section 5.4) |
| `soil_warnings(x)` | same | character: unique API warnings over all pages |
| `soil_columns(x)` | wide `soil_table`, `soil_export` | data.frame per variable column: `column`, `property_key`, `numeric`, `units` (list), `source_codes` (list), `horizon_count`, `multi_value_cells`, `methods` (list), `source_notes` (list), `method_facets` (list) |
| `soil_flags(x)` | `soil_table` | long data.frame `horizon_id`, `column`, `flag` from `value_flags` |
| `soil_markings(x)` | `soil_table` | long data.frame of raw cell/layer/profile markings and, with `view = "revised"`, the revised markings and `hidden_values` (`horizon_id`, `scope`, `column`, `marking`, `value`) |
| `soil_revised_rules(x)` | `soil_table`, `soil_summary`, `soil_export` | data.frame `id`, `title`, `issue`, `effect`, `n` (+ `pairs` attribute for R6) |
| `soil_first_layer(x)` | `soil_table` read with `layer = "first"` | the `metadata.first_layer` vocabulary (`view`, `statuses`, `profile_markings`) |

---

## 5. Data types and output shapes

### 5.1 The `soil_table` class

`class(x) = c("soil_table", "data.frame")` or `c("soil_table", "sf", "data.frame")` (sf keeps
its own class in front of `data.frame`, as sf does). Attributes: `soil_metadata` (section 5.4),
`soil_layout` (`"wide"`, `"long"`, `"features"`, `"values"`, `"health"`). Subsetting with `[` keeps
the class and the attributes (a `[.soil_table` method restores them, as sf does); `as.data.frame()`
drops them. Row order is the API's (stable paging order).

`print.soil_table` writes a two-line header then the first `getOption("soilhub.print_rows", 10)`
rows as a data frame with list columns shown as `<list>`:

```text
# soilhub wide table: 689 horizons, 137 features, 23 variables | wosis_points | view raw, layer all
# 2 API warnings (soil_warnings), typing (soil_columns), cite with soil_citations()
```

`summary.soil_table` prints `soil_columns(x)` (wide), the counts per dataset and, when present,
the revised rules with counts.

### 5.2 Wide layout (`layout = "wide"`, default)

One row per horizon row (key `dataset, feature_id, component_id, horizon_id`). Columns in API
order; type rules:

| Column(s) | R type | Source |
| --- | --- | --- |
| `dataset`, `provider_code`, `feature_id`, `profile_id`, `component_id`, `horizon_id`, `horizon_name`, `source_support`, `release_code` | character | fixed |
| `component_rank` | integer | fixed |
| `upper_depth_cm`, `lower_depth_cm` | double | fixed |
| `first_layer_status` | character; `profile_markings` list of character | with `layer = "first"` |
| `proportion_percent`, `cumulative_proportion_percent`, `terrain_proportion_percent` double; `is_representative`, `profile_inside_polygon` logical; `suid`, `tcid`, `scid` integer; `soil_code`, `representative_profile_id`, `newsuid`, `isoc`, `soil_map_unit`, `tcdc`, `linked_profile_feature_id` character | component columns | when SOTWIS/SOTER polygons selected |
| `source_profile_type`, `source_record_note`, `profile_attr_<key>`, `horizon_attr_<key>` | character (verbatim strings; `horizon_attr_organic_surface` stays `"true"`/`"false"` text as served) | when the dataset supplies them |
| `texture_sum` double; `consistency_flags`, `also_in_datasets` list of character; `possible_profile`, `superseded_by` character; `cell_markings` list of named lists (column → markings) | raw markings | when supplied |
| `value_flags` | list of named lists (column → character flags), `NULL` entries where none | both views |
| `retired_in_release` character; `retired_cells` list of named character | retirement | always on canonical rows |
| `revised_markings` | list of named lists (`hidden_values` as a data.frame, `cells` as named list) | with `view = "revised"` |
| `geometry_kind` character; `geometry` sfc (sf) or `geometry_text` WKT character | with `with_geometry` | one geometry per `feature_id`, copied to each row; rows without one get an empty geometry and one warning |
| `<key>` | double when `metadata.variables[column].numeric` is `TRUE` on every page that had cells, else character | variable |
| `<key>_units`, `<key>_method` | character | variable |
| `<key>_n` | integer | variable |
| `<key>_values` | list of character vectors; present only for columns with `multi_value_cells > 0` | client-side companion (below) |

**Multi-value cells** (decision 8). A WoSIS cell holding a JSON list of 2–10 values arrives as its
JSON text in `<key>`. The client parses it: `<key>` receives the **mean of the listed values**
(the value WoSIS publishes, per decision 8; `NA` if any element is non-numeric), `<key>_values`
keeps every original element verbatim as a character vector (`NULL` for single-value cells), and
`soil_metadata(x)$multi_value_rule = "mean"` records the rule. The column stays numeric. `soil_columns()`
reports `multi_value_cells`, and `cell_markings` carries the API's `value_count`, `methods_differ`,
`value_spread`, `source_method_kind`, `method_facets` for the same cell. (Open question Q1 confirms
"mean" as the published value.)

Pages with different column sets (no `variables` given) are aligned with `NA`; the column set is
the union in API order (fixed, markings, geometry, then variable groups sorted by name).
Columns reported `numeric: FALSE` are character with the original text.

### 5.3 Long layout (`layout = "long"`)

One row per observation; columns of `ObservationRecord` in API order. Types: `value` double
(the number the API extracted), `value_raw` **list** column holding the original JSON value verbatim
(number, string or list of strings); `unit`, codes and ids character; `release_id` integer;
`lineage`, `profile_attributes`, `horizon_attributes`, `component_attributes`, `method_facets`
list; `profile_markings`, `source_method_kind`, `consistency_flags`, `also_in_datasets`,
`value_flags` list of character; `value_count` integer; `methods_differ` logical;
`value_spread`, `texture_sum`, `method_tension_kpa` double; `revised_markings` list;
`geometry` sfc (`with_geometry = "sf"`) or `geometry_text` (GeoJSON string) or absent; component
columns as in 5.2. Fields the API serialises only for some selections are present only then.

**Wide/long equivalence** (acceptance 10.4): for the same selection, the set of
`(dataset, feature_id, component_id, horizon_id)` keys of the wide rows equals the distinct keys of
the long rows, and for each key and property column the wide `<key>` equals the first long `value`
by ingestion order (multi-value cells: the mean of `value_raw`), `<key>_n` equals the count of long
rows of that property. The client does not pivot; the test verifies the API's own equivalence
through the client's typing.

### 5.4 Metadata attribute

`soil_metadata(x)` is a list:

| Field | Content |
| --- | --- |
| `request` | the body sent (selection, layout, view, …), `endpoint` |
| `api_version`, `schema_version`, `client_version`, `retrieved_at` (UTC) |
| `request_ids` | one per page; `pages`; `complete` (FALSE on a partial result); `next_offset` |
| `total_count` | long: exact; wide/features: `NA` (API returns null) |
| `warnings` | unique API warnings over the pages (mixed units, multi-value cells, renamed columns, collapsed duplicates, component ties, SUM(PROP) ≠ 100) |
| `variables` | the merged `metadata.variables` of wide pages (`soil_columns()`); long: `NULL` |
| `view`, `revised` | `view` as echoed; `revised$rules` with counts over the selection, `pending`, `unchanged`, `scope`, R6 `pairs` |
| `first_layer` | with `layer = "first"`: `view`, `statuses`, `profile_markings` |
| `components`, `min_cumulative_percent` | effective values when a component dataset is selected |
| `crs` | `"EPSG:4326"` |
| `datasets` | catalog rows of the selected datasets (citation, licence, release, provenance), fetched once per session; `soil_citations(x)` reads it |
| `multi_value_rule` | `"mean"` (wide) |

### 5.5 Other results

- **Features**: `sf` with `dataset`, `provider_code`, `feature_id`, `feature_key`, `geometry_kind`,
  `source_support`, `components` (list of data.frames when SOTWIS/SOTER polygons are selected;
  `source_attributes` kept as a named list inside), `profile_markings` (list of character),
  `retired_in_release`; attribute metadata adds `feature_count`, `feature_count_by_dataset`,
  `mixed_geometry`.
- **Summary** (`soil_summary`): list; `print` shows counts per dataset, the variables, warnings and
  revised rules; `soil_citations()` works on it.
- **Catalog data frames**: nested objects are list columns of data.frames (`notes`,
  `source_assets`, `source_mappings`, `variants`), typed once by a helper, never left as raw lists.
- **Values / health**: data.frame with the API columns; `include_details` adds list columns
  (`inputs`, `memberships`, `activated_rules`, `diagnostics`, lineage inputs).

---

## 6. Exports and large requests

### 6.1 When to export

- The API refuses a synchronous read above `limits.max_sync_observations` observations
  (1,000,000 today; per-user later) with `422 load_limit_exceeded`; an export accepts up to
  `limits.max_export_observations` (10,000,000) and writes every record of the selection.
- The vignette rule of thumb: run `soil_summary()` first; below ~200,000 observations read
  synchronously; above, export (a whole-WoSIS wide CSV export took 9 min server-side and 88 MB
  zipped). Exports also give GeoPackage/Shapefile files for GIS.

### 6.2 Flow

```text
soil_export(soil, selection, format)        POST /exports  -> job_id, observation_count
   |  wait = TRUE                            GET /exports/{id}  every `poll` s (status, progress)
   |  completed                              GET /exports/{id}/download -> <dir>/<job_id>.zip
   |  unzip = TRUE                           <dir>/<job_id>/{metadata.json, files...}
soil_export_read(x)                          typed soil_table / sf + metadata
```

- `soil_export()` validates the format/content/layout combination client-side with the values of
  `capabilities$exports` (shapefile only with `content = "features"`), then submits. `wait = FALSE`
  returns at once with the `job_id` (printed, with the `expires_at`, 7 days by default), to be
  resumed with `soil_export_wait(soil, job_id)` in a later session (the id is the only handle:
  section 12.2).
- Polling: `poll` seconds (default 5, minimum 2), `timeout` seconds; the progress bar uses
  `progress` (fraction of observations written) when the API gives it. `failed` →
  `soilhub_job_error` with `error_message`; `unknown` (the API's 200 for an unknown id) →
  `soilhub_job_error(reason = "unknown_job")`.
- Download is streamed to disk (`httr2::req_perform(path =)`), with a byte progress bar; `dir`
  defaults to `soilhub.export_dir`; files are never overwritten unless `overwrite = TRUE`.
- `soil_export_read()` reads `metadata.json` first and uses it for typing: wide CSV/TSV columns
  listed in `wide_columns` are typed as in 5.2 (numeric when `numeric`, `_n` integer, multi-value
  text parsed to mean + `_values`); JSON-text cells (`value_flags`, `cell_markings`, `profile_markings`,
  `components`) are parsed back to list columns; `features.csv` `geometry_wkt` becomes `sf` when
  `sf` is installed, else stays text. GeoPackage and Shapefile require `sf` (`st_read` of the
  layers `features`, `observations`); GeoJSON uses `sf` when installed, else `jsonlite` into a
  data.frame with `geometry_text`. The result carries the same `soil_table` class and metadata as a
  synchronous read (`soil_citations()`, `soil_revised_rules()`, `soil_columns()` work).

### 6.3 A refused synchronous request

`soil_observations()` / `soil_features()` with `too_large = "stop"` (default) raise
`soilhub_load_limit_error` whose message prints the equivalent `soil_export()` call; `too_large =
"export"` catches the error, submits the export with `format = "csv"` (wide) or `"geojson"`
(features), waits, downloads, reads and returns the same shape as the synchronous read would have
(with `soil_metadata(x)$via_export = job_id`). `soil_export_from_error(soil, err, format = "gpkg")`
is the manual form for an error caught earlier.

### 6.4 Progress and file handling

Progress bars use `utils::txtProgressBar` (no new dependency) and are off when
`progress = FALSE` or not interactive. Zips keep the server name (`exp_<stamp>_<hex>.zip`);
unzipped directories are named after the job id; `soil_export_read()` accepts either. Temporary
NDJSON upload files of the write functions live in `tempfile()` and are removed unless
`keep_file = TRUE`.

---

## 7. Testing strategy

Three levels (decision 11), all without production credentials in CI.

### 7.1 Unit tests against a fake API (`tests/testthat/`)

- **webfakes** (already proven in 0.1.x) runs a local HTTP server per test file with routes built
  from **recorded fixtures**: JSON responses captured from the real API by `tools/record_fixtures.R`
  (run by the owner with a device login, scrubbed of `request_id`, user ids and any token) for
  each endpoint and shape: wide page with every optional column family (WoSIS markings, WISE
  attributes, SOTER profile type, SOTWIS components), multi-value cells, long page, features with
  components, summary, availability, consistency, revised metadata, first-layer metadata, load-limit
  422, 403, 401 then success, 409, 422 publication errors, export lifecycle (queued → running →
  completed, download zip fixture), jobs, source ingest.
- **Clock-controlled auth tests**: device login mocked at the OAuth endpoints (webfakes token
  routes), proactive refresh at `expires_at - 60 s`, rotation of the refresh token, reactive refresh
  on 401, refresh failure → `soilhub_auth_error`, partial result on mid-download expiry.
- **Typing tests** are pure (no server): page JSON → data frame, including column alignment across
  pages, multi-value parsing, `numeric: false` columns, list columns, wide/long key equivalence on
  the fixtures.
- **Export reading**: a fixture zip per format (csv, tsv, geojson, gpkg, shp) built once from a real
  small export (Vancouver bbox), read with and without `sf` (`_R_CHECK_FORCE_SUGGESTS_=false` job).
- **Rights**: pre-check with and without a `resource_access` block; 403 mapping.

### 7.2 Contract tests (`tests/contract/`)

Purpose: detect API drift before users do. Two snapshots committed in the package repo and
refreshed by `tools/update_contract_snapshots.R`:

1. `openapi.json` — fetched from `https://soilhub.weatherprogapp.it/openapi.json`, which is served
   **without a token** (verified 2026-09-17, `docs/api-operations.md`); FastAPI exposes it by default
   and `main.py` does not restrict it. So CI needs no secret: a scheduled workflow
   (`contract.yml`, weekly and on demand) fetches the live file and diffs it against the snapshot;
   a difference fails the job with the diff, and the owner decides whether the client follows.
2. `capabilities.json` — needs `soil:summary`, so it is recorded by the owner together with the
   fixtures (scrubbed) and compared in CI only against the snapshot (keys the client reads).

The contract tests themselves check, from the OpenAPI document: every path the client calls
exists with the method used; every request field the client sends is a property of that path's
request schema; enum values the client offers (`view`, `layer`, `layout`, `geometry`,
`components`, `format`, `content`, `profile_type` syntax) equal the schema's; response fields the
client types (the `ObservationRecord`, `ExportJobResponse`, `UnifiedJobResponse`, `SummaryResponse`
models) exist. What OpenAPI cannot describe (`metadata` is `dict[str, Any]`, wide rows are open
dicts) is covered by the recorded fixtures and by `capabilities.json` (`limits`, `views`,
`profile_types`, `exports`, capability keys). The client's `MIN_API_VERSION` / `MAX_API_MAJOR`
constants are checked against `info.version` of the snapshot.

### 7.3 Opt-in live tests (`tests/live/`, never run by `R CMD check`)

Scripts, not testthat files, run by the owner (device login is interactive):
`smoke.R` (health, capabilities, datasets, one wide and one long read of 5 rows per dataset,
summary, 5 features, one small export csv end to end, read-only), `session-hours.R` (#37: a loop of
reads every 20 min for 4 h, then a 90-min idle gap, then a read; logs renewals and lifetimes
without tokens), `write-acceptance.R` (section 10.2, with a publisher account). Each writes a
sanitised log under `tests/live/logs/` (git-ignored) that the owner attaches to the issue.

### 7.4 CI matrix (`check.yml`, GitHub Actions, r-lib/actions)

| Job | OS | R | Suggests | Purpose |
| --- | --- | --- | --- | --- |
| check-release | ubuntu-latest | release | all | `R CMD check --as-cran`, 0 errors/warnings/notes |
| check-oldest | ubuntu-latest | 4.1 | all | minimum R |
| check-nosf | ubuntu-latest | release | without `sf` | reads and exports without geometry |
| check-mac | macos-latest | release | all | |
| check-win | windows-latest | release | all | |

`pkgdown.yml` builds the site on `main`; `contract.yml` as in 7.2. No job needs a secret.

---

## 8. Documentation

- **README**: install from the latest GitHub release (the existing installer, with `sf` optional),
  three-line first use (`soil_connect()`, `soil_datasets()`, `soil_observations(...)`), link to the
  site, licence note (client MIT; provider data under their own licences; `soil_citations()`).
- **Vignettes** (`eval = FALSE` chunks except pure-R ones; never log in or download at build):
  1. `soilhub` (getting started): install, login, `soil_whoami()`, discovery, a 100-horizon wide
     read of WoSIS in one country, `soil_columns()`, save with `saveRDS` (not the session), citations.
  2. `raw-vs-revised`: the principle (mirror as is; rules in the response), `view`, how to read
     `soil_revised_rules()`, `soil_markings()`, value flags, retired rows; the rule table R1–R19
     linked to the API docs.
  3. `first-layer`: what `layer = "first"` returns (statuses `surface`, `tie`, `not_surface`,
     `depth_missing`, revised `surface_within_5cm`, `first_mineral`), `profile_markings`, why a
     profile may return nothing, SOTWIS/SOTER components.
  4. `exports`: sizing with `soil_summary()`, the load limit, `soil_export()` flows, reading back,
     GIS formats.
  5. `writing-data`: rights, products/versions/runs, `soil_resolve_targets()`,
     `soil_publish_values()`, soil-health, source ingest, jobs; idempotency keys.
  6. `migration-0.1`: section 8.1 table and the behavioural changes.
- **Reference** (roxygen2, one `@family` per group): every argument documented with the original
  term and the API field; a `?soilhub-terms` topic defines feature / profile / component / horizon
  / observation, PRID, HONU, SUID, TCID/SCID, CLAF, `source_support`, `first_layer_status`.
- **pkgdown** (`_pkgdown.yml`): Reference groups Session, Discovery, Reads, Exports, Writing,
  Results, Errors; Articles as above; `NEWS.md` per release.
- The thesis guide becomes the getting-started vignette (generic); `docs/r-*.md` in the API repo are
  retired with a pointer.

### 8.1 Migration 0.1.x → 0.2.0

| 0.1.x | 0.2.0 | Change |
| --- | --- | --- |
| `soil_connect(api_url, token_url, client_id, client_secret, …)` | removed | machine login left the package (decision 4-bis) |
| `soil_connect_device(api_url, token_url, device_url)` + `soil_login()` | `soil_connect(api_url, keycloak_url)` (logs in) | one realm URL; `soil_login()` kept for re-login |
| `soil_check_api()` | `soil_api_info()` | adds versions and compatibility |
| `soil_capabilities()` | same | cached |
| `soil_datasets(dataset =)` | `soil_datasets()`, `soil_dataset(name)` | provenance, citations, notes |
| `soil_variables(code, domains, measurement_kinds, …, "ALL")` | `soil_variables(code, domain, …, NULL)`, `soil_variable_mappings()` | `NULL` instead of `"ALL"`; singular API names |
| `soil_countries(country)` | `soil_countries()`, `soil_country(code)` | |
| `soil_consistency()` | same, `NULL` filters | |
| `soil_get_observations(layout, geometry_format, include_geometry, canonical)` | `soil_observations(layout, with_geometry)` | always canonical; `view`, `profile_type`, `components`; typed markings |
| `soil_get_data()` | `soil_observations(with_geometry = "sf")` | |
| `soil_get_features()` | `soil_features()` | canonical ids (join with observations by `feature_id`) |
| `soil_get_values()` | `soil_values()` | |
| `soil_get_health()` | `soil_health_scores()` | |
| `soil_get_target_ids()` | `soil_resolve_targets()` | reads `targets` (0.1.3 read `results`: a bug) |
| `soil_get_all_pages()` | internal | |
| `soil_register_variable()` | same | capability-gated, `validate_only` |
| `soil_publish_derived(values, product, version, run)` | `soil_product()`, `soil_product_version()`, `soil_run_open()`, `soil_publish_values(run_id, values)` | explicit steps; run completion added |
| `soil_publish_health()` | `soil_publish_health(run_id, scores)` | |
| `soil_publish_entities()` | `soil_publish_source()` | |
| `soil_publication_status()`, `soil_cancel_job()` | `soil_job()`, `soil_job_wait()`, `soil_job_cancel()` | |
| `soil_check_dependencies()`, `soil_install_dependencies()` | removed | package installation handles dependencies (#38 closed) |
| `max_records` | `max_rows` | counts rows of the returned layout |
| `"ALL"` filter value | `NULL` | `"ALL"` raises `soilhub_argument_error` naming `NULL` |

---

## 9. Versioning and release

### 9.1 API version and capability check at startup

Package constants: `MIN_API_VERSION = "0.5.0"`, `SUPPORTED_API_MAJOR = 0`,
`REQUIRED_CAPABILITIES = c("query_canonical_observations", "wide_layout", "canonical_features",
"canonical_summary", "load_limits", "complete_exports", "first_layer_status")`. `soil_connect()`:

- `api_version` below the minimum or another major → `soilhub_capability_error` (connection still
  returned with `login = FALSE` semantics so `soil_api_info()` can be inspected);
- a newer minor → message "API 0.6.x is newer than this client was tested with (0.5.x); update
  soilhub when available";
- a required capability `FALSE` → error naming it; optional capabilities (`revised_view`,
  `profile_type_filter`, `raw_markings`, `source_ingest`, `variable_registration`,
  `bulk_soil_health`, `code_lists`, `sotwis_ttr_flags`, `dataset_notes`, `sotwis_estimates`) are
  checked by the functions that need them, with `soilhub_capability_error`.

### 9.2 Compatibility policy

- Client `MAJOR.MINOR.PATCH`: PATCH = bug fixes; MINOR = new functions/arguments, API minor
  bumps; MAJOR = removed/renamed exports. One client minor supports one API minor range
  (`MIN_API_VERSION` … same major), stated in `NEWS.md` and `soil_api_info()`.
- Response fields unknown to the client pass through untyped (list columns) with a one-time
  `soilhub_contract_warning`; missing expected fields produce `NA` columns and the same warning:
  drift degrades, never silently changes meaning.

### 9.3 Release process (RQ-51 unchanged)

1. All work packages of the milestone merged into `develop`, CI green, contract snapshot current.
2. Owner approves version, `NEWS.md`, and the live acceptance logs (section 10).
3. `R CMD build` on `main`; `gh release create vX.Y.Z soilhub_X.Y.Z.tar.gz` by the owner (the
   installer in README reads the asset); tag only after the approval.
4. pkgdown site published from `main`.

### 9.4 r-universe

Pros: `install.packages("soilhub", repos = "https://giulange.r-universe.dev")` with binaries for
Windows/macOS, automatic rebuild from GitHub, dependency resolution, `pak` support, a visible
check status. Cons: builds from the repo HEAD or tags (the release discipline must be by tag);
one more public surface to keep green; the owner's GitHub organisation registry must be maintained;
students on RStudio Server still install source packages. Recommendation: keep GitHub Releases as
the official channel for 0.2.0; register r-universe after 0.2.0 as a convenience channel built
from tags only (`@branch: "release"` or tag-based), not a prerequisite.

---

## 10. Acceptance criteria for 0.2.0

1. **Package quality**: `R CMD check --as-cran` 0/0/0 on the matrix of 7.4; unit coverage of every
   exported function; contract tests pass against the committed snapshot and against the live
   `openapi.json` of production on release day.
2. **#37 multi-hour session** (gate): `tests/live/session-hours.R` run by the owner on RStudio
   Server with a student-role account: reads every 20 min for ≥ 4 h without any browser step, one
   idle gap of 90 min, renewals visible in the log; a forced expiry (Keycloak session revoked)
   yields `soilhub_auth_error(reason = "session_expired")` and a clean `soil_login()` recovery.
   The measured idle/max limits are written in the vignette. Reader permissions unchanged.
3. **A reproducible read on each dataset**: for each of `wosis_points`, `wise_profiles`,
   `soter_profiles`, `soter_polygons`, `sotwis_polygons`, `sotwis_components`, `sotwis_estimates`:
   one bounded wide read (bbox or country, `max_rows = 200`) and the same long read, logged with
   request ids, column counts and the first key; `view = "revised"` on the same selections lists
   the applied rules; `layer = "first"` on WoSIS and SOTER shows the statuses.
4. **Wide/long equivalence** on those selections (5.3), checked by `tests/live/smoke.R`.
5. **Exports end to end**: a WoSIS bbox export in `csv`, `gpkg`, `geojson` and a `shp`
   features-only export: submitted, waited, downloaded, unzipped, read with `soil_export_read()`;
   the observation rows read back equal the synchronous wide read of the same selection
   (`metadata.json` records match); a refused synchronous read (`datasets = NULL`) converted with
   `too_large = "export"` or `soil_export_from_error()`.
6. **Write acceptance with a publisher account** (RQ-42, never run): with a human account holding
   `soil:publish` and `soil:admin`: `soil_register_variable()` (validate then register, idempotent
   replay), `soil_product()`, `soil_product_version()`, `soil_run_open()`,
   `soil_publish_values()` sync (≤ 10 rows) and NDJSON job (> 10,000 rows), `soil_run_complete()`,
   re-read with `soil_values()` and lineage, `soil_publish_health()` sync, a reader account refused
   (`soilhub_permission_error`), job cancel on a queued job; a source-ingest round trip of a tiny
   synthetic bundle on the development API (not production). Logged and attached to the issue.
7. **Rights model**: `soil_whoami()` correct for a reader and a publisher; a reader calling a
   write function gets the local permission error before any request; with the pre-check disabled
   (token without `resource_access`) the API's 403 maps to the same error.
8. **Documentation**: the six vignettes build; pkgdown site published; migration table complete;
   README installer works on RStudio Server (student test, installed package, not source).
9. **Owner approval** of the version and release (section 9.3).

---

## 11. Implementation plan (work packages = issues on board #7)

Order follows dependencies; each package includes its unit tests and roxygen docs. The Status column is updated at every step (✅ merged into `develop`, 🔵 in progress, ⏳ to do); issues on board #7.

| # | Title | Scope | Depends on | Acceptance | Status |
| --- | --- | --- | --- | --- | --- |
| WP0 | Bootstrap `soilhub-r` package skeleton | DESCRIPTION (2.2), NAMESPACE via roxygen, LICENSE, `.Rbuildignore`, `check.yml` matrix, `_pkgdown.yml` skeleton, `NEWS.md`, `tests/testthat` with webfakes helper, `tools/` stubs; move the public README installer | — | `R CMD check` 0/0/0 on an empty package with CI green | ✅ in `develop` |
| WP1 | Errors, HTTP layer, paging | `errors.R` (2.5), `http.R` (2.4), `paging.R`, config precedence (2.6), verbosity | WP0 | fake-API tests: retries, Retry-After, error mapping incl. 422 load limit and `{message, errors}`, request ids, page loop stop rules, partial result | ✅ in `develop` |
| WP2 | Session: device login, renewal, identity | `session.R`, `auth-device.R`, `rights.R`, `soil_whoami`, default session, print | WP1 | clock-controlled tests (3.3), 401 renewal, no-refresh-token path, redacted print, JWT decode on fixtures | ✅ in `develop` |
| WP3 | Capabilities, version gate, catalog, variables, countries, code lists | `capabilities.R` (9.1), `catalog.R`, `variables.R`, `countries.R`, `code-lists.R`, `soil_citations`, `soil_licences` | WP2 | typed data frames for every fixture; capability error on a stripped capabilities fixture; citations from dataset text and from notes | ✅ in `develop` |
| WP4 | Selection and wide observations | `selection.R` (4.1), `observations.R` wide, `typing.R`, `results.R` (`soil_table`, metadata, print, summary, `soil_columns`, `soil_flags`, `soil_markings`, `soil_revised_rules`, `soil_first_layer`) | WP3 | fixtures of each column family typed per 5.2; multi-value parsing; page alignment; revised metadata; first-layer metadata; `too_large = "stop"` message | ✅ in `develop` |
| WP5 | Long observations, features, geometry | long typing (5.3), `features.R`, `geometry.R` (sf optional, text fallback), `with_geometry` | WP4 | long fixtures typed; features sf and text; no-sf job passes; wide/long key equivalence test on fixtures | ✅ in `develop` |
| WP6 | Summaries and thematic reads | `summary.R` (summary, availability, consistency), `values.R`, `health-read.R`, `soil_resolve_targets`, `soil_ttr_flags` | WP4 | each fixture typed; `soil_summary` print; `strict` resolution error | ✅ in `develop` |
| WP7 | Exports | `exports.R` (4.5, 6), `soil_export_read` per format, `too_large = "export"`, `soil_export_from_error` | WP5, WP6 | export lifecycle fixture; zip fixtures per format read with and without sf; typed from metadata.json; equality with the wide fixture | ✅ in `develop` |
| WP8 | Jobs and publication writes | `jobs.R`, `publish-variables.R`, `publish-products.R`, `publish-values.R`, `publish-health.R`, `ndjson.R`, rights pre-check | WP3 | fixtures for validate/publish/409/422 errors, NDJSON checksum, job polling to terminal states, permission pre-check and 403 mapping | ✅ in `develop` |
| WP9 | Source ingest | `publish-source.R` (bundle from sf, manifest, upload, validate, promote, wait) | WP8 | fixture round trip; `source_record_id` and CRS checks; `keep_file` | ✅ in `develop` |
| WP10 | Fixture recording and contract tests | `tools/record_fixtures.R` (scrubbing), `tools/update_contract_snapshots.R`, `tests/contract/` (7.2), `contract.yml` | WP0 (runs alongside WP3–WP9, fixtures recorded by the owner once) | snapshots committed; contract suite green against the snapshot and the live `openapi.json` | ✅ in `develop` (risposte vere registrate il 2026-10-20) |
| WP11 | Documentation and site | six vignettes (8), `?soilhub-terms`, pkgdown groups, README, `migration-0.1` | WP7, WP8 | vignettes build without network; site published from a preview branch | ✅ in `develop` |
| WP12 | Live acceptance (owner) | `tests/live/smoke.R`, `session-hours.R`, `write-acceptance.R`; runs on RStudio Server and the owner's Mac; logs attached to the issue | WP7, WP8, WP9 | criteria 10.2–10.7 ticked with logs | 🔵 script in `develop` (tests/live); collaudo dal vivo da eseguire con il proprietario |
| WP13 | Release 0.2.0 | version, `NEWS.md`, tarball, GitHub release, site, close #37/#38/#42 references, retire `docs/r-*.md` in the API repo | WP10–WP12 | owner approval; installer test from a clean R | ⏳ da fare |

Suggested milestone grouping: M1 "core" (WP0–WP3), M2 "reads" (WP4–WP7), M3 "writes"
(WP8–WP9), M4 "assurance and release" (WP10–WP13).

---

## 12. Open questions and API facts

### 12.1 Open questions for the owner

| # | Question | Options | Recommendation |
| --- | --- | --- | --- |
| Q1 | Multi-value WoSIS cells: decision 8 says the numeric column holds "the value WoSIS publishes (the mean)". The API deliberately returns the list without aggregation. Confirm the rule the client applies to `<key>`. | (a) mean of the listed values, originals in `<key>_values`, rule recorded in metadata; (b) `NA` in `<key>` and originals in `<key>_values`; (c) first element | (a), as decided; the companion column and `multi_value_rule` keep the client honest about a derived number |
| Q2 | Session lifetimes for #37: which Keycloak values apply to `ams-r` (access token, SSO session idle, SSO session max, client session idle/max, refresh-token rotation)? | (a) read them from the Keycloak admin console and give them to the client docs; (b) measure them with `session-hours.R` only | (a) then confirm with (b); the acceptance targets (4 h active, 90 min idle) need the numbers to be fair |
| Q3 | Source of the OpenAPI for contract tests | (a) committed snapshot refreshed by the owner; (b) live fetch of the public `openapi.json` of production; (c) both | (c): snapshot for deterministic tests, scheduled live diff as drift alarm |
| Q4 | Default session registry (`soil_session()` default argument) | (a) implicit default set by `soil_connect()`; (b) always explicit `soil` | (a): fewer arguments for students, explicit override for multiple sessions |
| Q5 | Account for the write acceptance (10.6): writes need a human account with `soil:publish` and `soil:admin` | (a) the owner's personal Keycloak user gets the roles; (b) a dedicated human "publisher-test" user | (a) for production acceptance, (b) on the development API for repeatable tests |
| Q6 | Exposure of `soil_values()`, `soil_health_scores()` and the SOTWIS raw-only tables (`soil_ttr_flags`, code lists) in the first release | (a) all in 0.2.0; (b) defer values/health reads | (a): decision 7 asks for the whole surface and they cost little |
| Q7 | `too_large = "export"` default | (a) `"stop"` (explicit); (b) `"export"` (silent fallback) | (a): a pedologist should see the size and choose the format |
| Q8 | r-universe | see 9.4 | after 0.2.0, tag-based |

### 12.2 API facts relevant to the client (not change requests)

1. No identity/permissions endpoint: rights are read from the JWT claims (`resource_access.<audience>.roles`); the API authorises on the same claims.
2. `GET /capabilities` `limits` are the configured defaults; per-principal limits (PDP) will appear only in the `422 load_limit_exceeded` detail unless a later endpoint reports them.
3. Export job control: `GET /exports/{id}` and download need `soil:read`, but `POST /jobs/{id}/cancel` and `GET /jobs/{id}` need `soil:publish`; a reader cannot cancel or inspect the unified view of their own export.
4. No endpoint lists a user's jobs or exports; the job id returned at submission is the only handle, so the client prints it and `soil_export(wait = FALSE)` users must keep it.
5. `GET /exports/{id}` answers `200 {"status": "unknown"}` for an unknown id (not 404).
6. No `GET /products`, `/products/{code}/versions`, `/product-versions/{id}`: a 409 on creation cannot be resolved by reading the existing object; the client surfaces `soilhub_conflict_error` and takes the known `product_code` / `product_version_id` from the user.
7. `/query/consistency` takes no `view`, `profile_type`, `components` or `canonical`; its counts are those of the daily statistics, different by design from `soil_summary()`.
8. The long layout computes `total_count` on every page (36 s on whole WoSIS): paging a large long selection pays it per page; the wide layout has no total.
9. `metadata` and wide rows are untyped in OpenAPI (`dict[str, Any]`); contract tests need recorded fixtures for them.
10. `/openapi.json` and `/docs` are served without a token (checked 2026-09-17).
11. `POST /query/targets/resolve` returns `targets` (0.1.3 read `results`).
12. Country filters on the canonical path accept ISO2, ISO3 and names case-insensitively; the 0.1.x client-side expansion is unnecessary.
13. Bulk publications accept `ndjson`, `parquet`, `geoparquet`; the client sends NDJSON only (decision 6).
14. `POST /source-ingests` reads `property_mappings` nowhere from the manifest model (`SourceIngestManifest` has no such field; extra fields are ignored); mappings are resolved from `soil_vocab.property_mappings` by provider.
15. Keycloak lifetimes are not discoverable through the API; the token response gives `expires_in` and `refresh_expires_in`, which the client records and shows in `soil_whoami()`.
16. Exports expire after `EXPORT_RETENTION_DAYS` (7); `expires_at` is returned and shown.
17. Hidden rows under `view = "revised"` never change `/datasets` counts or the load-limit count (the limit counts the selection in the requested view).
