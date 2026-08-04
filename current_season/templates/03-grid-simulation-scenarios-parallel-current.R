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
cores <- 1

#?apsimx_options()
#My desktop
apsimx_options(exe.path = 'C:\\Users\\efelli\\AppData\\Local\\Programs\\APSIM2025.3.7681.0\\bin\\Models.exe')
#Aurelie
#apsimx_options(exe.path = 'C:\\Users\\efelli\\AppData\\Local\\Programs\\APSIM2025.3.7681.0\\bin\\Models.exe')

apsim_version(which = c("inuse"))

## reading the simulation grid & scenarios
sim.grid <- readRDS('./intermediate-data/sim-grid.rds')

scenarios <- read_excel("intermediate-data/scenarios/soy-scenarios.xlsx") %>% as.data.frame()

## Use a local temporary folder to avoid Box sync conflicts
local_proc_dir <- "C:/temp/apsim-proc"

##creating an apsim copy
file.copy(paste0("processed-data/_soybean-daily-04-30-25.apsimx"),
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
            value = '2025-01-01',
            overwrite = TRUE)

#getting the last date from met file
weather_path <- normalizePath(file.path(getwd(), "intermediate-data", "weather","\\"))
iem <- read_table(paste0(weather_path,"142.met"),skip = 8,col_names = FALSE) %>% 
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

 #this_scenario <- scenarios$scenario[i]
 # this_co2 <- scenarios$co2[i]
  
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
  
  ?edit_apsimx(file = 'grid-simulation-file.apsimx',
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
                                     #1:150,#nrow(sim.grid),
                                     function(j){
j <- 142
                                       #paths (the ones from the R project were not working)
                                       weather_path <- normalizePath(file.path(getwd(), "intermediate-data", "weather","\\"))
                                       soil_path <- normalizePath(file.path(getwd(), "..", "soybean-ar-climate-change", "intermediate-data", "soil","\\"))
                                       crop_path <- normalizePath(file.path(getwd(), "intermediate-data", "crop_current","\\"))
                                      #j<-142
                                      #17458
                                       if (is.na(sim.grid[j, 'cultivated']))
                                         return(NULL)
                                       cat('Processing cell # ', j, ' out of ', nrow(sim.grid),"| Scenario = ",scenarios$scenario[i]," | CO2 = ",scenarios$co2[i],"(# ",i," out of ",nrow(scenarios),")", '\n')
                                      
                                       if (j %in% seq(1, nrow(sim.grid), 250)){
                                         cat(paste("Sleeping after simulation #", j))
                                         Sys.sleep(5 * 60)
                                       }
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
                                       
                                       soil.result <- try(readRDS(paste0(soil_path, j, '.rds')), silent = TRUE)
                                       
                                       if (inherits(soil.result, "try-error") || 
                                           !is.list(soil.result) ||
                                           length(soil.result) < 1 || 
                                           !is.list(soil.result[[1]]) || 
                                           length(soil.result[[1]]) < 1 || 
                                           !inherits(soil.result[[1]][[1]], "soil_profile")) {
                                         
                                         return(NULL)
                                       }
                                       
                                       soils <- soil.result[[1]][[1]]
                                       kl <- c(0.08,0.08,0.08,0.08,0.07,0.07,0.07,0.07,0.06,0.06,0.06,0.06,0.05,0.05,0.04,0.04,0.03,0.03,0.02,0.02)
                                       xf <- c(1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0)
                                       
                                       #not working
                                       soils <- apsimx:::fix_apsimx_soil_profile(soils, verbose = FALSE)
                                       soils$soil$KL <- kl
                                       soils$soil$XF <- xf
                                       #soils$soil$Maize.KL <- kl
                                       #soils$soil$Maize.XF <- xf
                                       soils$initialwater <- initialwater_parms(Depth = soils$soil$Depth, Thickness = soils$soil$Thickness, InitialValues = soils$soil$DUL)
                                       
                                       edit_apsimx_replace_soil_profile(file = par.sim.file,
                                                                        src.dir = local_proc_dir,
                                                                        wrt.dir = local_proc_dir,
                                                                        soil.profile = soils,
                                                                        verbose = FALSE,
                                                                        overwrite = TRUE)
                                       #this is working, only for soybean, the first crop in the list
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
                                       
                                       sim <- try(apsimx(file = par.sim.file, src.dir = local_proc_dir, cleanup = TRUE), silent = TRUE)
                                      
                                       if (inherits(sim, "try-error")) return(NULL)

                                       ans <- data.frame(cultivar = rep(scenarios$cultivar[i],nrow(sim)),
                                                         sowing = rep(scenarios$sowing[i],nrow(sim)),
                                                         scenario = rep(scenarios$scenario[i],nrow(sim)),
                                                         climate.control = rep(scenarios$climate.control[i],nrow(sim)),
                                                         co2 = rep(scenarios$co2[i],nrow(sim)),
                                                         rowSpacing = rep(scenarios$RowSpacing[i],nrow(sim)),
                                                         date = sim$Date,
                                                         Yield_kgha = sim$Yield_kgha,
                                                         Biomass_kgha = sim$Biomass_kgha,
                                                         rel_sw_6in = sim$rel_sw_6in,
                                                         rel_sw_12in = sim$rel_sw_12in,
                                                         rel_sw_24in = sim$rel_sw_24in,
                                                         swhc_6in = sim$swhc_6in,
                                                         swhc_12in = sim$swhc_12in,
                                                         swhc_24in = sim$swhc_24in,
                                                         CummRain_fromApril = sim$CummRain_fromApril,
                                                         CummThermalTime = sim$CummThermalTime)
                                       
                                       ans <- merge(sim.grid[j,],
                                                    ans)
                                       
                                       readr::write_csv(ans,
                                                        paste0(crop_path, j,".csv"))

                                       file.remove(file.path(local_proc_dir, par.sim.file))
                                                                              return(ans)
                                     })
  
  parallel::stopCluster(cl)
  
    scenario.df <- do.call(rbind, scenario.df)
  
  final.df[[i]] <- scenario.df
  
}

final.df <- do.call(rbind, final.df)

saveRDS(final.df, './intermediate-data/simulated-scenarios-current-df.rds')
write_csv(final.df, './intermediate-data/simulated-scenarios-current-df.csv')

##change climate control column
