#' @include typing.R
NULL

# Internal helpers shared by the summaries (summary.R) and the thematic reads
# (values.R, health-read.R, targets.R, ttr-flags.R): argument checks of the
# filters that are not part of the canonical selection, loose typing of the
# responses whose fields depend on the path the API takes, counts objects to
# named vectors, geometry columns and the metadata of a single response.
# No network.

# A JSON object of counts (`{"wosis_points": 12}`) to a named double vector.
named_counts <- function(counts) {
  if (!is.list(counts) || !length(counts) || is.null(names(counts))) {
    return(stats::setNames(numeric(), character()))
  }
  vapply(counts, function(v) scalar_num(v, as.numeric, NA_real_), numeric(1))
}

# Counts by dataset of a summary: the API sends them only when several
# datasets are selected (`null` otherwise); with one dataset the total is its
# count.
dataset_counts <- function(counts, datasets, total) {
  if (is.list(counts) && length(counts)) return(named_counts(counts))
  if (length(datasets) == 1L && !is.null(total)) {
    return(stats::setNames(scalar_num(total, as.numeric, NA_real_), datasets))
  }
  stats::setNames(numeric(), character())
}

#' Records to a data frame, types inferred where no schema is given
#'
#' For responses whose fields depend on the path the API takes (the three
#' calculations of `/query/consistency` select `s.*` of different statistics
#' tables): the fields of `schema` get its types, the others are typed from
#' their JSON values (numbers double, booleans logical, strings character,
#' anything else a list column). No contract warning: the shape varies by
#' design.
#' @keywords internal
#' @noRd
loose_frame <- function(records, schema = list()) {
  records <- records %||% list()
  if (!is.list(records)) records <- list()
  records <- lapply(records, function(record) if (is.list(record)) record else list())
  fields <- unique(unlist(lapply(records, names), use.names = FALSE))
  columns <- lapply(fields, function(name) {
    values <- lapply(records, function(record) record[[name]])
    type_column(values, schema[[name]] %||% infer_type(values))
  })
  names(columns) <- fields
  new_frame(columns, length(records))
}

infer_type <- function(values) {
  present <- Filter(Negate(is.null), values)
  if (!length(present)) return("chr")
  scalar <- all(vapply(present, function(v) is.atomic(v) && length(v) == 1L, logical(1)))
  if (!scalar) return("json")
  if (all(vapply(present, is.logical, logical(1)))) return("lgl")
  if (all(vapply(present, is.numeric, logical(1)))) return("dbl")
  "chr"
}

# Optional filter restricted to known values (NULL = no filter).
check_values <- function(value, choices, argument) {
  value <- check_filter(value, argument)
  if (is.null(value)) return(NULL)
  unknown <- setdiff(value, choices)
  if (length(unknown)) {
    abort(soilhub_argument_error(
      sprintf(
        "Unknown `%s` value(s) %s; accepted: %s.",
        argument, paste0("\"", unknown, "\"", collapse = ", "),
        paste0("\"", choices, "\"", collapse = ", ")
      ),
      argument
    ))
  }
  value
}

# Optional whole numbers (ids): NULL or a numeric vector without NA.
check_ids <- function(value, argument) {
  if (is.null(value)) return(NULL)
  number <- suppressWarnings(as.numeric(value))
  if (!(is.numeric(value) || is.character(value)) || !length(number) || anyNA(number) ||
      any(!is.finite(number)) || any(number != round(number)) || any(number < 1)) {
    abort(soilhub_argument_error(
      sprintf("`%s` must be NULL (no filter) or positive whole numbers, not %s.", argument, deparse_argument(value)),
      argument
    ))
  }
  unique(number)
}

# Optional single number (depths in cm).
check_number <- function(value, argument) {
  if (is.null(value)) return(NULL)
  if (!is.numeric(value) || length(value) != 1L || !is.finite(value)) {
    abort(soilhub_argument_error(
      sprintf("`%s` must be NULL or one number, not %s.", argument, deparse_argument(value)),
      argument
    ))
  }
  as.numeric(value)
}

