test_that("clean_col_names standardizes messy headers cleanly", {
  messy_df <- data.frame(`Well Group` = 1, `End..RFU!!` = 10, check.names = FALSE)
  cleaned <- qpcrpipeline:::clean_col_names(messy_df)
  expect_named(cleaned, c("well_group", "end_rfu"))
})

test_that("file_stem isolates filenames correctly", {
  expect_equal(qpcrpipeline:::file_stem("C:/data/plate_01.csv"), "plate_01")
})

test_that("list_files_depth honors requested folder depth", {
  tmp <- file.path(tempdir(), "list_files_depth_test")
  unlink(tmp, recursive = TRUE, force = TRUE)
  dir.create(tmp, recursive = TRUE)
  writeLines("root", file.path(tmp, "root.csv"))
  dir.create(file.path(tmp, "sub"))
  writeLines("sub", file.path(tmp, "sub", "sub.csv"))
  dir.create(file.path(tmp, "sub", "deep"), recursive = TRUE)
  writeLines("deep", file.path(tmp, "sub", "deep", "deep.csv"))

  expect_equal(
    sort(qpcrpipeline:::list_files_depth(tmp, pattern = "\\.csv$", depth = 0)),
    sort(file.path(tmp, "root.csv"))
  )
  expect_true(all(grepl("root.csv|sub.csv$", qpcrpipeline:::list_files_depth(tmp, pattern = "\\.csv$", depth = 1))))
  expect_false(any(grepl("deep.csv$", qpcrpipeline:::list_files_depth(tmp, pattern = "\\.csv$", depth = 1))))
})

test_that("build_file_tree renders nested paths and header correctly", {
  tmp <- file.path(tempdir(), "build_file_tree_test")
  unlink(tmp, recursive = TRUE, force = TRUE)
  dir.create(file.path(tmp, "sub"), recursive = TRUE)
  file1 <- file.path(tmp, "root.csv")
  file2 <- file.path(tmp, "sub", "sub.csv")
  writeLines("x", file1)
  writeLines("y", file2)

  tree_lines <- qpcrpipeline:::build_file_tree(c(file1, file2), tmp, depth_requested = 1)
  expect_true(any(grepl("depth requested: 1", tree_lines)))
  expect_true(any(grepl("sub/", tree_lines)))
  expect_true(any(grepl("root.csv", tree_lines)))
})

test_that("emit_file_tree writes output file and accepts valid modes", {
  tree_lines <- c("header", "  file.txt")
  out_file <- tempfile(fileext = ".txt")

  expect_error(qpcrpipeline:::emit_file_tree(tree_lines, output_mode = "invalid", tree_path = out_file),
               regexp = "tree_output must be one of")

  capture.output(qpcrpipeline:::emit_file_tree(tree_lines, output_mode = "file", tree_path = out_file))
  expect_true(file.exists(out_file))
  txt <- readLines(out_file)
  expect_true(grepl("Generated:", txt[1]))
  expect_true(any(grepl("header", txt)))
})

test_that("write_csv_retry successfully writes a CSV file", {
  tmp <- tempfile(fileext = ".csv")
  df <- data.frame(a = 1:2, b = c("x", "y"))

  expect_silent(qpcrpipeline:::write_csv_retry(df, file = tmp, max_tries = 2, wait_secs = 0.1))
  expect_true(file.exists(tmp))
  read_back <- readr::read_csv(tmp, show_col_types = FALSE)
  expect_equal(read_back$a, df$a)
  expect_equal(read_back$b, df$b)
})