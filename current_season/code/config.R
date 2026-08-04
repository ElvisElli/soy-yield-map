## ============================================================
## config.R — THE ONE FILE YOU EDIT for the IN-SEASON tracker.
##
## This pipeline is the real-time sibling of ../simulation (which does the 40-year
## HISTORICAL run). It simulates the CURRENT growing season only — from Jan 1 of
## this year to the latest available weather — on a DAILY step, and maps where
## soils are currently dry / adequate / wet.
##
## ------------------------------------------------------------
## WHAT IS WHERE (current_season/)
## ------------------------------------------------------------
##   config.R                ← YOU EDIT THIS (year, scenario, thresholds, cores)
##   01-get-weather.R        downloads this year's daily weather per cell
##                           (soil is REUSED from ../simulation, already conditioned)
##   02-run-apsim.R          runs the DAILY soil-water template per cell (parallel)
##   03-export-app-data.R    → ../app/data/soil-water.csv (latest-day map surface)
##   run-all.R               runs 01 → 02 → 03
##   R/soil.R                grid loader + soil conditioning (shared logic)
##   templates/soybean-daily.apsimx   daily-output soil-water template
##
## ------------------------------------------------------------
## HOW / WHEN IT RUNS
## ------------------------------------------------------------
##   Weekly: a scheduled job runs it every MONDAY and publishes TUESDAY morning.
##   Locally: install APSIM (auto-detected) + the R packages in README, then
##            Rscript run-all.R      (set N_CELLS <- 5 first for a quick test)
##
##   Run ../simulation/01-get-weather-soil.R at least once first so the soil
##   profiles exist — this pipeline reuses them (it only downloads new weather).
## ============================================================


## ── SEASON ───────────────────────────────────────────────────────────────
## The year to track. Defaults to the current calendar year.
CURRENT_YEAR <- as.integer(format(Sys.Date(), "%Y"))
## NASA POWER lags a few days; don't request weather past this.
POWER_LATENCY_DAYS <- 3L
## Years of spin-up before the current season. Because the weather is merged with
## the historical record, the daily run can start earlier so soil moisture is
## realistic on Jan 1 (instead of resetting to field capacity). 1 = start last
## year; 0 = current year only (fastest).
SPINUP_YEARS <- 1L


## ── SCENARIO (the "typical field" we track) ──────────────────────────────
## In-season tracking follows one representative crop so the soil-water map is
## unambiguous. Add rows to track more (each is mapped separately in the app).
SCENARIOS <- data.frame(
  name        = "current",
  cultivar    = "PurcellMG4",
  sow_date    = "22-May",
  co2         = 420,
  warming_C   = 0,
  row_spacing = 750,
  stringsAsFactors = FALSE
)


## ── ROOT PARAMETERS (same as the historical study) ───────────────────────
## Depth profiles for soybean rooting, applied when a soil must be conditioned
## here (normally the soil is already conditioned by ../simulation and reused).
KL_VEC <- c(0.08, 0.08, 0.08, 0.08, 0.07, 0.07, 0.07, 0.07,
            0.06, 0.06, 0.06, 0.06, 0.05, 0.05, 0.04, 0.04,
            0.03, 0.03, 0.02, 0.02)
XF_VEC <- c(1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0)


## ── SOIL-WATER CLASSES (for the map) ─────────────────────────────────────
## Relative soil water = fraction of plant-available water (0 = wilting point,
## 1 = field capacity). Cut points (in %) split the map into three classes.
SW_DRY_MAX      <- 40    # <= 40%  → "Dry"
SW_ADEQUATE_MAX <- 70    # <= 70%  → "Adequate";  above → "Excess"


## ── GRID (which fields to simulate) ──────────────────────────────────────
GRID_FILE <- "../simulation/input/sim-grid.rds"
## NULL = every cultivated cell; an integer = first N (quick test); a vector = cellids.
N_CELLS   <- NULL
## The master run.R can force a small test subset without editing the line above.
if (nzchar(Sys.getenv("SOY_N_CELLS"))) N_CELLS <- as.integer(Sys.getenv("SOY_N_CELLS"))


## ── COMPUTE ──────────────────────────────────────────────────────────────
N_CORES    <- max(1L, parallel::detectCores() - 2L)
CHUNK_SIZE <- 50L


## ── PATHS ────────────────────────────────────────────────────────────────
## APSIM template — the SAME base file as the historical run. The daily-reporting
## variant is derived from it at run time (build_daily_template in R/apsim.R), so
## there is a single maintained template.
BASE_TEMPLATE <- "../simulation/input/templates/soybean-mg4-baseline.apsimx"
TEMPLATE     <- "output/soybean-daily.apsimx"   # derived; rebuilt when the base changes
WEATHER_DIR  <- "input/weather"                   # this year merged with history
SOIL_DIR     <- "../simulation/input/soil"        # REUSE historical conditioned soil
HIST_WEATHER_DIR <- "../simulation/input/weather" # historical .met to merge onto
OUT_DIR      <- "output"
CHECKPOINTS  <- file.path(OUT_DIR, "checkpoints")

## Research stations (in-season time-series at named farms/stations).
STATIONS_FILE    <- "input/stations.csv"
STATION_WX_DIR   <- "input/stations-weather"    # full-record .met per station (cached, merged)
STATION_SOIL_DIR <- "input/stations-soil"
