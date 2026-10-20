#' @include thematic.R results.R
NULL

# Externally published (derived) values (design 4.4, 5.5): POST /query/values,
# paged, typed into a `soil_table` with `soil_layout = "values"`, and
# POST /query/values/summary.

value_target_levels <- c("feature", "profile", "component", "horizon")
value_statuses <- c("published", "insufficient_data", "not_applicable")

values_schema <- list(
  value_id = "chr", variable_code = "chr", variable_name = "chr",
  domain_code = "chr", value_type = "chr", measurement_kind_code = "chr",
  target_level = "chr", feature_id = "chr", profile_id = "chr",
  component_id = "chr", horizon_id = "chr", dataset_code = "chr",
  provider_code = "chr", source_support = "chr", geometry_kind = "chr",
  geometry = "json", release_code = "chr", product_version_code = "chr",
  run_id = "dbl", numeric_value = "dbl", text_value = "chr",
  boolean_value = "lgl", json_value = "json", value_status = "chr",
  quality_code = "chr", valid_time_start = "time", valid_time_end = "time",
  depth_top_cm = "dbl", depth_bottom_cm = "dbl"
)

values_lineage_schema <- list(
  observation_inputs = "json", value_inputs = "json", release_inputs = "json",
  asset_inputs = "json"
)

# The filters shared by soil_values() and soil_values_summary(), as the body
# of `ValueQueryRequest`.
values_body <- function(providers, datasets, variables, domains,
                        measurement_kinds, target_levels, country, bbox,
                        valid_at, depth_top_cm, depth_bottom_cm,
                        product_versions, run_ids, statuses) {
  thematic_body(
    providers = check_filter(providers, "providers"),
    datasets = check_filter(datasets, "datasets"),
    variables = check_filter(variables, "variables"),
    domains = check_filter(domains, "domains"),
    measurement_kinds = check_filter(measurement_kinds, "measurement_kinds"),
    target_levels = check_values(target_levels, value_target_levels, "target_levels"),
    country = check_filter(country, "country"),
    bbox = check_bbox(bbox),
    valid_at = check_instant(valid_at, "valid_at"),
    depth_top_cm = check_number(depth_top_cm, "depth_top_cm"),
    depth_bottom_cm = check_number(depth_bottom_cm, "depth_bottom_cm"),
    product_versions = check_filter(product_versions, "product_versions"),
    run_ids = check_ids(run_ids, "run_ids"),
    statuses = check_values(statuses, value_statuses, "statuses")
  )
}

