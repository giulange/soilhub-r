#' @include typing-wide.R
NULL

# The `soil_table` class (design 5.1, 5.4) and the result helpers (4.7):
# accessors of the metadata attribute, the typing of the variable columns,
# the value flags, the markings, the revised rules and the first-layer
# vocabulary. No network.

new_soil_table <- function(frame, metadata, layout) {
  attr(frame, "soil_metadata") <- metadata
  attr(frame, "soil_layout") <- layout
  # An sf frame keeps sf's class in front of data.frame (design 5.1).
  class(frame) <- if (inherits(frame, "sf")) c("soil_table", "sf", "data.frame") else c("soil_table", "data.frame")
  frame
}

#' Tables returned by the reads
#'
#' Reads such as [soil_observations()] return a `soil_table`: a
#' `data.frame` (or an `sf` object, with `sf`'s class kept in front of
#' `data.frame`) whose class starts with `"soil_table"`, with two
#' attributes:
#'
#' * `soil_metadata`, read with [soil_metadata()]: the request sent, the
#'   request ids of the pages, whether the read is complete, the API
#'   warnings, the typing of the variable columns ([soil_columns()]), the
#'   view and the revised rules applied ([soil_revised_rules()]), the
#'   first-layer vocabulary ([soil_first_layer()]), the catalog rows of the
#'   datasets (for [soil_citations()]);
#' * `soil_layout`: `"wide"`, `"long"`, `"features"`, `"values"` or
#'   `"health"`.
#'
#' Subsetting with `[` keeps the class and the attributes; [as.data.frame()]
#' drops them (and the `sf` class: the `geometry` column stays). Rows are in
#' the API's order (the stable order of the pages).
#'
#' Printing shows a two-line header (counts, datasets, view and layer;
#' warnings and the helpers to use) and the first
#' `getOption("soilhub.print_rows", 10)` rows, list columns as `<list>`.
#' [summary()] shows the typing of the variable columns, the rows per
#' dataset and, with `view = "revised"`, the rules applied with their counts.
#'
#' @param x,object A `soil_table`.
#' @param ... As for a data frame (`[`); unused otherwise.
#' @param row.names,optional Unused (the row names are kept).
#' @param n Rows to print.
#' @name soil_table
#' @family results
NULL

#' @rdname soil_table
#' @export
`[.soil_table` <- function(x, ...) {
  metadata <- attr(x, "soil_metadata")
  layout <- attr(x, "soil_layout")
  classes <- class(x)
  # `[.data.frame` with exactly the arguments the caller wrote (it decides
  # on `drop` from their number).
  out <- NextMethod()
  if (!is.data.frame(out)) return(out)
  attr(out, "soil_metadata") <- metadata
  attr(out, "soil_layout") <- layout
  class(out) <- classes
  out
}

#' @rdname soil_table
#' @export
as.data.frame.soil_table <- function(x, row.names = NULL, optional = FALSE, ...) {
  attr(x, "soil_metadata") <- NULL
  attr(x, "soil_layout") <- NULL
  attr(x, "sf_column") <- NULL
  attr(x, "agr") <- NULL
  class(x) <- setdiff(class(x), c("soil_table", "sf"))
  if (!inherits(x, "data.frame")) class(x) <- "data.frame"
  x
}

#' @rdname soil_table
#' @export
print.soil_table <- function(x, n = getOption("soilhub.print_rows", 10), ...) {
  cat(table_header(x), sep = "\n")
  frame <- as.data.frame(x)
  shown <- utils::head(frame, n)
  for (name in names(shown)) {
    if (inherits(shown[[name]], "sfc")) {
      shown[[name]] <- format(shown[[name]])
    } else if (is.list(shown[[name]]) && !is.data.frame(shown[[name]])) {
      shown[[name]] <- vapply(shown[[name]], function(v) if (is.null(v)) NA_character_ else "<list>", character(1))
    }
  }
  if (nrow(shown)) {
    print(shown, ...)
    if (nrow(frame) > nrow(shown)) {
      cat(sprintf("# ... %s more row(s)\n", format_count(nrow(frame) - nrow(shown))))
    }
  } else {
    cat("# no rows\n")
  }
  invisible(x)
}

