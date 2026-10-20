# Live smoke test of soilhub (design 7.3; acceptance criteria 10.3, 10.4 and
# the reader part of 10.7). Read-only: nothing is written to the API.
#
#   Rscript tests/live/smoke.R                 # from the package root
#   Rscript tests/live/smoke.R --datasets=wosis_points,sotwis_polygons
#   Rscript tests/live/smoke.R --fake          # dry run on local fake servers
#
# Sign in with a READER account (soil:summary, soil:read):
# the last checks verify that a reader is refused writes. With a publisher
# account they are skipped. See tests/live/README.md.

.live_dir <- local({
  file <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(file)) dirname(normalizePath(file[1])) else normalizePath(file.path("tests", "live"))
})
source(file.path(.live_dir, "common.R"))

# The bounded selections, one per dataset: each below the synchronous limit
# (1,000,000 observations) and not empty. `sotwis_components` and
# `sotwis_estimates` have no geometry (no bbox or country filter): the first
# is narrowed to its first layers (D1, about 640,000 observations), the
# second is small (459,264 observations) and read unfiltered.
selections <- list(
  wosis_points = list(bbox = c(-123.3, 49.0, -122.9, 49.4)),      # Vancouver
  wise_profiles = list(country = "KEN"),
  soter_profiles = list(country = "KEN"),
  soter_polygons = list(bbox = c(36.6, -1.45, 37.1, -1.1)),       # KENSOTER, Nairobi
  sotwis_polygons = list(bbox = c(10.0, 36.5, 10.5, 37.0)),       # near Tunis
  sotwis_components = list(layer = "first"),
  sotwis_estimates = list()
)
first_layer_datasets <- c("wosis_points", "soter_profiles", "soter_polygons")

usage <- c(
  "Usage: Rscript tests/live/smoke.R [options]",
  "  --datasets=a,b     datasets to read (default: all seven; fake run: wosis_points)",
  "  --max-rows=N       rows of each bounded read (default 200)",
  "  --installed        use the installed soilhub even in the source tree",
  "  --fake, --dry-run  run on local fake servers (no login, no network)"
)
opts <- live_init("smoke", .live_dir, list(datasets = "", max_rows = 200), usage)

