#' @include typing.R
NULL

# Source code lists and the SOTWIS taxotransfer flag legend (design 4.3):
# GET /code-lists, GET /code-lists/{code_list}, GET /sotwis/ttr-flags/legend.
# Codes, descriptions and meanings verbatim, as in the source. The flag rows
# themselves (`soil_ttr_flags()`, right `soil:read`) come with WP6.

code_list_source_schema <- list(source_record_id = "chr", source_dataset_name = "chr")

code_lists_schema <- list(
  code_list = "chr", provider_code = "chr", row_count = "dbl",
  distinct_entries = "dbl", attributes = "chr_list",
  source_datasets = frames(code_list_source_schema)
)

code_list_schema <- list(
  attribute = "chr", code = "chr", description = "chr",
  source_record_id = "chr", source_dataset_name = "chr", source_table = "chr",
  source_row_number = "int", provider_code = "chr"
)

ttr_legend_schema <- list(
  flag_table = "chr", flag_columns = "chr_list", symbol = "chr",
  symbol_kind = "chr", applies_to = frames(code_list_source_schema),
  meaning = "chr", documented = "lgl", source_reference = "chr",
  note = "chr", provider_code = "chr"
)

#' Source code lists
#'
#' The code lists kept as in the source (`GET /code-lists`), today the
#' `SOTWIS_codes` table of three SOTWIS packages (Senegal and The Gambia,
#' Tunisia, Upper Tana), which explains the codes of `CLAF`, `DRAI`, `ISOC`,
#' `LITH`, `LNDF`, `PHAS`, ...
#'
#' Rights: `soil:summary`. Capability: `code_lists`.
#'
#' @param soil A session; the default session when omitted. Client-side: not sent to the API.
#' @return A data frame, one row per code list and provider: `code_list`,
#'   `provider_code`, `row_count`, `distinct_entries`, `attributes` (list of
#'   character), `source_datasets` (list of data frames `source_record_id`,
#'   `source_dataset_name`).
#' @family discovery
#' @seealso [soil_code_list()]
#' @examples
#' \dontrun{
#' soil_code_lists(soil)
#' }
#' @export
soil_code_lists <- function(soil = soil_session()) {
  check_session(soil)
  soil_require_capability(soil, "code_lists", "`soil_code_lists()`")
  response <- soil_request(soil, "GET", "/code-lists", right = "soil:summary")
  out <- records_frame(response$code_lists, code_lists_schema, "GET /code-lists")
  attr(out, "soil_metadata") <- response$metadata
  out
}

#' Rows of one source code list
#'
#' The rows of a code list (`GET /code-lists/{code_list}`), verbatim: one
#' row per source row, with its source dataset and row number. A code may
#' appear once per source dataset (the same triple in each package).
#'
#' Rights: `soil:summary`. Capability: `code_lists`.
#'
#' @param soil A session; the default session when omitted (the name may then
#'   be given first: `soil_code_list("SOTWIS_codes")`). Client-side: not sent to the API.
#' @param name The code list (`"SOTWIS_codes"`). API path parameter `{code_list}` of
#'   `GET /code-lists/{code_list}`.
#' @param attribute Source attributes (`ATTRIBUTE`, e.g. `"LNDF"`), `NULL`
#'   for all. API query parameter `attribute`.
#' @param code Codes (`CODE`), `NULL` for all. API query parameter `code`.
#' @param source_dataset One source dataset (record id or name), `NULL` for
#'   all. API query parameter `source_dataset`.
#' @return A data frame: `attribute`, `code`, `description`,
#'   `source_record_id`, `source_dataset_name`, `source_table`,
#'   `source_row_number` (integer), `provider_code`. An unknown list raises
#'   `soilhub_not_found_error`.
#' @family discovery
#' @examples
#' \dontrun{
#' soil_code_list(soil, "SOTWIS_codes", attribute = "LNDF")
#' }
#' @export
soil_code_list <- function(soil = soil_session(), name, attribute = NULL,
                           code = NULL, source_dataset = NULL) {
  if (missing(name) && !missing(soil) && is.character(soil)) {
    name <- soil
    soil <- soil_session()
  }
  if (missing(name)) abort(soilhub_argument_error("`name` (the code list) is missing.", "name"))
  check_session(soil)
  name <- check_name(name, "name")
  query <- list(
    attribute = check_filter(attribute, "attribute"),
    code = check_filter(code, "code"),
    source_dataset = if (is.null(source_dataset)) NULL else check_name(source_dataset, "source_dataset")
  )
  soil_require_capability(soil, "code_lists", "`soil_code_list()`")
  response <- soil_request(
    soil, "GET", paste0("/code-lists/", url_segment(name)),
    query = query, right = "soil:summary"
  )
  out <- records_frame(response$codes, code_list_schema, "GET /code-lists/{code_list}")
  attr(out, "soil_metadata") <- response$metadata
  out
}

#' Legend of the SOTWIS taxotransfer flags
#'
#' What the codes of the `SOTERflagTTRrules` table mean
#' (`GET /sotwis/ttr-flags/legend`): per group of flag columns
#' (`flag_columns`, e.g. `TTRsub`, `TTRmain`) and symbol, the `meaning` and
#' the `source_reference` (report and page) where a report documents it;
#' `documented = FALSE` and no meaning otherwise. `applies_to` lists the
#' source datasets of an entry that holds for some of them only (`NULL`:
#' all).
#'
#' Rights: `soil:summary`. Capability: `sotwis_ttr_flags`.
#'
#' @param soil A session; the default session when omitted. Client-side: not sent to the API.
#' @return A data frame: `flag_table`, `flag_columns` (list of character),
#'   `symbol`, `symbol_kind`, `applies_to` (list of data frames
#'   `source_record_id`, `source_dataset_name`, or `NULL`), `meaning`,
#'   `documented` (logical), `source_reference`, `note`, `provider_code`.
#' @family discovery
#' @examples
#' \dontrun{
#' legend <- soil_ttr_flag_legend(soil)
#' legend[!legend$documented, c("symbol", "note")]
#' }
#' @export
soil_ttr_flag_legend <- function(soil = soil_session()) {
  check_session(soil)
  soil_require_capability(soil, "sotwis_ttr_flags", "`soil_ttr_flag_legend()`")
  response <- soil_request(soil, "GET", "/sotwis/ttr-flags/legend", right = "soil:summary")
  out <- records_frame(response$legend, ttr_legend_schema, "GET /sotwis/ttr-flags/legend")
  attr(out, "soil_metadata") <- response$metadata
  out
}
