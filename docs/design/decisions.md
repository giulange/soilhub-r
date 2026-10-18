# R client redesign — decisions

Decisions taken with Giuliano Langella before the redesign of the R client (`soilhub`), on the basis of
[requirements-inventory.md](requirements-inventory.md). Questions are numbered as in section 5 of the inventory.

## Premise (2026-10-18)

- `soilhub` is **one library for every user** of the Global Soil Data Hub API, not a student package. Students
  were the first test bench of DB + API + R library for bug fixing and early enhancements.
- What a user can do depends on their **rights**, not on which library they install. A fingerprint + PDP layer
  (attributes and policies) is being completed by the user and will take over checks done today by the API or
  Keycloak, including load limits per user/group.

## Round 1 (2026-10-18)

| # | Question | Decision |
|---|---|---|
| 1 | Where the code lives | **(b)** One public package repo `giulange/soilhub-r` with code, tests, docs and releases; the API repo no longer holds the client. |
| 2 | Delivery mode | **(a)** Package only (`library(soilhub)`); the `source()` loader is dropped. |
| 3 | Write features | **(a)** One library with read and write functions; differences come from the user's rights (Keycloak roles today, fingerprint + PDP later). No separate publisher package. |
| 4 | Authentication | **(a)** People: device flow only, tokens in memory, automatic renewal for multi-hour sessions (#37 becomes an acceptance gate). Password grant and confidential-secret login leave the public package. |
| 5 | Default API URL | **(a)** Production URL built in, overridable by configuration. |
| 4-bis | Access for programs | **(b)** The R library is for **human users only**. Any process run by a machine user (unattended jobs, models, ETL) is written in Python, as for the weather DBAPI. No client-credentials or secret-based login in the library; device flow only. |

## Round 2 (2026-10-18)

| # | Question | Decision |
|---|---|---|
| 6 | Dependencies | **(a)** `sf` optional (Suggests): reads without geometry work without it, geometry returns `sf`. Minimum R 4.1. `arrow` and `soil_install_dependencies()` removed; package installation handles dependencies. Closes #38. |
| 7 | API surface | **(a)** Explicit, documented arguments for everything the API offers today: `view` raw/revised, `layer`, `profile_type`, wide/long layout, variables, filters; summary and availability; exports with waiting and download; catalog with provenance, licences and citations; always canonical data. A load-limit refusal explains how to proceed (e.g. an export). |
| 8 | Output shape | **(a1)** Default wide data frame (one row per horizon, one column per property), `sf` when geometry is requested, long layout as an option. Multi-value WoSIS cells: the numeric column holds the value WoSIS publishes (the mean) and a companion column keeps all original values. Markings (flags, retired, first-layer status) are ordinary columns. |
| 9 | Compatibility | **(a)** Free redesign: function names and arguments may change; new version (e.g. 0.2.0) with a migration note from 0.1.x; the library checks API version and capabilities at start. |
| 10 | Documentation | **(a)** In the package repo: getting-started guide, full function reference, pkgdown site; English; the personal thesis guide becomes a generic guide. |
| 11 | Tests | **(a)** Three levels: fake-API unit tests; contract tests against the API's official description (OpenAPI/capabilities) to catch API drift; opt-in live smoke test with login. |
| 12 | Open items | **(a)** #37 (multi-hour sessions) is an acceptance gate of the redesign; #38 closes, superseded by decision 6; the never-run write acceptance becomes part of the acceptance of the new version. |
