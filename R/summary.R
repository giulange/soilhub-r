#' @include selection.R thematic.R
NULL

# Summaries of a selection (design 4.4, 5.5): POST /query/summary and
# POST /query/availability with the canonical selection of the reads
# (soil_selection(), `canonical = true`), and POST /query/consistency, the
# authoritative distinct totals of the daily statistics (its own request:
# no view, profile_type, components or canonical, fact 12.2.7).

semantics_schema <- list(
  dataset = "chr", source_code = "chr", canonical_property_key = "chr",
  canonical_name = "chr", property_family = "chr", source_unit = "chr",
  procedure_code = "chr", procedure_description = "chr",
  source_value_kind = "chr", mapping_status = "chr",
  documentation_url = "chr", source_notes = "chr"
)

variant_schema <- list(
  source_scope = "chr", canonical_property_key = "chr", source_unit = "chr",
  source_notes = "chr"
)

availability_variable_schema <- list(
  dataset = "chr", country_code = "chr", country_name = "chr",
  property_code = "chr", canonical_property_key = "chr", canonical_name = "chr",
  property_family = "chr", source_unit = "chr", procedure_code = "chr",
  procedure_description = "chr", source_value_kind = "chr",
  mapping_status = "chr", documentation_url = "chr", source_notes = "chr",
  variants = frames(variant_schema), feature_count = "dbl",
  horizon_count = "dbl", observation_count = "dbl"
)

availability_dataset_schema <- list(
  dataset = "chr", geometry = "chr", country_code = "chr",
  country_name = "chr", feature_count = "dbl", horizon_count = "dbl",
  observation_count = "dbl"
)

availability_country_schema <- list(
  country_code = "chr", country_name = "chr", feature_count = "dbl",
  horizon_count = "dbl", observation_count = "dbl"
)

consistency_schema <- list(
  iso_a3 = "chr", country_name = "chr", provider_code = "chr",
  dataset_code = "chr", variable_code = "chr", refreshed_at = "time",
  variables = "chr_list"
)

# ---------------------------------------------------------------------------
# soil_summary()

