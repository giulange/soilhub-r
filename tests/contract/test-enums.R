# Enumerated values the client offers equal the schema's (design 7.2):
# the selection constants (`selection_values`: geometry, layer, view,
# components; profile_type is a free array of strings in the OpenAPI and is
# compared with capabilities.json in test-capabilities.R) and the choices of
# the exported functions (`arg = c("a", "b")`) that are request fields of the
# endpoints the function calls (layout; format and content of the exports).

# The request schemas (JSON body properties and query parameters) of the
# operations the client calls, by operation.
called_fields <- function(doc) {
  out <- list()
  for (r in client_requests()) {
    match <- openapi_operation(doc, r$method, r$path)
    if (is.null(match$operation)) next
    label <- paste(r$method, openapi_client_path(match$template))
    if (!is.null(out[[label]])) {
      out[[label]]$callers <- union(out[[label]]$callers, r$callers)
      next
    }
    fields <- request_properties(doc, match$operation) %||% list()
    for (p in match$operation$parameters %||% list()) {
      p <- openapi_resolve(doc, p)
      if (identical(p[["in"]], "query") && is.null(fields[[p$name]])) fields[[p$name]] <- p$schema
    }
    out[[label]] <- list(fields = fields, callers = r$callers)
  }
  out
}

test_that("the selection values equal the API enums", {
  doc <- contract_openapi()
  operations <- called_fields(doc)
  problems <- character()
  compared <- character()
  for (name in names(selection_values)) {
    for (label in names(operations)) {
      schema <- operations[[label]]$fields[[name]]
      if (is.null(schema)) next
      accepted <- schema_enum(doc, schema)
      if (is.null(accepted)) next
      compared <- c(compared, name)
      problems <- c(problems, contract_check_enum(
        selection_values[[name]], accepted, sprintf("`%s` of %s (selection_values$%s)", name, label, name)
      ))
    }
  }
  expect_no_drift(problems, "Selection values")
  expect_setequal(unique(compared), c("geometry", "layer", "view", "components"))
})

test_that("the choices of the exported functions equal the API enums", {
  doc <- contract_openapi()
  operations <- called_fields(doc)
  ns <- asNamespace("soilhub")
  problems <- character()
  for (fun in getNamespaceExports("soilhub")) {
    f <- get(fun, envir = ns)
    if (!is.function(f)) next
    defaults <- formals(f)
    for (arg in names(defaults)) {
      if (!is.call(defaults[[arg]])) next
      default <- defaults[[arg]]
      if (!identical(default[[1]], as.name("c"))) next
      offered <- tryCatch(eval(default, baseenv()), error = function(e) NULL)
      if (!is.character(offered) || length(offered) < 2L) next
      for (label in names(operations)) {
        if (!fun %in% operations[[label]]$callers) next
        schema <- operations[[label]]$fields[[arg]]
        if (is.null(schema)) next
        accepted <- schema_enum(doc, schema)
        if (is.null(accepted)) next
        problems <- c(problems, contract_check_enum(offered, accepted, sprintf("`%s` of %s() (%s)", arg, fun, label)))
      }
    }
  }
  expect_no_drift(problems, "Choices of the exported functions")
})
