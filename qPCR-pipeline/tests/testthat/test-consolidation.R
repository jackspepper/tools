test_that("build_count_pivot cleanly cross-tabulates plates and targets", {
  # Mock consolidated memory dataset
  mock_data <- tibble::tibble(
    `Plate#` = c(1, 1, 1, 2, 2),
    .sheet_target = c("fucP", "fucP", "lytA", "lytA", "lytA")
  )
  
  pivot_res <- qpcrpipeline:::build_count_pivot(mock_data)
  
  expect_s3_class(pivot_res, "tbl_df")
  expect_true("Plate#" %in% names(pivot_res))
  # Ensure zero-fill replaces missing plate combinations
  expect_equal(pivot_res$fucP, c(2L, 0L)) 
  expect_equal(pivot_res$lytA, c(1L, 2L))
})

test_that("build_count_pivot handles empty inputs safely", {
  expect_null(qpcrpipeline:::build_count_pivot(NULL))
  expect_null(qpcrpipeline:::build_count_pivot(tibble::tibble()))
})

test_that("write_csv_retry throws clear errors when max attempts are reached", {
  dummy_df <- data.frame(a = 1, b = 2)
  # Target an impossible file directory configuration
  impossible_path <- "/non_existent_folder_xyz123/output.csv"
  
  expect_error(
    qpcrpipeline:::write_csv_retry(dummy_df, file = impossible_path, max_tries = 2, wait_secs = 0.1),
    regexp = "failed after 2 attempt\\(s\\)"
  )
})
test_that("build_decision_summary returns the most recent log and pivots counts", {
  tmp <- file.path(tempdir(), "decision_summary_test")
  unlink(tmp, recursive = TRUE, force = TRUE)
  dir.create(tmp, recursive = TRUE)

  dec_old <- tibble::tibble(
    input_file = c("plate1.csv", "plate2.csv"),
    run_id = c("20240101_000000_plate1", "20240101_000000_plate2"),
    rule_id = c("ruleA", "ruleB")
  )
  dec_new <- tibble::tibble(
    input_file = c("plate1.csv", "plate1.csv", "plate3.csv"),
    run_id = c("20240201_000000_plate1", "20240201_000000_plate1", "20240201_000000_plate3"),
    rule_id = c("ruleA", "ruleA", "ruleC")
  )

  readr::write_csv(dec_old, file.path(tmp, "pcr_decisions_202401.csv"))
  readr::write_csv(dec_new, file.path(tmp, "pcr_decisions_202402.csv"))
  Sys.setFileTime(file.path(tmp, "pcr_decisions_202401.csv"), as.POSIXct("2024-01-01 00:00:00"))
  Sys.setFileTime(file.path(tmp, "pcr_decisions_202402.csv"), as.POSIXct("2024-02-01 00:00:00"))

  summary <- qpcrpipeline:::build_decision_summary(tmp)
  expect_true("plate" %in% names(summary))
  expect_true("ruleA" %in% names(summary))
  expect_equal(summary$plate, c("plate1", "plate3"))
  expect_equal(summary$ruleA, c(2L, 0L))
  expect_equal(summary$ruleC, c(0L, 1L))
})

test_that("build_standards_summary returns latest run per plate with selected columns", {
  tmp <- file.path(tempdir(), "standards_summary_test")
  unlink(tmp, recursive = TRUE, force = TRUE)
  dir.create(tmp, recursive = TRUE)

  std_old <- tibble::tibble(
    input_file = c("plate1.csv"),
    run_id = c("20240101_000000_plate1"),
    action = c("pass"),
    missing_standards = c(""),
    lod_override = c(""),
    notes = c("old")
  )
  std_new <- tibble::tibble(
    input_file = c("plate1.csv", "plate2.csv"),
    run_id = c("20240201_000000_plate1", "20240201_000000_plate2"),
    action = c("forced", "pass"),
    missing_standards = c("Std-001", ""),
    lod_override = c("LOD_Hi=10", ""),
    notes = c("new", "fresh")
  )

  readr::write_csv(std_old, file.path(tmp, "pcr_standards_202401.csv"))
  readr::write_csv(std_new, file.path(tmp, "pcr_standards_202402.csv"))
  Sys.setFileTime(file.path(tmp, "pcr_standards_202401.csv"), as.POSIXct("2024-01-01 00:00:00"))
  Sys.setFileTime(file.path(tmp, "pcr_standards_202402.csv"), as.POSIXct("2024-02-01 00:00:00"))

  summary <- qpcrpipeline:::build_standards_summary(tmp)
  expect_equal(summary$plate, c("plate1", "plate2"))
  expect_equal(summary$action, c("forced", "pass"))
  expect_equal(summary$missing_standards, c("Std-001", ""))
  expect_equal(summary$notes, c("new", "fresh"))
})

test_that("build_count_pivot falls back to Target and handles NA plates", {
  mock_data <- tibble::tibble(
    `Plate#` = c(1, NA, 2, 1),
    Target = c("A", "B", "A", "A")
  )

  pivot_res <- qpcrpipeline:::build_count_pivot(mock_data)
  expect_equal(pivot_res$`Plate#`, c("1", "2", "Unknown"))
  expect_equal(pivot_res$A, c(2L, 1L, 0L))
  expect_equal(pivot_res$B, c(0L, 0L, 1L))
})

test_that("add_summary_sheet creates run_summary as first sheet and handles all-null tables", {
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "data")

  wb <- qpcrpipeline:::add_summary_sheet(wb, NULL, NULL, NULL, NULL,
                          font_name = "Calibri", font_size = 11L,
                          col_width_min = 8)

  expect_equal(wb$sheetOrder, c(2L, 1L))
  expect_equal(length(wb$sheetOrder), 2)
})

test_that("add_summary_sheet writes non-null summaries into the workbook", {
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "data")

  decision_tbl <- tibble::tibble(plate = "plate1", ruleA = 1L)
  standards_tbl <- tibble::tibble(plate = "plate1", action = "pass", missing_standards = "")
  all_counts <- tibble::tibble(`Plate#` = "1", targetA = 2L)
  review_counts <- tibble::tibble(`Plate#` = "1", targetA = 1L)

  wb <- qpcrpipeline:::add_summary_sheet(
    wb, decision_tbl, standards_tbl, all_counts, review_counts,
    font_name = "Calibri", font_size = 11L, col_width_min = 8
  )

  expect_equal(wb$sheet_names, c("data", "run_summary"))
  expect_equal(length(wb$sheet_names), 2)
})

test_that("save_workbook_retry writes a workbook successfully", {
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "sheet1")
  openxlsx::writeData(wb, "sheet1", tibble::tibble(x = 1))

  out_file <- tempfile(fileext = ".xlsx")
  expect_silent(qpcrpipeline:::save_workbook_retry(wb, out_file, overwrite = TRUE, max_tries = 2, wait_secs = 0))
  expect_true(file.exists(out_file))
  expect_equal(openxlsx::getSheetNames(out_file), "sheet1")
})