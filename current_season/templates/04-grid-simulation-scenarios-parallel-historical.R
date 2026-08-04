## This script was written to carry out the grid simulations
## for the cropland in the state of Arkansas

rm(list=ls())

## libraries
#devtools::install_github('femiguez/apsimx')

library(apsimx)
library(ggplot2)
library(stars)
library(sf)
library(readr)
library(dplyr)
library(readxl)
library(lubridate)

## Set up the number of cores to use in the simulation
cores <-10

#?apsimx_options
#apsimx_options(exe.path = 'C:\\Users\\efelli\\AppData\\Local\\Programs\\APSIM2025.3.7681.0\\bin\\Models.exe')
#apsim_version(which = c("inuse"))

## reading the simulation grid & scenarios
sim.grid <- read_excel("intermediate-data/station-coordinates.xlsx",sheet = "final")

scenarios <- read_excel("intermediate-data/scenarios/soy-scenarios.xlsx") %>% as.data.frame()

## Use a local temporary folder to avoid Box sync conflicts
local_proc_dir <- "C:/temp/apsim-proc"

##creating an apsim copy
file.copy(paste0("processed-data/_soybean-daily-05-14-25.apsimx"),
          paste0(local_proc_dir,"/grid-simulation-file.apsimx"),
          overwrite = TRUE)

## grid and soil file index
sim.grid$cellid <- 1:nrow(sim.grid)

## Changing the clock
edit_apsimx(file = 'grid-simulation-file.apsimx',
            src.dir = local_proc_dir,
            wrt.dir = local_proc_dir,
            node = 'Clock',
            parm = 'Start',
            value = '1985-01-01',#half period
            overwrite = TRUE)

#getting the last date from met file

#getting the last date from met file
weather_path <- normalizePath(file.path(getwd(), "intermediate-data", "weather-historical","\\"))
iem <- read_table(paste0(weather_path,"1.met"),skip = 8,col_names = FALSE) %>% 
  mutate(date=ymd(paste0(X1,"-01-01"))+X2-1)
latest_date <- as.character(max(iem$date))

edit_apsimx(file = 'grid-simulation-file.apsimx',
            src.dir = local_proc_dir,
            wrt.dir = local_proc_dir,
            node = 'Clock',
            parm = 'End',
            value = latest_date,
            overwrite = TRUE)

final.df <- vector('list', nrow(scenarios))