table_header <- function(x) {
  metadata <- soil_metadata(x)
  layout <- attr(x, "soil_layout") %||% "?"
  request <- metadata$request %||% list()
  datasets <- unique(stats::na.omit(x[["dataset"]] %||% x[["dataset_code"]]))
  if (!length(datasets)) datasets <- unlist(request$datasets) %||% character()
  thematic <- layout %in% c("values", "health")
  noun <- switch(layout, wide = "horizons", long = "observations", features = "features", "rows")
  counts <- sprintf("%s %s", format_count(nrow(x)), noun)
  if (!is.null(x$feature_id) && !identical(layout, "features")) {
    counts <- paste0(counts, sprintf(", %s features", format_count(length(unique(stats::na.omit(x$feature_id))))))
  }
  if (is.data.frame(metadata$variables)) {
    counts <- paste0(counts, sprintf(", %s variables", format_count(nrow(metadata$variables))))
  }
  view <- metadata$view %||% request$view %||% "raw"
  layer <- request$layer %||% "all"
  first <- sprintf(
    "# soilhub %s table: %s | %s%s",
    layout, counts,
    if (length(datasets)) paste(datasets, collapse = ", ") else "no dataset",
    if (thematic) "" else if (identical(layout, "features")) sprintf(" | view %s", view) else sprintf(" | view %s, layer %s", view, layer)
  )
  warnings <- length(metadata$warnings %||% character())
  second <- sprintf(
    "# %s API warning%s (soil_warnings), %scite with soil_citations()",
    if (warnings) format_count(warnings) else "no", if (warnings == 1L) "" else "s",
    if (thematic) "" else switch(layout, wide = "typing (soil_columns), ", long = "markings (soil_markings), ", "")
  )
  lines <- c(first, second)
  if (identical(layout, "long") && !is.null(metadata$total_count) && !is.na(metadata$total_count)) {
    lines[1] <- paste0(lines[1], sprintf(" | %s in the selection", format_count(metadata$total_count)))
  }
  if (isFALSE(metadata$complete)) {
    lines <- c(lines, sprintf(
      "# incomplete read: continue with offset = %s (soil_metadata(x)$next_offset)",
      format(metadata$next_offset, scientific = FALSE)
    ))
  }
  lines
}

#' @rdname soil_table
#' @export
summary.soil_table <- function(object, ...) {
  metadata <- soil_metadata(object)
  # `[[`: `$` of a data frame would partially match `dataset_code`
  dataset <- object[["dataset"]] %||% object[["dataset_code"]]
  datasets <- if (!is.null(dataset) && nrow(object)) {
    counts <- table(dataset)
    new_frame(list(dataset = names(counts), rows = as.integer(counts)), length(counts))
  } else {
    new_frame(list(dataset = character(), rows = integer()), 0L)
  }
  structure(
    list(
      header = table_header(object),
      columns = if (is.data.frame(metadata$variables)) metadata$variables else NULL,
      datasets = datasets,
      revised_rules = if (identical(metadata$view, "revised")) soil_revised_rules(object) else NULL
    ),
    class = "soil_table_summary"
  )
}

#' @export
print.soil_table_summary <- function(x, ...) {
  cat(x$header, sep = "\n")
  if (is.data.frame(x$columns)) {
    cat("\nVariable columns (soil_columns):\n")
    if (nrow(x$columns)) {
      shown <- x$columns[, c("column", "property_key", "numeric", "horizon_count", "multi_value_cells")]
      shown$units <- vapply(x$columns$units, function(u) paste(u, collapse = ", "), character(1))
      print(shown, row.names = FALSE)
    } else {
      cat("  none\n")
    }
  }
  cat("\nRows per dataset:\n")
  print(x$datasets, row.names = FALSE)
  if (is.data.frame(x$revised_rules)) {
    cat("\nRevised rules applied (soil_revised_rules):\n")
    if (nrow(x$revised_rules)) {
      print(x$revised_rules[, c("id", "effect", "n")], row.names = FALSE)
    } else {
      cat("  none in this selection\n")
    }
  }
  invisible(x)
}

