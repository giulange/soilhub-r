# Live write acceptance of soilhub (design 4.6, 7.3; acceptance criteria 10.6
# and 10.7). THIS SCRIPT WRITES TO THE API: run it on a development API
# unless the owner decided otherwise.
#
#   SOILHUB_API_URL=http://localhost:18080/api/v1 Rscript tests/live/write-acceptance.R
#   Rscript tests/live/write-acceptance.R --allow-production   # production, deliberately
#   Rscript tests/live/write-acceptance.R --fake               # dry run on local fake servers
#
# The API URL comes from SOILHUB_API_URL (else the option soilhub.api_url,
# else the production default). Against production the script refuses to
# run unless `--allow-production` is given.
#
# Sign in first with a PUBLISHER account (soil:publish and soil:admin), then,
# when asked, with a READER account (soil:read, no publish/admin) for the
# refusals of criterion 7.
#
# Everything it creates is named after the run stamp (UTC, yyyymmddHHMMSS):
#   variable      zz_soilhub_acceptance_<stamp>       (registered, immutable)
#   product       soilhub_acceptance                  (registered once, reused)
#   version       acceptance-<stamp>                  (immutable)
#   run           idempotency key soilhub-acceptance-run-<stamp> (completed)
#   values        about 10,060 values of the variable on WoSIS features
#   soil health   2 scores soil_health_physical_score on WoSIS horizons
#   export job    one whole-WoSIS CSV export, cancelled at once (job record)
#   source        provider zz_soilhub_acceptance, dataset
#                 zz_soilhub_acceptance_points, release r<stamp> (2 sites);
#                 only when the API is not production
# The API has no delete for these: they stay. The script deletes nothing.
# The list of what was created is written at the end of the log.

.live_dir <- local({
  file <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(file)) dirname(normalizePath(file[1])) else normalizePath(file.path("tests", "live"))
})
source(file.path(.live_dir, "common.R"))

usage <- c(
  "Usage: [SOILHUB_API_URL=...] Rscript tests/live/write-acceptance.R [options]",
  "  --allow-production     run against the production API (writes records there)",
  "  --ndjson-rows=N        rows of the NDJSON publication job (default 10050, more than 10,000)",
  "  --targets-country=A,B  countries of the WoSIS features used as targets of the job",
  "                         (default: the first of BRA; BRA,MEX; ... with enough features)",
  "  --poll=S, --timeout=S  polling of the jobs (default 5 s, 3600 s)",
  "  --skip-cancel          do not submit the export used for the job-cancel test",
  "  --skip-reader          do not ask for the reader sign-in (criterion 7)",
  "  --installed            use the installed soilhub even in the source tree",
  "  --fake, --dry-run      run on local fake servers (no login, no network)"
)
opts <- live_init(
  "write-acceptance", .live_dir,
  list(allow_production = FALSE, ndjson_rows = 10050, targets_country = "", poll = 5,
       timeout = 3600, skip_cancel = FALSE, skip_reader = FALSE),
  usage
)

vancouver <- c(-123.3, 49.0, -122.9, 49.4)
uuid_pattern <- "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

is_production <- function(url) grepl("^https?://soilhub\\.weatherprogapp\\.it(:[0-9]+)?(/|$)", url)

# Fake run only: the hand-made fixtures use short ids ("h-1"); the client
# checks UUIDs before publishing, so they are mapped to stable UUIDs.
as_uuid <- function(x) {
  if (!live$fake) return(x)
  h <- as.character(openssl::md5(as.character(x)))
  out <- sprintf("%s-%s-4%s-8%s-%s", substr(h, 1, 8), substr(h, 9, 12), substr(h, 14, 16), substr(h, 18, 20), substr(h, 21, 32))
  ifelse(grepl(uuid_pattern, x), x, out)
}

