# ============================================================================
# mod_map.R - Leaflet choropleth (fixed scales, smooth JS transitions)
# ============================================================================

mod_map_ui <- function(id) {
  ns <- NS(id)
  leafletOutput(ns("map"), height = "100%", width = "100%")
}

mod_map_server <- function(id, geo, posteriors, current_data,
                           selected_province, measure) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    vn_bounds <- list(south = 7.5, north = 24.0, west = 101.0, east = 115.0)

    # Pre-compute global fixed domains (once, at startup)
    sir_domain <- c(0, max(3, quantile(posteriors$sir, 0.98, na.rm = TRUE)))
    inc_raw_domain <- c(0, quantile(posteriors$incidence_raw, 0.98, na.rm = TRUE))
    inc_smooth_domain <- c(0, quantile(posteriors$incidence_smoothed, 0.98, na.rm = TRUE))

    # Fixed palettes (never change)
    sir_pal <- colorNumeric(
      c("#2166AC","#4393C3","#92C5DE","#D1E5F0","#FDDBC7","#F4A582","#D6604D","#B2182B"),
      domain = sir_domain, na.color = "#333")
    exc_pal <- colorNumeric(
      c("#2166AC","#4393C3","#D1E5F0","#F7F7F7","#FDDBC7","#D6604D","#B2182B"),
      domain = c(0, 1), na.color = "#333")
    inc_raw_pal <- colorNumeric(
      c("#FFF5F0","#FEE0D2","#FCBBA1","#FC9272","#FB6A4A","#EF3B2C","#CB181D","#99000D"),
      domain = inc_raw_domain, na.color = "#333")
    inc_smooth_pal <- colorNumeric(
      c("#FFF5F0","#FEE0D2","#FCBBA1","#FC9272","#FB6A4A","#EF3B2C","#CB181D","#99000D"),
      domain = inc_smooth_domain, na.color = "#333")

    # Track if polygons have been drawn
    polygons_drawn <- reactiveVal(FALSE)

    # Base map
    output$map <- renderLeaflet({
      leaflet(geo, options = leafletOptions(minZoom = 5, maxZoom = 12)) %>%
        addProviderTiles(providers$CartoDB.PositronNoLabels) %>%
        setView(lng = 106.6, lat = 16.0, zoom = 6) %>%
        setMaxBounds(vn_bounds$west, vn_bounds$south, vn_bounds$east, vn_bounds$north)
    })

    # Draw polygons once, then update colors via JS
    observe({
      req(current_data())
      data <- current_data()
      m <- measure()

      geo_data <- geo %>% left_join(data, by = "province_id")

      # Pick palette and values
      if (m == "sir") {
        values <- geo_data$sir
        pal <- sir_pal; title <- "SIR"; domain <- sir_domain
        fmt <- function(x) sprintf("%.2f", x)
      } else if (m == "exc_prob") {
        values <- geo_data$exc_prob
        pal <- exc_pal; title <- "P(SIR>1)"; domain <- c(0, 1)
        fmt <- function(x) sprintf("%.0f%%", x * 100)
      } else if (m == "incidence_raw") {
        values <- geo_data$incidence_raw
        pal <- inc_raw_pal; title <- "Raw/100k"; domain <- inc_raw_domain
        fmt <- function(x) sprintf("%.1f", x)
      } else {
        values <- geo_data$incidence_smoothed
        pal <- inc_smooth_pal; title <- "Smoothed/100k"; domain <- inc_smooth_domain
        fmt <- function(x) sprintf("%.1f", x)
      }

      fill_colors <- pal(pmin(pmax(values, domain[1]), domain[2]))

      # Tooltip labels
      labels <- sprintf(
        "<div style='font-size:13px; line-height:1.5;'>
          <strong>%s</strong><br/>
          <span style='color:#656d76;'>%s:</span> <b>%s</b><br/>
          <span style='color:#656d76;'>Cases:</span> %s<br/>
          <span style='color:#656d76;'>95%% CrI:</span> [%.2f, %.2f]<br/>
          <span style='color:#656d76;'>P(SIR&gt;1):</span> %.0f%%
        </div>",
        geo_data$name_en, title, sapply(values, fmt),
        format(geo_data$observed, big.mark = ","),
        ifelse(is.na(geo_data$sir_q025), 0, geo_data$sir_q025),
        ifelse(is.na(geo_data$sir_q975), 0, geo_data$sir_q975),
        ifelse(is.na(geo_data$exc_prob), 0, geo_data$exc_prob * 100)
      ) %>% lapply(htmltools::HTML)

      if (!polygons_drawn() || !is.null(input$measure_changed)) {
        # First draw or measure changed: draw full polygons
        leafletProxy(ns("map")) %>%
          clearShapes() %>%
          clearControls() %>%
          addPolygons(
            data = geo_data,
            fillColor = fill_colors,
            fillOpacity = 0.8,
            weight = 1.2, color = "#444444", opacity = 1,
            highlightOptions = highlightOptions(
              weight = 2, color = "#ffffff", fillOpacity = 0.95, bringToFront = TRUE),
            label = labels,
            labelOptions = labelOptions(
              style = list("background-color" = "#ffffff", "color" = "#1f2328",
                           "border" = "1px solid #d0d7de", "border-radius" = "6px",
                           "padding" = "8px 12px",
                           "font-family" = "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif",
                           "box-shadow" = "0 2px 8px rgba(0,0,0,0.15)"),
              textsize = "13px", direction = "auto"),
            layerId = ~province_id
          ) %>%
          addLegend(position = "bottomleft", pal = pal,
                    values = seq(domain[1], domain[2], length.out = 5),
                    title = title, opacity = 0.9)

        polygons_drawn(TRUE)
      } else {
        # Year changed: update colors via JS for smooth transition
        color_map <- setNames(fill_colors, geo_data$province_id)
        session$sendCustomMessage("updatePolygonColors", as.list(color_map))

        # Update legend (same fixed domain)
        leafletProxy(ns("map")) %>%
          clearControls() %>%
          addLegend(position = "bottomleft", pal = pal,
                    values = seq(domain[1], domain[2], length.out = 5),
                    title = title, opacity = 0.9)
      }
    })

    # Reset polygons_drawn when measure changes
    observeEvent(measure(), {
      polygons_drawn(FALSE)
    })

    # Map clicks
    observeEvent(input$map_shape_click, {
      click <- input$map_shape_click
      if (!is.null(click$id)) {
        prov_name <- geo$name_en[geo$province_id == click$id]
        if (length(prov_name) > 0) selected_province(prov_name[1])
      }
    })
  })
}
