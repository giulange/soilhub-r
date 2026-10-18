# soilhub (development version)

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
