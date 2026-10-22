# R client (soilhub): inventory of existing requirements

Prepared 2026-10-18 from the API repository (`develop`, API 0.5.0), the
GitHub issues of `giulange/global-soil-data-hub` and the public repository
`giulange/soilhub-r`. Read-only recovery of what was required and promised;
no judgement of the code design, no API change proposed. Status column =
what the code on `develop` does today (full unit suite re-run on 2026-10-18:
all 16 test files pass).

## 1. Overview

| Item | Fact |
| --- | --- |
| Where the code lives | API repo (private `giulange/global-soil-data-hub`): `R/soilhub.R` (source loader) and `R/soilhub/*.R` (12 modules, 24 public `soil_*` functions); tests `tests/testthat/` (17 files, 43 `test_that` blocks, fake API via webfakes) and `tests/r/`; examples `examples/r/01..04`; docs `docs/r-client.md`, `r-first-steps.md`, `r-student-guide.md`, `r-package-distribution.md`; plan `docs/superpowers/plans/2026-08-13-r-source-client-library.md`; wide-layout spec `docs/superpowers/specs/2026-10-07-wide-observations-layout-design.md`; Docker test image `docker/r-client.Dockerfile`. `R/wosis_50_profiles_test.R` is an old WoSIS GraphQL downloader, unrelated to the client. |
| Public repo | `giulange/soilhub-r` (public): only `README.md` (latest-release installer) and `TUTORIAL.md` (older "first data table" using long `soil_get_observations`); 4 commits; **no R code**. Releases v0.1.1 (2026-09-15), v0.1.2 (2026-09-30), v0.1.3 (2026-10-05, "Latest"), each with one `soilhub_X.Y.Z.tar.gz` asset. |
| Build/distribution | `bash scripts/build_r_package.sh` (wrapper: version from `config/r-package/DESCRIPTION`, per-version lock and receipt, never overwrites) calls `scripts/build_r_package.R`: copies `R/soilhub/*.R`, generates NAMESPACE (`@exportPattern ^soil_`) and Rd via roxygen2, bundles `inst/doc/` (`r-client.md`, `soilhub-student.Rmd` from `r-first-steps.md`, `soilhub-reference.Rmd` from `r-student-guide.md`, all `eval=FALSE`), `R CMD build`. The operator uploads the archive to a GitHub Release of `soilhub-r` by hand (`gh release create`). Not on CRAN. |
| Users (as stated) | Students on RStudio Server (guide written for a thesis student: personal Keycloak account in group `soil-class`, roles `soil:summary` + `soil:read`, read-only); Giuliano as sole human writer; external scientific models / ETL (technical client with `soil:publish`, `soil:admin`) publishing derived values, soil-health scores and new geography. |
| Current version | `config/r-package/DESCRIPTION` = **0.1.3** (= published). `develop` holds unreleased work (session renewal `bdfcbfb`, coordinates fix `f0f14d7`, wide default `97366e9`, unit-layer removal `e7fa76d`, docs; the release-1 runbook counted 17 unpublished commits on 2026-10-09). A local 0.1.4 was withdrawn on 2026-10-06; **next version deliberately undecided** (operator approval needed for any version, archive or upload). License MIT + file LICENSE, author/maintainer Giuliano Langella. |
| Design boundary | Talks only to the API (no direct PostgreSQL), runs no scientific models, no bundled credentials, tokens in memory only (`docs/r-client.md:17-19`, issues #12-#21 "Contract"). |

## 2. Requirements

Status: yes / partial / no. API column: **unchanged**, **changed** (how) or n/a.
Line numbers refer to files under `R/soilhub/` unless a path is given.

### 2.1 Configuration and authentication

| ID | Requirement | Source | Status as implemented | Relation to current API |
| --- | --- | --- | --- | --- |
| RQ-01 | Explicit connection object `soil_connect(api_url, token_url, client_id, client_secret, username, password, timeout=60)`, env fallbacks (`SOIL_API_URL`, `KEYCLOAK_TOKEN_URL`, `SOIL_ETL_CLIENT_ID`, `SOIL_ETL_CLIENT_SECRET`, `SOIL_USERNAME`, `SOIL_PASSWORD`), URL normalised, useful missing-field errors. | Plan T2; #13 | yes (`config.R:13-46`; `test-config.R`) | unchanged |
| RQ-02 | Technical client-credentials grant is the normal external-compute/ETL flow; password grant only for dedicated integration-test users, never presented as the student flow. | #13; plan "Deployed Contract Review" | yes (`auth.R:8-39`) | unchanged |
| RQ-03 | Human login with the public Keycloak client `ams-r`: device authorisation flow, fixed scope `openid soil`, PKCE S256, no secret, works headless/Docker; `soil_connect_device()` + `soil_login()`. | `docs/r-client.md:38-62`; `cross-repo/soil-hub-keycloak-*.md` | yes (`config.R:48-70`, `auth.R:42-72`; `test-device-auth.R`). Live login verified by the operator 2026-09-15 (not automated). | unchanged (auth model) |
| RQ-04 | Public URL defaults (API `https://soilhub.weatherprogapp.it/api/v1`, Keycloak realm `ams` token URL); precedence: explicit argument > environment variable > default; device URL derived from token URL (`KEYCLOAK_DEVICE_URL` override). | `docs/r-client.md:6-8`; v0.1.2 | yes (`config.R:48-70`) | unchanged |
| RQ-05 | Token cached in memory with 30 s margin, reused; renewed with the refresh token; `soil_login(force=TRUE)` is the explicit new browser login; explicit errors when renewal fails. | Plan T2; `docs/r-client.md:55-58` | yes (`auth.R:1-72`) | unchanged |
| RQ-06 | On the first HTTP 401 invalidate only the cached access token and renew through the refresh token without opening a browser; a device session with no refresh token fails explicitly; repeated 401 bounded. | #37 (comments 2026-10-06) | yes (`http.R:32-60`; `test-http-renewal.R`). **Unreleased** (develop only). | unchanged |
| RQ-07 | A real R session must stay usable for several hours (target duration and idle interval not yet confirmed); distinguish access-token life from refresh/session life; user can tell an expired session from an API/data error. | #37 | partial: renewal code and clock-controlled tests exist; real multi-hour run never done; only the 6-minute check (2026-09-15). Operator reported `ams-r` lifetime raised 5 min -> 2 h (2026-10-06), not independently verified. | n/a (Keycloak config) |
| RQ-08 | Secrets never printed, stored or in errors; connection print is redacted; docs tell users not to save the connection or `.RData`. | #13; `docs/r-first-steps.md:108` | yes (`print.R`; `test-auth.R`). Evidence note: `print()` shows `grant: client_credentials` also for a device connection. | n/a |
| RQ-09 | Scopes expected per workflow: `soil:summary` (capabilities, countries, datasets, variables, consistency), `soil:read` (queries), `soil:publish` (runs, publication, ingest, jobs), `soil:admin` (products, versions, variables); a 403 on a write is expected for readers. | Plan "Deployed Contract Review"; `docs/r-student-guide.md:287-289` | partial: scopes documented; the client does not pre-check scopes (only `source_ingest` capability). | unchanged (`GET /jobs/{id}` needs `soil:publish`; `/exports` needs `soil:read`) |

### 2.2 HTTP, errors, pagination

| ID | Requirement | Source | Status | API relation |
| --- | --- | --- | --- | --- |
| RQ-10 | One request layer: bearer auth, JSON body, timeout, client-generated `X-Request-ID`, JSON-only responses. | Plan T3; #14 | yes (`http.R:32-78`) | unchanged |
| RQ-11 | Bounded retry (3 attempts) on transport errors and 429/502/503 honouring `Retry-After` (capped at 2 s); no retry of 4xx validation errors. | #14 | yes (`http.R:50-60`; `test-http.R`) | unchanged |
| RQ-12 | Typed error `soil_api_error` with safe `status`, `endpoint`, `detail`, `request_id`; `soil_api_capability_error` for missing server capability; no credentials in either. | #14; `docs/r-client.md:183-187` | yes (`http.R:1-19`, `entities.R:1-13`). Multipart upload (`http.R:80-95`) has no retry or 401 renewal. | changed: 422 `detail` can now be an object (`load_limit_exceeded`); the client flattens it to JSON text, no dedicated handling |
| RQ-13 | `soil_get_all_pages()`: keep server order, advance `offset`, stop on `has_more=FALSE` or short page, guard against an unchanged page, honour `max_records`, page size 1000. | Plan T3; #14 | yes (`http.R:97-117`; `test-pagination.R`) | unchanged (`has_more` always present; `total_count` is `null` for wide and canonical features) |
| RQ-14 | `ALL` is a friendly input translated to "filter omitted" / `geometry="any"`; bbox validated as WGS84 `c(min_lon,min_lat,max_lon,max_lat)`; scalar country normalised; `NA` rejected. | Plan "Scope And Rules"; `validate.R` | yes | unchanged |
| RQ-15 | Country filter accepts ISO-2, ISO-3 or name, expanded through the `/countries` inventory (tolerates incomplete catalog fields; no `NA` leaks). | `discovery.R:42-59`; v0.1.3 release note | yes (`test-discovery.R`) | unchanged (country = daily intersects assignment) |
| RQ-16 | Runtime capability gating: fail clearly (instead of changing shape or writing partially) when the server lacks a capability. | Plan "API Integration Gates", T8; #19 | partial: gated for `wide_layout` (`read.R:130-136`), `source_ingest` (`entities.R:1-13`), `observation_geometry` (auto). Not gated: `variable_registration` (plan asked for it), health, bulk jobs. Plan's OpenAPI-path fallback not built. | changed: `/capabilities` is now API 0.5.0 with about 32 capability keys; limits are `max_page_size`, `max_sync_observations`, `max_export_observations`, `max_publication_bytes` (plan cited `max_sync_features`) |

### 2.3 Discovery

| ID | Requirement | Source | Status | API relation |
| --- | --- | --- | --- | --- |
| RQ-17 | `soil_check_api()` (health, ready, capabilities, auth enabled) and `soil_capabilities()`. | Plan T4; #15 | yes (`discovery.R:17-29`) | changed: richer capabilities payload (see RQ-16) |
| RQ-18 | `soil_countries()` compact inventory and one-country detail (datasets, variables). | #15 | yes (`discovery.R:31-40`) | unchanged |
| RQ-19 | `soil_datasets()` list or one dataset. | #15; student guide | yes (`discovery.R:62-66`) | changed: `GET /datasets` now carries release provenance, licence and citation texts, `source_assets`, `notes`, `retired_row_count` (#60, #72); nested fields reach R as list columns, not documented |
| RQ-20 | `soil_variables()` with filters code, domain, measurement kind, target level, dataset, provider, `available_only`; one row per variable; metadata kept as attribute. | Plan T4; #15 | yes (`discovery.R:69-84`) | changed: new `include_unmapped`, `source_mappings` per dataset, method facets, `property_family`; docs still say "four original ISRIC datasets" (catalog now has more, e.g. `soter_profiles`, `sotwis_components`, `sotwis_estimates`) |
| RQ-21 | `soil_consistency()` as the authoritative distinct-count source (`/query/consistency`); never sum country totals into a global total; returns `totals`, `by_country`, `by_dataset`, `variables` with metadata. | #15; `docs/r-client.md:118-119` | yes (`discovery.R:87-101`) | unchanged (endpoint takes no `view`/`profile_type`/`layer`) |

### 2.4 Reads and geometry

| ID | Requirement | Source | Status | API relation |
| --- | --- | --- | --- | --- |
| RQ-22 | `soil_get_features()` returns `sf` (EPSG:4326) for points/polygons with datasets, geometry, bbox, country, variables, layer, `max_records`; real coordinates, rings and holes preserved. | #16, #35, #41 (closed) | yes (`read.R:37-68`; `test-read-geometry.R`) | changed: the client never sends `canonical`, so it reads the legacy path with source ids (`sotwis_polygons:653`); the API now offers `canonical=true` features whose UUID ids match canonical observations (#45) |
| RQ-23 | `soil_get_observations()` long table (one row per measurement) with canonical ids, depths, value, unit, dataset, lineage; `canonical=TRUE` default; `include_geometry="auto"` uses `observation_geometry`. | #16 | yes (`read.R:144-168`) | changed: `observation_geometry` always true now; long rows gained `value_raw`, `value_flags`, `first_layer_status`, `profile_markings`, `retired_in_release`, `revised_markings` (unhandled, pass through) |
| RQ-24 | `soil_get_data()` = student-facing read with geometry; long fallback joins `/query/features` by dataset + feature id with no Cartesian duplication and a warning for unmatched ids. | Plan T5; #16 | yes (`read.R:175-210`; `test-read-geometry.R`) | changed: fallback joins legacy feature ids to canonical observation ids; the ids differ (#45), so the join would mostly warn; no longer needed when `observation_geometry` is true |
| RQ-25 | `soil_get_values()` generic observed/derived/modelled values with typed value, target, geometry (sf), status, optional lineage. | Plan T5; #16 | yes (`read.R:213-228`) | unchanged (unit fields removed from the API by #46; client never used them) |
| RQ-26 | `soil_get_target_ids()` resolves source identities to canonical UUIDs (chunks of 10,000), fails on missing or ambiguous. | Plan T5; #16 | yes (`read.R:231-243`; `test-read.R`) | unchanged |
| RQ-27 | `layer = "all" \| "first"` available on reads; `max_records` caps rows (horizons in wide, measurements in long), so a profile may be cut; docs must say so. | `docs/r-student-guide.md:170-178`; `r-first-steps.md:84` | yes (pass-through; wording in docs) | changed: `layer=first` redefined (ties at depth 0, `first_layer_status`, `profile_markings`, no fallback to a deeper horizon) and now shared by long and wide (#47 documented as implemented; issue still open) |
| RQ-28 | Missing geometry handled explicitly: empty geometry + one warning, never fabricated coordinates (WISE sites without coordinates). | #35; `docs/r-client.md:148-150` | yes (`read.R:115-128`) | changed: WISE coordinates restored (migration 163, #44), so far fewer empty geometries |
| RQ-29 | Reads return `data.frame`/`sf`/lists (no JSON for the user); response `metadata` (warnings, filters, request id) is available to the user. | Plan "Architecture" | partial: types yes; response metadata is dropped on observation/feature/value reads (kept only as attribute on `soil_variables` and in `soil_consistency`). | changed: `metadata.warnings` now carries conflicting duplicates, mixed units, multi-value counts |

### 2.5 Wide layout (issue #42, spec 2026-10-07)

| ID | Requirement | Source | Status | API relation |
| --- | --- | --- | --- | --- |
| RQ-30 | `soil_get_data()` and `soil_get_observations()` take `layout = c("wide","long")` (default **wide**) and `geometry_format = c("none","wkt")`; wide = one row per horizon, columns `<key>`, `<key>_units`, `<key>_n`; long kept as before. | #36, #42; spec "R Client" | yes (`read.R:70-113,144-210`; `test-read-wide.R`, 7 blocks). **Unreleased.** | changed: wide rows now also carry `<key>_method`, `value_flags`, `first_layer_status`, `profile_markings`, `retired_in_release`, `retired_cells`, component/source attribute columns; the client types only `<key>`, `<key>_units`, `<key>_n`, the rest pass through untyped or as list columns |
| RQ-31 | Typing from `metadata.variables`: `<key>` numeric only if every page says numeric, `_units` character, `_n` integer; pages with different columns are aligned with `NA`. | Spec "R Client" | yes (`read.R:70-90,92-113`) | changed: since 2026-10-08 a multi-value WoSIS cell (e.g. `["0.9","0.9"]`) arrives as JSON text inside a column still flagged numeric; by code reading `as.numeric()` would turn it into `NA` with a coercion warning (not run) |
| RQ-32 | `geometry_format="wkt"` returns an `sf` (EPSG:4326) with `geometries[feature_id]` copied to every row; rows without geometry keep an empty geometry and one warning. | Spec; #42 | yes (`read.R:115-128`) | unchanged |
| RQ-33 | Client-side rejection mirroring the API: wide needs `canonical=TRUE`, `include_geometry=TRUE` not allowed with wide, `geometry_format` needs wide. | Spec "Validation" | yes (`read.R:150-159`) | unchanged |
| RQ-34 | Old server without `capabilities.wide_layout` raises an error naming the minimum API version (0.4.0). | Spec | yes (`read.R:130-136`; one extra `GET /capabilities` per call) | unchanged (API is 0.5.0) |
| RQ-35 | `max_records` counts horizons in wide; paging by `has_more` (wide `total_count` is `null`). | Spec | yes | unchanged |
| RQ-36 | Student-visible semantics: no unit conversion, no hidden aggregation; repeated values visible through `_n`; "a limit of 100 horizons can leave a profile incomplete". | #36; `docs/r-first-steps.md:79-90`, `r-student-guide.md:184-191,263-267` | yes (documented; collapse is done by the API) | changed: multi-value cells and value flags are new (see RQ-31) |

### 2.6 Publication of derived values

| ID | Requirement | Source | Status | API relation |
| --- | --- | --- | --- | --- |
| RQ-37 | `soil_register_variable()` validates (`POST /variables/validate`) then registers (`POST /variables`) with an idempotency key; needs `soil:admin`; never direct DB. | #17; plan T6 | yes (`publication.R:29-43`; `test-publication.R`). Not capability-gated although the plan asked for it. | changed: `canonical_unit` removed from the request (#46); client already aligned, the plan signature is stale |
| RQ-38 | Product / immutable version / run lifecycle driven from R (`.soil_prepare_run`), accepting either definitions to create or already created objects. | #17 | partial: creation yes (`publication.R:45-55`); plan items not built: 409 idempotent-recovery vs true conflict, run completion/failure (`/complete`, `/fail` never called), "never complete a run with rejected or active jobs". | unchanged |
| RQ-39 | `soil_publish_derived()`: local check of required fields, server `validate` first, publish only a valid batch, return receipt + run ids; mandatory idempotency key. | #17; plan T6 | partial: checks only `variable_code`, `target_level`, `target_id`, `lineage` on the first record (`publication.R:58-86`); plan asked for `value_status`, typed value, release id, lineage lists, and a pre-check that the variable exists. | unchanged (sync limit 10,000 rows) |
| RQ-40 | Scale: synchronous up to 10,000 rows, above that a checksummed NDJSON (or Parquet) job with polling and timeout (default 3600 s). | #17; `docs/r-client.md:166-167` | partial: NDJSON yes; Parquet is accepted as an argument but stops with an error (even when `arrow` is installed). | unchanged (`max_publication_bytes` 512 MB) |
| RQ-41 | `soil_publication_status()` and `soil_cancel_job()` on the unified job endpoints. | #17, #19 | yes (`publication.R:89-96`) | unchanged |
| RQ-42 | Write acceptance: register variables and publish intermediate/final results through the ETL account, then verify re-read, lineage, idempotency, reader denial and cleanup. | Plan "Operational Acceptance Follow-Up" (closing step 6) | no: deferred by the operator; only an isolated synthetic publication test on the VM (run left `running`). | n/a |

### 2.7 Soil health

| ID | Requirement | Source | Status | API relation |
| --- | --- | --- | --- | --- |
| RQ-43 | `soil_publish_health()` transports externally computed scores and fuzzy details (memberships, rules, inputs, diagnostics); required fields and allowed `score_status`; sync up to 10,000 else NDJSON job; the client contains no fuzzy logic. | #18; plan T7; `docs/r-client.md:176-181` | partial: required fields and status checked on first/all rows (`health.R:1-30`); not built: horizon-UUID/score-class consistency checks, multi-batch with receipt/count reconciliation, Parquet. | unchanged |
| RQ-44 | `soil_get_health()` with provider, dataset, release, model version, run, category, class, status, support, country, bbox, depth filters, optional geometry (sf) and details. | #18 | yes (`health.R:33-54`; `test-health.R`) | unchanged |

### 2.8 Source and geography ingest

| ID | Requirement | Source | Status | API relation |
| --- | --- | --- | --- | --- |
| RQ-45 | `soil_publish_entities()` builds a provider-neutral source bundle from `sf` features (CRS required, to 4326, every feature needs `source_record_id`) and optional profile/component/horizon/observation tables, uploads manifest + file, validates, promotes (or `auto_promote`), polls to a terminal state; temp files removed unless `keep_file`. | #19; plan T8 | partial: flow yes (`entities.R:45-81`; `test-source-ingest.R`, 1 block); transport always NDJSON (Parquet only nominal); plan's "verify checksum and staged counts" and local parent-relationship validation not done on the client (the guide says the bundle "validates all parent relationships": that is the server's `validate`). | changed: #58 fixed a promotion failure on observation records; ingest never accepted in production by the client (RQ-42) |
| RQ-46 | New geography never goes through the value-publication API; function is capability-gated (`source_ingest`, scope `soil:publish`) and errors before any write. | Plan "Scope"; #19 | yes (`entities.R:1-13,52`; `test-api-gates.R`) | unchanged |

### 2.9 Packaging, distribution, dependencies

| ID | Requirement | Source | Status | API relation |
| --- | --- | --- | --- | --- |
| RQ-47 | Source delivery: `source("R/soilhub.R")` from any working directory, no attached packages, no `setwd`, no installs, no global connection state. | #12; plan T1 | yes (`R/soilhub.R`; `test-loader.R`) | n/a |
| RQ-48 | Package-ready code: no top-level side effects, no `library()`/`require()`/`setwd()`; temporary DESCRIPTION/NAMESPACE + roxygen + `R CMD check --no-manual` must pass. | #21; plan T10 | yes (`tests/r/check_package_readiness.R`). Roxygen blocks are mostly one-line titles (no `@param`/`@export`; exports by pattern `^soil_`). | n/a |
| RQ-49 | Installable versioned source package `soilhub` built by the Bash wrapper: version X.Y.Z from DESCRIPTION, no overwrite, per-version lock + receipt that survives archive deletion, real maintainer email, no placeholder metadata, no upload/tag/dependency install. | `docs/r-package-distribution.md` | yes (`scripts/build_r_package.{sh,R}`; `tests/r/test_package_archive.R`) | n/a |
| RQ-50 | Distribution through GitHub Releases of the public `soilhub-r` repo (asset `soilhub_X.Y.Z.tar.gz`, not GitHub's auto source archive); infrastructure repo stays private; every push, tag or upload is an explicit operator action; CRAN is a separate later decision (name check 2026-09-15: no conflict). | `docs/r-package-distribution.md:3-53,146-155` | yes (v0.1.1-v0.1.3 published). The public repo holds no code or tests. | n/a |
| RQ-51 | Release approval policy (2026-10-06): finish open issues first; version, archive and publication need explicit operator authorisation; local commits and tests are not releases. | `docs/r-package-distribution.md:3-15`; #37 | yes (in force; next version undecided) | n/a |
| RQ-52 | One-step latest-release installer without a hard-coded version (queries the GitHub API, installs the single `soilhub_*.tar.gz` asset, installs missing CRAN dependencies); needs R >= 4.1 (pipe). | `soilhub-r/README.md` | yes | n/a |
| RQ-53 | Dependencies: Imports `httr2, jsonlite, curl, openssl, sf, stats, utils`; Suggests `arrow`; nothing installed automatically; `soil_check_dependencies()` lists the missing ones; `soil_install_dependencies()` only on explicit call with consent; optional `renv`. | #12, #20; `docs/r-client.md:21-34` | yes (`dependencies.R`, `install_dependencies.R`). Facts: `sf` is a hard Import (system libraries on Linux) although `soil_check_dependencies()` treats it as optional; the Imports list is written in three places (`config/r-package/DESCRIPTION`, `scripts/build_r_package.R`, `dependencies.R`); no minimum R version declared (plan said 4.3+, README 4.1+). | n/a |
| RQ-54 | Report `httr2` as missing only when it is really missing; distinguish absent / unloadable / incompatible; never auto-install; update misleading tutorial text; verify in source and installed modes; publish a versioned fix. | #38 (open) | no: reported behaviour not reproduced in the code (the check lists only missing packages); no tests for the unloadable/incompatible cases; nothing committed for #38. | n/a |
| RQ-55 | Test environment without host R: Docker image (Debian trixie distro packages), `scripts/test_r_docker.sh unit\|package\|live`; live mode read-only, secrets forwarded from `.env` only. | `docs/r-client.md:189-216` | yes (`docker/r-client.Dockerfile`, `scripts/test_r_docker.sh`) | n/a |
| RQ-56 | License: MIT + file LICENSE for the client code and docs; provider data, API/DB and models keep their own licences; MIT notices preserved on redistribution. | `docs/r-package-distribution.md:62-72` | yes (`config/r-package/LICENSE`) | changed: the API now serves provider licence/citation texts (#60); the client does not surface them |

### 2.10 Documentation and tutorials

| ID | Requirement | Source | Status | API relation |
| --- | --- | --- | --- | --- |
| RQ-57 | English student guide covering install, connect, discovery, reads, derived values, ingest, soil health, with a feature/profile/component/horizon/observation table. | #20; plan T9 | yes (`docs/r-client.md`) | partly stale (see RQ-62) |
| RQ-58 | Beginner path ending in a saved table: install once, login, check access, inventory for Spain, read 100 WoSIS horizons, `saveRDS` (without the connection), session-renewal check. | #36 ("simple RStudio tutorial using WoSIS profile points"); `docs/r-first-steps.md` | partial: API-repo version already uses wide `soil_get_data`; the public `soilhub-r/TUTORIAL.md` still shows long `soil_get_observations`, so the two disagree. | changed: wide default needs API >= 0.4.0 |
| RQ-59 | Read-only reference guide (inspect variables before use, bbox order, save data + extraction recipe + session info, fuzzy-model boundary, troubleshooting table, acceptance checklist). | `docs/r-student-guide.md` | yes; checklist (lines 298-306) never executed by the student. | partly stale: examples use `variables = c("oc","ph_h2o")` (`oc` not found as a key or code in `docs/isric-variable-semantics.md`; to be checked), `first` layer semantics changed |
| RQ-60 | Rmd tutorials bundled in the package (`inst/doc/soilhub-student.Rmd`, `soilhub-reference.Rmd`) with every chunk `eval=FALSE` so knitting never logs in or downloads. | `docs/r-client.md:6-15`; builder | yes (`build_r_package.R`) | n/a |
| RQ-61 | Four runnable examples (discovery, read, publish derived, publish health) without embedded secrets. | Plan T4-T7 | partial: files exist (`examples/r/`), tested only for parsing (`test-documentation-examples.R`); the plan required executing them against fakes. Examples 03/04 use undefined placeholders. | example 02 uses `soil_connect()` (technical secret) rather than the device login |
| RQ-62 | Documentation stays consistent with the delivered code. | implicit | no: versions disagree (`r-client.md` says 0.1.2, `r-student-guide.md` 0.1.2, `r-package-distribution.md` mixes 0.1.2/0.1.3, DESCRIPTION 0.1.3); `r-client.md` says "loaded with `source()` and does not need package installation" next to the package install section; wide-layout description assumes an unreleased client. | n/a |

### 2.11 Tests

| ID | Requirement | Source | Status | API relation |
| --- | --- | --- | --- | --- |
| RQ-63 | Unit/contract tests per module against a fake API (webfakes), no production credentials. | Plan; #12-#21 | yes (17 files; all pass on 2026-10-18; run with `R_PROFILE_USER=/dev/null Rscript --no-init-file tests/r/run_tests.R` because this Mac's user profile points at a missing VS Code file) | fakes encode the API shapes of the time; they do not detect API drift (e.g. RQ-31) |
| RQ-64 | Clock-controlled authentication tests: cache, refresh, rotation, denied login, PKCE relation, 401 renewal. | #13, #37 | yes (`test-device-auth.R`, `test-http-renewal.R`) | n/a |
| RQ-65 | Opt-in read-only live smoke test (health, capabilities, inventory, 5 observations, 5 geometries); never publishes. | Plan T9; `docs/r-client.md:206-209` | yes (`tests/r/live_read_smoke.R`), uses technical credentials and `include_geometry=FALSE`, long layout, legacy features; not run in this inventory | partly outdated for wide and canonical ids |
| RQ-66 | Archive test: build a fixture archive, verify contents, reject invalid or duplicate versions, install in an isolated library, check exports. | `docs/r-package-distribution.md:128-144` | yes (`tests/r/test_package_archive.R`) | n/a |
| RQ-67 | Real-session acceptance: installed package, student account, RStudio Server, read after > 6 minutes, multi-hour run. | Plan "Completion Criteria", #35, #37 | no (see section 3) | n/a |

## 3. Open items

**Open issues**

| Issue | State | Facts |
| --- | --- | --- |
| #37 AUTH-01 multi-hour sessions | Open, `Todo` on board 7, deferred by the operator | Code fix done and tested but unreleased (`bdfcbfb`). Unmet acceptance: confirmed active/idle targets, real elapsed-time RStudio session, sanitised TTL record, reader permissions unchanged. Operator says `ams-r` lifetime is now 2 h (not verified). Reopen only if problems recur. |
| #38 R-DEP-01 `httr2` message | Open, `Todo` on board 7 | No commit. All acceptance boxes unmet; see RQ-54. |
| #42 wide layout | Open (not on board 7) | R side implemented (`97366e9`, unreleased); API side implemented in 0.4.0; acceptance boxes still unticked, including the live R check with points and polygons. |

**Closed on the board but with undelivered parts** (#35, #36 closed 2026-10-09 as "superseded" by #41-#45 / #42): "test the installed public package on RStudio Server and publish a versioned fix" and the user review of wide examples were not done for the wide default; no release contains it.

**Promised, not delivered**

- Write acceptance (plan closing step 6) and final verification (step 7): deferred; full ETL round trip, geographic-ingest test and reader-denial test never run.
- Student acceptance checklist (`docs/r-student-guide.md:298-306`) and installed-package read test from the student's RStudio Server session: not executed.
- Next release: 17+ unpublished commits, 0.1.4 withdrawn, no version chosen; public `soilhub-r` README/TUTORIAL describe 0.1.3.
- Plan items not built: capability gate on `soil_register_variable`; variable-existence pre-check in `soil_publish_derived`; HTTP 409 recovery; run completion/failure helpers; Parquet transport (publish, health, ingest); health multi-batch reconciliation and score/class checks; ingest staged-count check; OpenAPI fallback for capabilities; execution of documentation examples against fakes.
- Web and mobile Keycloak client registrations: deferred (no applications yet; not an R item).

## 4. Gaps: current API capabilities with no requirement in the client

- `view=raw|revised` (all canonical data endpoints, `/exports`, `/sotwis/ttr-flags`) and the rule metadata `metadata.revised`.
- `profile_type` filter (synthetic / virtual / none, with `!` exclusion).
- `components` and `min_cumulative_percent` (SOTWIS / SOTER component selection).
- `canonical=true` on `/query/features`, `/query/summary`, `/query/availability`; `POST /query/summary`, `POST /query/availability`, `POST /query/values/summary`, `POST /query/soil-health/summary` (none wrapped).
- `POST /exports`, `GET /exports/{id}`, `GET /exports/{id}/download` (zip: gpkg, geojson, csv, tsv, shp; whole selections).
- Load limits (#49): 422 `load_limit_exceeded` with `channel`, `max_observations`, `exports_url`; `limits.max_sync_observations` / `max_export_observations` in `/capabilities`.
- Provenance and attribution: `GET /datasets` licence, citation, release dates, `source_assets` with checksums, `retired_row_count`; dataset notes.
- Row markings: `retired_in_release`, `retired_cells`, `value_flags`, `revised_markings`, `first_layer_status`, `profile_markings`, `raw_markings` columns.
- Wide extras: `<key>_method` columns, `metadata.variables[].methods/source_notes/multi_value_cells`, WISE/SOTER source-attribute columns, multi-value cells as JSON text.
- `GET /code-lists`, `GET /code-lists/{name}`, `GET /sotwis/ttr-flags`, `GET /sotwis/ttr-flags/legend`.
- `GET /variables` with `include_unmapped`, `property_family`, per-dataset `source_mappings`; `GET /formats`.
- New datasets and models: `soter_profiles`, `sotwis_components`, `sotwis_estimates`; SOTER profile model, SOTWIS components.
- `POST /countries/refresh` (admin); dataset-specific job views `GET /publication-jobs/{id}` and `GET /soil-health-publication-jobs/{id}` (client uses the unified `GET /jobs/{id}`).
- `POST /publications/{run_id}/complete` and `/fail`.
- Surfacing of `metadata.warnings` / `metadata.request_id` to the user on reads.
- Page size is hard-coded to 1000 instead of read from `limits.max_page_size`.

## 5. Questions to decide before the redesign

1. **Where does the code live?**
   - (a) As now: code, tests and docs in the private API repo `R/`; public `soilhub-r` holds README, TUTORIAL and release assets only.
   - (b) One public package repo (`soilhub-r`) with code, tests, vignettes and releases; the API repo keeps at most an operations note.
   - (c) Package repo as source, API repo consumes it only for its Docker/live smoke tests.
   (The docs say the infra repo must stay private and nothing private may be copied; the plan kept the code "convertible into a package".)
2. **Delivery mode**: package only (`library(soilhub)`), or keep the `source("R/soilhub.R")` loader as a second path (the plan's first delivery; docs now push the package).
3. **Scope of write features**: keep all of `soil_register_variable`, `soil_publish_derived`, `soil_publish_health`, `soil_publish_entities`, job control in the student package; split them into a separate ETL/publisher package; or make the student client read-only and leave publication to Python/other tools. (Student guide: readers must not use writes; write acceptance never done; ETL needs `soil:admin`.)
4. **Authentication**: device flow with `ams-r` only for humans (current), or also authorisation code + PKCE with loopback (asked of Keycloak in the handoff); keep or drop the confidential-secret `soil_connect()` and password grant in a public package; session target for #37 (hours, idle interval); tokens in memory only (current) or an opt-in refresh-token cache (offline scope was not approved).
5. **Built-in URLs**: keep production URLs as defaults in public code (current), or require explicit `api_url` / environment configuration.
6. **Dependencies policy**: `sf` as hard Import (current) or Suggests with plain data-frame reads working without it; `arrow` (declared Suggests, unused); single source of truth for the dependency list; minimum R version (4.1 vs 4.3); keep `soil_install_dependencies()`; renv guidance; resolution of #38.
7. **Which API surface the client exposes**: curated arguments for `view`, `profile_type`, `components`, exports and load-limit handling, or thin pass-through of all request fields; whether to surface provenance, licence and citation of the datasets and row markings to the user; use `canonical=true` features everywhere.
8. **Default output shape**: wide data frame (current default), `sf` via `geometry_format="wkt"`, long kept as an option; how to present multi-value cells, flags and retired markings in R types.
9. **Compatibility**: keep 0.1.x function names and signatures (students and the published README depend on them) or break; version number of the redesigned release; minimum API version versus capability gating; release approval rules (RQ-51) stay as is.
10. **Documentation**: one beginner tutorial plus one reference (current) or one document; where it lives (API repo `docs/` generates the Rmd, or the package repo); language (English now); whether the thesis-student guide stays personal.
11. **Tests**: fake-API unit tests only (current), plus contract tests generated from the live OpenAPI/capabilities, plus an opt-in live smoke test with device login; keep the Docker image; where the test suite lives (follows question 1).
12. **Open items**: close #37 as deferred or keep it as an acceptance gate of the redesign; replace #38 by a new dependency requirement; run the deferred write acceptance (plan step 6) before or after the redesign.
