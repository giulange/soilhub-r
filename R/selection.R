#' @include catalog.R
NULL

# The selection (design 4.1): the common filters of the canonical data
# endpoints (observations, features, summary, availability, exports),
# validated client-side and translated to the request body. The R argument
# names and values are the API's own (`QueryRequest` of the API), so the body
# selection is the R selection. Pure functions, no network.

# Package constants, used when the server's /capabilities does not list the
# values (an older server); otherwise the server's values are accepted, so new
# values are not refused by the client.
selection_values <- list(
  geometry = c("any", "point", "polygon"),
  layer = c("all", "first"),
  view = c("raw", "revised"),
  profile_type = c("synthetic", "virtual", "none"),
  components = c("representative", "all", "cumulative")
)
profile_type_exclude_prefix <- "!"

#' Validate a selection and build the request body
#'
#' @param soil The session (its cached `/capabilities` give the accepted
#'   values of `view` and `profile_type`); `NULL` uses the package constants.
#' @param datasets,variables,bbox,country,geometry,layer,view,profile_type,components,min_cumulative_percent
#'   The selection arguments (design 4.1).
#' @return The request body: a list with the API field names, `NULL` fields
#'   dropped, arrays wrapped in [I()] so that a single value is sent as a JSON
#'   array, and `canonical = TRUE`. Its attribute `selection` holds the
#'   arguments that differ from the defaults (for messages and the export
#'   hint of a refused request).
#' @keywords internal
#' @noRd
soil_selection <- function(soil = NULL, datasets = NULL, variables = NULL,
                           bbox = NULL, country = NULL, geometry = "any",
                           layer = "all", view = "raw", profile_type = NULL,
                           components = NULL, min_cumulative_percent = NULL) {
  values <- selection_choices(soil)
  datasets <- check_filter(datasets, "datasets")
  variables <- check_filter(variables, "variables")
  country <- check_filter(country, "country")
  bbox <- check_bbox(bbox)
  geometry <- check_choice(geometry, values$geometry, "geometry")
  layer <- check_choice(layer, values$layer, "layer")
  view <- check_choice(view, values$view, "view")
  profile_type <- check_profile_type(profile_type, values$profile_type, values$exclude_prefix)
  components <- if (is.null(components)) NULL else check_choice(components, values$components, "components")
  min_cumulative_percent <- check_cumulative(min_cumulative_percent, components)

  body <- list(
    datasets = as_array(datasets),
    variables = as_array(variables),
    bbox = bbox,
    country = as_array(country),
    geometry = geometry,
    layer = layer,
    view = view,
    profile_type = as_array(profile_type),
    components = components,
    min_cumulative_percent = min_cumulative_percent,
    canonical = TRUE
  )
  body <- body[!vapply(body, is.null, logical(1))]

  selection <- list(
    datasets = datasets, variables = variables, bbox = bbox, country = country,
    geometry = if (identical(geometry, "any")) NULL else geometry,
    layer = if (identical(layer, "all")) NULL else layer,
    view = if (identical(view, "raw")) NULL else view,
    profile_type = profile_type, components = components,
    min_cumulative_percent = min_cumulative_percent
  )
  attr(body, "selection") <- selection[!vapply(selection, is.null, logical(1))]
  body
}

# The accepted values: the server's when its capabilities list them.
selection_choices <- function(soil) {
  values <- selection_values
  values$exclude_prefix <- profile_type_exclude_prefix
  capabilities <- tryCatch(session_cached(soil, "capabilities"), error = function(e) NULL)
  if (!is.list(capabilities)) return(values)
  server_values <- function(x) {
    x <- unlist(x, use.names = FALSE)
    if (is.character(x) && length(x)) x else NULL
  }
  views <- capabilities$views
  if (is.list(views)) values$view <- server_values(views$values) %||% values$view
  types <- capabilities$profile_types
  if (is.list(types)) {
    values$profile_type <- server_values(types$values) %||% values$profile_type
    if (is_string(types$exclude_prefix)) values$exclude_prefix <- types$exclude_prefix
  }
  values
}

as_array <- function(x) if (is.null(x)) NULL else I(x)

