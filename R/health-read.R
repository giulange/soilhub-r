#' @include thematic.R results.R
NULL

# Soil-health scores (design 4.4, 5.5): POST /query/soil-health, paged, typed
# into a `soil_table` with `soil_layout = "health"`, and
# POST /query/soil-health/summary. The R arguments `run_ids` and `statuses`
# are sent as the API fields `product_run_ids` and `score_statuses`.

health_statuses <- c("scored", "insufficient_data", "not_applicable")

health_schema <- list(
  horizon_score_id = "chr", value_id = "chr", variable_code = "chr",
  horizon_id = "chr", profile_id = "chr", component_id = "chr",
  feature_id = "chr", dataset_code = "chr", provider_code = "chr",
  release_id = "dbl", release_code = "chr", source_support = "chr",
  geometry_kind = "chr", geometry = "json", horizon_key = "chr",
  horizon_name = "chr", top_depth_cm = "dbl", bottom_depth_cm = "dbl",
  model_version_id = "dbl", model_version_code = "chr", model_name = "chr",
  model_checksum = "chr", health_run_id = "dbl", product_run_id = "dbl",
  category_code = "chr", category_name = "chr", score = "dbl",
  score_class = "chr", score_status = "chr", created_at = "time"
)

health_details_schema <- list(
  inputs = "json", derived_variables = "json", memberships = "json",
  activated_rules = "json", diagnostics = "json", input_observations = "json"
)

health_body <- function(providers, datasets, release_ids, release_codes,
                        model_versions, run_ids, categories, score_classes,
                        statuses, source_supports, country, bbox,
                        depth_top_cm, depth_bottom_cm) {
  thematic_body(
    providers = check_filter(providers, "providers"),
    datasets = check_filter(datasets, "datasets"),
    release_ids = check_ids(release_ids, "release_ids"),
    release_codes = check_filter(release_codes, "release_codes"),
    model_versions = check_filter(model_versions, "model_versions"),
    product_run_ids = check_ids(run_ids, "run_ids"),
    categories = check_filter(categories, "categories"),
    score_classes = check_filter(score_classes, "score_classes"),
    score_statuses = check_values(statuses, health_statuses, "statuses"),
    source_supports = check_filter(source_supports, "source_supports"),
    country = check_filter(country, "country"),
    bbox = check_bbox(bbox),
    depth_top_cm = check_number(depth_top_cm, "depth_top_cm"),
    depth_bottom_cm = check_number(depth_bottom_cm, "depth_bottom_cm")
  )
}

#' Soil-health scores
#'
#' Reads the soil-health scores published on horizons
#' (`POST /query/soil-health`), page by page, as a typed table: one row per
#' horizon, category and model version, with the score, its class and
#' status, the model and the run that produced it.
#'
#' Filters are combined with AND; each takes several values. `NULL` means no
#' filter.
#'
#' Rights: `soil:read`. Capabilities: `query_soil_health`;
#' `country_filtering` for `country`.
#'
#' @param soil A session; the default session when omitted.
#' @param providers Provider codes.
#' @param datasets Catalog dataset codes.
#' @param release_ids,release_codes Releases of the scored horizons.
#' @param model_versions Soil-health model version codes (an unknown code is
#'   refused by the API).
#' @param run_ids Product run ids (API field `product_run_ids`).
#' @param categories Category codes (`"physical"`, `"chemical"`, ...).
#' @param score_classes Score classes.
#' @param statuses Score statuses: `"scored"`, `"insufficient_data"`,
#'   `"not_applicable"` (API field `score_statuses`).
#' @param source_supports Source supports (`"point_observation"`,
#'   `"polygon_estimate"`, ...).
#' @param country Countries as ISO 3166 alpha-2 or alpha-3 codes or names.
#' @param bbox `c(xmin, ymin, xmax, ymax)` in WGS84 degrees.
#' @param depth_top_cm,depth_bottom_cm Depth interval in cm: the horizons
#'   overlapping it.
#' @param with_geometry `"none"`, or `"text"`: the geometry of the feature
#'   as GeoJSON text in `geometry_text`. `"sf"` is not available in this
#'   version yet.
#' @param include_details Add the list columns `inputs`,
#'   `derived_variables`, `memberships`, `activated_rules`, `diagnostics`,
#'   `input_observations` (how each score was computed).
#' @param max_rows Maximum number of scores to read (`Inf`: all).
#' @param progress Report the pages read.
#' @return A `soil_table` (see [soil_table]) with `soil_layout = "health"`:
#'   `horizon_score_id`, `value_id`, `variable_code`, `horizon_id`,
#'   `profile_id`, `component_id`, `feature_id`, `dataset_code`,
#'   `provider_code`, `release_id`, `release_code`, `source_support`,
#'   `geometry_kind`, (`geometry_text`), `horizon_key`, `horizon_name`,
#'   `top_depth_cm`, `bottom_depth_cm`, `model_version_id`,
#'   `model_version_code`, `model_name`, `model_checksum`, `health_run_id`,
#'   `product_run_id`, `category_code`, `category_name`, `score` (double),
#'   `score_class`, `score_status`, `created_at` (POSIXct UTC), and the
#'   detail columns.
#' @family thematic reads
#' @seealso [soil_health_summary()], [soil_publish_health()]
#' @examples
#' \dontrun{
#' h <- soil_health_scores(soil, datasets = "sotwis_polygons", country = "TUN",
#'                         categories = "physical", include_details = TRUE)
#' table(h$score_class)
#' }
#' @export
soil_health_scores <- function(soil = soil_session(), providers = NULL,
                               datasets = NULL, release_ids = NULL,
                               release_codes = NULL, model_versions = NULL,
                               run_ids = NULL, categories = NULL,
                               score_classes = NULL, statuses = NULL,
                               source_supports = NULL, country = NULL,
                               bbox = NULL, depth_top_cm = NULL,
                               depth_bottom_cm = NULL,
                               with_geometry = c("none", "sf", "text"),
                               include_details = FALSE, max_rows = Inf,
                               progress = interactive()) {
  check_session(soil)
  body <- health_body(providers, datasets, release_ids, release_codes,
                      model_versions, run_ids, categories, score_classes,
                      statuses, source_supports, country, bbox, depth_top_cm,
                      depth_bottom_cm)
  with_geometry <- check_with_geometry(with_geometry)
  include_details <- check_flag(include_details, "include_details")
  max_rows <- check_max_rows(max_rows)
  progress <- check_flag(progress, "progress")
  what <- "`soil_health_scores()`"
  soil_require_right(soil, "soil:read", what)
  soil_require_capability(soil, "query_soil_health", what)
  if (!is.null(body$country)) soil_require_capability(soil, "country_filtering", paste(what, "with `country`"))
  body$include_geometry <- !identical(with_geometry, "none")
  body$include_details <- include_details
  schema <- c(health_schema, if (include_details) health_details_schema)
  collect_typed(soil, "/query/soil-health", body, "scores", max_rows, progress, function(pages) {
    frame <- records_frame(pages$items, schema, "POST /query/soil-health")
    frame <- thematic_geometry(frame, with_geometry)
    meta <- pages_metadata(soil, pages)
    meta$datasets <- unique(c(unlist(meta$request$datasets), stats::na.omit(frame$dataset_code)))
    if (!identical(with_geometry, "none")) meta$crs <- "EPSG:4326"
    new_soil_table(frame, meta, "health")
  })
}

