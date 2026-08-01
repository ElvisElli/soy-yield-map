## ============================================================
## app/R/apsim-generate.R
## Turn a lon/lat into a ready-to-run APSIM Next Gen simulation, with USDA-SSURGO
## soil and NASA-POWER weather (daily, historical to ~today) baked onto the
## study's soybean template. The deliverable is a small .zip:
##
##     <name>.apsimx   — soil embedded, chosen cultivar + sow date, clock to now
##     weather.met     — NASA POWER daily weather (referenced relatively)
##
## Open the .apsimx in APSIM NG, or run it headless:  Models <name>.apsimx
##
## WHERE THIS RUNS
##   Anywhere the `apsimx` R package is installed — your computer, or a Shiny
##   server. It does NOT run on the static shinylive / WebAssembly site: that
##   has no server-side R, and a browser can't reach the SSURGO / POWER APIs.
##   The app detects that case (IS_WASM) and hands the visitor the portable
##   script (scripts/make-apsim.R) to run locally instead.
##
## DESIGN NOTE
##   `apsimx` (and `zip`) are referenced through variables, never as a literal
##   library()/requireNamespace("apsimx") call, so shinylive's dependency
##   scanner does not try to bundle them into the WebAssembly build (which would
##   fail — neither is available in webR).
## ============================================================

## TRUE when running inside webR / shinylive (the static site).
IS_WASM <- identical(R.version[["arch"]], "wasm32")

## NASA POWER daily has a few days' latency; don't ask for dates past this.
POWER_LATENCY_DAYS <- 3L

## Raw template location, used only as a last resort by the portable script when
## no local template is found (the app and the repo both ship one on disk).
TEMPLATE_RAW_URL <- paste0(
  "https://raw.githubusercontent.com/ElvisElli/soy-yield-map/main/",
  "app/templates/soybean-mg4-baseline.apsimx")

## Resolve an apsimx export (or internal) without a literal `apsimx::` /
## requireNamespace("apsimx") — keeps apsimx out of the shinylive bundle.
.aps <- function(name, internal = FALSE) {
  pkg <- paste0("aps", "imx")                     # variable → not a scanned dep
  if (!requireNamespace(pkg, quietly = TRUE))
    stop("The 'apsimx' package is required to generate APSIM files.\n",
         "Install it in R with:  install.packages(\"apsimx\")", call. = FALSE)
  if (internal) getFromNamespace(name, pkg) else getExportedValue(pkg, name)
}

## English month abbreviations — APSIM sow dates are "dd-mmm", locale-free.
.MONTHS <- c("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec")

## Date (or "YYYY-MM-DD") -> APSIM "dd-mmm" (e.g. "22-May"). Year is ignored.
to_apsim_date <- function(d) {
  d <- as.Date(d)
  sprintf("%d-%s", as.integer(format(d, "%d")),
          .MONTHS[as.integer(format(d, "%m"))])
}

## Find the soybean template on disk; fall back to the repo copy (portable use).
template_path <- function() {
  cands <- c("templates/soybean-mg4-baseline.apsimx",
             "app/templates/soybean-mg4-baseline.apsimx",
             "../app/templates/soybean-mg4-baseline.apsimx",
             "../simulation/templates/soybean-mg4-baseline.apsimx",
             "simulation/templates/soybean-mg4-baseline.apsimx")
  hit <- cands[file.exists(cands)]
  if (length(hit)) return(normalizePath(hit[1]))
  dest <- file.path(tempdir(), "soybean-mg4-baseline.apsimx")
  if (!file.exists(dest))
    utils::download.file(TEMPLATE_RAW_URL, dest, quiet = TRUE, mode = "wb")
  dest
}

## Condition a raw SSURGO profile for APSIM soybean runs (mirrors the pipeline's
## prepare_soil): decreasing Ks with depth, initial water at DUL, crop list.
.prepare_soil <- function(sp) {
  fix <- .aps("fix_apsimx_soil_profile", internal = TRUE)
  iw  <- .aps("initialwater_parms")
  sp <- fix(sp, verbose = FALSE)
  if (!is.null(sp$soil$KS)) {
    ks_max <- max(sp$soil$KS, na.rm = TRUE)
    sp$soil$KS <- ks_max * exp(seq(0, log(1e-4), length.out = length(sp$soil$KS)))
  }
  sp$initialwater <- iw(Depth = sp$soil$Depth, Thickness = sp$soil$Thickness,
                        InitialValues = sp$soil$DUL)
  sp$crops <- unique(c(sp$crops, "Soybean", "Wheat", "Maize"))
  sp
}

## Zip `files` (kept flat) into `zipfile`, preferring the pure-C `zip` package
## and falling back to the system zip. `zip` is referenced via a variable so it
## is not pulled into the shinylive bundle.
.make_zip <- function(zipfile, files) {
  root <- dirname(files[1]); rel <- basename(files)
  old <- setwd(root); on.exit(setwd(old), add = TRUE)
  zpkg <- "zip"
  if (requireNamespace(zpkg, quietly = TRUE)) {
    getExportedValue(zpkg, "zipr")(zipfile, rel)
  } else {
    utils::zip(zipfile, rel, flags = "-j9Xq")
  }
  zipfile
}

