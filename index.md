# soilhub

R client for the [Global Soil Data
Hub](https://soilhub.weatherprogapp.it/docs) API: discover, read and
export harmonised soil profile data (WoSIS, WISE, SOTER, SOTWIS), and,
with the appropriate rights, publish derived values. Outputs are
ordinary R data frames (or `sf` objects when you ask for geometries),
with the original terms of the sources.

Documentation: <https://giulange.github.io/soilhub-r> (getting started,
articles and the reference of every function).

## Install

In the R console (R 4.1 or later), once:

``` r

install.packages("remotes")
remotes::install_github("giulange/soilhub-r@*release")
```

R installs the packages soilhub needs by itself. Maps need the optional
package `sf`. Updating, checking and troubleshooting: see the
[installation
page](https://giulange.github.io/soilhub-r/articles/installation.html).

## First Use

``` r

library(soilhub)
soil <- soil_connect()     # opens the sign-in in your browser (a web address and a code)
soil_datasets(soil)        # the datasets of the hub
x <- soil_observations(soil, datasets = "wosis_points", country = "KEN", max_rows = 100)
```

`x` has one row per horizon and one group of columns per soil property.
The guide
[`vignette("soilhub", package = "soilhub")`](https://giulange.github.io/soilhub-r/articles/soilhub.md)
explains each step; the other articles cover the raw and revised views,
the first layer, exports and publishing.

The old 0.1.x tutorial is kept in
[docs/legacy/TUTORIAL-0.1.md](https://giulange.github.io/soilhub-r/docs/legacy/TUTORIAL-0.1.md).

## Licences And Citation

The client is MIT licensed. The soil data keep the licences of their
providers (ISRIC and the data providers of each profile): before using
or publishing results, check them and cite the data with

``` r

soil_citations(x)   # what to cite for the data in x
soil_licences(x)    # under which terms
```

What to cite (the data and the hub) and what the licences allow: see the
[How to
cite](https://giulange.github.io/soilhub-r/articles/how-to-cite.html)
page.

Design documents of the package are in
[docs/design/](https://giulange.github.io/soilhub-r/docs/design/).
