# Writes (design 4.6): variable registration, products, versions, runs,
# value and soil-health publication against the fake write API; rights
# pre-check (1.3), conflicts and validation errors (2.5), uploads never
# retried (2.4).

api <- fake_write_api()

# ---------------------------------------------------------------------------
# Rights

test_that("a reader is stopped locally before any request", {
  fake_control(api, "reset")
  reader <- write_session(api, "jwt-reader.json")
  calls <- list(
    soil_register_variable = function() soil_register_variable(
      reader, "x", "X", "soil", "numeric", "derived", "horizon", idempotency_key = "k"),
    soil_product = function() soil_product(reader, "p", "P", "horizon"),
    soil_product_version = function() soil_product_version(reader, "p", "v1", strrep("a", 64), data.frame()),
    soil_run_open = function() soil_run_open(reader, 7, "k"),
    soil_run_complete = function() soil_run_complete(reader, 42),
    soil_run_fail = function() soil_run_fail(reader, 42),
    soil_publish_values = function() soil_publish_values(reader, 42, value_records(1), "k"),
    soil_publish_health = function() soil_publish_health(reader, 42, health_records(1), "k")
  )
  for (name in names(calls)) {
    err <- tryCatch(calls[[name]](), soilhub_permission_error = function(e) e)
    expect_s3_class(err, "soilhub_permission_error")
    needed <- if (name %in% c("soil_register_variable", "soil_product", "soil_product_version")) "soil:admin" else "soil:publish"
    expect_identical(err$required_right, needed)
    expect_identical(err$required_right, names(Filter(function(f) name %in% f, .rights)))
    expect_match(conditionMessage(err), sprintf("`%s()` needs the right `%s`; your session has `soil:read`, `soil:summary`.", name, needed), fixed = TRUE)
  }
  expect_length(fake_log(api), 0L)
})

test_that("without declared rights the request is sent and a 403 is mapped", {
  fake_control(api, "reset")
  fake_control(api, "deny")
  undeclared <- write_session(api, "jwt-noroles.json")
  err <- tryCatch(soil_product(undeclared, "p", "P", "horizon"), soilhub_permission_error = function(e) e)
  expect_identical(err$status, 403L)
  expect_identical(err$required_right, "soil:admin")
  expect_match(conditionMessage(err), "Permission denied: Missing required scope (this request needs the right `soil:admin`)", fixed = TRUE)

  err <- tryCatch(soil_publish_values(undeclared, 42, value_records(1), "k"),
                  soilhub_permission_error = function(e) e)
  expect_identical(err$required_right, "soil:publish")
  expect_identical(err$endpoint, "/publications/42/validate")

  # the upload too: one request, no retry
  err <- tryCatch(soil_publish_values(undeclared, 42, value_records(1), "k", validate = FALSE, transport = "ndjson"),
                  soilhub_permission_error = function(e) e)
  expect_identical(err$endpoint, "/publications/42/jobs")
  expect_identical(fake_log(api), c("POST /api/v1/products", "POST /api/v1/publications/42/validate",
                                    "POST /api/v1/publications/42/jobs"))

  # a publisher whose token was refused by the API (403 despite the role)
  publisher <- write_session(api)
  err <- tryCatch(soil_run_open(publisher, 7, "k"), soilhub_permission_error = function(e) e)
  expect_identical(err$rights, c("soil:admin", "soil:publish", "soil:read", "soil:summary"))
  expect_match(conditionMessage(err), "your session has `soil:admin`, `soil:publish`", fixed = TRUE)
  fake_control(api, "reset")
})

# ---------------------------------------------------------------------------
# Variables

test_that("soil_register_variable() validates then registers", {
  fake_control(api, "reset")
  soil <- write_session(api)
  v <- soil_register_variable(
    soil, "soil_health_physical_score", "Physical score", "soil", "numeric", "derived",
    c("horizon", "profile", "horizon"), description = "Fuzzy score", idempotency_key = "var-1"
  )
  expect_identical(v$variable_id, 501)
  expect_identical(v$allowed_target_levels, c("horizon", "profile"))
  expect_false(v$idempotent_replay)
  expect_identical(fake_log(api), c("POST /api/v1/variables/validate", "POST /api/v1/variables"))

  # a single target level is sent as an array
  one <- soil_register_variable(soil, "one_level", "One", "soil", "text", "derived", "horizon",
                                idempotency_key = "var-2")
  expect_identical(one$allowed_target_levels, "horizon")
  expect_identical(one$value_type, "text")

  soil$verbose <- 1
  expect_message(
    replay <- soil_register_variable(soil, "x", "X", "soil", "numeric", "derived", "horizon",
                                     idempotency_key = "replay"),
    "idempotent replay", fixed = TRUE
  )
  expect_true(replay$idempotent_replay)
})

