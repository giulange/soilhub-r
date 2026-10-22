# Contract checks and scrubbing (design 7.1, 7.2; WP10) on a small OpenAPI
# document; the contract suite itself (tests/contract) runs them on the API's.

mini_openapi <- function() {
  list(
    openapi = "3.1.0",
    info = list(title = "test", version = "0.6.0"),
    paths = list(
      "/api/v1/items" = list(
        post = list(
          requestBody = list(required = TRUE, content = list(
            "application/json" = list(schema = list(`$ref` = "#/components/schemas/ItemRequest"))
          )),
          responses = list("200" = list(content = list(
            "application/json" = list(schema = list(`$ref` = "#/components/schemas/ItemResponse"))
          )))
        ),
        get = list(
          parameters = list(
            list(name = "code", `in` = "query", required = FALSE,
                 schema = list(anyOf = list(list(type = "string"), list(type = "null")))),
            list(name = "limit", `in` = "query", required = TRUE, schema = list(type = "integer"))
          ),
          responses = list("200" = list(content = list(
            "application/json" = list(schema = list(type = "object", additionalProperties = TRUE))
          )))
        )
      ),
      "/api/v1/items/{item_id}" = list(get = list(responses = list("200" = list(content = list(
        "application/json" = list(schema = list(`$ref` = "#/components/schemas/ItemResponse"))
      ))))),
      "/api/v1/items/refresh" = list(post = list(responses = list("200" = list()))),
      "/api/v1/uploads" = list(post = list(requestBody = list(content = list(
        "multipart/form-data" = list(schema = list(
          type = "object", required = list("file", "key"),
          properties = list(file = list(type = "string"), key = list(type = "string"))
        ))
      ))))
    ),
    components = list(schemas = list(
      Layer = list(type = "string", enum = list("all", "first"), title = "Layer"),
      ItemRequest = list(
        type = "object", title = "ItemRequest", required = list("name"),
        properties = list(
          name = list(type = "string"),
          layer = list(`$ref` = "#/components/schemas/Layer", default = "all"),
          datasets = list(anyOf = list(list(type = "array", items = list(type = "string")), list(type = "null"))),
          limit = list(type = "integer"),
          tags = list(type = "array", items = list(`$ref` = "#/components/schemas/Tag"))
        )
      ),
      Tag = list(type = "object", title = "Tag", properties = list(key = list(type = "string"))),
      ItemResponse = list(
        type = "object", title = "ItemResponse",
        properties = list(
          id = list(type = "integer"),
          name = list(type = "string"),
          created_at = list(type = "string", format = "date-time"),
          parts = list(type = "array", items = list(`$ref` = "#/components/schemas/Tag")),
          extra = list(type = "object", additionalProperties = TRUE)
        )
      )
    ))
  )
}

json_request <- function(method, path, body = NULL, query = list()) {
  list(method = method, path = path, query = query,
       body = if (is.null(body)) NULL else as.character(request_body_json(body)))
}

test_that("openapi_prefix() is the path of the API URL", {
  expect_identical(openapi_prefix(), "/api/v1")
  expect_identical(openapi_prefix("http://localhost:8000/api/v1/"), "/api/v1")
  expect_identical(openapi_prefix("https://example.org"), "")
})

test_that("openapi_operation() matches client paths, literals before parameters", {
  doc <- mini_openapi()
  match <- openapi_operation(doc, "GET", "/items/abc")
  expect_identical(match$template, "/api/v1/items/{item_id}")
  expect_false(is.null(match$operation))
  expect_identical(openapi_operation(doc, "POST", "/items/refresh")$template, "/api/v1/items/refresh")
  wrong <- openapi_operation(doc, "DELETE", "/items")
  expect_null(wrong$operation)
  expect_identical(wrong$methods, c("POST", "GET"))
  expect_null(openapi_operation(doc, "GET", "/nothing/here"))
  ops <- openapi_operations(doc)
  expect_true(all(c("POST /items", "GET /items/{item_id}") %in% paste(ops$method, ops$path)))
})