#' Published derived values
#'
#' Reads the values published by products (models, derivations, expert
#' assessments) on the features, profiles, components and horizons of the
#' Global Soil Data Hub (`POST /query/values`), page by page, as a typed
#' table: one row per value, with its variable, target, product version and
#' run, status, validity time and depth.
#'
#' `value` holds the value in its own type: a double column when every
#' value read is numeric, character for text, logical for boolean, else a
#' list column with each value in its type (`json` values as parsed lists).
#' The API columns `numeric_value`, `text_value`, `boolean_value` and
#' `json_value` are kept as returned.
#'
#' Filters are combined with AND; each takes several values (OR within the
#' filter). `NULL` means no filter.
#'
#' Rights: `soil:read`. Capabilities: `query_generic_values`;
#' `country_filtering` for `country`.
#'
#' @param soil A session; the default session when omitted. Client-side: not sent to the API.
#' @param providers Provider codes of the targets (`"isric"`). API field `providers`.
#' @param datasets Catalog dataset codes of the targets. API field `datasets`.
#' @param variables Variable codes (see [soil_variables()]). API field `variables`.
#' @param domains Domain codes of the variables. API field `domains`.
#' @param measurement_kinds Measurement kinds of the variables (`"derived"`,
#'   `"modelled"`, ...). API field `measurement_kinds`.
#' @param target_levels `"feature"`, `"profile"`, `"component"`,
#'   `"horizon"`. API field `target_levels`.
#' @param country Countries as ISO 3166 alpha-2 or alpha-3 codes or names. API field `country`.
#' @param bbox `c(xmin, ymin, xmax, ymax)` in WGS84 degrees. API field `bbox`.
#' @param valid_at A date-time (POSIXct, Date or ISO 8601 text): only the
#'   values valid at that instant (`valid_time_start <= valid_at <
#'   valid_time_end`, open ends included). API field `valid_at`.
#' @param depth_top_cm,depth_bottom_cm Depth interval in cm: the values whose
#'   depth interval overlaps it (values without depth included). API fields `depth_top_cm` and
#'   `depth_bottom_cm`.
#' @param product_versions Product version codes. API field `product_versions`.
#' @param run_ids Run ids. API field `run_ids`.
#' @param statuses Value statuses: `"published"`, `"insufficient_data"`,
#'   `"not_applicable"`. API field `statuses`.
#' @param with_geometry `"none"`, `"text"` (the geometry of the target's
#'   feature as GeoJSON text in `geometry_text`, EPSG:4326) or `"sf"` (an
#'   `sf` object with a `geometry` column; needs the package `sf`, else a
#'   `soilhub_dependency_error`). Client-side; sets the API field `include_geometry` (`false` for
#'   `"none"`), the form is built locally.
#' @param include_lineage Add the lineage list columns `observation_inputs`,
#'   `value_inputs`, `release_inputs`, `asset_inputs` (what each value was
#'   computed from). API field `include_lineage`.
#' @param max_rows Maximum number of values to read (`Inf`: all). Client-side; caps the API field
#'   `limit` of each page request.
#' @param progress Report the pages read. Client-side: not sent to the API.
#' @return A `soil_table` (see [soil_table]) with `soil_layout = "values"`:
#'   `value_id`, `variable_code`, `variable_name`, `domain_code`,
#'   `value_type`, `measurement_kind_code`, `target_level`, `feature_id`,
#'   `profile_id`, `component_id`, `horizon_id`, `dataset_code`,
#'   `provider_code`, `source_support`, `geometry_kind`, (`geometry_text`),
#'   `release_code`, `product_version_code`, `run_id`, `value`,
#'   `numeric_value`, `text_value`, `boolean_value`, `json_value` (list),
#'   `value_status`, `quality_code`, `valid_time_start`, `valid_time_end`
#'   (POSIXct UTC), `depth_top_cm`, `depth_bottom_cm`, and the lineage
#'   columns. `soil_metadata(x)$total_count` is the number of values of the
#'   selection.
#' @family thematic reads
#' @seealso [soil_values_summary()] to count before reading,
#'   [soil_publish_values()] to publish.
#' @examples
#' \dontrun{
#' v <- soil_values(soil, variables = "soc_stock_0_30", country = "KEN",
#'                  statuses = "published", include_lineage = TRUE)
#' v[, c("target_level", "horizon_id", "value", "run_id")]
#' }
#' @export
soil_values <- function(soil = soil_session(), providers = NULL,
                        datasets = NULL, variables = NULL, domains = NULL,
                        measurement_kinds = NULL, target_levels = NULL,
                        country = NULL, bbox = NULL, valid_at = NULL,
                        depth_top_cm = NULL, depth_bottom_cm = NULL,
                        product_versions = NULL, run_ids = NULL,
                        statuses = NULL,
                        with_geometry = c("none", "sf", "text"),
                        include_lineage = FALSE, max_rows = Inf,
                        progress = interactive()) {
  check_session(soil)
  body <- values_body(providers, datasets, variables, domains, measurement_kinds,
                      target_levels, country, bbox, valid_at, depth_top_cm,
                      depth_bottom_cm, product_versions, run_ids, statuses)
  with_geometry <- check_with_geometry(with_geometry, "`soil_values()`")
  include_lineage <- check_flag(include_lineage, "include_lineage")
  max_rows <- check_max_rows(max_rows)
  progress <- check_flag(progress, "progress")
  what <- "`soil_values()`"
  soil_require_right(soil, "soil:read", what)
  soil_require_capability(soil, "query_generic_values", what)
  if (!is.null(body$country)) soil_require_capability(soil, "country_filtering", paste(what, "with `country`"))
  body$include_geometry <- !identical(with_geometry, "none")
  body$include_lineage <- include_lineage
  schema <- c(values_schema, if (include_lineage) values_lineage_schema)
  collect_typed(soil, "/query/values", body, "values", max_rows, progress, function(pages) {
    values_table(soil, pages, schema, with_geometry)
  })
}

values_table <- function(soil, pages, schema, with_geometry) {
  frame <- records_frame(pages$items, schema, "POST /query/values")
  frame <- thematic_geometry(frame, with_geometry)
  frame <- with_typed_value(frame)
  frame <- thematic_as_sf(frame, with_geometry)
  meta <- pages_metadata(soil, pages)
  meta$datasets <- unique(c(unlist(meta$request$datasets), stats::na.omit(frame$dataset_code)))
  if (!identical(with_geometry, "none")) meta$crs <- "EPSG:4326"
  new_soil_table(frame, meta, "values")
}

