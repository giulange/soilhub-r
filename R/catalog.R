#' @include typing.R
NULL

# Discovery and catalog (design 4.3, 5.5; decision 7): the datasets with the
# provenance of the release mirrored now, their licences and citations
# (verbatim, never rewritten), and the export formats.

note_schema <- list(
  key = "chr", kind = "chr", source_record_id = "chr",
  source_dataset_name = "chr", title = "chr", body = "chr",
  details = "json", decision = "chr"
)

source_asset_schema <- list(
  asset_role = "chr", local_path = "chr", source_url = "chr",
  checksum_sha256 = "chr", byte_size = "dbl", media_type = "chr",
  source_record_id = "chr", source_title = "chr", source_version = "chr",
  source_published_on = "date", file_modified_at = "time"
)

dataset_schema <- list(
  name = "chr", title = "chr", provider_code = "chr", description = "chr",
  support_type = "chr", geometry_class = "chr",
  release_code = "chr", release_status = "chr",
  feature_count = "dbl", profile_count = "dbl", horizon_count = "dbl",
  observation_count = "dbl", country_codes = "chr_list",
  licence_text = "chr", licence_url = "chr", licence_source_url = "chr",
  licence_retrieved_on = "date", licence_note = "chr",
  citation_text = "chr", citation_source_url = "chr",
  citation_retrieved_on = "date", citation_note = "chr",
  release_acquired_at = "time", release_released_at = "time",
  release_source_url = "chr", release_source_version = "chr",
  release_source_doi = "chr", release_reconstructed = "lgl",
  release_note = "chr", retired_row_count = "dbl",
  source_assets = frames(source_asset_schema),
  notes = frames(note_schema),
  default_geometry_kind = "chr", geometry_available = "lgl",
  schema_name = "chr"
)

datasets_frame <- function(records, context = "GET /datasets") {
  records_frame(records, dataset_schema, context)
}

#' The datasets of the catalog
#'
#' One row per dataset of the Global Soil Data Hub (`GET /datasets`), with
#' the release mirrored now and its provenance, the licence and the citation
#' of the provider, and the catalog notes. Texts are the provider's own,
#' verbatim: use [soil_citations()] and [soil_licences()] for what to cite
#' and under which terms.
#'
#' Terms: a **dataset** is a hub collection of one provider (`wosis_points`,
#' `wise_profiles`, `soter_profiles`, `soter_polygons`, `sotwis_polygons`,
#' `sotwis_components`, `sotwis_estimates`); a **release** is one download of
#' it from the provider (`release_code`, `legacy_materialized` for the data
#' loaded before the provenance was recorded, then `release_reconstructed =
#' TRUE`); a **source dataset** is one record of the provider inside a hub
#' dataset (a SOTER country database, a SOTWIS package), named in the notes
#' by `source_record_id` (ISRIC data hub record) and `source_dataset_name`.
#'
#' Rights: `soil:summary`.
#'
#' @param soil A session; the default session when omitted. Client-side: not sent to the API.
#' @return A data frame, one row per dataset: `name`, `title`,
#'   `provider_code`, `description`, `support_type`, `geometry_class`,
#'   `release_code`, `release_status`, the counts `feature_count`,
#'   `profile_count`, `horizon_count`, `observation_count` (double),
#'   `country_codes` (list of character), `licence_text`, `licence_url`,
#'   `licence_source_url`, `licence_retrieved_on` (Date), `licence_note`,
#'   `citation_text`, `citation_source_url`, `citation_retrieved_on` (Date),
#'   `citation_note`, the provenance of the release `release_acquired_at`,
#'   `release_released_at` (POSIXct, UTC), `release_source_url`,
#'   `release_source_version`, `release_source_doi`, `release_reconstructed`
#'   (logical), `release_note`, `retired_row_count` (rows whose source left
#'   the provider, still served), `source_assets` (list of data frames: the
#'   files kept for the release, `asset_role`, `local_path`, `source_url`,
#'   `checksum_sha256`, `byte_size`, `media_type`, `source_record_id`,
#'   `source_title`, `source_version`, `source_published_on`,
#'   `file_modified_at`), `notes` (list of data frames: `key`, `kind`
#'   (`note`, `raw_only`, `citation`, `licence`), `source_record_id`,
#'   `source_dataset_name`, `title`, `body`, `details` (list), `decision`),
#'   and `default_geometry_kind`, `geometry_available`, `schema_name`.
#'   Fields the API adds later are kept as list columns (with a
#'   `soilhub_contract_warning`).
#' @family discovery
#' @seealso [soil_dataset()], [soil_citations()], [soil_licences()]
#' @examples
#' \dontrun{
#' ds <- soil_datasets(soil)
#' ds[, c("name", "release_code", "profile_count", "observation_count")]
#' ds$notes[[which(ds$name == "sotwis_polygons")]][, c("kind", "title")]
#' }
#' @export
soil_datasets <- function(soil = soil_session()) {
  check_session(soil)
  response <- soil_request(soil, "GET", "/datasets", right = "soil:summary")
  datasets <- datasets_frame(response$datasets)
  if (is.environment(soil$state)) soil$state$datasets <- datasets
  datasets
}

