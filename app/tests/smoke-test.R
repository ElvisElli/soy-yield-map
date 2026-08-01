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
gb <- make_barplot(crow, observed_kgha = 3000, unit = "bu/ac",
                   scenario_label = "MG4, planted late May")
stopifnot(inherits(gb, "ggplot"))
ggplot2::ggplot_build(gb)  # force evaluation
cat("[ok] plots: simulated-vs-observed bar plot builds without error\n")

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
  ## yields grossed to 13% moisture -> higher than the raw dry values
  cat(sprintf("[ok] server: scenario=%s, sim mean(13%%)=%.0f kg/ha (%.1f bu/ac), map cells=%d\n",
              pr$scenario, pr$yield_mean_kgha, pr$yield_mean_kgha / 67.25,
              nrow(map_cells())))
})

cat("\nALL SMOKE TESTS PASSED\n")