#' What a selection holds, before reading it
#'
#' Counts the features, horizons and observations of a selection, the
#' variables it holds and what they mean, without transferring the data
#' (`POST /query/summary`, `canonical = true`). The counts are those the reads
#' return for the same selection: `feature_count` is the number of features of
#' `soil_features()` (`layer` and `components` do not apply to it),
#' `horizon_count` the rows of the wide layout of [soil_observations()],
#' `observation_count` the rows of its long layout. It is also the sizing
#' step before an export: a selection above the limit of synchronous reads
#' (`soil_capabilities()$limits$max_sync_observations`) is read with
#' `soil_export()`.
#'
#' The arguments are the selection of [soil_observations()], validated the
#' same way before any request and sent with the same API names.
#'
#' Rights: `soil:summary`. Capabilities: `canonical_summary`; `revised_view`
#' for `view = "revised"`, `profile_type_filter` for `profile_type`,
#' `component_selection` for `components`.
#'
#' @inheritParams soil_observations
#' @return A `soil_summary` list:
#'   * `datasets` (character), `geometry`;
#'   * `feature_count`, `horizon_count`, `observation_count`,
#'     `observed_feature_count` (features with at least one horizon row) and
#'     each `<count>_by_dataset` (named double; with one dataset its total);
#'   * `avg_horizons_per_feature` (horizon rows per observed feature) and
#'     `avg_horizons_per_feature_by_dataset`;
#'   * `by_dataset`: a data frame of the same counts, one row per dataset;
#'   * `variables` (source codes, character), `variables_by_dataset` (named
#'     list of character), `variable_semantics` (data frame `dataset`,
#'     `source_code`, `canonical_property_key`, `canonical_name`,
#'     `property_family`, `source_unit`, `procedure_code`,
#'     `procedure_description`, `source_value_kind`, `mapping_status`,
#'     `documentation_url`, `source_notes`);
#'   * `formats` (export formats), `warnings`;
#'   * `view`, `revised` (with `view = "revised"`: the rules applied with
#'     their counts, see [soil_revised_rules()]), `components` and
#'     `min_cumulative_percent` (when a component dataset is selected);
#'   * `metadata` (see [soil_metadata()]): the request, its id, versions and
#'     the catalog rows of the datasets for [soil_citations()].
#'
#'   Printing shows a short report: counts per dataset, the variables, the
#'   warnings and the revised rules.
#' @family summaries
#' @seealso [soil_availability()] for the counts by country and variable,
#'   [soil_consistency()] for the distinct totals of the daily statistics.
#' @examples
#' \dontrun{
#' s <- soil_summary(soil, datasets = c("wosis_points", "wise_profiles"), country = "KEN")
#' s
#' s$observation_count_by_dataset
#' s$variable_semantics[, c("dataset", "source_code", "canonical_property_key")]
#' soil_citations(s)
#'
#' # the revised view lists the rules it applies to the selection
#' soil_revised_rules(soil_summary(soil, datasets = "sotwis_polygons", view = "revised"))
#' }
#' @export
soil_summary <- function(soil = soil_session(), datasets = NULL,
                         variables = NULL, bbox = NULL, country = NULL,
                         geometry = "any", layer = "all", view = "raw",
                         profile_type = NULL, components = NULL,
                         min_cumulative_percent = NULL) {
  check_session(soil)
  body <- soil_selection(
    soil, datasets = datasets, variables = variables, bbox = bbox,
    country = country, geometry = geometry, layer = layer, view = view,
    profile_type = profile_type, components = components,
    min_cumulative_percent = min_cumulative_percent
  )
  what <- "`soil_summary()`"
  soil_require_right(soil, "soil:summary", what)
  soil_require_capability(soil, "canonical_summary", what)
  require_selection_capabilities(soil, body, what)
  selection <- attr(body, "selection")
  attr(body, "selection") <- NULL
  response <- soil_request(soil, "POST", "/query/summary", body = body, right = "soil:summary")
  summary_result(soil, response, body, selection)
}

