# Contract checks against the OpenAPI document of the API (design 7.2) and
# scrubbing of recorded responses (design 7.1), WP10. Pure functions, no
# network: the contract suite (tests/contract/) applies them to the committed
# snapshot or to the live document, `tools/update_contract_snapshots.R` diffs
# two documents with `openapi_diff()`, `tools/record_fixtures.R` scrubs what
# it records with `scrub_json()`.
#
# The OpenAPI document is parsed with `jsonlite::fromJSON(simplifyVector =
# FALSE)`. Its paths carry the API prefix ("/api/v1"); the client's paths are
# below `api_url` and get the prefix of `openapi_prefix()`.

# ---------------------------------------------------------------------------
# Operations and schemas

#' The API prefix of the OpenAPI paths
#'
#' @param api_url The API base URL; the default of [soil_config()].
#' @return The path of `api_url` without the trailing slash (`"/api/v1"`).
#' @keywords internal
#' @noRd
openapi_prefix <- function(api_url = config_defaults$api_url) {
  sub("/+$", "", sub("^[A-Za-z][A-Za-z0-9+.-]*://[^/]+", "", api_url))
}

#' The OpenAPI operation of a client request
#'
#' @param doc The OpenAPI document (a list).
#' @param method HTTP method.
#' @param path The client path, below `api_url` (e.g. `"/jobs/0b4e"`), or a
#'   template (`"/jobs/{job_id}"`).
#' @param prefix The API prefix of the document paths.
#' @return `NULL` when no path matches; else a list: `template` (the document
#'   path), `methods` (its methods) and `operation` (`NULL` when the path has
#'   no operation for `method`). A literal segment wins over a parameter
#'   (`/countries/refresh` before `/countries/{code}`).
#' @keywords internal
#' @noRd
openapi_operation <- function(doc, method, path, prefix = openapi_prefix()) {
  method <- tolower(method)
  path <- sub("[?#].*$", "", path)
  segments <- strsplit(paste0(prefix, path), "/", fixed = TRUE)[[1]]
  best <- NULL
  best_params <- Inf
  for (template in names(doc$paths)) {
    parts <- strsplit(template, "/", fixed = TRUE)[[1]]
    if (length(parts) != length(segments)) next
    param <- grepl("^\\{[^}]+\\}$", parts)
    if (!all(param | parts == segments) || !all(nzchar(segments[param]))) next
    item <- doc$paths[[template]]
    has_method <- !is.null(item[[method]])
    # prefer a template with the method, then the fewest parameters
    score <- sum(param) + if (has_method) 0 else 1000
    if (score < best_params) {
      best_params <- score
      best <- list(
        template = template,
        methods = toupper(intersect(names(item), c("get", "post", "put", "patch", "delete", "head", "options"))),
        operation = item[[method]]
      )
    }
  }
  best
}

#' The client path of an OpenAPI path
#' @noRd
openapi_client_path <- function(template, prefix = openapi_prefix()) {
  if (nzchar(prefix) && startsWith(template, prefix)) substring(template, nchar(prefix) + 1L) else template
}

#' Every operation of an OpenAPI document
#'
#' @return A data frame: `method`, `path` (the client path, without prefix),
#'   `template` (the document path).
#' @keywords internal
#' @noRd
openapi_operations <- function(doc, prefix = openapi_prefix()) {
  rows <- list()
  for (template in names(doc$paths)) {
    for (method in intersect(names(doc$paths[[template]]), c("get", "post", "put", "patch", "delete"))) {
      rows[[length(rows) + 1L]] <- c(toupper(method), openapi_client_path(template, prefix), template)
    }
  }
  if (!length(rows)) return(data.frame(method = character(), path = character(), template = character()))
  m <- do.call(rbind, rows)
  data.frame(method = m[, 1], path = m[, 2], template = m[, 3], stringsAsFactors = FALSE)
}