# ---------------------------------------------------------------------------
# Accessors.

result_metadata <- function(x) {
  metadata <- attr(x, "soil_metadata")
  if (is.null(metadata) && is.list(x) && !is.data.frame(x) && is.list(x$metadata)) {
    metadata <- x$metadata
  }
  if (!is.list(metadata)) {
    abort(soilhub_argument_error(
      "`x` must be a result of soilhub (a soil_table, a summary or an export).",
      "x"
    ))
  }
  metadata
}

#' Metadata and warnings of a result
#'
#' `soil_metadata()` returns what the API and the client recorded about a
#' read: `request` (the body sent) and `endpoint`, `api_version`,
#' `schema_version`, `client_version`, `retrieved_at` (UTC), `request_ids`
#' (one per page, quote them when reporting a problem), `pages`, `complete`
#' (`FALSE` for a partial result) and `next_offset` (the offset to continue
#' from), `total_count` (`NA` for the wide layout: the API does not count),
#' `warnings`, `variables` (see [soil_columns()]), `view` and `revised` (see
#' [soil_revised_rules()]), `first_layer` (see [soil_first_layer()]),
#' `components` and `min_cumulative_percent` (when a component dataset is
#' selected), `crs`, `datasets` (the catalog rows of the datasets read: what
#' [soil_citations()] reads) and `multi_value_rule` (`"mean"`: the value of a
#' multi-value WoSIS cell in the numeric column).
#'
#' `soil_warnings()` returns the warnings of the API over all pages, once
#' each: mixed units in a column, multi-value cells, renamed columns,
#' collapsed duplicate measurements, component ties, component proportions
#' not summing to 100.
#'
#' @param x A `soil_table` (or a summary or export result).
#' @return `soil_metadata()`: a list. `soil_warnings()`: a character vector.
#' @family results
#' @examples
#' \dontrun{
#' x <- soil_observations(soil, datasets = "wosis_points", country = "KEN")
#' soil_metadata(x)$request_ids
#' soil_warnings(x)
#' }
#' @export
soil_metadata <- function(x) {
  result_metadata(x)
}

#' @rdname soil_metadata
#' @export
soil_warnings <- function(x) {
  as.character(unlist(result_metadata(x)$warnings)) %||% character()
}

#' Typing of the variable columns of a wide table
#'
#' One row per variable column of a wide [soil_observations()] read, from
#' the `metadata.variables` of the API merged over the pages: the canonical
#' property key (`organic_carbon`; `src_<code>` columns have none), whether
#' the column is numeric (`numeric = FALSE`: the column holds the source text
#' verbatim), the source units, the source codes, the horizons with a value,
#' the multi-value cells (WoSIS cells listing several values: the column
#' holds their mean, the `<key>_values` column every original value), the
#' laboratory methods, the notes of the source mappings and the method
#' facets of the multi-value cells.
#'
#' @param x A wide `soil_table`.
#' @return A data frame `column`, `property_key`, `numeric`, `units` (list),
#'   `source_codes` (list), `horizon_count`, `multi_value_cells`, `methods`
#'   (list of named character: method code -> description), `source_notes`
#'   (list of data frames `dataset`, `source_code`, `source_notes`),
#'   `method_facets` (list of named lists).
#' @family results
#' @examples
#' \dontrun{
#' x <- soil_observations(soil, datasets = "wosis_points", country = "KEN")
#' cols <- soil_columns(x)
#' cols[cols$multi_value_cells > 0, c("column", "multi_value_cells")]
#' }
#' @export
soil_columns <- function(x) {
  variables <- result_metadata(x)$variables
  if (!is.data.frame(variables)) {
    abort(soilhub_argument_error(
      "`x` has no typing of variable columns: soil_columns() works on wide reads.",
      "x"
    ))
  }
  variables
}

