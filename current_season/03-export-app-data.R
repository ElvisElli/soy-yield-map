## ============================================================
## 03-export-app-data.R
## Reduce the daily soil-water run to the LATEST day per cell and write the
## compact surface the app's In-season tab reads.
##
## Input : data/outputs/soil-water-daily.rds
## Output: ../app/data/soil-water.csv         (one row per cell, latest day)
##         ../app/data/soil-water-meta.json   (last-update date, thresholds)
##
## Run:  Rscript 03-export-app-data.R      (from current_season/)
## ============================================================

setwd_here <- function() {
  a <- commandArgs(FALSE); f <- grep("^--file=", a, value = TRUE)
  if (length(f)) setwd(dirname(normalizePath(sub("^--file=", "", f[1]))))
}
setwd_here()
source("config.R")
suppressPackageStartupMessages({ library(dplyr); library(readr); library(sf) })

ALBERS  <- 5070
IN_RDS  <- file.path(OUT_DIR, "soil-water-daily.rds")
COUNTY_SHP <- "../simulation/data/raw/cropland/Elvis-Crop-Data/Arkansas_Counties_4269.shp"
OUT_CSV  <- "../app/data/soil-water.csv"
OUT_META <- "../app/data/soil-water-meta.json"

if (!file.exists(IN_RDS))
  stop("Daily results not found: ", IN_RDS, "\nRun 01 then 02 first.")

daily <- readRDS(IN_RDS)
message(sprintf("[export] %d daily rows (%d cells)", nrow(daily),
                dplyr::n_distinct(daily$cellid)))

## Class a relative-soil-water fraction (0-1) into Dry / Adequate / Excess.
classify <- function(rel) {
  pct <- rel * 100
  factor(ifelse(pct <= SW_DRY_MAX, "Dry",
         ifelse(pct <= SW_ADEQUATE_MAX, "Adequate", "Excess")),
         levels = c("Dry", "Adequate", "Excess"))
}

## Latest simulated day per cell (one representative scenario per cell).
latest <- daily %>%
  filter(scenario == SCENARIOS$name[1]) %>%
  group_by(cellid) %>%
  slice_max(date, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  transmute(
    cellid, x = round(x, 5), y = round(y, 5), date,
    rel_sw_6in  = round(rel_sw_6in, 3),
    rel_sw_12in = round(rel_sw_12in, 3),
    rel_sw_24in = round(rel_sw_24in, 3),
    class_6in   = classify(rel_sw_6in),
    class_12in  = classify(rel_sw_12in),
    class_24in  = classify(rel_sw_24in),
    swhc_24in   = round(swhc_24in, 2),
    cumrain_in  = round(CummRain_fromApril / 25.4, 2)   # mm → inches
  )

## Project to Albers (map filter) + tag county.
alb <- sf::st_as_sf(latest, coords = c("x", "y"), crs = 4326, remove = FALSE) %>%
  sf::st_transform(ALBERS)
xy <- sf::st_coordinates(alb)
latest$x_alb <- round(xy[, 1], 1); latest$y_alb <- round(xy[, 2], 1)

if (file.exists(COUNTY_SHP)) {
  suppressWarnings(sf::sf_use_s2(FALSE))
  cy  <- sf::st_transform(sf::st_read(COUNTY_SHP, quiet = TRUE)["NAME"], 4326)
  pts <- sf::st_as_sf(latest, coords = c("x", "y"), crs = 4326, remove = FALSE)
  latest$county <- toupper(trimws(sf::st_join(pts, cy, join = sf::st_within)$NAME))
} else latest$county <- NA_character_

dir.create(dirname(OUT_CSV), recursive = TRUE, showWarnings = FALSE)
readr::write_csv(latest, OUT_CSV)
message("[export] wrote ", OUT_CSV, " (", nrow(latest), " cells)")

last_update <- as.character(max(latest$date, na.rm = TRUE))
meta <- sprintf(paste0(
  '{\n  "generated": "%s",\n  "season": %d,\n  "last_update": "%s",\n',
  '  "n_cells": %d,\n  "dry_max_pct": %d,\n  "adequate_max_pct": %d,\n',
  '  "source": "APSIM Next Generation in-season daily soil-water simulation"\n}\n'),
  format(Sys.time(), "%Y-%m-%d"), CURRENT_YEAR, last_update,
  nrow(latest), SW_DRY_MAX, SW_ADEQUATE_MAX)
writeLines(meta, OUT_META)
message("[export] wrote ", OUT_META, " | last update: ", last_update)
message("[export] DONE")
