## ============================================================
## config.R — the ONE place to edit the simulation.
##
## Sourced by every pipeline step (01 → 02 → 03). Change scenarios, the grid,
## the years or the compute settings here; nothing else needs editing.
## ============================================================

## ── SCENARIOS ────────────────────────────────────────────────────────────
## One row per scenario. Add or remove rows to explore other maturity groups
## or sowing dates — the rest of the pipeline adapts automatically.
##
##   name        short id used in outputs and the app
##   cultivar    APSIM cultivar defined in the template
##                 (PurcellMG4, PurcellMG5, PurcellMG6 are available)
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

## ── GRID (which fields to simulate) ──────────────────────────────────────
## The cropland grid of cultivated cells. Each cell is one lon/lat point.
GRID_FILE <- "data/raw/sim-grid.rds"
## Subset for a quick test run: NULL = every cultivated cell (~4,651);
## an integer = the first N cells; a numeric vector = specific cellids.
N_CELLS   <- NULL

## ── SIMULATION CLOCK ─────────────────────────────────────────────────────
DATE_START <- "1985-01-01"
DATE_END   <- "2024-12-31"

## ── WEATHER / SOIL SOURCES ───────────────────────────────────────────────
## Weather: NASA POWER (global, daily).  Soil: USDA SSURGO (CONUS).
## Both are downloaded once per cell and cached on disk (fully resumable).
WEATHER_YEARS <- c(1984, 2024)   # POWER range to fetch (>= sim clock)

## ── COMPUTE ──────────────────────────────────────────────────────────────
N_CORES    <- max(1L, parallel::detectCores() - 2L)
CHUNK_SIZE <- 50L                # cells per checkpoint

## ── PATHS (relative to simulation/) ──────────────────────────────────────
TEMPLATE     <- "templates/soybean-mg4-baseline.apsimx"
WEATHER_DIR  <- "data/raw/weather"
SOIL_DIR     <- "data/raw/soil"
OUT_DIR      <- "data/outputs"
CHECKPOINTS  <- file.path(OUT_DIR, "checkpoints")
