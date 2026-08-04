## ============================================================
## 01-get-weather-soil.R
## Download and CONDITION the weather and soil for every grid cell, caching the
## result so 02 can just read it. Fully resumable — cells already on disk are
## skipped, so it is safe to re-run after an interruption.
##
##   weather  NASA POWER daily         -> data/raw/weather/<cellid>.met
##   soil     USDA SSURGO, conditioned -> data/raw/soil/<cellid>.rds  (FINAL)
##
## ALL soil adaptations live in condition_soil() below, so the cached .rds is the
## finished, ready-to-simulate profile. These are ported verbatim from the
## climate-change study's 01-simulation.R:
##   1. KS  — saturated conductivity decreases with depth
##   2. fix — reconcile SAT / bulk density / DUL (apsimx)
##   3. KL  — root water-extraction, depth-decaying   (KL_VEC in config.R)
##   4. XF  — root exploration factor / rooting cap   (XF_VEC in config.R)
##   5. initial water at drained upper limit; crops = Soybean/Wheat/Maize
##
## NOTE: if you change KS/KL/XF or the root vectors, delete data/raw/soil/ so the
## profiles are re-conditioned on the next run (cached cells are otherwise kept).
##
## Run:  Rscript 01-get-weather-soil.R      (from simulation/)
## ============================================================

## set the working directory to the component root (folder with code/ input/ output/)
local({
  a <- commandArgs(FALSE); f <- grep("^--file=", a, value = TRUE)
  d <- if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1]))) else getwd()
  while (!file.exists(file.path(d, "code", "config.R")) && dirname(d) != d) d <- dirname(d)
  setwd(d)
})
source("code/config.R")
source("code/R/data.R")
suppressPackageStartupMessages(library(apsimx))
options(timeout = 300)

## ── WEATHER ──────────────────────────────────────────────────────────────
## Download (or reuse) a NASA POWER daily weather file -> <cellid>.met.
get_weather <- function(cellid, lon, lat, years, dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  met_path <- file.path(dir, paste0(cellid, ".met"))
  if (file.exists(met_path)) return(met_path)
  dates <- c(sprintf("%d-01-01", years[1]), sprintf("%d-12-31", years[2]))
  met <- get_power_apsim_met(lonlat = c(lon, lat), dates = dates)
  write_apsim_met(met, wrt.dir = dir, filename = paste0(cellid, ".met"))
  met_path
}

## ── SOIL CONDITIONING (all soil edits are here) ──────────────────────────
## Map a per-layer vector onto an N-layer profile: use the first N values; if
## the profile has more layers than the vector, repeat the last value.
fit_layers <- function(v, n) {
  if (n <= length(v)) v[seq_len(n)] else c(v, rep(v[length(v)], n - length(v)))
}

## Turn a raw SSURGO profile into the study's FINAL soybean profile.
condition_soil <- function(sp) {
  ## 1. Saturated hydraulic conductivity (KS) decreases with depth
  if (!is.null(sp$soil$KS)) {
    ks_max <- max(sp$soil$KS, na.rm = TRUE)
    sp$soil$KS <- ks_max * exp(seq(0, log(1e-4), length.out = length(sp$soil$KS)))
  }
  ## 2. Reconcile SAT / bulk density / DUL (apsimx sanity fix)
  sp <- apsimx:::fix_apsimx_soil_profile(sp, verbose = FALSE)
  ## 3. Root water-extraction (KL) and exploration factor (XF), depth-decaying.
  ##    Baked into every crop so the profile written by 02 carries them directly.
  n_lay <- nrow(sp$soil)
  kl <- fit_layers(KL_VEC, n_lay); xf <- fit_layers(XF_VEC, n_lay)
  for (crop in c("Soybean", "Maize", "Wheat")) {
    if (paste0(crop, ".KL") %in% names(sp$soil)) sp$soil[[paste0(crop, ".KL")]] <- kl
    if (paste0(crop, ".XF") %in% names(sp$soil)) sp$soil[[paste0(crop, ".XF")]] <- xf
  }
  ## 4. Start each season with the profile at drained upper limit
  sp$initialwater <- initialwater_parms(
    Depth = sp$soil$Depth, Thickness = sp$soil$Thickness, InitialValues = sp$soil$DUL)
  ## 5. Ensure the crops we simulate are present
  sp$crops <- unique(c(sp$crops, "Soybean", "Wheat", "Maize"))
  sp
}

## Download (or reuse) a SSURGO profile, condition it, and cache -> <cellid>.rds.
get_soil <- function(cellid, lon, lat, dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  rds_path <- file.path(dir, paste0(cellid, ".rds"))
  if (file.exists(rds_path)) return(rds_path)
  sp <- get_ssurgo_soil_profile(lonlat = c(lon, lat), nsoil = 1)[[1]]
  saveRDS(condition_soil(sp), rds_path)
  rds_path
}

## ── ACQUIRE EVERY CELL ───────────────────────────────────────────────────
cells <- load_grid(GRID_FILE, N_CELLS)
message(sprintf("[01] %d cells to acquire | weather -> %s | soil -> %s",
                nrow(cells), WEATHER_DIR, SOIL_DIR))

ok_w <- ok_s <- 0L; fail <- character(0)
for (i in seq_len(nrow(cells))) {
  cl <- cells[i, ]
  w <- tryCatch(get_weather(cl$cellid, cl$lon, cl$lat, WEATHER_YEARS, WEATHER_DIR),
                error = function(e) { fail <<- c(fail, sprintf("cell %d weather: %s", cl$cellid, conditionMessage(e))); NULL })
  s <- tryCatch(get_soil(cl$cellid, cl$lon, cl$lat, SOIL_DIR),
                error = function(e) { fail <<- c(fail, sprintf("cell %d soil: %s", cl$cellid, conditionMessage(e))); NULL })
  ok_w <- ok_w + !is.null(w); ok_s <- ok_s + !is.null(s)
  if (i %% 25 == 0 || i == nrow(cells))
    message(sprintf("[01] %d/%d  weather ok=%d  soil ok=%d  failed=%d",
                    i, nrow(cells), ok_w, ok_s, length(fail)))
}

if (length(fail)) {
  message("[01] ", length(fail), " problems (will be retried on next run):")
  message(paste(" -", head(fail, 10)), sep = "\n")
}
message("[01] DONE — weather cached; soil cached as FINAL conditioned profiles.")
