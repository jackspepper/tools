# Initialise libraries
# TODO Remove unnecessary libraries that were used in analysis absent from this script
library(readxl)
library(tidyverse)
library(purrr)
library(stringr)
library(ggplot2)
library(pracma)

# Function to convert Excel-style dates
convert_excel_date <- function(x) {
  as.Date(as.numeric(x), origin = "1899-12-30")
}

# Function to process a single workbook
process_workbook <- function(file_path) {
  all_sheets <- excel_sheets(file_path)

  if ("Cage Template" %in% all_sheets) {
    selected_sheets <- all_sheets[1:(which(all_sheets == "Cage Template") - 1)]
    excluded_sheets <- all_sheets[
      (which(all_sheets == "Cage Template")):length(all_sheets)
    ]
  } else {
    warning(
      "Sheet 'Cage Template' not found in ",
      file_path,
      ". Processing all sheets."
    )
    selected_sheets <- all_sheets
    excluded_sheets <- character(0)
  }

  message("Workbook: ", file_path)
  message("All Sheets: ", paste(all_sheets, collapse = ", "))
  message("Selected Sheets: ", paste(selected_sheets, collapse = ", "))
  message("Excluded Sheets: ", paste(excluded_sheets, collapse = ", "))

  # Function to process a single sheet
  process_sheet <- function(sheet) {
    df <- read_excel(
      file_path,
      sheet = sheet,
      col_names = FALSE,
      .name_repair = "minimal"
    )

    cage_number <- df[[1, 7]]
    sex <- df[[1, 12]]
    dob <- convert_excel_date(df[[1, 16]])
    experiment_id <- df[[3, 3]]
    start_date <- convert_excel_date(df[[2, 4]])
    end_date <- convert_excel_date(df[[2, 5]])
    treatment_group <- df[[2, 9]]

    max_col <- ncol(df)
    available_subjects <- floor((max_col - 4) / 5)
    muid_cols <- 4 + (0:(available_subjects - 1)) * 5
    muids <- df[7, muid_cols + 1] %>% unlist() %>% na.omit()

    map_dfr(seq_along(muids), function(i) {
      base_col <- (4 + (i - 1) * 5) + 1
      subject_data <- df[
        9:nrow(df),
        c(1, 4, base_col, base_col + 1, base_col + 3, base_col + 4)
      ]
      colnames(subject_data) <- c(
        "Date",
        "Experimental_Day",
        "Clinical_Score",
        "Weight",
        "Checked_By",
        "Comment"
      )

      # Filter out rows where all key fields are NA
      subject_data <- subject_data %>%
        filter(
          !(is.na(Date) &
            is.na(Experimental_Day) &
            is.na(Clinical_Score) &
            is.na(Weight))
        )

      message(
        "Subject ",
        muids[i],
        " in sheet ",
        sheet,
        " has ",
        nrow(subject_data),
        " valid rows."
      )

      subject_data <- subject_data %>%
        mutate(
          Date = convert_excel_date(Date),
          Experimental_Day = as.numeric(Experimental_Day),
          Clinical_Score = as.numeric(Clinical_Score),
          Weight = round(as.numeric(Weight), 1),
          Checked_By = as.character(Checked_By),
          Comment = as.character(Comment),
          MUID = as.numeric(muids[i]),
          Cage_Number = as.numeric(cage_number),
          Sex = sex,
          DOB = dob,
          Experiment_ID = str_extract(df[[3, 3]], "\\d+"),
          Start_Date = start_date,
          End_Date = end_date,
          Treatment_Group = treatment_group,
          Workbook = basename(file_path),
          Sheet = sheet,
          Extraction_Date = Sys.time()
        )
    })
  }

  # Process all selected sheets
  data <- map_dfr(selected_sheets, process_sheet)
  row_count <- nrow(data)
  na_counts <- colSums(is.na(data))

  list(
    data = data,
    summary = list(
      workbook = basename(file_path),
      all_sheets = all_sheets,
      selected_sheets = selected_sheets,
      excluded_sheets = excluded_sheets,
      total_rows = row_count,
      na_counts = na_counts
    )
  )
}

### Example Usage
# # List all files - could also be an automated search
# file_list <- c("data/Exp#1.xlsx",
#                "data/Exp#2.xlsx",
#                "data/Exp#3.xlsx")

# # Pull results from files
# results <- map(file_list, process_workbook)

# # Combine all data
# combined_data <- bind_rows(map(results, "data"))

# # View summaries
# summaries <- map(results, "summary")
# print(summaries)
