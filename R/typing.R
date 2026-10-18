# Typing of API records (design 5.5, 9.2): a list of JSON objects, parsed
# with `simplifyVector = FALSE`, becomes a data frame with one column per
# field of a schema, each of a fixed R type. Nested arrays of objects become
# list columns of data frames, typed by their own schema; free-form JSON
# objects stay list columns. Pure functions, no network.
#
# Drift (9.2): a field the schema does not know is kept as a list column
# (values as parsed) and a field the schema expects but the API did not send
# becomes an `NA` column; both are reported once per R session with a
# `soilhub_contract_warning`.
#
# Column types of a schema:
#   "chr"       character
#   "int"       integer
#   "dbl"       double (counts too: they may exceed the integer range)
#   "lgl"       logical
#   "time"      POSIXct, UTC (ISO 8601 text of the API)
#   "date"      Date
#   "chr_list"  list of character vectors (JSON arrays of strings)
#   "json"      list of parsed JSON values (free-form objects)
#   frames(s)   list of data frames typed by the schema `s` (arrays of
#               objects); a JSON null stays NULL

frames <- function(schema) {
  structure(list(schema = schema), class = "soilhub_frames_type")
}

#' Records to a typed data frame
#'
#' @param records A list of named lists (JSON objects).
#' @param schema A named list of column types (see the top of `typing.R`).
#' @param context Where the records come from (e.g. `"GET /datasets"`), for
#'   the contract warnings; `NULL` reports nothing.
#' @return A data frame with the schema columns in schema order, then the
#'   unknown fields as list columns.
#' @keywords internal
#' @noRd
records_frame <- function(records, schema, context = NULL) {
  records <- records %||% list()
  if (!is.list(records)) records <- list()
  # A single object instead of an array (a detail endpoint): one record.
  if (length(records) && !is.null(names(records)) && all(nzchar(names(records)))) {
    records <- list(records)
  }
  records <- lapply(records, function(record) if (is.list(record)) record else list())
  n <- length(records)
  fields <- unique(unlist(lapply(records, names), use.names = FALSE))
  expected <- names(schema)

  if (n > 0L && !is.null(context)) {
    report_drift(context, setdiff(fields, expected), setdiff(expected, fields))
  }

  columns <- lapply(expected, function(name) {
    values <- lapply(records, function(record) record[[name]])
    type_column(values, schema[[name]], paste0(context, ": ", name))
  })
  names(columns) <- expected
  unknown <- setdiff(fields, expected)
  for (name in unknown) {
    columns[[name]] <- lapply(records, function(record) record[[name]])
  }
  new_frame(columns, n)
}

new_frame <- function(columns, n) {
  structure(columns, class = "data.frame", row.names = .set_row_names(n))
}

# One column from the values of a field (NULL where absent or JSON null).
type_column <- function(values, type, context = NULL) {
  if (inherits(type, "soilhub_frames_type")) {
    return(lapply(values, function(value) {
      if (is.null(value)) return(NULL)
      records_frame(value, type$schema, context)
    }))
  }
  switch(type,
    chr = vapply(values, scalar_chr, character(1)),
    int = vapply(values, function(v) scalar_num(v, as.integer, NA_integer_), integer(1)),
    dbl = vapply(values, function(v) scalar_num(v, as.numeric, NA_real_), numeric(1)),
    lgl = vapply(values, scalar_lgl, logical(1)),
    time = parse_api_time(vapply(values, scalar_chr, character(1))),
    date = parse_api_date(vapply(values, scalar_chr, character(1))),
    chr_list = lapply(values, function(v) {
      if (is.null(v)) return(NULL)
      vapply(v, scalar_chr, character(1), USE.NAMES = FALSE)
    }),
    json = values,
    abort(soilhub_argument_error(sprintf("Unknown column type `%s`.", type), "type"))
  )
}

scalar_chr <- function(value) {
  if (is.null(value) || length(value) == 0L) return(NA_character_)
  if (is.list(value) || length(value) > 1L) {
    return(as.character(jsonlite::toJSON(value, auto_unbox = TRUE, null = "null")))
  }
  if (is.na(value)) return(NA_character_)
  if (is.numeric(value)) return(format(value, scientific = FALSE, trim = TRUE, digits = 15))
  if (is.logical(value)) return(tolower(as.character(value)))
  as.character(value)
}

