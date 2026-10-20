# Live test of a multi-hour session (#37; design 3.3, 7.3; acceptance
# criterion 10.2). Read-only: nothing is written to the API.
#
# Main mode (unattended after the sign-in): a small read every 20 minutes for
# 4 hours, then 90 minutes without any call, then one more read. The log
# shows, for every read, the time left to the access token and to the
# session and the number of renewals (never a token). PASS when every read
# succeeds without a new browser step and the session was renewed.
#
#   Rscript tests/live/session-hours.R                      # 4 h + 90 min idle
#   Rscript tests/live/session-hours.R --hours=4 --interval=20 --idle=90
#
# Forced expiry (attended, about 5 minutes): after a first read the script
# asks you to end the Keycloak session in the browser, then checks that the
# next call fails with soilhub_auth_error(reason = "session_expired") and
# that soil_login() signs in again cleanly (a second browser step).
#
#   Rscript tests/live/session-hours.R --forced-expiry
#   Rscript tests/live/session-hours.R --forced-expiry --expiry=natural
#
# Dry run on a fake Keycloak and a fake clock (hours pass in seconds):
#
#   Rscript tests/live/session-hours.R --fake
#   Rscript tests/live/session-hours.R --fake --forced-expiry
#
# How to run it unattended on RStudio Server, and the Keycloak facts measured
# on 2026-10-18 for the client ams-r: tests/live/README.md.

.live_dir <- local({
  file <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(file)) dirname(normalizePath(file[1])) else normalizePath(file.path("tests", "live"))
})
source(file.path(.live_dir, "common.R"))

usage <- c(
  "Usage: Rscript tests/live/session-hours.R [options]",
  "  --hours=H          duration of the reading phase in hours (default 4)",
  "  --interval=M       minutes between two reads (default 20)",
  "  --idle=M           minutes without any call after the reading phase (default 90)",
  "  --forced-expiry    the forced-expiry test instead (attended)",
  "  --expiry=force     forced expiry: mark the access token expired locally after you end the",
  "                     session, so the next call asks Keycloak at once (default)",
  "  --expiry=natural   forced expiry: wait until the access token expires by itself (up to 2 h)",
  "  --installed        use the installed soilhub even in the source tree",
  "  --fake, --dry-run  run on a fake Keycloak with a fake clock (no login, no network)"
)
opts <- live_init(
  "session-hours", .live_dir,
  list(hours = 4, interval = 20, idle = 90, forced_expiry = FALSE, expiry = "force"),
  usage
)
if (!opts$expiry %in% c("force", "natural")) live_usage_error("`--expiry` must be `force` or `natural`")

# Measured on 2026-10-18 for the public client ams-r (Keycloak realm ams).
keycloak_facts <- c(
  "access token 7200 s (2 h)",
  "refresh token 28800 s (8 h), rotated at every renewal",
  "an idle gap of 95 minutes is survived",
  "maximum session 9 h from the sign-in (then the renewal fails: invalid_grant, \"Token is not active\")"
)

