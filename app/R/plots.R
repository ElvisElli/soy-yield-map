## plots.R — UARK-branded ggplot2 figure for the soy-yield-map app.
## Kept separate from app.R so the visual can evolve independently and be
## reused (e.g. exported as a static figure for the university website).

library(ggplot2)

## ── University of Arkansas brand palette ─────────────────────────────────
UARK <- list(
  cardinal = "#9D2235",  # primary — PMS 201
  dark     = "#6E121E",
  gray     = "#54585A",
  lgray    = "#B1B3B3",
  cream    = "#F7EEF0",
  ## light → deep cardinal sequential ramp for the yield surface
  ramp     = c("#FBEAEC", "#E3A2AA", "#C05A67", "#9D2235", "#6E121E")
)

## Shared theme: clean, print-quality, university-website friendly.
theme_uark <- function(base_size = 13) {
  theme_minimal(base_size = base_size) +
    theme(
      text            = element_text(colour = "#2b2b2b"),
      plot.title      = element_text(face = "bold", colour = UARK$cardinal,
                                     size = rel(1.05)),
      plot.subtitle   = element_text(colour = UARK$gray, size = rel(0.9)),
      plot.title.position = "plot",
      axis.title      = element_text(colour = UARK$gray),
      panel.grid.minor = element_blank(),
      panel.grid.major.x = element_blank(),
      legend.position = "none",
      plot.margin     = margin(8, 12, 8, 8)
    )
}

## Convert a kg/ha value to the display unit.
.to_unit <- function(v, unit) if (identical(unit, "bu/ac")) v / 67.25 else v
.unit_lab <- function(unit) if (identical(unit, "bu/ac")) "Yield (bu/ac)" else "Yield (kg/ha)"

## ── Boxplot: simulated distribution vs the farmer's reported yield ───────
## `row` = ONE yield-surface row (the scenario the farmer selected).
## `observed_kgha` = the farmer's reported yield (may be NA).
make_boxplot <- function(row, observed_kgha = NA, unit = "bu/ac",
                         scenario_label = "Simulated") {
  sc <- function(v) .to_unit(v, unit)
  sim_cat <- "Simulated\n(40 years)"

  boxdf <- data.frame(
    cat    = sim_cat,
    ymin   = sc(row$yield_min_kgha),   lower = sc(row$yield_p25_kgha),
    middle = sc(row$yield_median_kgha), upper = sc(row$yield_p75_kgha),
    ymax   = sc(row$yield_max_kgha)
  )

  g <- ggplot() +
    geom_boxplot(
      data = boxdf,
      aes(x = cat, ymin = ymin, lower = lower, middle = middle,
          upper = upper, ymax = ymax),
      stat = "identity", width = 0.45,
      fill = UARK$cardinal, colour = UARK$dark, linewidth = 0.5)

  xlevels <- sim_cat
  if (!is.na(observed_kgha)) {
    obsdf <- data.frame(cat = "Your field", y = sc(observed_kgha))
    g <- g +
      geom_point(data = obsdf, aes(x = cat, y = y),
                 size = 5, colour = UARK$gray) +
      geom_text(data = obsdf, aes(x = cat, y = y, label = round(y, 1)),
                vjust = -1.1, fontface = "bold", colour = UARK$gray, size = 3.8)
    xlevels <- c(sim_cat, "Your field")
  }

  g +
    scale_x_discrete(limits = xlevels) +
    labs(title = "Simulated yield vs. your reported yield",
         subtitle = paste0(scenario_label,
                           "  ·  box = min–max, quartiles and median across 40 years"),
         x = NULL, y = .unit_lab(unit)) +
    theme_uark()
}