summary_result <- function(soil, response, body, selection, fetch_catalog = TRUE) {
  meta <- response_metadata(soil, response, "/query/summary", body, selection)
  datasets <- as.character(unlist(response$datasets %||% meta$datasets))
  meta$datasets <- metadata_datasets(soil, datasets, fetch_catalog)
  meta$view <- scalar_chr(meta$view %||% body$view %||% "raw")

  counts <- list(
    feature_count = scalar_num(response$feature_count, as.numeric, NA_real_),
    horizon_count = scalar_num(response$horizon_count, as.numeric, NA_real_),
    observation_count = scalar_num(meta$observation_count, as.numeric, NA_real_),
    observed_feature_count = scalar_num(meta$observed_feature_count, as.numeric, NA_real_)
  )
  by <- list(
    feature_count_by_dataset = dataset_counts(response$feature_count_by_dataset, datasets, counts$feature_count),
    horizon_count_by_dataset = dataset_counts(response$horizon_count_by_dataset, datasets, counts$horizon_count),
    observation_count_by_dataset = dataset_counts(meta$observation_count_by_dataset, datasets, counts$observation_count),
    observed_feature_count_by_dataset = dataset_counts(meta$observed_feature_count_by_dataset, datasets, counts$observed_feature_count),
    avg_horizons_per_feature_by_dataset = dataset_counts(
      response$avg_horizons_per_feature_by_dataset, datasets,
      response$avg_horizons_per_feature
    )
  )
  pick <- function(values) unname(values[datasets] %||% rep(NA_real_, length(datasets)))
  by_dataset <- new_frame(list(
    dataset = datasets,
    feature_count = pick(by$feature_count_by_dataset),
    horizon_count = pick(by$horizon_count_by_dataset),
    observation_count = pick(by$observation_count_by_dataset),
    observed_feature_count = pick(by$observed_feature_count_by_dataset),
    avg_horizons_per_feature = pick(by$avg_horizons_per_feature_by_dataset)
  ), length(datasets))

  semantics <- list()
  for (dataset in names(response$variable_semantics_by_dataset)) {
    for (record in response$variable_semantics_by_dataset[[dataset]]) {
      semantics[[length(semantics) + 1L]] <- c(list(dataset = dataset), record)
    }
  }
  variables_by_dataset <- lapply(response$variables_by_dataset %||% list(), function(codes) {
    vapply(codes, scalar_chr, character(1), USE.NAMES = FALSE)
  })

  structure(
    list(
      datasets = datasets,
      geometry = scalar_chr(response$geometry %||% body$geometry),
      feature_count = counts$feature_count,
      feature_count_by_dataset = by$feature_count_by_dataset,
      horizon_count = counts$horizon_count,
      horizon_count_by_dataset = by$horizon_count_by_dataset,
      observation_count = counts$observation_count,
      observation_count_by_dataset = by$observation_count_by_dataset,
      observed_feature_count = counts$observed_feature_count,
      observed_feature_count_by_dataset = by$observed_feature_count_by_dataset,
      avg_horizons_per_feature = scalar_num(response$avg_horizons_per_feature, as.numeric, NA_real_),
      avg_horizons_per_feature_by_dataset = by$avg_horizons_per_feature_by_dataset,
      by_dataset = by_dataset,
      variables = vapply(response$variables %||% list(), scalar_chr, character(1)),
      variables_by_dataset = variables_by_dataset,
      variable_semantics = records_frame(semantics, semantics_schema, "POST /query/summary (variable semantics)"),
      formats = vapply(response$formats %||% list(), scalar_chr, character(1)),
      warnings = as.character(unlist(response$warnings)) %||% character(),
      view = meta$view,
      revised = meta$revised,
      components = meta$components,
      min_cumulative_percent = meta$min_cumulative_percent,
      metadata = meta
    ),
    class = "soil_summary"
  )
}

#' @export
print.soil_summary <- function(x, ...) {
  request <- x$metadata$request %||% list()
  cat(sprintf(
    "# soilhub summary: %s features, %s horizons, %s observations | %s | view %s, layer %s\n",
    format_count(x$feature_count), format_count(x$horizon_count),
    format_count(x$observation_count),
    if (length(x$datasets)) paste(x$datasets, collapse = ", ") else "no dataset",
    x$view %||% "raw", request$layer %||% "all"
  ))
  if (!is.null(x$components)) {
    cat(sprintf(
      "# components: %s%s\n", x$components,
      if (is.null(x$min_cumulative_percent)) "" else sprintf(" (min_cumulative_percent %s)", format(x$min_cumulative_percent))
    ))
  }
  cat("\nCounts per dataset:\n")
  if (nrow(x$by_dataset)) {
    shown <- x$by_dataset
    for (name in setdiff(names(shown), c("dataset", "avg_horizons_per_feature"))) {
      shown[[name]] <- ifelse(is.na(shown[[name]]), "NA", format_count(shown[[name]]))
    }
    names(shown) <- sub("_count$", "s", names(shown))
    names(shown)[names(shown) == "avg_horizons_per_feature"] <- "horizons/feature"
    print(shown, row.names = FALSE)
  } else {
    cat("  none\n")
  }
  n <- length(x$variables)
  cat(sprintf("\nVariables (%d): ", n))
  if (n) {
    shown <- utils::head(x$variables, 20L)
    cat(paste(shown, collapse = ", "), if (n > length(shown)) sprintf(", ... (%d more)", n - length(shown)) else "", "\n", sep = "")
  } else {
    cat("none\n")
  }
  if (length(x$warnings)) {
    cat("\nWarnings:\n")
    cat(paste0("  - ", x$warnings), sep = "\n")
  }
  if (identical(x$view, "revised")) {
    rules <- soil_revised_rules(x)
    cat("\nRevised rules applied (soil_revised_rules):\n")
    if (nrow(rules)) {
      print(rules[, c("id", "effect", "n")], row.names = FALSE)
    } else {
      cat("  none in this selection\n")
    }
  }
  cat("\n# variable meanings in x$variable_semantics; cite with soil_citations(x)\n")
  invisible(x)
}

