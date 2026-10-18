# Page collector (design 2.3, 2.4, 3.4): offset loop over a paged POST
# endpoint, metadata accumulation, partial result on failure. It knows no
# column names: the items are returned as parsed, typing is done by the
# callers (typing.R, WP4).

paging_fields <- c("limit", "offset", "returned_count", "has_more", "request_id")

#' Read every page of a paged request
#'
#' Sends `body` with `limit` and `offset` to `path`, from `body$offset` (0 when
#' absent), adding the number of items returned to the offset, until
#' `metadata.has_more` is `FALSE`, a page is empty, or `max_rows` items are
#' read.
#'
#' @param soil The session.
#' @param path Endpoint path (`POST`).
#' @param body Request body (the selection); `limit` and `offset` are set here.
#' @param items Name of the array of the response that holds the page items
#'   (`"rows"`, `"observations"`, `"features"`).
#' @param max_rows Maximum number of items to read (`Inf` for all).
#' @param page_size Items per page; `NULL` uses `resolve_page_size()`.
#' @param progress Show progress (a bar when interactive and `total_count`
#'   is known, else one message per page at verbosity >= 1).
#' @return A list of class `soilhub_pages`: `items` (all items, concatenated),
#'   `metadata` (the first page's metadata without its paging fields, plus
#'   `endpoint`, `request` (body without `limit`/`offset`), `request_ids`,
#'   `pages`, `returned_count`, `start_offset`, `next_offset`, `complete`,
#'   `stop_reason`, `total_count`, `warnings`, `retrieved_at`),
#'   `page_metadata` (the metadata of every page) and `extras` (the other
#'   top-level fields of every page, e.g. `geometries`).
#'   On a `soilhub_error` after at least one page, the error is re-signalled
#'   with that result in `e$partial` (`complete = FALSE`, `next_offset` the
#'   offset of the failed page).
#' @keywords internal
#' @noRd
soil_collect <- function(soil, path, body = list(), items, max_rows = Inf,
                         page_size = NULL, progress = TRUE) {
  if (!is_string(items)) {
    abort(soilhub_argument_error("`items` must be the name of the page array.", "items"))
  }
  max_rows <- check_max_rows(max_rows)
  page_size <- resolve_page_size(soil, page_size)
  body <- body %||% list()
  start_offset <- as.numeric(body$offset %||% 0)
  request <- body[setdiff(names(body), c("limit", "offset"))]

  state <- new.env(parent = emptyenv())
  state$pages <- list()
  state$extras <- list()
  state$page_metadata <- list()
  state$request_ids <- character()
  state$count <- 0
  state$offset <- start_offset
  state$total <- NA_real_
  state$warnings <- character()

  bar <- NULL
  on.exit(if (!is.null(bar)) close(bar), add = TRUE)

  stop_reason <- NULL
  repeat {
    limit <- min(page_size, max_rows - state$count)
    page_body <- body
    page_body$limit <- limit
    page_body$offset <- state$offset

    page <- tryCatch(
      soil_request(soil, "POST", path, body = page_body),
      soilhub_error = function(e) e
    )
    if (inherits(page, "soilhub_error")) {
      if (length(state$pages) == 0L) abort(page)
      abort(with_partial(page, collected_result(state, request, path, start_offset, "error")))
    }
    if (!is.list(page)) {
      abort(soilhub_api_error(
        sprintf("The API returned no page body for POST %s.", path),
        endpoint = path, method = "POST", code = "invalid_page"
      ))
    }

    meta <- page$metadata %||% list()
    request_id <- meta$request_id %||% attr(page, "request_id")
    if (!is.null(request_id) && request_id %in% state$request_ids) {
      error <- soilhub_api_error(
        paste0(
          "The API returned the same page twice; the read stops to avoid a loop.",
          request_suffix(NULL, "POST", path, request_id)
        ),
        endpoint = path, method = "POST", request_id = request_id,
        code = "unchanged_page"
      )
      abort(with_partial(error, collected_result(state, request, path, start_offset, "error")))
    }

    rows <- page[[items]] %||% list()
    if (state$count + length(rows) > max_rows) {
      rows <- rows[seq_len(max_rows - state$count)]
    }
    returned <- length(rows)
    state$pages[[length(state$pages) + 1L]] <- rows
    state$page_metadata[[length(state$page_metadata) + 1L]] <- meta
    state$extras[[length(state$extras) + 1L]] <- page[setdiff(names(page), c(items, "metadata"))]
    state$request_ids <- c(state$request_ids, request_id %||% NA_character_)
    state$count <- state$count + returned
    state$offset <- state$offset + returned
    if (!is.null(meta$total_count)) state$total <- as.numeric(meta$total_count)
    state$warnings <- unique(c(state$warnings, unlist(meta$warnings)))

    has_more <- meta$has_more
    if (is.null(has_more)) has_more <- returned >= limit

    bar <- report_progress(soil, progress, bar, state, start_offset)

    if (returned == 0L) {
      stop_reason <- "empty_page"
    } else if (!isTRUE(has_more)) {
      stop_reason <- "end"
    } else if (state$count >= max_rows) {
      stop_reason <- "max_rows"
    }
    if (!is.null(stop_reason)) break
  }
  collected_result(state, request, path, start_offset, stop_reason)
}

