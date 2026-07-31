## plots.R — UARK-branded ggplot2 figures for the soy-yield-map app.
## Kept separate from app.R so the visuals can evolve independently and be
## reused (e.g. exported as static figures for the university website).

library(ggplot2)

## ── University of Arkansas brand palette ─────────────────────────────────
UARK <- list(
  cardinal = "#9D2235",  # primary — PMS 201
  dark     = "#6E121E",
  gray     = "#54585A",
  lgray    = "#B1B3B3",
  cream    = "#F7EEF0",
  ## light → deep cardinal sequential ramp for the yield surface
  ramp     = c("#FBEAEC", "#E3A2AA", "#C05A67", "#9D2235", "#6E121E"),
  ## bad / typical / good "year type" colours (muted → deep cardinal)
  yeartype = c(Bad = "#D98C95", Typical = "#9D2235", Good = "#5C1420")
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
      strip.text      = element_text(face = "bold", colour = UARK$dark,
                                     size = rel(0.85)),
      strip.background = element_rect(fill = UARK$cream, colour = NA),
      legend.position = "none",
      plot.margin     = margin(8, 12, 8, 8)
    )
}

## Short two-line labels for each scenario/practice, in a sensible order.
PRACTICE_LEVELS <- c("baseline", "early_sowing", "longer_mat",
                     "early_sowing_longer_mat", "climate_change")
PRACTICE_LABELS <- c(
  baseline                = "MG4 · late May\n(current)",
  climate_change          = "MG4 · late May\n(+2 °C)",
  early_sowing            = "MG4 · late Apr\n(+2 °C)",
  longer_mat              = "MG5 · late May\n(+2 °C)",
  early_sowing_longer_mat = "MG5 · late Apr\n(+2 °C)"
)

## Convert a kg/ha column to the display unit.
.to_unit <- function(v, unit) if (identical(unit, "bu/ac")) v / 67.25 else v
.unit_lab <- function(unit) if (identical(unit, "bu/ac")) "Yield (bu/ac)" else "Yield (kg/ha)"

## ── Boxplot: simulated distribution by practice vs the farmer's yield ─────
## `rows` = yield-surface rows for ONE cell (the practices to show).
## `observed_kgha` = the farmer's reported yield (may be NA).
## `highlight` = scenario name of the farmer's current selection (filled cardinal).
make_boxplot <- function(rows, observed_kgha = NA, unit = "bu/ac",
                         highlight = NULL) {
  rows <- rows[rows$scenario %in% PRACTICE_LEVELS, , drop = FALSE]
  rows <- rows[!duplicated(rows$scenario), , drop = FALSE]
  rows$scenario <- factor(rows$scenario, levels = PRACTICE_LEVELS)
  rows <- rows[order(rows$scenario), , drop = FALSE]
  rows$lab <- factor(PRACTICE_LABELS[as.character(rows$scenario)],
                     levels = PRACTICE_LABELS[levels(rows$scenario)])
  rows$is_sel <- !is.null(highlight) & rows$scenario == highlight

  sc <- function(v) .to_unit(v, unit)
  g <- ggplot(rows) +
    geom_boxplot(
      aes(x = lab,
          ymin = sc(yield_min_kgha), lower = sc(yield_p25_kgha),
          middle = sc(yield_median_kgha), upper = sc(yield_p75_kgha),
          ymax = sc(yield_max_kgha), fill = is_sel),
      stat = "identity", width = 0.6, colour = UARK$dark, linewidth = 0.4) +
    scale_fill_manual(values = c(`TRUE` = UARK$cardinal, `FALSE` = "#E9C9CE"))

  if (!is.na(observed_kgha)) {
    g <- g +
      geom_hline(yintercept = sc(observed_kgha), colour = UARK$gray,
                 linetype = "dashed", linewidth = 0.7) +
      annotate("text", x = 0.6, y = sc(observed_kgha),
               label = "Your yield", vjust = -0.5, hjust = 0,
               colour = UARK$gray, size = 3.4, fontface = "bold")
  }
  g +
    labs(title = "Simulated yield by practice vs. your reported yield",
         subtitle = "Boxes span 40 simulated years (min–max, quartiles, median)",
         x = NULL, y = .unit_lab(unit)) +
    theme_uark()
}

## ── Year-type small multiples: bad / typical / good years per scenario ────
make_yeartype_plot <- function(rows, unit = "bu/ac") {
  rows <- rows[rows$scenario %in% PRACTICE_LEVELS, , drop = FALSE]
  rows <- rows[!duplicated(rows$scenario), , drop = FALSE]
  sc <- function(v) .to_unit(v, unit)
  long <- do.call(rbind, lapply(seq_len(nrow(rows)), function(i) {
    data.frame(
      scenario = rows$scenario[i],
      year_type = c("Bad", "Typical", "Good"),
      yield = c(sc(rows$yield_p10_kgha[i]),
                sc(rows$yield_median_kgha[i]),
                sc(rows$yield_p90_kgha[i])),
      stringsAsFactors = FALSE)
  }))
  long$scenario <- factor(long$scenario, levels = PRACTICE_LEVELS)
  long$lab <- factor(PRACTICE_LABELS[as.character(long$scenario)],
                     levels = PRACTICE_LABELS[PRACTICE_LEVELS])
  long$year_type <- factor(long$year_type, levels = c("Bad", "Typical", "Good"))

  ggplot(long, aes(x = year_type, y = yield, fill = year_type)) +
    geom_col(width = 0.75) +
    geom_text(aes(label = round(yield)), vjust = -0.35, size = 2.9,
              colour = UARK$gray) +
    facet_wrap(~lab, nrow = 1) +
    scale_fill_manual(values = UARK$yeartype) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
    labs(title = "Yield potential by year type",
         subtitle = "Bad = 10th percentile · Typical = median · Good = 90th percentile of years",
         x = NULL, y = .unit_lab(unit)) +
    theme_uark() +
    theme(axis.text.x = element_text(size = rel(0.8)))
}
