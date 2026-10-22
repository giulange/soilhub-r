# Installing soilhub

This page explains how to install **soilhub** in R, how to update it and
what to do if the installation does not work. You need R 4.1 or later.
The same steps work in R, RStudio and RStudio Server.

## 1. Install

Copy these two lines into the R console and press Enter:

``` r

install.packages("remotes")
remotes::install_github("giulange/soilhub-r@*release")
```

What they do:

- the first line installs `remotes`, a small helper that installs
  packages published on GitHub. You need it only once;
- the second line downloads the latest released version of soilhub and
  installs it. R also installs, by itself, the packages that soilhub
  needs (`httr2`, `jsonlite`, `curl`, `openssl`): you do not have to
  install them.

If R asks whether to update other packages, you can answer “None” (or
press Enter): soilhub does not need newer versions of the packages you
already have.

## 2. Check

``` r

library(soilhub)
packageVersion("soilhub")
```

If the second line prints a version number, soilhub is installed. From
now on, every time you start R you only need
[`library(soilhub)`](https://github.com/giulange/soilhub-r).

## 3. Maps and geometries (optional)

soilhub can return the location of the soil profiles and the shape of
the map units as `sf` objects, ready for maps. This needs the package
`sf`, which is not installed automatically because many users do not
need it:

``` r

install.packages("sf")
```

Without `sf` everything else works; geometries can still be returned as
text (`with_geometry = "text"`).

## 4. Update

To move to a newer version, run the second installation line again and
then restart R (in RStudio: *Session \> Restart R*):

``` r

remotes::install_github("giulange/soilhub-r@*release")
```

## 5. If something goes wrong

| What you see | What to do |
|----|----|
| `there is no package called 'remotes'` | Run the first line of step 1 again. |
| A message about a library that is not writable | Answer “yes” when R offers a personal library. |
| On a Linux server, errors while installing `curl`, `openssl` or `sf` | These packages need system libraries: ask the administrator of the server. |
| `API rate limit exceeded` from GitHub | Wait a few minutes and try again, or use the file below. |

Installing from a file: download `soilhub_X.Y.Z.tar.gz` from the
[releases page](https://github.com/giulange/soilhub-r/releases) and run
(with the real file name):

``` r

install.packages("~/Downloads/soilhub_0.2.0.tar.gz", repos = NULL, type = "source")
```

In this case R does not install the packages soilhub needs: install them
first with
`install.packages(c("httr2", "jsonlite", "curl", "openssl"))`.

## 6. The development version

Only to try changes that are not released yet:

``` r

remotes::install_github("giulange/soilhub-r", ref = "develop")
```

Next: [Getting
started](https://giulange.github.io/soilhub-r/articles/soilhub.md).
