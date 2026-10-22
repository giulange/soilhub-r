# Page collector (design 2.4, 3.4) against a fake paged endpoint.
#
# POST /api/v1/query/rows serves items {id = 1..total}. Control fields in the
# body: total, server_max (page size clamp), with_total (send total_count),
# no_has_more, empty_at (empty page with has_more TRUE from this offset),
# fail_at + fail_status (error at this offset), fixed_request_id.

paging_routes <- list(
  list(method = "post", path = "/api/v1/query/rows", handler = function(req, res) {
    b <- req$json
    get <- function(name, default) if (is.null(b[[name]])) default else b[[name]]
    id <- req$get_header("X-Request-ID")
    if (!is.null(id)) res$set_header("X-Request-ID", id)
    total <- get("total", 25)
    limit <- min(b$limit, get("server_max", 1000))
    offset <- b$offset
    if (!is.null(b$fail_at) && offset == b$fail_at) {
      status <- get("fail_status", 503)
      detail <- if (status == 401) "Invalid authentication token" else "Database unavailable"
      return(res$set_status(status)$send_json(list(detail = detail), auto_unbox = TRUE))
    }
    ids <- if (offset < total) seq(offset + 1, min(offset + limit, total)) else numeric()
    has_more <- offset + length(ids) < total
    if (!is.null(b$empty_at) && offset >= b$empty_at) {
      ids <- numeric()
      has_more <- TRUE
    }
    meta <- list(
      schema_version = "1.0",
      request_id = get("fixed_request_id", id),
      filters = list(datasets = b$datasets),
      total_count = if (isTRUE(b$with_total)) total else NULL,
      returned_count = length(ids),
      limit = limit,
      offset = offset,
      has_more = has_more,
      warnings = list(paste("warning", (offset / 10) %% 2))
    )
    if (isTRUE(b$no_has_more)) meta$has_more <- NULL
    rows <- lapply(ids, function(i) list(id = i))
    geometries <- lapply(ids, function(i) paste0("POINT(", i, " 0)"))
    names(geometries) <- if (length(ids)) paste0("f", ids) else character()
    res$send_json(
      list(metadata = meta, rows = rows, geometries = geometries),
      auto_unbox = TRUE, null = "null"
    )
  })
)

server <- fake_api(paging_routes)

ids_of <- function(x) vapply(x$items, function(item) as.numeric(item$id), numeric(1))

test_that("the loop stops when has_more is FALSE", {
  soil <- test_session(server)
  x <- soil_collect(soil, "/query/rows", list(datasets = I("wosis_points"), total = 25, with_total = TRUE),
                    items = "rows", page_size = 10)
  expect_s3_class(x, "soilhub_pages")
  expect_identical(ids_of(x), as.numeric(1:25))
  meta <- x$metadata
  expect_identical(meta$pages, 3L)
  expect_true(meta$complete)
  expect_identical(meta$stop_reason, "end")
  expect_true(is.na(meta$next_offset))
  expect_identical(meta$returned_count, 25)
  expect_identical(meta$total_count, 25)
  expect_identical(meta$endpoint, "/query/rows")
  expect_identical(meta$request$datasets, I("wosis_points"))
  expect_null(meta$request$limit)
  expect_identical(meta$schema_version, "1.0")
  expect_null(meta$has_more)
  expect_length(meta$request_ids, 3L)
  expect_true(all(grepl(request_id_pattern, meta$request_ids)))
  expect_identical(anyDuplicated(meta$request_ids), 0L)
  expect_setequal(meta$warnings, c("warning 0", "warning 1"))
  expect_length(x$page_metadata, 3L)
  expect_identical(vapply(x$page_metadata, function(m) m$offset, numeric(1)), c(0, 10, 20))
  expect_identical(names(x$extras[[3]]$geometries), paste0("f", 21:25))
  expect_match(capture.output(print(x)), "25 item\\(s\\) from 3 page\\(s\\) of POST /query/rows, complete")
})

test_that("the loop stops at max_rows and asks only for what is missing", {
  soil <- test_session(server)
  x <- soil_collect(soil, "/query/rows", list(total = 100), items = "rows",
                    page_size = 10, max_rows = 25)
  expect_identical(ids_of(x), as.numeric(1:25))
  expect_identical(vapply(x$page_metadata, function(m) m$limit, numeric(1)), c(10, 10, 5))
  expect_false(x$metadata$complete)
  expect_identical(x$metadata$stop_reason, "max_rows")
  expect_identical(x$metadata$next_offset, 25)
  expect_true(is.na(x$metadata$total_count))
})

test_that("the loop stops on an empty page", {
  soil <- test_session(server)
  x <- soil_collect(soil, "/query/rows", list(total = 100, empty_at = 20),
                    items = "rows", page_size = 10)
  expect_identical(ids_of(x), as.numeric(1:20))
  expect_identical(x$metadata$pages, 3L)
  expect_identical(x$metadata$stop_reason, "empty_page")
  expect_true(x$metadata$complete)
})

test_that("an empty selection gives one empty page", {
  soil <- test_session(server)
  x <- soil_collect(soil, "/query/rows", list(total = 0), items = "rows")
  expect_length(x$items, 0L)
  expect_identical(x$metadata$pages, 1L)
  expect_true(x$metadata$complete)
})

test_that("the offset advances by the items returned when the server clamps the page", {
  soil <- test_session(server)
  x <- soil_collect(soil, "/query/rows", list(total = 30, server_max = 7),
                    items = "rows", page_size = 10)
  expect_identical(ids_of(x), as.numeric(1:30))
  expect_identical(vapply(x$page_metadata, function(m) m$offset, numeric(1)), c(0, 7, 14, 21, 28))
})