check_max_rows <- function(max_rows) {
  if (is.null(max_rows)) return(Inf)
  value <- suppressWarnings(as.numeric(max_rows))
  if (length(value) != 1L || is.na(value) || value < 1 ||
      (is.finite(value) && value != round(value))) {
    abort(soilhub_argument_error(
      sprintf(
        "`max_rows` must be a positive whole number or Inf, not %s.",
        deparse_argument(max_rows)
      ),
      "max_rows"
    ))
  }
  value
}

collected_result <- function(state, request, path, start_offset, stop_reason) {
  complete <- stop_reason %in% c("end", "empty_page")
  first <- if (length(state$page_metadata) > 0L) state$page_metadata[[1L]] else list()
  metadata <- first[setdiff(names(first), c(paging_fields, "total_count", "warnings"))]
  metadata$endpoint <- path
  metadata$request <- request
  metadata$request_ids <- state$request_ids
  metadata$pages <- length(state$pages)
  metadata$returned_count <- state$count
  metadata$start_offset <- start_offset
  metadata$next_offset <- if (complete) NA_real_ else state$offset
  metadata$complete <- complete
  metadata$stop_reason <- stop_reason
  metadata$total_count <- state$total
  metadata$warnings <- state$warnings
  metadata$retrieved_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  structure(
    list(
      items = unlist(state$pages, recursive = FALSE) %||% list(),
      metadata = metadata,
      page_metadata = state$page_metadata,
      extras = state$extras
    ),
    class = "soilhub_pages"
  )
}

# Attach the pages read before a failure (3.4) and say how to continue.
with_partial <- function(error, partial) {
  error$partial <- partial
  error$message <- paste0(
    conditionMessage(error),
    sprintf(
      "\n%s row(s) read before the failure are in `e$partial`; continue from offset %s.",
      format_count(length(partial$items)),
      format(partial$metadata$next_offset, scientific = FALSE)
    )
  )
  error
}

report_progress <- function(soil, progress, bar, state, start_offset) {
  if (!isTRUE(progress)) return(bar)
  if (interactive() && !is.na(state$total) && state$total > start_offset) {
    if (is.null(bar)) {
      bar <- utils::txtProgressBar(min = 0, max = state$total - start_offset, style = 3)
    }
    utils::setTxtProgressBar(bar, min(state$count, state$total - start_offset))
    return(bar)
  }
  total <- if (is.na(state$total)) "" else paste0(" of ", format_count(state$total - start_offset))
  soil_inform(soil, 1, sprintf(
    "soilhub: page %d read, %s%s row(s).",
    length(state$pages), format_count(state$count), total
  ))
  bar
}

#' @export
print.soilhub_pages <- function(x, ...) {
  meta <- x$metadata
  cat(sprintf(
    "<soilhub_pages> %s item(s) from %d page(s) of POST %s, %s\n",
    format_count(length(x$items)), meta$pages, meta$endpoint,
    if (isTRUE(meta$complete)) "complete" else paste("incomplete, next_offset", format(meta$next_offset, scientific = FALSE))
  ))
  invisible(x)
}
