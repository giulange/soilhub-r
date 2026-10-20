# soilhub

R client for the [Global Soil Data Hub](https://soilhub.weatherprogapp.it/docs)
API: discover, read and export harmonised soil profile data (WoSIS, WISE,
SOTER, SOTWIS), and, with the appropriate rights, publish derived values.
Outputs are ordinary R data frames (or `sf` objects when you ask for
geometries), with the original terms of the sources.

Documentation: <https://giulange.github.io/soilhub-r> (getting started,
articles and the reference of every function).

## Install Or Update

Run these two lines in the **RStudio / RStudio Server R console**. No GitHub
account is required.

```r
install.packages("remotes")
remotes::install_github("giulange/soilhub-r@*release")
```

The first line installs the small helper package `remotes` (only once). The second
installs the latest released version of soilhub and the packages it needs.

Requires R 4.1 or later. If the package was already loaded, **restart the R
session after updating**. Then check:

```r
library(soilhub)
packageVersion("soilhub")
```

`sf` is optional: install it (`install.packages("sf")`) only if you need
geometry. On Linux, dependencies such as `curl` and `openssl` (and `sf`) may
require system libraries: ask your RStudio Server administrator if installation
fails. Accept a personal library if the shared library is not writable.

If GitHub's rate limit is reached, retry later, or download the
`soilhub_*.tar.gz` file from [Releases](https://github.com/giulange/soilhub-r/releases)
and install it with `install.packages("path/to/soilhub_X.Y.Z.tar.gz", repos = NULL, type = "source")`.

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
