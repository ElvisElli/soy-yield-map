##
Yield_kgha <- lapply(soil.sims, function(df) df[c('Date', 'Yield_kgha')])
Yield_kgha <- Reduce(function(x, y) merge(x, y, by = 'Date'), Yield_kgha)
dates <-  Yield_kgha$Date
Yield_kgha <- matrix(unlist(Yield_kgha[-1]), ncol = length(soil.sims))
Yield_kgha <- apply(Yield_kgha, 1, function(br) weighted.mean(br, soil.fractions))

##
Biomass_kgha <- lapply(soil.sims, function(df) df[c('Date', 'Biomass_kgha')])
Biomass_kgha <- Reduce(function(x, y) merge(x, y, by = 'Date'), Biomass_kgha)
dates <-  Biomass_kgha$Date
Biomass_kgha <- matrix(unlist(Biomass_kgha[-1]), ncol = length(soil.sims))
Biomass_kgha <- apply(Biomass_kgha, 1, function(br) weighted.mean(br, soil.fractions))

##
rel_sw_6in <- lapply(soil.sims, function(df) df[c('Date', 'rel_sw_6in')])
rel_sw_6in <- Reduce(function(x, y) merge(x, y, by = 'Date'), rel_sw_6in)
dates <-  rel_sw_6in$Date
rel_sw_6in <- matrix(unlist(rel_sw_6in[-1]), ncol = length(soil.sims))
rel_sw_6in <- apply(rel_sw_6in, 1, function(br) weighted.mean(br, soil.fractions))


##
rel_sw_12in <- lapply(soil.sims, function(df) df[c('Date', 'rel_sw_12in')])
rel_sw_12in <- Reduce(function(x, y) merge(x, y, by = 'Date'), rel_sw_12in)
dates <-  rel_sw_12in$Date
rel_sw_12in <- matrix(unlist(rel_sw_12in[-1]), ncol = length(soil.sims))
rel_sw_12in <- apply(rel_sw_12in, 1, function(br) weighted.mean(br, soil.fractions))

##
rel_sw_24in <- lapply(soil.sims, function(df) df[c('Date', 'rel_sw_24in')])
rel_sw_24in <- Reduce(function(x, y) merge(x, y, by = 'Date'), rel_sw_24in)
dates <-  rel_sw_24in$Date
rel_sw_24in <- matrix(unlist(rel_sw_24in[-1]), ncol = length(soil.sims))
rel_sw_24in <- apply(rel_sw_24in, 1, function(br) weighted.mean(br, soil.fractions))

##
swhc_6in <- lapply(soil.sims, function(df) df[c('Date', 'swhc_6in')])
swhc_6in <- Reduce(function(x, y) merge(x, y, by = 'Date'), swhc_6in)
dates <-  swhc_6in$Date
swhc_6in <- matrix(unlist(swhc_6in[-1]), ncol = length(soil.sims))
swhc_6in <- apply(swhc_6in, 1, function(br) weighted.mean(br, soil.fractions))


##
swhc_12in <- lapply(soil.sims, function(df) df[c('Date', 'swhc_12in')])
swhc_12in <- Reduce(function(x, y) merge(x, y, by = 'Date'), swhc_12in)
dates <-  swhc_12in$Date
swhc_12in <- matrix(unlist(swhc_12in[-1]), ncol = length(soil.sims))
swhc_12in <- apply(swhc_12in, 1, function(br) weighted.mean(br, soil.fractions))

##
swhc_24in <- lapply(soil.sims, function(df) df[c('Date', 'swhc_24in')])
swhc_24in <- Reduce(function(x, y) merge(x, y, by = 'Date'), swhc_24in)
dates <-  swhc_24in$Date
swhc_24in <- matrix(unlist(swhc_24in[-1]), ncol = length(soil.sims))
swhc_24in <- apply(swhc_24in, 1, function(br) weighted.mean(br, soil.fractions))

##
CummRain_fromApril <- lapply(soil.sims, function(df) df[c('Date', 'CummRain_fromApril')])
CummRain_fromApril <- Reduce(function(x, y) merge(x, y, by = 'Date'), CummRain_fromApril)
dates <-  CummRain_fromApril$Date
CummRain_fromApril <- matrix(unlist(CummRain_fromApril[-1]), ncol = length(soil.sims))
CummRain_fromApril <- apply(CummRain_fromApril, 1, function(br) weighted.mean(br, soil.fractions))

##
CummThermalTime <- lapply(soil.sims, function(df) df[c('Date', 'CummThermalTime')])
CummThermalTime <- Reduce(function(x, y) merge(x, y, by = 'Date'), CummThermalTime)
dates <-  CummThermalTime$Date
CummThermalTime <- matrix(unlist(CummThermalTime[-1]), ncol = length(soil.sims))
CummThermalTime <- apply(CummThermalTime, 1, function(br) weighted.mean(br, soil.fractions))

##
Weather.Rain <- lapply(soil.sims, function(df) df[c('Date', 'Weather.Rain')])
Weather.Rain <- Reduce(function(x, y) merge(x, y, by = 'Date'), Weather.Rain)
dates <-  Weather.Rain$Date
Weather.Rain <- matrix(unlist(Weather.Rain[-1]), ncol = length(soil.sims))
Weather.Rain <- apply(Weather.Rain, 1, function(br) weighted.mean(br, soil.fractions))

##
CummET <- lapply(soil.sims, function(df) df[c('Date', 'CummET')])
CummET <- Reduce(function(x, y) merge(x, y, by = 'Date'), CummET)
dates <-  CummET$Date
CummET <- matrix(unlist(CummET[-1]), ncol = length(soil.sims))
CummET <- apply(CummET, 1, function(br) weighted.mean(br, soil.fractions))

##
CummPotentialET <- lapply(soil.sims, function(df) df[c('Date', 'CummPotentialET')])
CummPotentialET <- Reduce(function(x, y) merge(x, y, by = 'Date'), CummPotentialET)
dates <-  CummPotentialET$Date
CummPotentialET <- matrix(unlist(CummPotentialET[-1]), ncol = length(soil.sims))
CummPotentialET <- apply(CummPotentialET, 1, function(br) weighted.mean(br, soil.fractions))

##
Supply_Demand_Ratio <- lapply(soil.sims, function(df) df[c('Date', 'Supply_Demand_Ratio')])
Supply_Demand_Ratio <- Reduce(function(x, y) merge(x, y, by = 'Date'), Supply_Demand_Ratio)
dates <-  Supply_Demand_Ratio$Date
Supply_Demand_Ratio <- matrix(unlist(Supply_Demand_Ratio[-1]), ncol = length(soil.sims))
Supply_Demand_Ratio <- apply(Supply_Demand_Ratio, 1, function(br) weighted.mean(br, soil.fractions))

##
CummIrrigation <- lapply(soil.sims, function(df) df[c('Date', 'CummIrrigation')])
CummIrrigation <- Reduce(function(x, y) merge(x, y, by = 'Date'), CummIrrigation)
dates <-  CummIrrigation$Date
CummIrrigation <- matrix(unlist(CummIrrigation[-1]), ncol = length(soil.sims))
CummIrrigation <- apply(CummIrrigation, 1, function(br) weighted.mean(br, soil.fractions))