# ---------------------------------------------------------------------------
# soil_availability()

#' What exists by dataset, country and variable
#'
#' Counts the features, horizons and observations of a selection by dataset,
#' by country and by variable, with the meaning of each source variable in
#' each dataset (`POST /query/availability`, `canonical = true`). A feature
#' assigned to several countries (the country filter of the API selects the
#' features that intersect a country) counts under each of them, so the
#' country rows must not be summed: the dataset totals count every feature
#' once. Features without a country are grouped under an `NA` country.
#'
#' The arguments are the selection of [soil_observations()], validated the
#' same way before any request.
#'
#' Rights: `soil:summary`. Capabilities: `canonical_summary`; `revised_view`
#' for `view = "revised"`, `profile_type_filter` for `profile_type`,
#' `component_selection` for `components`.
#'
#' @inheritParams soil_observations
#' @return A `soil_availability` list of data frames:
#'   * `datasets`: one row per dataset, `dataset`, `geometry` (`"point"`,
#'     `"polygon"`), `feature_count`, `horizon_count`, `observation_count`
#'     (distinct totals of the dataset);
#'   * `countries`: `country_code`, `country_name`, `feature_count`,
#'     `horizon_count`, `observation_count`;
#'   * `dataset_countries`: one row per dataset and country, the same counts
#'     (`by_dataset` of the API);
#'   * `variables`: one row per dataset, country and source variable:
#'     `dataset`, `country_code`, `country_name`, `property_code` (the
#'     source code), `canonical_property_key`, `canonical_name`,
#'     `property_family`, `source_unit`, `procedure_code`,
#'     `procedure_description`, `source_value_kind`, `mapping_status`,
#'     `documentation_url`, `source_notes`, `variants` (list of data frames
#'     `source_scope`, `canonical_property_key`, `source_unit`,
#'     `source_notes`: the meanings of the code in parts of the dataset),
#'     `feature_count`, `horizon_count`, `observation_count`;
#'
#'   and `metadata` (see [soil_metadata()]).
#' @family summaries
#' @examples
#' \dontrun{
#' a <- soil_availability(soil, datasets = "soter_profiles", country = "KEN")
#' a$datasets
#' totc <- a$variables[a$variables$property_code == "TOTC", ]
#' totc[, c("country_code", "source_unit", "observation_count")]
#' }
#' @export
soil_availability <- function(soil = soil_session(), datasets = NULL,
                              variables = NULL, bbox = NULL, country = NULL,
                              geometry = "any", layer = "all", view = "raw",
                              profile_type = NULL, components = NULL,
                              min_cumulative_percent = NULL) {
  check_session(soil)
  body <- soil_selection(
    soil, datasets = datasets, variables = variables, bbox = bbox,
    country = country, geometry = geometry, layer = layer, view = view,
    profile_type = profile_type, components = components,
    min_cumulative_percent = min_cumulative_percent
  )
  what <- "`soil_availability()`"
  soil_require_right(soil, "soil:summary", what)
  soil_require_capability(soil, "canonical_summary", what)
  require_selection_capabilities(soil, body, what)
  selection <- attr(body, "selection")
  attr(body, "selection") <- NULL
  response <- soil_request(soil, "POST", "/query/availability", body = body, right = "soil:summary")
  availability_result(soil, response, body, selection)
}

