## R/data.R — grid + weather + soil acquisition helpers.
## All functions are resumable: anything already on disk is reused.

suppressPackageStartupMessages({
  library(apsimx)
})

## Load the cropland grid and return one row per cultivated cell:
##   cellid (stable integer), lon (x), lat (y).
## `n_cells`: NULL = all; a single integer = first N; a vector = those cellids.
load_grid <- function(grid_file, n_cells = NULL) {
  g <- readRDS(grid_file)
  names(g) <- tolower(names(g))
  if (!all(c("x", "y") %in% names(g)))
    stop("Grid must have x (lon) and y (lat) columns; found: ",
         paste(names(g), collapse = ", "))
  ## keep cultivated cells (cultivated flag == 1 / TRUE); if absent, keep all
  if ("cultivated" %in% names(g)) g <- g[!is.na(g$cultivated) & g$cultivated == 1, ]
  g <- g[order(-g$y, g$x), , drop = FALSE]          # stable north→south, west→east
  cells <- data.frame(cellid = seq_len(nrow(g)),
                      lon = g$x, lat = g$y, stringsAsFactors = FALSE)
  if (is.null(n_cells))            return(cells)
  if (length(n_cells) == 1L)       return(head(cells, n_cells))
  cells[cells$cellid %in% n_cells, , drop = FALSE]
}

## Download (or reuse) a NASA POWER weather file for one cell -> <cellid>.met.
## Returns the .met path.
get_weather <- function(cellid, lon, lat, years, dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  met_path <- file.path(dir, paste0(cellid, ".met"))
  if (file.exists(met_path)) return(met_path)
  dates <- c(sprintf("%d-01-01", years[1]), sprintf("%d-12-31", years[2]))
  met <- get_power_apsim_met(lonlat = c(lon, lat), dates = dates)
  ## POWER occasionally returns -99 sentinels; APSIM handles NA better
  write_apsim_met(met, wrt.dir = dir, filename = paste0(cellid, ".met"))
  met_path
}

## Download (or reuse) a SSURGO soil profile for one cell -> <cellid>.rds.
## Returns an apsimx soil_profile ready for simulation.
get_soil <- function(cellid, lon, lat, dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  rds_path <- file.path(dir, paste0(cellid, ".rds"))
  if (file.exists(rds_path)) return(readRDS(rds_path))
  sp <- get_ssurgo_soil_profile(lonlat = c(lon, lat), nsoil = 1)[[1]]
  sp <- prepare_soil(sp)
  saveRDS(sp, rds_path)
  sp
}

## Condition a raw SSURGO profile for APSIM soybean runs:
##  - decreasing saturated conductivity with depth
##  - initial water at drained upper limit
##  - crop list including Soybean
prepare_soil <- function(sp) {
  sp <- apsimx:::fix_apsimx_soil_profile(sp, verbose = FALSE)
  if (!is.null(sp$soil$KS)) {
    ks_max <- max(sp$soil$KS, na.rm = TRUE)
    sp$soil$KS <- ks_max * exp(seq(0, log(1e-4), length.out = length(sp$soil$KS)))
  }
  sp$initialwater <- initialwater_parms(
    Depth = sp$soil$Depth, Thickness = sp$soil$Thickness,
    InitialValues = sp$soil$DUL)
  sp$crops <- unique(c(sp$crops, "Soybean", "Wheat", "Maize"))
  sp
}