# Follow `$ref` (local references only).
openapi_resolve <- function(doc, schema) {
  seen <- 0L
  while (is.list(schema) && is_string(schema[["$ref"]])) {
    seen <- seen + 1L
    if (seen > 50L) break
    parts <- strsplit(sub("^#/", "", schema[["$ref"]]), "/", fixed = TRUE)[[1]]
    target <- doc
    for (part in parts) target <- target[[part]]
    schema <- target
  }
  schema
}

# The alternatives of a schema: `anyOf` / `oneOf` flattened, `$ref` resolved,
# `allOf` merged. A schema without any is its own single branch.
schema_branches <- function(doc, schema) {
  schema <- openapi_resolve(doc, schema)
  if (!is.list(schema)) return(list())
  alternatives <- schema$anyOf %||% schema$oneOf
  if (!is.null(alternatives)) {
    return(unlist(lapply(alternatives, function(s) schema_branches(doc, s)), recursive = FALSE))
  }
  if (!is.null(schema$allOf)) {
    merged <- schema[setdiff(names(schema), "allOf")]
    for (part in schema$allOf) {
      part <- openapi_resolve(doc, part)
      merged$properties <- c(merged$properties, part$properties)
      merged$required <- c(merged$required, part$required)
      merged$type <- merged$type %||% part$type
    }
    return(list(merged))
  }
  list(schema)
}

# The JSON types a schema branch accepts ("any" when it does not say).
schema_types <- function(schema) {
  if (!is.null(schema$type)) return(unlist(schema$type))
  if (!is.null(schema$properties) || !is.null(schema$additionalProperties)) return("object")
  if (!is.null(schema$items)) return("array")
  if (!is.null(schema$enum)) {
    return(unique(vapply(schema$enum, function(v) json_kind(v), character(1))))
  }
  if (!is.null(schema$const)) return(json_kind(schema$const))
  "any"
}

# The non-null branches of a schema.
schema_values <- function(doc, schema) {
  Filter(function(b) !identical(schema_types(b), "null"), schema_branches(doc, schema))
}

# The JSON type of a parsed JSON value (simplifyVector = FALSE).
json_kind <- function(value) {
  if (is.null(value)) return("null")
  if (is.list(value)) {
    if (length(value) == 0L) return(if (is.null(names(value))) "array" else "object")
    return(if (!is.null(names(value)) && all(nzchar(names(value)))) "object" else "array")
  }
  if (length(value) != 1L) return("array")
  if (is.na(value)) return("null")
  if (is.logical(value)) return("boolean")
  if (is.integer(value)) return("integer")
  if (is.numeric(value)) return(if (is.finite(value) && value == round(value)) "integer" else "number")
  if (is.character(value)) return("string")
  "any"
}

kind_matches <- function(kind, types) {
  if ("any" %in% types || identical(kind, "any")) return(TRUE)
  if (kind %in% types) return(TRUE)
  if (identical(kind, "integer") && "number" %in% types) return(TRUE)
  # an empty JSON object or array parses the same
  FALSE
}

describe_schema <- function(schema) {
  types <- schema_types(schema)
  text <- paste(types, collapse = "/")
  if (!is.null(schema$title) && identical(types, "object")) text <- paste0(text, " ", schema$title)
  if (!is.null(schema$enum)) text <- paste0(text, " (", paste(unlist(schema$enum), collapse = ", "), ")")
  if (identical(types, "array") && is.list(schema$items)) text <- paste0("array of ", paste(schema_types(schema$items), collapse = "/"))
  text
}

describe_value <- function(value, kind) {
  if (kind %in% c("string", "integer", "number", "boolean") && length(value) == 1L) {
    shown <- if (is.character(value)) paste0("\"", value, "\"") else format(value)
    return(paste(kind, shown))
  }
  kind
}

