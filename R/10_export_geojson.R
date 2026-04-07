# ============================================================================
# 10_export_geojson.R - Merge posteriors with shapefile for frontend
# ============================================================================

library(sf)
library(tidyverse)
library(jsonlite)
library(here)

# --------------------------------------------------------------------------
# 1. Load data
# --------------------------------------------------------------------------
vnm <- st_read(here("data", "processed", "vietnam_provinces_ordered.gpkg"), quiet = TRUE)
posteriors <- read_csv(here("data", "output", "posteriors.csv"), show_col_types = FALSE)
spatial_re <- read_csv(here("data", "output", "spatial_effects.csv"), show_col_types = FALSE)
temporal_re <- read_csv(here("data", "output", "temporal_trends.csv"), show_col_types = FALSE)

# --------------------------------------------------------------------------
# 2. Simplify polygons for web delivery
# --------------------------------------------------------------------------
cat("Simplifying polygons...\n")
vnm_simple <- st_simplify(vnm, dTolerance = 0.01, preserveTopology = TRUE)

orig_size <- object.size(vnm)
simp_size <- object.size(vnm_simple)
cat(sprintf("Polygon simplification: %.1f MB -> %.1f MB (%.0f%% reduction)\n",
            as.numeric(orig_size) / 1e6,
            as.numeric(simp_size) / 1e6,
            100 * (1 - as.numeric(simp_size) / as.numeric(orig_size))))

# --------------------------------------------------------------------------
# 3. Add spatial summary to GeoJSON properties
# --------------------------------------------------------------------------
vnm_export <- vnm_simple %>%
  left_join(spatial_re %>% select(gadm_name, spatial_rr, spatial_q025, spatial_q975),
            by = c("NAME_1" = "gadm_name")) %>%
  select(
    province_id,
    name_en = NAME_1,
    name_vn = VARNAME_1,
    type = TYPE_1,
    gid = GID_1,
    spatial_rr, spatial_q025, spatial_q975
  )

# --------------------------------------------------------------------------
# 4. Export GeoJSON (geometry + spatial summary)
# --------------------------------------------------------------------------
geojson_file <- here("data", "output", "vietnam_provinces.geojson")
st_write(vnm_export, geojson_file, driver = "GeoJSON", delete_dsn = TRUE)

file_size <- file.info(geojson_file)$size / 1e6
cat(sprintf("Saved GeoJSON: %s (%.1f MB)\n", geojson_file, file_size))

if (file_size > 3) {
  cat("WARNING: GeoJSON is large. Consider further simplification.\n")
}

# --------------------------------------------------------------------------
# 5. Export posteriors as JSON (keyed by province-year)
# --------------------------------------------------------------------------
posteriors_export <- posteriors %>%
  select(
    province = gadm_name,
    province_id,
    year,
    observed, expected, population,
    sir = sir_mean, sir_q025, sir_q50, sir_q975,
    cri_95_width,
    exc_prob, evidence_level,
    incidence_raw, incidence_smoothed
  )

posteriors_json <- toJSON(posteriors_export, pretty = FALSE, auto_unbox = TRUE)
posteriors_file <- here("data", "output", "posteriors.json")
writeLines(posteriors_json, posteriors_file)

file_size <- file.info(posteriors_file)$size / 1e6
cat(sprintf("Saved posteriors JSON: %s (%.1f MB)\n", posteriors_file, file_size))

# --------------------------------------------------------------------------
# 6. Export temporal trends as JSON
# --------------------------------------------------------------------------
trends_json <- toJSON(temporal_re, pretty = FALSE, auto_unbox = TRUE)
writeLines(trends_json, here("data", "output", "temporal_trends.json"))
cat("Saved temporal trends JSON\n")

# --------------------------------------------------------------------------
# 7. Export summary metadata
# --------------------------------------------------------------------------
metadata <- list(
  project = "Vietnam Dengue Atlas",
  n_provinces = nrow(vnm_export),
  years = sort(unique(posteriors$year)),
  year_range = range(posteriors$year),
  model = "BYM2 + RW1 (Poisson, INLA)",
  data_source = "OpenDengue V1.3",
  shapefile_source = "GADM 4.1",
  generated = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
)

writeLines(toJSON(metadata, pretty = TRUE, auto_unbox = TRUE),
           here("data", "output", "metadata.json"))
cat("Saved metadata JSON\n")

cat("\n=== EXPORT COMPLETE ===\n")
cat("Files ready for Shiny frontend:\n")
cat("  data/output/vietnam_provinces.geojson\n")
cat("  data/output/posteriors.json\n")
cat("  data/output/temporal_trends.json\n")
cat("  data/output/metadata.json\n")
