## ============================================================
## export-app-data.R
## COMPONENT 1 -> COMPONENT 2 bridge.
##
## Reads the full APSIM grid simulation results and aggregates them
## into a compact per-cell, per-practice "yield surface" that the Shiny
## app (app/) reads. This is the ONLY file the app depends on.
##
## Input : simulation/data/outputs/simulated-scenarios-df.rds
##           (an unnamed list of per-scenario data.frames, or a single
##            data.frame — both are handled)
## Output: app/data/yield-surface.csv        (committed, small)
##         app/data/yield-surface-meta.json  (provenance for the app footer)
##
## Run (from repo root):
##   Rscript simulation/export-app-data.R
## ============================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(sf)
})

## Projected CRS used by the manuscript maps (NAD83 / Conus Albers, metres)
ALBERS <- 5070

## ── Locate repo root (works from repo root or from simulation/) ──────────
find_root <- function() {
  cand <- c(".", "..")
  for (d in cand) {
    if (file.exists(file.path(d, "app", "app.R"))) return(normalizePath(d))
  }
  ## fall back to the directory this script lives in, one level up
  args <- commandArgs(FALSE)
  fa   <- grep("^--file=", args, value = TRUE)
  if (length(fa)) {
    here <- dirname(normalizePath(sub("^--file=", "", fa[1])))
    return(normalizePath(file.path(here, "..")))
  }
  normalizePath(".")
}
ROOT <- find_root()
message("[export] repo root: ", ROOT)

IN_RDS  <- file.path(ROOT, "simulation", "output", "simulated-scenarios-df.rds")
CROP    <- file.path(ROOT, "simulation", "input", "cropland")
STATE_SHP    <- file.path(CROP, "cb_2018_us_state_20m", "cb_2018_us_state_20m.shp")
COUNTY_SHP   <- file.path(CROP, "Elvis-Crop-Data", "Arkansas_Counties_4269.shp")

## A test subset (master run.R sets SOY_N_CELLS) must NOT overwrite the real app
## data — write it to output/ instead. Only a full run publishes to app/data.
IS_TEST <- nzchar(Sys.getenv("SOY_N_CELLS"))
DEST    <- if (IS_TEST) file.path(ROOT, "simulation", "output") else file.path(ROOT, "app", "data")
if (IS_TEST) message("[export] TEST run — writing to simulation/output/ (app data untouched)")
OUT_CSV <- file.path(DEST, "yield-surface.csv")
OUT_META<- file.path(DEST, "yield-surface-meta.json")
OUT_STATE   <- file.path(DEST, "ar-state.csv")
OUT_COUNTY  <- file.path(DEST, "ar-counties.csv")

if (!file.exists(IN_RDS)) {
  stop("Simulation results not found:\n  ", IN_RDS,
       "\nRun the simulation first (simulation/code/01-simulation.R), or copy\n",
       "simulated-scenarios-df.rds from the climate-change study into that path.")
}

## ── Load & flatten ───────────────────────────────────────────────────────
message("[export] reading ", IN_RDS)
raw <- readRDS(IN_RDS)
if (is.data.frame(raw)) {
  df <- raw
} else if (is.list(raw)) {
  df <- dplyr::bind_rows(lapply(raw, as.data.frame))
} else {
  stop("Unexpected object class in results file: ", paste(class(raw), collapse = "/"))
}
message(sprintf("[export] %s rows x %s cols loaded", nrow(df), ncol(df)))

need <- c("cellid", "x", "y", "cultivar", "sowing", "scenario",
          "climate.control", "co2", "Yield_kgha")
miss <- setdiff(need, names(df))
if (length(miss)) stop("Results missing expected columns: ", paste(miss, collapse = ", "))

## ── Derive farmer-facing labels ──────────────────────────────────────────
## climate.control is the ClimateController EnableDate. When the warming shift
## is enabled from before the simulation window (1/1/1980) the run is +2 C; when
## it is enabled in the future (1/1/2025) no shift occurs -> current climate.
parse_year <- function(x) {
  x <- as.character(x)
  suppressWarnings(as.integer(sub(".*/(\\d{4})$", "\\1", x)))
}

df <- df %>%
  mutate(
    mg = dplyr::case_when(
      grepl("MG5", cultivar) ~ "MG5",
      grepl("MG4", cultivar) ~ "MG4",
      TRUE ~ as.character(cultivar)
    ),
    ## normalise sowing to a friendly planting window label
    plant_window = dplyr::case_when(
      grepl("Apr", sowing, ignore.case = TRUE) ~ "late April",
      grepl("May", sowing, ignore.case = TRUE) ~ "late May",
      TRUE ~ as.character(sowing)
    ),
    climate = ifelse(parse_year(climate.control) >= 2025, "current", "plus2C")
  )

