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
})

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

IN_RDS  <- file.path(ROOT, "simulation", "data", "outputs", "simulated-scenarios-df.rds")
OUT_CSV <- file.path(ROOT, "app", "data", "yield-surface.csv")
OUT_META<- file.path(ROOT, "app", "data", "yield-surface-meta.json")

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
    yield_p10_kgha  = round(stats::quantile(Yield_kgha, 0.10, names = FALSE), 1),
    yield_p90_kgha  = round(stats::quantile(Yield_kgha, 0.90, names = FALSE), 1),
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

## ── Write outputs ────────────────────────────────────────────────────────
dir.create(dirname(OUT_CSV), recursive = TRUE, showWarnings = FALSE)
readr::write_csv(surface, OUT_CSV)
message("[export] wrote ", OUT_CSV, " (", round(file.size(OUT_CSV) / 1024), " KB)")

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
