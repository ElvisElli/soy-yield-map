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
library(leaflet)

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

## Restrict to eastern Arkansas (the soybean region) — drops the sparse western
## cells so the interactive map shows only the delta cropland.
SURFACE <- SURFACE[SURFACE$x_alb >= 360000 & SURFACE$x_alb <= 570000, , drop = FALSE]

## Unique cells for the map / nearest-cell search
CELLS <- unique(SURFACE[, c("cellid", "x", "y")])

## Practice choices, constrained to what was actually simulated
MG_CHOICES     <- sort(unique(SURFACE$mg))
window_choices <- function(mg) sort(unique(SURFACE$plant_window[SURFACE$mg == mg]))

## Shared colour scale for the map (market kg/ha)
YIELD_RANGE <- range(SURFACE$yield_mean_kgha, na.rm = TRUE)
pal <- leaflet::colorNumeric(UARK$ramp, domain = YIELD_RANGE, na.color = "#e6e6e6")

## Full Arkansas state + county outlines (lon/lat), drawn as the map background.
## NA separators let a single addPolylines() call draw every ring.
STATE_DF  <- read.csv("data/ar-state.csv",   stringsAsFactors = FALSE)
COUNTY_DF <- read.csv("data/ar-counties.csv", stringsAsFactors = FALSE)
poly_na <- function(df) {
  parts <- split(df, df$group)
  list(lng = unlist(lapply(parts, function(p) c(p$x, NA))),
       lat = unlist(lapply(parts, function(p) c(p$y, NA))))
}
STATE_LINE  <- poly_na(STATE_DF)
COUNTY_LINE <- poly_na(COUNTY_DF)
## Pad the state bounding box so neighbouring states show in the background.
.pad <- 1.1
STATE_BB <- list(lng = range(STATE_DF$x) + c(-.pad, .pad),
                 lat = range(STATE_DF$y) + c(-.pad, .pad))

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
    helpText("Type coordinates or click the map to drop a pin."),
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
    fill = FALSE,
    card_header("Potential vs. actual yield"),
    layout_column_wrap(
      width = 1/3, fixed_width = FALSE, heights_equal = "row", gap = "0.5rem",
      value_box("Potential yield", textOutput("vb_pot"), max_height = "130px",
                theme = value_box_theme(bg = "#9D2235", fg = "white")),
      value_box("Actual yield", textOutput("vb_act"), max_height = "130px",
                theme = value_box_theme(bg = "#3F5B74", fg = "white")),
      value_box("Yield gap", textOutput("vb_gap"), max_height = "130px",
                theme = value_box_theme(bg = "#B0842F", fg = "white"))
    ),
    plotOutput("barplot", height = "260px")
  ),
  card(
    full_screen = TRUE,
    card_header("Potential yield across Arkansas"),
    leafletOutput("map", height = 520)
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

  ## ── Value tiles (always bu/ac) + bar plot ───────────────────────────────
  output$vb_pot <- renderText({ pr <- pred_row(); req(pr); fmt_buac(pr$yield_mean_kgha) })
  output$vb_act <- renderText(fmt_buac(my_kgha()))
  output$vb_gap <- renderText({
    pr <- pred_row(); v <- my_kgha()
    if (is.null(pr) || is.na(v)) "—" else fmt_buac(pr$yield_mean_kgha - v)
  })

  output$barplot <- renderPlot({
    pr <- pred_row(); req(pr)
    make_barplot(pr, observed_kgha = my_kgha(), unit = input$unit)
  }, res = 96)

  ## ── Interactive map (Leaflet: pan/zoom basemap + yield points + farm) ────
  map_cells <- reactive({
    d <- SURFACE[SURFACE$mg == input$mg & SURFACE$plant_window == input$window, ]
    if (nrow(d) == 0) d <- SURFACE[SURFACE$scenario == "baseline", ]
    unique(d[, c("x", "y", "yield_mean_kgha", "yield_median_kgha")])
  })
  legend_vals <- reactive(seq(YIELD_RANGE[1], YIELD_RANGE[2], length.out = 5))

  output$map <- renderLeaflet({
    leaflet(options = leafletOptions(minZoom = 6, maxZoom = 13,
                                     preferCanvas = TRUE)) |>
      addProviderTiles(providers$CartoDB.Positron, group = "Map") |>
      addProviderTiles(providers$Esri.WorldImagery, group = "Satellite") |>
      addLayersControl(baseGroups = c("Map", "Satellite"),
                       options = layersControlOptions(collapsed = TRUE)) |>
      ## whole-state background: county lines (thin) + state outline (bold)
      addPolylines(lng = COUNTY_LINE$lng, lat = COUNTY_LINE$lat,
                   color = "#8a8a8a", weight = 0.6, opacity = 0.7,
                   group = "boundaries") |>
      addPolylines(lng = STATE_LINE$lng, lat = STATE_LINE$lat,
                   color = "#54585A", weight = 1.6, opacity = 0.9,
                   group = "boundaries") |>
      fitBounds(STATE_BB$lng[1], STATE_BB$lat[1],
                STATE_BB$lng[2], STATE_BB$lat[2])
  })

  ## Draw the yield surface for the selected practice (canvas circle markers)
  observe({
    d <- map_cells(); unit <- input$unit
    fmt_v <- function(v) vapply(v, function(x) fmt_yield(x, unit), character(1))
    labs <- sprintf("<b>%s</b><br>median %s",
                    fmt_v(d$yield_mean_kgha), fmt_v(d$yield_median_kgha))
    leafletProxy("map", data = d) |>
      clearGroup("cells") |>
      removeControl("yield-legend") |>
      addCircleMarkers(
        group = "cells", lng = ~x, lat = ~y, radius = 5,
        stroke = FALSE, fillOpacity = 0.9, fillColor = ~pal(yield_mean_kgha),
        label = lapply(labs, htmltools::HTML)) |>
      addLegend("bottomright", layerId = "yield-legend",
                colors = pal(legend_vals()),
                labels = vapply(legend_vals(), function(v) fmt_yield(v, unit),
                                character(1)),
                title = paste0("Potential yield<br>(", unit, ")"), opacity = 0.9)
  })

  ## Cardinal farm marker (follows the coordinates) + click-to-set
  farm_icon <- makeAwesomeIcon(icon = "map-marker", markerColor = "darkred",
                               iconColor = "#ffffff", library = "fa")
  observe({
    c <- cell(); req(c); pr <- pred_row()
    txt <- if (is.null(pr)) "not simulated" else fmt_yield(pr$yield_mean_kgha, input$unit)
    leafletProxy("map") |>
      clearGroup("farm") |>
      addAwesomeMarkers(group = "farm", lng = input$lon, lat = input$lat,
                        icon = farm_icon,
                        popup = paste0("<b>Your field</b><br>Potential: ", txt,
                                       "<br>Nearest cell: ", round(c$dist_km, 1), " km"))
  })

  observeEvent(input$map_click, {
    updateNumericInput(session, "lat", value = round(input$map_click$lat, 3))
    updateNumericInput(session, "lon", value = round(input$map_click$lng, 3))
  })

  ## ── Narrative explanation ──────────────────────────────────────────────
  output$explain <- renderUI({
    c <- cell(); pr <- pred_row(); v <- my_kgha()
    if (is.null(c)) return(helpText("Enter your field coordinates to begin."))
    parts <- list()
    if (!is.null(pr)) {
      parts <- c(parts, sprintf(
        "At your field (nearest simulated cell %s km away), the potential yield for %s is %s (40-year average at 13%% moisture; typical range %s–%s).",
        round(c$dist_km, 1),
        practice_label(pr),
        fmt_yield(pr$yield_mean_kgha, input$unit),
        fmt_yield(pr$yield_p10_kgha, input$unit),
        fmt_yield(pr$yield_p90_kgha, input$unit)))
    }
    if (!is.null(pr) && !is.na(v)) {
      gap <- pr$yield_mean_kgha - v
      parts <- c(parts, if (gap > 0)
        sprintf("Your actual yield of %s is %s below the potential — a gap to close through management.",
                fmt_yield(v, input$unit), fmt_yield(gap, input$unit))
        else
        sprintf("Your actual yield of %s meets or exceeds the potential — you are farming at or above the modelled potential here.",
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
