## ============================================================
## 01-get-weather.R
## Download THIS SEASON's daily weather for every grid cell — from Jan 1 of the
## current year to the latest available day — and make sure each cell has a
## conditioned soil profile (reused from ../simulation, or downloaded if missing).
##
##   weather  NASA POWER daily -> data/weather/<cellid>.met   (re-downloaded weekly)
##   soil     reused from ../simulation/data/raw/soil/<cellid>.rds
##
## Weather is imputed (POWER's near-real-time tail can miss a day) and the file
## is overwritten each run so the season grows through the year.
##
## Run:  Rscript 01-get-weather.R      (from current_season/)
## ============================================================

setwd_here <- function() {
  a <- commandArgs(FALSE); f <- grep("^--file=", a, value = TRUE)
  if (length(f)) setwd(dirname(normalizePath(sub("^--file=", "", f[1]))))
}
setwd_here()
source("config.R")
source("R/soil.R")
suppressPackageStartupMessages(library(apsimx))
options(timeout = 300)

## This season's weather window: Jan 1 → latest POWER day.
WX_START <- sprintf("%d-01-01", CURRENT_YEAR)
WX_END   <- as.character(Sys.Date() - POWER_LATENCY_DAYS)

## Download (always refresh) this year's weather for one cell -> <cellid>.met.
get_weather <- function(cellid, lon, lat, dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  met <- get_power_apsim_met(lonlat = c(lon, lat), dates = c(WX_START, WX_END))
  met <- tryCatch(impute_apsim_met(met), error = function(e) met)
  write_apsim_met(met, wrt.dir = dir, filename = paste0(cellid, ".met"))
  file.path(dir, paste0(cellid, ".met"))
}

cells <- load_grid(GRID_FILE, N_CELLS)
message(sprintf("[01] season %d | %s → %s | %d cells | weather -> %s",
                CURRENT_YEAR, WX_START, WX_END, nrow(cells), WEATHER_DIR))

ok_w <- ok_s <- 0L; fail <- character(0)
for (i in seq_len(nrow(cells))) {
  cl <- cells[i, ]
  w <- tryCatch(get_weather(cl$cellid, cl$lon, cl$lat, WEATHER_DIR),
                error = function(e) { fail <<- c(fail, sprintf("cell %d weather: %s", cl$cellid, conditionMessage(e))); NULL })
  s <- tryCatch(get_soil(cl$cellid, cl$lon, cl$lat, SOIL_DIR),
                error = function(e) { fail <<- c(fail, sprintf("cell %d soil: %s", cl$cellid, conditionMessage(e))); NULL })
  ok_w <- ok_w + !is.null(w); ok_s <- ok_s + !is.null(s)
  if (i %% 25 == 0 || i == nrow(cells))
    message(sprintf("[01] %d/%d  weather ok=%d  soil ok=%d  failed=%d",
                    i, nrow(cells), ok_w, ok_s, length(fail)))
}

if (length(fail)) {
  message("[01] ", length(fail), " problems (retried next run):")
  message(paste(" -", head(fail, 10)), sep = "\n")
}
message("[01] DONE — this season's weather cached; soils ready.")