availability_result <- function(soil, response, body, selection, fetch_catalog = TRUE) {
  context <- "POST /query/availability"
  meta <- response_metadata(soil, response, "/query/availability", body, selection)
  names <- as.character(unlist(meta$datasets))
  meta$datasets <- metadata_datasets(soil, names, fetch_catalog)
  meta$view <- scalar_chr(meta$view %||% body$view %||% "raw")

  rows <- response$by_dataset %||% list()
  variables <- list()
  for (row in rows) {
    for (variable in row$variables %||% list()) {
      variables[[length(variables) + 1L]] <- c(
        list(dataset = row$dataset, country_code = row$country_code, country_name = row$country_name),
        variable
      )
    }
  }
  dataset_countries <- records_frame(
    lapply(rows, function(row) row[setdiff(names(row), "variables")]),
    availability_dataset_schema, context
  )
  countries <- records_frame(
    lapply(response$by_country %||% list(), function(row) row[setdiff(names(row), "by_dataset")]),
    availability_country_schema, context
  )

  totals <- function(field) {
    dataset_counts(meta[[paste0(field, "_by_dataset")]], names, meta[[field]])
  }
  geometry <- vapply(names, function(name) {
    found <- dataset_countries$geometry[dataset_countries$dataset == name]
    if (length(found)) found[[1]] else NA_character_
  }, character(1), USE.NAMES = FALSE)
  pick <- function(values) unname(values[names] %||% rep(NA_real_, length(names)))
  datasets <- new_frame(list(
    dataset = names,
    geometry = geometry,
    feature_count = pick(totals("feature_count")),
    horizon_count = pick(totals("horizon_count")),
    observation_count = pick(totals("observation_count"))
  ), length(names))

  structure(
    list(
      datasets = datasets,
      countries = countries,
      dataset_countries = dataset_countries,
      variables = records_frame(variables, availability_variable_schema, context),
      metadata = meta
    ),
    class = "soil_availability"
  )
}

#' @export
print.soil_availability <- function(x, ...) {
  cat(sprintf(
    "# soilhub availability: %d dataset(s), %d countr%s, %d variable row(s) | view %s\n",
    nrow(x$datasets), nrow(x$countries), if (nrow(x$countries) == 1L) "y" else "ies",
    nrow(x$variables), x$metadata$view %||% "raw"
  ))
  cat("\nDatasets (distinct totals):\n")
  print(x$datasets, row.names = FALSE)
  if (nrow(x$countries)) {
    cat("\nCountries (a feature in several countries counts in each):\n")
    print(utils::head(x$countries, 10L), row.names = FALSE)
    if (nrow(x$countries) > 10L) cat(sprintf("# ... %d more countr%s\n", nrow(x$countries) - 10L, if (nrow(x$countries) == 11L) "y" else "ies"))
  }
  cat("\n# variables by dataset and country in x$variables\n")
  invisible(x)
}

# ---------------------------------------------------------------------------
# soil_consistency()

