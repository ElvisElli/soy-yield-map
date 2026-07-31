## ============================================================
## 02-run-apsim.R
## Run APSIM for every cell × scenario, collect yearly soybean yield, and write
## data/outputs/simulated-scenarios-df.rds (consumed by 03-export-app-data.R).
##
## Resumable: results are checkpointed per chunk of cells; re-running skips
## chunks that are already done. Requires 01-get-weather-soil.R to have cached
## the weather/soil for the cells.
##
## Parallelism: uses fork-based parallel::mclapply on Linux/macOS (ideal for the
## cloud); on Windows it falls back to a single core — run it in the cloud, or
## reduce the grid, for large jobs.
##
## Run:  Rscript 02-run-apsim.R      (from simulation/)
## ============================================================

setwd_here <- function() {
  a <- commandArgs(FALSE); f <- grep("^--file=", a, value = TRUE)
  if (length(f)) setwd(dirname(normalizePath(sub("^--file=", "", f[1]))))
}
setwd_here()
source("config.R")
source("R/data.R")
source("R/apsim.R")
suppressPackageStartupMessages(library(parallel))

exe <- init_apsim()
message("[02] APSIM: ", exe)
dir.create(CHECKPOINTS, recursive = TRUE, showWarnings = FALSE)

cells <- load_grid(GRID_FILE, N_CELLS)
message(sprintf("[02] %d cells × %d scenarios | %d cores",
                nrow(cells), nrow(SCENARIOS), N_CORES))

## Derived climate.control date (kept for compatibility with the app's climate
## label: a future enable date = current climate; a past one = warming applied).
SCENARIOS$climate.control <- ifelse(SCENARIOS$warming_C > 0, "1/1/1980", "1/1/2025")

## Simulate every scenario for one cell → a tidy data.frame (or NULL).
run_one_cell <- function(cl) {
  met  <- file.path(WEATHER_DIR, paste0(cl$cellid, ".met"))
  soilf <- file.path(SOIL_DIR,   paste0(cl$cellid, ".rds"))
  if (!file.exists(met) || !file.exists(soilf)) return(NULL)
  soil <- readRDS(soilf)

  rows <- lapply(seq_len(nrow(SCENARIOS)), function(s) {
    sc  <- SCENARIOS[s, ]
    dir <- tempfile(paste0("cell", cl$cellid, "_"))
    dir.create(dir, showWarnings = FALSE)
    on.exit(unlink(dir, recursive = TRUE), add = TRUE)
    f   <- tryCatch(build_cell(TEMPLATE, dir, sc, met, soil, DATE_START, DATE_END),
                    error = function(e) NULL)
    if (is.null(f)) return(NULL)
    res <- run_cell(f, dir)
    if (is.null(res)) return(NULL)
    date_col <- grep("Clock.Today$|^Date$", names(res), value = TRUE)[1]
    data.frame(
      cellid = cl$cellid, x = cl$lon, y = cl$lat,
      cultivar = sc$cultivar, sowing = sc$sow_date, scenario = sc$name,
      climate.control = sc$climate.control, co2 = sc$co2,
      Date = as.Date(res[[date_col]]), Yield_kgha = res$Yield_kgha,
      stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  if (is.null(out) || !nrow(out)) NULL else out
}

## Process in chunks so progress is checkpointed and resumable.
chunks <- split(cells, ceiling(seq_len(nrow(cells)) / CHUNK_SIZE))
for (k in seq_along(chunks)) {
  ck_file <- file.path(CHECKPOINTS, sprintf("chunk_%04d.rds", k))
  if (file.exists(ck_file)) { message(sprintf("[02] chunk %d/%d — skip (done)", k, length(chunks))); next }
  chunk <- chunks[[k]]
  rows  <- mclapply(seq_len(nrow(chunk)),
                    function(i) run_one_cell(chunk[i, ]),
                    mc.cores = N_CORES, mc.preschedule = FALSE)
  df <- do.call(rbind, rows[!vapply(rows, is.null, logical(1))])
  saveRDS(df, ck_file)
  message(sprintf("[02] chunk %d/%d — %d cells ok, %d rows",
                  k, length(chunks),
                  sum(!vapply(rows, is.null, logical(1))),
                  if (is.null(df)) 0L else nrow(df)))
}

## Combine all checkpoints → the results file the export reads.
all_files <- list.files(CHECKPOINTS, "^chunk_.*\\.rds$", full.names = TRUE)
final <- do.call(rbind, lapply(all_files, readRDS))
out_rds <- file.path(OUT_DIR, "simulated-scenarios-df.rds")
saveRDS(final, out_rds)
message(sprintf("[02] DONE — %d rows (%d cells) → %s",
                nrow(final), length(unique(final$cellid)), out_rds))
