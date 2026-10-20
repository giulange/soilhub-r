#' @include typing.R
NULL

# The variable catalog (design 4.3): registered variables, where they are
# available, and what each source code means in each dataset.

method_facet_schema <- list(
  facet_key = "chr", facet_value = "chr", element_count = "dbl",
  source_dataset_counts = "json"
)

source_mapping_schema <- list(
  provider_code = "chr", dataset_code = "chr", source_code = "chr",
  source_official_code = "chr", source_label = "chr", source_unit = "chr",
  procedure_code = "chr", procedure_description = "chr",
  source_value_kind = "chr", mapping_status = "chr",
  documentation_url = "chr", semantic_status = "chr", unit_status = "chr",
  unit_evidence = "json", source_notes = "chr", source_scope = "chr",
  method_facets = frames(method_facet_schema)
)

variable_schema <- list(
  variable_code = "chr", name = "chr", description = "chr",
  domain_code = "chr", value_type = "chr", measurement_kind_code = "chr",
  allowed_target_levels = "chr_list", property_family = "chr",
  property_family_name = "chr", documentation_url = "chr",
  value_count = "dbl", feature_count = "dbl",
  datasets = "chr_list", providers = "chr_list",
  available_target_levels = "chr_list", statuses = "chr_list",
  product_versions = "chr_list",
  min_depth_cm = "dbl", max_depth_cm = "dbl",
  valid_time_start = "time", valid_time_end = "time",
  coverage = "json",
  source_mappings = frames(source_mapping_schema)
)

unmapped_schema <- list(
  provider_code = "chr", dataset_code = "chr", source_code = "chr",
  observation_count = "dbl"
)

#' The variable catalog
#'
#' The registered variables (`GET /variables`): canonical soil properties
#' (`organic_carbon`, `clay`, ...) and variables published by products, with
#' where they are available and, for each one, the source codes that map to
#' it in each dataset (`source_mappings`, see [soil_variable_mappings()]).
#'
#' Every filter is optional (`NULL`, the default, means no filter; `"ALL"`
#' is not accepted) and takes several values.
#'
#' Rights: `soil:summary`.
#'
#' @param soil A session; the default session when omitted. Client-side: not sent to the API.
#' @param code Variable codes (`variable_code`, e.g. `"organic_carbon"`). API query parameter
#'   `code`.
#' @param domain Domains (`domain_code`, e.g. `"soil"`). API query parameter `domain`.
#' @param measurement_kind Measurement kinds (`measurement_kind_code`, e.g.
#'   `"observed"`). API query parameter `measurement_kind`.
#' @param target_level Target levels allowed for the variable (`"horizon"`,
#'   `"profile"`, `"feature"`, ...). API query parameter `target_level`.
#' @param dataset Datasets where the variable has values or a source mapping
#'   (e.g. `"wosis_points"`); the mappings are limited to them too. API query parameter `dataset`.
#' @param provider Providers (e.g. `"isric"`), as `dataset`. API query parameter `provider`.
#' @param available_only Only variables with at least one value. API query parameter
#'   `available_only`.
#' @param include_unmapped Also list the source codes that map to no
#'   variable, in `soil_metadata(x)$unmapped_source_codes`. API query parameter `include_unmapped`.
#' @return A data frame, one row per variable: `variable_code`, `name`,
#'   `description`, `domain_code`, `value_type`, `measurement_kind_code`,
#'   `allowed_target_levels` (list), `property_family`,
#'   `property_family_name`, `documentation_url`, the counts of published
#'   values `value_count` and `feature_count`, `datasets`, `providers`,
#'   `available_target_levels`, `statuses`, `product_versions` (lists of
#'   character), `min_depth_cm`, `max_depth_cm`, `valid_time_start`,
#'   `valid_time_end`, `coverage` (list: the GeoJSON extent of the published
#'   values, `NULL` when none) and `source_mappings` (list of data frames, see
#'   [soil_variable_mappings()]). The attribute `soil_metadata` holds
#'   `variable_count`, `unmapped_included`, `unmapped_source_code_count`,
#'   `unmapped_source_codes` (data frame `provider_code`, `dataset_code`,
#'   `source_code`, `observation_count`), the `request` and `retrieved_at`.
#' @family discovery
#' @seealso [soil_variable_mappings()]
#' @examples
#' \dontrun{
#' v <- soil_variables(soil, dataset = "wise_profiles")
#' v[, c("variable_code", "name", "property_family")]
#' soil_variable_mappings(v)
#' }
#' @export
soil_variables <- function(soil = soil_session(), code = NULL, domain = NULL,
                           measurement_kind = NULL, target_level = NULL,
                           dataset = NULL, provider = NULL,
                           available_only = FALSE, include_unmapped = FALSE) {
  check_session(soil)
  query <- list(
    code = check_filter(code, "code"),
    domain = check_filter(domain, "domain"),
    measurement_kind = check_filter(measurement_kind, "measurement_kind"),
    target_level = check_filter(target_level, "target_level"),
    dataset = check_filter(dataset, "dataset"),
    provider = check_filter(provider, "provider"),
    available_only = if (check_flag(available_only, "available_only")) TRUE else NULL,
    include_unmapped = if (check_flag(include_unmapped, "include_unmapped")) TRUE else NULL
  )
  response <- soil_request(soil, "GET", "/variables", query = query, right = "soil:summary")
  variables <- records_frame(response$variables, variable_schema, "GET /variables")
  metadata <- response$metadata %||% list()
  metadata$unmapped_source_codes <- records_frame(
    metadata$unmapped_source_codes, unmapped_schema, "GET /variables: unmapped_source_codes"
  )
  metadata$request <- Filter(Negate(is.null), query)
  metadata$endpoint <- "/variables"
  metadata$request_id <- attr(response, "request_id")
  metadata$retrieved_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  attr(variables, "soil_metadata") <- metadata
  variables
}