live_run(function() {
  if (live$fake) live_fake_start(c("auth", "catalog", "wide", "long", "thematic", "write"))
  datasets <- if (nzchar(opts$datasets)) strsplit(opts$datasets, ",", fixed = TRUE)[[1]] else if (live$fake) "wosis_points" else names(selections)
  unknown <- setdiff(datasets, names(selections))
  if (length(unknown)) stop("no selection defined for: ", paste(unknown, collapse = ", "))
  max_rows <- opts$max_rows

  soil <- live_connect("reader")

  live_check("0.1", "API reachable, versions compatible", function() {
    info <- soil_api_info(live_route(soil, "catalog"))
    live_logf("      API %s, schema %s, client %s, compatible %s",
              format(info$api_version %||% NA), format(info$schema_version %||% NA),
              format(info$client_version %||% NA), format(info$compatible %||% NA))
    v_expect(!isFALSE(info$compatible), "API version supported by this client")
  })

  me <- live_check("7.1", "soil_whoami() of the signed-in account (redacted)", function() {
    me <- live_log_whoami(soil)
    live_logf("      can: %s", paste(sprintf("%s=%s", names(me$can), me$can), collapse = " "))
    v_expect(identical(me$status, "signed_in") && !isFALSE(me$can[["read"]]),
             sprintf("rights %s", if (isTRUE(me$rights_known)) paste(me$roles, collapse = ", ") else "not declared in the token"),
             value = me)
  })

  live_check("0.2", "summary of the WoSIS selection (sizing before a read)", function() {
    s <- soil_summary(live_route(soil, "thematic"), datasets = "wosis_points", bbox = selections$wosis_points$bbox)
    live_logf("      features %s, horizons %s, observations %s",
              format(s$feature_count %||% NA), format(s$horizon_count %||% NA), format(s$observation_count %||% NA))
    v_expect(is.numeric(s$observation_count), "counts returned")
  })

  live_check("0.3", "five WoSIS features (geometry as text)", function() {
    f <- soil_features(live_route(soil, "long"), datasets = "wosis_points", bbox = selections$wosis_points$bbox,
                       with_geometry = "text", max_rows = 5, progress = FALSE)
    live_logf("      %d features, %d columns, request ids %s, first feature_key %s", nrow(f), ncol(f),
              paste(soil_metadata(f)$request_ids, collapse = " "), if (nrow(f)) f$feature_key[1] else "none")
    v_expect(nrow(f) > 0L, sprintf("%d features", nrow(f)))
  })

  for (dataset in datasets) {
    sel <- selections[[dataset]]
    read <- function(layout = "wide", view = "raw", layer = sel$layer %||% "all") {
      args <- c(
        list(live_route(soil, if (layout == "long") "long" else "wide"), datasets = dataset),
        sel[setdiff(names(sel), "layer")],
        list(layer = layer, view = view, layout = layout, max_rows = max_rows, progress = FALSE)
      )
      started <- Sys.time()
      x <- do.call(soil_observations, args)
      live_logf("      %s (%.1f s)", live_describe(x), as.numeric(difftime(Sys.time(), started, units = "secs")))
      x
    }
    label <- sprintf("%s %s", dataset, paste(sprintf("%s=%s", names(sel), vapply(sel, paste, "", collapse = ",")), collapse = " "))

    wide <- live_check(sprintf("3.%s.wide", dataset), sprintf("bounded wide read: %s, max_rows %d", label, max_rows), function() {
      x <- read("wide")
      v_expect(nrow(x) > 0L, sprintf("%d rows, %d variable columns", nrow(x), nrow(soil_columns(x))), value = x)
    })
    long <- live_check(sprintf("3.%s.long", dataset), sprintf("the same long read: %s", label), function() {
      x <- read("long")
      v_expect(nrow(x) > 0L, sprintf("%d observations, total_count %s", nrow(x), format(soil_metadata(x)$total_count)), value = x)
    })
    live_check(sprintf("4.%s", dataset), sprintf("wide/long equivalence: %s", dataset), function() {
      if (is.null(wide) || is.null(long)) return(v_skip("needs both reads"))
      eq <- live_equivalence(wide, long)
      for (m in utils::head(eq$mismatches, 10)) live_logf("      mismatch: %s", m)
      v_expect(eq$ok, eq$detail)
    })
    live_check(sprintf("3.%s.revised", dataset), sprintf("view = \"revised\" lists the applied rules: %s", dataset), function() {
      x <- read("wide", view = "revised")
      rules <- soil_revised_rules(x)
      applied <- if (is.data.frame(rules) && nrow(rules) && "n" %in% names(rules)) rules[!is.na(rules$n) & rules$n > 0, , drop = FALSE] else rules
      live_logf("      view %s; %d rule(s) reported, %d applied in this selection",
                format(soil_metadata(x)$view %||% NA), if (is.data.frame(rules)) nrow(rules) else 0L,
                if (is.data.frame(applied)) nrow(applied) else 0L)
      if (is.data.frame(applied) && nrow(applied)) live_log_table(applied[, intersect(c("id", "n", "effect", "title"), names(applied)), drop = FALSE])
      v_expect(identical(soil_metadata(x)$view, "revised") && is.data.frame(rules),
               sprintf("%d applied rule(s)", if (is.data.frame(applied)) nrow(applied) else 0L))
    })
    if (dataset %in% first_layer_datasets) {
      live_check(sprintf("3.%s.first", dataset), sprintf("layer = \"first\" shows the statuses: %s", dataset), function() {
        x <- read("wide", layer = "first")
        if (!nrow(x)) return(v_fail("no row"))
        statuses <- table(x$first_layer_status, useNA = "ifany")
        live_logf("      first_layer_status: %s", paste(sprintf("%s=%d", names(statuses), as.integer(statuses)), collapse = " "))
        vocabulary <- soil_first_layer(x)
        if (is.list(vocabulary)) {
          live_logf("      vocabulary (metadata.first_layer, view %s): statuses %s; profile markings %s",
                    format(vocabulary$view %||% NA), paste(unlist(vocabulary$statuses), collapse = ", "),
                    paste(unlist(vocabulary$profile_markings), collapse = ", "))
        }
        if (!is.null(x$profile_markings)) {
          marks <- table(unlist(x$profile_markings))
          if (length(marks)) live_logf("      profile_markings: %s", paste(sprintf("%s=%d", names(marks), as.integer(marks)), collapse = " "))
        }
        v_expect(!anyNA(x$first_layer_status), sprintf("%d rows, statuses %s", nrow(x), paste(names(statuses), collapse = ", ")))
      })
    }
  }

  if (is.list(me)) {
    if (live$fake) {
      # the fake write API answers 403 to every route after /test/deny
      live$fake_env$fake_control(live$servers$write, "deny")
    }
    live_reader_checks(soil, me, "7", jobs_soil = live_route(soil, "write"))
  }
})
