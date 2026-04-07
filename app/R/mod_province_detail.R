# ============================================================================
# mod_province_detail.R - Right panel province details (dark theme)
# ============================================================================

mod_province_detail_ui <- function(id) {
  ns <- NS(id)
  uiOutput(ns("detail_panel"))
}

mod_province_detail_server <- function(id, posteriors, selected_province, selected_year) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    output$detail_panel <- renderUI({
      prov <- selected_province()
      yr <- selected_year()

      # Placeholder when no province selected
      if (is.null(prov)) {
        return(tags$div(class = "placeholder",
          tags$div(class = "icon", icon("map-marker-alt")),
          tags$div(style = "font-size: 15px; margin-bottom: 6px;", "Select a Province"),
          tags$div(style = "font-size: 12px;", "Click on the map to view detailed statistics")
        ))
      }

      d <- posteriors %>% dplyr::filter(province == prov, year == yr)
      if (nrow(d) == 0) return(tags$div(class = "placeholder", p("No data available.")))
      d <- d[1, ]

      prov_all <- posteriors %>% dplyr::filter(province == prov) %>% dplyr::arrange(year)
      year_data <- posteriors %>% dplyr::filter(year == yr)
      rank_sir <- rank(-year_data$sir)[year_data$province == prov]
      n_prov <- nrow(year_data)

      # Evidence classification
      if (d$exc_prob > 0.95) {
        ev_text <- sprintf("%.0f%% above national average", (d$sir - 1) * 100)
        ev_class <- "evidence-elevated"
        ev_label <- "Very likely elevated"
      } else if (d$exc_prob > 0.80) {
        ev_text <- sprintf("%.0f%% above national average", (d$sir - 1) * 100)
        ev_class <- "evidence-likely-elevated"
        ev_label <- "Likely elevated"
      } else if (d$exc_prob < 0.05) {
        ev_text <- sprintf("%.0f%% below national average", (1 - d$sir) * 100)
        ev_class <- "evidence-lower"
        ev_label <- "Very likely lower"
      } else if (d$exc_prob < 0.20) {
        ev_text <- sprintf("%.0f%% below national average", (1 - d$sir) * 100)
        ev_class <- "evidence-likely-lower"
        ev_label <- "Likely lower"
      } else {
        ev_text <- "Near the national average"
        ev_class <- "evidence-neutral"
        ev_label <- "No clear difference"
      }

      # Gradient bar position (log scale)
      sir_log <- log10(max(min(d$sir, 10), 0.1))
      bar_pct <- (sir_log + 1) / 2 * 100
      bar_pct <- max(3, min(97, bar_pct))

      tagList(
        # Header
        tags$div(class = "prov-header",
          tags$div(class = "name", prov),
          tags$div(class = "subtitle",
            sprintf("Year %d  |  Rank %d of %d provinces", yr, rank_sir, n_prov))
        ),

        # SIR card
        tags$div(class = "sir-card",
          tags$div(class = "sir-value", sprintf("%.2f", d$sir)),
          tags$div(class = "sir-ci",
            sprintf("95%% CrI: [%.2f, %.2f]", d$sir_q025, d$sir_q975)),
          tags$div(class = paste("evidence-badge", ev_class), ev_label),
          tags$div(style = "font-size: 12px; color: #8b949e; margin-top: 4px;", ev_text)
        ),

        # Gradient bar
        tags$div(class = "gradient-section",
          tags$div(class = "gradient-labels",
            tags$span("Lower"), tags$span("Higher")),
          tags$div(class = "gradient-bar",
            tags$div(class = "gradient-marker",
              style = sprintf("left: %s%%;", bar_pct))
          ),
          tags$div(class = "gradient-caption", "Compared to national average")
        ),

        # Time series
        tags$div(class = "ts-section",
          tags$div(class = "section-title", "Annual Trend"),
          plotlyOutput(ns("ts_plot"), height = "200px")
        ),

        # Stats table
        tags$div(class = "stats-section",
          tags$div(class = "section-title", "Statistics"),
          tags$table(class = "stats-table",
            tags$tr(tags$td("Observed cases"), tags$td(format(d$observed, big.mark = ","))),
            tags$tr(tags$td("Expected cases"), tags$td(sprintf("%.0f", d$expected))),
            tags$tr(tags$td("Population"), tags$td(format(d$population, big.mark = ","))),
            tags$tr(tags$td("Incidence / 100k"), tags$td(sprintf("%.1f", d$incidence_smoothed))),
            tags$tr(tags$td("P(SIR > 1)"), tags$td(sprintf("%.1f%%", d$exc_prob * 100)))
          )
        )
      )
    })

    # Mini time series
    output$ts_plot <- renderPlotly({
      prov <- selected_province()
      req(prov)

      prov_data <- posteriors %>%
        dplyr::filter(province == prov) %>%
        dplyr::arrange(year)

      if (nrow(prov_data) == 0) return(plotly_empty())

      plot_ly(prov_data, x = ~year) %>%
        add_ribbons(
          ymin = ~sir_q025, ymax = ~sir_q975,
          fillcolor = "rgba(9,105,218,0.12)",
          line = list(color = "transparent"),
          showlegend = FALSE, hoverinfo = "none"
        ) %>%
        add_trace(
          y = ~sir, type = "scatter", mode = "lines+markers",
          line = list(color = "#0969da", width = 2),
          marker = list(color = "#0969da", size = 4),
          name = "SIR",
          text = ~sprintf("SIR = %.2f", sir),
          hoverinfo = "text"
        ) %>%
        add_segments(
          x = min(prov_data$year), xend = max(prov_data$year),
          y = 1, yend = 1,
          line = list(color = "rgba(207,34,46,0.4)", dash = "dash", width = 1),
          showlegend = FALSE, hoverinfo = "none"
        ) %>%
        layout(
          xaxis = list(title = "", color = "#656d76", gridcolor = "#e8ecf0",
                       tickfont = list(size = 10), dtick = 2),
          yaxis = list(title = "", color = "#656d76", gridcolor = "#e8ecf0",
                       tickfont = list(size = 10), rangemode = "tozero"),
          plot_bgcolor = "transparent",
          paper_bgcolor = "transparent",
          margin = list(l = 35, r = 5, t = 5, b = 25),
          showlegend = FALSE,
          hovermode = "closest",
          hoverlabel = list(bgcolor = "#fff", bordercolor = "#d0d7de",
                            font = list(color = "#1f2328", size = 12))
        ) %>%
        config(displayModeBar = FALSE)
    })
  })
}
