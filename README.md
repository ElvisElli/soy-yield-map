# soy-yield-map

**An interactive soybean yield-gap map for Arkansas farmers.**

`soy-yield-map` turns the grid-scale APSIM simulations from the
[`soybean-ar-climate-change`](https://github.com/ElvisElli/soybean-ar-climate-change)
study into a farmer-facing web tool. A grower enters the latitude/longitude of
their field, their maturity group and planting date, and their own measured
yield — and the app shows the model-predicted yield at that location, how their
yield compares (the **yield gap**), and how much they could gain by shifting
maturity group or planting date.

![The soy-yield-map app: yield-distribution plots above a cardinal-red map of
predicted soybean yield across Arkansas](docs/screenshot.png)

The repository has **two loosely-coupled components** so each can evolve
independently:

```
soy-yield-map/
├── simulation/     COMPONENT 1 — the modeling engine (R + APSIM NG)
│   ├── code/                 download weather & soil, run APSIM in parallel
│   ├── data/                 grid + scenario definitions
│   └── export-app-data.R     aggregate sim results → compact yield surface
│
├── app/            COMPONENT 2 — the interactive map (R Shiny)
│   ├── app.R                 the Shiny application
│   ├── R/                    helper functions (units, lookup, scenarios)
│   └── data/
│       └── yield-surface.csv baked per-cell predictions the app reads
│
└── .github/workflows/
    └── deploy.yml            build the app to WebAssembly, publish to Pages
```

## How the two components connect

```
  weather + soil            APSIM NG grid run           per-cell, per-practice
  (Box / IEM / SSURGO) ───▶ (simulation/code)  ───▶     yield surface (CSV)
                                                              │
                                                              ▼
                                            Shiny app  ◀───  app/data/yield-surface.csv
                                       (map, lat/lon lookup, gap)
```

Component 1 is expensive and run occasionally (it re-runs the whole state).
Component 2 is cheap, static, and updated every time the surface is refreshed.
The **only contract between them** is `app/data/yield-surface.csv` — regenerate
it with `simulation/export-app-data.R` and the app picks it up.

---

## Component 1 — simulation engine

Reuses the structure of the climate-change study: environment auto-detection,
`.met` weather + `.rds` soil profiles, and parallel APSIM runs across the
Arkansas cropland grid (~4,651 cultivated cells), 1985–2024.

```r
# From simulation/ in RStudio, or:
Rscript simulation/code/01-simulation.R      # run APSIM across grid × scenarios
Rscript simulation/export-app-data.R         # aggregate results -> app/data/yield-surface.csv
```

See [`simulation/README.md`](simulation/README.md) for machine setup, the local
data cache, and crash recovery. The engine is fully resumable — completed
chunks are skipped on re-run.

### Scenarios exposed to farmers

The app lets a grower pick their **maturity group** and **planting date**; each
combination maps to one simulated scenario:

| Maturity group | Planting date | Climate  | Scenario                  |
|----------------|---------------|----------|---------------------------|
| MG4            | late May      | current  | `baseline`                |
| MG4            | late May      | +2 °C    | `climate_change`          |
| MG4            | late April    | +2 °C    | `early_sowing`            |
| MG5            | late May      | +2 °C    | `longer_mat`              |
| MG5            | late April    | +2 °C    | `early_sowing_longer_mat` |

Each scenario also has a rising-CO₂ variant (540 ppm) selectable as an advanced
option. The two adaptation levers — **earlier planting (May→April)** and a
**longer maturity group (MG4→MG5)** — are exactly the synergistic shifts studied
in the paper; here a farmer can see the effect at their own field.

---

## Component 2 — the interactive map (R Shiny)

A single-file Shiny app (`app/app.R`) with a Leaflet map of Arkansas coloured by
predicted yield. The grower:

1. Drops a pin (clicks the map) or types **latitude / longitude**.
2. Selects **maturity group** and **planting date** (their current practice).
3. Enters **their own yield** (bu/ac or kg/ha).

The app finds the nearest simulated grid cell and shows:

- A **boxplot** of the simulated 40-year yield distribution for the grower's
  selected practice, the grower's reported yield as a **bar**, and a left-hand
  **summary card** with the potential (simulated mean), real (reported) and
  **yield gap**. The y-axis is fixed at **0–120 bu/ac** for easy comparison.
- A **map** rendered like the study's manuscript figures — EPSG:5070 (Conus
  Albers), **Arkansas state fill + county outlines**, a cardinal-red yield
  raster, and the field marked — cropped to the eastern (soybean) half of the
  state, exactly matching the paper's `coord_sf(xlim = c(360000, 570000))`.
- A narrative summary of the simulated mean, its typical range, and the gap.

The interface is styled in **University of Arkansas cardinal (#9D2235)** so the
map and figure can be embedded directly in a university web page.

**Grain moisture:** APSIM reports `Yield_kgha` as *dry* grain (0% moisture).
Bushels are a market unit defined at **13% moisture**, so the app grosses the
simulated yields up to 13% before display — putting them on the same basis as a
grower's measured, market-moisture yield (1 bu/ac = 67.25 kg/ha at 13%).

> This first version focuses on the **current-climate baseline**. The warming
> (+2 °C) scenarios are still produced by the simulation and can be layered back
> into the app when needed. The map uses only `ggplot2` (projection and
> boundaries are pre-baked by the export), so the app needs no `sf`/`leaflet`.

### Run locally

```r
# install.packages(c("shiny","leaflet","bslib","dplyr","readr"))
shiny::runApp("app")
```

### Hosting on GitHub (no server)

The app is deployed as a **static** site with
[`shinylive`](https://posit-dev.github.io/r-shinylive/): the R code is compiled
to WebAssembly and runs entirely in the visitor's browser, so it can be served
free from **GitHub Pages** with no Shiny server. The workflow in
`.github/workflows/deploy.yml` rebuilds and publishes on every push to the
default branch. The same `app.R` also runs unchanged on a traditional Shiny
Server or shinyapps.io if you ever want server-side execution.

---

## Roadmap / flexibility

The map and app are meant to keep improving. Natural next steps:

- On-demand single-point APSIM run for a farmer's exact coordinates (server mode).
- More levers: row spacing, irrigation, additional maturity groups (MG6).
- Historical NASS county yields overlaid for validation.
- County/field polygons instead of grid points.

Because the app only depends on `yield-surface.csv`, any of these can be added by
extending the export script without touching the map — or by extending the map
without re-running the simulation.
