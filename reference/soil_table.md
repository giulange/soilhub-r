# Tables returned by the reads

Reads such as
[`soil_observations()`](https://giulange.github.io/soilhub-r/reference/soil_observations.md)
return a `soil_table`: a `data.frame` (or an `sf` object, with `sf`'s
class kept in front of `data.frame`) whose class starts with
`"soil_table"`, with two attributes:

## Usage

``` r
# S3 method for class 'soil_table'
x[...]

# S3 method for class 'soil_table'
as.data.frame(x, row.names = NULL, optional = FALSE, ...)

# S3 method for class 'soil_table'
print(x, n = getOption("soilhub.print_rows", 10), ...)

# S3 method for class 'soil_table'
summary(object, ...)
```

## Arguments

- x, object:

  A `soil_table`. Client-side: not sent to the API.

- ...:

  As for a data frame (`[`); unused otherwise. Client-side: not sent to
  the API.

- row.names, optional:

  Unused (the row names are kept). Client-side: not sent to the API.

- n:

  Rows to print. Client-side: not sent to the API.

## Details

- `soil_metadata`, read with
  [`soil_metadata()`](https://giulange.github.io/soilhub-r/reference/soil_metadata.md):
  the request sent, the request ids of the pages, whether the read is
  complete, the API warnings, the typing of the variable columns
  ([`soil_columns()`](https://giulange.github.io/soilhub-r/reference/soil_columns.md)),
  the view and the revised rules applied
  ([`soil_revised_rules()`](https://giulange.github.io/soilhub-r/reference/soil_revised_rules.md)),
  the first-layer vocabulary
  ([`soil_first_layer()`](https://giulange.github.io/soilhub-r/reference/soil_first_layer.md)),
  the catalog rows of the datasets (for
  [`soil_citations()`](https://giulange.github.io/soilhub-r/reference/soil_citations.md));

- `soil_layout`: `"wide"`, `"long"`, `"features"`, `"values"` or
  `"health"`.

Subsetting with `[` keeps the class and the attributes;
[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) drops
them (and the `sf` class: the `geometry` column stays). Rows are in the
API's order (the stable order of the pages).

Printing shows a two-line header (counts, datasets, view and layer;
warnings and the helpers to use) and the first
`getOption("soilhub.print_rows", 10)` rows, list columns as `<list>`.
[`summary()`](https://rdrr.io/r/base/summary.html) shows the typing of
the variable columns, the rows per dataset and, with `view = "revised"`,
the rules applied with their counts.

## See also

Other results:
[`soil_columns()`](https://giulange.github.io/soilhub-r/reference/soil_columns.md),
[`soil_first_layer()`](https://giulange.github.io/soilhub-r/reference/soil_first_layer.md),
[`soil_flags()`](https://giulange.github.io/soilhub-r/reference/soil_flags.md),
[`soil_markings()`](https://giulange.github.io/soilhub-r/reference/soil_markings.md),
[`soil_metadata()`](https://giulange.github.io/soilhub-r/reference/soil_metadata.md),
[`soil_revised_rules()`](https://giulange.github.io/soilhub-r/reference/soil_revised_rules.md)
