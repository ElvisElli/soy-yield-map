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

## Unique cells for the map / nearest-cell search (county tags the NASS county)
CELLS <- unique(SURFACE[, c("cellid", "x", "y", "county")])

## County-level NASS soybean yield (bu/ac, 5-yr average) for the benchmark bar
NASS <- read.csv("data/nass-county-yield.csv", stringsAsFactors = FALSE)
NASS_YIELD <- setNames(NASS$yield_bu, NASS$county)     # UPPERCASE county -> bu/ac
NASS_YEARS <- if (nrow(NASS)) sprintf("%d–%d", NASS$year_min[1], NASS$year_max[1]) else ""

## Practice choices, constrained to what was actually simulated
MG_CHOICES     <- sort(unique(SURFACE$mg))
window_choices <- function(mg) sort(unique(SURFACE$plant_window[SURFACE$mg == mg]))

## Where the "Send feedback" button routes (edit to change the recipient).
FEEDBACK_EMAIL <- "eelli@uark.edu"

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

## ── In-season soil-water surface (optional; produced by current_season/) ──
## Class colours match the study's moisture maps. If the file is absent (the
## weekly run hasn't produced it yet) the In-season tab shows a friendly notice.
SW_COLORS       <- c(Dry = "#de2d26", Adequate = "#31a354", Excess = "#253494")
SW_DRY_MAX      <- 40      # rel. soil water % thresholds (match current_season/config.R)
SW_ADEQUATE_MAX <- 70
SW_DEPTHS       <- c("Top 6 in" = "rel_sw_6in",
                     "Top 12 in" = "rel_sw_12in",
                     "Top 24 in" = "rel_sw_24in")
SOILWATER <- tryCatch(read.csv("data/soil-water.csv", stringsAsFactors = FALSE),
                      error = function(e) NULL)
SW_META   <- tryCatch(paste(readLines("data/soil-water-meta.json", warn = FALSE),
                            collapse = " "), error = function(e) "")
SW_LAST_UPDATE <- if (nzchar(SW_META))
  sub('.*"last_update":\\s*"([^"]+)".*', "\\1", SW_META) else NA
sw_classify <- function(rel) {
  pct <- rel * 100
  factor(ifelse(pct <= SW_DRY_MAX, "Dry",
         ifelse(pct <= SW_ADEQUATE_MAX, "Adequate", "Excess")),
         levels = c("Dry", "Adequate", "Excess"))
}

## Research-station time series (this season vs the 1985+ historical range).
STATION_TS <- tryCatch(read.csv("data/station-timeseries.csv", stringsAsFactors = FALSE),
                       error = function(e) NULL)
STATION_CHOICES <- if (!is.null(STATION_TS)) sort(unique(STATION_TS$station)) else character(0)
STATION_VARS <- c("Soil water 0–6 in"  = "rel_sw_6in",
                  "Soil water 0–12 in" = "rel_sw_12in",
                  "Soil water 0–24 in" = "rel_sw_24in",
                  "Cumulative rain since Apr 1 (in)" = "CummRain_in",
                  "Biomass (kg/ha)"    = "Biomass_kgha")
## Month tick marks for the day-of-year x axis.
SW_DOY_BREAKS <- as.integer(format(seq(as.Date("2001-01-01"),
                            as.Date("2001-12-31"), by = "2 months"), "%j"))
SW_DOY_LABELS <- format(seq(as.Date("2001-01-01"), as.Date("2001-12-31"),
                            by = "2 months"), "%b")

