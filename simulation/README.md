# Component 1 — simulation engine

A small, reproducible R + APSIM Next Gen pipeline that builds the yield surface
the app consumes. It downloads its own weather and soil, runs APSIM across the
Arkansas cropland grid (~4,651 cultivated cells, 1985–2024) for a configurable
set of scenarios, and aggregates the results.

## What is where

Three folders — **`code/`** (scripts), **`input/`** (data in), **`output/`**
(results out):

```
code/config.R              ← THE ONE FILE YOU EDIT (scenarios, root params,
                             grid size, years 1985–2025, cores) — start here
code/01-get-weather-soil.R → input/weather/<cellid>.met   (NASA POWER, 1985–2025)
                             input/soil/<cellid>.rds       (USDA SSURGO, conditioned)
                             ↑ ALL soil adaptations (KS, KL, XF, initial water) live
                               in condition_soil() here, so the cached .rds is FINAL
code/02-run-apsim.R        → output/simulated-scenarios-df.rds
code/03-export-app-data.R  → ../app/data/yield-surface.csv (+ ar-state/ar-counties)
code/04-inspect.R          → output/plots/  ← CHECK RESULTS HERE (yield map + hist)
code/run-all.R             → runs 01 → 02 → 03 → 04
code/get-nass-yields.R     → ../app/data/nass-county-yield.csv (county benchmark)
code/R/                    → load-grid + build/run helpers
input/templates/…apsimx    → APSIM soybean template (MG4/MG5/MG6 cultivars)
```

**To run it on your computer:** open `simulation.Rproj` (or use the master
`../run.R`), install APSIM Next Gen (auto-detected) + the R packages below, then
`Rscript code/run-all.R`. Nothing is machine-specific. For a fast trial first set
`N_CELLS <- 5` in `code/config.R` (a test writes to `output/`, leaving the app
data untouched).

Every step is **resumable**: cached weather/soil are reused, and APSIM results
are checkpointed per chunk (`output/checkpoints/`). When done, open
`output/plots/inspect-yield-map.png` to confirm it worked.

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

`config.R` also holds the root parameters (`KL_VEC` / `XF_VEC`), the grid
(`N_CELLS` to subset for a quick test), the simulation clock (`DATE_START` /
`DATE_END`), and compute settings (`N_CORES`, `CHUNK_SIZE`).

## Soil conditioning (`01-get-weather-soil.R`)

Every raw SSURGO profile is conditioned once, at download time, so the cached
`data/raw/soil/<cellid>.rds` is the **final, ready-to-simulate** profile. All of
this is in `condition_soil()` — ported verbatim from the climate-change study's
`01-simulation.R`:

| Step | What it does |
|------|--------------|
| **KS** | saturated hydraulic conductivity decreases with depth |
| **fix** | reconcile SAT / bulk density / DUL (`apsimx`) |
| **KL** | root water-extraction per layer, depth-decaying (`KL_VEC`) |
| **XF** | root exploration factor per layer / rooting-depth cap (`XF_VEC`) |
| initial water | profile starts each season at drained upper limit |
| crops | ensures Soybean / Wheat / Maize are present |

`KL_VEC` and `XF_VEC` are baked into the profile's crop columns
(`Soybean.KL`, `Soybean.XF`, …), so `02` writes them straight into each APSIM
file — no separate edit step. **If you change any soil setting, delete
`data/raw/soil/` so profiles are re-conditioned on the next run** (cached cells
are otherwise reused).

## Installing APSIM

The pipeline needs the APSIM `Models` executable; `R/apsim.R` finds it
automatically.

- **Linux / cloud:** install the `.deb` from the climate-change study's
  `installers/` (`sudo dpkg -i apsim-*.deb`; GUI-only deps like `zenity` can be
  ignored — the `Models` CLI still runs).
- **Windows:** install APSIM normally; it is picked up from
  `%LOCALAPPDATA%\Programs\APSIM*`.

## Parallelism

`02-run-apsim.R` runs APSIM across all cores using a **PSOCK cluster**
(`parallel` + `doParallel`/`foreach`) — full multi-core on **both Windows and
Linux/macOS/cloud**, the same approach as the climate-change study. Core count
is `N_CORES` in `config.R` (default `detectCores() - 2`); it falls back to
sequential automatically if only one core is available.

## Required R packages

`apsimx`, `nasapower`, `soilDB`, `sf`, `dplyr`, `readr`, `parallel`,
`doParallel`, `foreach`, `jsonlite`.
(`nasapower` → weather, `soilDB` → SSURGO soil, `sf` → project cells + boundaries
in the export, `doParallel`/`foreach` → the PSOCK cluster, `jsonlite` → NASS.)

## Data sources

| Source        | What                         | Function                       |
|---------------|------------------------------|--------------------------------|
| NASA POWER    | daily weather → `.met`       | `apsimx::get_power_apsim_met`  |
| USDA SSURGO   | soil profile → `.rds`        | `apsimx::get_ssurgo_soil_profile` |
| Census TIGER  | AR state + county boundaries | shapefiles in `data/raw/cropland` |