check_choice <- function(value, choices, argument) {
  if (!is_string(value)) {
    abort(soilhub_argument_error(
      sprintf(
        "`%s` must be one of %s, not %s.",
        argument, paste0("\"", choices, "\"", collapse = ", "), deparse_argument(value)
      ),
      argument
    ))
  }
  if (toupper(value) == "ALL" && !"all" %in% choices) {
    abort(soilhub_argument_error(
      sprintf("`%s = \"ALL\"` is not a filter value: use `%s = NULL` for no filter.", argument, argument),
      argument
    ))
  }
  if (!value %in% choices) {
    abort(soilhub_argument_error(
      sprintf(
        "`%s` must be one of %s, not \"%s\".",
        argument, paste0("\"", choices, "\"", collapse = ", "), value
      ),
      argument
    ))
  }
  value
}

# bbox: c(xmin, ymin, xmax, ymax) in WGS84 degrees, the API's own rules.
check_bbox <- function(bbox) {
  if (is.null(bbox)) return(NULL)
  bad <- function(reason) {
    abort(soilhub_argument_error(
      sprintf("`bbox` %s, not %s.", reason, deparse_argument(bbox)),
      "bbox"
    ))
  }
  if (!is.numeric(bbox) || length(bbox) != 4L || anyNA(bbox) || !all(is.finite(bbox))) {
    bad("must be four numbers c(xmin, ymin, xmax, ymax) in WGS84 degrees (longitude, latitude)")
  }
  bbox <- as.numeric(unname(bbox))
  if (bbox[1] >= bbox[3] || bbox[2] >= bbox[4]) {
    bad("must have xmin < xmax and ymin < ymax (c(xmin, ymin, xmax, ymax))")
  }
  if (bbox[1] < -180 || bbox[3] > 180 || bbox[2] < -90 || bbox[4] > 90) {
    bad("must lie within the WGS84 bounds (longitude -180 to 180, latitude -90 to 90)")
  }
  bbox
}

# profile_type: source terms or "none", all selecting or all excluded with
# the prefix "!" (the API's syntax, profile_types.py).
check_profile_type <- function(profile_type, terms, prefix = profile_type_exclude_prefix) {
  if (is.null(profile_type)) return(NULL)
  profile_type <- check_filter(profile_type, "profile_type")
  excluded <- startsWith(profile_type, prefix)
  accepted <- paste0("\"", terms, "\"", collapse = ", ")
  if (any(excluded) && !all(excluded)) {
    abort(soilhub_argument_error(
      sprintf(
        "`profile_type`: either every term selects or every term excludes (prefix \"%s\"), not both: %s.",
        prefix, deparse_argument(profile_type)
      ),
      "profile_type"
    ))
  }
  bare <- if (all(excluded)) substring(profile_type, nchar(prefix) + 1L) else profile_type
  unknown <- setdiff(bare, terms)
  if (length(unknown)) {
    abort(soilhub_argument_error(
      sprintf(
        "Unknown `profile_type` term(s) %s; accepted: %s, each optionally prefixed by \"%s\" to exclude.",
        paste0("\"", unknown, "\"", collapse = ", "), accepted, prefix
      ),
      "profile_type"
    ))
  }
  profile_type
}

check_cumulative <- function(value, components) {
  cumulative <- identical(components, "cumulative")
  if (is.null(value)) {
    if (cumulative) {
      abort(soilhub_argument_error(
        "`components = \"cumulative\"` needs `min_cumulative_percent` (0 to 100).",
        "min_cumulative_percent"
      ))
    }
    return(NULL)
  }
  if (!is.numeric(value) || length(value) != 1L || is.na(value) || value < 0 || value > 100) {
    abort(soilhub_argument_error(
      sprintf("`min_cumulative_percent` must be one number from 0 to 100, not %s.", deparse_argument(value)),
      "min_cumulative_percent"
    ))
  }
  if (!cumulative) {
    abort(soilhub_argument_error(
      "`min_cumulative_percent` is used only with `components = \"cumulative\"`.",
      "min_cumulative_percent"
    ))
  }
  as.numeric(value)
}

# Capabilities the selection needs (design 9.1): checked from the cached
# /capabilities, no request.
require_selection_capabilities <- function(soil, body, what) {
  if (identical(body$view, "revised")) {
    soil_require_capability(soil, "revised_view", paste0(what, " with `view = \"revised\"`"))
  }
  if (!is.null(body$profile_type)) {
    soil_require_capability(soil, "profile_type_filter", paste0(what, " with `profile_type`"))
  }
  if (!is.null(body$components)) {
    soil_require_capability(soil, "component_selection", paste0(what, " with `components`"))
  }
  invisible(TRUE)
}