#' Check a JSON value against a schema
#'
#' @param doc The OpenAPI document.
#' @param value A parsed JSON value (`simplifyVector = FALSE`).
#' @param schema The schema (may be a `$ref`).
#' @param where Where the value is, for the messages (e.g. `"body field
#'   `layer`"`).
#' @return A character vector of problems (empty when the value conforms):
#'   an unknown property, a type the schema does not accept, a value outside
#'   its `enum`, a missing required property.
#' @keywords internal
#' @noRd
contract_check_value <- function(doc, value, schema, where) {
  branches <- schema_branches(doc, schema)
  if (!length(branches)) return(character())
  kind <- json_kind(value)
  results <- lapply(branches, function(branch) check_branch(doc, value, kind, branch, where))
  ok <- vapply(results, function(r) length(r) == 0L, logical(1))
  if (any(ok)) return(character())
  typed <- vapply(branches, function(b) kind_matches(kind, schema_types(b)), logical(1))
  if (any(typed)) return(results[[which(typed)[1]]])
  sprintf(
    "%s: the client sends %s, the API expects %s",
    where, describe_value(value, kind),
    paste(unique(vapply(branches, describe_schema, character(1))), collapse = " or ")
  )
}

check_branch <- function(doc, value, kind, schema, where) {
  types <- schema_types(schema)
  if (!kind_matches(kind, types)) {
    return(sprintf("%s: the client sends %s, the API expects %s",
                   where, describe_value(value, kind), describe_schema(schema)))
  }
  if (!is.null(schema$enum) && kind %in% c("string", "integer", "number", "boolean") &&
      !value %in% unlist(schema$enum)) {
    return(sprintf("%s: the client sends %s, which is not one of the values the API accepts (%s)",
                   where, describe_value(value, kind), paste(unlist(schema$enum), collapse = ", ")))
  }
  if (identical(kind, "array") && is.list(schema$items)) {
    problems <- unlist(lapply(value, function(item) {
      contract_check_value(doc, item, schema$items, paste0(where, "[]"))
    }))
    return(unique(problems))
  }
  if (identical(kind, "object")) return(check_object(doc, value, schema, where))
  character()
}

check_object <- function(doc, value, schema, where) {
  properties <- schema$properties
  additional <- schema$additionalProperties
  problems <- character()
  for (name in names(value)) {
    field <- paste0(where, "$", name)
    if (!is.null(properties[[name]])) {
      problems <- c(problems, contract_check_value(doc, value[[name]], properties[[name]], field))
    } else if (is.list(additional)) {
      problems <- c(problems, contract_check_value(doc, value[[name]], additional, field))
    } else if (!is.null(properties) && !isTRUE(additional)) {
      problems <- c(problems, sprintf(
        "%s: the client sends the field `%s`, which is not a property of %s",
        where, name, schema$title %||% "the API schema"
      ))
    }
  }
  missing <- setdiff(unlist(schema$required), names(value))
  if (length(missing)) {
    problems <- c(problems, sprintf(
      "%s: the client does not send the required field(s) %s of %s",
      where, paste0("`", missing, "`", collapse = ", "), schema$title %||% "the API schema"
    ))
  }
  problems
}

#' Check a recorded client request against the OpenAPI document
#'
#' @param doc The OpenAPI document.
#' @param request A request as passed to the `soilhub.exchange_hook` option
#'   (`method`, `path`, `query`, `body` (JSON text), `upload`).
#' @param prefix The API prefix of the document paths.
#' @return A character vector of problems: unknown path or method, query
#'   parameters, JSON body fields and multipart fields the operation does not
#'   declare or types it does not accept, required ones not sent.
#' @keywords internal
#' @noRd
contract_check_request <- function(doc, request, prefix = openapi_prefix()) {
  label <- paste(request$method, request$path)
  match <- openapi_operation(doc, request$method, request$path, prefix)
  if (is.null(match)) {
    return(sprintf("%s: the API has no path %s", label, request$path))
  }
  if (is.null(match$operation)) {
    return(sprintf("%s: the API path %s has no %s operation (only %s)",
                   label, match$template, request$method, paste(match$methods, collapse = ", ")))
  }
  label <- paste0(request$method, " ", openapi_client_path(match$template, prefix))
  operation <- match$operation
  c(
    check_query(doc, operation, request$query, label),
    check_body(doc, operation, request, label)
  )
}