# `value`: the value of each row in its own type (`value_type`), placed
# before `numeric_value`.
with_typed_value <- function(frame) {
  n <- nrow(frame)
  types <- unique(stats::na.omit(frame$value_type))
  pick <- function(i) {
    switch(frame$value_type[[i]] %||% NA_character_,
      numeric = frame$numeric_value[[i]],
      text = frame$text_value[[i]],
      boolean = frame$boolean_value[[i]],
      json = frame$json_value[[i]],
      NULL
    )
  }
  value <- if (length(types) == 0L) {
    rep(NA_real_, n)
  } else if (length(types) == 1L && types %in% c("numeric", "text", "boolean")) {
    switch(types, numeric = frame$numeric_value, text = frame$text_value, boolean = frame$boolean_value)
  } else {
    lapply(seq_len(n), function(i) if (is.na(frame$value_type[[i]])) NULL else pick(i))
  }
  columns <- unclass(frame)
  at <- match("numeric_value", names(columns))
  if (is.na(at)) at <- length(columns) + 1L
  columns <- append(columns, list(value = value), after = at - 1L)
  new_frame(columns, n)
}

#' Counts of published derived values
#'
#' Counts the values a [soil_values()] selection holds, without reading
#' them (`POST /query/values/summary`): in total, by variable, by dataset,
#' by target level and by status.
#'
#' Rights: `soil:summary`. Capabilities: `query_generic_values`;
#' `country_filtering` for `country`.
#'
#' @inheritParams soil_values
#' @return A `soil_values_summary` list: `total_value_count`,
#'   `feature_count`, `variables` (data frame `code`, `domain`),
#'   `by_dataset` (data frame `dataset`, `provider`, `value_count`,
#'   `feature_count`, `variable_count`), `by_target_level` and `by_status`
#'   (named doubles), `metadata`.
#' @family thematic reads
#' @examples
#' \dontrun{
#' soil_values_summary(soil, country = "KEN")$by_status
#' }
#' @export
soil_values_summary <- function(soil = soil_session(), providers = NULL,
                                datasets = NULL, variables = NULL,
                                domains = NULL, measurement_kinds = NULL,
                                target_levels = NULL, country = NULL,
                                bbox = NULL, valid_at = NULL,
                                depth_top_cm = NULL, depth_bottom_cm = NULL,
                                product_versions = NULL, run_ids = NULL,
                                statuses = NULL) {
  check_session(soil)
  body <- values_body(providers, datasets, variables, domains, measurement_kinds,
                      target_levels, country, bbox, valid_at, depth_top_cm,
                      depth_bottom_cm, product_versions, run_ids, statuses)
  what <- "`soil_values_summary()`"
  soil_require_right(soil, "soil:summary", what)
  soil_require_capability(soil, "query_generic_values", what)
  if (!is.null(body$country)) soil_require_capability(soil, "country_filtering", paste(what, "with `country`"))
  response <- soil_request(soil, "POST", "/query/values/summary", body = body, right = "soil:summary")
  context <- "POST /query/values/summary"
  structure(
    list(
      total_value_count = scalar_num(response$total_value_count, as.numeric, NA_real_),
      feature_count = scalar_num(response$feature_count, as.numeric, NA_real_),
      variables = records_frame(response$variables, list(code = "chr", domain = "chr"), context),
      by_dataset = records_frame(response$by_dataset, list(
        dataset = "chr", provider = "chr", value_count = "dbl",
        feature_count = "dbl", variable_count = "dbl"
      ), context),
      by_target_level = named_counts(response$by_target_level),
      by_status = named_counts(response$by_status),
      metadata = response_metadata(soil, response, "/query/values/summary", body)
    ),
    class = "soil_values_summary"
  )
}

#' @export
print.soil_values_summary <- function(x, ...) {
  cat(sprintf(
    "# soilhub values summary: %s values on %s features, %d variable(s)\n",
    format_count(x$total_value_count), format_count(x$feature_count), nrow(x$variables)
  ))
  if (nrow(x$by_dataset)) {
    cat("\nBy dataset:\n")
    print(x$by_dataset, row.names = FALSE)
  }
  show <- function(title, counts) {
    if (!length(counts)) return(invisible())
    cat(sprintf("\n%s: %s\n", title, paste(sprintf("%s %s", names(counts), format_count(counts)), collapse = ", ")))
  }
  show("By target level", x$by_target_level)
  show("By status", x$by_status)
  invisible(x)
}
