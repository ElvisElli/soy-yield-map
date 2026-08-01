## ============================================================
## get-nass-yields.R
## Download county-level soybean yield (bu/ac) for Arkansas from the USDA-NASS
## Quick Stats API and write a per-county 5-year average benchmark the app can
## overlay on its chart.
##
## Same rationale as the sowing-progress downloader in the soybean-ar-climate-
## change repo (Quick Stats API), just pulling YIELD instead of PROGRESS.
##
## Output: ../app/data/nass-county-yield.csv  (county, yield_bu, n_years, years)
##
## Run:  Rscript get-nass-yields.R      (from simulation/)
## ============================================================

setwd_here <- function() {
  a <- commandArgs(FALSE); f <- grep("^--file=", a, value = TRUE)
  if (length(f)) setwd(dirname(normalizePath(sub("^--file=", "", f[1]))))
}
setwd_here()
suppressPackageStartupMessages(library(jsonlite))

## Public Quick Stats key (same one used in the soybean-ar-climate-change repo).
NASS_KEY <- Sys.getenv("NASS_API_KEY", "D228A372-93ED-3BF7-9699-D2D0DDD3C88D")
N_YEARS  <- 5
OUT_CSV  <- file.path("..", "app", "data", "nass-county-yield.csv")

url <- paste0(
  "https://quickstats.nass.usda.gov/api/api_GET/?key=", NASS_KEY,
  "&commodity_desc=SOYBEANS&statisticcat_desc=YIELD",
  "&unit_desc=", utils::URLencode("BU / ACRE", reserved = TRUE),
  "&agg_level_desc=COUNTY&state_alpha=AR&format=JSON")

message("[nass] downloading Arkansas county soybean yields ...")
d <- tryCatch(jsonlite::fromJSON(url)$data, error = function(e) NULL)
if (is.null(d) || !nrow(d)) stop("[nass] Quick Stats returned no data.")

d <- d[d$short_desc == "SOYBEANS - YIELD, MEASURED IN BU / ACRE", ]
d$year  <- suppressWarnings(as.integer(d$year))
d$value <- suppressWarnings(as.numeric(gsub(",", "", d$Value)))
d$county <- toupper(trimws(d$county_name))
d <- d[!is.na(d$year) & !is.na(d$value) & nzchar(d$county) &
         d$county != "OTHER (COMBINED) COUNTIES", ]

## Keep the most recent N_YEARS present in the dataset
recent <- sort(unique(d$year), decreasing = TRUE)[seq_len(min(N_YEARS, length(unique(d$year))))]
d <- d[d$year %in% recent, ]

agg <- aggregate(value ~ county, data = d, FUN = mean)
cnt <- aggregate(year  ~ county, data = d, FUN = function(y) length(unique(y)))
out <- merge(agg, cnt, by = "county")
names(out) <- c("county", "yield_bu", "n_years")
out$yield_bu <- round(out$yield_bu, 1)
out$year_min <- min(recent); out$year_max <- max(recent)
out <- out[order(out$county), ]

dir.create(dirname(OUT_CSV), recursive = TRUE, showWarnings = FALSE)
write.csv(out, OUT_CSV, row.names = FALSE)
message(sprintf("[nass] wrote %s — %d counties, years %d-%d",
                OUT_CSV, nrow(out), min(recent), max(recent)))