check_query <- function(doc, operation, query, label) {
  parameters <- lapply(operation$parameters %||% list(), function(p) openapi_resolve(doc, p))
  parameters <- Filter(function(p) identical(p[["in"]], "query"), parameters)
  names(parameters) <- vapply(parameters, function(p) p$name, character(1))
  problems <- character()
  for (name in names(query)) {
    parameter <- parameters[[name]]
    if (is.null(parameter)) {
      problems <- c(problems, sprintf("%s: the client sends the query parameter `%s`, which the API does not declare", label, name))
      next
    }
    values <- query[[name]]
    is_array <- any(vapply(schema_values(doc, parameter$schema), function(b) "array" %in% schema_types(b), logical(1)))
    where <- sprintf("%s: query parameter `%s`", label, name)
    if (is_array) {
      problems <- c(problems, contract_check_value(doc, as.list(values), parameter$schema, where))
    } else if (length(values) > 1L) {
      problems <- c(problems, sprintf("%s: the client repeats it (%d values), the API takes one", where, length(values)))
    } else {
      problems <- c(problems, contract_check_value(doc, values, parameter$schema, where))
    }
  }
  required <- names(Filter(function(p) isTRUE(p$required), parameters))
  missing <- setdiff(required, names(query))
  if (length(missing)) {
    problems <- c(problems, sprintf("%s: the client does not send the required query parameter(s) %s",
                                    label, paste0("`", missing, "`", collapse = ", ")))
  }
  problems
}

check_body <- function(doc, operation, request, label) {
  content <- operation$requestBody$content
  sent_json <- !is.null(request$body)
  sent_upload <- !is.null(request$upload)
  if (!sent_json && !sent_upload) {
    if (isTRUE(operation$requestBody$required)) {
      return(sprintf("%s: the client sends no body, the API requires one (%s)", label, paste(names(content), collapse = ", ")))
    }
    return(character())
  }
  if (is.null(content)) {
    return(sprintf("%s: the client sends a body, the API declares none", label))
  }
  if (sent_json) {
    schema <- content[["application/json"]]$schema
    if (is.null(schema)) {
      return(sprintf("%s: the client sends JSON, the API takes %s", label, paste(names(content), collapse = ", ")))
    }
    body <- jsonlite::fromJSON(request$body, simplifyVector = FALSE)
    return(contract_check_value(doc, body, schema, paste0(label, ": body")))
  }
  schema <- content[["multipart/form-data"]]$schema
  if (is.null(schema)) {
    return(sprintf("%s: the client uploads a multipart form, the API takes %s", label, paste(names(content), collapse = ", ")))
  }
  # the text fields of a form are strings on the wire; only names and the
  # required ones are checked, and the file is always sent
  schema <- openapi_resolve(doc, schema)
  fields <- c(names(request$upload), "file")
  unknown <- setdiff(fields, names(schema$properties))
  missing <- setdiff(unlist(schema$required), fields)
  c(
    character(),
    if (length(unknown)) sprintf("%s: the client sends the form field(s) %s, which the API does not declare",
                                 label, paste0("`", unknown, "`", collapse = ", ")),
    if (length(missing)) sprintf("%s: the client does not send the required form field(s) %s",
                                 label, paste0("`", missing, "`", collapse = ", "))
  )
}

#' The values of an enumerated request field
#'
#' @param doc The OpenAPI document.
#' @param schema The schema of the field; arrays give the enum of their items.
#' @return The enum values (character), or `NULL` when the field is not
#'   enumerated.
#' @keywords internal
#' @noRd
schema_enum <- function(doc, schema) {
  values <- NULL
  for (branch in schema_values(doc, schema)) {
    if (!is.null(branch$enum)) values <- c(values, unlist(branch$enum))
    if (is.list(branch$items)) values <- c(values, schema_enum(doc, branch$items))
  }
  if (is.null(values)) NULL else unique(as.character(values))
}

