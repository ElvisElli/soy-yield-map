## ============================================================
## 02-run-apsim.R
## Run APSIM for every cell × scenario, collect yearly soybean yield, and write
## data/outputs/simulated-scenarios-df.rds (consumed by 03-export-app-data.R).
##
## Resumable: results are checkpointed per chunk of cells; re-running skips
## chunks that are already done. Requires 01-get-weather-soil.R to have cached
## the weather/soil for the cells.
##
## Parallelism: a PSOCK cluster (parallel + doParallel/foreach) — full multi-core
## on BOTH Windows and Linux/macOS/cloud. Falls back to sequential if only one
## core is available or the cluster can't start.
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
suppressPackageStartupMessages({
  library(parallel); library(foreach); library(doParallel)
})

exe <- init_apsim()
message("[02] APSIM: ", exe)
dir.create(CHECKPOINTS, recursive = TRUE, showWarnings = FALSE)

cells <- load_grid(GRID_FILE, N_CELLS)
message(sprintf("[02] %d cells × %d scenarios | %d cores",
                nrow(cells), nrow(SCENARIOS), N_CORES))

## climate.control date kept for app compatibility (future enable = current
## climate; past enable = warming). Derived from warming_C.
SCENARIOS$climate.control <- ifelse(SCENARIOS$warming_C > 0, "1/1/1980", "1/1/2025")

## ── Parallel backend (PSOCK works identically on Windows & Linux) ─────────
cl <- NULL
if (N_CORES > 1L) {
  cl <- tryCatch(makeCluster(N_CORES, type = "PSOCK"),
                 error = function(e) NULL)
}
if (!is.null(cl)) {
  registerDoParallel(cl)
  ## Each worker is a fresh R process: load the library files and point apsimx
  ## at the APSIM executable (done once, reused for every chunk).
  DATA_R <- normalizePath("R/data.R"); APSIM_R <- normalizePath("R/apsim.R")
  clusterExport(cl, c("DATA_R", "APSIM_R"), envir = environment())
  clusterEvalQ(cl, {
    suppressPackageStartupMessages(library(apsimx))
    source(DATA_R); source(APSIM_R); init_apsim(); TRUE
  })
  message("[02] PSOCK cluster with ", N_CORES, " workers")
} else {
  registerDoSEQ()
  message("[02] running sequentially (1 core)")
}
on.exit(if (!is.null(cl)) try(stopCluster(cl), silent = TRUE), add = TRUE)

## Process in chunks so progress is checkpointed and resumable.
chunks <- split(cells, ceiling(seq_len(nrow(cells)) / CHUNK_SIZE))
for (k in seq_along(chunks)) {
  ck_file <- file.path(CHECKPOINTS, sprintf("chunk_%04d.rds", k))
  if (file.exists(ck_file)) { message(sprintf("[02] chunk %d/%d — skip (done)", k, length(chunks))); next }
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

## Combine all checkpoints → the results file the export reads.
all_files <- list.files(CHECKPOINTS, "^chunk_.*\\.rds$", full.names = TRUE)
final <- do.call(rbind, lapply(all_files, readRDS))
out_rds <- file.path(OUT_DIR, "simulated-scenarios-df.rds")
saveRDS(final, out_rds)
message(sprintf("[02] DONE — %d rows (%d cells) → %s",
                nrow(final), length(unique(final$cellid)), out_rds))
