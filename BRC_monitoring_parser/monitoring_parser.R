# Initialise libraries
library(readxl)
library(tidyverse)

# Convert Excel serial date numbers to Date objects
convert_excel_date <- function(x) {
  as.Date(as.numeric(x), origin = "1899-12-30")
}

# Process a single subject's data block from a sheet
extract_subject_data <- function(df, subject_id, base_col) {
  subject_data <- df[
    9:nrow(df),
    c(1, 4, base_col, base_col + 1, base_col + 3, base_col + 4)
  ]
  colnames(subject_data) <- c(
    "Date",
    "Experimental_Day",
    "Score",
    "Weight",
    "Checked_By",
    "Comment"
  )

  subject_data %>%
    filter(
      !(is.na(Date) & is.na(Experimental_Day) & is.na(Score) & is.na(Weight))
    ) %>%
    mutate(
      Date = convert_excel_date(Date),
      Experimental_Day = as.numeric(Experimental_Day),
      Score = as.numeric(Score),
      Weight = round(as.numeric(Weight), 1),
      Checked_By = as.character(Checked_By),
      Comment = as.character(Comment),
      Subject_ID = subject_id
    )
}

# Process a single sheet (one cage/group)
process_sheet <- function(file_path, sheet) {
  df <- read_excel(
    file_path,
    sheet = sheet,
    col_names = FALSE,
    .name_repair = "minimal"
  )

  # Header metadata (fixed positions on the template)
  cage_number <- df[[1, 7]]
  sex <- df[[1, 12]]
  dob <- convert_excel_date(df[[1, 16]])
  experiment_id <- str_extract(df[[3, 3]], "\\d+")
  start_date <- convert_excel_date(df[[2, 4]])
  end_date <- convert_excel_date(df[[2, 5]])
  treatment_group <- df[[2, 9]]

  # Subject blocks are repeated every 5 columns from column 5
  max_col <- ncol(df)
  n_subjects <- floor((max_col - 4) / 5)
  id_cols <- 4 + (0:(n_subjects - 1)) * 5 + 1
  subject_ids <- df[7, id_cols] %>% unlist() %>% na.omit()

  map_dfr(seq_along(subject_ids), function(i) {
    base_col <- (4 + (i - 1) * 5) + 1
    extract_subject_data(df, subject_ids[i], base_col)
  }) %>%
    mutate(
      Cage_Number = as.numeric(cage_number),
      Sex = sex,
      DOB = dob,
      Experiment_ID = experiment_id,
      Start_Date = start_date,
      End_Date = end_date,
      Treatment_Group = treatment_group,
      Workbook = basename(file_path),
      Sheet = sheet,
      Extraction_Date = Sys.time()
    )
}

# Process a full workbook, skipping the template sheet onward
process_workbook <- function(file_path, template_sheet = "Cage Template") {
  all_sheets <- excel_sheets(file_path)
  template_idx <- match(template_sheet, all_sheets)

  if (is.na(template_idx)) {
    warning(
      "Sheet '",
      template_sheet,
      "' not found in ",
      file_path,
      ". Processing all sheets."
    )
    selected_sheets <- all_sheets
  } else {
    selected_sheets <- all_sheets[seq_len(template_idx - 1)]
  }

  data <- map_dfr(selected_sheets, ~ process_sheet(file_path, .x))

  list(
    data = data,
    summary = list(
      workbook = basename(file_path),
      sheets_processed = selected_sheets,
      total_rows = nrow(data),
      na_counts = colSums(is.na(data))
    )
  )
}

### Example Usage
# file_list <- list.files("data", pattern = "\\.xlsx$", full.names = TRUE)
# results <- map(file_list, process_workbook)
# combined_data <- bind_rows(map(results, "data"))
# summaries <- map(results, "summary")