test_that("a conforming request has no problem", {
  doc <- mini_openapi()
  body <- list(name = "a", layer = "first", datasets = I("x"), limit = 5,
               tags = list(list(key = "k")))
  expect_identical(contract_check_request(doc, json_request("POST", "/items", body)), character())
  expect_identical(contract_check_request(doc, json_request("GET", "/items", query = list(limit = 10, code = "x"))), character())
  expect_identical(contract_check_request(doc, json_request("POST", "/items/refresh")), character())
})

test_that("drift in a request is reported field by field", {
  doc <- mini_openapi()
  problems <- contract_check_request(doc, json_request("POST", "/items", list(
    layer = "second", datasets = "x", limit = 2.5, bogus = TRUE, tags = list(list(key = "k", other = 1))
  )))
  expect_length(problems, 6L)
  expect_match(problems, "body\\$layer: .*\"second\", which is not one of the values the API accepts \\(all, first\\)", all = FALSE)
  expect_match(problems, "body\\$datasets: the client sends string \"x\", the API expects array of string or null", all = FALSE)
  expect_match(problems, "body\\$limit: the client sends number 2.5, the API expects integer", all = FALSE)
  expect_match(problems, "the client sends the field `bogus`, which is not a property of ItemRequest", all = FALSE)
  expect_match(problems, "body\\$tags\\[\\]: the client sends the field `other`, which is not a property of Tag", all = FALSE)
  expect_match(problems, "does not send the required field\\(s\\) `name` of ItemRequest", all = FALSE)

  expect_match(contract_check_request(doc, json_request("GET", "/nothing")), "the API has no path /nothing")
  expect_match(contract_check_request(doc, json_request("DELETE", "/items")), "has no DELETE operation \\(only POST, GET\\)")
  expect_match(contract_check_request(doc, json_request("POST", "/items")), "sends no body, the API requires one")
  expect_match(contract_check_request(doc, json_request("POST", "/items/refresh", list(a = 1))), "the API declares none")

  query <- contract_check_request(doc, json_request("GET", "/items", query = list(bogus = 1, code = c("a", "b"))))
  expect_match(query, "query parameter `bogus`, which the API does not declare", all = FALSE)
  expect_match(query, "query parameter `code`: the client repeats it", all = FALSE)
  expect_match(query, "required query parameter\\(s\\) `limit`", all = FALSE)
})

test_that("multipart uploads are checked by field name", {
  doc <- mini_openapi()
  ok <- list(method = "POST", path = "/uploads", query = list(), upload = list(key = "k"))
  expect_identical(contract_check_request(doc, ok), character())
  bad <- list(method = "POST", path = "/uploads", query = list(), upload = list(other = "x"))
  problems <- contract_check_request(doc, bad)
  expect_match(problems, "form field\\(s\\) `other`", all = FALSE)
  expect_match(problems, "required form field\\(s\\) `key`", all = FALSE)
  json <- json_request("POST", "/uploads", list(key = "k"))
  expect_match(contract_check_request(doc, json), "sends JSON, the API takes multipart/form-data")
})

test_that("enums are read through references and arrays and compared both ways", {
  doc <- mini_openapi()
  properties <- request_properties(doc, doc$paths[["/api/v1/items"]]$post)
  expect_identical(schema_enum(doc, properties$layer), c("all", "first"))
  expect_null(schema_enum(doc, properties$name))
  expect_identical(contract_check_enum(c("all", "first"), c("first", "all"), "layer"), character())
  problems <- contract_check_enum(c("all", "top"), c("all", "first"), "layer")
  expect_length(problems, 2L)
  expect_match(problems[1], "the client offers \"top\", which the API does not accept")
  expect_match(problems[2], "the API accepts \"first\", which the client does not offer")
})

