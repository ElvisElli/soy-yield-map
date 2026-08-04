## This script was written to carry out the grid simulations
## for the cropland in the state of Arkansas
rm(list=ls())

## libraries
library(apsimx)
library(ggplot2)
library(stars)
library(sf)
library(dplyr)
library(readxl)

## The cultivated layer was downloaded for the entire country,
## then it was cropped to Arkansas and resampled to 500m. The
## resampling used the mode.
#start again with fine resolution
#use only one soil
#manual corrections if needed
source("code/openmeteo.R")

sim.grid <- read_excel("intermediate-data/station-coordinates.xlsx",sheet = "final")

## downloading weather and soil data
for (i in 1:nrow(sim.grid)) { #dim(sim.grid)[1]

  lonlat <- unlist(sim.grid[i, c('x', 'y')])
  
  ## Historical Weather
  iem <- get_iem_apsim_met(lonlat = lonlat,
                           dates = c('1985-01-01',  as.character(Sys.Date())))
  #tail(iem)
  #pwr <- get_power_apsim_met(lonlat = unlist(sim.grid[i, c('x', 'y')]),
  #                           dates = c('1985-01-01', '2024-12-31'))
  #iem$radn <- pwr$radn
  
  ##Forecast weather
  forecast <- get_openmeteo_daily(
    lonlat = lonlat,
    start_date = as.character(Sys.Date()),
    end_date = as.character(Sys.Date() + 7)
  )
  
  ## 3. Combine historical + forecast, avoiding duplicate dates
  if (!is.null(forecast)) {
    
    # Combine year and day into a string for comparison
    iem_keys <- paste(iem$year, iem$day, sep = "-")
    forecast_keys <- paste(forecast$year, forecast$day, sep = "-")
    
    # Remove overlapping dates
    forecast <- forecast[!forecast_keys %in% iem_keys, ]
    
    combined <- rbind(iem, forecast)
    
  } else {
    
    combined <- iem
  }
  
apsimx::write_apsim_met(combined, 
                          wrt.dir = './intermediate-data/weather-historical/',
                          filename = paste0(i, '.met'))

  #resolution <- 1600 #1 mile
  ### Soil
  #alt.res <- seq(resolution, 30, -100)
  #for (ar in alt.res){
  #  spp <- try(get_ssurgo_soil_profile(lonlat = lonlat,
  #                                     shift = ar,
  #                                     nlayers = 20,
  #                                     nsoil = NA), silent = TRUE)
  #  
  #  if (!inherits(spp, 'try-error')){break}
  #}
  #
  #saveRDS(list(spp), 
  #        paste0('./intermediate-data/soil-historical/', i, '.rds'))
  
  
  cat('Processing cell # ', i, ' out of ', nrow(sim.grid), '\n')
  
}