test_that("an invalid definition, validate_only and conflicts", {
  fake_control(api, "reset")
  soil <- write_session(api)
  err <- tryCatch(
    soil_register_variable(soil, "x", "X", "unknown_domain", "numeric", "derived", "horizon",
                           idempotency_key = "k"),
    soilhub_validation_error = function(e) e
  )
  expect_s3_class(err, "soilhub_api_error")
  expect_identical(err$errors$code, "unknown_domain")
  expect_match(conditionMessage(err), "- code unknown_domain, message unknown_domain", fixed = TRUE)
  expect_identical(fake_log(api), "POST /api/v1/variables/validate")

  check <- soil_register_variable(soil, "x", "X", "soil", "numeric", "derived", "horizon",
                                  idempotency_key = "k", validate_only = TRUE)
  expect_true(check$valid)
  expect_identical(nrow(check$errors), 0L)
  expect_identical(fake_log(api), rep("POST /api/v1/variables/validate", 2))

  taken <- tryCatch(
    soil_register_variable(soil, "taken", "X", "soil", "numeric", "derived", "horizon", idempotency_key = "k"),
    soilhub_conflict_error = function(e) e
  )
  expect_identical(taken$status, 409L)
  expect_match(conditionMessage(taken), "already exists with a different definition", fixed = TRUE)
  expect_match(conditionMessage(taken), "a registered variable is never redefined", fixed = TRUE)
  expect_match(taken$advice, "new idempotency key", fixed = TRUE)

  race <- tryCatch(
    soil_register_variable(soil, "race", "X", "soil", "numeric", "derived", "horizon", idempotency_key = "k"),
    soilhub_conflict_error = function(e) e
  )
  expect_identical(race$errors$code, "unknown_measurement_kind")
})

test_that("variable arguments and the capability are checked locally", {
  fake_control(api, "reset")
  soil <- write_session(api)
  reg <- function(...) {
    args <- utils::modifyList(list(soil = soil, variable_code = "x", name = "X", domain_code = "soil",
                                   value_type = "numeric", measurement_kind_code = "derived",
                                   allowed_target_levels = "horizon", idempotency_key = "k"), list(...))
    do.call(soil_register_variable, args)
  }
  expect_error(reg(variable_code = "Bad Code"), class = "soilhub_argument_error")
  expect_error(reg(value_type = "float"), class = "soilhub_argument_error")
  expect_error(reg(allowed_target_levels = "polygon"), class = "soilhub_argument_error")
  expect_error(reg(idempotency_key = strrep("k", 201)), class = "soilhub_argument_error")
  expect_error(reg(name = ""), class = "soilhub_argument_error")
  expect_length(fake_log(api), 0L)

  soil$state$capabilities <- capabilities_with(variable_registration = FALSE)
  err <- tryCatch(reg(), soilhub_capability_error = function(e) e)
  expect_identical(err$capability, "variable_registration")
  expect_length(fake_log(api), 0L)
})

# ---------------------------------------------------------------------------
# Products, versions, runs