## ── UI ───────────────────────────────────────────────────────────────────
## Tab 1 — the yield-gap map.
tab_yieldgap <- nav_panel(
  title = "Yield-gap map",
  layout_sidebar(
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
      checkboxInput("benchmark", "Add county 5-yr NASS average", value = FALSE),
      hr(),
      ## Feedback — opens the visitor's email client (works on the static site).
      tags$a(
        href = paste0("mailto:", FEEDBACK_EMAIL,
                      "?subject=Soybean%20Yield-Gap%20Map%20feedback"),
        target = "_blank", rel = "noopener",
        class = "btn btn-outline-secondary btn-sm w-100",
        "✉ Send feedback"),
      tags$div(class = "text-muted small mt-1 text-center",
               "or email ",
               tags$a(href = paste0("mailto:", FEEDBACK_EMAIL), FEEDBACK_EMAIL)),
      helpText(textOutput("provenance", inline = TRUE))
    ),
    card(
      fill = FALSE,
      uiOutput("tiles"),
      plotOutput("barplot", height = "260px"),
      uiOutput("bench_note")
    ),
    card(
      full_screen = TRUE,
      leafletOutput("map", height = 520)
    )
  )
)

## Tab 2 — in-season soil-water tracker (current growing season, updated weekly).
tab_inseason <- nav_panel(
  title = "In-season soil water",
  layout_sidebar(
    sidebar = sidebar(
      width = 340,
      h5("Current-season soil water"),
      uiOutput("sw_update"),
      hr(),
      radioButtons("sw_depth", "Depth", choices = SW_DEPTHS, selected = "rel_sw_6in"),
      hr(),
      tags$div(
        class = "small",
        tags$b("How wet is the soil?"), tags$br(),
        tags$span(style = paste0("color:", SW_COLORS["Dry"]), "●"), " Dry (< 40% of plant-available water)", tags$br(),
        tags$span(style = paste0("color:", SW_COLORS["Adequate"]), "●"), " Adequate (40–70%)", tags$br(),
        tags$span(style = paste0("color:", SW_COLORS["Excess"]), "●"), " Excess (> 70%)"
      ),
      helpText("APSIM daily simulation of the current season, refreshed weekly.")
    ),
    card(
      full_screen = TRUE,
      leafletOutput("sw_map", height = 560)
    ),
    ## Research-station time series — this season vs the historical range.
    if (!is.null(STATION_TS)) card(
      full_screen = TRUE,
      card_header("Research-station tracker"),
      fluidRow(
        column(6, selectInput("st_station", "Station", choices = STATION_CHOICES)),
        column(6, selectInput("st_var", "Variable", choices = STATION_VARS,
                              selected = "rel_sw_12in"))
      ),
      plotOutput("sw_station_ts", height = "300px"),
      tags$small(class = "text-muted",
        "Red = this season · grey band = historical min–max (1985+) · grey line = median.")
    )
  )
)