# The catalog of the session: read once, then cached (design 5.4).
session_catalog <- function(soil) {
  cached <- if (is.environment(soil$state)) soil$state$datasets else NULL
  if (is.data.frame(cached)) return(cached)
  soil_datasets(soil)
}

#' One dataset of the catalog
#'
#' The full catalog entry of one dataset (`GET /datasets/{name}`): the same
#' fields as a row of [soil_datasets()], as a list, with `source_assets` and
#' `notes` as data frames. Printing shows the title, the release, the counts,
#' the licence, the citation and the titles of the notes.
#'
#' Rights: `soil:summary`.
#'
#' @param soil A session; the default session when omitted (the dataset name
#'   may then be given first: `soil_dataset("wise_profiles")`). Client-side: not sent to the API.
#' @param name The dataset name (e.g. `"soter_profiles"`). API path parameter `{dataset_name}` of
#'   `GET /datasets/{dataset_name}`.
#' @return A `soil_dataset` list with the fields of [soil_datasets()].
#'   An unknown name raises `soilhub_not_found_error`.
#' @family discovery
#' @examples
#' \dontrun{
#' soter <- soil_dataset(soil, "soter_profiles")
#' soter
#' soter$notes[soter$notes$kind == "licence", c("source_dataset_name", "body")]
#' }
#' @export
soil_dataset <- function(soil = soil_session(), name) {
  if (missing(name) && !missing(soil) && is.character(soil)) {
    name <- soil
    soil <- soil_session()
  }
  if (missing(name)) abort(soilhub_argument_error("`name` (the dataset name) is missing.", "name"))
  check_session(soil)
  name <- check_name(name, "name")
  response <- tryCatch(
    soil_request(soil, "GET", paste0("/datasets/", url_segment(name)), right = "soil:summary"),
    soilhub_not_found_error = function(e) {
      e$message <- paste0(
        sprintf("Unknown dataset `%s`: soil_datasets() lists the catalog. ", name),
        conditionMessage(e)
      )
      abort(e)
    }
  )
  row <- datasets_frame(response, context = "GET /datasets/{name}")
  structure(frame_row_list(row), class = "soil_dataset")
}

