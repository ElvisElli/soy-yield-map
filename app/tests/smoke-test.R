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

bp <- practices_at_cell(surface, nc$cellid, "plus2C", 350L)
stopifnot(nrow(bp) >= 1, all(diff(bp$yield_mean_kgha) <= 0))
cat(sprintf("[ok] practices_at_cell: best +2C = %s @ %.0f kg/ha\n",
            practice_label(bp[1, ]), bp$yield_mean_kgha[1]))

## 2. Plot builders ------------------------------------------------------------
source("R/plots.R")
crows <- surface[surface$cellid == nc$cellid &
                   (surface$co2 == 350L | surface$scenario == "baseline"), ]
gb <- make_boxplot(crows, observed_kgha = 3000, unit = "bu/ac", highlight = "baseline")
gy <- make_yeartype_plot(crows, unit = "bu/ac")
stopifnot(inherits(gb, "ggplot"), inherits(gy, "ggplot"))
ggplot2::ggplot_build(gb); ggplot2::ggplot_build(gy)  # force evaluation
cat("[ok] plots: boxplot + year-type build without error\n")

## 3. Full reactive server test ------------------------------------------------
app <- source("app.R", local = new.env())$value
testServer(app, {
  session$setInputs(lat = 34.75, lon = -91.5, climate = "current",
                    mg = "MG4", window = "late May", co2 = "350",
                    myyield = 45, unit = "bu/ac")
  stopifnot(!is.null(cell()))
  stopifnot(!is.null(pred_row()))
  stopifnot(nrow(cell_rows()) > 0)
  stopifnot(identical(selected_scenario(), "baseline"))
  cat(sprintf("[ok] server current: cell_rows=%d, scenario=%s\n",
              nrow(cell_rows()), selected_scenario()))

  ## Switch to warming + adaptation practice
  session$setInputs(climate = "plus2C", mg = "MG5", window = "late April",
                    co2 = "350")
  stopifnot(!is.null(pred_row()))
  stopifnot(identical(selected_scenario(), "early_sowing_longer_mat"))
  cat(sprintf("[ok] server +2C MG5/late April: scenario=%s\n",
              selected_scenario()))
})

cat("\nALL SMOKE TESTS PASSED\n")