test_that("typed response fields are checked against the response models", {
  doc <- mini_openapi()
  found <- response_schema_at(doc, "GET", "/items/{item_id}")
  expect_true(found$typed)
  expect_null(found$problem)
  expect_identical(
    contract_check_fields(doc, list(id = "int", name = "chr", created_at = "time",
                                    parts = frames(list(key = "chr")), extra = "json"),
                          found$schema, "items"),
    character()
  )
  problems <- contract_check_fields(doc, list(id = "lgl", gone = "chr", parts = "dbl"), found$schema, "items")
  expect_length(problems, 3L)
  expect_match(problems, "types `id` as \"lgl\", ItemResponse declares integer", all = FALSE)
  expect_match(problems, "the field `gone`, which is not in ItemResponse", all = FALSE)

  nested <- response_schema_at(doc, "GET", "/items/x", "parts[]")
  expect_true(nested$typed)
  expect_identical(nested$schema$title, "Tag")
  expect_false(response_schema_at(doc, "GET", "/items/x", "extra")$typed)
  expect_false(response_schema_at(doc, "GET", "/items")$typed)
  expect_match(response_schema_at(doc, "GET", "/items/x", "missing[]")$problem, "has no field `missing`")
  expect_match(response_schema_at(doc, "GET", "/items/x", "name[]")$problem, "is not an array")
  expect_match(response_schema_at(doc, "PUT", "/items")$problem, "the API has no PUT /items")
})

test_that("accessed_fields() and path_literals() read the package code", {
  f <- function(response) {
    x <- response$a + response$b
    g(response$a, other$c)
  }
  expect_identical(accessed_fields(f), c("a", "b"))
  ns <- new.env()
  assign("reader", function() soil_request(NULL, "GET", paste0("/things/", 1, "/parts")), envir = ns)
  assign("table", list(path = "/jobs/", other = "not/a/path"), envir = ns)
  literals <- path_literals(ns)
  expect_identical(literals$literal, c("/things/", "/parts", "/jobs/"))
  expect_identical(literals$object, c("reader", "reader", "table"))
})

test_that("openapi_diff() lists the differences of two documents", {
  old <- mini_openapi()
  expect_identical(openapi_diff(old, old), character())
  new <- old
  new$info$version <- "0.7.0"
  new$paths[["/api/v1/items/refresh"]] <- NULL
  new$paths[["/api/v1/other"]] <- list(get = list(responses = list()))
  new$paths[["/api/v1/items"]]$get$parameters[[1]] <- NULL
  new$components$schemas$Layer$enum <- list("all", "first", "last")
  new$components$schemas$ItemRequest$properties$name <- NULL
  new$components$schemas$ItemRequest$required <- list()
  new$components$schemas$New <- list(type = "object")
  diff <- openapi_diff(old, new)
  expect_true(all(c(
    "info.version: 0.6.0 -> 0.7.0",
    "operation added: GET /api/v1/other",
    "operation removed: POST /api/v1/items/refresh",
    "GET /api/v1/items: parameter removed: code (query)",
    "schema added: New",
    "schema ItemRequest: property removed: name",
    "schema ItemRequest: required: [name] -> []",
    "schema Layer: enum: [all, first] -> [all, first, last]"
  ) %in% diff))
  described <- old
  described$info$description <- "changed"
  expect_identical(openapi_diff(old, described), "other details changed (descriptions, info, servers)")
})