#' Compare the values the client offers with an enumerated field
#'
#' @return A character vector of problems (empty when the sets are equal).
#' @keywords internal
#' @noRd
contract_check_enum <- function(offered, accepted, where) {
  offered <- unique(as.character(offered))
  extra <- setdiff(offered, accepted)
  absent <- setdiff(accepted, offered)
  c(
    character(),
    if (length(extra)) sprintf("%s: the client offers %s, which the API does not accept (API values: %s)",
                               where, paste0("\"", extra, "\"", collapse = ", "), paste(accepted, collapse = ", ")),
    if (length(absent)) sprintf("%s: the API accepts %s, which the client does not offer (client values: %s)",
                                where, paste0("\"", absent, "\"", collapse = ", "), paste(offered, collapse = ", "))
  )
}

#' The properties of a request body
#'
#' @return The named list of properties of the JSON request schema of an
#'   operation (`NULL` when it has none).
#' @keywords internal
#' @noRd
request_properties <- function(doc, operation) {
  schema <- operation$requestBody$content[["application/json"]]$schema
  if (is.null(schema)) return(NULL)
  branches <- schema_values(doc, schema)
  properties <- NULL
  for (branch in branches) properties <- c(properties, branch$properties)
  properties
}

# ---------------------------------------------------------------------------
# Response models

#' The response schema at a location of an operation
#'
#' @param doc The OpenAPI document.
#' @param method,path The operation (client path or template).
#' @param pointer Steps into the 2xx JSON response: `"a"` the property `a`,
#'   `"a[]"` the items of the array `a`, `"a{}"` the values of the map `a`,
#'   separated by `.`; `""` the response itself.
#' @return A list: `schema` (the resolved, non-null schema at the location),
#'   `typed` (`TRUE` when it declares properties), `problem` (a message when
#'   the location does not exist, else `NULL`).
#' @keywords internal
#' @noRd
response_schema_at <- function(doc, method, path, pointer = "", prefix = openapi_prefix()) {
  label <- trimws(paste(method, path, pointer))
  match <- openapi_operation(doc, method, path, prefix)
  if (is.null(match) || is.null(match$operation)) {
    return(list(schema = NULL, typed = FALSE, problem = sprintf("%s: the API has no %s %s", label, method, path)))
  }
  responses <- match$operation$responses
  codes <- grep("^2", names(responses), value = TRUE)
  schema <- if (length(codes)) responses[[codes[1]]]$content[["application/json"]]$schema else NULL
  steps <- if (nzchar(pointer)) strsplit(pointer, ".", fixed = TRUE)[[1]] else character()
  for (step in steps) {
    if (!length(object_branch(doc, schema))) {
      # an untyped object or no schema: nothing below can be checked
      return(list(schema = NULL, typed = FALSE, problem = NULL))
    }
    name <- sub("(\\[\\]|\\{\\})+$", "", step)
    branch <- object_branch(doc, schema)
    if (is.null(branch$properties)) return(list(schema = NULL, typed = FALSE, problem = NULL))
    field <- branch$properties[[name]]
    if (is.null(field)) {
      return(list(schema = NULL, typed = FALSE, problem = sprintf(
        "%s: the API response %s has no field `%s`", label, branch$title %||% "", name
      )))
    }
    suffixes <- regmatches(step, gregexpr("\\[\\]|\\{\\}", step))[[1]]
    for (suffix in suffixes) {
      if (identical(suffix, "[]")) {
        arrays <- Filter(function(b) "array" %in% schema_types(b), schema_values(doc, field))
        if (!length(arrays)) {
          return(list(schema = NULL, typed = FALSE, problem = sprintf("%s: the field `%s` is not an array", label, name)))
        }
        field <- arrays[[1]]$items
      } else {
        maps <- Filter(function(b) is.list(b$additionalProperties), schema_values(doc, field))
        if (!length(maps)) return(list(schema = NULL, typed = FALSE, problem = NULL))
        field <- maps[[1]]$additionalProperties
      }
    }
    schema <- field
  }
  branch <- object_branch(doc, schema)
  list(schema = branch, typed = length(branch) > 0L && !is.null(branch$properties), problem = NULL)
}

