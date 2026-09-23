example_path_csv <- system.file(
  "extdata", "example_clariostar_export.csv",
  package = "clariostarparser"
)

test_that("errors clearly on a missing CSV file", {
  expect_error(read_clariostar_csv("does_not_exist.csv"), "File not found")
})

test_that("reads the example CSV export without error", {
  skip_if_not(nzchar(example_path_csv), "example CSV fixture not found")
  result <- read_clariostar_csv(example_path_csv)
  expect_type(result, "list")
  expect_named(
    result,
    c("metadata", "data", "matrix_data", "format_used", "parse_info")
  )
})

test_that("metadata is parsed correctly from the CSV header", {
  skip_if_not(nzchar(example_path_csv), "example CSV fixture not found")
  result <- read_clariostar_csv(example_path_csv)
  expect_equal(result$metadata[["Test name"]], "Crystal Violet 590nm")
  expect_true("Date" %in% names(result$metadata))
  expect_true("Time" %in% names(result$metadata))
  expect_true("User" %in% names(result$metadata))
})

test_that("tidy table is preferred as the primary data output", {
  skip_if_not(nzchar(example_path_csv), "example CSV fixture not found")
  result <- read_clariostar_csv(example_path_csv)
  expect_equal(result$format_used, "tidy")
  expect_true(all(c("Well", "row", "col") %in% names(result$data)))
  expect_equal(nrow(result$data), 96)
})

test_that("matrix blocks are parsed into long format with one row per well per measure", {
  skip_if_not(nzchar(example_path_csv), "example CSV fixture not found")
  result <- read_clariostar_csv(example_path_csv)
  expect_false(is.null(result$matrix_data))
  expect_true(all(c("well", "measure", "value_numeric", "value_flag") %in% names(result$matrix_data)))
  # 5 measure blocks x 96 wells in this fixture
  expect_equal(nrow(result$matrix_data), 5 * 96)
})

test_that("overflow values stay as a flag and numeric measures stay numeric", {
  skip_if_not(nzchar(example_path_csv), "example CSV fixture not found")
  result <- read_clariostar_csv(example_path_csv)
  overflow_rows <- result$matrix_data[
    !is.na(result$matrix_data$value_flag) & result$matrix_data$value_flag == "overflow",
  ]
  expect_true(nrow(overflow_rows) > 0)
  expect_true(all(is.na(overflow_rows$value_numeric)))
})

test_that("parse_info tracks source file and package version", {
  skip_if_not(nzchar(example_path_csv), "example CSV fixture not found")
  result <- read_clariostar_csv(example_path_csv)
  expect_equal(result$parse_info$source_file, basename(example_path_csv))
  expect_equal(
    result$parse_info$package_version,
    as.character(utils::packageVersion("clariostarparser"))
  )
  expect_s3_class(result$parse_info$parsed_at, "POSIXct")
})

test_that("errors clearly when no tidy table or matrix blocks are found", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  writeLines(c("Some random line", "Another line, with, commas"), tmp)
  expect_error(read_clariostar_csv(tmp), "cannot process CSV exports")
})
