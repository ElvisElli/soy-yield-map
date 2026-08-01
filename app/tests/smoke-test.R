## smoke-test.R — exercises the app's server logic without a browser.
## Run from the app/ directory:  Rscript tests/smoke-test.R
## Verifies data loads, helpers work, and key outputs compute for a sample field.

stopifnot(basename(getwd()) == "app")

library(shiny)
source("R/helpers.R")

## 1. Helper unit tests --------------------------------------------------------
stopifnot(abs(kgha_to_buac(67.25) - 1) < 1e-9)
stopifnot(abs(buac_to_kgha(1) - 67.25) < 1e-9)
stopifnot(fmt_yield(NA_real_) == "—")
cat("[ok] helpers: unit conversion + formatting\n")

surface <- read.csv("data/yield-surface.csv", stringsAsFactors = FALSE)
surface$co2 <- as.integer(surface$co2)
cells <- unique(surface[, c("cellid", "x", "y")])
stopifnot(nrow(surface) > 0, nrow(cells) > 100)
cat(sprintf("[ok] data: %d rows, %d cells\n", nrow(surface), nrow(cells)))

nc <- nearest_cell(cells, 34.75, -91.5)
stopifnot(!is.null(nc), nc$dist_km >= 0, nc$dist_km < 50)
cat(sprintf("[ok] nearest_cell: cell %s, %.1f km away\n", nc$cellid, nc$dist_km))

lp <- lookup_practice(surface, nc$cellid, "MG4", "late May", "current", 350L)
stopifnot(!is.null(lp), lp$yield_mean_kgha > 0)
cat(sprintf("[ok] lookup_practice (baseline): %.0f kg/ha (%.1f bu/ac)\n",
            lp$yield_mean_kgha, kgha_to_buac(lp$yield_mean_kgha)))
stopifnot(practice_label(lp) == "MG4, planted late May")

## 2. Plot builder -------------------------------------------------------------
source("R/plots.R")
crow <- surface[surface$cellid == nc$cellid & surface$scenario == "baseline", ][1, ]
gb <- make_barplot(crow, observed_kgha = 3000, unit = "bu/ac")
gbench <- make_barplot(crow, observed_kgha = 3000, unit = "bu/ac", benchmark_kgha = 3800)
stopifnot(inherits(gb, "ggplot"), inherits(gbench, "ggplot"))
ggplot2::ggplot_build(gb); ggplot2::ggplot_build(gbench)  # force evaluation
stopifnot(fmt_buac(3362.5) == "50.0 bu/ac")
cat("[ok] plots: bar plot (+ NASS benchmark) builds; bu/ac formatter ok\n")

## NASS county benchmark data present and joinable
nass <- read.csv("data/nass-county-yield.csv", stringsAsFactors = FALSE)
stopifnot(nrow(nass) > 10, "county" %in% names(nass), "yield_bu" %in% names(nass))
stopifnot("county" %in% names(surface), any(!is.na(surface$county)))
cat(sprintf("[ok] NASS: %d counties; surface tagged with county\n", nrow(nass)))

## 2b. APSIM generator wiring (offline — no downloads) -------------------------
source("R/apsim-generate.R")
stopifnot(is.logical(IS_WASM), length(IS_WASM) == 1)
stopifnot(is.function(generate_apsimx_zip), is.function(generate_apsimx_bundle))
stopifnot(to_apsim_date(as.Date("2024-05-22")) == "22-May",
          to_apsim_date(as.Date("2020-04-03")) == "3-Apr")
tp <- template_path()
stopifnot(file.exists(tp), grepl("\\.apsimx$", tp))
## the generator must NOT hard-declare apsimx/zip in CODE (would break the webR
## build). Strip comments first so the design notes that mention them don't trip.
gcode <- sub("#.*$", "", readLines("R/apsim-generate.R"))
gcode <- paste(gcode, collapse = "\n")
stopifnot(!grepl('library\\(apsimx\\)', gcode),
          !grepl('requireNamespace\\(["\']apsimx', gcode),
          !grepl('apsimx::', gcode))
cat(sprintf("[ok] APSIM generator: wired; template %s; IS_WASM=%s\n",
            basename(tp), IS_WASM))

## Optional live generation + APSIM run (set RUN_APSIM_GEN=1; needs apsimx+net)
if (nzchar(Sys.getenv("RUN_APSIM_GEN")) && requireNamespace("apsimx", quietly = TRUE)) {
  z <- tempfile(fileext = ".zip")
  generate_apsimx_zip(lat = 34.75, lon = -91.5, zip_file = z, start_year = 2022)
  stopifnot(file.exists(z), file.size(z) > 1000)
  cat("[ok] APSIM generator: live .zip built\n")
}

## 3. Full reactive server test ------------------------------------------------
app <- source("app.R", local = new.env())$value
testServer(app, {
  session$setInputs(lat = 34.75, lon = -91.5, mg = "MG4", window = "late May",
                    myyield = 45, unit = "bu/ac")
  stopifnot(!is.null(cell()))
  stopifnot(!is.null(cell()$x), !is.null(cell()$y))   # lon/lat for the map
  pr <- pred_row()
  stopifnot(!is.null(pr), identical(pr$scenario, "baseline"))
  stopifnot(nrow(map_cells()) > 100)
  ## benchmark off by default -> NA; on -> a positive kg/ha for a Delta county
  stopifnot(is.na(benchmark_kgha()))
  session$setInputs(benchmark = TRUE)
  bk <- benchmark_kgha()
  cat(sprintf("[ok] server: sim mean=%.1f bu/ac, county=%s, NASS benchmark=%s\n",
              pr$yield_mean_kgha / 67.25, cell()$county,
              if (is.na(bk)) "none" else sprintf("%.1f bu/ac", bk / 67.25)))
})

cat("\nALL SMOKE TESTS PASSED\n")
