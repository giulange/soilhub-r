# Publish a source release: features, profiles, horizons, observations

Admits a provider dataset release into the hub as new canonical
geography and original observations: builds a provider-neutral source
bundle (one NDJSON record per feature, profile, component, horizon and
observation), uploads it with its manifest and SHA-256 checksum, has the
API validate it and promotes it as an immutable release. New geography
never goes through the publication of derived values
([`soil_publish_values()`](https://giulange.github.io/soilhub-r/reference/soil_publish_values.md)).

## Usage

``` r
soil_publish_source(
  soil = soil_session(),
  manifest,
  features,
  profiles = NULL,
  components = NULL,
  horizons = NULL,
  observations = NULL,
  idempotency_key,
  auto_promote = FALSE,
  wait = TRUE,
  keep_file = FALSE,
  timeout = 3600,
  poll = 5,
  progress = interactive()
)
```

## Arguments

- soil:

  A session; the default session when omitted. Client-side: not sent to
  the API.

- manifest:

  A named list describing the release: `provider_code`, `provider_name`,
  `dataset_code`, `dataset_name`, `release_code`, `support_type`
  (`"observed_point_profile"`, `"polygon_estimate"`,
  `"map_unit_profile_relation"`, `"non_spatial_profile"`,
  `"non_spatial_estimate"`), `default_geometry_kind` (`"POINT"`,
  `"POLYGON"`, `"MULTIPOLYGON"`, `"NONE"`), and optionally
  `provider_website_url`, `dataset_description`, `source_url`,
  `release_checksum_sha256`, `licence_text`, `citation_text`,
  `source_table_prefix` and `assets` (a data frame or list of records
  with `asset_role`, `source_url`, `checksum_sha256`, `media_type`,
  `byte_size`). Property mappings are not part of the manifest: the API
  resolves them from its own mappings of the provider. API form field
  `manifest` (JSON text).

- features:

  The features of the release, each with a `source_record_id` column: an
  `sf` object (needs the package `sf`), or the path of a spatial file –
  a GeoJSON file (`.geojson`, `.json`) is read without `sf` when in
  WGS84, any other format is read with
  [`sf::st_read()`](https://r-spatial.github.io/sf/reference/st_read.html).
  The other columns travel as attributes of the feature record
  (`source_support`, ...). For a non-spatial dataset
  (`default_geometry_kind = "NONE"`), a plain data frame. Records of the
  NDJSON bundle sent as API form field `file`.

- profiles, components, horizons, observations:

  Optional data frames (or lists of records) of the other record types,
  each with its `source_record_id` and the `source_record_id` of its
  parent (`feature_source_id`, `profile_source_id`,
  `component_source_id`, `horizon_source_id`). Horizons carry
  `top_depth_cm`, `bottom_depth_cm`, `horizon_name`; components
  `component_rank`, `proportion_percent`; observations `property_code`,
  `value`, `unit`, `status`, and optionally `method` and `quality`. `NA`
  fields are left out (an observation needs its `unit` declared).
  Records of the NDJSON bundle sent as API form field `file`.

- idempotency_key:

  Key of this ingest (at most 200 characters), stable for one bundle.
  API form field `idempotency_key`.

- auto_promote:

  Let the server validate and promote the job (`TRUE`), or validate and
  promote from the client (`FALSE`). API form field `auto_promote`.

- wait:

  Validate, promote and wait for the end of the job; `FALSE` returns
  after the upload. Client-side: not sent to the API.

- keep_file:

  Keep the NDJSON bundle written for the upload: its path is in `file`
  (a temporary file, removed when the R session ends; copy it to keep it
  longer). By default it is deleted. Client-side: not sent to the API.

- timeout, poll:

  Seconds to wait for the job, and between two polls. Client-side: not
  sent to the API.

- progress:

  Print the progress of the job. Client-side: not sent to the API.

## Value

A `soil_source_ingest` list: `job_id`, `status`, `provider_code`,
`dataset_code`, `release_code`, `auto_promote`, `record_count` (records
sent), `record_counts` (sent, by record type), `staged_counts` (staged
by the API, by record type), `published_count`, `release_id`,
`receipt_id`, `validation` (a `soil_source_validation`, or `NULL`),
`unmapped_property_codes`, `job` (the last `soil_job`),
`checksum_sha256`, `byte_size` and `file` (the bundle path with
`keep_file = TRUE`, else `NULL`).

## Details

Before any request the client checks, and lists by record in the
`errors` of a `soilhub_argument_error`:

- the manifest (required fields, codes of lowercase letters, digits and
  `_`, `support_type`, `default_geometry_kind`, checksums, assets);

- every record has a `source_record_id`, unique within its record type
  (text, or whole numbers turned into text);

- every profile, component, horizon and observation names an existing
  parent (`feature_source_id`, `profile_source_id`,
  `component_source_id`, `horizon_source_id`);

- every observation has `property_code`, a `unit` declaration and a
  `status` `"observed"` or `"computed"`;

- features have a CRS (an `sf` object without one is refused; any other
  CRS is transformed to WGS84, EPSG:4326, the only CRS of the API) and
  `POINT`, `POLYGON` or `MULTIPOLYGON` geometries, neither empty nor
  with missing coordinates.

Steps, with `wait = TRUE`:

1.  upload (`POST /source-ingests`, never repeated automatically, no
    total timeout); the API records the checksum of the file received,
    compared with the checksum of the file sent;

2.  with `auto_promote = FALSE` (default) the client validates
    (`POST /source-ingests/{job_id}/validate`): an invalid bundle is a
    `soilhub_validation_error` whose `errors` lists the rejected records
    (`record_number` in the bundle, `record_type`, `row` of its table)
    and the job fails; the counts staged by the API, per record type and
    in all, must equal the records sent, else a `soilhub_api_error`
    (code `staged_count_mismatch`) and nothing is promoted; then it
    promotes (`POST /source-ingests/{job_id}/promote`);

3.  with `auto_promote = TRUE` the server's ingest worker validates and
    promotes the job, and the client waits for it
    ([`soil_job_wait()`](https://giulange.github.io/soilhub-r/reference/soil_job_wait.md));
    a failed job is a `soilhub_job_error` with the rejected records in
    `errors`;

4.  the published counts are reconciled with the records sent (a
    difference is a `soilhub_reconciliation_warning`).

Property codes that the API cannot map to a variable of the hub are a
`soilhub_unmapped_properties_warning`: their observations are stored
with the original code and do not appear under a canonical variable
until a mapping exists (see
[`soil_variable_mappings()`](https://giulange.github.io/soilhub-r/reference/soil_variable_mappings.md)).

With `wait = FALSE` the function returns after the upload: follow the
job with
[`soil_source_validate()`](https://giulange.github.io/soilhub-r/reference/soil_source_validate.md)
and
[`soil_source_promote()`](https://giulange.github.io/soilhub-r/reference/soil_source_validate.md)
(or
[`soil_job_wait()`](https://giulange.github.io/soilhub-r/reference/soil_job_wait.md)
when `auto_promote = TRUE`). The API keeps no list of a user's jobs:
keep the `job_id`.

The same `idempotency_key` with the same file returns the job already
submitted (a completed job is returned as it is, an ended one is a
`soilhub_job_error`); the same key with another file is a
`soilhub_conflict_error` (HTTP 409): use a new key. Releases are
immutable: a `release_code` already promoted for the dataset makes the
promotion fail.

Rights: `soil:publish`. Capability: `source_ingest`.

## See also

[`soil_source_validate()`](https://giulange.github.io/soilhub-r/reference/soil_source_validate.md),
[`soil_source_promote()`](https://giulange.github.io/soilhub-r/reference/soil_source_validate.md),
[`soil_job()`](https://giulange.github.io/soilhub-r/reference/soil_job.md)

Other writing:
[`soil_product()`](https://giulange.github.io/soilhub-r/reference/soil_product.md),
[`soil_product_version()`](https://giulange.github.io/soilhub-r/reference/soil_product_version.md),
[`soil_publish_health()`](https://giulange.github.io/soilhub-r/reference/soil_publish_health.md),
[`soil_publish_values()`](https://giulange.github.io/soilhub-r/reference/soil_publish_values.md),
[`soil_register_variable()`](https://giulange.github.io/soilhub-r/reference/soil_register_variable.md),
[`soil_run_open()`](https://giulange.github.io/soilhub-r/reference/soil_run_open.md),
[`soil_source_validate()`](https://giulange.github.io/soilhub-r/reference/soil_source_validate.md)

## Examples

``` r
if (FALSE) { # \dontrun{
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
} # }
```