#' What each source code means in each dataset
#'
#' One row per mapping of a source code to a variable: the original code
#' and label of the provider, its unit and procedure as the source gives
#' them, and how the hub judged the mapping (`semantic_status`,
#' `unit_status`, `unit_evidence`). Original terms are kept: no unit is
#' converted, no label rewritten.
#'
#' Terms: `source_code` is the code of the source as stored,
#' `source_official_code` the provider's official spelling; `source_scope`
#' limits a mapping to one source dataset (e.g. `"<SOTWIS package>/"`) when
#' the same code means something different there; `method_facets` are the
#' facets of the WoSIS methods that change the meaning of a value.
#'
#' Rights: `soil:summary`.
#'
#' @param soil A session (the default session when omitted), or the result
#'   of [soil_variables()], whose mappings are then listed without a request. Client-side: not sent
#'   to the API.
#' @param ... The filters of [soil_variables()] (`code`, `domain`,
#'   `measurement_kind`, `target_level`, `dataset`, `provider`,
#'   `available_only`) when `soil` is a session. API query parameters of `GET /variables`, as for
#'   [soil_variables()].
#' @return A data frame, one row per (variable, dataset, mapping):
#'   `variable_code`, `provider_code`, `dataset_code`, `source_code`,
#'   `source_official_code`, `source_label`, `source_unit`,
#'   `procedure_code`, `procedure_description`, `source_value_kind`,
#'   `mapping_status`, `semantic_status`, `unit_status`, `unit_evidence`
#'   (list), `source_scope`, `source_notes`, `documentation_url`,
#'   `method_facets` (list of data frames `facet_key`, `facet_value`,
#'   `element_count`, `source_dataset_counts`).
#' @family discovery
#' @examples
#' \dontrun{
#' m <- soil_variable_mappings(soil, dataset = "sotwis_polygons")
#' m[m$unit_status != "documented", c("variable_code", "source_code", "source_unit", "source_notes")]
#' }
#' @export
soil_variable_mappings <- function(soil = soil_session(), ...) {
  variables <- if (!missing(soil) && is.data.frame(soil)) {
    soil
  } else {
    soil_variables(soil, ...)
  }
  if (!all(c("variable_code", "source_mappings") %in% names(variables))) {
    abort(soilhub_argument_error(
      "`soil` must be a session or the result of soil_variables().", "soil"
    ))
  }
  columns <- c("variable_code", names(source_mapping_schema))
  pieces <- lapply(seq_len(nrow(variables)), function(i) {
    mappings <- variables$source_mappings[[i]]
    if (!is.data.frame(mappings) || nrow(mappings) == 0L) return(NULL)
    mappings <- mappings[, intersect(names(source_mapping_schema), names(mappings)), drop = FALSE]
    cbind_first(variable_code = rep(variables$variable_code[[i]], nrow(mappings)), mappings)
  })
  pieces <- Filter(Negate(is.null), pieces)
  if (length(pieces) == 0L) {
    empty <- records_frame(list(), source_mapping_schema)
    return(cbind_first(variable_code = character(), empty))
  }
  out <- do.call(rbind_frames, pieces)
  out[, intersect(columns, names(out)), drop = FALSE]
}

# Prepend a column to a data frame (list columns kept).
cbind_first <- function(variable_code, frame) {
  columns <- c(list(variable_code = variable_code), as.list(frame))
  new_frame(columns, length(variable_code))
}

# Row-bind data frames with the same columns, list columns included.
rbind_frames <- function(...) {
  frames <- list(...)
  columns <- names(frames[[1]])
  out <- lapply(columns, function(name) {
    values <- lapply(frames, `[[`, name)
    if (is.list(values[[1]])) return(do.call(c, values))
    first <- values[[1]]
    combined <- do.call(c, values)
    if (inherits(first, "POSIXct")) combined <- as_utc(as.numeric(combined))
    combined
  })
  names(out) <- columns
  new_frame(out, sum(vapply(frames, nrow, integer(1))))
}
