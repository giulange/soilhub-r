# Job control (design 4.6): status views, waiting to a terminal state with a
# controlled clock, cancel, country refresh, rights pre-check.

api <- fake_write_api()

# Submit an NDJSON value publication without waiting; returns the job id.
submit_job <- function(soil, key) {
  out <- soil_publish_values(soil, 42, value_records(2), key, validate = FALSE,
                             transport = "ndjson", wait = FALSE)
  out$job_id
}

test_that("soil_job() reads the unified and the dataset-specific views", {
  soil <- write_session(api)
  id <- submit_job(soil, "views")
  job <- soil_job(soil, id)
  expect_s3_class(job, "soil_job")
  expect_identical(job$status, "running")
  expect_identical(job$job_type, "value_publication")
  expect_identical(job$received_count, 2)
  expect_s3_class(job$created_at, "POSIXct")
  expect_null(job$error)
  expect_match(attr(job, "request_id"), request_id_pattern)
  expect_output(print(job), "Status:  running, 20%", fixed = TRUE)

  view <- soil_job(soil, id, detail = "publication")
  expect_identical(attr(view, "view"), "publication")
  expect_identical(view$input_format, "ndjson")
  expect_identical(view$run_id, 42)
  expect_output(print(view), "View:    publication", fixed = TRUE)

  # an unknown job is a not-found error; a bad id an argument error
  expect_error(soil_job(soil, "nope"), class = "soilhub_not_found_error")
  expect_error(soil_job(soil, NA_character_), class = "soilhub_argument_error")
  expect_error(soil_job(soil, id, detail = "export"))
})

test_that("soil_job_wait() polls to completed with the controlled clock", {
  clock <- local_fake_clock()
  soil <- write_session(api)
  id <- submit_job(soil, "complete-me")
  msgs <- character()
  job <- withCallingHandlers(
    soil_job_wait(soil, id, poll = 5, progress = TRUE),
    soilhub_message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  expect_identical(job$status, "completed")
  expect_identical(job$published_count, 2)
  expect_identical(clock$waits, c(5, 5, 5))
  expect_match(msgs[1], paste0("job ", id, " running (20%)"), fixed = TRUE)
  expect_match(msgs[length(msgs)], "completed (100%)", fixed = TRUE)
})

test_that("a failed or cancelled job is a soilhub_job_error with the last status", {
  local_fake_clock()
  soil <- write_session(api)
  failed <- tryCatch(soil_job_wait(soil, submit_job(soil, "will-fail"), progress = FALSE),
                     soilhub_job_error = function(e) e)
  expect_s3_class(failed, "soilhub_job_error")
  expect_identical(failed$reason, "failed")
  expect_identical(failed$job$status, "failed")
  expect_match(conditionMessage(failed), "ended failed: publication payload is invalid (validation_failed)", fixed = TRUE)

  cancelled <- tryCatch(soil_job_wait(soil, submit_job(soil, "cancel-me"), progress = FALSE),
                        soilhub_job_error = function(e) e)
  expect_identical(cancelled$reason, "cancelled")
  expect_identical(cancelled$job_id, cancelled$job$job_id)
})

test_that("waiting stops at the timeout and the job keeps running", {
  clock <- local_fake_clock()
  soil <- write_session(api)
  id <- submit_job(soil, "slow")
  err <- tryCatch(soil_job_wait(soil, id, timeout = 12, poll = 5, progress = FALSE),
                  soilhub_job_error = function(e) e)
  expect_identical(err$reason, "timeout")
  expect_identical(err$job$status, "running")
  expect_identical(clock$waits, c(5, 5, 2))
  expect_match(conditionMessage(err), "continues on the server", fixed = TRUE)
  expect_error(soil_job_wait(soil, id, timeout = -1), class = "soilhub_argument_error")
  expect_error(soil_job_wait(soil, id, poll = 0), class = "soilhub_argument_error")
})

test_that("soil_job_cancel() cancels, reports an ended job, maps 409", {
  local_fake_clock()
  soil <- write_session(api)
  id <- submit_job(soil, "to-cancel")
  job <- soil_job_cancel(soil, id)
  expect_identical(job$status, "cancelled")
  expect_true(job$cancel_requested)

  soil$verbose <- 1
  done <- suppressMessages(submit_job(soil, "done-before"))
  soil_job_wait(soil, done, progress = FALSE)
  expect_message(again <- soil_job_cancel(soil, done), "had already ended (completed)", fixed = TRUE)
  expect_identical(again$status, "completed")

  err <- tryCatch(soil_job_cancel(soil, "conflict-job"), soilhub_conflict_error = function(e) e)
  expect_s3_class(err, "soilhub_conflict_error")
  expect_identical(err$status, 409L)
  expect_match(conditionMessage(err), "A job that has ended cannot change state", fixed = TRUE)
})

test_that("soil_refresh_countries() queues a job and needs soil:admin", {
  soil <- write_session(api)
  job <- soil_refresh_countries(soil, idempotency_key = "countries-1")
  expect_identical(job$job_type, "country_refresh")
  expect_identical(job$status, "queued")
  expect_identical(job$diagnostics$idempotency_key, "countries-1")
  expect_error(soil_refresh_countries(soil, idempotency_key = ""), class = "soilhub_argument_error")

  fake_control(api, "reset")
  reader <- write_session(api, "jwt-reader.json")
  err <- tryCatch(soil_refresh_countries(reader), soilhub_permission_error = function(e) e)
  expect_identical(err$required_right, "soil:admin")
  expect_match(conditionMessage(err), "`soil_refresh_countries()` needs the right `soil:admin`", fixed = TRUE)
  expect_length(fake_log(api), 0L)
})

test_that("job functions pre-check soil:publish, or let the API decide", {
  fake_control(api, "reset")
  reader <- write_session(api, "jwt-reader.json")
  for (call in list(
    function() soil_job(reader, "x"),
    function() soil_job_wait(reader, "x"),
    function() soil_job_cancel(reader, "x")
  )) {
    err <- tryCatch(call(), soilhub_permission_error = function(e) e)
    expect_s3_class(err, "soilhub_permission_error")
    expect_identical(err$required_right, "soil:publish")
    expect_identical(err$rights, c("soil:read", "soil:summary"))
    expect_null(err$status)
  }
  expect_length(fake_log(api), 0L)

  # rights not declared in the token: the request is sent, the 403 mapped
  fake_control(api, "deny")
  undeclared <- write_session(api, "jwt-noroles.json")
  err <- tryCatch(soil_job(undeclared, "x"), soilhub_permission_error = function(e) e)
  expect_identical(err$status, 403L)
  expect_identical(err$required_right, "soil:publish")
  expect_identical(err$endpoint, "/jobs/x")
  expect_match(conditionMessage(err), "Missing required scope", fixed = TRUE)
  expect_identical(fake_log(api), "GET /api/v1/jobs/x")
  fake_control(api, "reset")
})
