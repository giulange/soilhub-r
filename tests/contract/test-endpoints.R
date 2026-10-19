# Every path the client calls exists with the method used (design 7.2).

test_that("the unit tests exercise the client requests", {
  requests <- client_requests()
  expect_gt(length(requests), 50L)
})

test_that("every path the client calls exists with the method used", {
  doc <- contract_openapi()
  problems <- character()
  for (request in client_requests()) {
    match <- openapi_operation(doc, request$method, request$path)
    if (is.null(match)) {
      problems <- c(problems, sprintf("%s %s: no such path in the API%s",
                                      request$method, request$path, callers_label(request$callers)))
    } else if (is.null(match$operation)) {
      problems <- c(problems, sprintf("%s %s: the API path %s has no %s (only %s)%s",
                                      request$method, request$path, match$template, request$method,
                                      paste(match$methods, collapse = ", "), callers_label(request$callers)))
    }
  }
  expect_no_drift(problems, "Client requests to paths or methods the API does not have")
})

test_that("every API path literal of the package code is requested by the unit tests", {
  literals <- path_literals(asNamespace("soilhub"))
  literals <- literals[!literals$literal %in% non_api_literals, , drop = FALSE]
  paths <- unique(vapply(client_requests(), function(r) r$path, character(1)))
  seen <- vapply(literals$literal, function(l) any(grepl(l, paths, fixed = TRUE)), logical(1))
  missing <- literals[!seen, , drop = FALSE]
  expect_no_drift(
    sprintf("\"%s\" (in %s) is never requested through an exported function by the unit tests: add a fake-API test so that the contract suite sees the request",
            missing$literal, missing$object),
    "Path literals without a recorded request"
  )
})

test_that("API operations the client does not call are listed", {
  doc <- contract_openapi()
  operations <- openapi_operations(doc)
  used <- unique(unlist(lapply(client_requests(), function(r) {
    match <- openapi_operation(doc, r$method, r$path)
    if (!is.null(match$operation)) paste(r$method, match$template)
  })))
  unused <- operations[!paste(operations$method, operations$template) %in% used, , drop = FALSE]
  if (nrow(unused)) {
    message("API operations not called by the client: ",
            paste(unused$method, unused$path, collapse = ", "))
  }
  succeed()
})
