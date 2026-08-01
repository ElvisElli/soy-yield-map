## plots.R — UARK-branded ggplot2 figures for the soy-yield-map app.
## Kept separate from app.R so the visuals can evolve independently and be
## reused (e.g. exported as static figures for the university website).
##
## All yield values passed in are kg/ha at 13% market moisture (the app grosses
## up the APSIM dry-matter yields on load — see app.R).

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

BU_AC_KG_HA <- 67.25   # 1 bu/ac = 67.25 kg/ha at 13% moisture

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

.to_unit  <- function(v, unit) if (identical(unit, "bu/ac")) v / BU_AC_KG_HA else v
.unit_lab <- function(unit) if (identical(unit, "bu/ac")) "Yield (bu/ac)" else "Yield (kg/ha)"
.y_max    <- function(unit) if (identical(unit, "bu/ac")) 120 else 120 * BU_AC_KG_HA
.fmt_u    <- function(kgha, unit) {
  v <- .to_unit(kgha, unit)
  if (is.na(v)) return("—")
  if (identical(unit, "bu/ac")) sprintf("%.1f bu/ac", v)
  else sprintf("%s kg/ha", formatC(round(v), big.mark = ",", format = "f", digits = 0))
}

## ── Boxplot: simulated distribution + observed bar + summary card ─────────
## `row` = ONE yield-surface row (the scenario the farmer selected), market kg/ha.
## `observed_kgha` = the farmer's reported yield in market kg/ha (may be NA).
make_boxplot <- function(row, observed_kgha = NA, unit = "bu/ac",
                         scenario_label = "Simulated") {
  sc   <- function(v) .to_unit(v, unit)
  ymax <- .y_max(unit)
  potential <- row$yield_mean_kgha              # kg/ha (market)
  gap <- if (is.na(observed_kgha)) NA_real_ else potential - observed_kgha

  ## Positions on a numeric x-axis: [simulated box] .. [your bar] .. [card]
  x_box <- 0.75; x_bar <- 1.65; w <- 0.5

  boxdf <- data.frame(
    x = x_box,
    ymin = sc(row$yield_min_kgha),   lower = sc(row$yield_p25_kgha),
    middle = sc(row$yield_median_kgha), upper = sc(row$yield_p75_kgha),
    ymax = sc(row$yield_max_kgha)
  )

  g <- ggplot() +
    ## simulated distribution
    geom_boxplot(
      data = boxdf,
      aes(x = x, ymin = ymin, lower = lower, middle = middle,
          upper = upper, ymax = ymax),
      stat = "identity", width = w, fill = UARK$cardinal,
      colour = UARK$dark, linewidth = 0.5)

  ## observed yield as a bar
  if (!is.na(observed_kgha)) {
    g <- g +
      geom_col(data = data.frame(x = x_bar, y = sc(observed_kgha)),
               aes(x = x, y = y), width = w, fill = UARK$gray) +
      geom_text(data = data.frame(x = x_bar, y = sc(observed_kgha)),
                aes(x = x, y = y, label = round(y, 1)),
                vjust = -0.6, fontface = "bold", colour = UARK$gray, size = 3.6)
  }

  ## ── Summary card on the RIGHT: one row each for potential / real / gap ──
  ## Always shown in bushels/acre, regardless of the axis unit.
  fmt_bu <- function(kgha) if (is.na(kgha)) "—" else sprintf("%.1f bu/ac", kgha / BU_AC_KG_HA)
  card_x <- c(2.35, 3.95)
  lx <- card_x[1] + 0.08      # left-aligned labels
  rx <- card_x[2] - 0.08      # right-aligned values
  g <- g +
    annotate("rect", xmin = card_x[1], xmax = card_x[2],
             ymin = 0.10 * ymax, ymax = 1.00 * ymax,
             fill = UARK$cream, colour = UARK$cardinal, linewidth = 0.5) +
    annotate("text", x = mean(card_x), y = 0.90 * ymax, label = "YIELD SUMMARY",
             fontface = "bold", colour = UARK$cardinal, size = 3.6)

  card_row <- function(g, y0, label, value, col) {
    g +
      annotate("text", x = lx, y = y0 * ymax, label = label, hjust = 0,
               colour = UARK$gray, size = 3.3) +
      annotate("text", x = rx, y = y0 * ymax, label = value, hjust = 1,
               fontface = "bold", colour = col, size = 3.9)
  }
  g <- card_row(g, 0.66, "Potential", fmt_bu(potential), UARK$cardinal)
  g <- card_row(g, 0.42, "Your yield", fmt_bu(observed_kgha), UARK$gray)
  g <- card_row(g, 0.20, "Yield gap", fmt_bu(gap), UARK$dark)

  g +
    scale_x_continuous(limits = c(0, 4), breaks = c(x_box, x_bar),
                       labels = c("Simulated\n(40 years)", "Your\nfield")) +
    scale_y_continuous(limits = c(0, ymax), expand = expansion(mult = c(0, 0.02))) +
    labs(title = "Simulated yield vs. your reported yield",
         subtitle = paste0(scenario_label,
                           "  ·  box = min–max, quartiles and median across 40 years"),
         x = NULL, y = .unit_lab(unit)) +
    theme_uark() +
    theme(axis.text.x = element_text(size = rel(0.95)))
}
