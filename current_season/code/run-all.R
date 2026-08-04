## ============================================================
## run-all.R — run the whole IN-SEASON pipeline in order.
##
##   01  download this year's daily weather + merge onto the historical record
##   02  run the daily soil-water template across cells
##   03  reduce to the latest day → app/data/soil-water.csv
##   04  inspection plots → output/plots/ (quick "did it work?" check)
##
## This is what the weekly Monday job runs; the app updates Tuesday morning.
##
## Run:  Rscript code/run-all.R          (or use the master ../run.R)
## ============================================================

## set the working directory to the component root (folder with code/ input/ output/)
local({
  a <- commandArgs(FALSE); f <- grep("^--file=", a, value = TRUE)
  d <- if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1]))) else getwd()
  while (!file.exists(file.path(d, "code", "config.R")) && dirname(d) != d) d <- dirname(d)
  setwd(d)
})

steps <- c("01-get-weather.R", "02-run-apsim.R",
           "03-export-app-data.R", "04-inspect.R", "05-stations.R")
for (s in steps) {
  message("\n=================  ", s, "  =================")
  status <- system2("Rscript", file.path("code", s))
  if (status != 0) stop("Step failed: ", s, call. = FALSE)
}
message("\n[run-all] in-season pipeline complete. See output/plots/ to check it.")
