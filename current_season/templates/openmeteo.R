get_openmeteo_daily <- function(lonlat, start_date, end_date) {
  library(httr)
  library(jsonlite)
  
  lat <- lonlat[2]
  lon <- lonlat[1]
  
  variables <- c("temperature_2m_max", "temperature_2m_min",
                 "shortwave_radiation_sum", "precipitation_sum")
  
  url <- paste0(
    "https://api.open-meteo.com/v1/forecast?",
    "latitude=", lat,
    "&longitude=", lon,
    "&daily=", paste(variables, collapse = ","),
    "&start_date=", start_date,
    "&end_date=", end_date,
    "&timezone=auto"
  )
  
  response <- try(GET(url), silent = TRUE)
  
  ## Pause to ensure we do not exceed API rate limit
  Sys.sleep(5)  # 2 requests per second
  
  if (inherits(response, "try-error")) return(NULL)
  
  data <- try(fromJSON(content(response, as = "text")), silent = TRUE)
  if (inherits(data, "try-error") || is.null(data$daily)) return(NULL)
  
  forecast <- data.frame(
    date = as.Date(data$daily$time),
    t_max = data$daily$temperature_2m_max,
    t_min = data$daily$temperature_2m_min,
    solar_rad = data$daily$shortwave_radiation_sum,
    precipitation = data$daily$precipitation_sum
  )
  
  forecast$year <- as.numeric(format(forecast$date, "%Y"))
  forecast$day  <- as.numeric(format(forecast$date, "%j"))
  
  forecast <- forecast[, c("year", "day", "solar_rad", "t_max", "t_min", "precipitation")]
  colnames(forecast) <- c("year", "day", "radn", "maxt", "mint", "rain")
  
  return(forecast)
}