test_that("products and versions are registered; conflicts explain the way out", {
  soil <- write_session(api)
  p <- soil_product(soil, "soil_health_fuzzy", "Soil health", "horizon")
  expect_identical(p$product_code, "soil_health_fuzzy")
  expect_true(is.na(p$description))
  err <- tryCatch(soil_product(soil, "taken", "X", "horizon"), soilhub_conflict_error = function(e) e)
  expect_match(conditionMessage(err), "The API cannot show it", fixed = TRUE)
  expect_error(soil_product(soil, "p", "P", "polygon"), class = "soilhub_argument_error")

  checksum <- strrep("ab", 32)
  v <- soil_product_version(
    soil, "soil_health_fuzzy", "v1.0.0", checksum,
    variables = data.frame(variable_code = c("soil_health_physical_score", "soil_health_soc_score"),
                           target_levels = "horizon"),
    configuration = list(rule_base = "physical-v1")
  )
  expect_identical(v$product_version_id, 7)
  expect_identical(v$configuration, list(rule_base = "physical-v1"))
  expect_s3_class(v$declared_variables, "data.frame")
  expect_identical(v$declared_variables$target_levels[[1]], "horizon")
  expect_s3_class(v$created_at, "POSIXct")

  # list of records, list column of levels, empty configuration sent as {}
  listed <- soil_product_version(soil, "soil_health_fuzzy", "v1.0.1", checksum,
                                 variables = list(list(variable_code = "a", target_levels = c("profile", "horizon"))))
  expect_identical(listed$declared_variables$target_levels[[1]], c("horizon", "profile"))
  expect_length(listed$configuration, 0L)

  expect_error(soil_product_version(soil, "p", "v", "ABC", data.frame(variable_code = "a", target_levels = "horizon")),
               class = "soilhub_argument_error")
  expect_error(soil_product_version(soil, "p", "v", checksum, data.frame(code = "a")),
               class = "soilhub_argument_error")
  expect_error(soil_product_version(soil, "nope", "v", checksum, data.frame(variable_code = "a", target_levels = "horizon")),
               class = "soilhub_not_found_error")
  err <- tryCatch(soil_product_version(soil, "p", "taken", checksum, data.frame(variable_code = "a", target_levels = "horizon")),
                  soilhub_conflict_error = function(e) e)
  expect_match(conditionMessage(err), "versions are immutable", fixed = TRUE)
})

test_that("runs are opened, completed and failed", {
  soil <- write_session(api)
  run <- soil_run_open(soil, 7, "run-1", input_release_ids = 12, parameters = list(country = "IND"))
  expect_identical(run$run_id, 42)
  expect_identical(run$status, "running")
  expect_identical(run$input_release_ids, 12L)
  expect_identical(run$parameters, list(country = "IND"))
  expect_true(is.na(run$completed_at))
  expect_error(soil_run_open(soil, 0, "k"), class = "soilhub_argument_error")
  expect_error(soil_run_open(soil, 7, "k", input_release_ids = "x"), class = "soilhub_argument_error")
  expect_error(soil_run_open(soil, 7, "k", parameters = list(1)), class = "soilhub_argument_error")
  err <- tryCatch(soil_run_open(soil, 7, "taken"), soilhub_conflict_error = function(e) e)
  expect_match(conditionMessage(err), "use a new key for a new execution", fixed = TRUE)

  done <- soil_run_complete(soil, 42, diagnostics = list(checked = TRUE))
  expect_identical(done$status, "completed")
  expect_identical(done$diagnostics, list(checked = TRUE))
  expect_s3_class(done$completed_at, "POSIXct")
  expect_identical(soil_run_fail(soil, 42)$status, "failed")
  err <- tryCatch(soil_run_fail(soil, 99), soilhub_conflict_error = function(e) e)
  expect_match(conditionMessage(err), "run cannot transition from completed to failed", fixed = TRUE)
  expect_match(conditionMessage(err), "A closed run cannot change state", fixed = TRUE)
})

# ---------------------------------------------------------------------------
# Values

test_that("synchronous values: local check, server validation, publication", {
  fake_control(api, "reset")
  soil <- write_session(api)
  out <- soil_publish_values(soil, 42, value_records(3), "pub-1")
  expect_s3_class(out, "soil_publication")
  expect_identical(out$transport, "sync")
  expect_identical(out$record_count, 3L)
  expect_identical(out$published_count, 3)
  expect_true(out$validation$valid)
  expect_match(out$publication_id, "^0{8}-")
  expect_identical(fake_log(api), c("POST /api/v1/publications/42/validate", "POST /api/v1/publications/42/values"))
  expect_output(print(out), "Records:   sent 3, received 3, published 3", fixed = TRUE)

  fake_control(api, "reset")
  soil_publish_values(soil, 42, value_records(1), "pub-2", validate = FALSE)
  expect_identical(fake_log(api), "POST /api/v1/publications/42/values")
})

