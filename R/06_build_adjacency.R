# ============================================================================
# 06_build_adjacency.R - Build spatial adjacency matrix from shapefile
# ============================================================================

library(sf)
library(spdep)
library(tidyverse)
library(here)

# --------------------------------------------------------------------------
# 1. Load filtered shapefile (63 provinces, no disputed islands)
# --------------------------------------------------------------------------
vnm <- st_read(here("data", "processed", "vietnam_provinces.gpkg"), quiet = TRUE)
cat(sprintf("Loaded %d province polygons\n", nrow(vnm)))

# Ensure province order matches the province_ids used in model_data
province_ids <- read_csv(here("data", "processed", "province_ids.csv"), show_col_types = FALSE)

# Reorder shapefile to match province_ids ordering
vnm <- vnm %>%
  inner_join(province_ids, by = c("NAME_1" = "gadm_name")) %>%
  arrange(province_id)

cat(sprintf("Matched provinces: %d\n", nrow(vnm)))

# --------------------------------------------------------------------------
# 2. Build queen contiguity neighbors
# --------------------------------------------------------------------------
nb <- poly2nb(vnm, queen = TRUE)
cat(sprintf("\nNeighbor summary:\n"))
print(summary(nb))

# Check for isolates (provinces with zero neighbors)
isolates <- which(card(nb) == 0)
if (length(isolates) > 0) {
  cat(sprintf("\nWARNING: %d isolated provinces (no neighbors):\n", length(isolates)))
  cat(paste(" -", vnm$NAME_1[isolates]), sep = "\n")

  # Fix isolates by adding nearest neighbor
  coords <- st_coordinates(st_centroid(vnm))
  for (iso in isolates) {
    dists <- as.numeric(st_distance(st_centroid(vnm[iso, ]), st_centroid(vnm)))
    dists[iso] <- Inf  # Exclude self
    nearest <- which.min(dists)
    cat(sprintf("  Adding neighbor: %s <-> %s\n", vnm$NAME_1[iso], vnm$NAME_1[nearest]))
    nb[[iso]] <- as.integer(nearest)
    nb[[nearest]] <- sort(unique(c(nb[[nearest]], as.integer(iso))))
  }
}

# Verify connectivity
comp <- n.comp.nb(nb)
cat(sprintf("\nConnected components: %d\n", comp$nc))
if (comp$nc > 1) {
  cat("WARNING: Graph is not fully connected! Components:\n")
  for (i in seq_len(comp$nc)) {
    members <- which(comp$comp.id == i)
    cat(sprintf("  Component %d (%d provinces): %s\n",
                i, length(members),
                paste(vnm$NAME_1[members], collapse = ", ")))
  }
}

# --------------------------------------------------------------------------
# 3. Export for INLA
# --------------------------------------------------------------------------
adj_file <- here("data", "processed", "vietnam.adj")
nb2INLA(adj_file, nb)
cat(sprintf("\nSaved INLA adjacency file: %s\n", adj_file))

# Also save the ordered shapefile for later use
st_write(vnm, here("data", "processed", "vietnam_provinces_ordered.gpkg"),
         delete_dsn = TRUE, quiet = TRUE)
cat("Saved ordered shapefile: data/processed/vietnam_provinces_ordered.gpkg\n")

# --------------------------------------------------------------------------
# 4. Diagnostic plot
# --------------------------------------------------------------------------
# Save a neighbor connectivity map
pdf(here("output", "model_diagnostics", "adjacency_map.pdf"), width = 8, height = 12)
coords <- st_coordinates(st_centroid(st_geometry(vnm)))
plot(st_geometry(vnm), border = "grey60", main = "Vietnam Province Adjacency")
plot(nb, coords, add = TRUE, col = "red", lwd = 0.5)
points(coords, pch = 16, cex = 0.3)
dev.off()
cat("Saved adjacency map: output/model_diagnostics/adjacency_map.pdf\n")
