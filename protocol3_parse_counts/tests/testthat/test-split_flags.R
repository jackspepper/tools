test_that("split_flags correctly parses space-separated flag strings", {
  res <- split_flags(c("E M", "M", NA, "", "  "))
  expect_equal(res, list(c("E", "M"), "M", character(0), character(0), character(0)))
})
