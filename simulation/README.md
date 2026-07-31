# Component 1 — simulation engine

Grid-scale APSIM Next Generation soybean simulations across Arkansas cropland
(~4,651 cultivated cells), 40-year weather record (1985–2024), for the scenarios
the yield-map app exposes. This is the same modeling structure as the
[`soybean-ar-climate-change`](https://github.com/ElvisElli/soybean-ar-climate-change)
study, packaged here to feed the interactive map.

## What it produces

```
simulation/code/01-simulation.R   ──►  data/outputs/simulated-scenarios-df.rds   (full, ~30 MB, gitignored)
simulation/export-app-data.R      ──►  ../app/data/yield-surface.csv             (aggregated, committed)
```

`yield-surface.csv` is the **only** thing the app consumes — a per-cell,
per-practice 40-year mean yield with p10/p90 spread.

## Running

```r
# From the repo root, in RStudio or:
Rscript simulation/code/01-simulation.R     # 1. run APSIM across grid × scenarios (parallel, resumable)
Rscript simulation/export-app-data.R        # 2. aggregate results → app/data/yield-surface.csv
```

The simulation is **fully resumable** — re-run any time; completed chunks are
skipped automatically (per-chunk RDS checkpoints under
`data/outputs/checkpoints/`).

| Setting            | Default   | Notes                                   |
|--------------------|-----------|-----------------------------------------|
| `CHUNK_SIZE`       | 50        | cells per parallel task                 |
| `DATE_START/END`   | 1985–2024 | simulation clock                        |
| Cores              | `nCores-2`| leaves 2 free for the OS                |
| `LOCAL_DATA_CACHE` | see below | optional local-SSD copy of weather/soil |

**Local data cache (Windows):** Box Drive network latency is the main
bottleneck. Copy `weather/` and `soil/` to a local SSD once (~10 GB) and set
`LOCAL_DATA_CACHE <- "C:/temp/soybean-data"` in `code/01-simulation.R` to cut
runtime 30–50%.

## Environment auto-detection

The script identifies the machine at startup — no manual configuration:

| Environment        | APSIM exe                              | Weather/soil                                | Tmp dir            |
|--------------------|----------------------------------------|---------------------------------------------|--------------------|
| Windows (any user) | Latest APSIM under `%LOCALAPPDATA%`     | Scans Box mount points across user profiles | `C:\temp\apsim-proc` |
| Linux / cloud      | Auto-detected                          | `data/raw/weather` + `data/raw/soil`        | `/tmp/apsim-proc`  |

## Scenarios

Defined in `data/raw/scenarios/soy-scenarios-10-24.xlsx`:

| Scenario                  | Cultivar   | Sowing | CO₂ (ppm) | Climate  |
|---------------------------|------------|--------|-----------|----------|
| baseline                  | PurcellMG4 | 22-May | 350       | current  |
| climate_change            | PurcellMG4 | 22-May | 350 / 540 | +2 °C    |
| early_sowing              | PurcellMG4 | 24-Apr | 350 / 540 | +2 °C    |
| longer_mat                | PurcellMG5 | 22-May | 350 / 540 | +2 °C    |
| early_sowing_longer_mat   | PurcellMG5 | 24-Apr | 350 / 540 | +2 °C    |

## Required R packages

`apsimx`, `doParallel`, `foreach`, `dplyr`, `readr`, `readxl`, `parallel`,
`data.table`. The `export-app-data.R` step needs `dplyr`, `readr` and `sf`
(to project cells and the state/county boundaries to EPSG:5070 for the app).

## Files

| File                                       | Description                                   |
|--------------------------------------------|-----------------------------------------------|
| `code/01-simulation.R`                     | Run APSIM across grid × scenarios (parallel)  |
| `code/utils/variables.R`                   | Soil-fraction weighted variable aggregation   |
| `code/utils/plot-theme.R`                  | Shared ggplot2 theme                          |
| `export-app-data.R`                        | Aggregate sim results → app yield surface     |
| `data/raw/sim-grid.rds`                    | Spatial grid (x, y, cellid, cultivated flag)  |
| `data/raw/scenarios/soy-scenarios-10-24.xlsx` | Scenario definitions                       |
