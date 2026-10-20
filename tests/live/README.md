# Live acceptance scripts (owner)

These scripts check soilhub 0.2.0 against the real Global Soil Data Hub API
and Keycloak (acceptance criteria 2–7 of the design, section 10; issue #14).
They need a person: each one starts with the **device login** (R prints a web
address and a code; you open the address in a browser, enter the code and
sign in). They are never run by `R CMD check` (the folder is excluded from
the package build).

Each run writes a log in `tests/live/logs/` (not committed), named
`<script>-<UTC date and time>.log`. The log holds what is needed to judge the
result (request ids, row and column counts, the first key of each table,
timings, PASS/FAIL per check) and **no token and no personal identifier**:
your user name and subject are replaced by `<user>`, tokens by `<token>`, and
the log is checked once more at the end. Attach the logs to issue #14.

Every script ends with a summary, one line per check, and
`RESULT: PASS` or `RESULT: FAIL` (WARN and SKIP do not make a run fail).

## How to run them

From the root of the package (the folder with `DESCRIPTION`), on the Mac:

```bash
R_PROFILE_USER=/dev/null Rscript --no-init-file tests/live/smoke.R
```

From the source tree the scripts load the package with `pkgload::load_all()`;
add `--installed` to use the installed soilhub instead (as a student would).
Away from the source tree (for example a copy of `tests/live/` on RStudio
Server with soilhub installed) they use the installed package. `--help`
lists the options of each script.

`--fake` (or `--dry-run`) runs a script on local fake servers built from the
unit-test fixtures: no login, no network, nothing written anywhere. It only
proves that the script itself runs; it says nothing about the API. Some
checks fail by construction in a fake run (see the end of this page).

## The scripts, in the order to run them

| # | Script | Account | Writes to the API | Time |
| --- | --- | --- | --- | --- |
| 1 | `smoke.R` | reader (student) | nothing | 5–15 min |
| 2 | `exports.R` | reader | 5 small export jobs (kept 7 days by the server) | 2–5 min |
| 3 | `session-hours.R --forced-expiry` | reader | nothing | about 5 min, attended |
| 4 | `session-hours.R` | reader | nothing | about 5 h 30 min, unattended |
| 5 | `write-acceptance.R` | publisher, then reader | yes, see below | 10–30 min |

Do not run 3 and 4 at the same time with the same account: ending the
Keycloak session in 3 also ends the session of 4.

### 1. `smoke.R` — one read on each dataset (criteria 3, 4, 7)

For each of `wosis_points`, `wise_profiles`, `soter_profiles`,
`soter_polygons`, `sotwis_polygons`, `sotwis_components`, `sotwis_estimates`:
a wide read of a small selection (at most 200 rows), the same read in the
long layout, the check that the two agree (same horizons, same values, same
counts), the same selection with `view = "revised"` listing the rules the API
applied, and for WoSIS and SOTER `layer = "first"` with the statuses found.
The selections are at the top of the script (WoSIS around Vancouver, WISE and
SOTER profiles in Kenya, SOTER polygons around Nairobi, SOTWIS polygons near
Tunis; the two SOTWIS tables without geometry: first layers only, and the
whole small estimates table). Then, signed in as a reader, it checks that a
write function is refused **before** any request, and that the API's own
refusal (HTTP 403, with the local check switched off) gives the same error.

```bash
R_PROFILE_USER=/dev/null Rscript --no-init-file tests/live/smoke.R
R_PROFILE_USER=/dev/null Rscript --no-init-file tests/live/smoke.R --datasets=wosis_points,sotwis_polygons
```

### 2. `exports.R` — exports end to end (criterion 5)

The WoSIS selection around Vancouver (4 profiles, 12 horizons) exported as
CSV, GeoPackage and GeoJSON, plus a Shapefile of the features only: each is
submitted, waited for, downloaded, unzipped and read back with
`soil_export_read()`, and its rows are compared with the synchronous read of
the same selection. Then a read of the whole catalogue (`datasets = NULL`),
which the API refuses as too large, is turned into an export with
`soil_export_from_error()`, giving the Vancouver box as a narrower selection
so the export stays small (exporting the whole catalogue and cancelling it
would start a job of millions of rows and needs the publish right to
cancel). Downloads go to a temporary folder, deleted at the end (`--keep`
keeps them). The GeoPackage and Shapefile steps need the package `sf`.

### 3. and 4. `session-hours.R` — sessions of several hours (criterion 2)

Keycloak values measured on 2026-10-18 for the client `ams-r`: access token
2 hours; refresh token 8 hours, replaced at every renewal; a pause of 95
minutes is survived; a session lasts at most 9 hours from the sign-in (then
the renewal is refused with `invalid_grant`, "Token is not active"). The
getting-started vignette states them.

**Main run (4).** After the sign-in it reads a few rows every 20 minutes for
4 hours, then makes no call for 90 minutes, then reads once more. Each line of
the log shows how long the access token and the session still last and how
many renewals happened. It passes when every read works without a new
browser step and the session was renewed. Options: `--hours=4`,
`--interval=20`, `--idle=90`.

Unattended on RStudio Server: open the **Terminal** tab, go to the folder
that holds `tests/live/` (for example a clone of the repository), and start
it detached, with its output in a file:

```bash
mkdir -p tests/live/logs
nohup env R_PROFILE_USER=/dev/null Rscript --no-init-file tests/live/session-hours.R --installed \
  > tests/live/logs/session-hours.out 2>&1 &
sleep 10; grep -A2 "to sign in" tests/live/logs/session-hours.out
```

Open the address shown and enter the code within 10 minutes. Then the
browser, the terminal and RStudio can be closed: the run goes on by itself.
Follow it with `tail -f tests/live/logs/session-hours-*.log`; the last line is
`RESULT: ...`. To stop it early: `pkill -f "tests/live/session-hours.R"`.
(If the server stops processes when the RStudio session ends, start the
same command with `setsid nohup ...`.)

**Forced expiry (3), attended.** After one read, the script asks you to end
the Keycloak session: in the browser open
`https://kc.weatherprogapp.it/realms/ams/account`, go to *Device activity*
(or *Sessions*) and choose *Sign out all devices*, then press Enter in the
terminal. The API checks a token only by its signature and expiry, so a
session ended in Keycloak shows at the next renewal: by default the script
marks the access token as expired on its side, so the next call asks Keycloak
at once (`--expiry=natural` waits instead until the token expires by itself,
up to 2 hours). The next call must fail with
`soilhub_auth_error(reason = "session_expired")`; then `soil_login()` asks
for a new browser sign-in and the session must work again.

```bash
R_PROFILE_USER=/dev/null Rscript --no-init-file tests/live/session-hours.R --forced-expiry
```

Run it in a terminal (it waits for Enter), not as an RStudio background job.

### 5. `write-acceptance.R` — writing with a publisher account (criteria 6, 7)

**It writes to the API.** The API is taken from `SOILHUB_API_URL`; against
production (`https://soilhub.weatherprogapp.it/api/v1`, also the default when
the variable is not set) the script refuses to run unless you add
`--allow-production`. The recommended target is the development API on the
Mac:

```bash
SOILHUB_API_URL=http://localhost:18080/api/v1 \
  R_PROFILE_USER=/dev/null Rscript --no-init-file tests/live/write-acceptance.R
```

Sign in first with an account that has `soil:publish` and `soil:admin` for
the audience of that API (the audience is the one in its `/capabilities`;
production uses `soil-api`). The steps: read a few WoSIS records around
Vancouver; find their ids with `soil_resolve_targets()`; register a test
variable (check, register, register again: the second time must be
recognised as a repetition); register the product and a new version; open a
run; publish 4 values in one request and about 10,050 values as a file job
(targets: WoSIS features of a country found with `soil_summary()`, Brazil
first; `--targets-country=` to choose); publish 2 soil-health scores (only
when the API knows `soil_health_physical_score`); close the run; read
everything back with `soil_values()` and its lineage; submit a large export
and cancel it at once (job cancel on a queued job; the export writes no
data); on a non-production API, publish and read back a tiny synthetic
source dataset of 2 sites. Then it asks you to sign in as a **reader**: sign
out of Keycloak in the browser first, or use a private window, otherwise the
browser approves the code as the publisher again. As a reader it checks
`soil_whoami()` and the refusals of criterion 7.

What stays on the API afterwards (the API has no delete for these; the
script deletes nothing; the log ends with the exact list and ids):

- the variable `zz_soilhub_acceptance_<stamp>` (`<stamp>` = UTC date and time
  of the run, e.g. `20261020101500`);
- the product `soilhub_acceptance` (registered once, reused by later runs)
  and its version `acceptance-<stamp>`;
- one completed run with about 10,055 values of the test variable on WoSIS
  features, and 2 scores `soil_health_physical_score` on WoSIS horizons:
  they appear in `soil_values()` and `soil_health_scores()` for every user;
- one cancelled export job;
- on a non-production API only: the provider `zz_soilhub_acceptance`, the
  dataset `zz_soilhub_acceptance_points` and its release `r<stamp>`
  (2 sites, 2 observations), visible in the catalogue.

Options: `--skip-cancel`, `--skip-reader`, `--ndjson-rows=N` (more than
10,000), `--poll=`, `--timeout=`.

## Fake runs (`--fake`)

The fake servers are the ones of the unit tests (`tests/testthat/helper-fake-*.R`),
so a fake run needs the source tree and the package `webfakes`. Hours pass in
seconds in `session-hours.R --fake` (a fake clock). Checks that fail in a fake
run because the hand-made fixtures cannot hold what the check expects:

- `exports.R` `5.shp`: the Shapefile fixture holds polygon features, the
  synchronous fixture point features;
- `write-acceptance.R` `6.2` (the fake recognises a repetition only for the
  key `"replay"`), `6.9` (the fake values are fixed fixtures), `6.11r` (the
  fake catalogue does not learn the new dataset).
