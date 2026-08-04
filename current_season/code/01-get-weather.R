## ============================================================
## 01-get-weather.R
## Get THIS SEASON's daily weather for every grid cell and MERGE it onto the
## historical record, so each cell ends up with one continuous .met from 1985 to
## the latest available day. Soil is reused from ../simulation.
##
##   download   NASA POWER daily, current year only (Jan 1 → latest day)
##   merge      onto ../simulation/input/weather/<cellid>.met  (1985–2025)
##   write      input/weather/<cellid>.met   (1985 → today)
##   soil       reused from ../simulation/input/soil/<cellid>.rds
##
## Only the NEW year is downloaded each week — the 40-year history is never
## re-fetched. If no historical file exists yet (you haven't run ../simulation),
## the current year alone is used.
##
## Run:  Rscript code/run-all.R   (or the master ../run.R)
## ============================================================

## set the working directory to the component root (folder with code/ input/ output/)
local({
  a <- commandArgs(FALSE); f <- grep("^--file=", a, value = TRUE)
  d <- if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1]))) else getwd()
  while (!file.exists(file.path(d, "code", "config.R")) && dirname(d) != d) d <- dirname(d)
  setwd(d)
})
source("code/config.R")
source("code/R/soil.R")
suppressPackageStartupMessages(library(apsimx))
options(timeout = 300)

## This season's weather window: Jan 1 → latest POWER day.
WX_START <- sprintf("%d-01-01", CURRENT_YEAR)
WX_END   <- as.character(Sys.Date() - POWER_LATENCY_DAYS)

## Merge two apsim met objects: keep all historical years strictly before the
## current record, append the current year(s), re-sort, and carry the met header
## attributes so write_apsim_met() produces a valid file.
merge_met <- function(hist, cur) {
  hd <- as.data.frame(hist); cd <- as.data.frame(cur)
  hd <- hd[!(hd$year %in% unique(cd$year)), , drop = FALSE]   # current wins on overlap
  comb <- rbind(hd[names(cd)], cd)
  comb <- comb[order(comb$year, comb$day), , drop = FALSE]
  for (a in c("units", "latitude", "longitude", "site", "colnames",
              "comments", "constants", "tav", "amp"))
    if (!is.null(attr(cur, a))) attr(comb, a) <- attr(cur, a)
  class(comb) <- class(cur)
  comb
}

## Download the current year and merge it onto the historical record -> .met.
get_weather <- function(cellid, lon, lat, dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  cur <- get_power_apsim_met(lonlat = c(lon, lat), dates = c(WX_START, WX_END))
  cur <- tryCatch(impute_apsim_met(cur), error = function(e) cur)
  hist_met <- file.path(HIST_WEATHER_DIR, paste0(cellid, ".met"))
  out <- if (file.exists(hist_met)) {
    h <- read_apsim_met(paste0(cellid, ".met"), src.dir = HIST_WEATHER_DIR, verbose = FALSE)
    merge_met(h, cur)
  } else cur
  write_apsim_met(out, wrt.dir = dir, filename = paste0(cellid, ".met"))
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
