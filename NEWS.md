# soilhub (development version)

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