#' Authoritative distinct totals
#'
#' The distinct counts of features, profiles, horizons, observations and
#' variables of a selection, as the daily statistics of the Global Soil Data
#' Hub compute them (`POST /query/consistency`): the totals count every
#' feature, profile and horizon once, so they are the numbers to quote; the
#' country rows count a feature in each country it intersects and **must
#' never be summed**. Without filters, or with one country and no other
#' filter than `providers` and `datasets`, the API reads the daily statistics
#' (`metadata$calculation = "summary"`, `as_of` the refresh time); other
#' selections are counted live (`"live"`).
#'
#' This endpoint has its own request: it takes no `view`, `profile_type`,
#' `components` or `canonical`, and its counts include the published derived
#' values (`value_count`), so they differ by design from [soil_summary()].
#'
#' Rights: `soil:summary`. Capability: `unified_consistency`.
#'
#' @param soil A session; the default session when omitted. Client-side: not sent to the API.
#' @param providers Provider codes (`"isric"`), `NULL` for all. API field `providers`.
#' @param datasets Catalog dataset codes, `NULL` for all. API field `datasets`.
#' @param geometry `NULL` (all), or `"point"` and/or `"polygon"`. API field `geometry`.
#' @param country Countries as ISO 3166 alpha-2 or alpha-3 codes. API field `country`.
#' @param bbox `c(xmin, ymin, xmax, ymax)` in WGS84 degrees. API field `bbox`.
#' @param variables Canonical variable codes or source codes. API field `variables`.
#' @return A `soil_consistency` list: `totals` (named list: `feature_count`,
#'   `point_count`, `polygon_count`, `profile_count`, `horizon_count`,
#'   `original_observation_count`, `value_count`, `observation_count`,
#'   `variable_count`, `dataset_count` as doubles and `variables`
#'   character), `countries`, `datasets` and `variables` (data frames, the
#'   columns of the calculation used: counts double, `refreshed_at` POSIXct)
#'   and `metadata` (`calculation`, `as_of` POSIXct, `summary_scope`,
#'   `country_assignment`, the request).
#' @family summaries
#' @examples
#' \dontrun{
#' k <- soil_consistency(soil, country = "KEN")
#' k$totals$feature_count
#' k$metadata$calculation
#' }
#' @export
soil_consistency <- function(soil = soil_session(), providers = NULL,
                             datasets = NULL, geometry = NULL, country = NULL,
                             bbox = NULL, variables = NULL) {
  check_session(soil)
  body <- thematic_body(
    providers = check_filter(providers, "providers"),
    datasets = check_filter(datasets, "datasets"),
    geometry = as_array(check_values(geometry, c("point", "polygon"), "geometry")),
    country = check_filter(country, "country"),
    bbox = check_bbox(bbox),
    variables = check_filter(variables, "variables")
  )
  what <- "`soil_consistency()`"
  soil_require_right(soil, "soil:summary", what)
  soil_require_capability(soil, "unified_consistency", what)
  response <- soil_request(soil, "POST", "/query/consistency", body = body, right = "soil:summary")
  consistency_result(soil, response, body)
}

consistency_result <- function(soil, response, body) {
  meta <- response_metadata(soil, response, "/query/consistency", body)
  meta$calculation <- scalar_chr(meta$calculation)
  meta$as_of <- parse_api_time(scalar_chr(meta$as_of))
  totals <- response$totals %||% list()
  totals <- lapply(stats::setNames(names(totals), names(totals)), function(name) {
    value <- totals[[name]]
    if (identical(name, "variables")) return(vapply(value %||% list(), scalar_chr, character(1)))
    if (is.list(value)) return(value)
    scalar_num(value, as.numeric, NA_real_)
  })
  structure(
    list(
      totals = totals,
      countries = loose_frame(response$countries, consistency_schema),
      datasets = loose_frame(response$datasets, consistency_schema),
      variables = loose_frame(response$variables, consistency_schema),
      metadata = meta
    ),
    class = "soil_consistency"
  )
}

#' @export
print.soil_consistency <- function(x, ...) {
  meta <- x$metadata
  cat(sprintf(
    "# soilhub consistency (%s%s): distinct totals, never sum the countries\n",
    meta$calculation %||% "?",
    if (length(meta$as_of) && !is.na(meta$as_of)) paste0(", as of ", format_time(meta$as_of)) else ""
  ))
  counts <- x$totals[setdiff(names(x$totals), "variables")]
  counts <- counts[vapply(counts, function(v) is.numeric(v) && length(v) == 1L, logical(1))]
  for (name in names(counts)) cat(sprintf("  %-27s %s\n", name, format_count(counts[[name]])))
  cat(sprintf("# %d dataset row(s), %d country row(s), %d variable row(s)\n",
              nrow(x$datasets), nrow(x$countries), nrow(x$variables)))
  invisible(x)
}
