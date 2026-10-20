#' @include observations.R geometry.R
NULL

# Reads of the features (design 4.4, 5.5): `POST /query/features` with
# `canonical = true`, paged, typed into a `soil_table` with
# `soil_layout = "features"`: an `sf` (points and (multi)polygons,
# EPSG:4326) or a data frame with `geometry_text` (GeoJSON).

feature_property_types <- c(
  dataset = "chr", provider_code = "chr", feature_id = "chr", feature_key = "chr",
  geometry_kind = "chr", source_support = "chr", components = "components",
  profile_markings = "chr_list", retired_in_release = "chr"
)
feature_component_types <- c(
  component_id = "chr", component_rank = "int", proportion_percent = "dbl",
  soil_code = "chr", representative_profile_id = "chr",
  cumulative_proportion_percent = "dbl", is_representative = "lgl", suid = "int",
  newsuid = "chr", isoc = "chr", soil_map_unit = "chr", tcid = "int", scid = "int",
  terrain_proportion_percent = "dbl", tcdc = "chr", linked_profile_feature_id = "chr",
  profile_inside_polygon = "lgl", source_attributes = "json"
)
features_context <- "POST /query/features"
polygon_kinds <- c("POLYGON", "MULTIPOLYGON")

#' Soil features: where the profiles and map units are
#'
#' Reads the features of a selection from the canonical layer of the Global
#' Soil Data Hub (`POST /query/features`, always `canonical = true`), page by
#' page: one row per feature (a WoSIS, WISE or SOTER profile location, a
#' SOTER or SOTWIS map unit), with its geometry. The `feature_id` is the one
#' of [soil_observations()] read with the same selection, so features and
#' measurements join by it (`merge(features, observations, by =
#' "feature_id")`).
#'
#' **Columns** (design 5.5), in the API's order: `dataset`, `provider_code`,
#' `feature_id`, `feature_key` (the canonical key: the reference to the
#' source record), `geometry_kind` (`POINT`, `POLYGON`, `MULTIPOLYGON`),
#' `source_support`; when SOTWIS or SOTER polygons are selected `components`
#' (a list of data frames, one row per selected soil component of the map
#' unit, in selection order: `component_id`, `component_rank`,
#' `proportion_percent`, `is_representative`, ..., and `source_attributes`,
#' the source descriptors of the component as a named list); when
#' `soter_profiles` is selected `profile_markings` (list of character:
#' `no_horizons_in_source` for a profile without horizons in the source);
#' `retired_in_release` (the release in which the feature left ISRIC, still
#' served); then the geometry: `geometry` (`sf`) or `geometry_text`
#' (GeoJSON text).
#'
#' The API returns only features with a geometry; a feature served without
#' one gets an empty geometry (`sf`) or `NA` (`"text"`) and one warning.
#' `soil_metadata(x)` adds `feature_count`, `feature_count_by_dataset` (when
#' several datasets are selected) and `mixed_geometry` (points and polygons
#' in the result); `total_count` is `NA` (the API does not count features;
#' the summary of the selection does).
#'
#' **Pages.** At most `max_page_size` features per request (1000, see
#' [soil_capabilities()]); a failure after some pages raises the error with
#' the features already read in `e$partial` (a `soil_table` whose metadata
#' has `complete = FALSE`).
#'
#' Rights: `soil:read`. Capabilities: `canonical_features`; `revised_view`
#' for `view = "revised"`, `profile_type_filter` for `profile_type`,
#' `component_selection` for `components`.
#'
#' @inheritParams soil_observations
#' @param view `"raw"` or `"revised"`: with `"revised"` the features the
#'   rules of the revised view exclude (SOTER copy profiles whose original is
#'   in the selection, R8) are not returned, and the rules are listed in
#'   [soil_revised_rules()]. API field `view`.
#' @param with_geometry `"sf"` (the default: an `sf` object, EPSG:4326; needs
#'   the package `sf`, else a `soilhub_dependency_error`) or `"text"` (a data
#'   frame with `geometry_text`, the GeoJSON of each feature: no package
#'   needed; `sf::st_read()` or `geojsonsf` read it). Client-side: not sent to the API (features
#'   always carry their GeoJSON geometry).
#' @param max_rows Maximum number of features to read (`Inf`: the whole
#'   selection). Client-side; caps the API field `limit` of each page request.
#' @param page_size Features per request; `NULL` uses the session's, the
#'   `soilhub.page_size` option or the server's `max_page_size`. Client-side; sets the API field
#'   `limit` of each page request.
#' @param too_large What to do when the API refuses the selection as too
#'   large for a synchronous read: `"stop"` raises
#'   `soilhub_load_limit_error`, whose message names the equivalent
#'   `soil_export(..., content = "features")` call; `"export"` exports the
#'   features of the selection (GeoJSON), waits, downloads, reads them back
#'   and returns the same shape, with `soil_metadata(x)$via_export` the job
#'   id. Client-side: not sent to the API.
#' @return A `soil_table` with `soil_layout = "features"`: an `sf` object
#'   (`with_geometry = "sf"`) or a data frame (`"text"`).
#' @family reads
#' @seealso [soil_observations()], [soil_citations()]
#' @examples
#' \dontrun{
#' soil <- soil_connect()
#' f <- soil_features(soil, datasets = "wosis_points", country = "KEN")
#' plot(sf::st_geometry(f))
#'
#' # without sf: GeoJSON text
#' g <- soil_features(soil, datasets = "sotwis_polygons", country = "TUN",
#'                    with_geometry = "text")
#' g$components[[1]]
#' }
#' @export
soil_features <- function(soil = soil_session(), datasets = NULL,
                          variables = NULL, bbox = NULL, country = NULL,
                          geometry = "any", view = "raw", profile_type = NULL,
                          components = NULL, min_cumulative_percent = NULL,
                          with_geometry = c("sf", "text"), max_rows = Inf,
                          page_size = NULL, too_large = c("stop", "export"),
                          progress = interactive()) {
  check_session(soil)
  body <- soil_selection(
    soil, datasets = datasets, variables = variables, bbox = bbox,
    country = country, geometry = geometry, view = view,
    profile_type = profile_type, components = components,
    min_cumulative_percent = min_cumulative_percent
  )
  with_geometry <- check_option(with_geometry, c("sf", "text"), "with_geometry")
  too_large <- check_option(too_large, c("stop", "export"), "too_large")
  max_rows <- check_max_rows(max_rows)
  if (!is.null(page_size)) page_size <- check_page_size(page_size)
  progress <- check_flag(progress, "progress")

  what <- "`soil_features()`"
  if (identical(with_geometry, "sf")) require_sf(what)
  soil_require_right(soil, "soil:read", what)
  soil_require_capability(soil, "canonical_features", what)
  require_selection_capabilities(soil, body, what)

  selection <- attr(body, "selection")
  attr(body, "selection") <- NULL
  # `layer` does not apply to the features (the API ignores it); `layout`,
  # `geometry_format` and `include_geometry` are not sent: features always
  # carry their GeoJSON geometry.
  body$layer <- NULL

  pages <- tryCatch(
    soil_collect(soil, "/query/features", body, items = "features",
                 max_rows = max_rows, page_size = page_size, progress = progress),
    soilhub_load_limit_error = function(e) {
      if (identical(too_large, "export") && identical(e$channel, "sync")) return(e)
      abort(features_load_limit(soil, e, selection, too_large, with_geometry))
    },
    soilhub_error = function(e) {
      abort(with_typed_features(soil, e, selection, with_geometry))
    }
  )
  if (inherits(pages, "soilhub_load_limit_error")) {
    # too_large = "export" (design 6.3): the features exported and read back
    return(features_via_export(soil, selection, with_geometry, max_rows, progress))
  }
  features_table(soil, pages, selection, with_geometry)
}