#' Value flags of a table
#'
#' The `value_flags` column of a wide or long read as a long data frame: one
#' row per flag of a cell (of an observation in the long layout). Flags are markings computed by the API in both views
#' (`trace_convention`, `method_label_contradicted`, `uniform_profile_value`,
#' `extreme`, `above_unit_maximum`, `impossible_for_declared_unit`); they
#' change no value.
#'
#' @param x A `soil_table` with a `value_flags` column.
#' @return A data frame `row` (row number in `x`), `horizon_id`, `column`
#'   (the variable column; in the long layout the `property_code` of the
#'   row), `flag`.
#' @family results
#' @examples
#' \dontrun{
#' soil_flags(x)
#' }
#' @export
soil_flags <- function(x) {
  check_table(x)
  out <- list()
  flags <- x[["value_flags"]]
  long <- identical(attr(x, "soil_layout"), "long")
  for (i in seq_along(flags)) {
    cell <- flags[[i]]
    if (long) {
      for (flag in cell) out[[length(out) + 1L]] <- list(i, x$horizon_id[[i]], x$property_code[[i]], flag)
      next
    }
    for (column in names(cell)) {
      for (flag in cell[[column]]) out[[length(out) + 1L]] <- list(i, x$horizon_id[[i]], column, flag)
    }
  }
  long_frame(out, c("row", "horizon_id", "column", "flag"), c("int", "chr", "chr", "chr"))
}

#' Markings of a table
#'
#' Every marking of a wide read as a long data frame: the raw markings of
#' the cells (`cell_markings`: `value_count`, `methods_differ`,
#' `value_spread`, `source_method_kind`, `method_facets` of WoSIS cells
#' listing several values), of the layers (`texture_sum`,
#' `consistency_flags`), of the profiles (`also_in_datasets`,
#' `possible_profile`, `superseded_by`, and with `layer = "first"` the
#' `profile_markings`), the retirement of cells (`retired_cells`) and, with
#' `view = "revised"`, the revised markings of the horizons, of the cells and
#' the values a revised rule did not return (`hidden_values`). Markings
#' change no row and no value: they describe them.
#'
#' A marking holding several values gives one row per value; an object
#' (such as `method_facets`) gives one row with its JSON text.
#'
#' In the long layout the cell markings are columns of the row (`column` is
#' its `property_code`), the layer and profile markings repeat on every
#' observation of the horizon, and `revised_markings` mixes the horizon
#' markings with those of the cell (`texture_normalized`,
#' `guessed_elements_removed`, `value_from_estimates`, `kept_from_copy`,
#' `values_differ`: scope `"revised_cell"`).
#'
#' @param x A `soil_table`.
#' @return A data frame `row` (row number in `x`), `horizon_id`, `scope`
#'   (`"cell"`, `"layer"`, `"profile"`, `"retired_cell"`, `"revised_horizon"`,
#'   `"revised_cell"`, `"hidden_value"`), `column` (the variable column, or
#'   the source property code of a hidden value; `NA` for a row marking),
#'   `marking` (the marking name, or the rule of a hidden value) and `value`
#'   (character).
#' @family results
#' @examples
#' \dontrun{
#' m <- soil_markings(x)
#' m[m$scope == "hidden_value", ]
#' }
#' @export
soil_markings <- function(x) {
  check_table(x)
  out <- list()
  add <- function(i, scope, column, marking, value) {
    for (v in marking_values(value)) {
      out[[length(out) + 1L]] <<- list(i, x$horizon_id[[i]], scope, column, marking, v)
    }
  }
  long <- identical(attr(x, "soil_layout"), "long")
  for (i in seq_len(nrow(x))) {
    if (long) {
      long_row_markings(x, i, add)
      next
    }
    cells <- if (!is.null(x[["cell_markings"]])) x[["cell_markings"]][[i]] else NULL
    for (column in names(cells)) {
      for (marking in names(cells[[column]])) add(i, "cell", column, marking, cells[[column]][[marking]])
    }
    for (marking in c("texture_sum", "consistency_flags")) {
      if (!is.null(x[[marking]])) add(i, "layer", NA_character_, marking, x[[marking]][[i]])
    }
    for (marking in c("also_in_datasets", "possible_profile", "superseded_by", "profile_markings")) {
      if (!is.null(x[[marking]])) add(i, "profile", NA_character_, marking, x[[marking]][[i]])
    }
    retired <- if (!is.null(x[["retired_cells"]])) x[["retired_cells"]][[i]] else NULL
    for (column in names(retired)) add(i, "retired_cell", column, "retired_in_release", retired[[column]])
    revised <- if (!is.null(x[["revised_markings"]])) x[["revised_markings"]][[i]] else NULL
    for (name in names(revised)) {
      item <- revised[[name]]
      if (identical(name, "hidden_values") && is.data.frame(item)) {
        for (k in seq_len(nrow(item))) {
          add(i, "hidden_value", item$property_code[[k]], item$rule[[k]], list(item$source_value[[k]]))
        }
      } else if (identical(name, "cells")) {
        for (column in names(item)) {
          for (marking in names(item[[column]])) add(i, "revised_cell", column, marking, item[[column]][[marking]])
        }
      } else {
        add(i, "revised_horizon", NA_character_, name, item)
      }
    }
  }
  long_frame(out, c("row", "horizon_id", "scope", "column", "marking", "value"),
             c("int", "chr", "chr", "chr", "chr", "chr"))
}

