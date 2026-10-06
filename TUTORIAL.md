# Soil Hub: Your First Data Table In RStudio

**Goal:** log in and open a table of up to 100 soil observations from profile
points in Spain. No database writes, maps or modelling are required.

Run each block in the **RStudio Console**, in order. If a block fails, stop
there and send the error message to Giuliano, without passwords or tokens.

## 1. Install Or Update Once

Version 0.1.4 includes the session-renewal fix. Its download link works after
the maintainer publishes the release. Do not repeat installation at every login.

```r
download.file(
  "https://github.com/giulange/soilhub-r/releases/download/v0.1.4/soilhub_0.1.4.tar.gz",
  "soilhub_0.1.4.tar.gz",
  mode = "wb"
)
install.packages("soilhub_0.1.4.tar.gz", repos = NULL, type = "source")
```

Dependencies are assumed installed on your RStudio Server. If R reports a missing
package, ask Giuliano; do not install anything merely because this guide mentions it.
After an update select **Session > Restart R**. Then continue below.

## 2. Log In

```r
library(soilhub)
packageVersion("soilhub")
soil <- soil_connect_device()
invisible(soil_login(soil))
```

Open the link printed by R and enter the displayed code if requested. Sign in
with **your own Keycloak account**, not another person's existing browser session.
Return to RStudio once authorization succeeds. Never share the displayed code.

## 3. Check Your Access

```r
soil_datasets(soil)
```

You should see the available datasets. We will use `wosis_points`, not polygons.

## 4. Check What Is Available In Spain

```r
inventory <- soil_consistency(
  soil,
  datasets = "wosis_points",
  geometry = "point",
  country = "ESP"
)
inventory$totals
```

These are counts, not the downloaded measurements. `ESP` means Spain.

## 5. Read And Open A Small Table

```r
observations <- soil_get_observations(
  soil,
  datasets = "wosis_points",
  geometry = "point",
  country = "ESP",
  variables = "ALL",
  layer = "all",
  include_geometry = FALSE,
  max_records = 100
)
View(observations)
```

**Result:** a table opens in RStudio. Each row is one property observation for
a soil horizon, not one whole profile. Several rows can belong to the same
horizon. The limit is 100 observations, so a profile may be incomplete.

For this first exercise we deliberately request values without coordinates;
the separate geometry issue is still under investigation. This is not yet a
wide table with one column per soil variable, nor a complete model input dataset.

If the table is empty, report the counts from step 4. Do not change to a polygon
dataset to make the example return something.

## 6. Save Your Table

```r
saveRDS(observations, "soil_spain_sample.rds")
getwd()
```

The file is saved in the folder printed by `getwd()`, visible in RStudio's Files
pane. Open it in another session with:

```r
observations <- readRDS("soil_spain_sample.rds")
View(observations)
```

Save the observations, **not** the `soil` connection or your whole workspace:
the connection contains authentication tokens. Decline saving `.RData` on exit.

## Check Session Renewal Together

Keep the same R session and the same `soil` object. After more than six minutes:

```r
soil_datasets(soil)
```

This should work without another browser login. Repeat during your normal work;
a six-minute success does not by itself prove several hours of continuity.
Do not recreate `soil` between calls: a new connection has no cached session.

If R says the session cannot be renewed, sign in again explicitly:

```r
invisible(soil_login(soil, force = TRUE))
```

Tell Giuliano which step succeeded or failed and the package version. Never send
tokens or your connection object. More detailed material remains available in
the companion `soilhub-reference.Rmd`; it is not required for this first exercise.
