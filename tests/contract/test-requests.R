# Every request field the client sends is a property of the request schema,
# with a type the schema accepts; query parameters and form fields likewise
# (design 7.2).

local({
  doc <- contract_openapi()
  requests <- client_requests()
  key <- vapply(requests, function(r) {
    paste(r$method, r$path, jsonlite::toJSON(r$query, auto_unbox = TRUE), r$body %||% "",
          paste(names(r$upload), collapse = ","))
  }, character(1))
  requests <- requests[!duplicated(key)]
  template <- vapply(requests, function(r) {
    match <- openapi_operation(doc, r$method, r$path)
    if (is.null(match$operation)) "(unknown)" else paste(r$method, openapi_client_path(match$template))
  }, character(1))

  for (operation in sort(unique(template))) {
    if (identical(operation, "(unknown)")) next # test-endpoints.R reports them
    group <- requests[template == operation]
    test_that(sprintf("requests to %s match the API (%d distinct)", operation, length(group)), {
      problems <- unlist(lapply(group, function(r) {
        found <- contract_check_request(doc, r)
        if (length(found)) paste0(found, callers_label(r$callers)) else character()
      }))
      expect_no_drift(problems, sprintf("Requests to %s", operation))
    })
  }
})
