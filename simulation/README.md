# Component 1 — simulation engine

A small, reproducible R + APSIM Next Gen pipeline that builds the yield surface
the app consumes. It downloads its own weather and soil, runs APSIM across the
Arkansas cropland grid (~4,651 cultivated cells, 1985–2024) for a configurable
set of scenarios, and aggregates the results.

## Pipeline

```
config.R                ← the one file you edit (scenarios, grid, years, cores)
01-get-weather-soil.R   → data/raw/weather/<cellid>.met   (NASA POWER)
                          data/raw/soil/<cellid>.rds      (USDA SSURGO)
02-run-apsim.R          → data/outputs/simulated-scenarios-df.rds
03-export-app-data.R    → ../app/data/yield-surface.csv (+ ar-state/ar-counties)
get-nass-yields.R       → ../app/data/nass-county-yield.csv (county benchmark)
run-all.R               → runs 01 → 02 → 03
R/data.R, R/apsim.R     → helper library (download, build, run)
templates/…apsimx       → APSIM soybean template (MG4/MG5/MG6 cultivars)
```

Run the whole thing, or one step at a time:

```bash
Rscript run-all.R                 # everything
# or
Rscript 01-get-weather-soil.R
Rscript 02-run-apsim.R
Rscript 03-export-app-data.R
```

Every step is **resumable**: cached weather/soil are reused, and APSIM results
are checkpointed per chunk of cells (`data/outputs/checkpoints/`), so an
interrupted run continues where it left off.

## Editing scenarios (`config.R`)

One row per scenario — add or remove rows freely:

| field       | meaning                                            |
|-------------|----------------------------------------------------|
| `name`      | short id used in outputs and the app               |
| `cultivar`  | `PurcellMG4` / `PurcellMG5` / `PurcellMG6`          |
| `sow_date`  | APSIM `dd-mmm`, e.g. `22-May`, `24-Apr`, `05-Jun`   |
| `co2`       | atmospheric CO₂ (ppm)                              |
| `warming_C` | °C added to daily min/max temperature (0 = current)|
| `row_spacing` | mm                                               |

`config.R` also holds the grid (`N_CELLS` to subset for a quick test), the
simulation clock (`DATE_START` / `DATE_END`), and compute settings (`N_CORES`,
`CHUNK_SIZE`).

## Installing APSIM

The pipeline needs the APSIM `Models` executable; `R/apsim.R` finds it
automatically.

- **Linux / cloud:** install the `.deb` from the climate-change study's
  `installers/` (`sudo dpkg -i apsim-*.deb`; GUI-only deps like `zenity` can be
  ignored — the `Models` CLI still runs).
- **Windows:** install APSIM normally; it is picked up from
  `%LOCALAPPDATA%\Programs\APSIM*`.

## Parallelism

`02-run-apsim.R` uses fork-based `parallel::mclapply` (ideal on a Linux cloud
box). On Windows it falls back to a single core — run large jobs in the cloud,
or subset the grid with `N_CELLS`.

## Required R packages

`apsimx`, `nasapower`, `soilDB`, `sf`, `dplyr`, `readr`, `parallel`.
(`nasapower` → weather, `soilDB` → SSURGO soil, `sf` → project cells + boundaries
in the export.)

## Data sources

| Source        | What                         | Function                       |
|---------------|------------------------------|--------------------------------|
| NASA POWER    | daily weather → `.met`       | `apsimx::get_power_apsim_met`  |
| USDA SSURGO   | soil profile → `.rds`        | `apsimx::get_ssurgo_soil_profile` |
| Census TIGER  | AR state + county boundaries | shapefiles in `data/raw/cropland` |
