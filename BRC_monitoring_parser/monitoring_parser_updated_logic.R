# Initialise libraries
library(readxl)
library(tidyverse)

# ---- A1-style cell reference helpers ------------------------------------
# Lets sheet positions be defined the way they'd be read in Excel (e.g. "G1"),
# rather than as raw row/column numbers.

# Convert a column letter (e.g. "G", "AA") to its column number
col_letter_to_num <- function(letters) {
  letters <- toupper(letters)
  chars <- strsplit(letters, "")[[1]]
  Reduce(function(acc, ch) acc * 26 + (utf8ToInt(ch) - utf8ToInt("A") + 1), chars, 0)
}

# Convert a column number to its Excel letter (e.g. 27 -> "AA")
col_num_to_letter <- function(col) {
  letters_out <- c()
  while (col > 0) {
    rem <- (col - 1) %% 26
    letters_out <- c(LETTERS[rem + 1], letters_out)
    col <- (col - 1) %/% 26
  }
  paste(letters_out, collapse = "")
}

# Parse "G1" -> list(row = 1, col = 7)
parse_cell_ref <- function(ref) {
  m <- regmatches(ref, regexec("^([A-Za-z]+)([0-9]+)$", ref))[[1]]
  if (length(m) != 3) stop("Invalid cell reference: ", ref)
  list(row = as.numeric(m[3]), col = col_letter_to_num(m[2]))
}

# Get a single cell's value from a data frame read with col_names = FALSE,
# using an A1-style reference (e.g. get_cell(df, "G1"))
get_cell <- function(df, ref) {
  pos <- parse_cell_ref(ref)
  df[[pos$row, pos$col]]
}

# Shift an A1-style column reference by n columns (e.g. shift_col("E", 2) -> "G")
shift_col <- function(ref, n) {
  col_num_to_letter(col_letter_to_num(ref) + n)
}
# ---------------------------------------------------------------------------

# Convert Excel serial date numbers to Date objects
convert_excel_date <- function(x) {
  as.Date(as.numeric(x), origin = "1899-12-30")
}

# Layout of the monitoring template, in A1-style cell references.
# Adjust these if the template's layout changes.
template_layout <- list(
  cage_number     = "G1",
  sex             = "L1",
  dob             = "P1",
  experiment_id   = "C3",
  start_date      = "D2",
  end_date        = "E2",
  treatment_group = "I2",
  id_row          = 7,   # row containing subject IDs
  first_id_col    = "F", # column of the first subject's ID
  data_start_row  = 9,   # row where daily monitoring data begins
  date_col        = "A",
  day_col         = "D",
  block_width     = 5    # columns per subject block (Score, Weight, %, Checked by, Comments)
)

# Process a single subject's data block from a sheet
extract_subject_data <- function(df, subject_id, score_col, layout) {
  weight_col <- col_letter_to_num(shift_col(col_num_to_letter(score_col), 1))
  checked_col <- col_letter_to_num(shift_col(col_num_to_letter(score_col), 3))
  comment_col <- col_letter_to_num(shift_col(col_num_to_letter(score_col), 4))
  date_col <- col_letter_to_num(layout$date_col)
  day_col <- col_letter_to_num(layout$day_col)

  subject_data <- df[
    layout$data_start_row:nrow(df),
    c(date_col, day_col, score_col, weight_col, checked_col, comment_col)
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
process_sheet <- function(file_path, sheet, layout = template_layout, verbose = FALSE) {
  df <- read_excel(
    file_path,
    sheet = sheet,
    col_names = FALSE,
    .name_repair = "minimal"
  )

  # Header metadata (fixed positions on the template)
  cage_number <- get_cell(df, layout$cage_number)
  sex <- get_cell(df, layout$sex)
  dob <- convert_excel_date(get_cell(df, layout$dob))
  experiment_id <- str_extract(get_cell(df, layout$experiment_id), "\\d+")
  start_date <- convert_excel_date(get_cell(df, layout$start_date))
  end_date <- convert_excel_date(get_cell(df, layout$end_date))
  treatment_group <- get_cell(df, layout$treatment_group)

  # Subject blocks repeat every `block_width` columns, starting at first_id_col
  max_col <- ncol(df)
  first_id_col_num <- col_letter_to_num(layout$first_id_col)
  n_subjects <- floor((max_col - first_id_col_num + 1) / layout$block_width)
  id_cols <- first_id_col_num + (0:(n_subjects - 1)) * layout$block_width
  subject_ids <- df[layout$id_row, id_cols] %>% unlist() %>% na.omit()

  if (verbose) {
    message("Sheet: ", sheet, " | Subjects found: ", paste(subject_ids, collapse = ", "))
  }

  result <- map_dfr(seq_along(subject_ids), function(i) {
    score_col <- id_cols[i]
    subject_data <- extract_subject_data(df, subject_ids[i], score_col, layout)
    if (verbose) {
      message(
        "  Subject ", subject_ids[i], " in sheet ", sheet,
        ": ", nrow(subject_data), " valid rows."
      )
    }
    subject_data
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

  result
}

# Process a full workbook, skipping the template sheet onward
process_workbook <- function(
  file_path,
  template_sheet = "Cage Template",
  layout = template_layout,
  verbose = FALSE
) {
  all_sheets <- excel_sheets(file_path)
  template_idx <- match(template_sheet, all_sheets)

  if (is.na(template_idx)) {
    warning(
      "Sheet '", template_sheet, "' not found in ", file_path,
      ". Processing all sheets."
    )
    selected_sheets <- all_sheets
  } else {
    selected_sheets <- all_sheets[seq_len(template_idx - 1)]
  }

  if (verbose) {
    message("Workbook: ", file_path)
    message("Sheets to process: ", paste(selected_sheets, collapse = ", "))
  }

  data <- map_dfr(
    selected_sheets,
    ~ process_sheet(file_path, .x, layout = layout, verbose = verbose)
  )

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
# results <- map(file_list, process_workbook, verbose = TRUE)
# combined_data <- bind_rows(map(results, "data"))
# summaries <- map(results, "summary")

# To point at a differently laid-out template, override individual cells:
# my_layout <- modifyList(template_layout, list(cage_number = "H1", id_row = 8))
# results <- map(file_list, process_workbook, layout = my_layout)
