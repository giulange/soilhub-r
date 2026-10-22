#' @include typing.R
NULL

# Geometry helpers (design 2.2, 5.2, 5.3, 5.5; decision 6): `sf` is optional
# (Suggests). Every read without geometry works without it; the text forms
# (WKT for the wide layout, GeoJSON for the long layout and the features) need
# nothing; `with_geometry = "sf"` needs `sf` and raises a
# `soilhub_dependency_error` naming the text alternative when it is absent.
# The GeoJSON of the API is converted to WKT here (pure R), then to an `sfc`
# by `sf::st_as_sfc()`, so one code path serves the three reads.

geometry_crs <- 4326L

# Whether a suggested package can be loaded. A function of its own so that the
# tests can simulate a missing package (testthat::local_mocked_bindings()).
soil_has_package <- function(package) {
  requireNamespace(package, quietly = TRUE)
}

# Stop with a soilhub_dependency_error when `sf` is not installed.
require_sf <- function(what) {
  if (soil_has_package("sf")) return(invisible(TRUE))
  abort(soilhub_dependency_error("sf", sprintf(
    paste0(
      "%s with `with_geometry = \"sf\"` needs the package 'sf', which is not installed: ",
      "install.packages(\"sf\"), or use `with_geometry = \"text\"` (the geometry as text, no package needed)."
    ),
    what
  )))
}

# A number of a coordinate as WKT writes it (15 significant digits).
wkt_number <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  out <- sprintf("%.15g", x)
  out[is.na(x)] <- "NaN"
  out
}

#' GeoJSON geometry to WKT
#'
#' @param geometry A GeoJSON geometry parsed with `simplifyVector = FALSE`
#'   (`type`, `coordinates` or `geometries`).
#' @return One WKT string (2D: the first two coordinates of each position),
#'   `NA` for `NULL` or an unknown type.
#' @keywords internal
#' @noRd
geojson_to_wkt <- function(geometry) {
  if (!is.list(geometry) || !is_string(geometry$type)) return(NA_character_)
  type <- geometry$type
  coordinates <- geometry$coordinates
  position <- function(p) paste(wkt_number(unlist(p, use.names = FALSE)[1:2]), collapse = " ")
  line <- function(points) paste0("(", paste(vapply(points, position, character(1)), collapse = ", "), ")")
  polygon <- function(rings) paste0("(", paste(vapply(rings, line, character(1)), collapse = ", "), ")")
  empty <- function(name) paste(name, "EMPTY")
  switch(type,
    Point = if (length(coordinates) < 2L) empty("POINT") else paste0("POINT (", position(coordinates), ")"),
    MultiPoint = if (!length(coordinates)) empty("MULTIPOINT") else
      paste0("MULTIPOINT (", paste(vapply(coordinates, function(p) paste0("(", position(p), ")"), character(1)), collapse = ", "), ")"),
    LineString = if (!length(coordinates)) empty("LINESTRING") else paste0("LINESTRING ", line(coordinates)),
    MultiLineString = if (!length(coordinates)) empty("MULTILINESTRING") else
      paste0("MULTILINESTRING (", paste(vapply(coordinates, line, character(1)), collapse = ", "), ")"),
    Polygon = if (!length(coordinates)) empty("POLYGON") else paste0("POLYGON ", polygon(coordinates)),
    MultiPolygon = if (!length(coordinates)) empty("MULTIPOLYGON") else
      paste0("MULTIPOLYGON (", paste(vapply(coordinates, polygon, character(1)), collapse = ", "), ")"),
    GeometryCollection = {
      parts <- vapply(geometry$geometries %||% list(), geojson_to_wkt, character(1))
      if (!length(parts) || anyNA(parts)) empty("GEOMETRYCOLLECTION") else
        paste0("GEOMETRYCOLLECTION (", paste(parts, collapse = ", "), ")")
    },
    NA_character_
  )
}

# A parsed GeoJSON geometry as GeoJSON text; NA for NULL.
geojson_text <- function(geometry) {
  if (!is.list(geometry)) return(NA_character_)
  as.character(jsonlite::toJSON(geometry, auto_unbox = TRUE, null = "null", digits = NA))
}

#' WKT strings to an `sfc` (EPSG:4326)
#'
#' Missing geometries (`NA`) become empty geometries: of the type of the
#' others when they all share one, else `GEOMETRYCOLLECTION EMPTY`.
#'
#' @param wkt Character vector of WKT.
#' @return An `sfc` of the same length, CRS EPSG:4326.
#' @keywords internal
#' @noRd
wkt_sfc <- function(wkt) {
  wkt <- as.character(wkt)
  missing <- is.na(wkt)
  if (any(missing)) {
    types <- unique(toupper(sub("^\\s*([A-Za-z]+).*$", "\\1", wkt[!missing])))
    wkt[missing] <- if (length(types) == 1L) paste(types, "EMPTY") else "GEOMETRYCOLLECTION EMPTY"
  }
  sf::st_as_sfc(wkt, crs = geometry_crs)
}

# A data frame with the `sfc` `geometry` as an sf object (sf class in front
# of data.frame); the column keeps its position.
frame_as_sf <- function(frame, geometry, column = "geometry") {
  frame[[column]] <- geometry
  sf::st_sf(frame, sf_column_name = column, sfc_last = FALSE)
}

# One warning for the rows (of features) without geometry.
warn_missing_geometry <- function(missing, feature_id, what) {
  if (!any(missing)) return(invisible(NULL))
  soilhub_warning(sprintf(
    paste0(
      "%s row(s) of %s feature(s) have no geometry (for example WISE profiles without ",
      "coordinates): %s."
    ),
    format_count(sum(missing)), format_count(length(unique(feature_id[missing]))), what
  ), "soilhub_geometry_warning")
}

# The text that says what a row without geometry gets.
missing_geometry_text <- function(with_geometry, column = "geometry_text") {
  if (identical(with_geometry, "sf")) "their geometry is empty" else sprintf("their %s is NA", column)
}

# One value per row from one value per feature: `geometry_of(row)` is called
# once per feature_id (rows of a feature share its geometry), per row where
# the feature_id is missing.
per_feature <- function(rows, feature_id, geometry_of) {
  out <- character(length(rows))
  seen <- list()
  for (i in seq_along(rows)) {
    id <- feature_id[[i]]
    if (!is.na(id) && !is.null(seen[[id]])) {
      out[[i]] <- seen[[id]]
      next
    }
    out[[i]] <- geometry_of(rows[[i]])
    if (!is.na(id) && !is.na(out[[i]])) seen[[id]] <- out[[i]]
  }
  out
}
