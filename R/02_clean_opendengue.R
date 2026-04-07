# ============================================================================
# 02_clean_opendengue.R - Filter and clean OpenDengue data for Vietnam
# ============================================================================
#
# Data: OpenDengue V1.3 Spatial extract
# Vietnam has MONTHLY province-level data from 1994-2010 (64 provinces)
# Province names are ALL CAPS English (e.g., "HA NOI CITY", "HO CHI MINH CITY")
# Ha Tay province merged into Hanoi in 2008 - must aggregate

library(tidyverse)
library(here)

# --------------------------------------------------------------------------
# 1. Load and filter to Vietnam province-level data
# --------------------------------------------------------------------------
cat("Loading OpenDengue spatial extract...\n")
od <- read_csv(here("data", "raw", "opendengue", "Spatial_extract_V1_3.csv"),
               show_col_types = FALSE)

vietnam <- od %>%
  filter(grepl("VIET NAM", adm_0_name, ignore.case = TRUE),
         !is.na(adm_1_name), adm_1_name != "") %>%
  mutate(
    start_date = as.Date(calendar_start_date),
    end_date = as.Date(calendar_end_date),
    year = year(start_date),
    month = month(start_date)
  )

cat(sprintf("Vietnam province-level rows: %d\n", nrow(vietnam)))
cat(sprintf("Date range: %s to %s\n", min(vietnam$start_date), max(vietnam$end_date)))
cat(sprintf("Years: %d-%d\n", min(vietnam$year), max(vietnam$year)))
cat(sprintf("Provinces: %d unique\n", n_distinct(vietnam$adm_1_name)))

# --------------------------------------------------------------------------
# 2. Handle Ha Tay → Hanoi merge (2008)
# --------------------------------------------------------------------------
# Ha Tay province was absorbed into Hanoi on 2008-08-01.
# For consistency, merge Ha Tay cases into Hanoi for all years.
cat("\nMerging Ha Tay into Ha Noi...\n")
cat(sprintf("  Ha Tay rows before merge: %d\n",
            sum(vietnam$adm_1_name == "HA TAY")))

vietnam <- vietnam %>%
  mutate(adm_1_name = if_else(adm_1_name == "HA TAY", "HA NOI CITY", adm_1_name))

cat(sprintf("  Provinces after merge: %d\n", n_distinct(vietnam$adm_1_name)))

# --------------------------------------------------------------------------
# 3. Aggregate to annual province level
# --------------------------------------------------------------------------
# Model will use annual data (summing monthly cases within each province-year)
# Monthly data provides 12 records per province per year.
annual <- vietnam %>%
  group_by(adm_1_name, year) %>%
  summarise(
    dengue_total = sum(dengue_total, na.rm = TRUE),
    n_months = n(),
    .groups = "drop"
  )

cat(sprintf("\nAnnual province-year combinations: %d\n", nrow(annual)))
cat(sprintf("Years: %s\n", paste(sort(unique(annual$year)), collapse = ", ")))

# Check completeness (should be ~12 months per province-year)
incomplete <- annual %>% filter(n_months < 12)
if (nrow(incomplete) > 0) {
  cat(sprintf("\nWARNING: %d province-years have <12 months of data:\n", nrow(incomplete)))
  print(incomplete %>% arrange(n_months) %>% head(20))
}

# --------------------------------------------------------------------------
# 4. Standardize province names for matching
# --------------------------------------------------------------------------
# Remove "CITY" suffix from municipality names for cleaner matching
# Keep original name for reference
annual <- annual %>%
  mutate(
    province_original = adm_1_name,
    province_clean = gsub("\\s*CITY$", "", adm_1_name),
    province_clean = trimws(province_clean)
  )

cat("\nCleaned province names:\n")
cat(paste(" -", sort(unique(annual$province_clean))), sep = "\n")

# --------------------------------------------------------------------------
# 5. Save outputs
# --------------------------------------------------------------------------
# Save monthly data (for potential monthly analysis later)
write_csv(vietnam, here("data", "processed", "vietnam_dengue_monthly.csv"))
cat(sprintf("\nSaved monthly data: %d rows\n", nrow(vietnam)))

# Save annual aggregated data
write_csv(annual, here("data", "processed", "vietnam_dengue_annual.csv"))
cat(sprintf("Saved annual data: %d rows\n", nrow(annual)))

# Save province names for matching
province_names <- sort(unique(annual$province_clean))
writeLines(province_names, here("data", "processed", "opendengue_province_names.txt"))
cat(sprintf("Saved %d province names for matching\n", length(province_names)))

# --------------------------------------------------------------------------
# 6. Summary
# --------------------------------------------------------------------------
cat("\n=== DATA SUMMARY ===\n")
cat(sprintf("Total cases 1994-2010: %s\n",
            format(sum(annual$dengue_total), big.mark = ",")))

top_provinces <- annual %>%
  group_by(province_clean) %>%
  summarise(total = sum(dengue_total), .groups = "drop") %>%
  arrange(desc(total)) %>%
  head(10)

cat("\nTop 10 provinces by total cases:\n")
print(top_provinces)
