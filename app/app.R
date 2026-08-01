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
source("R/apsim-generate.R", local = TRUE)  # "Get APSIM template" tab (IS_WASM, generator)

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

## ── "Get APSIM template" tab: choices + contiguous-US map bounds ──────────
CULTIVAR_CHOICES <- c("MG4 (PurcellMG4)" = "PurcellMG4",
                      "MG5 (PurcellMG5)" = "PurcellMG5",
                      "MG6 (PurcellMG6)" = "PurcellMG6")
US_BB <- list(lng = c(-125, -66.5), lat = c(24, 49.5))   # lower-48 view

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
## Tab 1 — the yield-gap map (unchanged content, now inside a sidebar layout).
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
      ## target/rel let it open reliably from the WebAssembly page; the address
      ## is also shown as plain, copyable text for devices with no mail handler.
      ## Change FEEDBACK_EMAIL above to route feedback elsewhere.
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

## Tab 2 — generate a ready-to-run APSIM file for any point in the U.S.
tab_apsim <- nav_panel(
  title = "Get APSIM template",
  layout_sidebar(
    sidebar = sidebar(
      width = 340,
      h5("Field location"),
      fluidRow(
        column(6, numericInput("g_lat", "Latitude", value = 34.75,
                               min = 24, max = 49.5, step = 0.001)),
        column(6, numericInput("g_lon", "Longitude", value = -91.5,
                               min = -125, max = -66.5, step = 0.001))
      ),
      helpText("Click the map to drop a pin anywhere in the contiguous U.S."),
      hr(),

      h5("Crop setup"),
      selectInput("g_cultivar", "Maturity group", choices = CULTIVAR_CHOICES),
      dateInput("g_sow", "Sowing date",
                value = as.Date(paste0(format(Sys.Date(), "%Y"), "-05-22")),
                format = "M d", startview = "month"),
      helpText("Only the month/day are used (the year is ignored)."),
      numericInput("g_start", "Weather start year", value = 1985,
                   min = 1984, max = as.integer(format(Sys.Date(), "%Y")),
                   step = 1),
      hr(),

      ## Download control depends on where the app is running.
      if (IS_WASM) uiOutput("g_wasm_notice")
      else tagList(
        downloadButton("dl_apsimx", "Generate & download APSIM (.zip)",
                       class = "btn-primary w-100"),
        helpText("Downloads SSURGO soil + NASA POWER weather and builds the",
                 "file — this can take up to a minute.")
      ),
      textOutput("g_status")
    ),
    card(
      full_screen = TRUE,
      card_header("Pick a location"),
      leafletOutput("g_map", height = 460)
    ),
    card(
      card_header("What you get"),
      uiOutput("g_explain")
    )
  )
)

ui <- page_navbar(
  title = "Soybean Field Toolkit",
  theme = bs_theme(version = 5, bootswatch = "flatly",
                   primary = "#9D2235", secondary = "#54585A"),
  tab_yieldgap,
  tab_apsim
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

  output$provenance <- renderText({
    meta <- tryCatch(readLines("data/yield-surface-meta.json", warn = FALSE),
                     error = function(e) NULL)
    gen <- if (!is.null(meta)) sub('.*"generated":\\s*"([^"]+)".*', "\\1",
                                   paste(meta, collapse = " ")) else "?"
    paste0("Data: APSIM NG grid simulation, ", nrow(CELLS),
           " cells. Generated ", gen, ".")
  })

  ## ── Tab 2: Get APSIM template ────────────────────────────────────────────
  ## US map to pick the point (click sets the coordinate inputs).
  output$g_map <- renderLeaflet({
    leaflet(options = leafletOptions(minZoom = 3, maxZoom = 12)) |>
      addProviderTiles(providers$CartoDB.Positron, group = "Map") |>
      addProviderTiles(providers$Esri.WorldImagery, group = "Satellite") |>
      addLayersControl(baseGroups = c("Map", "Satellite"),
                       options = layersControlOptions(collapsed = TRUE)) |>
      fitBounds(US_BB$lng[1], US_BB$lat[1], US_BB$lng[2], US_BB$lat[2])
  })

  g_icon <- makeAwesomeIcon(icon = "leaf", markerColor = "green",
                            iconColor = "#ffffff", library = "fa")
  observe({
    lat <- input$g_lat; lon <- input$g_lon
    req(is.finite(lat), is.finite(lon))
    leafletProxy("g_map") |>
      clearGroup("pin") |>
      addAwesomeMarkers(group = "pin", lng = lon, lat = lat, icon = g_icon,
                        popup = sprintf("Selected: %.4f, %.4f", lat, lon))
  })
  observeEvent(input$g_map_click, {
    updateNumericInput(session, "g_lat", value = round(input$g_map_click$lat, 4))
    updateNumericInput(session, "g_lon", value = round(input$g_map_click$lng, 4))
  })

  ## Plain-language description of the deliverable.
  output$g_explain <- renderUI({
    cult <- names(CULTIVAR_CHOICES)[match(input$g_cultivar, CULTIVAR_CHOICES)]
    sow  <- tryCatch(to_apsim_date(input$g_sow), error = function(e) "22-May")
    tagList(
      tags$p("A ", tags$b(".zip"), " containing a ready-to-run APSIM Next Gen",
             " simulation for the selected point:"),
      tags$ul(
        tags$li(tags$b("soybean.apsimx"), " — the study's template with the",
                " USDA-SSURGO soil profile embedded, cultivar ",
                tags$b(cult), ", sowing ", tags$b(sow),
                ", and the clock running from ", tags$b(input$g_start),
                " to about today."),
        tags$li(tags$b("weather.met"), " — NASA POWER daily weather for the",
                " point (referenced by the .apsimx).")
      ),
      tags$p(class = "text-muted small",
             "Unzip, then open soybean.apsimx in APSIM NG, or run headless:",
             tags$code("Models soybean.apsimx"), ". NASA POWER has a few days'",
             " latency, so weather runs to roughly the current date.")
    )
  })

  if (IS_WASM) {
    ## Static site: no server R / no API access — hand over the portable script.
    output$g_wasm_notice <- renderUI({
      tagList(
        div(class = "alert alert-warning small mb-2",
            tags$b("Runs on your computer."), " Building the file downloads",
            " USDA soil and NASA weather, which the in-browser version can't do.",
            " Download the script below and run it in R:", tags$br(),
            tags$code("Rscript make-apsim.R --lat  --lon "),
            " (needs ", tags$code("install.packages(\"apsimx\")"), ")."),
        downloadButton("dl_script", "Download generator script (make-apsim.R)",
                       class = "btn-primary w-100")
      )
    })
    output$dl_script <- downloadHandler(
      filename = function() "make-apsim.R",
      content  = function(file) file.copy("scripts/make-apsim.R", file, overwrite = TRUE)
    )
  } else {
    ## Server / local: build and download the .zip directly.
    output$dl_apsimx <- downloadHandler(
      filename = function()
        sprintf("apsim-soybean_%.4f_%.4f.zip",
                as.numeric(input$g_lat), as.numeric(input$g_lon)),
      content = function(file) {
        withProgress(message = "Building APSIM file", value = 0, {
          generate_apsimx_zip(
            lat = as.numeric(input$g_lat), lon = as.numeric(input$g_lon),
            zip_file = file, name = "soybean",
            cultivar = input$g_cultivar, sow_date = to_apsim_date(input$g_sow),
            start_year = as.integer(input$g_start),
            progress = function(p, m) setProgress(value = p, detail = m))
        })
      }
    )
  }

  output$g_status <- renderText("")
}

shinyApp(ui, server)
