# ============================================================================
# 00_setup.R - Install required packages for Vietnam Dengue Atlas
# ============================================================================

options(repos = c(CRAN = "https://cloud.r-project.org"))

# INLA (not on CRAN - requires special repository)
if (!requireNamespace("INLA", quietly = TRUE)) {
  install.packages("INLA",
    repos = c(CRAN = "https://cloud.r-project.org",
              INLA = "https://inla.r-inla-download.org/R/stable"),
    dep = TRUE
  )
}

# CRAN packages
pkgs <- c(
  # Spatial
  "sf", "spdep", "terra", "geodata", "rmapshaper",
  # Epidemiology
  "SpatialEpi", "classInt",
  # Shiny & visualization
  "shiny", "bslib", "leaflet", "leaflet.extras", "plotly", "htmlwidgets",
  # Data wrangling
  "tidyverse", "jsonlite", "geojsonsf",
  # String matching
  "stringdist", "stringi",
  # Reproducibility
  "here"
)

to_install <- pkgs[!sapply(pkgs, requireNamespace, quietly = TRUE)]
if (length(to_install) > 0) {
  install.packages(to_install)
}

cat("Setup complete. Installed packages:\n")
cat(paste(" -", pkgs[sapply(pkgs, requireNamespace, quietly = TRUE)]), sep = "\n")

missing <- pkgs[!sapply(pkgs, requireNamespace, quietly = TRUE)]
if (length(missing) > 0) {
  warning("Failed to install: ", paste(missing, collapse = ", "))
}
