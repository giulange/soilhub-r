# Records and NDJSON files of the write functions (design 4.6, decision 6):
# pure tests, no server.

test_that("a data frame becomes one record per row, empty fields left out", {
  values <- data.frame(
    variable_code = c("organic_carbon", "organic_carbon"),
    target_id = c("a", "b"),
    value = c(1.5, NA),
    value_status = c("published", "insufficient_data"),
    valid_time_start = as.POSIXct(c("2020-01-01 10:00:00", NA), tz = "UTC"),
    sampled = as.Date(c("2019-05-01", NA)),
    kind = factor(c("x", "y")),
    stringsAsFactors = FALSE
  )
  values$lineage <- list(list(observations = list(list(id = "o1", role = "r"))), NULL)
  records <- as_records(values)
  expect_length(records, 2L)
  expect_identical(records[[1]]$value, 1.5)
  expect_identical(records[[1]]$valid_time_start, "2020-01-01T10:00:00Z")
  expect_identical(records[[1]]$sampled, "2019-05-01")
  expect_identical(records[[1]]$kind, "x")
  expect_identical(records[[1]]$lineage$observations[[1]]$id, "o1")
  expect_false(any(c("value", "valid_time_start", "sampled", "lineage") %in% names(records[[2]])))
  expect_identical(records[[2]]$value_status, "insufficient_data")

  # a list of records is kept, NULL and NA fields dropped
  listed <- as_records(list(list(a = 1, b = NULL, c = NA, d = list())))
  expect_identical(listed, list(list(a = 1)))
  expect_error(as_records("x"), class = "soilhub_argument_error")
  expect_error(as_records(list(1, 2)), class = "soilhub_argument_error")
})

test_that("NDJSON files hold one object per line and their SHA-256", {
  records <- list(
    list(variable_code = "organic_carbon", value = 1.25, target_levels = list("horizon"),
         lineage = list(observations = list(list(id = "o1", role = "r")))),
    list(variable_code = "clay", value = 30L, note = "été", flag = TRUE)
  )
  path <- withr::local_tempfile(fileext = ".ndjson")
  file <- write_ndjson(records, path)
  expect_identical(file$path, path)
  expect_identical(file$row_count, 2L)
  bytes <- readBin(path, "raw", file.size(path))
  expect_equal(file$byte_size, length(bytes))
  expect_identical(file$checksum_sha256, as.vector(as.character(openssl::sha256(bytes))))
  expect_match(file$checksum_sha256, "^[0-9a-f]{64}$")

  lines <- readLines(path, encoding = "UTF-8")
  expect_identical(lines[1], paste0(
    '{"variable_code":"organic_carbon","value":1.25,"target_levels":["horizon"],',
    '"lineage":{"observations":[{"id":"o1","role":"r"}]}}'
  ))
  expect_identical(lines[2], '{"variable_code":"clay","value":30,"note":"été","flag":true}')
  # every line ends with "\n", no carriage return
  expect_identical(bytes[length(bytes)], as.raw(10L))
  expect_false(any(bytes == as.raw(13L)))

  # the same records give the same bytes (a re-submission has the same checksum)
  again <- write_ndjson(records, withr::local_tempfile(fileext = ".ndjson"))
  expect_identical(again$checksum_sha256, file$checksum_sha256)
  expect_identical(sha256_file(path), file$checksum_sha256)
})

test_that("JSON objects are sent as objects even when empty", {
  expect_identical(as.character(jsonlite::toJSON(json_object(list(), "x"))), "{}")
  expect_identical(json_object(list(a = 1), "x"), list(a = 1))
  expect_error(json_object(list(1), "x"), class = "soilhub_argument_error")
  upload <- upload_body("f.ndjson")
  expect_s3_class(upload, "soilhub_upload")
  expect_identical(upload$type, "application/x-ndjson")
})
