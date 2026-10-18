#' @include typing.R
NULL

# Typing of the wide layout (design 5.2; decision 8 a1): the rows of the
# pages of `POST /query/observations` with `layout = "wide"` become one typed
# data frame. Pure functions, no network.
#
# Column families and R types:
#   fixed columns                       character / integer / double
#   layer = "first"                     first_layer_status character,
#                                       profile_markings list of character
#   component columns (SOTWIS, SOTER)   double / logical / integer / character
#   source attributes                   character, verbatim
#   raw markings                        texture_sum double; consistency_flags,
#                                       also_in_datasets list of character;
#                                       possible_profile, superseded_by
#                                       character; cell_markings list of named
#                                       lists (column -> markings)
#   value_flags                         list of named lists (column -> flags)
#   retirement                          retired_in_release character,
#                                       retired_cells list of named character
#   revised_markings (view = revised)   list of named lists: hidden_values a
#                                       data frame, cells a named list
#   geometry (with_geometry = "text")   geometry_kind, geometry_text (WKT)
#   variable groups                     <key> double when the column is
#                                       numeric on every page, else character;
#                                       <key>_units, <key>_method character;
#                                       <key>_n integer; <key>_values list of
#                                       character (multi-value cells only)
#
# Multi-value cells (decision 8): a WoSIS cell holding a JSON list of values
# arrives as its JSON text (the API does not aggregate). `<key>` receives the
# mean of the listed values (the value WoSIS publishes; NA when an element is
# not a number), `<key>_values` every original element verbatim (NULL for the
# other cells). The rule is recorded as `multi_value_rule = "mean"`.

wide_column_types <- c(
  # fixed
  dataset = "chr", provider_code = "chr", feature_id = "chr", profile_id = "chr",
  component_id = "chr", component_rank = "int", horizon_id = "chr",
  horizon_name = "chr", upper_depth_cm = "dbl", lower_depth_cm = "dbl",
  source_support = "chr", release_code = "chr",
  # layer = "first"
  first_layer_status = "chr", profile_markings = "chr_list",
  # components (SOTWIS, SOTER polygons)
  proportion_percent = "dbl", soil_code = "chr", representative_profile_id = "chr",
  cumulative_proportion_percent = "dbl", is_representative = "lgl", suid = "int",
  newsuid = "chr", isoc = "chr", soil_map_unit = "chr", tcid = "int", scid = "int",
  terrain_proportion_percent = "dbl", tcdc = "chr", linked_profile_feature_id = "chr",
  profile_inside_polygon = "lgl",
  # source records and attributes
  source_profile_type = "chr", source_record_note = "chr",
  # raw markings
  texture_sum = "dbl", consistency_flags = "chr_list", also_in_datasets = "chr_list",
  possible_profile = "chr", superseded_by = "chr", cell_markings = "cell_markings",
  value_flags = "value_flags",
  # retirement
  retired_in_release = "chr", retired_cells = "retired_cells",
  # view = "revised"
  revised_markings = "revised_markings",
  # geometry_format = "wkt"
  geometry_kind = "chr"
)
wide_fixed_columns <- c(
  "dataset", "provider_code", "feature_id", "profile_id", "component_id",
  "component_rank", "horizon_id", "horizon_name", "upper_depth_cm",
  "lower_depth_cm", "source_support", "release_code"
)
wide_attribute_prefixes <- c("profile_attr_", "horizon_attr_")
wide_companion_suffixes <- c("_units", "_method", "_n")
numeric_text_pattern <- "^-?[0-9]+(\\.[0-9]+)?([eE][-+]?[0-9]+)?$"
wide_context <- "POST /query/observations (wide)"

hidden_values_schema <- list(property_code = "chr", rule = "chr", source_value = "json")

# Sort as the API does (code points), NULL-safe.
sort_chr <- function(x) sort(as.character(x), method = "radix")

# The type of a non-variable column; NULL when unknown to the client.
wide_column_type <- function(name) {
  type <- wide_column_types[name]
  if (!is.na(type)) return(unname(type))
  if (any(startsWith(name, wide_attribute_prefixes))) return("chr")
  NULL
}