#' Feature pages to a `soil_table`
#'
#' @param soil The session (capabilities and catalog cache).
#' @param pages A `soilhub_pages` of feature pages, complete or partial.
#' @param selection The selection arguments (non-default), for the metadata.
#' @param with_geometry `"sf"` or `"text"`.
#' @param fetch_catalog Read the catalog (once per session) for the
#'   `datasets` of the metadata.
#' @return A `soil_table` with `soil_layout = "features"`.
#' @keywords internal
#' @noRd
features_table <- function(soil, pages, selection = NULL, with_geometry = "sf",
                           fetch_catalog = TRUE) {
  frame <- features_frame(pages, with_geometry)
  metadata <- features_metadata(soil, pages, frame, selection, fetch_catalog)
  if (identical(with_geometry, "sf")) {
    frame <- frame_as_sf(frame, wkt_sfc(frame$geometry))
  }
  new_soil_table(frame, metadata, "features")
}

#' GeoJSON features to a typed data frame
#'
#' @param pages A `soilhub_pages` whose items are GeoJSON features (`id`,
#'   `geometry`, `properties`).
#' @param with_geometry `"text"` (`geometry_text`: GeoJSON) or `"sf"`
#'   (`geometry`: WKT, turned into an `sfc` by `features_table()`).
#' @return A data frame: the properties in API order, then the geometry.
#' @keywords internal
#' @noRd
features_frame <- function(pages, with_geometry = "sf") {
  items <- lapply(pages$items %||% list(), function(item) if (is.list(item)) item else list())
  n <- length(items)
  properties <- lapply(items, function(item) {
    p <- item$properties
    if (!is.list(p)) p <- list()
    if (is.null(p$feature_id) && !is.null(item$id)) p$feature_id <- item$id
    p
  })
  fields <- unique(unlist(lapply(properties, names), use.names = FALSE))
  if (n == 0L) fields <- union(c("dataset", "provider_code", "feature_id", "feature_key",
                                 "geometry_kind", "source_support"), fields)
  unknown <- setdiff(fields, names(feature_property_types))
  if (length(unknown)) report_drift(features_context, unknown, character())

  columns <- list()
  for (name in fields) {
    values <- lapply(properties, function(p) p[[name]])
    type <- feature_property_types[name]
    columns[[name]] <- if (is.na(type)) {
      values
    } else if (identical(unname(type), "components")) {
      lapply(values, type_feature_components)
    } else {
      type_column(values, unname(type))
    }
  }

  geometries <- lapply(items, function(item) item$geometry)
  sf <- identical(with_geometry, "sf")
  column <- if (sf) "geometry" else "geometry_text"
  text <- vapply(geometries, if (sf) geojson_to_wkt else geojson_text, character(1))
  feature_id <- columns$feature_id %||% character()
  warn_missing_geometry(is.na(text), feature_id, missing_geometry_text(with_geometry, column))
  columns[[column]] <- text
  new_frame(columns, n)
}

