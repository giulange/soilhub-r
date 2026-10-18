test_that("the package loads with the expected name", {
  expect_identical(utils::packageName(), "soilhub")
})

test_that("the fake API helper serves /health", {
  server <- fake_api()
  response <- curl::curl_fetch_memory(paste0(server$url(), "/health"))
  expect_identical(response$status_code, 200L)
  body <- jsonlite::fromJSON(rawToChar(response$content))
  expect_identical(body$status, "ok")
})
