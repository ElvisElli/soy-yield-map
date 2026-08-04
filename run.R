## ============================================================
## run.R — MASTER SWITCHBOARD. Choose what to run, then run this file.
##
##   From RStudio:  open soy-yield-map.Rproj, open run.R, click "Source".
##   From a shell:  Rscript run.R      (in the repo root)
##
## Each component also has its own RStudio project (simulation/simulation.Rproj,
## current_season/current_season.Rproj, app/app.Rproj) if you prefer to work
## inside one at a time.
## ============================================================


## ── 1. WHAT DO YOU WANT TO RUN?  (set TRUE / FALSE) ──────────────────────
RUN_HISTORICAL <- TRUE    # simulation/      40-year grid → app/data/yield-surface.csv
RUN_CURRENT    <- FALSE   # current_season/  in-season daily soil water → soil-water.csv
LAUNCH_APP     <- FALSE   # app/             open the interactive map locally


## ── 2. TEST FIRST ON A SMALL SUBSET?  (recommended) ──────────────────────
## TRUE  = run only a handful of cells, to confirm everything works end to end
##         on your computer (a few minutes) before the full state (hours).
## FALSE = run every cultivated cell (the real run).
TEST_MODE    <- TRUE
TEST_N_CELLS <- 5


## ── 3. (nothing to edit below) ───────────────────────────────────────────
setwd_here <- function() {
  a <- commandArgs(FALSE); f <- grep("^--file=", a, value = TRUE)
  if (length(f)) setwd(dirname(normalizePath(sub("^--file=", "", f[1]))))
}
setwd_here()

## The subset switch is passed to each pipeline's config.R via an env var, so
## you never have to edit N_CELLS by hand just to test.
if (TEST_MODE) Sys.setenv(SOY_N_CELLS = as.character(TEST_N_CELLS)) else Sys.unsetenv("SOY_N_CELLS")

run_pipeline <- function(dir) {
  message("\n############################################################")
  message("##  ", dir, if (TEST_MODE) sprintf("  (TEST: first %d cells)", TEST_N_CELLS) else "  (FULL run)")
  message("############################################################")
  status <- system2("Rscript", file.path(dir, "run-all.R"))
  if (status != 0) stop("Pipeline failed in ", dir, call. = FALSE)
}

if (RUN_HISTORICAL) run_pipeline("simulation")
if (RUN_CURRENT)    run_pipeline("current_season")

if (LAUNCH_APP) {
  message("\n[run] launching the Shiny app (Ctrl/Cmd-C to stop) ...")
  shiny::runApp("app")
}

message("\n[run] done.")
