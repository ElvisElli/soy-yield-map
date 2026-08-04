## R/apsim.R — build & run ONE in-season APSIM simulation per cell × scenario,
## returning the DAILY soil-water time series. Self-contained so it runs unchanged
## on a PSOCK worker (Windows) or a fork (Linux).

suppressPackageStartupMessages(library(apsimx))

## Daily report variables for the in-season soil-water tracker.
.DAILY_REPORT_VARS <- c(
  "[Clock].Today",
  "([Soil].SoilWater.SW[1]) - ([Soil].Physical.LL15[1]) as sw1",
  "([Soil].SoilWater.SW[2]) - ([Soil].Physical.LL15[2]) as sw2",
  "([Soil].SoilWater.SW[3]) - ([Soil].Physical.LL15[3]) as sw3",
  "([Soil].SoilWater.SW[4]) - ([Soil].Physical.LL15[4]) as sw4",
  "([Soil].SoilWater.SW[5]) - ([Soil].Physical.LL15[5]) as sw5",
  "([Soil].SoilWater.SW[6]) - ([Soil].Physical.LL15[6]) as sw6",
  "([Soil].Physical.SAT[1]) - ([Soil].Physical.LL15[1]) as sat1",
  "([Soil].Physical.SAT[2]) - ([Soil].Physical.LL15[2]) as sat2",
  "([Soil].Physical.SAT[3]) - ([Soil].Physical.LL15[3]) as sat3",
  "([Soil].Physical.SAT[4]) - ([Soil].Physical.LL15[4]) as sat4",
  "([Soil].Physical.SAT[5]) - ([Soil].Physical.LL15[5]) as sat5",
  "([Soil].Physical.SAT[6]) - ([Soil].Physical.LL15[6]) as sat6",
  "sw1/sat1 as r1", "sw2/sat2 as r2", "sw3/sat3 as r3",
  "sw4/sat4 as r4", "sw5/sat5 as r5", "sw6/sat6 as r6",
  "(r1*2 + r2*1)/3 as rel_sw_6in",
  "(r1+r2+r3)/3 as rel_sw_12in",
  "(r1+r2+r3+r4+r5+r6)/6 as rel_sw_24in",
  "[Soil].Physical.SoybeanSoil.PAWCmm[1] as swhc1",
  "[Soil].Physical.SoybeanSoil.PAWCmm[2] as swhc2",
  "[Soil].Physical.SoybeanSoil.PAWCmm[3] as swhc3",
  "[Soil].Physical.SoybeanSoil.PAWCmm[4] as swhc4",
  "[Soil].Physical.SoybeanSoil.PAWCmm[5] as swhc5",
  "[Soil].Physical.SoybeanSoil.PAWCmm[6] as swhc6",
  "(swhc1 + swhc2*0.5)/2.54 as swhc_6in",
  "(swhc1+swhc2+swhc3)/2.54 as swhc_12in",
  "(swhc1+swhc2+swhc3+swhc4+swhc5+swhc6)/2.54 as swhc_24in",
  "sum of [Weather].Rain from 1-Apr to 31-Dec as CummRain_fromApril",
  "max of [Soybean].Grain.Wt * 10 from [Soybean].Sowing to [Soybean].Harvesting as Yield_kgha",
  "[Soybean].AboveGround.Wt * 10 as Biomass_kgha")

## Derive the DAILY soil-water template from the shared historical base template
## (so there is ONE maintained .apsimx). Switches every Report node to fire daily
## and report the soil-water variables. Cached: only rebuilt if the base changed.
build_daily_template <- function(base, out) {
  if (!file.exists(base)) stop("Base template not found: ", base)
  if (file.exists(out) && file.info(out)$mtime >= file.info(base)$mtime) return(out)
  j <- jsonlite::read_json(base, simplifyVector = FALSE)
  vars <- as.list(.DAILY_REPORT_VARS)
  set_reports <- function(node) {
    if (is.list(node)) {
      if (!is.null(node[["$type"]]) && grepl("Models\\.Report", node[["$type"]])) {
        node[["EventNames"]]    <- list("[Clock].EndOfDay")
        node[["VariableNames"]] <- vars
      }
      if (!is.null(node[["Children"]]))
        node[["Children"]] <- lapply(node[["Children"]], set_reports)
    }
    node
  }
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(set_reports(j), out, auto_unbox = TRUE, pretty = TRUE,
                       null = "null", digits = NA)
  out
}

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