#' @export
print.soil_dataset <- function(x, ...) {
  text_or <- function(value, other) if (is.null(value) || is.na(value)) other else value
  cat("<soil_dataset> ", x$name, ": ", text_or(x$title, ""), "\n", sep = "")
  cat("  Provider:  ", text_or(x$provider_code, "?"), "; ", text_or(x$support_type, "?"),
      ", geometry ", text_or(x$geometry_class, "?"), "\n", sep = "")
  release <- paste0(text_or(x$release_code, "?"), " (", text_or(x$release_status, "?"))
  if (!is.null(x$release_acquired_at) && !is.na(x$release_acquired_at)) {
    release <- paste0(release, ", acquired ", format(x$release_acquired_at, "%Y-%m-%d", tz = "UTC"))
  }
  if (isTRUE(x$release_reconstructed)) release <- paste0(release, ", reconstructed")
  cat("  Release:   ", release, ")\n", sep = "")
  counts <- c(features = x$feature_count, profiles = x$profile_count,
              horizons = x$horizon_count, observations = x$observation_count)
  counts <- counts[!is.na(counts)]
  if (length(counts)) {
    cat("  Counts:    ", paste(format_count(counts), names(counts), collapse = ", "), "\n", sep = "")
  }
  cat("  Licence:   ", text_or(x$licence_text, paste0("(none at dataset level) ", text_or(x$licence_note, ""))), "\n", sep = "")
  cat("  Citation:  ", text_or(x$citation_text, paste0("(none at dataset level) ", text_or(x$citation_note, ""))), "\n", sep = "")
  notes <- x$notes
  if (is.data.frame(notes) && nrow(notes)) {
    titles <- unique(paste0("[", notes$kind, "] ", notes$title))
    cat("  Notes:     ", nrow(notes), " (", length(titles), " title(s))\n", sep = "")
    shown <- utils::head(titles, 10L)
    cat(paste0("    ", shown), sep = "\n")
    if (length(titles) > length(shown)) cat("    ...\n")
  }
  cat("  See soil_citations() and soil_licences() for what to cite and the terms of use.\n")
  invisible(x)
}

# ---------------------------------------------------------------------------
# Citations and licences.

#' What to cite, and under which terms
#'
#' `soil_citations()` returns the citation texts of datasets, `soil_licences()`
#' their licences, both **verbatim** as the providers publish them (never
#' rewritten), with the address they were read from and the date of reading.
#'
#' When a dataset has one text (`citation_text`, `licence_text` of
#' [soil_datasets()]), it is one row with `level = "dataset"`. When it has
#' none (SOTER: the licence differs between source datasets and the records
#' publish no citation; SOTWIS: no citation text), the rows are the catalog
#' notes of kind `citation` / `licence`, one per source dataset, with
#' `level = "source dataset"` and `label` the title the API gives them
#' (e.g. "Citation proposal of the ISRIC data hub", a proposal built by the
#' ISRIC data hub from the record, not a text of the authors; "Licence (ISRIC
#' data hub record)"). The dataset's `citation_note` / `licence_note`
#' explains where the texts are. A dataset with neither text nor notes gives
#' one row with an `NA` text.
#'
#' Rights: `soil:summary` (the catalog is read once per session).
#'
#' @param x What to cite: dataset names (character), rows of
#'   [soil_datasets()], a [soil_dataset()], or a result carrying the catalog
#'   rows of its datasets in its metadata (a `soil_table`, `soil_summary` or
#'   `soil_export`). Client-side: not sent to the API.
#' @param soil A session; the default session when omitted (needed only when
#'   `x` holds dataset names). Client-side: not sent to the API.
#' @return `soil_citations()`: a data frame `dataset`, `citation_text`,
#'   `citation_source_url`, `citation_retrieved_on` (Date), `citation_note`,
#'   `level`, `label`, `note_key`, `source_record_id`,
#'   `source_dataset_name`, `record_title`.
#'
#'   `soil_licences()`: a data frame `dataset`, `licence_text`,
#'   `licence_url`, `licence_source_url`, `licence_retrieved_on` (Date),
#'   `licence_note`, `level`, `label`, `note_key`, `source_record_id`,
#'   `source_dataset_name`, `record_title`.
#' @family discovery
#' @examples
#' \dontrun{
#' soil_citations("wosis_points")
#' soil_citations(c("soter_profiles", "sotwis_polygons"))[, c("dataset", "label", "citation_text")]
#' soil_licences("soter_profiles")[, c("source_dataset_name", "licence_text")]
#' }
#' @export
soil_citations <- function(x, soil = soil_session()) {
  rows <- catalog_rows(x, soil)
  terms_frame(rows, "citation")
}

