test_that("std_label_to_num extracts integers across multiple formatting styles", {
  expect_equal(qpcrpipeline:::std_label_to_num("Std-001"), 1L)
  expect_equal(qpcrpipeline:::std_label_to_num("Std-01"), 1L)
  expect_equal(qpcrpipeline:::std_label_to_num("std-2"), 2L)
  expect_equal(qpcrpipeline:::std_label_to_num("STD-0005"), 5L)
  expect_true(is.na(qpcrpipeline:::std_label_to_num("Unknown-Sample")))
})

test_that("normalize_std_label outputs structured canonical 3-digit strings", {
  expect_equal(qpcrpipeline:::normalize_std_label("Std-1"), "Std-001")
  expect_equal(qpcrpipeline:::normalize_std_label("std-02"), "Std-002")
  expect_equal(qpcrpipeline:::normalize_std_label("Std-45"), "Std-045")
})

test_that("classify_missing_standards catches missing curve endpoints", {
  res <- qpcrpipeline:::classify_missing_standards(missing = c("Std-001"), n_expected = 6L)
  expect_equal(res$type, "end_missing")
  expect_true(res$hi_endpoint_missing)
})

test_that("check_plate_standards identifies missing and non-canonical labels", {
  tmp <- tempfile(fileext = ".csv")
  writeLines(c(
    "Well,Content,Target",
    "A1,Std-001,TargetA",
    "A2,Std-003,TargetA",
    "A3,Std-005,TargetB"
  ), tmp)

  res <- qpcrpipeline:::check_plate_standards(tmp, n_expected = 5L)
  expect_false(res$passed)
  expect_equal(res$missing, c("Std-002", "Std-004"))
  expect_equal(res$label_style, "standard")
  expect_true(is.null(res$label_warning))
  expect_equal(res$targets, c("targeta", "targetb"))
})

test_that("check_plate_standards reports file read errors cleanly", {
  res <- qpcrpipeline:::check_plate_standards("does_not_exist.csv", n_expected = 3L)
  expect_false(res$passed)
  expect_true(grepl("does not exist", res$error, ignore.case = TRUE))
})

test_that("classify_missing_standards splits endpoints and middle groups accurately", {
  # Scenario 1: Strict Endpoint failure (Missing standard number 1 out of 6)
  res_end <- qpcrpipeline:::classify_missing_standards(missing = c("Std-001"), n_expected = 6L)
  expect_equal(res_end$type, "end_missing")
  expect_true(res_end$hi_endpoint_missing)
  expect_false(res_end$lo_endpoint_missing)
  expect_true(res_end$missing_hi_half)
  
  # Scenario 2: 1-2 interior standards missing (Middle failure)
  res_mid_minor <- qpcrpipeline:::classify_missing_standards(missing = c("Std-003"), n_expected = 6L)
  expect_equal(res_mid_minor$type, "middle_1_2")
  expect_equal(res_mid_minor$n_missing_middle, 1L)
  expect_false(res_mid_minor$hi_endpoint_missing)
  
  # Scenario 3: 3+ middle standards missing (Severe curve failure)
  res_mid_major <- qpcrpipeline:::classify_missing_standards(missing = c("Std-002", "Std-003", "Std-004"), n_expected = 6L)
  expect_equal(res_mid_major$type, "middle_3plus")
  
  # Scenario 4: Edge Case handling boundary where n_expected < 2
  expect_warning(res_edge <- qpcrpipeline:::classify_missing_standards(missing = c("Std-001"), n_expected = 1L))
  expect_equal(res_edge$type, "end_missing")
  expect_true(res_edge$needs_both_lods)
})

test_that("validate_target_lod rejects malformed LOD lists", {
  expect_error(qpcrpipeline:::validate_target_lod(list(LOD_Hi = "bad", LOD_Lo = list())),
               regexp = "LOD_Lo")
  expect_error(qpcrpipeline:::validate_target_lod(list(LOD_Hi = list(), LOD_Lo = list())),
               regexp = "missing or empty")
})