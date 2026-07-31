## helpers.R — pure functions for the soy-yield-map Shiny app.
## Kept free of Shiny/reactives so they can be unit-tested and reused.

## Soybean unit conversion: 1 bushel = 60 lb at 13% moisture.
## 1 bu/ac = 67.25 kg/ha (standard soybean conversion factor).
BU_AC_PER_KG_HA <- 1 / 67.25
KG_HA_PER_BU_AC <- 67.25

kgha_to_buac <- function(x) x * BU_AC_PER_KG_HA
buac_to_kgha <- function(x) x * KG_HA_PER_BU_AC

## Format a yield value in the requested unit.
fmt_yield <- function(kgha, unit = c("bu/ac", "kg/ha"), digits = NULL) {
  unit <- match.arg(unit)
  if (is.na(kgha)) return("—")
  if (unit == "bu/ac") {
    v <- kgha_to_buac(kgha); d <- if (is.null(digits)) 1 else digits
    sprintf("%.*f bu/ac", d, v)
  } else {
    d <- if (is.null(digits)) 0 else digits
    sprintf("%s kg/ha", formatC(round(kgha, d), big.mark = ",",
                                format = "f", digits = 0))
  }
}

## Great-circle-ish nearest cell. Arkansas spans ~2.5 deg lat, so a simple
## cos-lat-corrected euclidean distance is more than accurate enough and avoids
## any geo dependency (keeps the app webR/shinylive friendly).
nearest_cell <- function(surface_cells, lat, lon) {
  if (is.na(lat) || is.na(lon)) return(NULL)
  latr <- lat * pi / 180
  dx <- (surface_cells$x - lon) * cos(latr)
  dy <- (surface_cells$y - lat)
  d2 <- dx * dx + dy * dy
  i <- which.min(d2)
  cell <- surface_cells[i, , drop = FALSE]
  cell$dist_km <- sqrt(d2[i]) * 111.0   # ~111 km per degree
  cell
}

## Map a farmer's practice selection to the matching simulated scenario row(s).
## Returns the single yield-surface row for one cell, or NULL if that practice
## was not simulated (e.g. MG5 under current climate).
lookup_practice <- function(surface, cellid, mg, plant_window, climate, co2) {
  hit <- surface[surface$cellid == cellid &
                   surface$mg == mg &
                   surface$plant_window == plant_window &
                   surface$climate == climate &
                   surface$co2 == co2, , drop = FALSE]
  if (nrow(hit) == 0) return(NULL)
  hit[1, , drop = FALSE]
}

## All simulated practices available at one cell for a given climate + co2,
## ordered best-yield first. Used for the "best practice here" recommendation.
practices_at_cell <- function(surface, cellid, climate, co2) {
  rows <- surface[surface$cellid == cellid &
                    surface$climate == climate &
                    surface$co2 == co2, , drop = FALSE]
  rows[order(-rows$yield_mean_kgha), , drop = FALSE]
}

## Human label for a practice row.
practice_label <- function(row) {
  if (is.null(row) || nrow(row) == 0) return("—")
  sprintf("%s, planted %s", row$mg, row$plant_window)
}

## Colour bins for the map legend (kg/ha). Chosen to span AR soybean yields.
yield_bins_kgha <- c(0, 2500, 3000, 3500, 4000, 4500, 5000, Inf)
