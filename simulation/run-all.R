## ============================================================
## run-all.R — run the whole simulation pipeline in order.
##
##   01  download weather (NASA POWER) + soil (SSURGO) for every cell
##   02  run APSIM across cells × scenarios, collect yearly yield
##   03  aggregate results → app/data/yield-surface.csv (+ boundaries)
##
## Each step is resumable, so re-running after an interruption continues where
## it left off. Edit config.R to change scenarios, the grid, or the years.
##
## Run:  Rscript run-all.R      (from simulation/)
## ============================================================

setwd_here <- function() {
  a <- commandArgs(FALSE); f <- grep("^--file=", a, value = TRUE)
  if (length(f)) setwd(dirname(normalizePath(sub("^--file=", "", f[1]))))
}
setwd_here()

steps <- c("01-get-weather-soil.R", "02-run-apsim.R", "03-export-app-data.R")
for (s in steps) {
  message("\n=================  ", s, "  =================")
  system2("Rscript", s)
}
message("\n[run-all] pipeline complete.")
