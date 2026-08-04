## This script was written to carry out the grid simulations
## for the cropland in the state of Arkansas
rm(list=ls())

## libraries
library(apsimx)
library(ggplot2)
library(stars)
library(sf)
library(dplyr)

## The cultivated layer was downloaded for the entire country,
## then it was cropped to Arkansas and resampled to 500m. The
## resampling used the mode.
#start again with fine resolution
#use only one soil
#manual corrections if needed

cdl <- stars::read_stars('./raw-data/cropland/cultivated-layer.tif')

plot(cdl)

# Get the bounding box (extent) of the raster
bbox_cdl <- st_bbox(cdl)

## this is to test the simulations with lower resolution
if (TRUE){
  cdl2 <- st_as_stars(st_bbox(cdl), dx = 2500, dy = 2500)#10000
  cdl2 <- st_warp(cdl, cdl2, use_gdal = TRUE, no_data_value = NA, method = 'mode')
  cdl <- cdl2
}

plot(cdl)

resolution <- st_res(cdl)[1]

ark <- st_read('./raw-data/cropland/cb_2018_us_state_20m/cb_2018_us_state_20m.shp')
#plot(ark)
ark <- subset(ark, STUSPS == 'AR')
#plot(ark)
ark <- st_transform(ark, st_crs(cdl))
plot(ark)

## selecting only the cultivated pixels
cdl[cdl != 2] <- NA
cdl[cdl == 2] <- 1

## reprojecting to get latitude and longitude
cdl <- st_transform(cdl, 4326)
sim.grid <- as.data.frame(cdl)
names(sim.grid) <- c('x', 'y', 'cultivated')

saveRDS(sim.grid, 
        './intermediate-data/sim-grid.rds')

## downloading weather and soil data
for (i in 1:nrow(sim.grid)) { #dim(sim.grid)[1]
 
  if (is.na(sim.grid[i, "cultivated"])) next
  
  ## Weather
  iem <- get_iem_apsim_met(lonlat = unlist(sim.grid[i, c('x', 'y')]),
                           dates =  c('2025-01-01', as.character(Sys.Date())))
  
  #pwr <- get_power_apsim_met(lonlat = unlist(sim.grid[i, c('x', 'y')]),
  #                           dates =  c('2025-01-01', as.character(Sys.Date())))
  #
  #iem$radn <- pwr$radn
  
  apsimx::write_apsim_met(iem, 
                          wrt.dir = './intermediate-data/weather/',
                          filename = paste0(i, '.met'))
  
  cat('Processing cell # ', i, ' out of ', nrow(sim.grid), '\n')
  
  if (i %in% seq(1, nrow(sim.grid), 200)){Sys.sleep(3*60)
    cat('Temporary Sleep\n')
  }

}

