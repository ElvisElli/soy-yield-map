## ============================================================
## run-all.R — run the whole HISTORICAL pipeline in order.
##
##   01  download+condition weather (1985–2025) + soil for every cell
##   02  run APSIM across cells × scenarios, collect yearly yield
##   03  aggregate results → app/data/yield-surface.csv (+ boundaries)
##   04  inspection plots → output/plots/ (quick "did it work?" check)
##
## Each step is resumable. Edit code/config.R to change scenarios, grid, years.
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

steps <- c("01-get-weather-soil.R", "02-run-apsim.R",
           "03-export-app-data.R", "04-inspect.R")
for (s in steps) {
  message("\n=================  ", s, "  =================")
  status <- system2("Rscript", file.path("code", s))
  if (status != 0) stop("Step failed: ", s, call. = FALSE)
}
message("\n[run-all] historical pipeline complete. See output/plots/ to check it.")