test_that("records failing the local checks are listed and nothing is sent", {
  fake_control(api, "reset")
  soil <- write_session(api)
  bad <- value_records(4)
  bad$target_id[2] <- "not-a-uuid"
  bad$value[3] <- NA
  bad$depth_top_cm[4] <- 50
  bad$lineage[[4]] <- list(observations = list())
  err <- tryCatch(soil_publish_values(soil, 42, bad, "k"), soilhub_argument_error = function(e) e)
  expect_identical(err$argument, "values")
  expect_identical(err$errors$record, 2:4)
  expect_identical(err$errors$errors, c("target_id_not_uuid", "published_value_missing",
                                        "lineage_required, invalid_depth_interval"))
  expect_match(conditionMessage(err), "3 of the 4 record(s) of `values` fail the local checks", fixed = TRUE)

  status <- value_records(1)
  status$value_status <- "insufficient_data"
  err <- tryCatch(soil_publish_values(soil, 42, status, "k"), soilhub_argument_error = function(e) e)
  expect_identical(err$errors$errors, "non_published_status_must_not_have_value")

  missing <- list(list(variable_code = "x", target_level = "pedon", value = 1))
  err <- tryCatch(soil_publish_values(soil, 42, missing, "k"), soilhub_argument_error = function(e) e)
  expect_identical(err$errors$errors, "target_id_missing, invalid_target_level, lineage_missing")
  expect_error(soil_publish_values(soil, 42, value_records(1)[0, ], "k"), class = "soilhub_argument_error")
  expect_error(soil_publish_values(soil, 42, value_records(1), "k", transport = "parquet"))
  expect_length(fake_log(api), 0L)
})

test_that("server validation and publication errors keep the rejected rows", {
  fake_control(api, "reset")
  soil <- write_session(api)
  values <- value_records(3)
  values$variable_code[2] <- "undeclared"
  err <- tryCatch(soil_publish_values(soil, 42, values, "k"), soilhub_validation_error = function(e) e)
  expect_identical(err$errors$row, 1L)
  expect_identical(err$errors$record, 2L)
  expect_identical(err$errors$errors, "unknown_or_undeclared_variable")
  expect_match(conditionMessage(err), "nothing was published", fixed = TRUE)
  expect_identical(fake_log(api), "POST /api/v1/publications/42/validate")

  err <- tryCatch(soil_publish_values(soil, 77, value_records(1), "k", validate = FALSE),
                  soilhub_validation_error = function(e) e)
  expect_identical(err$status, 422L)
  expect_identical(err$errors$errors, "target_not_found")
  expect_match(conditionMessage(err), "publication validation failed", fixed = TRUE)

  err <- tryCatch(soil_publish_values(soil, 42, value_records(1), "conflict"),
                  soilhub_conflict_error = function(e) e)
  expect_match(conditionMessage(err), "a retry must send the same records with the same key", fixed = TRUE)
})

test_that("an idempotent replay is reported and receipts are reconciled", {
  soil <- write_session(api)
  soil$verbose <- 1
  expect_message(out <- soil_publish_values(soil, 42, value_records(2), "replay"), "idempotent replay", fixed = TRUE)
  expect_true(out$idempotent_replay)
  soil$verbose <- 0
  expect_warning(
    short <- soil_publish_values(soil, 42, value_records(3), "short"),
    "published 2", class = "soilhub_reconciliation_warning"
  )
  expect_identical(short$published_count, 2)
})

test_that("the transport follows the size; a sync batch holds at most 10,000 records", {
  expect_identical(choose_transport("auto", 10000L), "sync")
  expect_identical(choose_transport("auto", 10001L), "ndjson")
  expect_identical(choose_transport("ndjson", 5L), "ndjson")
  expect_error(choose_transport("sync", 10001L), class = "soilhub_argument_error")
})

