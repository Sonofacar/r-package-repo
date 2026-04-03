#!/usr/bin/env Rscript

compare_dbs <- function(new, old) {
  if (nrow(old) == 0) {
    return(new)
  }
  rows <- c()
  for (i in seq_len(nrow(new))) {
    rows <- c(
      rows,
      old[old$Package == new[i, "Package"], "Version"] |>
        (\(versions, row, name) {
          if (!(row$Version %in% versions)) new[(new$Package == name), ]
        })(new[i, ], new[i, "Package"]) |>
        rownames() |>
        as.numeric()
    )
  }

  new[rows, -c(8:13)]
}

cols <- c(
  "Package",
  "Version",
  "Title",
  "License",
  "Imports",
  "Suggests",
  "MD5sum",
  "iteration"
)

old_db <- read.table(
  "stdin",
  header = FALSE,
  col.names = cols,
  sep = "|",
  quote = "",
  fill = FALSE
)[-8]
new_db <- tools::CRAN_package_db()[c("Package",
                                     "Version",
                                     "Title",
                                     "License",
                                     "Imports",
                                     "Suggests",
                                     "MD5sum")] |>
  within({
    Title <- gsub("|", "/", License, fixed = TRUE) |>
      gsub(";", ":", x = _) |>
      gsub("\"", "", x = _, fixed = TRUE) |>
      gsub("\'", "", x = _, fixed = TRUE) |>
      gsub("\n", " ", x = _)
    License <- gsub("|", "+", License, fixed = TRUE) |>
      gsub("\'", "", x = _, fixed = TRUE) |>
      gsub("\"", "", x = _, fixed = TRUE)
    Imports <- gsub(";", ":", Imports) |>
      gsub("\'", "", x = _, fixed = TRUE) |>
      gsub("\"", "", x = _, fixed = TRUE) |>
      gsub("\n", " ", x = _)
    Suggests <- gsub(";", ":", Suggests) |>
      gsub("\'", "", x = _, fixed = TRUE) |>
      gsub("\"", "", x = _, fixed = TRUE) |>
      gsub("\n", " ", x = _)
  })
output <- compare_dbs(new_db, old_db)

for (i in seq_len(nrow(output))) {
  query <- paste0(
    "INSERT INTO package_info (",
    paste0(colnames(output), collapse = ", "),
    ") VALUES (\'",
    paste0(output[i, ], collapse = "\', \'"),
    "\');"
  ) |>
    cat()
}
q()