# Markings of row `i` of a long table, passed to `add(i, scope, column,
# marking, value)`.
long_cell_markings <- c("value_count", "methods_differ", "value_spread", "source_method_kind", "method_facets")
long_revised_cell_markings <- c(
  "texture_normalized", "guessed_elements_removed", "value_from_estimates",
  "kept_from_copy", "values_differ"
)
long_row_markings <- function(x, i, add) {
  property <- if (!is.null(x[["property_code"]])) x[["property_code"]][[i]] else NA_character_
  # As the wide cell_markings of the API: value_count only above 1,
  # methods_differ only when true.
  for (marking in long_cell_markings) {
    if (is.null(x[[marking]])) next
    value <- x[[marking]][[i]]
    if (identical(marking, "value_count") && !isTRUE(value > 1)) next
    if (identical(marking, "methods_differ") && !isTRUE(value)) next
    add(i, "cell", property, marking, value)
  }
  for (marking in c("texture_sum", "consistency_flags")) {
    if (!is.null(x[[marking]])) add(i, "layer", NA_character_, marking, x[[marking]][[i]])
  }
  for (marking in c("also_in_datasets", "possible_profile", "superseded_by", "profile_markings")) {
    if (!is.null(x[[marking]])) add(i, "profile", NA_character_, marking, x[[marking]][[i]])
  }
  revised <- if (!is.null(x[["revised_markings"]])) x[["revised_markings"]][[i]] else NULL
  for (name in names(revised)) {
    item <- revised[[name]]
    if (identical(name, "hidden_values") && is.data.frame(item)) {
      for (k in seq_len(nrow(item))) {
        add(i, "hidden_value", item$property_code[[k]], item$rule[[k]], list(item$source_value[[k]]))
      }
    } else if (name %in% long_revised_cell_markings) {
      add(i, "revised_cell", property, name, item)
    } else {
      add(i, "revised_horizon", NA_character_, name, item)
    }
  }
}

# The values of a marking as character: one per element of an atomic vector,
# JSON text for an object or a wrapped value, none for NULL/NA.
marking_values <- function(value) {
  if (is.null(value) || (is.atomic(value) && length(value) == 1L && is.na(value))) return(character())
  if (is.atomic(value)) return(vapply(value, scalar_chr, character(1), USE.NAMES = FALSE))
  if (is.list(value) && is.null(names(value)) && length(value) == 1L) value <- value[[1]]
  if (is.null(value)) return(NA_character_)
  if (is.atomic(value) && length(value) == 1L) return(scalar_chr(value))
  as.character(jsonlite::toJSON(value, auto_unbox = TRUE, null = "null", digits = NA))
}

