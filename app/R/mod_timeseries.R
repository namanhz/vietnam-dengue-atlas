# ============================================================================
# mod_timeseries.R - Time series visualization module
# ============================================================================

mod_timeseries_ui <- function(id) {
  ns <- NS(id)
  tagList(
    plotlyOutput(ns("ts_plot"), height = "500px"),
    br(),
    wellPanel(
      h4("Summary"),
      tableOutput(ns("ts_table"))
    )
  )
}

mod_timeseries_server <- function(id, posteriors, temporal_trends,
                                   selected_province, show_ci, show_national) {
  moduleServer(id, function(input, output, session) {

    output$ts_plot <- renderPlotly({
      prov <- selected_province()

      if (is.null(prov) || prov == "__national__") {
        # National temporal trend
        p <- plot_ly(temporal_trends, x = ~year, y = ~temporal_rr,
                     type = "scatter", mode = "lines+markers",
                     name = "National trend",
                     line = list(color = "#2C3E50", width = 2)) %>%
          layout(
            title = "National Dengue Temporal Trend",
            xaxis = list(title = "Year"),
            yaxis = list(title = "Relative Risk", rangemode = "tozero"),
            hovermode = "x unified"
          )

        if (show_ci()) {
          p <- p %>%
            add_ribbons(
              ymin = ~temporal_q025, ymax = ~temporal_q975,
              fillcolor = "rgba(44,62,80,0.15)",
              line = list(color = "transparent"),
              name = "95% CrI"
            )
        }

        # Add reference line at RR = 1
        p <- p %>%
          add_trace(
            x = range(temporal_trends$year), y = c(1, 1),
            type = "scatter", mode = "lines",
            line = list(color = "grey", dash = "dash", width = 1),
            name = "Reference (RR=1)", showlegend = FALSE
          )

        p
      } else {
        # Province-specific time series
        prov_data <- posteriors %>%
          filter(province == prov) %>%
          arrange(year)

        if (nrow(prov_data) == 0) {
          return(plotly_empty() %>%
                   layout(title = paste("No data for", prov)))
        }

        p <- plot_ly(prov_data, x = ~year) %>%
          add_trace(
            y = ~sir, type = "scatter", mode = "lines+markers",
            name = "Smoothed SIR",
            line = list(color = "#E74C3C", width = 2),
            marker = list(color = "#E74C3C", size = 6)
          ) %>%
          layout(
            title = paste("Dengue SIR:", prov),
            xaxis = list(title = "Year"),
            yaxis = list(title = "Standardized Incidence Ratio"),
            hovermode = "x unified"
          )

        if (show_ci()) {
          p <- p %>%
            add_ribbons(
              ymin = ~sir_q025, ymax = ~sir_q975,
              fillcolor = "rgba(231,76,60,0.15)",
              line = list(color = "transparent"),
              name = "95% CrI"
            )
        }

        if (show_national()) {
          # Add national average (SIR = 1 by definition)
          p <- p %>%
            add_trace(
              x = range(prov_data$year), y = c(1, 1),
              type = "scatter", mode = "lines",
              line = list(color = "#7F8C8D", dash = "dash", width = 1),
              name = "National average (SIR=1)"
            )
        }

        p
      }
    })

    output$ts_table <- renderTable({
      prov <- selected_province()

      if (is.null(prov) || prov == "__national__") {
        temporal_trends %>%
          mutate(
            Year = year,
            `Relative Risk` = sprintf("%.3f", temporal_rr),
            `95% CrI` = sprintf("[%.3f, %.3f]", temporal_q025, temporal_q975)
          ) %>%
          select(Year, `Relative Risk`, `95% CrI`)
      } else {
        posteriors %>%
          filter(province == prov) %>%
          arrange(year) %>%
          mutate(
            Year = year,
            Observed = format(observed, big.mark = ","),
            Expected = sprintf("%.0f", expected),
            SIR = sprintf("%.3f", sir),
            `95% CrI` = sprintf("[%.3f, %.3f]", sir_q025, sir_q975),
            `P(SIR>1)` = sprintf("%.1f%%", exc_prob * 100)
          ) %>%
          select(Year, Observed, Expected, SIR, `95% CrI`, `P(SIR>1)`)
      }
    }, striped = TRUE, hover = TRUE, spacing = "s")
  })
}
