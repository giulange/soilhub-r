# Response fields the client types exist in the response models (design
# 7.2), where the OpenAPI types them. Untyped responses (`dict[str, Any]`,
# the observation pages) are covered by the recorded fixtures
# (test-recorded.R).

typing_tables <- function() {
  ns <- asNamespace("soilhub")
  names <- ls(ns)
  keep <- vapply(names, function(name) {
    x <- get(name, envir = ns)
    (grepl("_schema$", name) && is.list(x) && !is.null(names(x))) ||
      (grepl("_types$", name) && is.character(x) && !is.null(names(x)) &&
         any(x %in% names(typing_json_types)))
  }, logical(1))
  names[keep]
}

test_that("every typing table of the client is placed in the API responses", {
  missing <- setdiff(typing_tables(), names(response_tables))
  gone <- setdiff(names(response_tables), typing_tables())
  expect_no_drift(c(
    sprintf("`%s` is not in `response_tables` of tests/contract/helper-contract.R: say which response it types", missing),
    sprintf("`%s` of `response_tables` is no longer a typing table of the package", gone)
  ), "Typing tables")
})

test_that("the fields of the typed response models exist with compatible types", {
  doc <- contract_openapi()
  ns <- asNamespace("soilhub")
  problems <- character()
  untyped <- character()
  for (table in intersect(names(response_tables), typing_tables())) {
    entry <- response_tables[[table]]
    fields <- get(table, envir = ns)
    for (at_text in entry$at) {
      at <- split_at(at_text)
      found <- response_schema_at(doc, at$method, at$path, entry$pointer %||% "")
      if (!is.null(found$problem)) {
        problems <- c(problems, paste0(found$problem, " (`", table, "`)"))
        next
      }
      if (!found$typed) {
        untyped <- c(untyped, table)
        next
      }
      problems <- c(problems, contract_check_fields(
        doc, as.list(fields), found$schema,
        sprintf("`%s` (%s%s)", table, at_text, if (is.null(entry$pointer)) "" else paste0(" ", entry$pointer))
      ))
    }
  }
  untyped <- unique(untyped)
  if (length(untyped)) {
    message("Typing tables of untyped API responses (checked by the recorded fixtures): ",
            paste(untyped, collapse = ", "))
  }
  expect_no_drift(problems, "Typed response fields")
})

test_that("the fields read directly from responses exist", {
  doc <- contract_openapi()
  ns <- asNamespace("soilhub")
  readers <- Filter(function(name) {
    f <- get(name, envir = ns)
    is.function(f) && !is.primitive(f) && length(accessed_fields(f, "response"))
  }, ls(ns))
  unplaced <- setdiff(readers, c(names(response_readers), response_readers_other))
  problems <- sprintf(
    "%s() reads `response$...` and is not in `response_readers` of tests/contract/helper-contract.R",
    unplaced
  )
  for (fun in intersect(names(response_readers), readers)) {
    at <- split_at(response_readers[[fun]])
    found <- response_schema_at(doc, at$method, at$path)
    if (!is.null(found$problem)) {
      problems <- c(problems, found$problem)
      next
    }
    if (!found$typed) next
    fields <- accessed_fields(get(fun, envir = ns), "response")
    absent <- setdiff(fields, names(found$schema$properties))
    if (length(absent)) {
      problems <- c(problems, sprintf(
        "%s() reads %s from %s, which %s does not declare",
        fun, paste0("`", absent, "`", collapse = ", "), response_readers[[fun]],
        found$schema$title %||% "the response model"
      ))
    }
  }
  expect_no_drift(problems, "Fields read from responses")
})