#' Merge `metadata.variables` of the wide pages
#'
#' @param page_metadata The metadata of every page.
#' @return A data frame, one row per variable column sorted by name:
#'   `column`, `property_key`, `numeric` (TRUE when numeric on every page that
#'   had cells of it), `units`, `source_codes` (lists of character),
#'   `horizon_count`, `multi_value_cells` (integer, summed over pages),
#'   `methods` (list of named character: method code -> description),
#'   `source_notes` (list of data frames `dataset`, `source_code`,
#'   `source_notes`) and `method_facets` (list of named lists of character).
#' @keywords internal
#' @noRd
merge_wide_variables <- function(page_metadata) {
  entries <- list()
  for (meta in page_metadata) {
    for (item in meta$variables %||% list()) {
      column <- scalar_chr(item$column)
      if (is.na(column)) next
      entries[[column]] <- c(entries[[column]], list(item))
    }
  }
  columns <- sort_chr(names(entries))
  chr_union <- function(items, field) {
    values <- unlist(lapply(items, function(item) unlist(item[[field]])), use.names = FALSE)
    sort_chr(unique(values))
  }
  merged <- lapply(columns, function(column) {
    items <- entries[[column]]
    with_cells <- Filter(function(item) isTRUE(as.numeric(item$horizon_count %||% 0) > 0), items)
    numeric_flags <- vapply(with_cells, function(item) !isFALSE(item$numeric), logical(1))
    keys <- unlist(lapply(items, function(item) item$property_key), use.names = FALSE)
    methods <- list()
    for (item in items) {
      for (code in names(item$methods)) {
        if (is.null(methods[[code]])) methods[[code]] <- scalar_chr(item$methods[[code]])
      }
    }
    methods <- unlist(methods[sort_chr(names(methods))]) %||% stats::setNames(character(), character())
    notes <- unique(unlist(lapply(items, function(item) item$source_notes), recursive = FALSE))
    facets <- list()
    for (item in items) {
      for (key in names(item$method_facets)) {
        facets[[key]] <- sort_chr(unique(c(facets[[key]], vapply(item$method_facets[[key]], scalar_chr, character(1)))))
      }
    }
    list(
      column = column,
      property_key = if (length(keys)) as.character(keys[[1]]) else NA_character_,
      numeric = all(numeric_flags),
      units = chr_union(items, "units"),
      source_codes = chr_union(items, "source_codes"),
      horizon_count = as.integer(sum(vapply(items, function(item) as.numeric(item$horizon_count %||% 0), numeric(1)))),
      multi_value_cells = as.integer(sum(vapply(items, function(item) as.numeric(item$multi_value_cells %||% 0), numeric(1)))),
      methods = methods,
      source_notes = records_frame(notes, list(dataset = "chr", source_code = "chr", source_notes = "chr")),
      method_facets = stats::setNames(facets[sort_chr(names(facets))], sort_chr(names(facets)))
    )
  })
  field <- function(name, fun) fun(lapply(merged, `[[`, name))
  new_frame(
    list(
      column = field("column", function(x) as.character(unlist(x)) %||% character()),
      property_key = field("property_key", function(x) as.character(unlist(x)) %||% character()),
      numeric = field("numeric", function(x) as.logical(unlist(x)) %||% logical()),
      units = field("units", identity),
      source_codes = field("source_codes", identity),
      horizon_count = field("horizon_count", function(x) as.integer(unlist(x)) %||% integer()),
      multi_value_cells = field("multi_value_cells", function(x) as.integer(unlist(x)) %||% integer()),
      methods = field("methods", identity),
      source_notes = field("source_notes", identity),
      method_facets = field("method_facets", identity)
    ),
    length(merged)
  )
}

#' Wide pages to a typed data frame
#'
#' @param pages A `soilhub_pages` of wide pages (complete or partial).
#' @param variables The merged variables (`merge_wide_variables()`).
#' @param with_geometry `"none"` or `"text"`: `"text"` adds `geometry_text`
#'   (the WKT of the row's feature, from the `geometries` of the pages).
#' @return A data frame (columns in API order: the non-variable columns, then
#'   `geometry_text`, then the variable groups sorted by name).
#' @keywords internal
#' @noRd
wide_frame <- function(pages, variables = merge_wide_variables(pages$page_metadata),
                       with_geometry = "none") {
  rows <- lapply(pages$items %||% list(), function(row) if (is.list(row)) row else list())
  n <- length(rows)
  values_of <- function(name) lapply(rows, function(row) row[[name]])

  var_columns <- variables$column
  group_names <- c(var_columns, unlist(lapply(wide_companion_suffixes, function(s) paste0(var_columns, s))))
  fields <- unique(unlist(lapply(rows, names), use.names = FALSE))
  other <- setdiff(fields, group_names)
  if (n == 0L) other <- union(wide_fixed_columns, other)

  unknown <- other[vapply(other, function(name) is.null(wide_column_type(name)), logical(1))]
  if (length(unknown)) report_drift(wide_context, unknown, character())

  columns <- list()
  for (name in other) {
    type <- wide_column_type(name)
    values <- values_of(name)
    columns[[name]] <- if (is.null(type)) values else type_wide_values(values, type)
  }

  if (identical(with_geometry, "text")) {
    columns$geometry_text <- wide_geometry_text(pages, columns$feature_id %||% character())
  }

  for (i in seq_along(var_columns)) {
    column <- var_columns[[i]]
    multi <- isTRUE(variables$multi_value_cells[[i]] > 0)
    typed <- type_variable_values(values_of(column), numeric = isTRUE(variables$numeric[[i]]), multi = multi)
    columns[[column]] <- typed$value
    columns[[paste0(column, "_units")]] <- type_column(values_of(paste0(column, "_units")), "chr")
    columns[[paste0(column, "_method")]] <- type_column(values_of(paste0(column, "_method")), "chr")
    columns[[paste0(column, "_n")]] <- type_column(values_of(paste0(column, "_n")), "int")
    if (multi) columns[[paste0(column, "_values")]] <- typed$values
  }
  new_frame(columns, n)
}

