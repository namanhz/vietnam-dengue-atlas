# ============================================================================
# 01_download_data.R - Download raw data for Vietnam Dengue Atlas
# ============================================================================

library(here)

raw_dir <- here("data", "raw")

# --------------------------------------------------------------------------
# 1. OpenDengue V1.3 - Spatial extract (highest geographic resolution)
# --------------------------------------------------------------------------
opendengue_dir <- file.path(raw_dir, "opendengue")
opendengue_zip <- file.path(opendengue_dir, "Spatial_extract_V1_3.zip")

if (!file.exists(opendengue_zip)) {
  cat("Downloading OpenDengue V1.3 spatial extract...\n")
  download.file(
    url = "https://github.com/OpenDengue/master-repo/raw/main/data/releases/V1.3/Spatial_extract_V1_3.zip",
    destfile = opendengue_zip,
    mode = "wb"
  )
  unzip(opendengue_zip, exdir = opendengue_dir)
  cat("OpenDengue data downloaded and extracted.\n")
} else {
  cat("OpenDengue data already exists, skipping.\n")
}

# List extracted files
cat("OpenDengue files:\n")
print(list.files(opendengue_dir, recursive = TRUE))

# --------------------------------------------------------------------------
# 2. GADM Vietnam Admin Level 1 shapefile
# --------------------------------------------------------------------------
gadm_dir <- file.path(raw_dir, "gadm")
gadm_zip <- file.path(gadm_dir, "gadm41_VNM_shp.zip")

if (!file.exists(gadm_zip)) {
  cat("Downloading GADM Vietnam Level 1 shapefile...\n")
  download.file(
    url = "https://geodata.ucdavis.edu/gadm/gadm4.1/shp/gadm41_VNM_shp.zip",
    destfile = gadm_zip,
    mode = "wb"
  )
  unzip(gadm_zip, exdir = gadm_dir)
  cat("GADM shapefile downloaded and extracted.\n")
} else {
  cat("GADM shapefile already exists, skipping.\n")
}

cat("GADM files:\n")
print(list.files(gadm_dir, pattern = "\\.(shp|dbf|prj|shx)$"))

# --------------------------------------------------------------------------
# 3. Population data (GSO Vietnam - hardcoded from statistical yearbook)
# --------------------------------------------------------------------------
# Vietnam GSO publishes provincial population annually.
# We use a curated table covering 2000-2023 from GSO statistical yearbooks.
# Source: https://www.gso.gov.vn/en/population/
#
# For the MVP, we create a population file from known GSO figures.
# This will be generated in 04_prepare_population.R

cat("\nData download complete.\n")
cat("Next step: Run 02_clean_opendengue.R to inspect Vietnam data.\n")