test_that("an NDJSON job uploads the records with their checksum and waits", {
  local_fake_clock()
  fake_control(api, "reset")
  soil <- write_session(api)
  values <- value_records(3)
  out <- soil_publish_values(soil, 42, values, "bulk-1", transport = "ndjson", poll = 1, progress = FALSE)
  expect_identical(out$transport, "ndjson")
  expect_identical(out$status, "completed")
  expect_identical(out$published_count, 3)
  expect_identical(out$received_count, 3)
  expect_s3_class(out$job, "soil_job")
  expect_match(out$publication_id, "^0{8}-")

  upload <- fake_upload(api, out$job_id)
  expect_match(upload$content_type, "^multipart/form-data")
  sent <- strsplit(upload$text, "\n", fixed = TRUE)[[1]]
  expect_identical(sent, ndjson_lines(as_records(values)))
  expect_identical(out$checksum_sha256, as.vector(as.character(openssl::sha256(charToRaw(upload$text)))))
  expect_equal(out$byte_size, nchar(upload$text, type = "bytes"))

  log <- fake_log(api)
  expect_identical(log[1:2], c("GET /api/v1/variables", "POST /api/v1/publications/42/jobs"))
  expect_true(all(log[-(1:2)] == paste0("GET /api/v1/jobs/", out$job_id)))
  query <- httr2::resp_body_json(httr2::req_perform(httr2::request(api$url("/test/log"))))$log[[2]]$query
  expect_match(query, "idempotency_key=bulk-1&input_format=ndjson&expected_checksum=", fixed = TRUE)
  expect_match(query, out$checksum_sha256, fixed = TRUE)
  # the temporary file is removed
  expect_length(list.files(tempdir(), pattern = "^soilhub-.*\\.ndjson$"), 0L)
})

test_that("an upload is never retried and the way out is the same key", {
  fake_control(api, "reset")
  soil <- write_session(api)
  err <- tryCatch(
    soil_publish_values(soil, 42, value_records(2), "flaky", validate = FALSE, transport = "ndjson"),
    soilhub_unavailable_error = function(e) e
  )
  expect_identical(err$status, 503L)
  expect_identical(err$attempts, 1L)
  expect_identical(fake_log(api), "POST /api/v1/publications/42/jobs")

  err <- tryCatch(
    soil_publish_values(soil, 42, value_records(2), "conflict", validate = FALSE, transport = "ndjson"),
    soilhub_conflict_error = function(e) e
  )
  expect_match(conditionMessage(err), "idempotency key was already used with a different file", fixed = TRUE)
})

test_that("unregistered variables stop an upload before it starts", {
  fake_control(api, "reset")
  soil <- write_session(api)
  err <- tryCatch(
    soil_publish_values(soil, 42, value_records(2, "my_index"), "k", transport = "ndjson"),
    soilhub_argument_error = function(e) e
  )
  expect_match(conditionMessage(err), "The variable(s) `my_index` are not registered", fixed = TRUE)
  expect_identical(fake_log(api), "GET /api/v1/variables")
})

test_that("a failed job carries the rejected rows; wait = FALSE returns the job", {
  local_fake_clock()
  soil <- write_session(api)
  err <- tryCatch(
    soil_publish_values(soil, 42, value_records(3), "bulk-fail", transport = "ndjson", progress = FALSE),
    soilhub_job_error = function(e) e
  )
  expect_identical(err$reason, "failed")
  expect_identical(err$errors$record, 3L)
  expect_identical(err$errors$errors, "target_not_found")
  expect_identical(err$job_detail$diagnostics$diagnostics_truncated, FALSE)

  queued <- soil_publish_values(soil, 42, value_records(2), "bulk-later", transport = "ndjson", wait = FALSE)
  expect_identical(queued$status, "queued")
  expect_true(is.na(queued$published_count))
  expect_output(print(queued), "Job:       ", fixed = TRUE)
  expect_identical(soil_job_wait(soil, queued, progress = FALSE)$status, "completed")

  expect_warning(
    soil_publish_values(soil, 42, value_records(3), "bulk-short", transport = "ndjson", progress = FALSE),
    class = "soilhub_reconciliation_warning"
  )
})

test_that("the capabilities of value publication are checked", {
  fake_control(api, "reset")
  soil <- write_session(api)
  soil$state$capabilities <- capabilities_with(publish_generic_values = FALSE)
  expect_error(soil_publish_values(soil, 42, value_records(1), "k"), class = "soilhub_capability_error")
  soil$state$capabilities <- capabilities_with(generic_bulk_publication = FALSE)
  expect_error(soil_publish_values(soil, 42, value_records(1), "k", transport = "ndjson"),
               class = "soilhub_capability_error")
  expect_length(fake_log(api), 0L)
})