test_that("without has_more a short page ends the read", {
  soil <- test_session(server)
  x <- soil_collect(soil, "/query/rows", list(total = 25, no_has_more = TRUE),
                    items = "rows", page_size = 10)
  expect_identical(ids_of(x), as.numeric(1:25))
  expect_identical(x$metadata$pages, 3L)
})

test_that("a read starts at body$offset", {
  soil <- test_session(server)
  x <- soil_collect(soil, "/query/rows", list(total = 25, offset = 10),
                    items = "rows", page_size = 10)
  expect_identical(ids_of(x), as.numeric(11:25))
  expect_identical(x$metadata$start_offset, 10)
})

test_that("page size: call > session > option > server max > 1000", {
  local_clean_config()
  expect_identical(resolve_page_size(list()), 1000)
  expect_identical(resolve_page_size(list(capabilities = list(limits = list(max_page_size = 500L)))), 500)
  local_opts(soilhub.page_size = 200)
  expect_identical(resolve_page_size(list()), 200)
  expect_identical(resolve_page_size(list(page_size = 300)), 300)
  expect_identical(resolve_page_size(list(page_size = 300), 50), 50)
  expect_identical(resolve_page_size(list(capabilities = list(limits = list(max_page_size = 100L))), 5000), 100)
  expect_error(resolve_page_size(list(), 0), class = "soilhub_argument_error")
  expect_error(resolve_page_size(list(), 2.5), class = "soilhub_argument_error")
})

test_that("argument checks", {
  soil <- test_session(server)
  expect_error(soil_collect(soil, "/query/rows", list(), items = "rows", max_rows = 0),
               class = "soilhub_argument_error")
  expect_error(soil_collect(soil, "/query/rows", list(), items = NULL),
               class = "soilhub_argument_error")
})

test_that("a failing page returns the pages read as a partial result", {
  sleeps <- local_fake_sleep()
  soil <- test_session(server)
  e <- expect_error(
    soil_collect(soil, "/query/rows", list(total = 100, fail_at = 20, with_total = TRUE),
                 items = "rows", page_size = 10),
    class = "soilhub_unavailable_error"
  )
  expect_identical(e$attempts, 3L)
  expect_s3_class(e$partial, "soilhub_pages")
  expect_identical(ids_of(e$partial), as.numeric(1:20))
  expect_false(e$partial$metadata$complete)
  expect_identical(e$partial$metadata$stop_reason, "error")
  expect_identical(e$partial$metadata$next_offset, 20)
  expect_identical(e$partial$metadata$total_count, 100)
  expect_match(conditionMessage(e), "20 row(s) read before the failure are in `e$partial`; continue from offset 20.", fixed = TRUE)
  expect_true(any(grepl("partial: 20 row\\(s\\) read, next_offset = 20", capture.output(print(e)))))

  # continuing from next_offset reads the rest
  x <- soil_collect(soil, "/query/rows",
                    list(total = 100, offset = e$partial$metadata$next_offset, fail_at = 10),
                    items = "rows", page_size = 10)
  expect_identical(ids_of(x), as.numeric(21:100))
})

test_that("an expired session mid-read keeps the pages read (auth error)", {
  soil <- test_session(server, auth = function(soil, renew = FALSE) "token")
  e <- expect_error(
    soil_collect(soil, "/query/rows", list(total = 100, fail_at = 30, fail_status = 401),
                 items = "rows", page_size = 10),
    class = "soilhub_auth_error"
  )
  expect_identical(e$reason, "session_expired")
  expect_identical(length(e$partial$items), 30L)
  expect_identical(e$partial$metadata$next_offset, 30)
})

test_that("a failure on the first page has no partial result", {
  soil <- test_session(server)
  e <- expect_error(
    soil_collect(soil, "/query/rows", list(total = 100, fail_at = 0, fail_status = 404),
                 items = "rows", page_size = 10),
    class = "soilhub_not_found_error"
  )
  expect_null(e$partial)
})

test_that("the same page served twice stops the loop", {
  soil <- test_session(server)
  e <- expect_error(
    soil_collect(soil, "/query/rows", list(total = 100, fixed_request_id = "same"),
                 items = "rows", page_size = 10),
    class = "soilhub_api_error"
  )
  expect_identical(e$code, "unchanged_page")
  expect_identical(length(e$partial$items), 10L)
})

test_that("verbosity 1 reports the pages read; progress = FALSE and verbosity 0 are silent", {
  soil <- test_session(server, verbose = 1)
  msgs <- testthat::capture_messages(
    soil_collect(soil, "/query/rows", list(total = 25, with_total = TRUE), items = "rows", page_size = 10)
  )
  expect_identical(msgs, c(
    "soilhub: page 1 read, 10 of 25 row(s).\n",
    "soilhub: page 2 read, 20 of 25 row(s).\n",
    "soilhub: page 3 read, 25 of 25 row(s).\n"
  ))
  msgs <- testthat::capture_messages(
    soil_collect(soil, "/query/rows", list(total = 15), items = "rows", page_size = 10)
  )
  expect_identical(msgs[2], "soilhub: page 2 read, 15 row(s).\n")
  expect_no_message(
    soil_collect(soil, "/query/rows", list(total = 25), items = "rows", page_size = 10, progress = FALSE)
  )
  soil$verbose <- 0
  expect_no_message(soil_collect(soil, "/query/rows", list(total = 25), items = "rows", page_size = 10))

  soil$verbose <- 2
  msgs <- testthat::capture_messages(
    soil_collect(soil, "/query/rows", list(total = 15), items = "rows", page_size = 10)
  )
  expect_length(grep("^soilhub: POST /query/rows -> 200", msgs), 2L)
  expect_length(grep("^soilhub: page", msgs), 2L)
})
