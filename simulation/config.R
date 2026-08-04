## ============================================================
## config.R — THE ONE FILE YOU EDIT.
##
## Everything you might change to run or tune the simulation lives here:
## scenarios, root parameters, how many cells, the years, and compute settings.
## The numbered scripts read these values; you rarely need to open them.
##
## ------------------------------------------------------------
## WHAT IS WHERE (simulation/)
## ------------------------------------------------------------
##   config.R                ← YOU EDIT THIS (settings, scenarios, root params)
##   01-get-weather-soil.R   downloads + conditions weather & soil per cell,
##                           caching the FINAL soil profile (KS, KL, XF, …)
##   02-run-apsim.R          runs APSIM across cells × scenarios (parallel)
##   03-export-app-data.R    aggregates results → ../app/data/yield-surface.csv
##   run-all.R               runs 01 → 02 → 03 in order
##   get-nass-yields.R       county USDA-NASS benchmark for the app
##   R/data.R                load the cropland grid (tiny helper)
##   R/apsim.R               build & run one APSIM file (helper)
##   templates/…apsimx       the APSIM soybean template (MG4/MG5/MG6)
##
## ------------------------------------------------------------
## HOW TO RUN IT ON YOUR COMPUTER
## ------------------------------------------------------------
##   1. Install APSIM Next Gen (it is found automatically — nothing to set here).
##   2. Install the R packages listed in README.md.
##   3. From the simulation/ folder:
##
##        # quick test first (set N_CELLS <- 5 below), then:
##        Rscript run-all.R
##
##   There is NOTHING machine-specific to change: APSIM is auto-detected, and the
##   weather/soil download themselves. To do a fast trial run, set N_CELLS to a
##   small number (e.g. 5); set it back to NULL for the full state.
## ============================================================


## ── SCENARIOS ────────────────────────────────────────────────────────────
## One row per scenario. Add or remove rows freely — the pipeline and the app
## adapt to whatever you define here.
##
##   name        short id used in outputs and the app
##   cultivar    APSIM cultivar in the template (PurcellMG4 / MG5 / MG6)
##   sow_date    sowing date, APSIM "dd-mmm" format (e.g. "22-May", "24-Apr")
##   co2         atmospheric CO2 (ppm)   — 350 ≈ current-ish, 540 ≈ future
##   warming_C   °C added to min & max temperature (0 = current climate)
##   row_spacing mm
SCENARIOS <- data.frame(
  name        = c("baseline",   "early_sowing", "longer_mat", "early_sowing_longer_mat"),
  cultivar    = c("PurcellMG4", "PurcellMG4",   "PurcellMG5", "PurcellMG5"),
  sow_date    = c("22-May",     "24-Apr",       "22-May",     "24-Apr"),
  co2         = c(350,          350,            350,          350),
  warming_C   = c(0,            0,              0,            0),
  row_spacing = 750,
  stringsAsFactors = FALSE
)
## Example — to add an MG6, later-planting scenario, append:
##   rbind(SCENARIOS, data.frame(name="mg6_june", cultivar="PurcellMG6",
##         sow_date="05-Jun", co2=350, warming_C=0, row_spacing=750))


## ── ROOT PARAMETERS (soil) ───────────────────────────────────────────────
## The study's depth profiles for soybean rooting, applied to every soil in
## 01-get-weather-soil.R (ported verbatim from the climate-change study's
## 01-simulation.R). One value per soil layer, from the surface down.
##
##   KL_VEC  how much plant-available water a root extracts from each layer per
##           day (fraction). Decreases with depth as rooting density drops.
##   XF_VEC  root exploration factor per layer: 1 = roots grow freely, 0 = no
##           roots. The trailing zeros cap effective rooting depth.
##
## A profile with N layers uses the first N values (extra layers repeat the last
## value). Edit these to change the rooting assumptions.
KL_VEC <- c(0.08, 0.08, 0.08, 0.08, 0.07, 0.07, 0.07, 0.07,
            0.06, 0.06, 0.06, 0.06, 0.05, 0.05, 0.04, 0.04,
            0.03, 0.03, 0.02, 0.02)
XF_VEC <- c(1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0)


## ── GRID (which fields to simulate) ──────────────────────────────────────
## The cropland grid of cultivated cells. Each cell is one lon/lat point.
GRID_FILE <- "data/raw/sim-grid.rds"
## Quick test vs. full run:
##   NULL          every cultivated cell (~4,651)  ← full run
##   an integer    the first N cells               ← fast trial (e.g. 5)
##   a vector      specific cellids
N_CELLS   <- NULL


## ── SIMULATION CLOCK (years to simulate) ─────────────────────────────────
DATE_START <- "1985-01-01"
DATE_END   <- "2024-12-31"


## ── WEATHER / SOIL SOURCES ───────────────────────────────────────────────
## Weather: NASA POWER (global, daily).  Soil: USDA SSURGO (CONUS).
## Both download once per cell and cache on disk (fully resumable).
WEATHER_YEARS <- c(1984, 2024)   # POWER range to fetch (>= the sim clock)


## ── COMPUTE ──────────────────────────────────────────────────────────────
## Leaves 2 cores free for the OS. Falls back to sequential on a single core.
N_CORES    <- max(1L, parallel::detectCores() - 2L)
CHUNK_SIZE <- 50L                # cells per checkpoint (resume granularity)


## ── PATHS (relative to simulation/) ──────────────────────────────────────
TEMPLATE     <- "templates/soybean-mg4-baseline.apsimx"
WEATHER_DIR  <- "data/raw/weather"
SOIL_DIR     <- "data/raw/soil"
OUT_DIR      <- "data/outputs"
CHECKPOINTS  <- file.path(OUT_DIR, "checkpoints")
