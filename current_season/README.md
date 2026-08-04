# Current-season tracker — in-season simulation engine

The real-time sibling of [`../simulation`](../simulation). Where that pipeline
runs the **40-year historical** record, this one runs the **current growing
season only** — from Jan 1 of this year to the latest available weather — on a
**daily** step, and maps where soils are currently **dry / adequate / wet**.

It reuses the historical pipeline's conditioned soils and root parameters, so
the two are physically consistent; only the weather (this year, refreshed) and
the reporting frequency (daily, not annual) differ.

## What is where

```
config.R                ← THE ONE FILE YOU EDIT (year, scenario, thresholds)
01-get-weather.R        → data/weather/<cellid>.met  (this year, NASA POWER daily)
                          soil is REUSED from ../simulation/data/raw/soil
02-run-apsim.R          → data/outputs/soil-water-daily.rds  (daily, parallel)
03-export-app-data.R    → ../app/data/soil-water.csv  (latest day per cell)
run-all.R               runs 01 → 02 → 03
R/soil.R                grid loader + soil conditioning (matches ../simulation)
R/apsim.R               build & run one daily simulation
templates/soybean-daily.apsimx   the historical template, re-reported DAILY
```

## Running it

```bash
# once, so soils exist (this pipeline reuses them):
cd ../simulation && Rscript 01-get-weather-soil.R && cd ../current_season

# then, from current_season/:
Rscript run-all.R                 # quick test first: set N_CELLS <- 5 in config.R
```

Nothing is machine-specific — APSIM is auto-detected and the weather downloads
itself. `run-all.R` overwrites this season's weather each run, so the season
grows through the year.

## Schedule

Designed to run **every Monday** and publish **Tuesday morning**: the weekly job
(`.github/workflows/refresh-current-season.yml`) runs the pipeline, commits the
updated `app/data/soil-water.csv`, and that commit redeploys the site.

## The daily template

`templates/soybean-daily.apsimx` is the historical soybean template with its
report switched to fire **every day** (`[Clock].EndOfDay`) and its variables
replaced with the in-season soil-water set:

| variable | meaning |
|----------|---------|
| `rel_sw_6in` / `12in` / `24in` | relative soil water (0 = wilting, 1 = field capacity) at 0–6 / 0–12 / 0–24 in |
| `swhc_6in` / `12in` / `24in` | plant-available water capacity (inches of water) |
| `CummRain_fromApril` | cumulative rainfall since April 1 (mm) |
| `Yield_kgha` / `Biomass_kgha` | running crop state |

`03` maps `rel_sw` into **Dry ≤ 40 %**, **Adequate ≤ 70 %**, **Excess** (cut
points in `config.R`).

## Required R packages

`apsimx`, `nasapower`, `soilDB`, `sf`, `dplyr`, `readr`, `parallel`,
`doParallel`, `foreach`.

## Data sources

| Source | What | Function |
|--------|------|----------|
| NASA POWER | this year's daily weather → `.met` | `apsimx::get_power_apsim_met` |
| USDA SSURGO | soil profile (reused from ../simulation) | `apsimx::get_ssurgo_soil_profile` |