ui <- page_navbar(
  title = "Arkansas Soybean Tools",
  theme = bs_theme(version = 5, bootswatch = "flatly",
                   primary = "#9D2235", secondary = "#54585A"),
  tab_yieldgap,
  tab_inseason
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
  output$vb_cty <- renderText({
    b <- benchmark_kgha(); if (is.na(b)) "—" else fmt_buac(b)
  })

  ## Headline tiles: 3 by default, +County-avg tile when the benchmark is on
  output$tiles <- renderUI({
    on <- isTRUE(input$benchmark)
    h  <- if (on) "120px" else "100px"     # a touch taller when 4 tiles wrap
    box <- function(title, id, bg) value_box(
      title, textOutput(id), max_height = h,
      theme = value_box_theme(bg = bg, fg = "white"))
    tiles <- list(box("Potential yield", "vb_pot", "#9D2235"),
                  box("Actual yield",    "vb_act", "#3F5B74"),
                  box("Yield gap",       "vb_gap", "#B0842F"))
    if (on) tiles <- c(tiles, list(box("County avg (NASS)", "vb_cty", "#2E7D32")))
    do.call(layout_column_wrap,
            c(list(width = if (on) 1/4 else 1/3,
                   fixed_width = FALSE, heights_equal = "row", gap = "0.5rem"),
              tiles))
  })

  ## County NASS 5-yr average (market kg/ha) for the optional benchmark bar
  benchmark_kgha <- reactive({
    if (!isTRUE(input$benchmark)) return(NA_real_)
    c <- cell(); if (is.null(c) || is.na(c$county)) return(NA_real_)
    by <- NASS_YIELD[[as.character(c$county)]]
    if (is.null(by) || is.na(by)) return(NA_real_)
    buac_to_kgha(by)                       # bu/ac -> market kg/ha
  })

  output$barplot <- renderPlot({
    pr <- pred_row(); req(pr)
    make_barplot(pr, observed_kgha = my_kgha(), unit = input$unit,
                 benchmark_kgha = benchmark_kgha())
  }, res = 96)

  output$bench_note <- renderUI({
    if (!isTRUE(input$benchmark)) return(NULL)
    c <- cell(); if (is.null(c)) return(NULL)
    county <- if (is.na(c$county)) NA else tools::toTitleCase(tolower(as.character(c$county)))
    by <- if (!is.na(c$county)) NASS_YIELD[[as.character(c$county)]] else NULL
    if (is.null(by) || is.na(by))
      tags$small(class = "text-muted",
        sprintf("No NASS soybean-yield record for %s County.",
                ifelse(is.na(county), "this", county)))
    else
      tags$small(class = "text-muted",
        sprintf("Green bar: %s County USDA-NASS soybean yield, %s average (%.1f bu/ac).",
                county, NASS_YEARS, by))
  })

  ## ── Interactive map (Leaflet: pan/zoom basemap + yield points + farm) ────
  map_cells <- reactive({
    d <- SURFACE[SURFACE$mg == input$mg & SURFACE$plant_window == input$window, ]
    if (nrow(d) == 0) d <- SURFACE[SURFACE$scenario == "baseline", ]
    ## Thin the ~4,500-cell fine grid to a coarser display grid (mean yield per
    ## ~0.06° bin). The full grid overwhelmed the mobile renderer (dots never
    ## painted); ~1,000 points render reliably and fast on phones.
    res <- 0.06
    agg <- aggregate(d$yield_mean_kgha,
                     list(x = round(d$x / res) * res, y = round(d$y / res) * res),
                     mean, na.rm = TRUE)
    names(agg)[3] <- "yield_mean_kgha"
    agg
  })
  legend_vals <- reactive(seq(YIELD_RANGE[1], YIELD_RANGE[2], length.out = 5))

  output$map <- renderLeaflet({
    ## SVG renderer (default) — the canvas renderer left the yield dots blank on
    ## mobile Safari. With the thinned grid, SVG renders reliably and stays fast.
    leaflet(options = leafletOptions(minZoom = 6, maxZoom = 13)) |>
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
                STATE_BB$lng[2], STATE_BB$lat[2]) |>
      ## Mobile: the map card can lay out at the wrong size (it's below the fold),
      ## leaving tiles/markers blank until a resize. Recalculate size after render
      ## and on rotation/resize so the yield points always paint.
      htmlwidgets::onRender(
        "function(el, x) {
           var map = this;
           var fix = function() { map.invalidateSize(); };
           setTimeout(fix, 300); setTimeout(fix, 1200);
           window.addEventListener('resize', fix);
         }")
  })

  ## Draw the yield surface for the selected practice (canvas circle markers).
  ## The dots are non-interactive so a tap anywhere on the map — including over
  ## the cropland — falls through to the map and drops the field pin (essential
  ## on touch screens, where the old per-cell hover labels did nothing anyway).
  observe({
    d <- map_cells(); unit <- input$unit
    leafletProxy("map", data = d) |>
      clearGroup("cells") |>
      removeControl("yield-legend") |>
      addCircleMarkers(
        group = "cells", lng = ~x, lat = ~y, radius = 6,
        stroke = FALSE, fillOpacity = 0.9, fillColor = ~pal(yield_mean_kgha),
        options = pathOptions(interactive = FALSE)) |>
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

  output$provenance <- renderText({
    meta <- tryCatch(readLines("data/yield-surface-meta.json", warn = FALSE),
                     error = function(e) NULL)
    gen <- if (!is.null(meta)) sub('.*"generated":\\s*"([^"]+)".*', "\\1",
                                   paste(meta, collapse = " ")) else "?"
    paste0("Data: APSIM NG grid simulation, ", nrow(CELLS),
           " cells. Generated ", gen, ".")
  })

  ## ── Tab 2: In-season soil-water map ──────────────────────────────────────
  output$sw_update <- renderUI({
    if (is.null(SOILWATER))
      return(tags$div(class = "text-warning small",
                      "In-season data not published yet — check back after the",
                      " next weekly update."))
    tags$div(class = "small",
             "Season ", tags$b(format(Sys.Date(), "%Y")), " · last updated ",
             tags$b(if (is.na(SW_LAST_UPDATE) || !nzchar(SW_LAST_UPDATE)) "—" else SW_LAST_UPDATE))
  })

  output$sw_map <- renderLeaflet({
    leaflet(options = leafletOptions(minZoom = 6, maxZoom = 13)) |>
      addProviderTiles(providers$CartoDB.Positron, group = "Map") |>
      addProviderTiles(providers$Esri.WorldImagery, group = "Satellite") |>
      addLayersControl(baseGroups = c("Map", "Satellite"),
                       options = layersControlOptions(collapsed = TRUE)) |>
      addPolylines(lng = COUNTY_LINE$lng, lat = COUNTY_LINE$lat,
                   color = "#8a8a8a", weight = 0.6, opacity = 0.7) |>
      addPolylines(lng = STATE_LINE$lng, lat = STATE_LINE$lat,
                   color = "#54585A", weight = 1.6, opacity = 0.9) |>
      fitBounds(STATE_BB$lng[1], STATE_BB$lat[1],
                STATE_BB$lng[2], STATE_BB$lat[2]) |>
      htmlwidgets::onRender(
        "function(el, x) {
           var map = this;
           var fix = function() { map.invalidateSize(); };
           setTimeout(fix, 300); setTimeout(fix, 1200);
           window.addEventListener('resize', fix);
         }")
  })

  ## Draw the soil-water classes for the selected depth (thinned + reclassified
  ## so it stays fast and paints reliably on phones, like the yield map).
  observe({
    if (is.null(SOILWATER)) return(NULL)
    col <- input$sw_depth; req(col %in% names(SOILWATER))
    d <- data.frame(x = SOILWATER$x, y = SOILWATER$y, rel = SOILWATER[[col]])
    d <- d[is.finite(d$rel), , drop = FALSE]
    if (!nrow(d)) return(NULL)
    res <- 0.06
    agg <- aggregate(d$rel, list(x = round(d$x / res) * res, y = round(d$y / res) * res),
                     mean, na.rm = TRUE)
    names(agg)[3] <- "rel"
    agg$col <- unname(SW_COLORS[as.character(sw_classify(agg$rel))])
    leafletProxy("sw_map", data = agg) |>
      clearGroup("sw") |>
      removeControl("sw-legend") |>
      addCircleMarkers(group = "sw", lng = ~x, lat = ~y, radius = 6,
                       stroke = FALSE, fillOpacity = 0.9, fillColor = ~col,
                       options = pathOptions(interactive = FALSE)) |>
      addLegend("bottomright", layerId = "sw-legend",
                colors = unname(SW_COLORS), labels = names(SW_COLORS),
                title = "Soil water", opacity = 0.9)
  })

  ## Research-station time series: this season (red) vs historical range (grey).
  output$sw_station_ts <- renderPlot({
    req(!is.null(STATION_TS), input$st_station, input$st_var)
    d <- STATION_TS[STATION_TS$station == input$st_station &
                    STATION_TS$variable == input$st_var, , drop = FALSE]
    validate(need(nrow(d) > 0, "No data for this station/variable yet."))
    vlab <- names(STATION_VARS)[match(input$st_var, STATION_VARS)]
    ggplot(d, aes(doy)) +
      geom_ribbon(aes(ymin = lo, ymax = hi), fill = "grey85") +
      geom_line(aes(y = med), colour = "grey45") +
      geom_line(aes(y = current), colour = "#9D2235", linewidth = 0.9, na.rm = TRUE) +
      scale_x_continuous(breaks = SW_DOY_BREAKS, labels = SW_DOY_LABELS) +
      labs(x = NULL, y = vlab, title = input$st_station) +
      theme_minimal(base_size = 13)
  }, res = 96)
}

shinyApp(ui, server)