#' Revised rules applied to a result
#'
#' With `view = "revised"` the API applies the decided rules of the revised
#' view (R2 to R19 of the API documentation) in the response only, and lists
#' the rules that changed or flagged something in the selection with their
#' counts over the whole selection (every page, not only the rows read).
#' One row per rule and effect (`values_hidden`, `rows_hidden`,
#' `values_changed`, `values_flagged:<flag>`, ...).
#'
#' @param x A `soil_table` read with `view = "revised"` (or a summary or an
#'   export of the revised view).
#' @return A data frame `id`, `title`, `issue`, `effect`, `n` (zero rows for
#'   the raw view). Its attribute `pairs` holds the spellings linked by R6
#'   (SOTWIS PRID linked without case), when listed; `pending` and
#'   `unchanged` the rules not applied and the rules whose revised view
#'   equals the raw one; `scope` what the counts cover.
#' @family results
#' @examples
#' \dontrun{
#' x <- soil_observations(soil, datasets = "wise_profiles", view = "revised")
#' soil_revised_rules(x)
#' attr(soil_revised_rules(x), "pairs")
#' }
#' @export
soil_revised_rules <- function(x) {
  revised <- result_metadata(x)$revised
  out <- list()
  pairs <- NULL
  for (rule in revised$rules %||% list()) {
    counts <- rule$counts %||% list()
    if (!is.null(rule$pairs)) pairs <- rule$pairs
    if (length(counts) == 0L) {
      out[[length(out) + 1L]] <- list(rule$id, rule$title, rule$issue, NA_character_, NA_real_)
    }
    for (effect in names(counts)) {
      out[[length(out) + 1L]] <- list(rule$id, rule$title, rule$issue, effect, counts[[effect]])
    }
  }
  frame <- long_frame(out, c("id", "title", "issue", "effect", "n"), c("chr", "chr", "chr", "chr", "dbl"))
  attr(frame, "pairs") <- if (is.null(pairs)) NULL else records_frame(pairs, list(
    source_dataset_name = "chr", source_record_id = "chr", CLAF = "chr",
    summary_prid = "chr", estimate_prid = "chr", summary_profiles = "dbl"
  ))
  attr(frame, "pending") <- revised$pending
  attr(frame, "unchanged") <- revised$unchanged
  attr(frame, "scope") <- revised$scope
  frame
}

#' First-layer vocabulary of a table
#'
#' With `layer = "first"` the API keeps only the first horizon(s) of each
#' profile (of each selected component for SOTWIS and SOTER polygons) and adds
#' the columns `first_layer_status` (`surface`, `tie`, `not_surface`,
#' `depth_missing`; with `view = "revised"` also `surface_within_5cm` and
#' `first_mineral`) and `profile_markings` (`negative_depth_above`,
#' `empty_row`, `depth_order_conflict`, `numbering_starts_at_<N>`,
#' `numbering_gap`). This returns the vocabulary the API reported for the
#' read.
#'
#' @param x A `soil_table` read with `layer = "first"`.
#' @return A list `view`, `statuses` (character), `profile_markings`
#'   (character); `NULL` when `x` was not read with `layer = "first"`.
#' @family results
#' @examples
#' \dontrun{
#' x <- soil_observations(soil, datasets = "soter_profiles", layer = "first")
#' soil_first_layer(x)
#' table(x$first_layer_status)
#' }
#' @export
soil_first_layer <- function(x) {
  first <- result_metadata(x)$first_layer
  if (!is.list(first)) return(NULL)
  list(
    view = scalar_chr(first$view),
    statuses = vapply(first$statuses %||% list(), scalar_chr, character(1)),
    profile_markings = vapply(first$profile_markings %||% list(), scalar_chr, character(1))
  )
}

check_table <- function(x) {
  if (!is.data.frame(x)) {
    abort(soilhub_argument_error("`x` must be a soil_table (a read of soilhub).", "x"))
  }
  invisible(x)
}

# Rows (lists of scalars) to a data frame of the given names and types.
long_frame <- function(rows, names, types) {
  columns <- lapply(seq_along(names), function(k) {
    values <- lapply(rows, `[[`, k)
    type_column(values, types[[k]])
  })
  names(columns) <- names
  new_frame(columns, length(rows))
}
