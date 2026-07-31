## ============================================================
## soy-yield-map — interactive soybean yield-gap map for Arkansas
##
## A farmer enters their field location, their maturity group / planting date,
## and their own measured yield. The app shows the APSIM-simulated yield
## distribution at that location for the selected practice, and how their
## reported yield compares (the yield gap), on a map styled like the study's
## manuscript figures (state + county boundaries, eastern-Arkansas crop).
##
## Yield note: APSIM reports Yield_kgha as DRY grain (0% moisture). Market
## yields (and bushels, defined at 13% moisture) are higher, so on load we
## gross the simulated yields up to 13% moisture and display everything on that
## basis — consistent with a grower's measured, market-moisture yield.
##
## Single-file Shiny app. Runs locally (shiny::runApp("app")), on a Shiny
## server, or as a static WebAssembly site via shinylive (see .github). Uses
## only shiny + bslib + ggplot2 — no sf/leaflet — so the shinylive build stays
## light; all map projection is pre-baked by simulation/export-app-data.R.
##
## Data contract: app/data/yield-surface.csv (+ ar-state.csv, ar-counties.csv),
## produced by simulation/export-app-data.R.
## ============================================================

library(shiny)
library(bslib)
library(ggplot2)

source("R/helpers.R", local = TRUE)
source("R/plots.R", local = TRUE)

## ── Load the yield surface (base read.csv keeps webR/shinylive happy) ─────
SURFACE <- read.csv("data/yield-surface.csv", stringsAsFactors = FALSE)
SURFACE$co2 <- as.integer(SURFACE$co2)

## This version focuses on the current-climate baseline only.
SURFACE <- SURFACE[SURFACE$climate == "current", , drop = FALSE]

## Gross APSIM dry yields up to 13% market moisture (see header note).
GRAIN_MOISTURE <- 0.13
ycols <- grep("^yield_.*_kgha$", names(SURFACE), value = TRUE)
SURFACE[ycols] <- SURFACE[ycols] / (1 - GRAIN_MOISTURE)

## Restrict to eastern Arkansas (the soybean region) — matches the manuscript
## maps' coord_sf(xlim = c(360000, 570000)) crop.
SURFACE <- SURFACE[SURFACE$x_alb >= 360000 & SURFACE$x_alb <= 570000, , drop = FALSE]

## Boundaries (pre-projected to EPSG:5070 by the export script)
STATE_DF  <- read.csv("data/ar-state.csv",   stringsAsFactors = FALSE)
COUNTY_DF <- read.csv("data/ar-counties.csv", stringsAsFactors = FALSE)

## Unique cells for the map / nearest-cell search
CELLS <- unique(SURFACE[, c("cellid", "x", "y", "x_alb", "y_alb")])

## Practice choices, constrained to what was actually simulated
MG_CHOICES     <- sort(unique(SURFACE$mg))
window_choices <- function(mg) sort(unique(SURFACE$plant_window[SURFACE$mg == mg]))

## Shared colour scale across the map (market kg/ha)
FILL_LIMITS <- range(SURFACE$yield_mean_kgha, na.rm = TRUE)

## ── UI ───────────────────────────────────────────────────────────────────
ui <- page_sidebar(
  title = "Arkansas Soybean Yield-Gap Map",
  theme = bs_theme(version = 5, bootswatch = "flatly",
                   primary = "#9D2235", secondary = "#54585A"),

  sidebar = sidebar(
    width = 340,
    h5("Your field"),
    fluidRow(
      column(6, numericInput("lat", "Latitude", value = 34.75,
                             min = 33, max = 36.6, step = 0.01)),
      column(6, numericInput("lon", "Longitude", value = -91.5,
                             min = -95, max = -89.5, step = 0.01))
    ),
    helpText("Enter your field's coordinates to locate it on the map."),
    hr(),

    h5("Your practice"),
    selectInput("mg", "Maturity group", choices = MG_CHOICES),
    selectInput("window", "Planting window", choices = NULL),
    hr(),

    h5("Your yield"),
    fluidRow(
      column(7, numericInput("myyield", "Measured yield", value = 50, min = 0)),
      column(5, radioButtons("unit", "Units",
                             c("bu/ac", "kg/ha"), selected = "bu/ac"))
    ),
    helpText("Yields shown at 13% market moisture."),
    hr(),
    helpText(textOutput("provenance", inline = TRUE))
  ),

  card(
    card_header(textOutput("plots_header", inline = TRUE)),
    plotOutput("boxplot", height = 340)
  ),
  card(
    full_screen = TRUE,
    card_header("Simulated soybean yield across eastern Arkansas"),
    plotOutput("map", height = 520)
  ),
  card(
    card_header("What this means for your field"),
    uiOutput("explain")
  )
)

