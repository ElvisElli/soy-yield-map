## ============================================================
## run-all.R — run the whole in-season pipeline in order.
##
##   01  download this season's daily weather (soil reused from ../simulation)
##   02  run the daily soil-water template across cells
##   03  reduce to the latest day → ../app/data/soil-water.csv
##
## This is what the weekly Monday job runs; the app updates Tuesday morning.
##
## Run:  Rscript run-all.R      (from current_season/)
## ============================================================

setwd_here <- function() {
  a <- commandArgs(FALSE); f <- grep("^--file=", a, value = TRUE)
  if (length(f)) setwd(dirname(normalizePath(sub("^--file=", "", f[1]))))
}
setwd_here()

for (s in c("01-get-weather.R", "02-run-apsim.R", "03-export-app-data.R")) {
  message("\n=================  ", s, "  =================")
  status <- system2("Rscript", s)
  if (status != 0) stop("Step failed: ", s)
}
message("\n[run-all] in-season pipeline complete.")
