## R/soil.R — grid loader + soil conditioning for the in-season pipeline.
##
## Soils are normally already conditioned by ../simulation (reused as-is). This
## file only re-conditions a soil if one is missing, using the SAME steps as
## ../simulation/01-get-weather-soil.R so results stay consistent.

suppressPackageStartupMessages(library(apsimx))

## Load the cropland grid → one row per cultivated cell (cellid, lon, lat).
load_grid <- function(grid_file, n_cells = NULL) {
  g <- readRDS(grid_file)
  names(g) <- tolower(names(g))
  if ("cultivated" %in% names(g)) g <- g[!is.na(g$cultivated) & g$cultivated == 1, ]
  g <- g[order(-g$y, g$x), , drop = FALSE]
  cells <- data.frame(cellid = seq_len(nrow(g)), lon = g$x, lat = g$y,
                      stringsAsFactors = FALSE)
  if (is.null(n_cells))      return(cells)
  if (length(n_cells) == 1L) return(head(cells, n_cells))
  cells[cells$cellid %in% n_cells, , drop = FALSE]
}

## Map a per-layer vector onto an N-layer profile.
fit_layers <- function(v, n) {
  if (n <= length(v)) v[seq_len(n)] else c(v, rep(v[length(v)], n - length(v)))
}

## Condition a raw SSURGO profile (KS decay, fix, KL, XF, initial water, crops) —
## identical to the historical pipeline so the two match.
condition_soil <- function(sp) {
  if (!is.null(sp$soil$KS)) {
    ks_max <- max(sp$soil$KS, na.rm = TRUE)
    sp$soil$KS <- ks_max * exp(seq(0, log(1e-4), length.out = length(sp$soil$KS)))
  }
  sp <- apsimx:::fix_apsimx_soil_profile(sp, verbose = FALSE)
  n_lay <- nrow(sp$soil)
  kl <- fit_layers(KL_VEC, n_lay); xf <- fit_layers(XF_VEC, n_lay)
  for (crop in c("Soybean", "Maize", "Wheat")) {
    if (paste0(crop, ".KL") %in% names(sp$soil)) sp$soil[[paste0(crop, ".KL")]] <- kl
    if (paste0(crop, ".XF") %in% names(sp$soil)) sp$soil[[paste0(crop, ".XF")]] <- xf
  }
  sp$initialwater <- initialwater_parms(
    Depth = sp$soil$Depth, Thickness = sp$soil$Thickness, InitialValues = sp$soil$DUL)
  sp$crops <- unique(c(sp$crops, "Soybean", "Wheat", "Maize"))
  sp
}

## Return the conditioned soil for a cell: reuse the cached .rds if present
## (produced by ../simulation), otherwise download from SSURGO and condition it.
get_soil <- function(cellid, lon, lat, dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  rds_path <- file.path(dir, paste0(cellid, ".rds"))
  if (file.exists(rds_path)) return(rds_path)
  sp <- get_ssurgo_soil_profile(lonlat = c(lon, lat), nsoil = 1)[[1]]
  saveRDS(condition_soil(sp), rds_path)
  rds_path
}

## Merge two apsim met objects: keep historical years strictly before the current
## record, append the current year(s), re-sort, and carry the header attributes.
merge_met <- function(hist, cur) {
  hd <- as.data.frame(hist); cd <- as.data.frame(cur)
  hd <- hd[!(hd$year %in% unique(cd$year)), , drop = FALSE]   # current wins on overlap
  comb <- rbind(hd[names(cd)], cd)
  comb <- comb[order(comb$year, comb$day), , drop = FALSE]
  for (a in c("units", "latitude", "longitude", "site", "colnames",
              "comments", "constants", "tav", "amp"))
    if (!is.null(attr(cur, a))) attr(comb, a) <- attr(cur, a)
  class(comb) <- class(cur)
  comb
}