for (i in 1:nrow(scenarios)){

  edit_apsimx(file = 'grid-simulation-file.apsimx',
              src.dir = local_proc_dir,
              wrt.dir = local_proc_dir,
              node = 'Other',
              parm.path = '.Simulations.Simulation.Field.SowSoybean.CultivarName',
              value = scenarios[i, 'cultivar'],
              verbose = FALSE,
              overwrite = TRUE)
  
  edit_apsimx(file = 'grid-simulation-file.apsimx',
              src.dir = local_proc_dir,
              wrt.dir = local_proc_dir,
              node = 'Other',
              parm.path = '.Simulations.Simulation.Field.SowSoybean.SowDate',
              value = scenarios[i, 'sowing'],
              verbose = FALSE,
              overwrite = TRUE)
  
  edit_apsimx(file = 'grid-simulation-file.apsimx',
              src.dir = local_proc_dir,
              wrt.dir = local_proc_dir,
              node = 'Other',
              parm.path = '.Simulations.Simulation.Field.ClimateController.EnableDate',
              value = scenarios[i, 'climate.control'],
              verbose = FALSE,
              overwrite = TRUE)
  
  edit_apsimx(file = 'grid-simulation-file.apsimx',
              src.dir = local_proc_dir,
              wrt.dir = local_proc_dir,
              node = 'Other',
              parm.path = '.Simulations.Simulation.Field.SowSoybean.RowSpacing',
              value = scenarios[i, 'RowSpacing'],
              verbose = FALSE,
              overwrite = TRUE)
  
  edit_apsimx(file = 'grid-simulation-file.apsimx',
              src.dir = local_proc_dir,
              wrt.dir = local_proc_dir,
              node = 'Other',
              parm.path = '.Simulations.Simulation.Field.CO2.CO2',
              value = scenarios[i, 'co2'],
              verbose = FALSE,
              overwrite = TRUE)
  
  max.cores <- parallel::detectCores(logical = FALSE)
  ncores <- ifelse(cores > max.cores, max.cores, cores)
  cl <- parallel::makeCluster(ncores, outfile = 'log.txt')
  parallel::clusterEvalQ(cl, {library('apsimx')})
  
  parallel::clusterExport(cl, 
                          c('sim.grid', 'scenarios', 'i'))
  
  cat('Running scenario ', i, '\n')
  print(scenarios[i, ])
  
  scenario.df <- parallel::parLapply(cl,
                                     1:nrow(sim.grid),
                                     function(j){
                                       j <- 3
                                       #paths (the ones from the R project were not working)
                                       weather_path <- normalizePath(file.path(getwd(), "intermediate-data", "weather-historical","\\"))
                                       soil_path <- normalizePath(file.path(getwd(), "intermediate-data", "soil-historical","\\"))
                                       crop_path <- normalizePath(file.path(getwd(), "intermediate-data", "crop_historical","\\"))

                                      cat('Processing cell # ', j, ' out of ', nrow(sim.grid),"| Scenario = ",scenarios$scenario[i]," | CO2 = ",scenarios$co2[i],"(# ",i," out of ",nrow(scenarios),")", '\n')
                                      
                                      ## Use a local temporary folder to avoid Box sync conflicts
                                       local_proc_dir <- "C:/temp/apsim-proc"
                                       
                                       #Creating a temporary APSIM file
                                       par.sim.file <- paste0('par-sim-',j,'.apsimx')
                                       
                                       file.copy(file.path(local_proc_dir, 'grid-simulation-file.apsimx'),
                                                 file.path(local_proc_dir, par.sim.file),
                                                 overwrite = TRUE)
                                       
                                       edit_apsimx(file = par.sim.file,
                                                   src.dir = local_proc_dir,
                                                   wrt.dir = local_proc_dir,
                                                   node = 'Weather',
                                                   value = paste0(weather_path, j, '.met'),
                                                   overwrite = TRUE,
                                                   verbose = FALSE)
                                       
                                       soil.result <- readRDS(paste0(soil_path, j, '.rds'))
                                       soils <- soil.result[[1]]
                                       
                                       ## determining the fraction of the simulation for each
                                       ## soil
                                       soil.fractions <- sapply(1:length(soils), function(k) {
                                         mtd <- strsplit(soils[[k]]$metadata$Comments, '-')
                                         mtd <- grep('component percent', mtd[[1]], value= TRUE)
                                         regmatches(mtd, regexpr('[0-9]{1,}([.][0-9]{0,})?',mtd))
                                       })
                                       
                                       soil.fractions <- as.numeric(soil.fractions) / 100
                                       
                                       soils <- lapply(soils, 
                                                       function(sp){
                                                         sp <- apsimx:::fix_apsimx_soil_profile(sp, verbose = FALSE)
                                                         sp$initialwater <- initialwater_parms(Depth = sp$soil$Depth,
                                                                                               Thickness = sp$soil$Thickness,
                                                                                               InitialValues = sp$soil$DUL)
                                                         
                                                         sp
                                                       })
                                       
                                       soil.sims <- list()
                                       
                                       for (k in 1:length(soils)){
                                      
                                       edit_apsimx_replace_soil_profile(file = par.sim.file,
                                                                        src.dir = local_proc_dir,
                                                                        wrt.dir = local_proc_dir,
                                                                        soil.profile = soils[[k]],
                                                                        verbose = FALSE,
                                                                        overwrite = TRUE)
                                       
                                         kl <- c(0.08,0.08,0.08,0.08,0.07,0.07,0.07,0.07,0.06,0.06,0.06,0.06,0.05,0.05,0.04,0.04,0.03,0.03,0.02,0.02)
                                         xf <- c(1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0)
                                      
                                          edit_apsimx(file = par.sim.file,
                                                   src.dir = local_proc_dir,
                                                   wrt.dir = local_proc_dir,
                                                   node = "Soil",
                                                   soil.child = "Physical", 
                                                   parm = "KL", value = kl,
                                                   verbose = FALSE,
                                                   overwrite = TRUE)
                                       
                                       edit_apsimx(file = par.sim.file,
                                                   src.dir = local_proc_dir,
                                                   wrt.dir = local_proc_dir,
                                                   node = "Soil",
                                                   soil.child = "Physical", 
                                                   parm = "XF", value = xf,
                                                   verbose = FALSE,
                                                   overwrite = TRUE)
                                       
                                       sim <- try(apsimx(file = par.sim.file,
                                                         src.dir =local_proc_dir,
                                                         cleanup = TRUE), silent = TRUE)
                                       
                                       if (inherits(sim, 'try-error')) {
                                         soil.fractions[k] <- NA 
                                         return(NULL)
                                       }
                                       
                                       sim$soil.profile <- k
                                       sim$soil.fraction <- soil.fractions[k]
                                       soil.sims[[length(soil.sims) + 1]] <- sim
                                       }
                                       
                                       if (length(soil.sims) < 1) return(NULL)
                                       
                                       soil.fractions <- na.omit(soil.fractions)
                                       
                                       source('./code/variables.R', local = environment())

                                       ans <- data.frame(cultivar = rep(scenarios$cultivar[i],nrow(sim)),
                                                         sowing = rep(scenarios$sowing[i],nrow(sim)),
                                                         scenario = rep(scenarios$scenario[i],nrow(sim)),
                                                         climate.control = rep(scenarios$climate.control[i],nrow(sim)),
                                                         co2 = rep(scenarios$co2[i],nrow(sim)),
                                                         rowSpacing = rep(scenarios$RowSpacing[i],nrow(sim)),
                                                         date = dates,
                                                         Yield_kgha = Yield_kgha,
                                                         Biomass_kgha = Biomass_kgha,
                                                         rel_sw_6in = rel_sw_6in,
                                                         rel_sw_12in = rel_sw_12in,
                                                         rel_sw_24in = rel_sw_24in,
                                                         swhc_6in = swhc_6in,
                                                         swhc_12in = swhc_12in,
                                                         swhc_24in = sim$swhc_24in,
                                                         CummRain_fromApril = CummRain_fromApril,
                                                         CummThermalTime = CummThermalTime,
                                                         Weather.Rain = Weather.Rain,
                                                         CummET = CummET,
                                                         CummPotentialET = CummPotentialET,
                                                         Supply_Demand_Ratio,
                                                         CummIrrigation)
                                       
                                       ans <- merge(sim.grid[j,],
                                                    ans)
                                       
                                       readr::write_csv(ans,
                                                        paste0(crop_path, j,".csv"))

                                       #file.remove(file.path(local_proc_dir, par.sim.file))
                                      return(ans)
                                     })
  
  parallel::stopCluster(cl)
  
    scenario.df <- do.call(rbind, scenario.df)
  
  final.df[[i]] <- scenario.df
  
}

final.df <- do.call(rbind, final.df)

saveRDS(final.df, './intermediate-data/simulated-scenarios-historical-df.rds')
write_csv(final.df, './intermediate-data/simulated-scenarios-historical-df.csv')


