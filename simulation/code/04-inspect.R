## ============================================================
## 04-inspect.R
## Quick "did it work?" plots for the HISTORICAL run. Reads the simulation output
## and writes PNGs to output/plots/ — open them to confirm the run looks sane.
##
## Run:  Rscript code/04-inspect.R   (runs automatically as the last run-all step)
## ============================================================

## set the working directory to the component root (folder with code/ input/ output/)
local({
  a <- commandArgs(FALSE); f <- grep("^--file=", a, value = TRUE)
  d <- if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1]))) else getwd()
  while (!file.exists(file.path(d, "code", "config.R")) && dirname(d) != d) d <- dirname(d)
  setwd(d)
})
source("code/config.R")
suppressPackageStartupMessages({ library(ggplot2); library(sf) })

## Arkansas state + county outlines for the map background (grey, like the app).
load_ar <- function() {
  crop <- "input/cropland"
  st <- tryCatch(st_transform(st_read(file.path(crop, "cb_2018_us_state_20m",
                 "cb_2018_us_state_20m.shp"), quiet = TRUE), 4326), error = function(e) NULL)
  if (!is.null(st)) st <- st[st$STUSPS == "AR", ]
  cty <- tryCatch(st_transform(st_read(file.path(crop, "Elvis-Crop-Data",
                 "Arkansas_Counties_4269.shp"), quiet = TRUE), 4326), error = function(e) NULL)
  list(state = st, county = cty)
}
AR <- load_ar()
ar_base <- function() {
  g <- ggplot()
  if (!is.null(AR$state))  g <- g + geom_sf(data = AR$state, fill = "grey92", colour = "grey40", linewidth = 0.4)
  if (!is.null(AR$county)) g <- g + geom_sf(data = AR$county, fill = NA, colour = "grey75", linewidth = 0.2)
  g
}
ar_zoom <- function() {
  if (is.null(AR$state)) return(coord_quickmap())
  bb <- sf::st_bbox(AR$state)
  coord_sf(xlim = c(bb[["xmin"]], bb[["xmax"]]), ylim = c(bb[["ymin"]], bb[["ymax"]]), expand = FALSE)
}

in_rds <- file.path(OUT_DIR, "simulated-scenarios-df.rds")
if (!file.exists(in_rds)) stop("No results at ", in_rds, " — run 01 → 02 first.")
raw <- readRDS(in_rds)
df  <- if (is.data.frame(raw)) raw else do.call(rbind, lapply(raw, as.data.frame))

## Mean yield per cell for the first scenario, on the app's basis (market bu/ac).
sc1 <- df[df$scenario == df$scenario[1], , drop = FALSE]
agg <- aggregate(Yield_kgha ~ cellid + x + y, data = sc1,
                 FUN = function(v) mean(v, na.rm = TRUE))
agg$bu_ac <- agg$Yield_kgha / (1 - 0.13) / 67.25   # dry kg/ha → 13% moisture bu/ac

dir.create("output/plots", recursive = TRUE, showWarnings = FALSE)

pmap <- ar_base() +
  geom_point(data = agg, aes(x, y, colour = bu_ac), size = 1.5) +
  scale_colour_viridis_c(name = "bu/ac") +
  ar_zoom() +
  labs(title = sprintf("Historical mean yield — '%s'  (%d cells)", sc1$scenario[1], nrow(agg)),
       subtitle = format(Sys.time(), "generated %Y-%m-%d %H:%M"), x = NULL, y = NULL) +
  theme_minimal(base_size = 11) +
  theme(axis.text = element_blank(), panel.grid = element_blank())
ggsave("output/plots/inspect-yield-map.png", pmap, width = 6, height = 7, dpi = 110, bg = "white")

phist <- ggplot(agg, aes(bu_ac)) +
  geom_histogram(bins = 30, fill = "#9D2235", colour = "white") +
  labs(title = "Yield distribution across cells", x = "Mean yield (bu/ac)", y = "cells") +
  theme_minimal(base_size = 11)
ggsave("output/plots/inspect-yield-hist.png", phist, width = 6, height = 4, dpi = 110, bg = "white")

message(sprintf("[04] wrote output/plots/inspect-yield-map.png + inspect-yield-hist.png"))
message(sprintf("[04] yield bu/ac  min/mean/max = %.1f / %.1f / %.1f  (%d cells)",
                min(agg$bu_ac), mean(agg$bu_ac), max(agg$bu_ac), nrow(agg)))