## ── Aggregate across the 40-year record ──────────────────────────────────
message("[export] aggregating per cell x practice ...")
surface <- df %>%
  filter(!is.na(Yield_kgha)) %>%
  group_by(cellid, x, y, scenario, cultivar, mg, sowing, plant_window, climate, co2) %>%
  summarise(
    yield_mean_kgha = round(mean(Yield_kgha), 1),
    yield_sd_kgha   = round(stats::sd(Yield_kgha), 1),
    ## Full 5-number summary (+ p10/p90) so the app can draw boxplots and
    ## "year type" (bad / typical / good) breakdowns without shipping the raw
    ## 40-year series for every cell.
    yield_min_kgha  = round(min(Yield_kgha), 1),
    yield_p10_kgha  = round(stats::quantile(Yield_kgha, 0.10, names = FALSE), 1),
    yield_p25_kgha  = round(stats::quantile(Yield_kgha, 0.25, names = FALSE), 1),
    yield_median_kgha = round(stats::median(Yield_kgha), 1),
    yield_p75_kgha  = round(stats::quantile(Yield_kgha, 0.75, names = FALSE), 1),
    yield_p90_kgha  = round(stats::quantile(Yield_kgha, 0.90, names = FALSE), 1),
    yield_max_kgha  = round(max(Yield_kgha), 1),
    n_years         = dplyr::n(),
    .groups = "drop"
  ) %>%
  mutate(
    x = round(x, 5),
    y = round(y, 5)
  ) %>%
  arrange(scenario, co2, cellid)

message(sprintf("[export] surface: %s rows (%s cells, %s practices)",
                nrow(surface),
                dplyr::n_distinct(surface$cellid),
                dplyr::n_distinct(paste(surface$scenario, surface$co2))))

## ── Project cell centroids to Albers (matches manuscript maps) ────────────
message("[export] projecting cells to EPSG:", ALBERS, " ...")
cell_xy <- surface %>% distinct(cellid, x, y)
alb <- sf::st_as_sf(cell_xy, coords = c("x", "y"), crs = 4326) %>%
  sf::st_transform(ALBERS) %>%
  sf::st_coordinates()
cell_xy$x_alb <- round(alb[, 1], 1)
cell_xy$y_alb <- round(alb[, 2], 1)

## Tag each cell with its county (for the NASS county-yield benchmark overlay)
if (file.exists(COUNTY_SHP)) {
  suppressWarnings(sf::sf_use_s2(FALSE))
  cy <- sf::st_transform(sf::st_read(COUNTY_SHP, quiet = TRUE)["NAME"], 4326)
  pts <- sf::st_as_sf(cell_xy, coords = c("x", "y"), crs = 4326, remove = FALSE)
  cell_xy$county <- toupper(trimws(sf::st_join(pts, cy, join = sf::st_within)$NAME))
} else {
  cell_xy$county <- NA_character_
}
surface <- surface %>%
  left_join(cell_xy[c("cellid", "x_alb", "y_alb", "county")], by = "cellid")

## ── Write outputs ────────────────────────────────────────────────────────
dir.create(dirname(OUT_CSV), recursive = TRUE, showWarnings = FALSE)
readr::write_csv(surface, OUT_CSV)
message("[export] wrote ", OUT_CSV, " (", round(file.size(OUT_CSV) / 1024), " KB)")

## ── Fortify AR state + county boundaries to plain lon/lat data frames ─────
## Stored as lon (x) / lat (y) with a ring `group` so the Shiny app can draw
## them on the Leaflet map (as polylines) without needing the sf package.
fortify_sf <- function(geom) {
  co <- as.data.frame(sf::st_coordinates(geom))
  ## Build a unique ring id from whatever hierarchy columns are present
  idc <- intersect(c("L3", "L2", "L1"), names(co))
  co$group <- do.call(paste, c(co[idc], sep = "_"))
  data.frame(x = round(co$X, 5), y = round(co$Y, 5),
             group = co$group, stringsAsFactors = FALSE)
}

if (file.exists(STATE_SHP) && file.exists(COUNTY_SHP)) {
  ark <- sf::st_read(STATE_SHP, quiet = TRUE)
  ark <- ark[ark$STUSPS == "AR", ]
  ark <- sf::st_transform(ark, 4326)
  readr::write_csv(fortify_sf(sf::st_geometry(ark)), OUT_STATE)
  message("[export] wrote ", OUT_STATE)

  cty <- sf::st_read(COUNTY_SHP, quiet = TRUE)
  cty <- sf::st_transform(cty, 4326)
  ## Light simplification keeps the file small without visible loss at map scale
  cty <- sf::st_make_valid(cty)
  cty <- sf::st_simplify(cty, dTolerance = 0.003, preserveTopology = TRUE)
  cty_geom <- sf::st_collection_extract(sf::st_geometry(cty), "POLYGON")
  readr::write_csv(fortify_sf(cty_geom), OUT_COUNTY)
  message("[export] wrote ", OUT_COUNTY)
} else {
  message("[export] NOTE: boundary shapefiles not found — skipping state/county export")
}

year_range <- "1985-2024"
if ("Date" %in% names(df)) {
  yy <- suppressWarnings(as.integer(format(as.Date(df$Date), "%Y")))
  yy <- yy[is.finite(yy)]
  if (length(yy)) year_range <- paste(range(yy), collapse = "-")
}
meta <- sprintf(paste0(
  '{\n',
  '  "generated": "%s",\n',
  '  "n_cells": %d,\n',
  '  "n_rows": %d,\n',
  '  "years": "%s",\n',
  '  "scenarios": [%s],\n',
  '  "source": "APSIM Next Generation grid simulation (soybean-ar-climate-change)"\n',
  '}\n'),
  format(Sys.time(), "%Y-%m-%d"),
  dplyr::n_distinct(surface$cellid),
  nrow(surface),
  year_range,
  paste(sprintf('"%s"', sort(unique(surface$scenario))), collapse = ", ")
)
writeLines(meta, OUT_META)
message("[export] wrote ", OUT_META)
message("[export] DONE")
