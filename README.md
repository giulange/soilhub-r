# soilhub

R client for the Global Soil Data Hub API. Read soil datasets and horizon-level
observations with personal authentication. Publishing requires additional roles.

## Install Or Update

Run this in the **RStudio / RStudio Server R console**. It discovers the latest
stable GitHub release and installs its attached R source package, without a
hard-coded version. No GitHub account or private repository access is required.

```r
dependencies <- c("httr2", "jsonlite", "curl", "openssl", "sf")
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

On Linux, dependencies such as `sf`, `curl` and `openssl` may require system
libraries: ask your RStudio Server administrator if installation fails. Accept
a personal library if the shared library is not writable. The script installs
missing dependencies; it does not automatically upgrade every existing package.

If GitHub's public API rate limit is reached, retry later or download the
`soilhub_*.tar.gz` asset manually from [Releases](https://github.com/giulange/soilhub-r/releases).
Do not install GitHub's automatic "Source code" archive: the installable package
is the explicitly attached `soilhub_*.tar.gz` file.

## Personal Login

```r
soil <- soil_connect_device()
invisible(soil_login(soil))
soil_datasets(soil)
```

Open the displayed verification link and log in with your own authorized
Keycloak account. Never share passwords, tokens or device codes. No ETL secret
is needed. Defaults use `https://soilhub.weatherprogapp.it/api/v1`; explicit
arguments override environment variables, which override public defaults.

## Student Tutorial And Help

Start with [Your First Data Table In RStudio](TUTORIAL.md): one short path from
login to a table of WoSIS observations, then saving the result. This is a local
documentation update; the next package version is not decided. The published
package is 0.1.3. The previous detailed guide is retained in the development
builder as `soilhub-reference.Rmd` rather than being required for beginners.

```r
file.edit(system.file("doc", "soilhub-student.Rmd", package = "soilhub"))
?soil_consistency
?soil_get_data
```

Copy the tutorial into your project before editing. Chunks use `eval=FALSE`:
run them interactively as needed. Knitting does not automatically install
packages, authenticate or download soil data. For current installation
instructions, use this README rather than a version-pinned tutorial example.

API documentation: [Global Soil Data Hub](https://soilhub.weatherprogapp.it/docs).
The client is MIT licensed; provider data retain their original licenses.