# Optional instant: POSIXct, Date or ISO 8601 text -> ISO 8601 text (UTC).
check_instant <- function(value, argument) {
  if (is.null(value)) return(NULL)
  bad <- function() {
    abort(soilhub_argument_error(
      sprintf(
        "`%s` must be NULL, a date-time (POSIXct), a Date or ISO 8601 text such as \"2024-01-01T00:00:00Z\", not %s.",
        argument, deparse_argument(value)
      ),
      argument
    ))
  }
  if (length(value) != 1L) bad()
  if (inherits(value, "Date")) {
    if (is.na(value)) bad()
    return(format(value, "%Y-%m-%dT00:00:00Z"))
  }
  if (inherits(value, "POSIXt")) {
    if (is.na(value)) bad()
    return(format(as.POSIXct(value), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  }
  if (is_string(value) && !is.na(parse_api_time(value))) return(value)
  bad()
}

# The geometry column of a values or health page (GeoJSON parsed as lists):
# dropped with "none", GeoJSON text in `geometry_text` with "text".
thematic_geometry <- function(frame, with_geometry) {
  pos <- match("geometry", names(frame))
  if (is.na(pos)) return(frame)
  if (identical(with_geometry, "none")) {
    frame[["geometry"]] <- NULL
    return(frame)
  }
  text <- vapply(frame[["geometry"]], function(geometry) {
    if (is.null(geometry)) return(NA_character_)
    as.character(jsonlite::toJSON(geometry, auto_unbox = TRUE, digits = NA))
  }, character(1))
  names(frame)[pos] <- "geometry_text"
  frame[[pos]] <- text
  frame
}

# `with_geometry` of the thematic reads; "sf" waits for the sf conversion of
# the geometry module (design 5.5), as for soil_observations().
check_with_geometry <- function(with_geometry) {
  with_geometry <- check_option(with_geometry, c("none", "sf", "text"), "with_geometry")
  if (identical(with_geometry, "sf")) {
    abort(soilhub_argument_error(
      "`with_geometry = \"sf\"` is not available in this version of soilhub yet: use `with_geometry = \"text\"` (GeoJSON).",
      "with_geometry"
    ))
  }
  with_geometry
}

# Request body: NULL fields dropped, vectors sent as JSON arrays.
thematic_body <- function(...) {
  body <- list(...)
  body <- body[!vapply(body, is.null, logical(1))]
  arrays <- vapply(body, function(value) is.atomic(value) && !inherits(value, "AsIs") && length(value) >= 1L, logical(1))
  arrays <- arrays & !names(body) %in% thematic_scalars
  body[arrays] <- lapply(body[arrays], I)
  body
}
thematic_scalars <- c(
  "valid_at", "depth_top_cm", "depth_bottom_cm", "include_geometry",
  "include_lineage", "include_details", "geometry", "layer", "view",
  "components", "min_cumulative_percent", "canonical"
)

# The metadata of a single (not paged) response, in the shape of
# soil_metadata() of a read (design 5.4).
response_metadata <- function(soil, response, endpoint, request, selection = NULL) {
  meta <- if (is.list(response$metadata)) response$metadata else list()
  capabilities <- tryCatch(session_cached(soil, "capabilities"), error = function(e) NULL)
  meta[c("limit", "offset", "returned_count", "has_more", "request_id")] <- NULL
  attr(request, "selection") <- NULL
  added <- list(
    endpoint = endpoint,
    request = request,
    selection = selection,
    request_ids = attr(response, "request_id") %||% NA_character_,
    api_version = if (is.list(capabilities) && is_string(capabilities$api_version)) capabilities$api_version else NA_character_,
    schema_version = scalar_chr(meta$schema_version),
    client_version = client_version(),
    retrieved_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    complete = TRUE,
    warnings = as.character(unlist(meta$warnings)) %||% character()
  )
  for (name in names(added)) meta[name] <- list(added[[name]])
  meta
}

# The metadata of a paged thematic read.
pages_metadata <- function(soil, pages) {
  meta <- pages$metadata
  capabilities <- tryCatch(session_cached(soil, "capabilities"), error = function(e) NULL)
  meta$api_version <- if (is.list(capabilities) && is_string(capabilities$api_version)) capabilities$api_version else NA_character_
  meta$client_version <- client_version()
  meta$schema_version <- scalar_chr(meta$schema_version)
  meta
}

# A failure after some pages: the pages read become a typed result.
with_typed_pages <- function(error, build) {
  if (inherits(error$partial, "soilhub_pages")) {
    typed <- tryCatch(build(error$partial), error = function(e) NULL)
    if (!is.null(typed)) error$partial <- typed
  }
  error
}

# Read every page of a thematic endpoint; a failure keeps the typed pages.
collect_typed <- function(soil, path, body, items, max_rows, progress, build, method = "POST") {
  pages <- tryCatch(
    soil_collect(soil, path, body, items = items, max_rows = max_rows,
                 progress = progress, method = method),
    soilhub_error = function(e) abort(with_typed_pages(e, build))
  )
  build(pages)
}