# The first non-null object branch of a schema, or an empty list.
object_branch <- function(doc, schema) {
  if (is.null(schema)) return(list())
  for (branch in schema_values(doc, schema)) {
    if ("object" %in% schema_types(branch) || !is.null(branch$properties)) return(branch)
  }
  list()
}

# JSON types an R column type of typing.R reads without loss.
typing_json_types <- list(
  chr = c("string", "integer", "number", "boolean"),
  int = "integer",
  dbl = c("integer", "number"),
  lgl = "boolean",
  time = "string",
  date = "string",
  chr_list = "array",
  json = "any"
)

#' Check typed response fields against a response model
#'
#' @param doc The OpenAPI document.
#' @param fields A named list (or character vector) of column types of
#'   `typing.R` (`frames()` for nested arrays of objects); `NA` checks the
#'   name only.
#' @param schema The resolved object schema (from `response_schema_at()`).
#' @param where The table and location, for the messages.
#' @return A character vector of problems: fields the model does not have,
#'   and types it does not declare.
#' @keywords internal
#' @noRd
contract_check_fields <- function(doc, fields, schema, where) {
  properties <- schema$properties
  title <- schema$title %||% "the response model"
  problems <- character()
  for (name in names(fields)) {
    field <- properties[[name]]
    if (is.null(field)) {
      problems <- c(problems, sprintf("%s: the client types the field `%s`, which is not in %s", where, name, title))
      next
    }
    type <- fields[[name]]
    accepted <- if (inherits(type, "soilhub_frames_type")) {
      c("array", "object")
    } else if (is.character(type) && length(type) == 1L && !is.na(type)) {
      typing_json_types[[type]] %||% "any"
    } else {
      "any"
    }
    declared <- unique(unlist(lapply(schema_values(doc, field), schema_types)))
    if (!length(declared) || "any" %in% declared || "any" %in% accepted) next
    if (!length(intersect(declared, c(accepted, if ("number" %in% accepted) "integer")))) {
      shown <- if (inherits(type, "soilhub_frames_type")) "a list of data frames" else paste0("\"", type, "\"")
      problems <- c(problems, sprintf(
        "%s: the client types `%s` as %s, %s declares %s",
        where, name, shown, title, paste(declared, collapse = "/")
      ))
    }
  }
  problems
}

#' The fields a function reads from a variable
#'
#' Walks the body of a function for `var$field` (static, no evaluation).
#'
#' @param fun A function.
#' @param var The variable name (e.g. `"response"`).
#' @return The field names, unique, in order of appearance.
#' @keywords internal
#' @noRd
accessed_fields <- function(fun, var = "response") {
  walk <- function(e) {
    if (!is.call(e)) return(character())
    out <- character()
    if (identical(e[[1]], as.name("$")) && identical(e[[2]], as.name(var))) {
      out <- as.character(e[[3]])
    }
    for (i in seq_along(e)[-1]) {
      arg <- e[[i]]
      if (!missing(arg)) out <- c(out, walk(arg))
    }
    out
  }
  unique(walk(body(fun)))
}

#' API path literals in the package code
#'
#' Walks the bodies of the functions and the lists of the namespace for
#' character constants that look like API paths (`/name`, `/a/b/`).
#'
#' @param ns The namespace environment.
#' @return A data frame: `literal` and `object` (where it was found).
#' @keywords internal
#' @noRd
path_literals <- function(ns = asNamespace("soilhub")) {
  pattern <- "^/[a-z][a-z0-9_-]*(/[a-z0-9_-]+)*/?$"
  walk <- function(e) {
    if (is.character(e)) return(e[!is.na(e) & grepl(pattern, e)])
    if (is.function(e)) return(if (is.primitive(e)) character() else walk(body(e)))
    if (is.call(e) || is.pairlist(e) || is.list(e)) {
      out <- character()
      for (i in seq_along(e)) {
        arg <- e[[i]]
        if (!missing(arg) && !is.null(arg)) out <- c(out, walk(arg))
      }
      return(out)
    }
    character()
  }
  rows <- list()
  for (name in ls(ns, all.names = FALSE)) {
    found <- unique(walk(get(name, envir = ns)))
    if (length(found)) rows[[length(rows) + 1L]] <- data.frame(literal = found, object = name, stringsAsFactors = FALSE)
  }
  if (!length(rows)) return(data.frame(literal = character(), object = character()))
  do.call(rbind, rows)
}

