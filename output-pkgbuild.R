#!/usr/bin/env Rscript

# Outputs in this format:
# _cranname=
# _cranver=
# pkgname=r-${_cranname,,}
# pkgver=${_cranver//[:-]/.}
# pkgrel=1
# pkgdesc=""
# arch=(any)
# url="https://cran.r-project.org/package=${_cranname}"
# license=()
# depends=(r)
# makedepends=()
# optdepends=()
# source=("https://cran.r-project.org/src/contrib/${_cranname}_${_cranver}.tar.gz")
# # _source=("https://cran.r-project.org/src/contrib/Archive/${_cranname}/${_cranname}_${_cranver}.tar.gz")
# sha256sums=()
#
# build() {
#   R CMD INSTALL ${_cranname}_${_cranver}.tar.gz -l "${srcdir}"
# }
#
# package() {
#   install -dm0755 "${pkgdir}/usr/lib/R/library"
#
#   cp -a --no-preserve=ownership "${_cranname}" "${pkgdir}/usr/lib/R/library"
# }

cols <- c(
  "Package",
  "Version",
  "Title",
  "License",
  "Depends",
  "Imports",
  "Suggests",
  "MD5sum",
  "iteration"
)

row <- read.table(
  "stdin",
  header = FALSE,
  col.names = cols,
  sep = "|",
  quote = "",
  fill = FALSE
)

clean_depend_list <- function(s, depend_str, include_r = TRUE) {
  if (is.na(s)) {
    if (include_r) {
      paste(depend_str, "=(", sep = "") |>
        paste("\tr", ")", sep = "\n")
    } else {
      paste(depend_str, "=()\n", sep = "")
    }
  } else {
    output <- s |>
      sub(",$", "", x = _) |>
      gsub(" \\(", "", x = _) |>
      gsub("\\n", "", x = _) |>
      gsub(" ", "", x = _) |>
      gsub(",", "\n\tr-", x = _) |>
      gsub(")", "", x = _) |>
      sub("^", "\tr-", x = _)

    if (include_r) {
      paste(depend_str, "=(", sep = "") |>
        paste("\tr", output, ")", sep = "\n")
    } else {
      paste(depend_str, "=(", sep = "") |>
        paste(output, ")", sep = "\n")
    }
  }
}

c(
  paste("_cranname=", row$Package, sep = ""),
  paste("_cranname=", row$Version, sep = ""),
  "pkgname=r-${_cranname,,}",
  "pkgver=${_cranver//[:-]/.}",
  "pkgrel=1",
  paste("pkgdesc=\"", row$Title, "\"", sep = ""),
  "url=\"https://cran.r-project.org/package=${_cranname}\"",
  paste("license=(", row$License, ")", sep = ""),
  clean_depend_list(c(row$Imports, row$Depends), "depends"),
  clean_depend_list(row$Suggests, "optdepends", include_r = FALSE),
  "arch=(any)",
  "source=(\"https://cran.r-project.org/src/contrib/${_cranname}_${_cranver}.tar.gz\")",
  "# _source=(\"https://cran.r-project.org/src/contrib/Archive/${_cranname}/${_cranname}_${_cranver}.tar.gz\")",
  paste("md5sums=('", row$MD5sum, "')", sep = ""),
  "",
  "build() {\n\tmkdir build\n\tR CMD INSTALL -l build \"$_pkgname\"\n}",
  "",
  c(
    "package() {",
    "\tinstall -d \"$pkgdir/usr/lib/R/library\"",
    "\tcp -a --no-preserve=ownership \"build/$_pkgname\" \"$pkgdir/usr/lib/R/library\"",
    "",
    "\tinstall -d \"$pkgdir/usr/share/licenses/$pkgname\"",
    "\tln -s \"/usr/lib/R/library/$_pkgname/LICENSE\" \"$pkgdir/usr/share/licenses/$pkgname\"",
    "}",
    ""
  ) |>
    paste(collapse = "\n")
) |>
  paste(collapse = "\n") |>
  cat()
q()
