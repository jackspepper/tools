example_path <- system.file(
  "extdata", "example_clariostar_export.xlsx",
  package = "clariostarparser"
)

test_that("errors clearly on a missing file", {
  expect_error(read_clariostar("does_not_exist.xlsx"), "File not found")
})

test_that("reads the example export without error", {
  skip_if_not(nzchar(example_path), "example fixture not found")
  result <- read_clariostar(example_path)
  expect_type(result, "list")
  expect_named(
    result,
    c("metadata", "data", "matrix_data", "format_used", "parse_info")
  )
})

test_that("metadata is parsed correctly", {
  skip_if_not(nzchar(example_path), "example fixture not found")
  result <- read_clariostar(example_path)
  expect_equal(result$metadata[["Test Name"]], "Crystal Violet 590nm")
  expect_true("Date" %in% names(result$metadata))
  expect_true("Time" %in% names(result$metadata))
})

test_that("tidy sheet is preferred as the primary data output", {
  skip_if_not(nzchar(example_path), "example fixture not found")
  result <- read_clariostar(example_path)
  expect_equal(result$format_used, "tidy")
  expect_true(all(c("Well", "row", "col") %in% names(result$data)))
  expect_equal(nrow(result$data), 96)
})

test_that("matrix sheet is parsed into long format with one row per well per measure", {
  skip_if_not(nzchar(example_path), "example fixture not found")
  result <- read_clariostar(example_path)
  expect_false(is.null(result$matrix_data))
  expect_true(all(c("well", "measure", "value_numeric", "value_flag") %in% names(result$matrix_data)))
  # 6 measure blocks x 96 wells
  expect_equal(nrow(result$matrix_data), 6 * 96)
})

test_that("pass/fail flags stay character and numeric measures stay numeric", {
  skip_if_not(nzchar(example_path), "example fixture not found")
  result <- read_clariostar(example_path)
  gb <- result$matrix_data[grepl("good", result$matrix_data$measure), ]
  expect_true(all(gb$value_flag %in% c("passed", "failed")))
  expect_true(all(is.na(gb$value_numeric)))
})

test_that("parse_info tracks source file and package version", {
  skip_if_not(nzchar(example_path), "example fixture not found")
  result <- read_clariostar(example_path)
  expect_equal(result$parse_info$source_file, basename(example_path))
  expect_equal(
    result$parse_info$package_version,
    as.character(utils::packageVersion("clariostarparser"))
  )
  expect_s3_class(result$parse_info$parsed_at, "POSIXct")
})

test_that("errors clearly when neither expected sheet is present", {
  skip_if_not(nzchar(example_path), "example fixture not found")
  # Build a throwaway workbook with an unrelated sheet name.
  tmp <- tempfile(fileext = ".xlsx")
  on.exit(unlink(tmp))
  writexl_available <- requireNamespace("writexl", quietly = TRUE)
  skip_if_not(writexl_available, "writexl not available for this test")
  writexl::write_xlsx(list("Unrelated Sheet" = data.frame(x = 1)), tmp)
  expect_error(read_clariostar(tmp), "cannot process exports missing")
})
