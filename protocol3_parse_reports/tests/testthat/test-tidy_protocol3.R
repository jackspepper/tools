test_that("tidy_protocol3 flattens plate metadata and data", {
  plates <- list(
    Plate1 = list(
      metadata = data.frame(`Plate Name` = "Plate1", User = "Jack", check.names = FALSE, stringsAsFactors = FALSE),
      data = data.frame(Sector = 1:2, Count = c(10, 20), stringsAsFactors = FALSE)
    )
  )
  tidy_df <- tidy_protocol3(plates)
  expect_equal(nrow(tidy_df), 2)
  expect_equal(tidy_df[["Plate Name"]], c("Plate1", "Plate1"))
  expect_equal(tidy_df[["User"]], c("Jack", "Jack"))
  expect_equal(tidy_df[["Sector"]], c(1, 2))
  expect_equal(tidy_df[["Count"]], c(10, 20))
})
