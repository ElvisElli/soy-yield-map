## ============================================================
## soy-yield-map — interactive soybean yield-gap map for Arkansas
##
## A farmer enters their field location, maturity group and planting date,
## and their own measured yield. The app shows the APSIM-predicted yield at
## that location, the yield gap, and how much could be gained by adapting
## maturity group / planting date under +2 C warming.
##
## Single-file Shiny app. Runs three ways from the SAME source:
##   • locally:            shiny::runApp("app")
##   • Shiny Server / io:  deploy the app/ folder
##   • static (Pages):     compiled to WebAssembly by shinylive (see .github)
##
## Data contract: app/data/yield-surface.csv, produced by
## simulation/export-app-data.R.
## ============================================================

library(shiny)
library(bslib)
library(leaflet)
library(ggplot2)

## Helpers (unit conversion, nearest-cell lookup, practice lookup) + UARK plots
source("R/helpers.R", local = TRUE)
source("R/plots.R", local = TRUE)

## ── Load the yield surface (base read.csv keeps webR/shinylive happy) ─────
SURFACE <- read.csv("data/yield-surface.csv", stringsAsFactors = FALSE)
SURFACE$co2 <- as.integer(SURFACE$co2)

## Unique cells for the map / nearest-cell search
CELLS <- unique(SURFACE[, c("cellid", "x", "y")])

## Choices constrained to what was actually simulated
CLIMATES <- c("Current climate" = "current", "+2 °C warming" = "plus2C")
mg_choices     <- function(clim) sort(unique(SURFACE$mg[SURFACE$climate == clim]))
window_choices <- function(clim, mg) sort(unique(
  SURFACE$plant_window[SURFACE$climate == clim & SURFACE$mg == mg]))
co2_choices    <- function(clim) sort(unique(SURFACE$co2[SURFACE$climate == clim]))

AR_CENTER <- list(lng = mean(range(CELLS$x)), lat = mean(range(CELLS$y)))

## UARK cardinal sequential palette for the yield surface (continuous)
YIELD_RANGE <- range(SURFACE$yield_mean_kgha, na.rm = TRUE)
pal <- leaflet::colorNumeric(UARK$ramp, domain = YIELD_RANGE, na.color = "#e6e6e6")

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
    selectInput("climate", "Climate scenario", choices = CLIMATES),
    selectInput("mg", "Maturity group", choices = NULL),
    selectInput("window", "Planting window", choices = NULL),
    conditionalPanel(
      "input.climate == 'plus2C'",
      selectInput("co2", "CO₂ (ppm)", choices = NULL)
    ),
    uiOutput("practice_note"),
    hr(),

    h5("Your yield"),
    fluidRow(
      column(7, numericInput("myyield", "Measured yield", value = 50, min = 0)),
      column(5, radioButtons("unit", "Units",
                             c("bu/ac", "kg/ha"), selected = "bu/ac"))
    ),
    hr(),
    helpText(textOutput("provenance", inline = TRUE))
  ),

  ## ── Plots (above the map) ────────────────────────────────────────────
  card(
    card_header(textOutput("plots_header", inline = TRUE)),
    plotOutput("boxplot", height = 300),
    plotOutput("yeartype", height = 260)
  ),

  ## ── Map ──────────────────────────────────────────────────────────────
  card(
    full_screen = TRUE,
    card_header("Predicted soybean yield across Arkansas — selected practice"),
    leafletOutput("map", height = 500)
  ),

  ## ── Narrative ────────────────────────────────────────────────────────
  card(
    card_header("What this means for your field"),
    uiOutput("explain")
  )
)

