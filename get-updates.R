#!/usr/bin/env Rscript

cols <- c(
  "Package",
  "Version",
  "Title",
  "License",
  "Depends",
  "Imports",
  "Suggests",
  "MD5sum"
)

packages <- readLines()
tools::CRAN_package_db()[cols] |>
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
    Depends <- gsub(";", ":", Depends) |>
      gsub("\'", "", x = _, fixed = TRUE) |>
      gsub("\"", "", x = _, fixed = TRUE) |>
      gsub("\n", " ", x = _)
    Suggests <- gsub(";", ":", Suggests) |>
      gsub("\'", "", x = _, fixed = TRUE) |>
      gsub("\"", "", x = _, fixed = TRUE) |>
      gsub("\n", " ", x = _)
  }) |>
  (\(df) {
     deps <- c()
     for (pkg in packages) {
       deps <- c(
         strsplit(df[df$Package == pkg, "Depends"], ", ") |>
           sub(" \\(.*\\)", "", x = _) |>
           (\(.) .[[1]])(),
         strsplit(df[df$Package == pkg, "Imports"], ", ") |>
           sub(" \\(.*\\)", "", x = _) |>
           (\(.) .[[1]])(),
         deps
       )
     }
     print(deps)
     df[df$Package %in% c(packages, deps), ]
  })() |>
  (\(df)
    for (i in seq_len(nrow(df))) {
      query <- paste0(
        "INSERT INTO package_info (",
        paste0(cols, collapse = ", "),
        ") VALUES (\'",
        paste0(df[i, ], collapse = "\', \'"),
        "\');\n"
      ) |>
        cat()
    })()