live_run(function() {
  if (live$fake) {
    env <- live_fake_start("auth")
    clock <- env$local_fake_clock(start = Sys.time(), .local_envir = new.env())
  }
  live_log(paste("Keycloak facts measured on 2026-10-18 for ams-r:", paste(keycloak_facts, collapse = "; ")))

  soil <- live_connect("reader")

  # The small read of each step: WoSIS around Vancouver, 5 rows (fake run:
  # the capabilities, the one protected route of the fake API).
  probe <- function() {
    if (live$fake) {
      soil_capabilities(soil, refresh = TRUE)
      return("capabilities read")
    }
    x <- soil_observations(soil, datasets = "wosis_points", bbox = c(-123.3, 49.0, -122.9, 49.4),
                           max_rows = 5, progress = FALSE)
    sprintf("%d rows, request id %s", nrow(x), paste(soil_metadata(x)$request_ids, collapse = " "))
  }
  remaining <- function(at) {
    if (is.null(at) || all(is.na(at))) return("unknown")
    soilhub:::format_duration(as.numeric(difftime(at, live_now(), units = "secs")))
  }
  t0 <- live_now()
  elapsed <- function() soilhub:::format_duration(as.numeric(difftime(live_now(), t0, units = "secs")))
  state <- soil$state
  logged_in_at <- state$logged_in_at

  # One read, logged with the lifetimes and the renewals; TRUE when it worked.
  read_once <- function(label) {
    before <- state$renewals %||% 0L
    outcome <- tryCatch(probe(), error = function(e) e)
    ok <- !inherits(outcome, "error")
    renewals <- state$renewals %||% 0L
    live_logf(
      "  %-12s +%-7s %s; token left %s, session left %s, renewals %d%s",
      label, elapsed(),
      if (ok) paste("OK,", outcome) else sprintf("FAILED (%s: %s)", class(outcome)[1], conditionMessage(outcome)),
      remaining(state$expires_at), remaining(state$refresh_expires_at), renewals,
      if (renewals > before) sprintf(" (renewed now, at %s)", soilhub:::format_time(state$last_renewed_at)) else ""
    )
    list(ok = ok, error = if (ok) NULL else outcome)
  }

  if (!isTRUE(opts$forced_expiry)) {
    n_reads <- floor(opts$hours * 60 / opts$interval) + 1L
    live_logf("Plan: %d reads every %g min (%g h), then %g min idle, then one read; about %s in all.",
              n_reads, opts$interval, opts$hours, opts$idle,
              soilhub:::format_duration((opts$hours * 60 + opts$idle) * 60))
    results <- list()
    for (i in seq_len(n_reads)) {
      if (i > 1L) live_wait(opts$interval * 60)
      results[[length(results) + 1L]] <- read_once(sprintf("read %02d", i))
    }
    live_logf("  idle: no call for %g min (until about %s UTC)", opts$idle,
              format(live_now() + opts$idle * 60, "%H:%M", tz = "UTC"))
    live_wait(opts$idle * 60)
    after_idle <- read_once("after idle")
    results[[length(results) + 1L]] <- after_idle
    total <- as.numeric(difftime(live_now(), t0, units = "secs"))

    live_check("2.1", sprintf("reads every %g min for %g h, then %g min idle, without a browser step", opts$interval, opts$hours, opts$idle), function() {
      failed <- sum(!vapply(results, `[[`, TRUE, "ok"))
      relogin <- !identical(as.numeric(state$logged_in_at), as.numeric(logged_in_at))
      lifetime <- state$access_lifetime %||% NA_real_
      renewals <- state$renewals %||% 0L
      problems <- c(
        if (failed) sprintf("%d read(s) failed", failed),
        if (relogin) "a new sign-in happened",
        if (!is.na(lifetime) && total > lifetime && renewals < 1L) "the session was never renewed",
        if (!after_idle$ok) "the read after the idle gap failed"
      )
      v_expect(!length(problems), if (length(problems)) paste(problems, collapse = "; ") else
        sprintf("%d reads over %s, %d renewal(s), no new sign-in", length(results), soilhub:::format_duration(total), renewals))
    })
    live_check("2.2", "lifetimes observed (for the vignette)", function() {
      lifetime <- state$access_lifetime %||% NA_real_
      session_left <- if (is.null(state$refresh_expires_at) || all(is.na(state$refresh_expires_at))) NA_real_ else
        as.numeric(difftime(state$refresh_expires_at, state$last_renewed_at %||% state$logged_in_at, units = "secs"))
      live_logf("      access token lifetime %s s; refresh lifetime after the last renewal %s s; renewals %d; last renewal %s",
                format(lifetime), format(round(session_left)), state$renewals %||% 0L,
                soilhub:::format_time(state$last_renewed_at))
      v_pass(sprintf("access %s s, refresh %s s", format(lifetime), format(round(session_left))))
    })
  } else {
    live_check("2.3", "a read before the session is ended", function() {
      r <- read_once("before")
      v_expect(r$ok, "read OK")
    })
    if (live$fake) {
      live_log("FAKE: Keycloak ends the session (POST /test/revoke on the fake server).")
      live$fake_env$server_post(live$servers$auth, "/test/revoke")
    } else {
      live_prompt(paste0(
        "end the Keycloak session of this account now: open ", soil$keycloak_url, "/account in the browser, ",
        "go to 'Device activity' (or 'Sessions') and choose 'Sign out all devices' (or sign out of the ",
        "session of the client ams-r). Then come back here."
      ))
    }
    if (identical(opts$expiry, "force")) {
      # The API checks the access token by its signature and expiry only: a
      # session ended in Keycloak is noticed at the next renewal. Marking the
      # access token expired here makes the next call renew at once, as it
      # would by itself when the token expires (up to 2 h later).
      state$expires_at <- live_now() - 1
      live_log("The access token is marked as expired locally: the next call asks Keycloak to renew the session.")
    }
    expired <- live_check("2.4", "the next call fails with soilhub_auth_error(reason = \"session_expired\")", function() {
      deadline <- live_now() + 130 * 60
      repeat {
        r <- read_once("after end")
        if (!r$ok || identical(opts$expiry, "force") || live_now() > deadline) break
        live_log("  the access token is still valid: next attempt in 10 min")
        live_wait(600)
      }
      e <- r$error
      if (is.null(e)) return(v_fail("the read succeeded: was the Keycloak session ended?"))
      live_logf("      %s, reason %s: %s", class(e)[1], format(e$reason %||% NA), conditionMessage(e))
      v_expect(inherits(e, "soilhub_auth_error") && identical(e$reason, "session_expired"),
               sprintf("%s (reason %s)", class(e)[1], format(e$reason %||% NA)), value = e)
    })
    live_check("2.5", "a clean soil_login() recovery on the same session", function() {
      if (!live$fake) live_log("Sign in again: open the address printed below in a browser and enter the code.")
      soil_login(soil)
      live_track_session(soil, "reader")
      r <- read_once("after login")
      me <- soil_whoami(soil)
      v_expect(r$ok && identical(me$status, "signed_in") && identical(me$renewals, 0L),
               sprintf("read %s; status %s, renewals %d", if (r$ok) "OK" else "failed", me$status, me$renewals))
    })
  }
})
