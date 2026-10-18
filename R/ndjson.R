# Records for the write functions (design 4.6, decision 6): a data frame or a
# list of records becomes a list of JSON objects; bulk publications travel
# as an NDJSON file (one JSON object per line, UTF-8, "\n") with its SHA-256
# checksum, uploaded as `multipart/form-data`. Pure functions, no network,
# except `upload_body()` which only describes the upload for http.R.

#' Records from a data frame or a list of records
#'
#' A data frame gives one record per row: atomic columns become scalars,
#' list columns keep their element (a nested list, a data frame, a vector).
#' `NA` scalars, `NULL` and zero-length elements are dropped, so an optional
#' field left empty is absent from the JSON object and the API default
#' applies. `POSIXct` values become ISO 8601 UTC text, `Date` values
#' `YYYY-MM-DD`, factors text.
#'
#' @param x A data frame, or a list of named lists.
#' @param argument The argument name, for the error message.
#' @return A list of named lists.
#' @keywords internal
#' @noRd
as_records <- function(x, argument = "values") {
  if (is.data.frame(x)) {
    columns <- lapply(x, record_column)
    names(columns) <- names(x)
    records <- lapply(seq_len(nrow(x)), function(i) {
      record <- lapply(columns, function(column) column[[i]])
      compact_record(record)
    })
    return(records)
  }
  if (is.list(x) && is.null(names(x)) &&
      all(vapply(x, function(r) is.list(r) && !is.null(names(r)), logical(1)))) {
    return(lapply(x, function(record) compact_record(lapply(record, record_value))))
  }
  abort(soilhub_argument_error(
    sprintf("`%s` must be a data frame or a list of records (named lists).", argument),
    argument
  ))
}

# A data frame column prepared for row extraction: times as text, factors
# as character; list columns unchanged.
record_column <- function(column) {
  if (is.list(column)) return(lapply(column, record_value))
  record_value(column)
}

record_value <- function(value) {
  if (inherits(value, "POSIXt")) {
    out <- format(as.POSIXct(value), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    out[is.na(value)] <- NA_character_
    return(out)
  }
  if (inherits(value, "Date")) {
    out <- format(value, "%Y-%m-%d")
    out[is.na(value)] <- NA_character_
    return(out)
  }
  if (is.factor(value)) return(as.character(value))
  value
}

# Drop the absent fields of a record: NULL, zero-length, a scalar NA.
compact_record <- function(record) {
  keep <- vapply(record, function(value) {
    if (is.null(value) || length(value) == 0L) return(FALSE)
    if (is.atomic(value) && length(value) == 1L && is.na(value)) return(FALSE)
    TRUE
  }, logical(1))
  record[keep]
}

# A JSON object (`{}` when empty) from a named list.
json_object <- function(x, argument) {
  if (is.null(x) || length(x) == 0L) return(structure(list(), names = character()))
  if (!is.list(x) || is.null(names(x)) || any(!nzchar(names(x)))) {
    abort(soilhub_argument_error(
      sprintf("`%s` must be a named list (a JSON object).", argument),
      argument
    ))
  }
  x
}

#' One JSON line per record
#'
#' @param records A list of named lists.
#' @return A character vector, one JSON object per element.
#' @keywords internal
#' @noRd
ndjson_lines <- function(records) {
  vapply(records, function(record) {
    as.character(jsonlite::toJSON(
      record, auto_unbox = TRUE, null = "null", na = "null", digits = NA
    ))
  }, character(1), USE.NAMES = FALSE)
}

#' Write records as an NDJSON file and checksum it
#'
#' The file is UTF-8, one JSON object per line, each line ending with `\n`;
#' the same records always give the same bytes, so a deliberate
#' re-submission with the same idempotency key has the same checksum.
#'
#' @param records A list of named lists (see `as_records()`).
#' @param path The file to write; a temporary file by default.
#' @return A list: `path`, `checksum_sha256` (lowercase hex SHA-256 of the
#'   file), `byte_size`, `row_count`.
#' @keywords internal
#' @noRd
write_ndjson <- function(records, path = tempfile("soilhub-", fileext = ".ndjson")) {
  lines <- enc2utf8(ndjson_lines(records))
  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  if (length(lines)) {
    writeBin(charToRaw(paste0(paste(lines, collapse = "\n"), "\n")), con)
  }
  close(con)
  on.exit()
  list(
    path = path,
    checksum_sha256 = sha256_file(path),
    byte_size = file.size(path),
    row_count = length(lines)
  )
}

#' SHA-256 of a file, lowercase hex
#' @keywords internal
#' @noRd
sha256_file <- function(path) {
  con <- file(path, open = "rb")
  on.exit(close(con))
  # as.vector(): drop the `hash` class of openssl
  as.vector(as.character(openssl::sha256(con)))
}

#' A file upload for `soil_request()`
#'
#' @param path The file to upload (field `file` of a `multipart/form-data`
#'   body).
#' @param type Its media type.
#' @keywords internal
#' @noRd
upload_body <- function(path, type = "application/x-ndjson") {
  structure(list(path = path, type = type), class = "soilhub_upload")
}
