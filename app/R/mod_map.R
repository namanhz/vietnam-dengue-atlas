# ============================================================================
# mod_map.R - Leaflet choropleth map (dark theme)
# ============================================================================

mod_map_ui <- function(id) {
  ns <- NS(id)
  leafletOutput(ns("map"), height = "100%", width = "100%")
}

mod_map_server <- function(id, geo, posteriors, current_data,
                           selected_province, measure) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Vietnam bounds
    vn_bounds <- list(south = 7.5, north = 24.0, west = 101.0, east = 115.0)

    output$map <- renderLeaflet({
      leaflet(geo, options = leafletOptions(minZoom = 5, maxZoom = 12)) %>%
        addProviderTiles(providers$CartoDB.PositronNoLabels) %>%
        setView(lng = 106.6, lat = 16.0, zoom = 6) %>%
        setMaxBounds(vn_bounds$west, vn_bounds$south, vn_bounds$east, vn_bounds$north)
    })

    observe({
      req(current_data())
      data <- current_data()
      m <- measure()

      geo_data <- geo %>% left_join(data, by = "province_id")

      if (m == "sir") {
        values <- geo_data$sir
        pal <- colorNumeric(
          palette = c("#2166AC", "#4393C3", "#92C5DE", "#D1E5F0",
                      "#FDDBC7", "#F4A582", "#D6604D", "#B2182B"),
          domain = c(0, max(3, max(values, na.rm = TRUE))),
          na.color = "#333")
        title <- "SIR"
        fmt <- function(x) sprintf("%.2f", x)
      } else if (m == "exc_prob") {
        values <- geo_data$exc_prob
        pal <- colorNumeric(
          palette = c("#2166AC", "#4393C3", "#D1E5F0", "#F7F7F7",
                      "#FDDBC7", "#D6604D", "#B2182B"),
          domain = c(0, 1), na.color = "#333")
        title <- "P(SIR>1)"
        fmt <- function(x) sprintf("%.0f%%", x * 100)
      } else {
        values <- if (m == "incidence_raw") geo_data$incidence_raw else geo_data$incidence_smoothed
        domain <- range(values, na.rm = TRUE)
        pal <- colorNumeric(
          palette = c("#FFF5F0", "#FEE0D2", "#FCBBA1", "#FC9272",
                      "#FB6A4A", "#EF3B2C", "#CB181D", "#99000D"),
          domain = domain, na.color = "#333")
        title <- if (m == "incidence_raw") "Raw/100k" else "Smoothed/100k"
        fmt <- function(x) sprintf("%.1f", x)
      }

      labels <- sprintf(
        "<div style='font-size:13px; line-height:1.5;'>
          <strong>%s</strong><br/>
          <span style='color:#656d76;'>%s:</span> <b>%s</b><br/>
          <span style='color:#656d76;'>Cases:</span> %s<br/>
          <span style='color:#656d76;'>95%% CrI:</span> [%.2f, %.2f]<br/>
          <span style='color:#656d76;'>P(SIR&gt;1):</span> %.0f%%
        </div>",
        geo_data$name_en,
        title, sapply(values, fmt),
        format(geo_data$observed, big.mark = ","),
        ifelse(is.na(geo_data$sir_q025), 0, geo_data$sir_q025),
        ifelse(is.na(geo_data$sir_q975), 0, geo_data$sir_q975),
        ifelse(is.na(geo_data$exc_prob), 0, geo_data$exc_prob * 100)
      ) %>% lapply(htmltools::HTML)

      leafletProxy(ns("map")) %>%
        clearControls() %>%
        addPolygons(
          data = geo_data,
          fillColor = ~pal(values),
          fillOpacity = 0.8,
          weight = 1.2,
          color = "#444444",
          opacity = 1,
          highlightOptions = highlightOptions(
            weight = 2, color = "#ffffff",
            fillOpacity = 0.95, bringToFront = TRUE
          ),
          label = labels,
          labelOptions = labelOptions(
            style = list(
              "background-color" = "#ffffff",
              "color" = "#1f2328",
              "border" = "1px solid #d0d7de",
              "border-radius" = "6px",
              "padding" = "8px 12px",
              "font-family" = "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif",
              "box-shadow" = "0 2px 8px rgba(0,0,0,0.15)"
            ),
            textsize = "13px", direction = "auto"
          ),
          layerId = ~province_id
        ) %>%
        addLegend(
          position = "bottomleft",
          pal = pal, values = values,
          title = title, opacity = 0.9
        )
    })

    observeEvent(input$map_shape_click, {
      click <- input$map_shape_click
      if (!is.null(click$id)) {
        prov_name <- geo$name_en[geo$province_id == click$id]
        if (length(prov_name) > 0) selected_province(prov_name[1])
      }
    })
  })
}
