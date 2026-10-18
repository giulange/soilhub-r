# Small internal helpers shared by the modules.

`%||%` <- function(x, y) if (is.null(x)) y else x

# Package-level state: the sleep function used between retries (replaced by
# tests through `local_soilhub_sleep()`) and the one-time messages already shown.
soilhub_env <- new.env(parent = emptyenv())
soilhub_env$sleep <- function(seconds) Sys.sleep(seconds)
soilhub_env$shown <- character()

http_sleep <- function(seconds) {
  if (seconds > 0) soilhub_env$sleep(seconds)
  invisible(NULL)
}

# A message of class `soilhub_message`, suppressible with
# `suppressMessages()` or a `soilhub_message` calling handler.
soilhub_message <- function(text) {
  cond <- structure(
    class = c("soilhub_message", "message", "condition"),
    list(message = paste0(text, "\n"), call = NULL)
  )
  message(cond)
}

# Emit `text` when the verbosity of `soil` is at least `level` (2.4).
soil_inform <- function(soil, level, text) {
  if (soil_verbosity(soil) >= level) soilhub_message(text)
  invisible(NULL)
}

# A message shown once per R session (keyed by `key`).
inform_once <- function(key, text) {
  if (key %in% soilhub_env$shown) return(invisible(NULL))
  soilhub_env$shown <- c(soilhub_env$shown, key)
  soilhub_message(text)
}

format_count <- function(x) {
  formatC(x, format = "d", big.mark = ",")
}

is_string <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
}
