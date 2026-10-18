# The daily country inventory (design 4.3): GET /countries and
# GET /countries/{code}.

country_count_schema <- list(
  dataset_count = "dbl", feature_count = "dbl", point_count = "dbl",
  polygon_count = "dbl", profile_count = "dbl", horizon_count = "dbl",
  original_observation_count = "dbl", value_count = "dbl",
  observation_count = "dbl", variable_count = "dbl"
)

country_list_schema <- c(
  list(iso_a2 = "chr", iso_a3 = "chr", name = "chr"),
  country_count_schema,
  list(as_of = "time")
)

country_detail_schema <- c(
  list(iso_a2 = "chr", iso_a3 = "chr", name = "chr"),
  country_count_schema,
  list(source_signature = "chr", aggregation_version = "chr",
       refresh_job_id = "chr", refreshed_at = "time")
)

country_dataset_schema <- c(
  list(provider_code = "chr", dataset_code = "chr", dataset_name = "chr",
       country_id = "dbl", dataset_id = "dbl"),
  country_count_schema[setdiff(names(country_count_schema), "dataset_count")],
  list(source_signature = "chr", aggregation_version = "chr",
       refresh_job_id = "chr", refreshed_at = "time")
)

country_variable_schema <- list(
  provider_code = "chr", dataset_code = "chr", variable_code = "chr",
  original_observation_count = "dbl", value_count = "dbl",
  observation_count = "dbl"
)

#' The country inventory
#'
#' Daily totals per country (`GET /countries`), including the countries
#' without data. A feature is assigned to every country its geometry
#' intersects (`country_assignment = "intersects"`): a polygon crossing a
#' border counts in each country, so **country totals must not be summed**
#' to obtain a global total (use `soil_consistency()` for distinct totals).
#'
#' Rights: `soil:summary`.
#'
#' @param soil A session; the default session when omitted.
#' @return A data frame, one row per country: `iso_a2`, `iso_a3`, `name`,
#'   the counts `dataset_count`, `feature_count`, `point_count`,
#'   `polygon_count`, `profile_count`, `horizon_count`,
#'   `original_observation_count`, `value_count`, `observation_count`,
#'   `variable_count` (double) and `as_of` (POSIXct, UTC: the last
#'   successful refresh of that country). Attributes `country_assignment`
#'   (`"intersects"`) and `soil_metadata` (the response metadata).
#' @family discovery
#' @seealso [soil_country()]
#' @examples
#' \dontrun{
#' countries <- soil_countries(soil)
#' head(countries[order(-countries$profile_count), c("iso_a3", "name", "profile_count")])
#' }
#' @export
soil_countries <- function(soil = soil_session()) {
  check_session(soil)
  soil_require_capability(soil, "country_inventory", "`soil_countries()`")
  response <- soil_request(soil, "GET", "/countries", right = "soil:summary")
  countries <- records_frame(response$countries, country_list_schema, "GET /countries")
  metadata <- response$metadata %||% list()
  attr(countries, "country_assignment") <- metadata$country_assignment %||% NA_character_
  attr(countries, "soil_metadata") <- metadata
  countries
}

#' One country by dataset and variable
#'
#' The inventory of one country (`GET /countries/{code}`): its totals, the
#' totals per dataset and per (dataset, variable). Same assignment rule as
#' [soil_countries()] (`intersects`).
#'
#' Rights: `soil:summary`.
#'
#' @param soil A session; the default session when omitted (the code may
#'   then be given first: `soil_country("KEN")`).
#' @param code ISO 3166-1 alpha-2 or alpha-3 code (`"KE"`, `"KEN"`), any
#'   case.
#' @return A list: `country` (one-row data frame: `iso_a2`, `iso_a3`,
#'   `name`, the counts of [soil_countries()], `source_signature`,
#'   `aggregation_version`, `refresh_job_id`, `refreshed_at`), `datasets`
#'   (data frame per dataset: `provider_code`, `dataset_code`,
#'   `dataset_name`, the API ids `country_id`, `dataset_id`, the counts,
#'   `refreshed_at`, ...), `variables` (data frame per dataset and variable:
#'   `provider_code`, `dataset_code`, `variable_code`,
#'   `original_observation_count`, `value_count`, `observation_count`),
#'   `as_of` (POSIXct) and `country_assignment`. An unknown code raises
#'   `soilhub_not_found_error`.
#' @family discovery
#' @examples
#' \dontrun{
#' kenya <- soil_country(soil, "KEN")
#' kenya$datasets[, c("dataset_code", "profile_count", "observation_count")]
#' }
#' @export
soil_country <- function(soil = soil_session(), code) {
  if (missing(code) && !missing(soil) && is.character(soil)) {
    code <- soil
    soil <- soil_session()
  }
  if (missing(code)) abort(soilhub_argument_error("`code` (the ISO country code) is missing.", "code"))
  check_session(soil)
  code <- check_name(code, "code")
  if (!grepl("^[A-Za-z]{2,3}$", code)) {
    abort(soilhub_argument_error(
      sprintf("`code` must be an ISO 3166-1 alpha-2 or alpha-3 code (\"KE\", \"KEN\"), not \"%s\".", code),
      "code"
    ))
  }
  soil_require_capability(soil, "country_inventory", "`soil_country()`")
  response <- soil_request(soil, "GET", paste0("/countries/", url_segment(code)), right = "soil:summary")
  metadata <- response$metadata %||% list()
  list(
    country = records_frame(response$country, country_detail_schema, "GET /countries/{code}: country"),
    datasets = records_frame(response$datasets, country_dataset_schema, "GET /countries/{code}: datasets"),
    variables = records_frame(response$variables, country_variable_schema, "GET /countries/{code}: variables"),
    as_of = parse_api_time(scalar_chr(metadata$as_of)),
    country_assignment = metadata$country_assignment %||% NA_character_
  )
}