type_wide_values <- function(values, type) {
  switch(type,
    cell_markings = lapply(values, function(v) if (is.null(v)) NULL else simplify_json(v)),
    value_flags = lapply(values, function(v) {
      if (is.null(v)) return(NULL)
      lapply(v, function(flags) vapply(flags, scalar_chr, character(1), USE.NAMES = FALSE))
    }),
    retired_cells = lapply(values, function(v) {
      if (is.null(v)) return(NULL)
      vapply(v, scalar_chr, character(1))
    }),
    revised_markings = lapply(values, type_revised_markings),
    type_column(values, type)
  )
}

# revised_markings of a row: horizon markings as parsed, `hidden_values` a
# data frame (property_code, rule, source_value verbatim), `cells` a named
# list (column -> cell markings).
type_revised_markings <- function(value) {
  if (is.null(value)) return(NULL)
  out <- lapply(names(value), function(name) {
    item <- value[[name]]
    if (identical(name, "hidden_values")) return(records_frame(item, hidden_values_schema))
    simplify_json(item)
  })
  names(out) <- names(value)
  out
}

# Parsed JSON with arrays of scalars as atomic vectors (objects stay named
# lists, nulls NULL).
simplify_json <- function(x) {
  if (!is.list(x)) return(x)
  if (length(x) && is.null(names(x))) {
    scalar <- vapply(x, function(e) !is.null(e) && !is.list(e) && length(e) == 1L, logical(1))
    if (all(scalar)) {
      kinds <- unique(vapply(x, function(e) class(e)[1], character(1)))
      if (length(kinds) == 1L) return(unlist(x, use.names = FALSE))
      if (all(kinds %in% c("integer", "numeric"))) return(as.numeric(unlist(x, use.names = FALSE)))
      return(vapply(x, scalar_chr, character(1)))
    }
  }
  out <- lapply(x, simplify_json)
  names(out) <- names(x)
  out
}

# The elements of a multi-value cell (JSON text of an array of two or more
# values), verbatim as character; NULL for any other value.
multi_value_elements <- function(value) {
  if (!is.character(value) || length(value) != 1L || is.na(value)) return(NULL)
  if (!grepl("^\\s*\\[", value)) return(NULL)
  parsed <- tryCatch(jsonlite::fromJSON(value, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(parsed) || !is.null(names(parsed)) || length(parsed) < 2L) return(NULL)
  vapply(parsed, scalar_chr, character(1), USE.NAMES = FALSE)
}

# The number of a value as the API reads one (a JSON number or a numeric
# string); NA otherwise.
as_api_number <- function(value) {
  if (is.null(value) || length(value) != 1L || is.list(value)) return(NA_real_)
  if (is.numeric(value)) return(as.numeric(value))
  if (is.character(value) && !is.na(value) && grepl(numeric_text_pattern, value)) {
    return(as.numeric(value))
  }
  NA_real_
}

# The mean of the elements of a multi-value cell; NA when one is not a number.
multi_value_mean <- function(elements) {
  numbers <- vapply(elements, as_api_number, numeric(1))
  if (anyNA(numbers)) NA_real_ else mean(numbers)
}

# A variable column: `value` (double when numeric, else character) and, when
# the column has multi-value cells, `values` (list of character, NULL for a
# single-value cell).
type_variable_values <- function(values, numeric, multi) {
  elements <- if (multi) lapply(values, multi_value_elements) else vector("list", length(values))
  if (numeric) {
    value <- vapply(seq_along(values), function(i) {
      if (!is.null(elements[[i]])) return(multi_value_mean(elements[[i]]))
      as_api_number(values[[i]])
    }, numeric(1))
  } else {
    value <- vapply(values, scalar_chr, character(1), USE.NAMES = FALSE)
  }
  list(value = value, values = if (multi) elements else NULL)
}

# geometry_text: the WKT of each row's feature (one per feature_id in the
# `geometries` of the pages); NA with one warning for rows without one.
wide_geometry_text <- function(pages, feature_id) {
  geometries <- list()
  for (extra in pages$extras %||% list()) {
    page <- extra$geometries
    for (id in names(page)) {
      if (is.null(geometries[[id]])) geometries[[id]] <- scalar_chr(page[[id]])
    }
  }
  text <- vapply(feature_id, function(id) {
    if (is.na(id) || is.null(geometries[[id]])) NA_character_ else geometries[[id]]
  }, character(1), USE.NAMES = FALSE)
  missing <- is.na(text)
  if (any(missing)) {
    soilhub_warning(sprintf(
      paste0(
        "%s row(s) of %s feature(s) have no geometry (for example WISE profiles without ",
        "coordinates): their geometry_text is NA."
      ),
      format_count(sum(missing)), format_count(length(unique(feature_id[missing])))
    ), "soilhub_geometry_warning")
  }
  text
}
