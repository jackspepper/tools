test_that("include_version appends Parser Version to metadata and attributes", {
  raw_block <- data.frame(
    V1 = c("Plate Name", "User", "Created", "Comments / Notes"),
    V2 = c("Plate1", "Jack", "2026-08-26", "Note"),
    stringsAsFactors = FALSE
  )
  meta_ver <- .extract_metadata(raw_block, include_version = TRUE)
  expect_equal(meta_ver[["Parser Version"]], "0.1.0.9000")

  meta_nover <- .extract_metadata(raw_block, include_version = FALSE)
  expect_false("Parser Version" %in% names(meta_nover))
})

test_that("tidy_protocol3 propagates audit attributes and handles wrapper list", {
  plates <- list(
    Plate1 = list(
      metadata = data.frame(`Plate Name` = "Plate1", `Parser Version` = "0.1.0.9000", check.names = FALSE, stringsAsFactors = FALSE),
      data = data.frame(Sector = 1L, Count = 10, stringsAsFactors = FALSE)
    )
  )
  attr(plates, "parser_version") <- "0.1.0.9000"
  attr(plates, "parsed_at") <- Sys.time()

  tidy_df <- tidy_protocol3(plates)
  expect_equal(tidy_df[["Parser Version"]], "0.1.0.9000")
  expect_equal(attr(tidy_df, "parser_version"), "0.1.0.9000")
  expect_s3_class(attr(tidy_df, "parsed_at"), "POSIXct")
})
