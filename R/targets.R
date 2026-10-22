#' @include thematic.R
NULL

# Resolution of source identities to canonical ids (design 4.4):
# POST /query/targets/resolve, at most 10,000 targets per request. The
# response array is `targets` (fact 12.2.11; soilhub 0.1.3 read `results`).

target_chunk_size <- 10000L
target_key_fields <- c("provider_code", "dataset_code", "release_code",
                       "target_level", "source_record_id")

target_result_schema <- list(
  input_index = "dbl", status = "chr", provider_code = "chr",
  dataset_code = "chr", release_code = "chr", target_level = "chr",
  source_record_id = "chr", source_table = "chr", release_status = "chr",
  target_id = "chr", feature_id = "chr", profile_id = "chr",
  component_id = "chr", horizon_id = "chr", source_support = "chr",
  geometry_kind = "chr", top_depth_cm = "dbl", bottom_depth_cm = "dbl",
  candidate_count = "int"
)

#' Canonical ids of source records
#'
#' Finds the canonical ids (`target_id`, and the `feature_id`,
#' `profile_id`, `component_id`, `horizon_id` it belongs to) of records
#' known by their source identity: provider, dataset, release, level and the
#' source record id (`POST /query/targets/resolve`). It is the step before
#' publishing derived values ([soil_publish_values()]) on records known by
#' their source ids. Targets are sent in requests of at most 10,000.
#'
#' Each target is `resolved` (one canonical record), `missing` (none) or
#' `ambiguous` (several: give `source_table` to choose). With
#' `strict = TRUE` (the default) any `missing` or `ambiguous` target is an
#' error, so a later publication never uses a partial resolution; with
#' `strict = FALSE` the statuses are returned for inspection.
#'
#' Rights: `soil:read`. Capability: `target_resolution`.
#'
#' @param soil A session; the default session when omitted. Client-side: not sent to the API.
#' @param targets A data frame with the columns `provider_code`,
#'   `dataset_code` (lower-case codes), `release_code`, `target_level`
#'   (`"feature"`, `"profile"`, `"component"`, `"horizon"`),
#'   `source_record_id` and optionally `source_table`, without `NA` (except
#'   in `source_table`). API field `targets`.
#' @param strict Stop with `soilhub_argument_error` (argument `targets`) when
#'   a target is `missing` or `ambiguous`; the full resolution is in the
#'   error's `resolution` field. Client-side: not sent to the API.
#' @return A data frame, one row per row of `targets` and in the same order:
#'   `input_index` (0-based position in `targets`), `status`,
#'   `provider_code`, `dataset_code`, `release_code`, `target_level`,
#'   `source_record_id`, `source_table`, `release_status`, `target_id`,
#'   `feature_id`, `profile_id`, `component_id`, `horizon_id`,
#'   `source_support`, `geometry_kind`, `top_depth_cm`, `bottom_depth_cm`,
#'   `candidate_count` (integer). Attribute `soil_metadata`: the request ids
#'   and `status_counts`.
#' @family thematic reads
#' @examples
#' \dontrun{
#' keys <- data.frame(provider_code = "isric", dataset_code = "wosis_points",
#'                    release_code = "2023-12", target_level = "profile",
#'                    source_record_id = c("101", "102"))
#' ids <- soil_resolve_targets(soil, keys)
#' ids$target_id
#'
#' # inspect instead of stopping
#' res <- soil_resolve_targets(soil, keys, strict = FALSE)
#' table(res$status)
#' }
#' @export
soil_resolve_targets <- function(soil = soil_session(), targets, strict = TRUE) {
  check_session(soil)
  records <- check_targets(targets)
  strict <- check_flag(strict, "strict")
  what <- "`soil_resolve_targets()`"
  soil_require_right(soil, "soil:read", what)
  soil_require_capability(soil, "target_resolution", what)

  starts <- seq.int(1L, length(records), by = target_chunk_size)
  results <- list()
  request_ids <- character()
  for (start in starts) {
    chunk <- records[start:min(start + target_chunk_size - 1L, length(records))]
    response <- soil_request(soil, "POST", "/query/targets/resolve",
                             body = list(targets = chunk), right = "soil:read")
    frame <- records_frame(response$targets, target_result_schema, "POST /query/targets/resolve")
    if (nrow(frame) != length(chunk)) {
      abort(soilhub_api_error(
        sprintf(
          "The API resolved %d target(s) of the %d sent in one request.%s",
          nrow(frame), length(chunk),
          request_suffix(NULL, "POST", "/query/targets/resolve", attr(response, "request_id"))
        ),
        endpoint = "/query/targets/resolve", method = "POST",
        request_id = attr(response, "request_id"), code = "incomplete_resolution"
      ))
    }
    frame$input_index <- frame$input_index + (start - 1)
    results[[length(results) + 1L]] <- frame
    request_ids <- c(request_ids, attr(response, "request_id") %||% NA_character_)
  }
  out <- do.call(rbind, results)
  rownames(out) <- NULL
  counts <- vapply(c("resolved", "missing", "ambiguous"), function(s) sum(out$status == s, na.rm = TRUE), numeric(1))
  attr(out, "soil_metadata") <- list(
    endpoint = "/query/targets/resolve", request_ids = request_ids,
    pages = length(request_ids), status_counts = counts,
    client_version = client_version(),
    retrieved_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
  if (strict && (counts[["missing"]] > 0 || counts[["ambiguous"]] > 0)) {
    abort(unresolved_targets_error(out, counts))
  }
  out
}

# The targets as a list of request objects (TargetResolutionKey), checked
# before any request.
check_targets <- function(targets) {
  bad <- function(reason) abort(soilhub_argument_error(paste0("`targets` ", reason), "targets"))
  if (!is.data.frame(targets)) bad("must be a data frame of source identities.")
  if (nrow(targets) == 0L) bad("has no rows.")
  missing <- setdiff(target_key_fields, names(targets))
  if (length(missing)) {
    bad(sprintf("lacks the column(s) %s.", paste0("`", missing, "`", collapse = ", ")))
  }
  fields <- c(target_key_fields, intersect("source_table", names(targets)))
  columns <- lapply(stats::setNames(fields, fields), function(name) {
    value <- targets[[name]]
    if (is.factor(value)) value <- as.character(value)
    if (!is.character(value) && !is.numeric(value)) {
      bad(sprintf("column `%s` must be character, not %s.", name, class(value)[1]))
    }
    value <- if (is.numeric(value)) {
      vapply(value, function(v) if (is.na(v)) NA_character_ else format(v, scientific = FALSE, trim = TRUE, digits = 15), character(1))
    } else {
      value
    }
    if (!identical(name, "source_table") && (anyNA(value) || any(!nzchar(value)))) {
      rows <- which(is.na(value) | !nzchar(value))
      bad(sprintf("column `%s` has missing values (row%s %s).", name, if (length(rows) > 1L) "s" else "",
                  paste(utils::head(rows, 5L), collapse = ", ")))
    }
    value
  })
  for (name in c("provider_code", "dataset_code")) {
    wrong <- which(!grepl("^[a-z0-9_]+$", columns[[name]]))
    if (length(wrong)) {
      bad(sprintf("column `%s` must hold lower-case codes (a-z, 0-9, _), not %s (row %d).",
                  name, deparse_argument(columns[[name]][[wrong[1]]]), wrong[1]))
    }
  }
  levels <- unique(columns$target_level)
  unknown <- setdiff(levels, value_target_levels)
  if (length(unknown)) {
    bad(sprintf("column `target_level` has unknown level(s) %s; accepted: %s.",
                paste0("\"", unknown, "\"", collapse = ", "),
                paste0("\"", value_target_levels, "\"", collapse = ", ")))
  }
  lapply(seq_len(nrow(targets)), function(i) {
    record <- lapply(columns, `[[`, i)
    if (!is.null(record$source_table) && is.na(record$source_table)) record$source_table <- NULL
    record
  })
}

unresolved_targets_error <- function(resolution, counts) {
  unresolved <- resolution[resolution$status != "resolved", , drop = FALSE]
  shown <- utils::head(unresolved, 5L)
  lines <- sprintf(
    "  row %d: %s/%s/%s %s %s: %s%s",
    as.integer(shown$input_index) + 1L, shown$provider_code, shown$dataset_code,
    shown$release_code, shown$target_level, shown$source_record_id, shown$status,
    ifelse(shown$status == "ambiguous", sprintf(" (%d candidates: give `source_table`)", shown$candidate_count), "")
  )
  e <- soilhub_argument_error(
    paste0(
      sprintf(
        "%s of %s target(s) did not resolve to one canonical record (%s missing, %s ambiguous):\n",
        format_count(nrow(unresolved)), format_count(nrow(resolution)),
        format_count(counts[["missing"]]), format_count(counts[["ambiguous"]])
      ),
      paste(lines, collapse = "\n"),
      if (nrow(unresolved) > nrow(shown)) sprintf("\n  ... %s more", format_count(nrow(unresolved) - nrow(shown))) else "",
      "\nThe full resolution is in `e$resolution`; use `strict = FALSE` to return it."
    ),
    "targets"
  )
  e$resolution <- resolution
  e
}