live_run(function() {
  stamp <- format(Sys.time(), "%Y%m%d%H%M%S", tz = "UTC")
  ids <- list(
    variable = paste0("zz_soilhub_acceptance_", stamp),
    product = "soilhub_acceptance",
    version = paste0("acceptance-", stamp),
    key = function(what) sprintf("soilhub-acceptance-%s-%s", what, stamp)
  )
  created <- character()
  remember <- function(text) created <<- c(created, text)

  api_url <- Sys.getenv("SOILHUB_API_URL")
  if (!nzchar(api_url)) api_url <- getOption("soilhub.api_url", production_api_url)
  if (live$fake) {
    live_fake_start(c("auth", "write", "thematic", "wide", "long", "export", "source"))
    api_url <- live$servers$write$url("/api/v1")
    # The fake GET /variables knows only its fixture: the client checks that
    # the variable of an NDJSON job is registered, so a fixture code is used.
    ids$variable <- "organic_carbon"
    live_log("FAKE: the variable code is `organic_carbon` (a variable of the fake catalogue).")
  }
  production <- is_production(api_url)
  allowed <- live_check("6.env", "the API to write to", function() {
    live_logf("      API %s (%s); run stamp %s", api_url, if (production) "PRODUCTION" else "not production", stamp)
    if (production && !isTRUE(opts$allow_production)) {
      return(v_fail(paste0(
        "refused: this is the production API. Set SOILHUB_API_URL to a development API ",
        "(e.g. http://localhost:18080/api/v1) or pass --allow-production deliberately"
      )))
    }
    v_pass(if (production) "production, allowed by --allow-production" else "not production", value = TRUE)
  })
  if (!isTRUE(allowed)) return(invisible(NULL))

  # --- Publisher -------------------------------------------------------------

  soil <- live_connect("publisher", api_url = api_url, jwt = "jwt-publisher.json", kind = "write")
  publisher <- live_check("7.p", "soil_whoami() correct for a publisher (soil:publish and soil:admin)", function() {
    me <- live_log_whoami(soil)
    if (!isTRUE(me$rights_known)) return(v_warn("rights not declared in the token: the API decides", value = me))
    v_expect(isTRUE(me$can[["publish"]]) && isTRUE(me$can[["admin"]]),
             sprintf("rights %s", paste(me$roles, collapse = ", ")), value = me)
  })
  can_write <- is.list(publisher) && (!isTRUE(publisher$rights_known) ||
                                        (isTRUE(publisher$can[["publish"]]) && isTRUE(publisher$can[["admin"]])))
  if (!can_write) live_log("The account cannot publish and administer: the write steps are skipped.")
  needs <- function(...) {
    missing <- !vapply(list(...), function(x) !is.null(x) && !isFALSE(x), TRUE)
    if (!can_write) return("the publisher account lacks soil:publish or soil:admin")
    if (any(missing)) return("needs an earlier step")
    NULL
  }

  inputs <- live_check("6.in", "inputs read from the hub: WoSIS around Vancouver (features, horizons, observations, release)", function() {
    wide <- soil_observations(live_route(soil, "wide"), datasets = "wosis_points", bbox = vancouver, progress = FALSE)
    long <- soil_observations(live_route(soil, "long"), datasets = "wosis_points", bbox = vancouver, layout = "long", progress = FALSE)
    features <- soil_features(live_route(soil, "long"), datasets = "wosis_points", bbox = vancouver,
                              with_geometry = "text", progress = FALSE)
    release_id <- unique(stats::na.omit(long$release_id))
    release_code <- unique(stats::na.omit(wide$release_code))
    live_logf("      wide %s", live_describe(wide))
    live_logf("      long %s", live_describe(long))
    live_logf("      %d features; release id %s, release code %s", nrow(features),
              paste(release_id, collapse = ","), paste(release_code, collapse = ","))
    v_expect(nrow(features) > 0L && nrow(wide) > 0L && length(release_id) >= 1L && length(release_code) >= 1L,
             sprintf("%d features, %d horizons, %d observations", nrow(features), nrow(wide), nrow(long)),
             value = list(wide = wide, long = long, features = features,
                          release_id = as.integer(release_id[1]), release_code = release_code[1]))
  })

  sync_targets <- live_check("6.1", "soil_resolve_targets() on the Vancouver features (source ids -> canonical ids)", function() {
    if (is.null(inputs)) return(v_skip("needs the inputs (6.in)"))
    f <- inputs$features
    keys <- data.frame(provider_code = f$provider_code, dataset_code = f$dataset,
                       release_code = inputs$release_code, target_level = "feature",
                       source_record_id = f$feature_key, stringsAsFactors = FALSE)
    res <- soil_resolve_targets(live_route(soil, "thematic"), keys, strict = FALSE)
    statuses <- table(res$status)
    live_logf("      %d keys: %s; request ids %s", nrow(keys),
              paste(sprintf("%s=%d", names(statuses), as.integer(statuses)), collapse = " "),
              paste(soil_metadata(res)$request_ids %||% "none", collapse = " "))
    resolved <- res[res$status == "resolved", , drop = FALSE]
    same <- sum(resolved$feature_id == f$feature_id[resolved$input_index + 1L], na.rm = TRUE)
    live_logf("      %d resolved feature id(s) equal to the feature ids read", same)
    if (!nrow(resolved)) {
      return(v_fail("no target resolved; the feature ids read are used for the publication instead",
                    value = utils::head(as_uuid(f$feature_id), 10)))
    }
    v_expect(nrow(resolved) == nrow(keys), sprintf("%d of %d resolved", nrow(resolved), nrow(keys)),
             value = utils::head(as_uuid(resolved$target_id), 10))
  })

  # --- Variable, product, version, run ------------------------------------------

  variable <- live_check("6.2", sprintf("soil_register_variable(): validate, register, idempotent replay (%s)", ids$variable), function() {
    if (!is.null(why <- needs())) return(v_skip(why))
    w <- live_route(soil, "write")
    args <- list(w, variable_code = ids$variable, name = paste("soilhub acceptance test variable", stamp),
                 domain_code = "soil", value_type = "numeric", measurement_kind_code = "derived",
                 allowed_target_levels = "feature",
                 description = "Synthetic test variable written by the soilhub live acceptance; not a soil property.",
                 idempotency_key = ids$key("variable"))
    check <- do.call(soil_register_variable, c(args, list(validate_only = TRUE)))
    live_logf("      validate: valid %s, %d error(s)", format(check$valid), if (is.data.frame(check$errors)) nrow(check$errors) else 0L)
    first <- do.call(soil_register_variable, args)
    remember(sprintf("variable %s (id %s)", first$variable_code, format(first$variable_id %||% NA)))
    live_logf("      register: variable_id %s, idempotent_replay %s", format(first$variable_id %||% NA), format(first$idempotent_replay))
    replay <- do.call(soil_register_variable, args)
    live_logf("      replay:   variable_id %s, idempotent_replay %s", format(replay$variable_id %||% NA), format(replay$idempotent_replay))
    v_expect(isTRUE(check$valid) && isFALSE(first$idempotent_replay) && isTRUE(replay$idempotent_replay),
             sprintf("valid %s, first replay %s, second replay %s", format(check$valid), format(first$idempotent_replay), format(replay$idempotent_replay)),
             value = TRUE)
  })

  health_declared <- FALSE
  version <- live_check("6.3", sprintf("soil_product() %s and soil_product_version() %s", ids$product, ids$version), function() {
    if (!is.null(why <- needs(variable))) return(v_skip(why))
    w <- live_route(soil, "write")
    product <- tryCatch(
      soil_product(w, ids$product, "soilhub acceptance (test product, not a soil product)", "feature",
                   description = "Registered by the live acceptance of the soilhub R package (tests/live/write-acceptance.R)."),
      soilhub_conflict_error = function(e) e
    )
    if (inherits(product, "soilhub_conflict_error")) {
      live_logf("      product: 409, it exists with another definition: %s", conditionMessage(product))
      return(v_fail("the product soilhub_acceptance exists with another name, description or target level"))
    }
    remember(sprintf("product %s (registered once, reused by later runs)", product$product_code))
    health <- tryCatch(soil_variables(w, code = "soil_health_physical_score"), error = function(e) NULL)
    health_declared <<- live$fake || (is.data.frame(health) && "soil_health_physical_score" %in% health$variable_code)
    live_logf("      product %s; soil_health_physical_score registered on this API: %s", product$product_code, health_declared)
    variables <- list(list(variable_code = ids$variable, target_levels = "feature"))
    if (health_declared) {
      variables[[2]] <- list(variable_code = "soil_health_physical_score", target_levels = "horizon")
    }
    checksum <- as.character(openssl::sha256(paste("soilhub live acceptance", stamp)))
    v <- soil_product_version(w, ids$product, ids$version, algorithm_checksum = checksum, variables = variables,
                              configuration = list(purpose = "soilhub 0.2.0 live acceptance", run_stamp = stamp))
    remember(sprintf("product version %s (product_version_id %s)", v$version_code, format(v$product_version_id)))
    live_logf("      version %s: product_version_id %s, declared %s", v$version_code, format(v$product_version_id),
              paste(v$declared_variables$variable_code, collapse = ", "))
    v_expect(!is.null(v$product_version_id), sprintf("product_version_id %s", format(v$product_version_id)), value = v)
  })

  run <- live_check("6.4", "soil_run_open()", function() {
    if (!is.null(why <- needs(version, inputs))) return(v_skip(why))
    r <- soil_run_open(live_route(soil, "write"), version$product_version_id, idempotency_key = ids$key("run"),
                       input_release_ids = inputs$release_id,
                       parameters = list(purpose = "soilhub live acceptance", run_stamp = stamp))
    remember(sprintf("run %s (idempotency key %s)", format(r$run_id), ids$key("run")))
    live_logf("      run_id %s, status %s, input releases %s", format(r$run_id), r$status, paste(unlist(r$input_release_ids), collapse = ","))
    v_expect(identical(r$status, "running"), sprintf("run %s %s", format(r$run_id), r$status), value = r)
  })

  value_rows <- function(target_ids, offset) {
    values <- data.frame(
      variable_code = ids$variable, target_level = "feature", target_id = target_ids,
      value = round(offset + seq_along(target_ids) / 1000, 3), release_id = inputs$release_id,
      stringsAsFactors = FALSE
    )
    values$lineage <- lapply(seq_along(target_ids), function(i) list(releases = list(list(id = inputs$release_id, role = "input"))))
    values
  }
  log_receipt <- function(p) {
    live_logf("      %s: status %s, sent %s, received %s, published %s, publication %s%s%s",
              p$transport %||% "?", format(p$status %||% NA), format(p$record_count %||% NA),
              format(p$received_count %||% NA), format(p$published_count %||% NA), format(p$publication_id %||% NA),
              if (!is.null(p$job_id)) sprintf(", job %s", p$job_id) else "",
              if (!is.null(p$checksum_sha256)) sprintf(", %s bytes, sha256 %s", format(p$byte_size %||% NA), p$checksum_sha256) else "")
  }

  published <- list(sync = 0, ndjson = 0, health = 0)

  live_check("6.5", "soil_publish_values() synchronous (at most 10 rows, Vancouver features)", function() {
    if (!is.null(why <- needs(run, sync_targets))) return(v_skip(why))
    values <- value_rows(sync_targets, 1)
    p <- soil_publish_values(live_route(soil, "write"), run$run_id, values, idempotency_key = ids$key("values-sync"),
                             transport = "sync", progress = FALSE)
    log_receipt(p)
    published$sync <<- p$published_count %||% 0
    remember(sprintf("%s values (synchronous) of %s on WoSIS features", format(p$published_count), ids$variable))
    v_expect(identical(as.numeric(p$published_count), as.numeric(nrow(values))) && nrow(values) <= 10L,
             sprintf("%s of %d published", format(p$published_count), nrow(values)))
  })

  # Targets of the NDJSON job: more than 10,000 WoSIS features (a value per
  # target: the API refuses two values of one variable on one target in a
  # run), found by country, sized first with soil_summary() so that the
  # feature read stays below the synchronous limit, then resolved from their
  # source ids. Fake run: synthetic source ids (the fixtures hold 3 features).
  job_targets <- live_check("6.6t", sprintf("%g targets for the NDJSON job, resolved with soil_resolve_targets()", opts$ndjson_rows), function() {
    if (!is.null(why <- needs(inputs))) return(v_skip(why))
    need <- opts$ndjson_rows
    if (need <= 10000) return(v_fail("--ndjson-rows must be more than 10,000"))
    if (live$fake) {
      keys <- data.frame(provider_code = "isric", dataset_code = "wosis_points", release_code = inputs$release_code,
                         target_level = "feature", source_record_id = sprintf("fake-%05d", seq_len(need)),
                         stringsAsFactors = FALSE)
      live_log("      FAKE: synthetic source ids")
    } else {
      candidates <- if (nzchar(opts$targets_country)) list(strsplit(opts$targets_country, ",", fixed = TRUE)[[1]]) else
        list("BRA", c("BRA", "MEX"), c("BRA", "MEX", "ARG", "COL"),
             c("BRA", "MEX", "ARG", "COL", "PER", "CHL", "ECU", "VEN", "URY", "CUB"))
      limit <- soil_capabilities(soil)$limits$max_sync_observations %||% 1e6
      chosen <- NULL
      for (countries in candidates) {
        s <- soil_summary(soil, datasets = "wosis_points", country = countries)
        live_logf("      summary %s: %s features, %s observations", paste(countries, collapse = ","),
                  format(s$feature_count), format(s$observation_count))
        if (isTRUE(s$feature_count >= need + 50) && isTRUE(s$observation_count < limit)) {
          chosen <- countries
          break
        }
      }
      if (is.null(chosen)) return(v_fail("no candidate selection has enough features below the synchronous limit: use --targets-country"))
      f <- soil_features(soil, datasets = "wosis_points", country = chosen, with_geometry = "text",
                         max_rows = need + 300, progress = FALSE)
      f <- f[!f$feature_id %in% inputs$features$feature_id, , drop = FALSE]
      live_logf("      %d features read in %s (%d page(s))", nrow(f), paste(chosen, collapse = ","), soil_metadata(f)$pages)
      keys <- data.frame(provider_code = f$provider_code, dataset_code = f$dataset, release_code = inputs$release_code,
                         target_level = "feature", source_record_id = f$feature_key, stringsAsFactors = FALSE)
    }
    res <- soil_resolve_targets(live_route(soil, "thematic"), keys, strict = FALSE)
    statuses <- table(res$status)
    live_logf("      resolution: %s (%d request(s))", paste(sprintf("%s=%d", names(statuses), as.integer(statuses)), collapse = " "),
              length(soil_metadata(res)$request_ids %||% character()))
    target_ids <- unique(as_uuid(res$target_id[res$status == "resolved"]))
    target_ids <- setdiff(target_ids, sync_targets)
    v_expect(length(target_ids) >= need, sprintf("%d distinct resolved targets (need %g)", length(target_ids), need),
             value = utils::head(target_ids, need))
  })

  live_check("6.6", sprintf("soil_publish_values() NDJSON job (%g rows)", opts$ndjson_rows), function() {
    if (!is.null(why <- needs(run, job_targets))) return(v_skip(why))
    values <- value_rows(job_targets, 100)
    started <- Sys.time()
    p <- soil_publish_values(live_route(soil, "write"), run$run_id, values, idempotency_key = ids$key("values-ndjson"),
                             transport = "auto", timeout = opts$timeout, poll = opts$poll, progress = FALSE)
    log_receipt(p)
    live_logf("      job round trip %.0f s", as.numeric(difftime(Sys.time(), started, units = "secs")))
    published$ndjson <<- p$published_count %||% 0
    remember(sprintf("%s values (NDJSON job %s) of %s on WoSIS features", format(p$published_count), format(p$job_id %||% NA), ids$variable))
    v_expect(identical(p$transport, "ndjson") && identical(as.numeric(p$published_count), as.numeric(nrow(values))),
             sprintf("transport %s, %s of %d published", p$transport, format(p$published_count), nrow(values)))
  })

  live_check("6.7", "soil_publish_health() synchronous (2 scores on Vancouver horizons)", function() {
    if (!is.null(why <- needs(run, inputs))) return(v_skip(why))
    if (!health_declared) return(v_skip("soil_health_physical_score is not registered on this API"))
    long <- inputs$long
    horizons <- utils::head(unique(long$horizon_id[!is.na(long$observation_id)]), 2)
    scores <- data.frame(
      horizon_id = as_uuid(horizons), release_id = inputs$release_id, category_code = "physical",
      score_status = "scored", score = c(72.5, 64)[seq_along(horizons)], score_class = "good",
      source_support = "observed_point_profile", stringsAsFactors = FALSE
    )
    scores$observation_inputs <- lapply(horizons, function(h) {
      obs <- utils::head(long$observation_id[long$horizon_id == h & !is.na(long$observation_id)], 2)
      lapply(as_uuid(obs), function(o) list(observation_id = o, input_role = "acceptance_input"))
    })
    scores$diagnostics <- lapply(horizons, function(h) list(note = "synthetic score of the soilhub live acceptance"))
    p <- soil_publish_health(live_route(soil, "write"), run$run_id, scores, idempotency_key = ids$key("health"),
                             transport = "sync", progress = FALSE)
    log_receipt(p)
    published$health <<- p$published_count %||% 0
    remember(sprintf("%s soil-health scores (soil_health_physical_score) on WoSIS horizons", format(p$published_count)))
    v_expect(identical(as.numeric(p$published_count), as.numeric(nrow(scores))),
             sprintf("%s of %d published, score_count %s", format(p$published_count), nrow(scores), format(p$score_count %||% NA)))
  })

  completed <- live_check("6.8", "soil_run_complete()", function() {
    if (!is.null(why <- needs(run))) return(v_skip(why))
    r <- soil_run_complete(live_route(soil, "write"), run$run_id,
                           diagnostics = list(note = "soilhub live acceptance", run_stamp = stamp))
    live_logf("      run %s: status %s, completed at %s", format(r$run_id), r$status, format(r$completed_at %||% NA))
    v_expect(identical(r$status, "completed"), sprintf("status %s", r$status), value = TRUE)
  })

  live_check("6.9", "re-read with soil_values() and the lineage", function() {
    if (!is.null(why <- needs(run, completed))) return(v_skip(why))
    th <- live_route(soil, "thematic")
    v <- soil_values(th, run_ids = run$run_id, include_lineage = TRUE, progress = FALSE)
    s <- soil_values_summary(th, run_ids = run$run_id)
    expected <- published$sync + published$ndjson + published$health
    mine <- v[v$variable_code == ids$variable, , drop = FALSE]
    with_lineage <- if (nrow(mine) && !is.null(mine$release_inputs)) sum(lengths(mine$release_inputs) > 0L) else 0L
    live_logf("      %d values read (%s pages, request ids %s); summary total %s; expected %s; %d of %d values of %s carry their release lineage",
              nrow(v), format(soil_metadata(v)$pages %||% NA), paste(utils::head(soil_metadata(v)$request_ids, 3), collapse = " "),
              format(s$total_value_count %||% NA), format(expected), with_lineage, nrow(mine), ids$variable)
    if (nrow(v)) live_log_table(utils::head(v[, intersect(c("variable_code", "target_level", "value", "value_status", "run_id"), names(v)), drop = FALSE], 3))
    v_expect(nrow(v) == expected && nrow(mine) > 0L && with_lineage == nrow(mine),
             sprintf("%d values read, %s expected, lineage on %d of %d", nrow(v), format(expected), with_lineage, nrow(mine)))
  })

  # Job cancel on a queued job: a whole-WoSIS CSV export (about 6 million
  # observations, 9 minutes of work) submitted without waiting and cancelled
  # at once. An export writes no soil data, unlike a publication job that
  # might complete before the cancel arrives. Best effort: if the job ended
  # first the verdict is WARN.
  live_check("6.10", "soil_job_cancel() on a queued job (a large export, cancelled at once)", function() {
    if (isTRUE(opts$skip_cancel)) return(v_skip("--skip-cancel"))
    if (!is.null(why <- needs())) return(v_skip(why))
    ex <- live_route(soil, "export")
    x <- soil_export(ex, datasets = "wosis_points", format = "csv", wait = FALSE, progress = FALSE)
    live_logf("      export %s submitted: status %s, %s observations", x$job_id, x$status, format(x$observation_count %||% NA))
    job <- tryCatch(soil_job_cancel(ex, x$job_id), soilhub_conflict_error = function(e) e)
    remember(sprintf("export job %s (whole wosis_points, csv), cancel requested", x$job_id))
    if (inherits(job, "soilhub_conflict_error")) {
      return(v_warn(sprintf("the export had ended before the cancel: %s", conditionMessage(job))))
    }
    live_logf("      cancel: status %s, cancel_requested %s", job$status, format(job$cancel_requested))
    final <- tryCatch(soil_job(ex, x$job_id), error = function(e) e)
    if (inherits(final, "error")) {
      live_logf("      soil_job(): %s", conditionMessage(final))
    } else {
      live_logf("      soil_job(): status %s, progress %s%%", final$status, format(final$progress_percent %||% NA))
    }
    if (identical(job$status, "cancelled") || isTRUE(job$cancel_requested)) {
      v_pass(sprintf("status %s, cancel_requested %s", job$status, format(job$cancel_requested)))
    } else if (job$status %in% c("completed", "failed")) {
      v_warn(sprintf("the export had ended (%s) before the cancel", job$status))
    } else {
      v_fail(sprintf("status %s after the cancel", job$status))
    }
  })

  source_release <- live_check("6.11", "source-ingest round trip of a tiny synthetic bundle (not on production)", function() {
    if (production) return(v_skip("production API: the source-ingest round trip runs on a development API only"))
    if (!is.null(why <- needs())) return(v_skip(why))
    if (!requireNamespace("sf", quietly = TRUE)) return(v_skip("needs the package sf"))
    manifest <- list(
      provider_code = "zz_soilhub_acceptance", provider_name = "soilhub acceptance (test provider)",
      dataset_code = "zz_soilhub_acceptance_points", dataset_name = "soilhub acceptance points (synthetic)",
      release_code = paste0("r", stamp), support_type = "observed_point_profile", default_geometry_kind = "POINT",
      licence_text = "CC0 1.0 (synthetic test records)",
      citation_text = "Synthetic records written by the soilhub live acceptance (tests/live/write-acceptance.R)"
    )
    sites <- sf::st_as_sf(data.frame(source_record_id = c("ZZ1", "ZZ2"), x = c(14.35, 14.36), y = c(40.81, 40.82)),
                          coords = c("x", "y"), crs = 4326)
    profiles <- data.frame(source_record_id = c("ZZ1", "ZZ2"), feature_source_id = c("ZZ1", "ZZ2"))
    components <- data.frame(source_record_id = c("ZZ1-c", "ZZ2-c"), profile_source_id = c("ZZ1", "ZZ2"),
                             component_rank = 1L, proportion_percent = 100)
    horizons <- data.frame(source_record_id = c("ZZ1-1", "ZZ2-1"), component_source_id = c("ZZ1-c", "ZZ2-c"),
                           top_depth_cm = 0, bottom_depth_cm = 30, horizon_name = "Ap")
    observations <- data.frame(source_record_id = c("ZZ1-1-orgc", "ZZ2-1-orgc"), horizon_source_id = c("ZZ1-1", "ZZ2-1"),
                               property_code = "orgc", value = c(12.1, 8.4), unit = "g/kg", status = "observed")
    ingest <- soil_publish_source(live_route(soil, "source"), manifest, sites, profiles, components, horizons, observations,
                                  idempotency_key = ids$key("source"), wait = TRUE, timeout = opts$timeout,
                                  poll = opts$poll, progress = FALSE)
    remember(sprintf("source release %s/%s/%s (release_id %s, job %s)", manifest$provider_code, manifest$dataset_code,
                     manifest$release_code, format(ingest$release_id %||% NA), ingest$job_id))
    live_logf("      job %s: status %s, sent %s, published %s, release_id %s, receipt %s, unmapped %s",
              ingest$job_id, ingest$status, format(ingest$record_count), format(ingest$published_count %||% NA),
              format(ingest$release_id %||% NA), format(ingest$receipt_id %||% NA),
              paste(unlist(ingest$unmapped_property_codes), collapse = ",") %||% "")
    v_expect(identical(ingest$status, "completed") && isTRUE(ingest$published_count > 0),
             sprintf("status %s, %s records published", ingest$status, format(ingest$published_count %||% NA)),
             value = manifest$dataset_code)
  })

  live_check("6.11r", "the ingested release read back with soil_features()", function() {
    if (is.null(source_release)) return(v_skip("needs the source ingest (6.11)"))
    f <- soil_features(live_route(soil, "long"), datasets = source_release, with_geometry = "text", progress = FALSE)
    live_logf("      %d features: %s", nrow(f), paste(f$feature_key, collapse = ", "))
    v_expect(nrow(f) == 2L, sprintf("%d features", nrow(f)))
  })

  # --- Reader (criterion 7) ------------------------------------------------------

  if (isTRUE(opts$skip_reader)) {
    live_log("--skip-reader: the reader checks are not run.")
  } else {
    live_prompt(paste0(
      "next sign-in is for the READER account. In the browser, sign out of Keycloak first ",
      "(or use a private window), so that the code is approved by the reader, not by the publisher."
    ))
    reader <- live_connect("reader", api_url = api_url)
    me <- live_check("7.r", "soil_whoami() correct for a reader (soil:read, no soil:publish, no soil:admin)", function() {
      me <- live_log_whoami(reader)
      if (!isTRUE(me$rights_known)) return(v_warn("rights not declared in the token: the API decides", value = me))
      v_expect(isTRUE(me$can[["read"]]) && !isTRUE(me$can[["publish"]]) && !isTRUE(me$can[["admin"]]),
               sprintf("rights %s", paste(me$roles, collapse = ", ")), value = me)
    })
    if (is.list(me)) {
      if (live$fake) live$fake_env$fake_control(live$servers$write, "deny")
      live_reader_checks(reader, me, "7.r", jobs_soil = live_route(reader, "write"))
    }
  }

  live_log("")
  live_log(sprintf("Created on %s by this run (stamp %s); nothing was deleted:", api_url, stamp))
  for (item in if (length(created)) created else "nothing") live_logf("  - %s", item)
})
