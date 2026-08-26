test_that(".extract_metadata extracts key-value plate metadata", {
  raw_block <- data.frame(
    V1 = c("Plate Name", "User", "Created", "Comments / Notes"),
    V2 = c("20260826_1000_Sub1_P1", "Jack", "2026-08-26", "Note 1"),
    stringsAsFactors = FALSE
  )
  meta <- .extract_metadata(raw_block)
  expect_equal(nrow(meta), 1)
  expect_equal(meta[["Plate Name"]], "20260826_1000_Sub1_P1")
  expect_equal(meta[["User"]], "Jack")
  expect_equal(meta[["Created"]], "2026-08-26")
  expect_equal(meta[["Comments / Notes"]], "Note 1")
})

test_that(".split_plate_name splits plate name components correctly", {
  meta <- data.frame(`Plate Name` = "20260826_1000_Sub1_P1", check.names = FALSE, stringsAsFactors = FALSE)
  res <- .split_plate_name(meta, c("Date", "Time", "Subject", "PlateID"))
  expect_equal(res[["Date"]], "20260826")
  expect_equal(res[["Time"]], "1000")
  expect_equal(res[["Subject"]], "Sub1")
  expect_equal(res[["PlateID"]], "P1")
})

test_that(".split_plate_name warns and uses NA when component count mismatches", {
  meta <- data.frame(`Plate Name` = "Plate1", check.names = FALSE, stringsAsFactors = FALSE)
  expect_warning(
    res <- .split_plate_name(meta, c("Date", "Time")),
    "Plate Name 'Plate1' has 1 component"
  )
  expect_true(is.na(res[["Date"]]))
  expect_true(is.na(res[["Time"]]))
})

test_that(".post_process_plate handles numeric conversion and flag splitting", {
  plate <- list(
    metadata = data.frame(`Plate Name` = "P1", check.names = FALSE),
    data = data.frame(Sector = "1", Count = "15", Flags = "E M", stringsAsFactors = FALSE)
  )
  processed <- .post_process_plate(plate, num_cols = "Count", split_flags = TRUE)
  expect_type(processed$data$Count, "double")
  expect_equal(processed$data$Count, 15)
  expect_equal(processed$data$Flags_list[[1]], c("E", "M"))
})

test_that(".apply_exclusion correctly filters plates", {
  plates <- list(
    P1 = list(metadata = data.frame(`Plate Name` = "Plate_A", check.names = FALSE)),
    P2 = list(metadata = data.frame(`Plate Name` = "Plate_Exclude_B", check.names = FALSE))
  )
  res <- .apply_exclusion(plates, exclude = "_Exclude", column = "Plate Name")
  expect_named(res$included, "P1")
  expect_named(res$excluded, "P2")
})
