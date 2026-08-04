## R/apsim.R — build & run ONE in-season APSIM simulation per cell × scenario,
## returning the DAILY soil-water time series. Self-contained so it runs unchanged
## on a PSOCK worker (Windows) or a fork (Linux).

suppressPackageStartupMessages(library(apsimx))

## Locate the APSIM "Models" executable and point apsimx at it.
init_apsim <- function() {
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
    stop("APSIM 'Models' executable not found. Install APSIM and re-run.")
  exe <- sort(cand, decreasing = TRUE)[1]
  apsimx::apsimx_options(exe.path = exe, warn.versions = FALSE)
  exe
}

.set <- function(file, dir, path, value)
  edit_apsimx(file, src.dir = dir, wrt.dir = dir, node = "Other",
              parm.path = path, value = value, overwrite = TRUE, verbose = FALSE)

FIELD <- ".Simulations.Simulation.Field"

## Build a ready-to-run daily .apsimx for one cell × scenario in `dir`.
build_cell <- function(template, dir, scenario, met_path, soil, date_start, date_end) {
  file.copy(template, file.path(dir, "sim.apsimx"), overwrite = TRUE)
  edit_apsimx("sim.apsimx", src.dir = dir, wrt.dir = dir, node = "Clock",
              parm = "Start", value = date_start, overwrite = TRUE, verbose = FALSE)
  edit_apsimx("sim.apsimx", src.dir = dir, wrt.dir = dir, node = "Clock",
              parm = "End", value = date_end, overwrite = TRUE, verbose = FALSE)
  .set("sim.apsimx", dir, paste0(FIELD, ".SowSoybean.CultivarName"), scenario$cultivar)
  .set("sim.apsimx", dir, paste0(FIELD, ".SowSoybean.SowDate"),      scenario$sow_date)
  .set("sim.apsimx", dir, paste0(FIELD, ".SowSoybean.RowSpacing"),   scenario$row_spacing)
  .set("sim.apsimx", dir, paste0(FIELD, ".CO2.CO2"),                 scenario$co2)
  .set("sim.apsimx", dir, paste0(FIELD, ".ClimateController.MaxTAddition"), scenario$warming_C)
  .set("sim.apsimx", dir, paste0(FIELD, ".ClimateController.MinTAddition"), scenario$warming_C)
  edit_apsimx_replace_soil_profile("sim.apsimx", src.dir = dir, wrt.dir = dir,
                                   soil.profile = soil, overwrite = TRUE, verbose = FALSE)
  edit_apsimx("sim.apsimx", src.dir = dir, wrt.dir = dir, node = "Weather",
              value = normalizePath(met_path), overwrite = TRUE, verbose = FALSE)
  "sim.apsimx"
}

## Columns kept from the daily report (the soil-water tracker).
DAILY_KEEP <- c("rel_sw_6in", "rel_sw_12in", "rel_sw_24in",
                "swhc_6in", "swhc_12in", "swhc_24in",
                "CummRain_fromApril", "Yield_kgha", "Biomass_kgha")

## Simulate every scenario for ONE cell and return a tidy DAILY data.frame.
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
    res <- tryCatch(apsimx(f, src.dir = dir, cleanup = TRUE, silent = TRUE),
                    error = function(e) NULL)
    if (is.null(res) || !nrow(res)) return(NULL)
    date_col <- grep("Clock.Today$|^Date$", names(res), value = TRUE)[1]
    keep <- intersect(DAILY_KEEP, names(res))
    data.frame(
      cellid = cell$cellid, x = cell$lon, y = cell$lat,
      scenario = sc$name, date = as.Date(res[[date_col]]),
      res[, keep, drop = FALSE], stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  if (is.null(out) || !nrow(out)) NULL else out
}