#' @rdname soil_citations
#' @export
soil_licences <- function(x, soil = soil_session()) {
  rows <- catalog_rows(x, soil)
  terms_frame(rows, "licence")
}

# Catalog rows (typed as soil_datasets()) of what `x` refers to.
catalog_rows <- function(x, soil) {
  if (inherits(x, "soil_dataset")) return(dataset_as_row(x))
  metadata <- attr(x, "soil_metadata")
  if (is.null(metadata) && is.list(x) && !is.data.frame(x) && is.list(x$metadata)) {
    metadata <- x$metadata
  }
  if (is.list(metadata)) {
    datasets <- metadata$datasets
    if (is.data.frame(datasets)) return(datasets)
    if (is.list(datasets) && length(datasets) && is.list(datasets[[1]])) {
      return(datasets_frame(datasets, context = NULL))
    }
    names <- unlist(metadata$request$datasets %||% datasets)
    if (is.character(names) && length(names)) return(catalog_by_name(names, soil))
  }
  if (is.data.frame(x) && all(c("name", "citation_text", "licence_text") %in% names(x))) {
    return(x)
  }
  if (is.character(x) && length(x) && !anyNA(x)) return(catalog_by_name(x, soil))
  abort(soilhub_argument_error(
    paste0(
      "`x` must be dataset names, rows of soil_datasets(), a soil_dataset(), ",
      "or a result of a read, summary or export."
    ),
    "x"
  ))
}

# A soil_dataset() back to a one-row catalog data frame.
dataset_as_row <- function(x) {
  x <- unclass(x)
  columns <- lapply(names(x), function(name) {
    type <- dataset_schema[[name]]
    atomic <- is.character(type) && type %in% c("chr", "int", "dbl", "lgl", "time", "date")
    if (atomic) x[[name]] else list(x[[name]])
  })
  names(columns) <- names(x)
  new_frame(columns, 1L)
}

catalog_by_name <- function(names, soil) {
  check_session(soil)
  catalog <- session_catalog(soil)
  unknown <- setdiff(names, catalog$name)
  if (length(unknown)) {
    abort(soilhub_argument_error(
      sprintf(
        "Unknown dataset(s) %s; the catalog has %s.",
        paste0("`", unknown, "`", collapse = ", "),
        paste0("`", catalog$name, "`", collapse = ", ")
      ),
      "x"
    ))
  }
  catalog[match(unique(names), catalog$name), , drop = FALSE]
}