# ---------------------------------------------------------------------------
# Live diff

#' Differences between two OpenAPI documents
#'
#' @param old,new Two OpenAPI documents (lists).
#' @return A character vector, one line per difference (empty when the
#'   documents are identical): API version, operations added or removed,
#'   parameters, request and response schemas of the operations, schemas
#'   added or removed, properties, required fields, enums and types of the
#'   schemas.
#' @keywords internal
#' @noRd
openapi_diff <- function(old, new) {
  out <- character()
  if (!identical(old$info$version, new$info$version)) {
    out <- c(out, sprintf("info.version: %s -> %s", old$info$version %||% "none", new$info$version %||% "none"))
  }
  key <- function(ops) paste(ops$method, ops$template)
  old_ops <- openapi_operations(old, prefix = "")
  new_ops <- openapi_operations(new, prefix = "")
  for (op in setdiff(key(new_ops), key(old_ops))) out <- c(out, paste("operation added:", op))
  for (op in setdiff(key(old_ops), key(new_ops))) out <- c(out, paste("operation removed:", op))
  for (op in intersect(key(old_ops), key(new_ops))) {
    parts <- strsplit(op, " ", fixed = TRUE)[[1]]
    a <- old$paths[[parts[2]]][[tolower(parts[1])]]
    b <- new$paths[[parts[2]]][[tolower(parts[1])]]
    pa <- vapply(a$parameters %||% list(), function(p) paste0(p$name, " (", p[["in"]], ")"), character(1))
    pb <- vapply(b$parameters %||% list(), function(p) paste0(p$name, " (", p[["in"]], ")"), character(1))
    for (p in setdiff(pb, pa)) out <- c(out, sprintf("%s: parameter added: %s", op, p))
    for (p in setdiff(pa, pb)) out <- c(out, sprintf("%s: parameter removed: %s", op, p))
    for (p in intersect(pa, pb)) {
      if (!identical(a$parameters[[match(p, pa)]], b$parameters[[match(p, pb)]])) {
        out <- c(out, sprintf("%s: parameter changed: %s", op, p))
      }
    }
    if (!identical(a$requestBody, b$requestBody)) out <- c(out, sprintf("%s: request body changed", op))
    if (!identical(a$responses, b$responses)) out <- c(out, sprintf("%s: responses changed", op))
  }
  sa <- old$components$schemas %||% list()
  sb <- new$components$schemas %||% list()
  for (s in setdiff(names(sb), names(sa))) out <- c(out, paste("schema added:", s))
  for (s in setdiff(names(sa), names(sb))) out <- c(out, paste("schema removed:", s))
  for (s in intersect(names(sa), names(sb))) {
    a <- sa[[s]]
    b <- sb[[s]]
    if (identical(a, b)) next
    for (p in setdiff(names(b$properties), names(a$properties))) out <- c(out, sprintf("schema %s: property added: %s", s, p))
    for (p in setdiff(names(a$properties), names(b$properties))) out <- c(out, sprintf("schema %s: property removed: %s", s, p))
    for (p in intersect(names(a$properties), names(b$properties))) {
      if (!identical(a$properties[[p]], b$properties[[p]])) out <- c(out, sprintf("schema %s: property changed: %s", s, p))
    }
    if (!identical(sort(unlist(a$required)), sort(unlist(b$required)))) {
      out <- c(out, sprintf("schema %s: required: [%s] -> [%s]", s,
                            paste(unlist(a$required), collapse = ", "), paste(unlist(b$required), collapse = ", ")))
    }
    if (!identical(unlist(a$enum), unlist(b$enum))) {
      out <- c(out, sprintf("schema %s: enum: [%s] -> [%s]", s,
                            paste(unlist(a$enum), collapse = ", "), paste(unlist(b$enum), collapse = ", ")))
    }
    rest <- function(x) x[setdiff(names(x), c("properties", "required", "enum"))]
    if (!identical(rest(a), rest(b))) out <- c(out, sprintf("schema %s: description or other details changed", s))
  }
  if (!length(out) && !identical(old, new)) out <- "other details changed (descriptions, info, servers)"
  out
}

