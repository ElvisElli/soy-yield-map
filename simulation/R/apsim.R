## R/apsim.R — build and run one APSIM soybean simulation per cell × scenario.

suppressPackageStartupMessages({
  library(apsimx)
})

## Locate the APSIM "Models" executable and point apsimx at it.
## Works on Linux (installed from the .deb under /usr/local/lib/apsim) and on
## Windows (APSIM under %LOCALAPPDATA%\Programs). Returns the exe path.
init_apsim <- function() {
  cand <- character(0)
  if (.Platform$OS.type == "unix") {
    cand <- Sys.glob(c("/usr/local/lib/apsim/*/bin/Models",
                       "/usr/local/bin/Models", "/opt/apsim/*/bin/Models"))
  } else {
    local_app <- Sys.getenv("LOCALAPPDATA",
                            file.path(Sys.getenv("USERPROFILE"), "AppData", "Local"))
    cand <- Sys.glob(c(file.path(local_app, "Programs", "APSIM*", "bin", "Models.exe"),
                       "C:/Program Files/APSIM*/bin/Models.exe"))
  }
  cand <- cand[file.exists(cand)]
  if (!length(cand))
    stop("APSIM 'Models' executable not found. Install APSIM (on Linux: the .deb ",
         "in installers/) and re-run.")
  exe <- sort(cand, decreasing = TRUE)[1]           # newest version
  apsimx::apsimx_options(exe.path = exe, warn.versions = FALSE)
  exe
}

## Edit one property/parameter by full path (thin wrapper for readability).
.set <- function(file, dir, path, value) {
  edit_apsimx(file, src.dir = dir, wrt.dir = dir, node = "Other",
              parm.path = path, value = value, overwrite = TRUE, verbose = FALSE)
}

## Build a ready-to-run .apsimx for one cell × scenario in `dir`.
## Returns the .apsimx filename (relative to dir).
FIELD <- ".Simulations.Simulation.Field"

build_cell <- function(template, dir, scenario, met_path, soil,
                       date_start, date_end) {
  file.copy(template, file.path(dir, "sim.apsimx"), overwrite = TRUE)

  ## Clock
  edit_apsimx("sim.apsimx", src.dir = dir, wrt.dir = dir, node = "Clock",
              parm = "Start", value = date_start, overwrite = TRUE, verbose = FALSE)
  edit_apsimx("sim.apsimx", src.dir = dir, wrt.dir = dir, node = "Clock",
              parm = "End", value = date_end, overwrite = TRUE, verbose = FALSE)

  ## Management + environment
  .set("sim.apsimx", dir, paste0(FIELD, ".SowSoybean.CultivarName"), scenario$cultivar)
  .set("sim.apsimx", dir, paste0(FIELD, ".SowSoybean.SowDate"),      scenario$sow_date)
  .set("sim.apsimx", dir, paste0(FIELD, ".SowSoybean.RowSpacing"),   scenario$row_spacing)
  .set("sim.apsimx", dir, paste0(FIELD, ".CO2.CO2"),                 scenario$co2)
  ## ClimateController: warming_C added to min & max temperature (0 = current)
  .set("sim.apsimx", dir, paste0(FIELD, ".ClimateController.MaxTAddition"), scenario$warming_C)
  .set("sim.apsimx", dir, paste0(FIELD, ".ClimateController.MinTAddition"), scenario$warming_C)

  ## Soil profile
  edit_apsimx_replace_soil_profile("sim.apsimx", src.dir = dir, wrt.dir = dir,
                                   soil.profile = soil, overwrite = TRUE, verbose = FALSE)

  ## Weather
  edit_apsimx("sim.apsimx", src.dir = dir, wrt.dir = dir, node = "Weather",
              value = normalizePath(met_path), overwrite = TRUE, verbose = FALSE)

  "sim.apsimx"
}

## Run one built .apsimx and return its results data.frame (or NULL on failure).
run_cell <- function(apsimx_file, dir) {
  out <- tryCatch(
    apsimx(apsimx_file, src.dir = dir, cleanup = TRUE, silent = TRUE),
    error = function(e) NULL)
  if (is.null(out) || !nrow(out)) return(NULL)
  out
}

## Simulate every scenario for ONE cell using its cached weather + soil.
## Returns a tidy data.frame (cellid, x, y, scenario meta, Date, Yield_kgha) or
## NULL. Fully self-contained (all inputs are arguments) so it runs unchanged on
## a PSOCK worker (Windows) or a fork (Linux) — the cell's weather/soil must
## already be cached by 01-get-weather-soil.R.
run_one_cell <- function(cell, scenarios, template, date_start, date_end,
                         weather_dir, soil_dir) {
  met   <- file.path(weather_dir, paste0(cell$cellid, ".met"))
  soilf <- file.path(soil_dir,    paste0(cell$cellid, ".rds"))
  if (!file.exists(met) || !file.exists(soilf)) return(NULL)
  soil <- readRDS(soilf)

  rows <- lapply(seq_len(nrow(scenarios)), function(s) {
    sc  <- scenarios[s, ]
    dir <- tempfile(paste0("cell", cell$cellid, "_"))
    dir.create(dir, showWarnings = FALSE)
    on.exit(unlink(dir, recursive = TRUE), add = TRUE)
    f <- tryCatch(build_cell(template, dir, sc, met, soil, date_start, date_end),
                  error = function(e) NULL)
    if (is.null(f)) return(NULL)
    res <- run_cell(f, dir)
    if (is.null(res)) return(NULL)
    date_col <- grep("Clock.Today$|^Date$", names(res), value = TRUE)[1]
    data.frame(
      cellid = cell$cellid, x = cell$lon, y = cell$lat,
      cultivar = sc$cultivar, sowing = sc$sow_date, scenario = sc$name,
      climate.control = sc$climate.control, co2 = sc$co2,
      Date = as.Date(res[[date_col]]), Yield_kgha = res$Yield_kgha,
      stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  if (is.null(out) || !nrow(out)) NULL else out
}
