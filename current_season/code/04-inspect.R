## ============================================================
## 04-inspect.R
## Quick "did it work?" plots for the IN-SEASON run. Reads the daily soil-water
## output and writes PNGs to output/plots/ — open them to confirm it looks sane.
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
suppressPackageStartupMessages(library(ggplot2))

in_rds <- file.path(OUT_DIR, "soil-water-daily.rds")
if (!file.exists(in_rds)) stop("No results at ", in_rds, " — run 01 → 02 first.")
daily <- readRDS(in_rds)

## Latest simulated day per cell, classified for the top 6 in.
latest <- do.call(rbind, by(daily, daily$cellid, function(d) d[which.max(d$date), , drop = FALSE]))
pct <- latest$rel_sw_6in * 100
latest$class <- factor(ifelse(pct <= SW_DRY_MAX, "Dry",
                       ifelse(pct <= SW_ADEQUATE_MAX, "Adequate", "Excess")),
                       levels = c("Dry", "Adequate", "Excess"))
cols <- c(Dry = "#de2d26", Adequate = "#31a354", Excess = "#253494")

dir.create("output/plots", recursive = TRUE, showWarnings = FALSE)

pmap <- ggplot(latest, aes(x, y, colour = class)) +
  geom_point(size = 1.5) +
  scale_colour_manual(values = cols, name = "0–6 in", drop = FALSE) +
  coord_quickmap() +
  labs(title = sprintf("In-season soil water — %s", max(latest$date)),
       subtitle = sprintf("%d cells | season %d", nrow(latest), CURRENT_YEAR),
       x = NULL, y = NULL) +
  theme_minimal(base_size = 11)
ggsave("output/plots/inspect-soil-water-map.png", pmap, width = 6, height = 7, dpi = 110, bg = "white")

pbar <- ggplot(latest, aes(class, fill = class)) +
  geom_bar() +
  scale_fill_manual(values = cols, guide = "none", drop = FALSE) +
  labs(title = "Soil-water class counts (0–6 in)", x = NULL, y = "cells") +
  theme_minimal(base_size = 11)
ggsave("output/plots/inspect-soil-water-bar.png", pbar, width = 5, height = 4, dpi = 110, bg = "white")

tbl <- table(latest$class)
message("[04] wrote output/plots/inspect-soil-water-map.png + inspect-soil-water-bar.png")
message("[04] latest day ", as.character(max(latest$date)), " | ",
        paste(names(tbl), as.integer(tbl), sep = ":", collapse = "  "))
