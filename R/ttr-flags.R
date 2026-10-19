#' @include thematic.R code-lists.R
NULL

# SOTWIS taxotransfer flags (design 4.4): GET /sotwis/ttr-flags, paged with
# `limit` and `offset` in the query string, rows of the source table
# `SOTERflagTTRrules` with their columns verbatim. The legend is
# soil_ttr_flag_legend() (code-lists.R).

ttr_flags_schema <- list(
  flag_id = "dbl", feature_id = "chr", profile_id = "chr", horizon_id = "chr",
  source_record_id = "chr", source_dataset_name = "chr", source_table = "chr",
  source_row_number = "int", sub_layer_number = "int", CLAF = "chr",
  PRID = "chr", Layer = "chr", Newtopdep = "dbl", Newbotdep = "dbl",
  TTRsub = "chr", TTRmain = "chr", TTRfinal = "chr", TTRexpert = "chr"
)

#' SOTWIS taxotransfer flags
#'
#' Which taxotransfer rules produced each SOTWIS estimate: the rows of the
#' source table `SOTERflagTTRrules` (`GET /sotwis/ttr-flags`) linked to the
#' profiles and horizons of `sotwis_estimates`, with the source columns
#' verbatim (`CLAF`, `PRID`, `Layer`, `Newtopdep`, `Newbotdep`, `TTRsub`,
#' `TTRmain`, `TTRfinal`, `TTRexpert`). The codes are explained by
#' [soil_ttr_flag_legend()].
#'
#' With `view = "revised"` a `prid` filter also matches the spellings of the
#' same profile id that differ only by case (rule R6); the spellings linked
#' are listed in `soil_metadata(x)$revised`.
#'
#' Rights: `soil:read`. Capabilities: `sotwis_ttr_flags`; `revised_view` for
#' `view = "revised"`.
#'
#' @param soil A session; the default session when omitted.
#' @param source_dataset One SOTWIS source dataset (record id or name).
#' @param prid One profile id (`PRID`).
#' @param claf One soil unit code (`CLAF`).
#' @param layer One layer (`Layer`, e.g. `"D1"`).
#' @param feature_id,horizon_id One canonical feature or horizon id (UUID).
#' @param view `"raw"` (sent explicitly) or `"revised"`.
#' @param max_rows Maximum number of rows to read (`Inf`: all).
#' @return A data frame: `flag_id`, `feature_id`, `profile_id`,
#'   `horizon_id`, `source_record_id`, `source_dataset_name`,
#'   `source_table`, `source_row_number`, `sub_layer_number` (integer), then
#'   the source columns `CLAF`, `PRID`, `Layer`, `Newtopdep`, `Newbotdep`
#'   (double), `TTRsub`, `TTRmain`, `TTRfinal`, `TTRexpert`. Attribute
#'   `soil_metadata` (see [soil_metadata()]).
#' @family thematic reads
#' @examples
#' \dontrun{
#' f <- soil_ttr_flags(soil, claf = "LVh", layer = "D1")
#' table(f$TTRfinal)
#' legend <- soil_ttr_flag_legend(soil)
#' }
#' @export
soil_ttr_flags <- function(soil = soil_session(), source_dataset = NULL,
                           prid = NULL, claf = NULL, layer = NULL,
                           feature_id = NULL, horizon_id = NULL,
                           view = "raw", max_rows = Inf) {
  check_session(soil)
  one <- function(value, argument) if (is.null(value)) NULL else check_name(value, argument)
  query <- list(
    source_dataset = one(source_dataset, "source_dataset"),
    prid = one(prid, "prid"),
    claf = one(claf, "claf"),
    layer = one(layer, "layer"),
    feature_id = one(feature_id, "feature_id"),
    horizon_id = one(horizon_id, "horizon_id"),
    view = check_choice(view, selection_choices(soil)$view, "view")
  )
  query <- query[!vapply(query, is.null, logical(1))]
  max_rows <- check_max_rows(max_rows)
  what <- "`soil_ttr_flags()`"
  soil_require_right(soil, "soil:read", what)
  soil_require_capability(soil, "sotwis_ttr_flags", what)
  if (identical(query$view, "revised")) {
    soil_require_capability(soil, "revised_view", paste0(what, " with `view = \"revised\"`"))
  }
  collect_typed(soil, "/sotwis/ttr-flags", query, "flags", max_rows, FALSE, function(pages) {
    out <- records_frame(pages$items, ttr_flags_schema, "GET /sotwis/ttr-flags")
    meta <- pages_metadata(soil, pages)
    meta$view <- scalar_chr(meta$view %||% query$view)
    attr(out, "soil_metadata") <- meta
    out
  }, method = "GET")
}