# The components of a map-unit feature: a data frame typed by the fields
# present (they depend on the datasets selected), `source_attributes` a list
# column of named lists; NULL for a feature without components.
type_feature_components <- function(value) {
  if (is.null(value)) return(NULL)
  records <- lapply(value, function(record) if (is.list(record)) record else list())
  fields <- unique(unlist(lapply(records, names), use.names = FALSE))
  unknown <- setdiff(fields, names(feature_component_types))
  if (length(unknown)) report_drift(paste0(features_context, ": components"), unknown, character())
  schema <- as.list(feature_component_types[intersect(names(feature_component_types), fields)])
  frame <- records_frame(records, schema)
  frame[intersect(fields, names(frame))]
}

# The metadata of a features read (design 5.4, 5.5): as for observations,
# plus the feature counts over the pages and `mixed_geometry`.
features_metadata <- function(soil, pages, frame, selection, fetch_catalog) {
  meta <- observations_metadata(soil, pages, NULL, selection, fetch_catalog)
  meta$multi_value_rule <- NULL
  datasets <- as.character(unlist(pages$metadata$datasets %||% pages$metadata$request$datasets))
  counts <- if (length(datasets) > 1L) {
    stats::setNames(
      lapply(datasets, function(name) sum(frame$dataset == name, na.rm = TRUE)),
      datasets
    )
  } else {
    NULL
  }
  kinds <- unique(ifelse(toupper(frame$geometry_kind %||% character()) %in% polygon_kinds, "polygon", "point"))
  meta["feature_count"] <- list(nrow(frame))
  meta["feature_count_by_dataset"] <- list(counts)
  meta["mixed_geometry"] <- list(length(kinds) > 1L)
  meta
}

# A failure after some pages: the features read become a typed soil_table.
with_typed_features <- function(soil, error, selection, with_geometry) {
  if (inherits(error$partial, "soilhub_pages")) {
    typed <- tryCatch(
      features_table(soil, error$partial, selection, with_geometry, fetch_catalog = FALSE),
      error = function(e) NULL
    )
    if (!is.null(typed)) error$partial <- typed
  }
  error
}

# The load-limit error of a features read: the export hint names
# `content = "features"`.
features_load_limit <- function(soil, error, selection, too_large, with_geometry) {
  hinted <- c(selection, list(content = "features"))
  rebuilt <- load_limit_error(
    error$detail, request = error$request, selection = hinted,
    status = error$status, endpoint = error$endpoint, method = error$method,
    request_id = error$request_id, attempts = error$attempts
  )
  rebuilt$selection <- selection
  if (!is.null(error$partial)) {
    rebuilt$partial <- with_typed_features(soil, error, selection, with_geometry)$partial
  }
  rebuilt
}
