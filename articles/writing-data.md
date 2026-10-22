# Publishing data (special rights)

``` r

library(soilhub)
```

Besides reading, the hub accepts **new data**: values you computed from
the soil data (a soil organic carbon stock, a soil-health score), and
whole new source datasets. Writing is reserved to accounts with special
rights. This guide lists every step and the right it needs. The writing
calls are **not run** in this guide (they would change the database);
the reads at the end were recorded from the Global Soil Data Hub API in
October 2026.

## Which rights do I need?

| Right | Who has it | What it allows |
|----|----|----|
| `soil:summary` | readers | catalog, counts, summaries |
| `soil:read` | readers | reading data, exports, [`soil_resolve_targets()`](https://giulange.github.io/soilhub-r/reference/soil_resolve_targets.md) |
| `soil:publish` | publishers | runs, publishing values and scores, source datasets, jobs |
| `soil:admin` | administrators | new variables, products and versions, country refresh |

The steps of this guide need:

| Step | Function | Right |
|----|----|----|
| 1\. Register a variable | [`soil_register_variable()`](https://giulange.github.io/soilhub-r/reference/soil_register_variable.md) | `soil:admin` |
| 2\. Register a product and a version | [`soil_product()`](https://giulange.github.io/soilhub-r/reference/soil_product.md), [`soil_product_version()`](https://giulange.github.io/soilhub-r/reference/soil_product_version.md) | `soil:admin` |
| 3\. Open a run | [`soil_run_open()`](https://giulange.github.io/soilhub-r/reference/soil_run_open.md) | `soil:publish` |
| 4\. Find the target ids | [`soil_resolve_targets()`](https://giulange.github.io/soilhub-r/reference/soil_resolve_targets.md) | `soil:read` |
| 5\. Publish the values | [`soil_publish_values()`](https://giulange.github.io/soilhub-r/reference/soil_publish_values.md) | `soil:publish` |
| 6\. Close the run | [`soil_run_complete()`](https://giulange.github.io/soilhub-r/reference/soil_run_open.md), [`soil_run_fail()`](https://giulange.github.io/soilhub-r/reference/soil_run_open.md) | `soil:publish` |
| 7\. Read them back | [`soil_values()`](https://giulange.github.io/soilhub-r/reference/soil_values.md), [`soil_values_summary()`](https://giulange.github.io/soilhub-r/reference/soil_values_summary.md) | `soil:read`, `soil:summary` |
| Soil-health scores | [`soil_publish_health()`](https://giulange.github.io/soilhub-r/reference/soil_publish_health.md) | `soil:publish` |
| Follow a job | [`soil_job()`](https://giulange.github.io/soilhub-r/reference/soil_job.md), [`soil_job_wait()`](https://giulange.github.io/soilhub-r/reference/soil_job_wait.md), [`soil_job_cancel()`](https://giulange.github.io/soilhub-r/reference/soil_job_cancel.md) | `soil:publish` |
| A new source dataset | [`soil_publish_source()`](https://giulange.github.io/soilhub-r/reference/soil_publish_source.md) | `soil:publish` |

Check your own rights with
[`soil_whoami()`](https://giulange.github.io/soilhub-r/reference/soil_whoami.md)
(sign in first with `soil <- soil_connect()`):

``` r

me <- soil_whoami(soil)
me$can
#> summary    read publish   admin
#>    TRUE    TRUE   FALSE   FALSE
```

If a right is missing, the function stops **before** sending anything,
with a message like this one:

    Error: `soil_register_variable()` needs the right `soil:admin`; your session has `soil:summary`, `soil:read`.

Ask the administrator of the hub for the right; nothing was written.

## The words of publishing

- A **variable** is a property you publish (for example
  `soil_health_physical_score`). It must be registered once.
- A **product** is the method that computes it (your model), and a
  **version** of the product is one fixed release of that method, with
  the checksum of its code.
- A **run** is one execution of a version: every value published belongs
  to a run, so anybody can see how it was obtained.
- A **target** is what a value describes: a feature, a profile, a
  component or a horizon of the hub, by its id.
- An **idempotency key** is a name you choose for each operation (for
  example `"run-kenya-2026-10"`). If the same operation is sent twice (a
  network problem, a script run again), the server recognises the key
  and does not do it twice.

## 1. Register the variable (`soil:admin`)

``` r

soil_register_variable(
  soil,
  variable_code = "soil_health_physical_score",
  name = "Soil health, physical score",
  domain_code = "soil",
  value_type = "numeric",
  measurement_kind_code = "derived",
  allowed_target_levels = "horizon",
  idempotency_key = "var-soil-health-physical-v1"
)
```

With `validate_only = TRUE` the server only checks the definition and
registers nothing.

## 2. Register the product and its version (`soil:admin`)

The product once:

``` r

soil_product(soil, "soil_health_fuzzy", "Soil health (fuzzy model)", "horizon")
```

Then one version per release of your method. The checksum identifies the
exact code of the model (here the file `model.R`):

``` r

checksum <- as.character(openssl::sha256(file("model.R")))
version <- soil_product_version(
  soil, "soil_health_fuzzy", "v1.0.0",
  algorithm_checksum = checksum,
  variables = data.frame(variable_code = "soil_health_physical_score",
                         target_levels = "horizon")
)
version$product_version_id
```

Keep the `product_version_id`: the next steps need it.

## 3. Open a run (`soil:publish`)

``` r

run <- soil_run_open(soil, version$product_version_id, "run-kenya-2026-10")
run$run_id
```

## 4. Find the ids of the targets (`soil:read`)

Your values describe horizons (or profiles, features) of the hub. If you
know them by their source identifiers,
[`soil_resolve_targets()`](https://giulange.github.io/soilhub-r/reference/soil_resolve_targets.md)
gives their ids in the hub:

``` r

keys <- data.frame(provider_code = "isric", dataset_code = "wosis_points",
                   release_code = "legacy_materialized", target_level = "profile",
                   source_record_id = c("101", "102"))
ids <- soil_resolve_targets(soil, keys)
ids$target_id
```

If you read the data with
[`soil_observations()`](https://giulange.github.io/soilhub-r/reference/soil_observations.md),
the ids are already in the columns `feature_id`, `profile_id`,
`component_id` and `horizon_id`.

## 5. Publish the values (`soil:publish`)

One row per value, with at least the variable, the target level, the
target id and the value:

``` r

values <- data.frame(
  variable_code = "soil_health_physical_score",
  target_level = "horizon",
  target_id = c("4fa5fbe3-8fd4-4fb1-94cf-d07963eb50f7",
                "9d55ca7b-e031-427c-8afd-dc2b3b40f8a5"),
  value = c(72.5, 64.0)
)
receipt <- soil_publish_values(soil, run$run_id, values, "values-kenya-2026-10")
receipt$published_count
```

The server first validates the values, then publishes them. Up to 10,000
rows are sent in one request; more rows are sent as a file (NDJSON) and
processed as a **job**, which the function follows until it ends.

## 6. Close the run (`soil:publish`)

When everything is published, close the run as completed; if something
went wrong, close it as failed:

``` r

soil_run_complete(soil, run$run_id)
# or: soil_run_fail(soil, run$run_id, diagnostics = list(reason = "input error"))
```

## 7. Read the values back

Published values can be read by every user with `soil:read`. These two
calls were run against the hub:
[`soil_values()`](https://giulange.github.io/soilhub-r/reference/soil_values.md)
returns the published values,

``` r

published <- soil_values(soil, max_rows = 5)
published[, c("variable_code", "target_level", "dataset_code", "value", "value_status", "run_id")]
#> # soilhub values table: 4 rows | hurl_profiles, soter_profiles
#> # no API warnings (soil_warnings), cite with soil_citations()
#>   variable_code target_level   dataset_code value value_status run_id
#> 1         ph_aq      horizon  hurl_profiles   6.5    published     20
#> 2         ph_aq      horizon soter_profiles   6.5    published      3
#> 3         ph_aq      horizon soter_profiles   6.5    published      9
#> 4         ph_aq      horizon soter_profiles   6.5    published     19
```

and
[`soil_values_summary()`](https://giulange.github.io/soilhub-r/reference/soil_values_summary.md)
counts them (right `soil:summary`):

``` r

soil_values_summary(soil)
#> # soilhub values summary: 4 values on 2 features, 1 variable(s)
#> 
#> By dataset:
#>         dataset    provider value_count feature_count variable_count
#>   hurl_profiles hurl_source           1             1              1
#>  soter_profiles       isric           3             1              1
#> 
#> By target level: horizon 4
#> 
#> By status: published 4
```

At the time of recording, four test values of pH (`ph_aq`, 6.5) were
published on horizons of two datasets, by four different runs.

## Soil-health scores (`soil:publish`)

Scores of a soil-health model are published like values, with their
category, class and the details of the fuzzy model:

``` r

scores <- data.frame(
  horizon_id = "4fa5fbe3-8fd4-4fb1-94cf-d07963eb50f7",
  release_id = 12L,
  category_code = "physical",
  score_status = "scored",
  score = 72.5,
  score_class = "good",
  source_support = "polygon_estimate"
)
soil_publish_health(soil, run$run_id, scores, "health-kenya-2026-10")
```

Everybody can read them with
[`soil_health_scores()`](https://giulange.github.io/soilhub-r/reference/soil_health_scores.md)
and count them with
[`soil_health_summary()`](https://giulange.github.io/soilhub-r/reference/soil_health_summary.md).
At the time of recording no score was published yet:

``` r

soil_health_summary(soil)
#> # soilhub soil-health summary: 0 scores on 0 horizons of 0 features
```

## Jobs (`soil:publish`)

Large publications and source datasets run as **jobs** on the server.
The functions follow them for you; to look at a job yourself:

``` r

job <- soil_job(soil, "0b4e...")         # its status now
job <- soil_job_wait(soil, "0b4e...")    # wait until it ends
soil_job_cancel(soil, "0b4e...")         # stop it
```

## A new source dataset (`soil:publish`)

[`soil_publish_source()`](https://giulange.github.io/soilhub-r/reference/soil_publish_source.md)
uploads a whole new dataset: a description (the manifest), the places
(an `sf` object with a `source_record_id` column) and optionally
profiles, components, horizons and observations. The server also needs
the capability `source_ingest`. A short example with two profiles:

``` r

library(sf)
sites <- st_as_sf(
  data.frame(source_record_id = c("P1", "P2"), x = c(500100, 501200), y = c(4520300, 4521900)),
  coords = c("x", "y"), crs = 32633
)
manifest <- list(
  provider_code = "unina", provider_name = "University of Naples Federico II",
  dataset_code = "campania_profiles", dataset_name = "Campania soil profiles",
  release_code = "2026-10", support_type = "observed_point_profile",
  default_geometry_kind = "POINT", licence_text = "CC-BY 4.0"
)
profiles <- data.frame(source_record_id = c("P1", "P2"), feature_source_id = c("P1", "P2"))
components <- data.frame(source_record_id = c("P1", "P2"), profile_source_id = c("P1", "P2"))
horizons <- data.frame(
  source_record_id = c("P1-1", "P2-1"), component_source_id = c("P1", "P2"),
  top_depth_cm = 0, bottom_depth_cm = 30
)
observations <- data.frame(
  source_record_id = c("P1-1-orgc", "P2-1-orgc"), horizon_source_id = c("P1-1", "P2-1"),
  property_code = "orgc", value = c(12.1, 8.4), unit = "g/kg", status = "observed"
)
ingest <- soil_publish_source(
  soil, manifest, sites, profiles, components, horizons, observations,
  idempotency_key = "campania-2026-10"
)
ingest$release_id
```

The package writes the bundle file, uploads it with its checksum, asks
the server to validate it and then to make it public (promote), and
waits for the end.
[`soil_source_validate()`](https://giulange.github.io/soilhub-r/reference/soil_source_validate.md)
and
[`soil_source_promote()`](https://giulange.github.io/soilhub-r/reference/soil_source_validate.md)
do the two steps separately when you want to check before publishing.

## Country statistics (`soil:admin`)

The counts per country
([`soil_countries()`](https://giulange.github.io/soilhub-r/reference/soil_countries.md))
are refreshed daily. An administrator can ask for a refresh at once:

``` r

soil_refresh_countries(soil)
```
