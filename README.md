# soilhub

R client for the [Global Soil Data Hub](https://soilhub.weatherprogapp.it/docs)
API: discover, read and export harmonised soil profile data (WoSIS, WISE,
SOTER, SOTWIS), and, with the appropriate rights, publish derived values.
Outputs are ordinary R data frames (or `sf` objects when you ask for
geometries), with the original terms of the sources.

Documentation: <https://giulange.github.io/soilhub-r> (getting started,
articles and the reference of every function).

## Install Or Update

Run this in the **RStudio / RStudio Server R console**. It discovers the latest
stable GitHub release and installs its attached R source package, without a
hard-coded version. No GitHub account or private repository access is required.

```r
dependencies <- c("httr2", "jsonlite", "curl", "openssl")
missing <- dependencies[!vapply(dependencies, requireNamespace,
                                quietly = TRUE, FUN.VALUE = logical(1))]
if (length(missing)) {
  install.packages(missing, repos = "https://cloud.r-project.org")
}

release <- httr2::request(
  "https://api.github.com/repos/giulange/soilhub-r/releases/latest"
) |>
  httr2::req_user_agent("soilhub-installer") |>
  httr2::req_timeout(60) |>
  httr2::req_perform() |>
  httr2::resp_body_json(simplifyVector = TRUE)

assets <- release$assets
package <- assets[grepl("^soilhub_[0-9]+[.][0-9]+[.][0-9]+[.]tar[.]gz$",
                       assets$name), , drop = FALSE]
if (nrow(package) != 1L) {
  stop("Expected exactly one soilhub source package in the latest release")
}
message("Installing ", package$name, " from ", release$tag_name)

local({
  archive <- tempfile(fileext = ".tar.gz")
  on.exit(unlink(archive))
  download.file(package$browser_download_url, destfile = archive, mode = "wb")
  install.packages(archive, repos = NULL, type = "source")
})
```

Requires R 4.1 or later for the example's pipe syntax. If the package was already
loaded, **restart the R session after updating**. Then check:

```r
library(soilhub)
packageVersion("soilhub")
```

`sf` is optional: install it (`install.packages("sf")`) only if you need
geometry. On Linux, dependencies such as `curl` and `openssl` (and `sf`) may
require system libraries: ask your RStudio Server administrator if installation
fails. Accept a personal library if the shared library is not writable. The script installs
missing dependencies; it does not automatically upgrade every existing package.

If GitHub's public API rate limit is reached, retry later or download the
`soilhub_*.tar.gz` asset manually from [Releases](https://github.com/giulange/soilhub-r/releases).
Do not install GitHub's automatic "Source code" archive: the installable package
is the explicitly attached `soilhub_*.tar.gz` file.

## Development Install

To try the development version from the repository (requires the `remotes`
package):

```r
remotes::install_github("giulange/soilhub-r", ref = "develop")
```

## First Use

```r
library(soilhub)
soil <- soil_connect()     # opens the sign-in in your browser (a web address and a code)
soil_datasets(soil)        # the datasets of the hub
x <- soil_observations(soil, datasets = "wosis_points", country = "KEN", max_rows = 100)
```

`x` has one row per horizon and one group of columns per soil property. The
guide `vignette("soilhub", package = "soilhub")` explains each step; the
other articles cover the raw and revised views, the first layer, exports and
publishing.

Users of the 0.1.x client: see `vignette("migration-0.1", package = "soilhub")`
(the old tutorial is in [docs/legacy/TUTORIAL-0.1.md](docs/legacy/TUTORIAL-0.1.md)).

## Licences And Citation

The client is MIT licensed. The soil data keep the licences of their
providers (ISRIC and the data providers of each profile): before using or
publishing results, check them and cite the data with

```r
soil_citations(x)   # what to cite for the data in x
soil_licences(x)    # under which terms
```

Design documents of the package are in [docs/design/](docs/design/).