test_that("scrub_json() removes personal values, tokens, request ids and request times", {
  jwt <- "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ4In0.c2ln"
  x <- list(
    metadata = list(request_id = "abc-123", retrieved_at = "2026-10-19T10:00:00Z", count = 5L),
    user = list(sub = "f0e1-uuid", preferred_username = "jdoe", email = "jdoe@example.org"),
    note = "requested by jdoe with soilhub-20261019100000-0a1b2c3d",
    token = jwt,
    text = paste("Bearer", jwt),
    rows = list(list(name = "wosis_points", value = 1.5)),
    empty = NULL
  )
  out <- scrub_json(x, secrets = c("jdoe", "f0e1-uuid", "jdoe@example.org"))
  expect_identical(out$metadata$request_id, "scrubbed-request-id")
  expect_identical(out$metadata$retrieved_at, "2026-01-01T00:00:00Z")
  expect_identical(out$metadata$count, 5L)
  expect_identical(out$user, list(sub = "scrubbed", preferred_username = "scrubbed", email = "scrubbed"))
  expect_identical(out$note, "requested by scrubbed with soilhub-00000000000000-00000000")
  expect_identical(out$token, "scrubbed-token")
  expect_identical(out$text, "Bearer scrubbed-token")
  expect_identical(out$rows, x$rows)
  expect_true("empty" %in% names(out))
  text <- as.character(jsonlite::toJSON(out, auto_unbox = TRUE, null = "null"))
  expect_identical(scrub_leaks(text, c("jdoe", "f0e1-uuid", "jdoe@example.org")), character())
  expect_identical(scrub_leaks(paste("jdoe", jwt), c("jdoe", "ab")), c("jdoe", "a JWT"))
})

test_that("the exchange hook receives every request with its response", {
  seen <- list()
  local_opts(soilhub.exchange_hook = function(exchange) seen[[length(seen) + 1L]] <<- exchange)
  api <- fake_api(list(list(method = "post", path = "/api/v1/echo", handler = function(req, res) {
    res$send_json(list(ok = TRUE), auto_unbox = TRUE)
  })))
  soil <- test_session(api)
  soil_request(soil, "POST", "/echo", body = list(datasets = I("a"), layer = "all"),
               query = list(a = 1, b = NULL))
  expect_length(seen, 1L)
  expect_identical(seen[[1]]$method, "POST")
  expect_identical(seen[[1]]$path, "/echo")
  expect_identical(seen[[1]]$query, list(a = 1))
  expect_identical(seen[[1]]$body, "{\"datasets\":[\"a\"],\"layer\":\"all\"}")
  expect_null(seen[[1]]$upload)
  expect_identical(seen[[1]]$status, 200L)
  expect_identical(jsonlite::fromJSON(seen[[1]]$response), list(ok = TRUE))

  # an error of the hook is a warning, the request goes on
  local_opts(soilhub.exchange_hook = function(exchange) stop("boom"))
  expect_warning(out <- soil_request(soil, "POST", "/echo"), "soilhub.exchange_hook failed: boom")
  expect_true(out$ok)
})

test_that("streamed downloads pass through the exchange hook too", {
  seen <- list()
  local_opts(soilhub.exchange_hook = function(exchange) {
    if (!is.null(exchange$download)) exchange$size <- file.size(exchange$download)
    seen[[length(seen) + 1L]] <<- exchange
  })
  api <- fake_api(list(
    list(method = "get", path = "/api/v1/files/ok/download", handler = function(req, res) {
      res$set_type("application/zip")$send(as.raw(1:10))
    }),
    list(method = "get", path = "/api/v1/files/gone/download", handler = function(req, res) {
      res$set_status(404L)$send_json(list(detail = "Export not found"), auto_unbox = TRUE)
    })
  ))
  soil <- test_session(api)
  dest <- withr::local_tempfile(fileext = ".zip")
  soil_download(soil, "/files/ok/download", dest)
  expect_identical(readBin(dest, "raw", 100), as.raw(1:10))
  expect_length(seen, 1L)
  expect_identical(seen[[1]][c("method", "path", "status")], list(method = "GET", path = "/files/ok/download", status = 200L))
  expect_identical(seen[[1]]$query, list())
  expect_null(seen[[1]]$body)
  expect_null(seen[[1]]$response)
  expect_identical(seen[[1]]$size, 10)

  expect_error(soil_download(soil, "/files/gone/download", dest), class = "soilhub_not_found_error")
  expect_length(seen, 2L)
  expect_identical(seen[[2]]$status, 404L)
  expect_null(seen[[2]]$download)
  expect_match(seen[[2]]$response, "Export not found")
})
