#' @keywords internal
"_PACKAGE"

# The HTTP, JSON, TLS and utility packages declared in Imports are used by the
# modules added in later work packages; they are imported here so that the
# skeleton passes R CMD check without an "unused Imports" NOTE.
#' @importFrom curl curl_version
#' @importFrom httr2 request
#' @importFrom jsonlite fromJSON
#' @importFrom openssl sha256
#' @importFrom stats setNames
#' @importFrom utils head
NULL
