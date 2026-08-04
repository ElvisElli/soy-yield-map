## ============================================================
## 05-stations.R
## Run the DAILY soil-water template over the FULL record (1985 → today) at each
## research station, so we can show this season's trajectory against the
## historical range. Cheap — only a handful of stations.
##
##   input/stations.csv          → station name + lat/lon
##   → output/station-daily.rds   full daily series per station (all years)
##   → ../app/data/station-timeseries.csv   compact: historical band + this year
##   → output/plots/inspect-stations.png    quick check
##
## Weather is cached per station and only the current year is re-downloaded and
## merged each run (same as the grid). Run via code/run-all.R or the master.
## ============================================================

## set the working directory to the component root (folder with code/ input/ output/)
local({
  a <- commandArgs(FALSE); f <- grep("^--file=", a, value = TRUE)
  d <- if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1]))) else getwd()
  while (!file.exists(file.path(d, "code", "config.R")) && dirname(d) != d) d <- dirname(d)
  setwd(d)
})
source("code/config.R"); source("code/R/soil.R"); source("code/R/apsim.R")
suppressPackageStartupMessages({ library(apsimx); library(dplyr) })
options(timeout = 600)

exe <- init_apsim()
build_daily_template(BASE_TEMPLATE, TEMPLATE)   # shared base → daily variant
WX_END <- as.character(Sys.Date() - POWER_LATENCY_DAYS)

stations <- read.csv(STATIONS_FILE, stringsAsFactors = FALSE)
if (nzchar(Sys.getenv("SOY_N_CELLS"))) stations <- head(stations, 2)   # test subset
message(sprintf("[05] %d research stations | 1985 → %s", nrow(stations), WX_END))

## Full-record station weather: cache it; only re-download + merge the current year.
station_weather <- function(id, lon, lat) {
  dir.create(STATION_WX_DIR, recursive = TRUE, showWarnings = FALSE)
  met_path <- file.path(STATION_WX_DIR, paste0(id, ".met"))
  cur <- get_power_apsim_met(lonlat = c(lon, lat),
                             dates = c(sprintf("%d-01-01", CURRENT_YEAR), WX_END))
  cur <- tryCatch(impute_apsim_met(cur), error = function(e) cur)
  if (file.exists(met_path)) {
    h <- read_apsim_met(paste0(id, ".met"), src.dir = STATION_WX_DIR, verbose = FALSE)
    out <- merge_met(h, cur)
  } else {
    h <- get_power_apsim_met(lonlat = c(lon, lat),
                             dates = c("1985-01-01", sprintf("%d-12-31", CURRENT_YEAR - 1)))
    h <- tryCatch(impute_apsim_met(h), error = function(e) h)
    out <- merge_met(h, cur)
  }
  write_apsim_met(out, wrt.dir = STATION_WX_DIR, filename = paste0(id, ".met"))
  met_path
}

KEEP <- c("rel_sw_6in", "rel_sw_12in", "rel_sw_24in", "CummRain_fromApril", "Biomass_kgha")

run_station <- function(id, name, lon, lat) {
  met  <- station_weather(id, lon, lat)
  soil <- readRDS(get_soil(paste0("st", id), lon, lat, STATION_SOIL_DIR))
  d <- tempfile(paste0("st", id, "_")); dir.create(d); on.exit(unlink(d, recursive = TRUE), add = TRUE)
  f <- build_cell(TEMPLATE, d, SCENARIOS[1, ], met, soil, "1985-01-01", WX_END)
  res <- tryCatch(apsimx(f, src.dir = d, cleanup = TRUE, silent = TRUE), error = function(e) NULL)
  if (is.null(res) || !nrow(res)) return(NULL)
  dc <- grep("Clock.Today$|^Date$", names(res), value = TRUE)[1]
  data.frame(station = name, date = as.Date(res[[dc]]),
             res[, intersect(KEEP, names(res)), drop = FALSE], stringsAsFactors = FALSE)
}

