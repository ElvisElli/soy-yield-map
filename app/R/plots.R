## plots.R — UARK-branded ggplot2 figure for the soy-yield-map app.
## Kept separate from app.R so the visual can evolve independently and be
## reused (e.g. exported as a static figure for the university website).
##
## All yield values passed in are kg/ha at 13% market moisture (the app grosses
## up the APSIM dry-matter yields on load — see app.R).

library(ggplot2)

## ── Palette — University of Arkansas cardinal + refined neutrals ──────────
UARK <- list(
  cardinal = "#9D2235",  # potential yield  (primary — PMS 201)
  steel    = "#3F5B74",  # actual yield     (professional steel-blue)
  green    = "#2E7D32",  # county NASS benchmark
  gold     = "#B0842F",  # (spare accent)
  ink      = "#33373B",  # body text
  gray     = "#5B6169",  # muted labels
  ## light → deep cardinal sequential ramp for the yield surface
  ramp     = c("#F4E7E2", "#DCA9A2", "#C06E6A", "#9D2235", "#6E121E")
)

BU_AC_KG_HA <- 67.25   # 1 bu/ac = 67.25 kg/ha at 13% moisture

## Shared theme: clean, print-quality, university-website friendly.
theme_uark <- function(base_size = 14) {
  theme_minimal(base_size = base_size) +
    theme(
      text             = element_text(colour = UARK$ink),
      axis.title       = element_text(colour = UARK$gray, size = rel(0.9)),
      axis.text.x      = element_text(colour = UARK$ink, size = rel(1.0)),
      panel.grid.minor = element_blank(),
      panel.grid.major.x = element_blank(),
      legend.position  = "none",
      plot.margin      = margin(6, 10, 4, 6)
    )
}

.to_unit  <- function(v, unit) if (identical(unit, "bu/ac")) v / BU_AC_KG_HA else v
.unit_lab <- function(unit) if (identical(unit, "bu/ac")) "Yield (bu/ac)" else "Yield (kg/ha)"
.y_max    <- function(unit) if (identical(unit, "bu/ac")) 120 else 120 * BU_AC_KG_HA

## Format a yield in bu/ac (used for the value tiles, always bushels).
fmt_buac <- function(kgha) if (is.na(kgha)) "—" else sprintf("%.1f bu/ac", kgha / BU_AC_KG_HA)

## ── Bar plot: potential (simulated mean) vs. actual (reported) yield ──────
## `row` = ONE yield-surface row (the selected scenario), market kg/ha.
## `observed_kgha`  = the farmer's actual yield in market kg/ha (may be NA).
## `benchmark_kgha` = optional county NASS 5-yr average (market kg/ha); when
##                    supplied, a third green benchmark bar is drawn.
make_barplot <- function(row, observed_kgha = NA, unit = "bu/ac",
                         benchmark_kgha = NA) {
  sc   <- function(v) .to_unit(v, unit)
  ymax <- .y_max(unit)
  lv   <- c("Potential", "Actual", "County")

  df <- data.frame(type = factor("Potential", levels = lv), x = 1,
                   y = sc(row$yield_mean_kgha))
  if (!is.na(observed_kgha))
    df <- rbind(df, data.frame(type = factor("Actual", levels = lv), x = 2,
                               y = sc(observed_kgha)))
  if (!is.na(benchmark_kgha))
    df <- rbind(df, data.frame(type = factor("County", levels = lv), x = 3,
                               y = sc(benchmark_kgha)))

  xmax <- if (!is.na(benchmark_kgha)) 3.6 else 2.6

  ggplot(df, aes(x = x, y = y, fill = type)) +
    geom_col(width = 0.58) +
    geom_text(aes(label = round(y, 1)), vjust = -0.5, fontface = "bold",
              colour = UARK$ink, size = 4.3) +
    scale_fill_manual(values = c(Potential = UARK$cardinal, Actual = UARK$steel,
                                 County = UARK$green)) +
    scale_x_continuous(limits = c(0.4, xmax), breaks = c(1, 2, 3),
                       labels = c("Potential\nyield", "Actual\nyield",
                                  "County avg\n(NASS 5-yr)")) +
    scale_y_continuous(limits = c(0, ymax), expand = expansion(mult = c(0, 0.05))) +
    labs(x = NULL, y = .unit_lab(unit)) +
    theme_uark()
}