# ---------------------------------------------------------------------------
# Soil health

test_that("soil-health scores are checked, published and reconciled", {
  fake_control(api, "reset")
  soil <- write_session(api)
  out <- soil_publish_health(soil, 42, health_records(2), "health-1")
  expect_identical(out$transport, "sync")
  expect_identical(out$score_count, 2)
  expect_identical(out$published_count, 2)
  expect_null(out$validation)
  expect_identical(fake_log(api), "POST /api/v1/publications/42/soil-health")
  expect_output(print(out), "scores 2", fixed = TRUE)

  expect_warning(soil_publish_health(soil, 42, health_records(2), "short"),
                 class = "soilhub_reconciliation_warning")
  err <- tryCatch(soil_publish_health(soil, 77, health_records(1), "k"), soilhub_validation_error = function(e) e)
  expect_identical(err$errors$errors, "target_not_found")
  err <- tryCatch(soil_publish_health(soil, 42, health_records(1), "conflict"), soilhub_conflict_error = function(e) e)
  expect_match(conditionMessage(err), "also in memberships, rules or diagnostics", fixed = TRUE)
})

test_that("soil-health records failing the local checks are listed", {
  fake_control(api, "reset")
  soil <- write_session(api)
  scores <- health_records(5)
  scores[[1]]$score_class <- NULL
  scores[[2]]$score_status <- "insufficient_data"
  scores[[3]]$source_support <- "satellite"
  scores[[4]]$observation_inputs <- list(list(observation_id = "x", input_role = "bd"))
  scores[[5]]$horizon_id <- scores[[5 - 1]]$horizon_id
  err <- tryCatch(soil_publish_health(soil, 42, scores, "k"), soilhub_argument_error = function(e) e)
  expect_identical(err$argument, "scores")
  expect_identical(err$errors$record, 1:5)
  expect_identical(err$errors$errors, c(
    "scored_without_score_class", "non_scored_with_score_or_class", "invalid_source_support",
    "invalid_observation_input", "duplicate_horizon_category_release"
  ))
  frame <- data.frame(horizon_id = uuid_n(1), release_id = NA_integer_, category_code = "soc",
                      score_status = "graded", source_support = "polygon_estimate")
  err <- tryCatch(soil_publish_health(soil, 42, frame, "k"), soilhub_argument_error = function(e) e)
  expect_identical(err$errors$errors, "release_id_missing, invalid_score_status")
  expect_length(fake_log(api), 0L)

  # a data frame of non-scored rows passes
  ok <- data.frame(horizon_id = uuid_n(1:2), release_id = 12L, category_code = "soc",
                   score_status = "not_applicable", score = NA_real_, score_class = NA_character_,
                   source_support = "non_spatial_estimate")
  expect_identical(soil_publish_health(soil, 42, ok, "health-df")$published_count, 2)
})

test_that("soil-health NDJSON jobs upload to their endpoint and read their view", {
  local_fake_clock()
  fake_control(api, "reset")
  soil <- write_session(api)
  out <- soil_publish_health(soil, 42, health_records(3), "health-bulk", transport = "ndjson", progress = FALSE)
  expect_identical(out$published_count, 3)
  expect_identical(fake_log(api)[1], "POST /api/v1/publications/42/soil-health/jobs")
  sent <- strsplit(fake_upload(api, out$job_id)$text, "\n", fixed = TRUE)[[1]]
  expect_identical(jsonlite::fromJSON(sent[1], simplifyVector = FALSE)$memberships, list(poor = 0.1, good = 0.8))

  err <- tryCatch(
    soil_publish_health(soil, 42, health_records(2), "health-fail", transport = "ndjson", progress = FALSE),
    soilhub_job_error = function(e) e
  )
  expect_identical(attr(err$job_detail, "view"), "soil_health")
  expect_identical(err$errors$errors, "target_not_found")

  soil$state$capabilities <- capabilities_with(bulk_soil_health = FALSE)
  expect_error(soil_publish_health(soil, 42, health_records(1), "k", transport = "ndjson"),
               class = "soilhub_capability_error")
})
