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

  ## Positions on a numeric x-axis: [card] .. [simulated box] .. [your bar]
  x_box <- 2.55; x_bar <- 3.45; w <- 0.5

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

  ## ── Summary card on the left: one row each for potential / real / gap ──
  card_x <- c(0.10, 1.95)
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
  g <- card_row(g, 0.66, "Potential", .fmt_u(potential, unit), UARK$cardinal)
  g <- card_row(g, 0.42, "Your yield", .fmt_u(observed_kgha, unit), UARK$gray)
  g <- card_row(g, 0.20, "Yield gap",
                if (is.na(gap)) "—" else .fmt_u(gap, unit), UARK$dark)

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

## ── Map: filled yield surface with AR state + county outlines ─────────────
## Mirrors the manuscript maps: EPSG:5070, state fill + county lines, western
## crop. Everything is pre-projected so this needs only ggplot2 (no sf).
## `cells` needs columns x_alb, y_alb, yield_mean_kgha (market kg/ha).
## `farm` = c(x_alb, y_alb) of the selected field, or NULL.
XLIM_ALBERS <- c(360000, 570000)   # crops the (non-soybean) western third
TILE_M      <- 2500                # grid pitch in metres (matches sim grid)

make_map <- function(cells, state_df, county_df, farm = NULL, unit = "bu/ac",
                     fill_limits = NULL) {
  cells <- cells[cells$x_alb >= XLIM_ALBERS[1] & cells$x_alb <= XLIM_ALBERS[2], ]
  ylim <- range(state_df$y)

  g <- ggplot() +
    geom_polygon(data = state_df, aes(x = x, y = y, group = group),
                 fill = "#ECECEC", colour = "#8A8A8A", linewidth = 0.4) +
    geom_tile(data = cells, aes(x = x_alb, y = y_alb, fill = yield_mean_kgha),
              width = TILE_M, height = TILE_M) +
    geom_path(data = county_df, aes(x = x, y = y, group = group),
              colour = "#6b6b6b", linewidth = 0.22) +
    scale_fill_gradientn(
      colours = UARK$ramp, limits = fill_limits,
      labels = function(b) round(.to_unit(b, unit)),
      name = if (identical(unit, "bu/ac")) "Yield\n(bu/ac)" else "Yield\n(kg/ha)")

  if (!is.null(farm)) {
    fdf <- data.frame(x = farm[1], y = farm[2])
    g <- g +
      geom_point(data = fdf, aes(x = x, y = y), shape = 21, size = 4.2,
                 stroke = 1.1, fill = UARK$cardinal, colour = "white")
  }

  g +
    coord_fixed(ratio = 1, xlim = XLIM_ALBERS, ylim = ylim, expand = FALSE) +
    theme_void(base_size = 13) +
    theme(
      legend.position = "right",
      legend.title = element_text(colour = UARK$gray, size = rel(0.85)),
      plot.margin = margin(6, 6, 6, 6)
    )
}
