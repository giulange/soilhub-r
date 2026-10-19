#' @include typing-wide.R geometry.R
NULL

# Typing of the long layout (design 5.3; decision 8 a1): the observations of
# the pages of `POST /query/observations` with `layout = "long"` become one
# typed data frame, one row per observation, columns of `ObservationRecord`
# in API order. Pure functions, no network.
#
#   value                               double: the number the API extracted
#                                       (a JSON number, a numeric string or a
#                                       one-element array of either); for a
#                                       multi-value cell (the API extracts
#                                       none) the mean of the listed values,
#                                       computed by the client (decision 8),
#                                       NA when one is not a number
#   value_raw                           list: the original value verbatim as
#                                       parsed (number, string, list of strings)
#   codes, ids, unit, method texts      character
#   release_id, value_count,            integer
#   component_rank, suid, tcid, scid
#   depths, value_spread, texture_sum,  double
#   method_tension_kpa, proportions
#   methods_differ, is_representative,  logical
#   profile_inside_polygon
#   lineage, profile_attributes,        list (named lists, arrays as vectors)
#   horizon_attributes,
#   component_attributes, method_facets
#   profile_markings,                   list of character
#   source_method_kind,
#   consistency_flags,
#   also_in_datasets, value_flags
#   revised_markings                    list of named lists, hidden_values a
#                                       data frame (view = "revised")
#   geometry                            absent (with_geometry = "none"),
#                                       geometry_text GeoJSON ("text") or an
#                                       sfc ("sf", converted by the caller)
#
# Fields the API serialises only for some selections (components, first
# layer, canonical markings) are present only when served.

long_column_types <- c(
  dataset = "chr", observation_id = "chr", feature_id = "chr", source_code = "chr",
  component_id = "chr", component_rank = "int", representative_profile_id = "chr",
  horizon_id = "chr", source_horizon_id = "chr", horizon_name = "chr",
  upper_depth_cm = "dbl", lower_depth_cm = "dbl", property_code = "chr",
  value = "dbl", value_raw = "raw", unit = "chr", source_table = "chr",
  source_observation_id = "chr", provider_code = "chr", release_code = "chr",
  release_id = "int", canonical_feature_id = "chr", canonical_horizon_id = "chr",
  canonical_property_key = "chr", source_support = "chr", lineage = "object",
  geometry = "geometry", geometry_kind = "chr",
  # components (SOTWIS, SOTER polygons)
  proportion_percent = "dbl", soil_code = "chr", cumulative_proportion_percent = "dbl",
  is_representative = "lgl", suid = "int", newsuid = "chr", isoc = "chr",
  soil_map_unit = "chr", tcid = "int", scid = "int", terrain_proportion_percent = "dbl",
  tcdc = "chr", linked_profile_feature_id = "chr", profile_inside_polygon = "lgl",
  # methods and source records
  method_code = "chr", method_description = "chr", method_tension_kpa = "dbl",
  profile_attributes = "object", horizon_attributes = "object",
  component_attributes = "object", source_profile_type = "chr", source_record_note = "chr",
  # layer = "first"
  first_layer_status = "chr", profile_markings = "chr_list",
  # raw markings: cell, layer, profile
  value_count = "int", methods_differ = "lgl", value_spread = "dbl",
  source_method_kind = "chr_list", method_facets = "object", texture_sum = "dbl",
  consistency_flags = "chr_list", also_in_datasets = "chr_list",
  possible_profile = "chr", superseded_by = "chr",
  # flags, retirement, view = "revised"
  value_flags = "chr_list", retired_in_release = "chr", revised_markings = "revised_markings"
)
# The fields every long record carries (the others are serialised only for
# some selections): the columns of an empty read.
long_base_columns <- c(
  "dataset", "observation_id", "feature_id", "source_code", "component_id",
  "component_rank", "representative_profile_id", "horizon_id", "source_horizon_id",
  "horizon_name", "upper_depth_cm", "lower_depth_cm", "property_code", "value",
  "value_raw", "unit", "source_table", "source_observation_id", "provider_code",
  "release_code", "release_id", "canonical_feature_id", "canonical_horizon_id",
  "canonical_property_key", "source_support", "lineage", "geometry", "geometry_kind"
)
long_context <- "POST /query/observations (long)"

#' Long pages to a typed data frame
#'
#' @param pages A `soilhub_pages` of long pages (complete or partial).
#' @param with_geometry `"none"` (the `geometry` column is dropped),
#'   `"text"` (`geometry_text`: GeoJSON) or `"sf"` (`geometry`: WKT, turned
#'   into an `sfc` by `observations_table()`).
#' @return A data frame, columns in API order.
#' @keywords internal
#' @noRd
long_layout_frame <- function(pages, with_geometry = "none") {
  rows <- lapply(pages$items %||% list(), function(row) if (is.list(row)) row else list())
  n <- length(rows)
  fields <- unique(unlist(lapply(rows, names), use.names = FALSE))
  if (n == 0L) fields <- union(long_base_columns, fields)
  unknown <- setdiff(fields, names(long_column_types))
  if (length(unknown)) report_drift(long_context, unknown, character())

  columns <- list()
  feature_id <- type_column(lapply(rows, function(row) row$feature_id), "chr")
  for (name in fields) {
    values <- lapply(rows, function(row) row[[name]])
    type <- long_column_types[name]
    if (is.na(type)) {
      columns[[name]] <- values
      next
    }
    if (identical(unname(type), "geometry")) {
      if (identical(with_geometry, "none")) next
      convert <- if (identical(with_geometry, "sf")) geojson_to_wkt else geojson_text
      column <- if (identical(with_geometry, "sf")) "geometry" else "geometry_text"
      text <- per_feature(values, feature_id, convert)
      warn_missing_geometry(is.na(text), feature_id, missing_geometry_text(with_geometry, column))
      columns[[column]] <- text
      next
    }
    columns[[name]] <- type_long_values(values, unname(type))
  }

  if (!is.null(columns$value) && !is.null(columns$value_raw)) {
    columns$value <- long_multi_value_means(columns$value, columns$value_raw)
  }
  new_frame(columns, n)
}

type_long_values <- function(values, type) {
  switch(type,
    raw = values,
    object = lapply(values, function(v) if (is.null(v)) NULL else simplify_json(v)),
    revised_markings = lapply(values, type_revised_markings),
    type_column(values, type)
  )
}

# `value` of the multi-value cells (an array of two or more values in
# `value_raw`, for which the API extracts no number): the mean of the listed
# values (decision 8), NA when one is not a number.
long_multi_value_means <- function(value, value_raw) {
  for (i in seq_along(value)) {
    raw <- value_raw[[i]]
    if (!is.na(value[[i]]) || !is.list(raw) || !is.null(names(raw)) || length(raw) < 2L) next
    value[[i]] <- multi_value_mean(raw)
  }
  value
}