## Build the two-file bundle (sim.apsimx + weather.met) in `out_dir`.
## Returns the paths. `progress(fraction, message)` is called if supplied.
generate_apsimx_bundle <- function(lat, lon, out_dir,
                                   name       = "soybean",
                                   cultivar   = "PurcellMG4",
                                   sow_date   = "22-May",
                                   start_year = 1985L,
                                   end_date   = Sys.Date() - POWER_LATENCY_DAYS,
                                   co2        = 420,
                                   row_spacing = 750,
                                   template   = template_path(),
                                   progress   = NULL) {
  step <- function(p, m) if (is.function(progress)) progress(p, m)
  if (!is.finite(lat) || !is.finite(lon))
    stop("Latitude and longitude must be numbers.", call. = FALSE)
  if (is.null(template) || !file.exists(template))
    stop("APSIM template not found.", call. = FALSE)

  get_power <- .aps("get_power_apsim_met")
  write_met <- .aps("write_apsim_met")
  impute    <- .aps("impute_apsim_met")
  get_soil  <- .aps("get_ssurgo_soil_profile")
  edit      <- .aps("edit_apsimx")
  edit_soil <- .aps("edit_apsimx_replace_soil_profile")

  end_date   <- as.Date(end_date)
  date_start <- sprintf("%04d-01-01", as.integer(start_year))
  date_end   <- format(end_date, "%Y-%m-%d")

  work <- tempfile("apsimgen_"); dir.create(work, recursive = TRUE)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)

  ## 1) Weather — NASA POWER daily -> weather.met
  ## POWER's near-real-time tail can miss a day of radiation; APSIM rejects any
  ## gap, so we impute missing values and clamp the clock to the last weather
  ## day (never simulate past the weather record).
  step(0.10, "Downloading NASA POWER weather…")
  met <- get_power(lonlat = c(lon, lat), dates = c(date_start, date_end))
  met <- tryCatch(impute(met), error = function(e) met)
  mdf <- as.data.frame(met)
  last_wx <- suppressWarnings(max(as.Date(paste(mdf$year, mdf$day), "%Y %j"),
                                  na.rm = TRUE))
  if (is.finite(last_wx)) date_end <- format(min(end_date, last_wx), "%Y-%m-%d")
  write_met(met, wrt.dir = work, filename = "weather.met")
  met_path <- file.path(work, "weather.met")

  ## 2) Soil — USDA SSURGO -> conditioned profile (embedded in the .apsimx)
  step(0.45, "Downloading USDA SSURGO soil…")
  soil <- .prepare_soil(get_soil(lonlat = c(lon, lat), nsoil = 1)[[1]])

  ## 3) Assemble the .apsimx from the template
  step(0.72, "Assembling APSIM file…")
  file.copy(template, file.path(work, "sim.apsimx"), overwrite = TRUE)
  FIELD <- ".Simulations.Simulation.Field"
  set <- function(path, value)
    edit("sim.apsimx", src.dir = work, wrt.dir = work, node = "Other",
         parm.path = path, value = value, overwrite = TRUE, verbose = FALSE)

  edit("sim.apsimx", src.dir = work, wrt.dir = work, node = "Clock",
       parm = "Start", value = date_start, overwrite = TRUE, verbose = FALSE)
  edit("sim.apsimx", src.dir = work, wrt.dir = work, node = "Clock",
       parm = "End",   value = date_end,   overwrite = TRUE, verbose = FALSE)
  set(paste0(FIELD, ".SowSoybean.CultivarName"), cultivar)
  set(paste0(FIELD, ".SowSoybean.SowDate"),      sow_date)
  set(paste0(FIELD, ".SowSoybean.RowSpacing"),   row_spacing)
  set(paste0(FIELD, ".CO2.CO2"),                 co2)
  set(paste0(FIELD, ".ClimateController.MaxTAddition"), 0)
  set(paste0(FIELD, ".ClimateController.MinTAddition"), 0)
  edit_soil("sim.apsimx", src.dir = work, wrt.dir = work,
            soil.profile = soil, overwrite = TRUE, verbose = FALSE)
  edit("sim.apsimx", src.dir = work, wrt.dir = work, node = "Weather",
       value = normalizePath(met_path), overwrite = TRUE, verbose = FALSE)

  ## Make the weather reference relative ("weather.met") so the bundle is
  ## portable — APSIM resolves it next to the .apsimx.
  txt  <- readLines(file.path(work, "sim.apsimx"), warn = FALSE)
  abs1 <- normalizePath(met_path)                       # forward slashes (unix)
  abs2 <- gsub("/", "\\\\", abs1)                       # backslashes (windows)
  txt  <- gsub(abs1, "weather.met", txt, fixed = TRUE)
  txt  <- gsub(gsub("\\\\", "\\\\\\\\", abs2), "weather.met", txt, fixed = TRUE)
  writeLines(txt, file.path(work, "sim.apsimx"))

  ## 4) Move into out_dir with a friendly stem
  step(0.95, "Writing files…")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  apsimx_out <- file.path(out_dir, paste0(name, ".apsimx"))
  met_out    <- file.path(out_dir, "weather.met")
  file.copy(file.path(work, "sim.apsimx"), apsimx_out, overwrite = TRUE)
  file.copy(met_path,                      met_out,    overwrite = TRUE)
  step(1, "Done")
  c(apsimx = apsimx_out, met = met_out)
}

## Convenience wrapper: build the bundle and zip it into `zip_file`.
generate_apsimx_zip <- function(lat, lon, zip_file, name = "soybean", ...) {
  stage <- tempfile("apsimzip_"); dir.create(stage, recursive = TRUE)
  on.exit(unlink(stage, recursive = TRUE), add = TRUE)
  files <- generate_apsimx_bundle(lat, lon, out_dir = stage, name = name, ...)
  .make_zip(normalizePath(zip_file, mustWork = FALSE), unname(files))
  zip_file
}
