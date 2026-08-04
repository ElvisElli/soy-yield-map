## R/data.R — load the cropland grid.
##
## The one helper shared by 01 (which cells to acquire) and 02 (which cells to
## run). Weather/soil download + soil conditioning live in 01-get-weather-soil.R
## so that step is self-contained.

## Return one row per cultivated cell: cellid (stable integer), lon (x), lat (y).
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
