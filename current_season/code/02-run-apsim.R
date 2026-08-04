## ============================================================
## 02-run-apsim.R
## Run the DAILY soil-water template for every cell × scenario over this season
## (Jan 1 → latest weather day) and write data/outputs/soil-water-daily.rds.
##
## Resumable (per-chunk checkpoints) and parallel (PSOCK cluster, Windows + Linux).
## Requires 01-get-weather.R to have cached this season's weather.
##
## Run:  Rscript 02-run-apsim.R      (from current_season/)
## ============================================================

## set the working directory to the component root (folder with code/ input/ output/)
local({
  a <- commandArgs(FALSE); f <- grep("^--file=", a, value = TRUE)
  d <- if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1]))) else getwd()
  while (!file.exists(file.path(d, "code", "config.R")) && dirname(d) != d) d <- dirname(d)
  setwd(d)
})
source("code/config.R")
source("code/R/soil.R")
source("code/R/apsim.R")
suppressPackageStartupMessages({ library(parallel); library(foreach); library(doParallel) })

exe <- init_apsim()
message("[02] APSIM: ", exe)
dir.create(CHECKPOINTS, recursive = TRUE, showWarnings = FALSE)

DATE_START <- sprintf("%d-01-01", CURRENT_YEAR - SPINUP_YEARS)   # spin-up from merged history
DATE_END   <- as.character(Sys.Date() - POWER_LATENCY_DAYS)

cells <- load_grid(GRID_FILE, N_CELLS)
message(sprintf("[02] season %d | %s → %s | %d cells × %d scenario(s) | %d cores",
                CURRENT_YEAR, DATE_START, DATE_END, nrow(cells), nrow(SCENARIOS), N_CORES))

## ── Parallel backend ─────────────────────────────────────────────────────
cl <- NULL
if (N_CORES > 1L) cl <- tryCatch(makeCluster(N_CORES, type = "PSOCK"), error = function(e) NULL)
if (!is.null(cl)) {
  registerDoParallel(cl)
  SOIL_R <- normalizePath("code/R/soil.R"); APSIM_R <- normalizePath("code/R/apsim.R")
  clusterExport(cl, c("SOIL_R", "APSIM_R"), envir = environment())
  clusterEvalQ(cl, {
    suppressPackageStartupMessages(library(apsimx))
    source(SOIL_R); source(APSIM_R); init_apsim(); TRUE
  })
  message("[02] PSOCK cluster with ", N_CORES, " workers")
} else {
  registerDoSEQ(); message("[02] running sequentially (1 core)")
}
on.exit(if (!is.null(cl)) try(stopCluster(cl), silent = TRUE), add = TRUE)

## ── Chunked, checkpointed run ────────────────────────────────────────────
## Checkpoints are cleared each season-run because the season grows daily.
chunks <- split(cells, ceiling(seq_len(nrow(cells)) / CHUNK_SIZE))
for (k in seq_along(chunks)) {
  ck_file <- file.path(CHECKPOINTS, sprintf("chunk_%04d.rds", k))
  chunk <- chunks[[k]]
  rows <- foreach(i = seq_len(nrow(chunk)), .packages = "apsimx",
                  .errorhandling = "pass") %dopar% {
    run_one_cell(chunk[i, ], SCENARIOS, TEMPLATE, DATE_START, DATE_END,
                 WEATHER_DIR, SOIL_DIR)
  }
  ok <- rows[!vapply(rows, function(x) is.null(x) || inherits(x, "error"), logical(1))]
  df <- if (length(ok)) do.call(rbind, ok) else NULL
  saveRDS(df, ck_file)
  message(sprintf("[02] chunk %d/%d — %d cells ok, %d rows",
                  k, length(chunks), length(ok), if (is.null(df)) 0L else nrow(df)))
}

all_files <- list.files(CHECKPOINTS, "^chunk_.*\\.rds$", full.names = TRUE)
final <- do.call(rbind, lapply(all_files, readRDS))
out_rds <- file.path(OUT_DIR, "soil-water-daily.rds")
saveRDS(final, out_rds)
message(sprintf("[02] DONE — %d daily rows (%d cells) → %s",
                nrow(final), length(unique(final$cellid)), out_rds))