## ── Server ─────────────────────────────────────────────────────────────────
server <- function(input, output, session) {

  ## Planting-window choices follow the selected maturity group
  observeEvent(input$mg, {
    wins <- window_choices(input$mg)
    sel <- if ("late May" %in% wins) "late May" else wins[1]
    updateSelectInput(session, "window", choices = wins, selected = sel)
  }, ignoreInit = FALSE)

  ## Selected cell (nearest simulated grid cell to the entered coordinates)
  cell <- reactive({
    nearest_cell(CELLS, input$lat, input$lon)
  })

  ## Simulated row for the selected practice at that cell (market kg/ha)
  pred_row <- reactive({
    c <- cell(); req(c, input$mg, input$window)
    lookup_practice(SURFACE, c$cellid, input$mg, input$window, "current", 350L)
  })

  ## Farmer's yield in market kg/ha
  my_kgha <- reactive({
    v <- input$myyield
    if (is.null(v) || is.na(v)) return(NA_real_)
    if (identical(input$unit, "bu/ac")) buac_to_kgha(v) else v
  })

  ## ── Boxplot ─────────────────────────────────────────────────────────────
  output$plots_header <- renderText({
    c <- cell()
    if (is.null(c)) "Yield distribution" else
      sprintf("Yield distribution at your field (nearest cell %.1f km away)",
              c$dist_km)
  })

  output$boxplot <- renderPlot({
    pr <- pred_row(); req(pr)
    make_boxplot(pr, observed_kgha = my_kgha(), unit = input$unit,
                 scenario_label = practice_label(pr))
  }, res = 96)

  ## ── Map (ggplot: state + county + yield raster + farm) ──────────────────
  map_cells <- reactive({
    d <- SURFACE[SURFACE$mg == input$mg & SURFACE$plant_window == input$window, ]
    if (nrow(d) == 0) d <- SURFACE[SURFACE$scenario == "baseline", ]
    unique(d[, c("x_alb", "y_alb", "yield_mean_kgha")])
  })

  output$map <- renderPlot({
    c <- cell()
    farm <- if (is.null(c)) NULL else c(c$x_alb, c$y_alb)
    make_map(map_cells(), STATE_DF, COUNTY_DF, farm = farm,
             unit = input$unit, fill_limits = FILL_LIMITS)
  }, res = 96)

  ## ── Narrative explanation ──────────────────────────────────────────────
  output$explain <- renderUI({
    c <- cell(); pr <- pred_row(); v <- my_kgha()
    if (is.null(c)) return(helpText("Enter your field coordinates to begin."))
    parts <- list()
    if (!is.null(pr)) {
      parts <- c(parts, sprintf(
        "At your field (nearest simulated cell %s km away), APSIM simulates a mean yield of %s for %s (40-year average at 13%% moisture; typical range %s–%s).",
        round(c$dist_km, 1),
        fmt_yield(pr$yield_mean_kgha, input$unit),
        practice_label(pr),
        fmt_yield(pr$yield_p10_kgha, input$unit),
        fmt_yield(pr$yield_p90_kgha, input$unit)))
    }
    if (!is.null(pr) && !is.na(v)) {
      gap <- pr$yield_mean_kgha - v
      parts <- c(parts, if (gap > 0)
        sprintf("Your reported yield of %s is %s below the simulated mean — a potential gap to close through management.",
                fmt_yield(v, input$unit), fmt_yield(gap, input$unit))
        else
        sprintf("Your reported yield of %s meets or exceeds the simulated mean — you are farming at or above the simulated potential here.",
                fmt_yield(v, input$unit)))
    }
    tagList(lapply(parts, function(p) tags$p(p)))
  })

  output$provenance <- renderText({
    meta <- tryCatch(readLines("data/yield-surface-meta.json", warn = FALSE),
                     error = function(e) NULL)
    gen <- if (!is.null(meta)) sub('.*"generated":\\s*"([^"]+)".*', "\\1",
                                   paste(meta, collapse = " ")) else "?"
    paste0("Data: APSIM NG grid simulation, ", nrow(CELLS),
           " cells. Generated ", gen, ".")
  })
}

shinyApp(ui, server)
