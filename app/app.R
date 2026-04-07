# ============================================================================
# Vietnam Dengue Atlas - Single-Page Dark Theme
# ============================================================================

library(shiny)
library(leaflet)
library(sf)
library(dplyr)
library(plotly)
library(jsonlite)
library(markdown)

# --------------------------------------------------------------------------
# Load data
# --------------------------------------------------------------------------
data_dir <- normalizePath(file.path("..", "data", "output"), mustWork = FALSE)
if (!dir.exists(data_dir)) {
  data_dir <- normalizePath(file.path("data", "output"), mustWork = FALSE)
}

geo <- st_read(file.path(data_dir, "vietnam_provinces.geojson"), quiet = TRUE)
posteriors <- read.csv(file.path(data_dir, "posteriors.csv"), stringsAsFactors = FALSE)
temporal_trends <- read.csv(file.path(data_dir, "temporal_trends.csv"), stringsAsFactors = FALSE)

posteriors <- posteriors %>% rename(province = gadm_name, sir = sir_mean)
geo <- st_transform(geo, 4326)

years <- sort(unique(posteriors$year))
provinces <- sort(unique(posteriors$province))

source("R/mod_map.R")
source("R/mod_province_detail.R")

# --------------------------------------------------------------------------
# UI
# --------------------------------------------------------------------------
ui <- fluidPage(
  tags$head(
    tags$link(rel = "stylesheet", href = "style.css"),
    tags$script(HTML("
      Shiny.addCustomMessageHandler('togglePlayIcon', function(state) {
        var btn = document.getElementById('play_btn');
        var icon = btn.querySelector('i');
        if (icon) {
          icon.className = state === 'pause' ? 'fa fa-pause' : 'fa fa-play';
        }
      });
    "))
  ),

  # Header bar
  tags$div(class = "atlas-header",
    tags$span(class = "title", "Vietnam Dengue Atlas"),
    tags$div(class = "controls",
      tags$div(style = "width: 200px;",
        selectInput("measure", NULL,
          choices = c("Smoothed SIR" = "sir",
                      "Exceedance Prob." = "exc_prob",
                      "Raw Incidence" = "incidence_raw",
                      "Smoothed Incidence" = "incidence_smoothed"),
          selected = "sir", width = "100%")
      ),
      tags$div(style = "display: flex; align-items: center; gap: 8px; flex: 1; min-width: 200px; max-width: 550px;",
        actionButton("play_btn", NULL, icon = icon("play"), class = "play-btn"),
        tags$div(style = "flex: 1;",
          sliderInput("year", NULL,
            min = min(years), max = max(years), value = max(years),
            step = 1, sep = "", width = "100%")
        )
      )
    ),
    actionButton("show_method", "Methodology", class = "method-btn",
                 icon = icon("book")),
    tags$a(href = "https://github.com/namanhz/vietnam-dengue-atlas",
           target = "_blank", class = "method-btn",
           icon("github"), "GitHub")
  ),

  # Body: map + detail panel
  tags$div(class = "atlas-body",
    tags$div(class = "map-container",
      mod_map_ui("map")
    ),
    tags$div(class = "detail-panel",
      mod_province_detail_ui("detail")
    )
  )
)

# --------------------------------------------------------------------------
# Server
# --------------------------------------------------------------------------
server <- function(input, output, session) {

  selected_province <- reactiveVal(NULL)

  # Custom play/pause animation
  playing <- reactiveVal(FALSE)
  anim_timer <- reactiveVal(NULL)

  observeEvent(input$play_btn, {
    if (playing()) {
      playing(FALSE)
      session$sendCustomMessage("togglePlayIcon", "play")
    } else {
      playing(TRUE)
      session$sendCustomMessage("togglePlayIcon", "pause")
    }
  })

  observe({
    if (playing()) {
      invalidateLater(1200, session)
      yr <- isolate(input$year)
      next_yr <- yr + 1
      if (next_yr > max(years)) {
        next_yr <- min(years)
      }
      updateSliderInput(session, "year", value = next_yr)
    }
  })

  current_data <- reactive({
    posteriors %>% filter(year == input$year)
  })

  mod_map_server("map", geo, posteriors, current_data,
                 selected_province, reactive(input$measure))

  mod_province_detail_server("detail", posteriors, selected_province,
                             reactive(input$year))

  # Methodology modal
  observeEvent(input$show_method, {
    md_path <- normalizePath(file.path("..", "docs", "methodology.md"), mustWork = FALSE)
    content <- if (file.exists(md_path)) {
      withMathJax(HTML(markdown::markdownToHTML(
        text = paste(readLines(md_path, warn = FALSE), collapse = "\n"),
        fragment.only = TRUE
      )))
    } else {
      p("Methodology document not found.")
    }

    showModal(modalDialog(
      title = "Statistical Methodology",
      content,
      size = "l",
      easyClose = TRUE,
      footer = modalButton("Close")
    ))
  })
}

shinyApp(ui, server)
