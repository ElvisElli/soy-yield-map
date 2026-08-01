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
│   ├── config.R              ← edit here: scenarios, grid, years
│   ├── 01-get-weather-soil.R download NASA POWER weather + SSURGO soil
│   ├── 02-run-apsim.R        run APSIM across cells × scenarios (parallel)
│   ├── 03-export-app-data.R  aggregate results → compact yield surface
│   ├── run-all.R             run 01 → 02 → 03 in order
│   ├── R/                    helper library (data.R, apsim.R)
│   └── templates/            APSIM soybean template (.apsimx)
│
├── app/            COMPONENT 2 — the interactive tool (R Shiny + ggplot2)
│   ├── app.R                 the Shiny application
│   ├── R/                    helpers (units/moisture) + UARK plots
│   └── data/
│       ├── yield-surface.csv baked per-cell predictions the app reads
│       └── ar-*.csv          pre-projected state + county boundaries
│
└── .github/workflows/
    └── deploy.yml            build the app to WebAssembly, publish to Pages
```

## How the two components connect

```
  weather  (NASA POWER)  ┐     APSIM NG run          per-cell, per-scenario
  soil     (USDA SSURGO) ┼──▶  (simulation/02) ──▶   yield surface (CSV)
  scenarios (config.R)   ┘                                  │
                                                            ▼
                                          Shiny app  ◀──  app/data/yield-surface.csv
                                     (boxplot + gap, state/county yield map)
```

Component 1 is expensive and run occasionally (it re-runs the whole state).
Component 2 is cheap, static, and updated every time the surface is refreshed.
The **only contract between them** is `app/data/yield-surface.csv` (plus the
boundary CSVs) — regenerate with `simulation/03-export-app-data.R` and the app
picks it up.

---

## Component 1 — simulation engine

A small, self-contained pipeline that reproduces the yield surface from scratch:
it **downloads** its own weather and soil, runs APSIM Next Gen across the
Arkansas cropland grid (~4,651 cultivated cells, 1985–2024), and aggregates the
results. No pre-staged data files required.

```r
# From simulation/ — run the whole thing:
Rscript run-all.R
# …or step by step:
Rscript 01-get-weather-soil.R   # NASA POWER weather + USDA SSURGO soil (cached)
Rscript 02-run-apsim.R          # APSIM across cells × scenarios (parallel)
Rscript 03-export-app-data.R    # aggregate → app/data/yield-surface.csv
```

Every step is **resumable** (weather/soil are cached per cell; APSIM results are
checkpointed per chunk). APSIM itself installs from the `.deb` shipped in the
climate-change study's `installers/` — so the whole pipeline runs on a plain
Linux cloud box. See [`simulation/README.md`](simulation/README.md) for setup.

### Scenarios — add or remove your own

Scenarios live in a single editable table in **`simulation/config.R`**. Each row
is one scenario; the pipeline and the app adapt to whatever rows you define:

| name                      | cultivar   | sow_date | co2 | warming_C |
|---------------------------|------------|----------|-----|-----------|
| baseline                  | PurcellMG4 | 22-May   | 350 | 0         |
| early_sowing              | PurcellMG4 | 24-Apr   | 350 | 0         |
| longer_mat                | PurcellMG5 | 22-May   | 350 | 0         |
| early_sowing_longer_mat   | PurcellMG5 | 24-Apr   | 350 | 0         |

To explore another sowing date or maturity group, add a row (e.g.
`PurcellMG6`, `05-Jun`) — the template ships MG4/MG5/MG6 cultivars. `warming_C`
adds °C to daily min/max temperature (0 = current climate); `co2` sets the
atmosphere. That's the whole knob set.

---

## Component 2 — the interactive tool (R Shiny + ggplot2)

A single-file Shiny app (`app/app.R`). The grower:

1. Types their field's **latitude / longitude**.
2. Selects **maturity group** and **planting date** (their practice).
3. Enters **their own yield** (bu/ac or kg/ha).

The app finds the nearest simulated grid cell and shows:

- A **boxplot** of the simulated 40-year yield distribution for the grower's
  selected practice, the grower's reported yield as a **bar**, and a right-hand
  **summary card** (always in **bu/ac**) with the potential (simulated mean),
  real (reported) and **yield gap**. The y-axis is fixed at **0–120 bu/ac**.
- An **interactive Leaflet map** (pan/zoom, map/satellite basemap) of the
  cardinal-red yield surface across the **eastern Arkansas** soybean region
  (western cells dropped); click the map to drop a pin and locate a field.
- A narrative summary of the simulated mean, its typical range, and the gap.

The interface is styled in **University of Arkansas cardinal (#9D2235)** so the
map and figure can be embedded directly in a university web page.

**Grain moisture:** APSIM reports `Yield_kgha` as *dry* grain (0% moisture).
Bushels are a market unit defined at **13% moisture**, so the app grosses the
simulated yields up to 13% before display — putting them on the same basis as a
grower's measured, market-moisture yield (1 bu/ac = 67.25 kg/ha at 13%).

> This first version focuses on the **current-climate baseline**. The warming
> (+2 °C) scenarios are still produced by the simulation and can be layered back
> into the app when needed.

### Run locally

```r
# install.packages(c("shiny", "bslib", "ggplot2"))
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

- Re-enable the **+2 °C warming** scenarios in the app (already produced by the
  pipeline) for a "now vs. future best-practice" view.
- More levers in `config.R`: row spacing, irrigation, additional maturity groups.
- On-demand single-point APSIM run for a farmer's exact coordinates (server mode).
- Historical NASS county yields overlaid for validation.

Because the app only depends on `yield-surface.csv`, any of these can be added by
extending the export without touching the app — or by extending the app without
re-running the simulation.