# ---------------------------------------------------------------------------
# Scrubbing of recorded responses (design 7.1)

#' Default scrubbing rules of the recorded fixtures
#' @noRd
scrub_defaults <- list(
  # personal or session identifiers, wherever they appear as keys
  identity_keys = c(
    "sub", "preferred_username", "email", "given_name", "family_name",
    "username", "user_id", "user_name", "created_by", "submitted_by",
    "requested_by", "owner", "sid", "session_state"
  ),
  token_keys = c(
    "access_token", "refresh_token", "id_token", "token", "authorization",
    "device_code", "user_code"
  ),
  # request-scoped identifiers
  request_keys = c("request_id", "correlation_id", "worker_id", "receipt_id"),
  # request-scoped times: fixed so that a new recording differs only in data
  time_keys = c("retrieved_at", "generated_at", "server_time", "requested_at",
                "heartbeat_at", "lease_expires_at"),
  replacement = list(
    identity = "scrubbed",
    token = "scrubbed-token",
    request = "scrubbed-request-id",
    time = "2026-01-01T00:00:00Z"
  )
)

#' Scrub a parsed JSON value
#'
#' Replaces the values of personal, token, request-scoped and time keys
#' (anywhere in the value), then every occurrence of the `secrets` (the user
#' name, subject, e-mail of the recording session, its tokens) and of JWTs and
#' client request ids inside the strings.
#'
#' @param x A parsed JSON value (`simplifyVector = FALSE`).
#' @param secrets Character vector of strings that must not appear.
#' @param rules The rules (`scrub_defaults`).
#' @return `x` scrubbed.
#' @keywords internal
#' @noRd
scrub_json <- function(x, secrets = character(), rules = scrub_defaults) {
  secrets <- unique(secrets[!is.na(secrets) & nchar(secrets) >= 3L])
  walk <- function(value, key = NULL) {
    if (!is.null(key) && !is.null(value) && !is.list(value)) {
      lower <- tolower(key)
      if (lower %in% rules$identity_keys) return(rules$replacement$identity)
      if (lower %in% rules$token_keys) return(rules$replacement$token)
      if (lower %in% rules$request_keys) return(rules$replacement$request)
      if (lower %in% rules$time_keys && is.character(value)) return(rules$replacement$time)
    }
    if (is.list(value)) {
      keys <- names(value)
      for (i in seq_along(value)) {
        item <- value[[i]]
        if (is.null(item)) next
        value[[i]] <- walk(item, if (is.null(keys)) NULL else keys[[i]])
      }
      return(value)
    }
    if (is.character(value)) return(scrub_text(value, secrets, rules))
    value
  }
  walk(x)
}

#' Scrub a text
#' @noRd
scrub_text <- function(text, secrets = character(), rules = scrub_defaults) {
  text <- gsub("eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]*", rules$replacement$token, text, perl = TRUE)
  text <- gsub("soilhub-[0-9]{14}-[0-9a-f]{8}", "soilhub-00000000000000-00000000", text, perl = TRUE)
  for (secret in secrets) {
    text <- gsub(secret, rules$replacement$identity, text, fixed = TRUE)
  }
  text
}

#' Secrets left in a text
#'
#' @return The `secrets` (and JWT-like strings) still present in `text`, for
#'   the final check of `tools/record_fixtures.R`.
#' @keywords internal
#' @noRd
scrub_leaks <- function(text, secrets = character()) {
  secrets <- unique(secrets[!is.na(secrets) & nchar(secrets) >= 3L])
  found <- secrets[vapply(secrets, function(s) grepl(s, text, fixed = TRUE), logical(1))]
  if (grepl("eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.", text, perl = TRUE)) found <- c(found, "a JWT")
  found
}
