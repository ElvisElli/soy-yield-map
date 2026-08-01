#!/usr/bin/env Rscript
## ============================================================
## make-apsim.R — build a ready-to-run APSIM soybean file for ONE location.
##
## Downloaded from the "Get APSIM template" tab of the Soybean Yield-Gap app for
## visitors on the static site (which can't generate the file in-browser). Run
## it on your own computer, where the `apsimx` package and internet access do
## the SSURGO + NASA-POWER downloads.
##
##   1. Install APSIM Next Gen and the R package once:
##        install.packages("apsimx")
##   2. Run:
##        Rscript make-apsim.R --lat 34.75 --lon -91.5
##        Rscript make-apsim.R --lat 40.1 --lon -88.2 --cultivar PurcellMG5 \
##                             --sow 10-May --start 1990 --out my-field.zip
##
## Output: a .zip with <name>.apsimx (SSURGO soil embedded, your cultivar / sow
## date, weather clock to ~today) + weather.met (NASA POWER). Unzip, then open
## the .apsimx in APSIM NG or run:  Models <name>.apsimx
##
## The generation logic lives in one place — app/R/apsim-generate.R. This script
## uses the local copy if present, otherwise fetches it from the repo.
## ============================================================

## ── tiny --flag value parser ─────────────────────────────────────────────
args <- commandArgs(trailingOnly = TRUE)
getarg <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i == length(args)) default else args[i + 1]
}
if ("--help" %in% args || "-h" %in% args) {
  cat("Usage: Rscript make-apsim.R --lat <lat> --lon <lon>",
      "[--cultivar PurcellMG4|PurcellMG5|PurcellMG6] [--sow dd-mmm]",
      "[--start <year>] [--out <file.zip>]\n")
  quit(status = 0)
}

lat <- as.numeric(getarg("--lat"))
lon <- as.numeric(getarg("--lon"))
if (is.na(lat) || is.na(lon))
  stop("Please pass --lat and --lon, e.g. --lat 34.75 --lon -91.5", call. = FALSE)

cultivar <- getarg("--cultivar", "PurcellMG4")
sow      <- getarg("--sow",      "22-May")
start    <- as.integer(getarg("--start", "1985"))
out      <- getarg("--out", sprintf("apsim-soybean_%.4f_%.4f.zip", lat, lon))

## ── load the shared generator (local copy, else fetch from the repo) ──────
gen_local <- c("R/apsim-generate.R", "app/R/apsim-generate.R",
               "../app/R/apsim-generate.R")
gen <- gen_local[file.exists(gen_local)]
if (length(gen)) {
  source(gen[1])
} else {
  tmp <- tempfile(fileext = ".R")
  utils::download.file(paste0(
    "https://raw.githubusercontent.com/ElvisElli/soy-yield-map/main/",
    "app/R/apsim-generate.R"), tmp, quiet = TRUE)
  source(tmp)
}

cat(sprintf("Building APSIM file for  lat %.4f, lon %.4f\n", lat, lon))
cat(sprintf("  cultivar %s | sow %s | weather %d–now\n", cultivar, sow, start))

generate_apsimx_zip(
  lat = lat, lon = lon, zip_file = out,
  name = "soybean", cultivar = cultivar, sow_date = sow, start_year = start,
  progress = function(p, m) cat(sprintf("  [%3.0f%%] %s\n", 100 * p, m)))

cat("Wrote ", normalizePath(out), "\n", sep = "")
