## ============================================================
## 01-get-weather-soil.R
## Download weather (NASA POWER) and soil (USDA SSURGO) for every grid cell.
## Fully resumable — cells already on disk are skipped, so it is safe to
## re-run after an interruption.
##
## Run:  Rscript 01-get-weather-soil.R      (from simulation/)
## ============================================================

setwd_here <- function() {
  a <- commandArgs(FALSE); f <- grep("^--file=", a, value = TRUE)
  if (length(f)) setwd(dirname(normalizePath(sub("^--file=", "", f[1]))))
}
setwd_here()
source("config.R")
source("R/data.R")
options(timeout = 300)

cells <- load_grid(GRID_FILE, N_CELLS)
message(sprintf("[01] %d cells to acquire | weather -> %s | soil -> %s",
                nrow(cells), WEATHER_DIR, SOIL_DIR))

ok_w <- ok_s <- 0L; fail <- character(0)
for (i in seq_len(nrow(cells))) {
  cl <- cells[i, ]
  w <- tryCatch(get_weather(cl$cellid, cl$lon, cl$lat, WEATHER_YEARS, WEATHER_DIR),
                error = function(e) { fail <<- c(fail, sprintf("cell %d weather: %s", cl$cellid, conditionMessage(e))); NULL })
  s <- tryCatch(get_soil(cl$cellid, cl$lon, cl$lat, SOIL_DIR),
                error = function(e) { fail <<- c(fail, sprintf("cell %d soil: %s", cl$cellid, conditionMessage(e))); NULL })
  ok_w <- ok_w + !is.null(w); ok_s <- ok_s + !is.null(s)
  if (i %% 25 == 0 || i == nrow(cells))
    message(sprintf("[01] %d/%d  weather ok=%d  soil ok=%d  failed=%d",
                    i, nrow(cells), ok_w, ok_s, length(fail)))
}

if (length(fail)) {
  message("[01] ", length(fail), " problems (will be retried on next run):")
  message(paste(" -", head(fail, 10)), sep = "\n")
}
message("[01] DONE — weather+soil cached under data/raw/")