all <- vector("list", nrow(stations))
for (i in seq_len(nrow(stations))) {
  st <- stations[i, ]
  message(sprintf("[05] %d/%d  %s", i, nrow(stations), st$station))
  all[[i]] <- tryCatch(run_station(i, st$station, st$lon, st$lat),
                       error = function(e) { message("   FAILED: ", conditionMessage(e)); NULL })
}
daily <- do.call(rbind, all)
if (is.null(daily) || !nrow(daily)) stop("[05] no station results produced.")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
saveRDS(daily, file.path(OUT_DIR, "station-daily.rds"))
message(sprintf("[05] %d daily rows across %d stations", nrow(daily), dplyr::n_distinct(daily$station)))

## ── Compact app series: historical band (min/median/max over past years) +
##    this year's line, per station × variable × day-of-year. ──────────────
daily$year <- as.integer(format(daily$date, "%Y"))
daily$doy  <- as.integer(format(daily$date, "%j"))
daily$CummRain_fromApril <- daily$CummRain_fromApril / 25.4   # mm → inches
names(daily)[names(daily) == "CummRain_fromApril"] <- "CummRain_in"
VARS <- c("rel_sw_6in", "rel_sw_12in", "rel_sw_24in", "CummRain_in", "Biomass_kgha")

long <- do.call(rbind, lapply(VARS, function(v)
  data.frame(station = daily$station, year = daily$year, doy = daily$doy,
             variable = v, value = daily[[v]], stringsAsFactors = FALSE)))
hist <- long |>
  dplyr::filter(year < CURRENT_YEAR) |>
  dplyr::group_by(station, variable, doy) |>
  dplyr::summarise(lo = round(min(value, na.rm = TRUE), 3),
                   med = round(median(value, na.rm = TRUE), 3),
                   hi = round(max(value, na.rm = TRUE), 3), .groups = "drop")
cur <- long |>
  dplyr::filter(year == CURRENT_YEAR) |>
  dplyr::group_by(station, variable, doy) |>
  dplyr::summarise(current = round(mean(value, na.rm = TRUE), 3), .groups = "drop")
series <- dplyr::left_join(hist, cur, by = c("station", "variable", "doy")) |>
  dplyr::arrange(station, variable, doy)

IS_TEST <- nzchar(Sys.getenv("SOY_N_CELLS"))
OUT_CSV <- if (IS_TEST) file.path(OUT_DIR, "station-timeseries.csv") else "../app/data/station-timeseries.csv"
readr_ok <- requireNamespace("readr", quietly = TRUE)
if (readr_ok) readr::write_csv(series, OUT_CSV) else write.csv(series, OUT_CSV, row.names = FALSE)
message("[05] wrote ", OUT_CSV, " (", nrow(series), " rows)")

## ── Inspection plot: relative soil water 0–12 in, this year vs history ────
suppressPackageStartupMessages(library(ggplot2))
lab_dates  <- seq(as.Date("2025-01-01"), as.Date("2025-12-31"), by = "2 months")
doy_breaks <- as.integer(format(lab_dates, "%j")); doy_labels <- format(lab_dates, "%b")
ps <- series |> dplyr::filter(variable == "rel_sw_12in")
p <- ggplot(ps, aes(doy)) +
  geom_ribbon(aes(ymin = lo, ymax = hi), fill = "grey85") +
  geom_line(aes(y = med), colour = "grey45") +
  geom_line(aes(y = current), colour = "#9D2235", linewidth = 0.7, na.rm = TRUE) +
  facet_wrap(~station) +
  scale_x_continuous(breaks = doy_breaks, labels = doy_labels) +
  labs(title = sprintf("Relative soil water 0–12 in — %d vs 1985–%d", CURRENT_YEAR, CURRENT_YEAR - 1),
       subtitle = "red = this season · grey band = historical min–max · grey line = median",
       x = NULL, y = "fraction of available water") +
  theme_minimal(base_size = 10) +
  theme(axis.text.x = element_text(angle = 35, hjust = 1))
dir.create("output/plots", showWarnings = FALSE, recursive = TRUE)
ggsave("output/plots/inspect-stations.png", p, width = 9, height = 6, dpi = 110, bg = "white")
message("[05] wrote output/plots/inspect-stations.png")