scalar_num <- function(value, as, missing) {
  if (is.null(value) || length(value) != 1L || is.list(value)) return(missing)
  out <- suppressWarnings(as(value))
  if (length(out) != 1L) missing else out
}

scalar_lgl <- function(value) {
  if (is.null(value) || length(value) != 1L || is.list(value)) return(NA)
  if (is.logical(value)) return(value)
  if (is.character(value)) {
    return(switch(tolower(value), "true" = TRUE, "false" = FALSE, NA))
  }
  if (is.numeric(value)) return(value != 0)
  NA
}

#' ISO 8601 text to POSIXct (UTC)
#'
#' Accepts `YYYY-MM-DD`, `YYYY-MM-DDTHH:MM[:SS[.fff]]` (or a space instead of
#' `T`) with an optional `Z` or `+HH:MM` / `-HHMM` offset, as FastAPI and
#' PostgreSQL write them; anything else is `NA`.
#' @keywords internal
#' @noRd
parse_api_time <- function(x) {
  x <- as.character(x)
  out <- rep(NA_real_, length(x))
  pattern <- "^(\\d{4}-\\d{2}-\\d{2})(?:[T ](\\d{2}:\\d{2})(:\\d{2})?(\\.\\d+)?)?\\s*(Z|[+-]\\d{2}(?::?\\d{2})?)?$"
  ok <- !is.na(x)
  parts <- regmatches(x[ok], regexec(pattern, x[ok], perl = TRUE))
  values <- vapply(parts, function(p) {
    if (length(p) == 0L) return(NA_real_)
    clock <- if (nzchar(p[3])) paste0(p[3], if (nzchar(p[4])) p[4] else ":00") else "00:00:00"
    base <- as.numeric(as.POSIXct(paste(p[2], clock), format = "%Y-%m-%d %H:%M:%S", tz = "UTC"))
    if (nzchar(p[5])) base <- base + as.numeric(paste0("0", p[5]))
    offset <- p[6]
    if (nzchar(offset) && offset != "Z") {
      sign <- if (startsWith(offset, "-")) -1 else 1
      digits <- gsub("[^0-9]", "", offset)
      hours <- as.numeric(substr(digits, 1, 2))
      minutes <- if (nchar(digits) >= 4) as.numeric(substr(digits, 3, 4)) else 0
      base <- base - sign * (hours * 3600 + minutes * 60)
    }
    base
  }, numeric(1))
  out[ok] <- values
  as_utc(out)
}

parse_api_date <- function(x) {
  x <- as.character(x)
  out <- rep(as.Date(NA), length(x))
  ok <- !is.na(x) & grepl("^\\d{4}-\\d{2}-\\d{2}", x)
  out[ok] <- as.Date(substr(x[ok], 1L, 10L), format = "%Y-%m-%d")
  out
}

# One-time warning (per R session and per context and field set) when the
# API sends fields the client does not know, or lacks fields it expects.
report_drift <- function(context, unknown, missing) {
  if (length(unknown)) {
    key <- paste0("contract:unknown:", context, ":", paste(sort(unknown), collapse = ","))
    if (!key %in% soilhub_env$shown) {
      soilhub_env$shown <- c(soilhub_env$shown, key)
      soilhub_warning(sprintf(
        paste0(
          "The API response of %s has field(s) this version of soilhub does not know: %s. ",
          "They are kept as list columns; update soilhub when a new version is available."
        ),
        context, paste0("`", unknown, "`", collapse = ", ")
      ), "soilhub_contract_warning")
    }
  }
  if (length(missing)) {
    key <- paste0("contract:missing:", context, ":", paste(sort(missing), collapse = ","))
    if (!key %in% soilhub_env$shown) {
      soilhub_env$shown <- c(soilhub_env$shown, key)
      soilhub_warning(sprintf(
        paste0(
          "The API response of %s lacks field(s) this version of soilhub expects: %s. ",
          "They are returned as NA (an older or newer API)."
        ),
        context, paste0("`", missing, "`", collapse = ", ")
      ), "soilhub_contract_warning")
    }
  }
  invisible(NULL)
}

# The one-row data frame `x` as a named list: list columns unwrapped.
frame_row_list <- function(x, i = 1L) {
  out <- lapply(x, function(column) column[[i]])
  names(out) <- names(x)
  out
}