#' Counts of soil-health scores
#'
#' Counts the scores a [soil_health_scores()] selection holds, without
#' reading them (`POST /query/soil-health/summary`): in total and by
#' dataset, release, source support, category, class and status.
#'
#' Rights: `soil:summary`. Capabilities: `query_soil_health`;
#' `country_filtering` for `country`.
#'
#' @inheritParams soil_health_scores
#' @return A `soil_health_summary` list: `total_score_count`,
#'   `feature_count`, `horizon_count` and the data frames `by_dataset`
#'   (`dataset`, `provider`, `score_count`, `feature_count`,
#'   `horizon_count`), `by_release` (`release_id`, `release_code`,
#'   `score_count`), `by_source_support` (`source_support`, `score_count`),
#'   `by_category` (`category`, `variable`, `score_count`), `by_class`
#'   (`score_class`, `score_count`), `by_status` (`score_status`,
#'   `score_count`), and `metadata`.
#' @family thematic reads
#' @examples
#' \dontrun{
#' soil_health_summary(soil, country = "TUN")$by_class
#' }
#' @export
soil_health_summary <- function(soil = soil_session(), providers = NULL,
                                datasets = NULL, release_ids = NULL,
                                release_codes = NULL, model_versions = NULL,
                                run_ids = NULL, categories = NULL,
                                score_classes = NULL, statuses = NULL,
                                source_supports = NULL, country = NULL,
                                bbox = NULL, depth_top_cm = NULL,
                                depth_bottom_cm = NULL) {
  check_session(soil)
  body <- health_body(providers, datasets, release_ids, release_codes,
                      model_versions, run_ids, categories, score_classes,
                      statuses, source_supports, country, bbox, depth_top_cm,
                      depth_bottom_cm)
  what <- "`soil_health_summary()`"
  soil_require_right(soil, "soil:summary", what)
  soil_require_capability(soil, "query_soil_health", what)
  if (!is.null(body$country)) soil_require_capability(soil, "country_filtering", paste(what, "with `country`"))
  response <- soil_request(soil, "POST", "/query/soil-health/summary", body = body, right = "soil:summary")
  context <- "POST /query/soil-health/summary"
  frame <- function(field, schema) records_frame(response[[field]], schema, context)
  structure(
    list(
      total_score_count = scalar_num(response$total_score_count, as.numeric, NA_real_),
      feature_count = scalar_num(response$feature_count, as.numeric, NA_real_),
      horizon_count = scalar_num(response$horizon_count, as.numeric, NA_real_),
      by_dataset = frame("by_dataset", list(
        dataset = "chr", provider = "chr", score_count = "dbl",
        feature_count = "dbl", horizon_count = "dbl"
      )),
      by_release = frame("by_release", list(release_id = "dbl", release_code = "chr", score_count = "dbl")),
      by_source_support = frame("by_source_support", list(source_support = "chr", score_count = "dbl")),
      by_category = frame("by_category", list(category = "chr", variable = "chr", score_count = "dbl")),
      by_class = frame("by_class", list(score_class = "chr", score_count = "dbl")),
      by_status = frame("by_status", list(score_status = "chr", score_count = "dbl")),
      metadata = response_metadata(soil, response, "/query/soil-health/summary", body)
    ),
    class = "soil_health_summary"
  )
}

#' @export
print.soil_health_summary <- function(x, ...) {
  cat(sprintf(
    "# soilhub soil-health summary: %s scores on %s horizons of %s features\n",
    format_count(x$total_score_count), format_count(x$horizon_count), format_count(x$feature_count)
  ))
  for (name in c("by_dataset", "by_category", "by_class", "by_status")) {
    if (nrow(x[[name]])) {
      cat(sprintf("\n%s:\n", sub("_", " ", sub("^by_", "By ", name))))
      print(x[[name]], row.names = FALSE)
    }
  }
  invisible(x)
}