# One row per dataset text, or per source-dataset note when the dataset has
# no text of that kind. `kind` is "citation" or "licence".
terms_frame <- function(rows, kind) {
  text_col <- paste0(kind, "_text")
  url_cols <- if (kind == "licence") c("licence_url", "licence_source_url") else "citation_source_url"
  out <- list()
  for (i in seq_len(nrow(rows))) {
    dataset <- rows$name[[i]]
    text <- rows[[text_col]][[i]]
    note <- rows[[paste0(kind, "_note")]][[i]]
    pieces <- list()
    if (!is.na(text)) {
      piece <- list(
        dataset = dataset, text = text,
        licence_url = if (kind == "licence") rows$licence_url[[i]] else NA_character_,
        source_url = rows[[paste0(kind, "_source_url")]][[i]],
        retrieved_on = rows[[paste0(kind, "_retrieved_on")]][[i]],
        note = note, level = "dataset", label = NA_character_,
        note_key = NA_character_, source_record_id = NA_character_,
        source_dataset_name = NA_character_, record_title = NA_character_
      )
      pieces[[1]] <- piece
    } else {
      notes <- if ("notes" %in% names(rows)) rows$notes[[i]] else NULL
      if (is.data.frame(notes) && nrow(notes)) {
        notes <- notes[!is.na(notes$kind) & notes$kind == kind, , drop = FALSE]
        for (j in seq_len(nrow(notes))) {
          details <- notes$details[[j]]
          detail <- function(field) {
            value <- if (is.list(details)) details[[field]] else NULL
            if (is.null(value) || length(value) != 1L) NA_character_ else as.character(value)
          }
          pieces[[length(pieces) + 1L]] <- list(
            dataset = dataset, text = notes$body[[j]],
            licence_url = detail("licence_url"),
            source_url = detail("source_url"),
            retrieved_on = parse_api_date(detail("retrieved_on")),
            note = note, level = "source dataset", label = notes$title[[j]],
            note_key = notes$key[[j]], source_record_id = notes$source_record_id[[j]],
            source_dataset_name = notes$source_dataset_name[[j]],
            record_title = detail("record_title")
          )
        }
      }
      if (length(pieces) == 0L) {
        pieces[[1]] <- list(
          dataset = dataset, text = NA_character_, licence_url = NA_character_,
          source_url = NA_character_, retrieved_on = as.Date(NA), note = note,
          level = "dataset", label = NA_character_, note_key = NA_character_,
          source_record_id = NA_character_, source_dataset_name = NA_character_,
          record_title = NA_character_
        )
      }
    }
    out <- c(out, pieces)
  }
  column <- function(field, empty) {
    if (length(out) == 0L) return(empty)
    values <- lapply(out, `[[`, field)
    if (inherits(empty, "Date")) return(as.Date(vapply(values, as.numeric, numeric(1)), origin = "1970-01-01"))
    vapply(values, function(v) if (is.null(v)) NA_character_ else as.character(v), character(1))
  }
  frame <- list(dataset = column("dataset", character()))
  frame[[text_col]] <- column("text", character())
  if (kind == "licence") frame$licence_url <- column("licence_url", character())
  frame[[paste0(kind, "_source_url")]] <- column("source_url", character())
  frame[[paste0(kind, "_retrieved_on")]] <- column("retrieved_on", as.Date(character()))
  frame[[paste0(kind, "_note")]] <- column("note", character())
  for (field in c("level", "label", "note_key", "source_record_id", "source_dataset_name", "record_title")) {
    frame[[field]] <- column(field, character())
  }
  new_frame(frame, length(out))
}

#' Export formats
#'
#' The formats of exports (`GET /formats`): GeoPackage, GeoJSON, CSV, TSV and
#' Shapefile (`shp` only for exports of features; see
#' [soil_capabilities()]`$exports` for the formats per export content).
#'
#' Rights: `soil:summary`.
#'
#' @param soil A session; the default session when omitted. Client-side: not sent to the API.
#' @return A character vector.
#' @family discovery
#' @examples
#' \dontrun{
#' soil_formats(soil)
#' }
#' @export
soil_formats <- function(soil = soil_session()) {
  check_session(soil)
  response <- soil_request(soil, "GET", "/formats", right = "soil:summary")
  vapply(response$formats %||% list(), scalar_chr, character(1))
}

# ---------------------------------------------------------------------------
# Argument helpers shared by the discovery functions.

check_name <- function(value, argument) {
  if (!is_string(value)) {
    abort(soilhub_argument_error(
      sprintf("`%s` must be one non-empty string, not %s.", argument, deparse_argument(value)),
      argument
    ))
  }
  value
}

# Optional character filter: NULL, or a character vector without NA; "ALL"
# (the 0.1.x convention) is refused with the way to say "no filter".
check_filter <- function(value, argument) {
  if (is.null(value)) return(NULL)
  if (!is.character(value) || length(value) == 0L || anyNA(value) || !all(nzchar(value))) {
    abort(soilhub_argument_error(
      sprintf("`%s` must be NULL (no filter) or a character vector without NA, not %s.", argument, deparse_argument(value)),
      argument
    ))
  }
  if (any(toupper(value) == "ALL")) {
    abort(soilhub_argument_error(
      sprintf("`%s = \"ALL\"` is not a filter value: use `%s = NULL` (the default) for no filter.", argument, argument),
      argument
    ))
  }
  unique(value)
}

check_flag <- function(value, argument) {
  if (!is.logical(value) || length(value) != 1L || is.na(value)) {
    abort(soilhub_argument_error(sprintf("`%s` must be TRUE or FALSE.", argument), argument))
  }
  value
}

url_segment <- function(value) curl::curl_escape(value)