## ── Server ─────────────────────────────────────────────────────────────────
server <- function(input, output, session) {

  ## Constrain practice choices to simulated combinations for the chosen climate
  observeEvent(input$climate, {
    mgs <- mg_choices(input$climate)
    updateSelectInput(session, "mg", choices = mgs,
                      selected = if ("MG4" %in% mgs) "MG4" else mgs[1])
    updateSelectInput(session, "co2", choices = co2_choices(input$climate))
  }, ignoreInit = FALSE)

  observeEvent(list(input$climate, input$mg), {
    req(input$mg)
    wins <- window_choices(input$climate, input$mg)
    sel <- if ("late May" %in% wins) "late May" else wins[1]
    updateSelectInput(session, "window", choices = wins, selected = sel)
  }, ignoreInit = FALSE)

  co2_sel <- reactive({
    if (identical(input$climate, "current")) 350L else as.integer(input$co2 %||% 350)
  })

  ## Selected cell (nearest simulated grid cell to the entered coordinates)
  cell <- reactive({
    nearest_cell(CELLS, input$lat, input$lon)
  })

  ## Predicted yield for the selected practice at that cell
  pred_row <- reactive({
    c <- cell(); req(c, input$mg, input$window)
    lookup_practice(SURFACE, c$cellid, input$mg, input$window,
                    input$climate, co2_sel())
  })

  ## Farmer's yield in kg/ha
  my_kgha <- reactive({
    v <- input$myyield
    if (is.null(v) || is.na(v)) return(NA_real_)
    if (identical(input$unit, "bu/ac")) buac_to_kgha(v) else v
  })

  ## Best practice at the cell for the selected climate, and best under +2 C
  best_here <- reactive({
    c <- cell(); req(c)
    p <- practices_at_cell(SURFACE, c$cellid, input$climate, co2_sel())
    if (nrow(p) == 0) NULL else p[1, , drop = FALSE]
  })
  baseline_row <- reactive({
    c <- cell(); req(c)
    r <- SURFACE[SURFACE$cellid == c$cellid & SURFACE$scenario == "baseline", ]
    if (nrow(r) == 0) NULL else r[1, , drop = FALSE]
  })
  best_plus2 <- reactive({
    c <- cell(); req(c)
    p <- practices_at_cell(SURFACE, c$cellid, "plus2C", co2_sel())
    if (nrow(p) == 0) NULL else p[1, , drop = FALSE]
  })

  ## ── Plots (simulated distribution vs observed; year-type potential) ─────
  ## All simulated practices at the selected cell (baseline + adaptations),
  ## at the selected CO2 (baseline is CO2 350 only, always included).
  cell_rows <- reactive({
    c <- cell(); req(c)
    SURFACE[SURFACE$cellid == c$cellid &
              (SURFACE$co2 == co2_sel() | SURFACE$scenario == "baseline"), ]
  })
  selected_scenario <- reactive({
    pr <- pred_row(); if (is.null(pr)) NA_character_ else pr$scenario[1]
  })

  output$plots_header <- renderText({
    c <- cell()
    if (is.null(c)) "Yield distribution" else
      sprintf("Yield distribution at your field (nearest cell %.1f km away)",
              c$dist_km)
  })

  output$boxplot <- renderPlot({
    rows <- cell_rows(); req(nrow(rows) > 0)
    make_boxplot(rows, observed_kgha = my_kgha(), unit = input$unit,
                 highlight = selected_scenario())
  }, res = 96)

  output$yeartype <- renderPlot({
    rows <- cell_rows(); req(nrow(rows) > 0)
    make_yeartype_plot(rows, unit = input$unit)
  }, res = 96)

  ## ── Practice availability note ─────────────────────────────────────────
  output$practice_note <- renderUI({
    if (identical(input$climate, "current")) {
      tags$small(class = "text-muted",
        "Current-climate simulations cover MG4 planted late May (the study baseline). ",
        "Switch to “+2 °C warming” to explore earlier planting and MG5.")
    }
  })

  ## ── Map ────────────────────────────────────────────────────────────────
  ## Per-cell yield for the selected practice (may be NA where not simulated)
  map_data <- reactive({
    d <- SURFACE[SURFACE$climate == input$climate &
                   SURFACE$co2 == co2_sel() &
                   SURFACE$mg == input$mg &
                   SURFACE$plant_window == input$window, ]
    if (nrow(d) == 0) {
      ## fall back to baseline layer so the map is never blank
      d <- SURFACE[SURFACE$scenario == "baseline", ]
    }
    d
  })

  ## Legend values in the user's unit; palette stays keyed on kg/ha internally
  legend_vals <- reactive(seq(YIELD_RANGE[1], YIELD_RANGE[2], length.out = 5))

  output$map <- renderLeaflet({
    leaflet(options = leafletOptions(minZoom = 6, maxZoom = 12,
                                     preferCanvas = TRUE)) |>
      addProviderTiles(providers$CartoDB.PositronNoLabels,
                       group = "Clean") |>
      addProviderTiles(providers$Esri.WorldImagery, group = "Satellite") |>
      addLayersControl(baseGroups = c("Clean", "Satellite"),
                       options = layersControlOptions(collapsed = TRUE)) |>
      setView(AR_CENTER$lng, AR_CENTER$lat, zoom = 7)
  })

  ## Draw the filled yield surface (grid tiles) for the selected practice
  observe({
    d <- map_data()
    unit <- input$unit
    fmt_v <- function(v) vapply(v, function(x) fmt_yield(x, unit), character(1))
    labs <- sprintf("<b>%s</b><br>%s",
                    fmt_v(d$yield_mean_kgha),
                    ifelse(is.na(d$yield_median_kgha), "",
                           paste0("median ", fmt_v(d$yield_median_kgha))))
    leafletProxy("map", data = d) |>
      clearGroup("cells") |>
      removeControl("yield-legend") |>
      addCircleMarkers(
        group = "cells",
        lng = ~x, lat = ~y, radius = 5, stroke = FALSE, fillOpacity = 0.9,
        fillColor = ~pal(yield_mean_kgha),
        label = lapply(labs, htmltools::HTML)) |>
      addLegend("bottomright", layerId = "yield-legend",
                colors = pal(legend_vals()),
                labels = vapply(legend_vals(),
                                function(v) fmt_yield(v, unit), character(1)),
                title = paste0("Predicted yield<br>(", unit, ")"),
                opacity = 0.9)
  })

  ## Prominent cardinal farm marker + click-to-set
  farm_icon <- makeAwesomeIcon(icon = "map-marker", markerColor = "darkred",
                               iconColor = "#ffffff", library = "fa")
  observe({
    c <- cell(); req(c)
    pr <- pred_row()
    txt <- if (is.null(pr)) "not simulated for this practice"
           else fmt_yield(pr$yield_mean_kgha, input$unit)
    leafletProxy("map") |>
      clearGroup("farm") |>
      addAwesomeMarkers(group = "farm", lng = input$lon, lat = input$lat,
                        icon = farm_icon,
                        popup = paste0("<b>Your field</b><br>Predicted: ", txt,
                                       "<br>Nearest cell: ",
                                       round(c$dist_km, 1), " km"))
  })

  observeEvent(input$map_click, {
    click <- input$map_click
    updateNumericInput(session, "lat", value = round(click$lat, 3))
    updateNumericInput(session, "lon", value = round(click$lng, 3))
  })

  ## ── Narrative explanation ──────────────────────────────────────────────
  output$explain <- renderUI({
    c <- cell(); pr <- pred_row(); v <- my_kgha()
    b <- baseline_row(); bp <- best_plus2()
    if (is.null(c)) return(helpText("Enter your field coordinates to begin."))
    parts <- list()
    if (!is.null(pr)) {
      parts <- c(parts, sprintf(
        "At your field (nearest simulated cell %s km away), APSIM predicts a mean yield of %s for %s under the %s scenario (40-year average; typical range %s–%s).",
        round(c$dist_km, 1),
        fmt_yield(pr$yield_mean_kgha, input$unit),
        practice_label(pr),
        if (input$climate == "current") "current-climate" else "+2 °C warming",
        fmt_yield(pr$yield_p10_kgha, input$unit),
        fmt_yield(pr$yield_p90_kgha, input$unit)))
    }
    if (!is.null(pr) && !is.na(v)) {
      gap <- pr$yield_mean_kgha - v
      parts <- c(parts, if (gap > 0)
        sprintf("Your reported yield of %s is %s below the model prediction — a potential gap to close through management.",
                fmt_yield(v, input$unit), fmt_yield(gap, input$unit))
        else
        sprintf("Your reported yield of %s meets or exceeds the model prediction — you are farming at or above the simulated potential here.",
                fmt_yield(v, input$unit)))
    }
    if (!is.null(b) && !is.null(bp) && bp$yield_mean_kgha > b$yield_mean_kgha) {
      parts <- c(parts, sprintf(
        "Under +2 °C warming, the best-performing practice at your field is %s, yielding %s — about %s above the current MG4/late-May baseline. This is the synergistic maturity-group and planting-date shift from the study.",
        practice_label(bp),
        fmt_yield(bp$yield_mean_kgha, input$unit),
        fmt_yield(bp$yield_mean_kgha - b$yield_mean_kgha, input$unit)))
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

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || is.na(a[1])) b else a

shinyApp(ui, server)
