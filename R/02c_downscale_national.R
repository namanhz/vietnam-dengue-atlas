# ============================================================================
# 02c_downscale_national.R - Downscale national totals to provinces (2018-2024)
# ============================================================================
#
# For 2018-2024, no public province-level data exists. National totals are
# available from OpenDengue V1.3. Provincial shares are estimated from
# the average distribution during 2011-2017 (GDPM yearbook period).
#
# Method: E[Y_it] = Y_t * (avg_share_i)
# where avg_share_i = mean(Y_i,2011:2017) / mean(Y_total,2011:2017)
#
# This is a standard spatial downscaling approach used by WHO/IHME when
# subnational data is unavailable.

library(tidyverse)
library(here)

# --------------------------------------------------------------------------
# 1. Compute provincial shares from GDPM period (2011-2017)
# --------------------------------------------------------------------------
combined <- read_csv(here("data", "processed", "vietnam_dengue_combined.csv"),
                     show_col_types = FALSE)

gdpm_period <- combined %>% filter(year >= 2011, year <= 2017)

province_totals <- gdpm_period %>%
  group_by(gadm_name) %>%
  summarise(total_cases = sum(dengue_total, na.rm = TRUE), .groups = "drop")

national_total <- sum(province_totals$total_cases)

province_shares <- province_totals %>%
  mutate(share = total_cases / national_total)

cat("Province shares (2011-2017 average):\n")
cat(sprintf("  Sum of shares: %.6f\n", sum(province_shares$share)))
cat(sprintf("  Top 5:\n"))
print(province_shares %>% arrange(desc(share)) %>% head(5))
cat(sprintf("  Bottom 5:\n"))
print(province_shares %>% arrange(share) %>% head(5))

# --------------------------------------------------------------------------
# 2. Get national annual totals from OpenDengue (2018-2024)
# --------------------------------------------------------------------------
od <- read.csv(here("data", "raw", "opendengue", "Spatial_extract_V1_3.csv"),
               stringsAsFactors = FALSE)

vn_national <- od %>%
  filter(grepl("VIET NAM", adm_0_name, ignore.case = TRUE)) %>%
  mutate(year = as.integer(substr(calendar_start_date, 1, 4))) %>%
  filter(year >= 2018, year <= 2024) %>%
  group_by(year) %>%
  summarise(national_cases = sum(dengue_total, na.rm = TRUE), .groups = "drop")

cat("\nNational totals 2018-2024:\n")
print(vn_national)

# --------------------------------------------------------------------------
# 3. Downscale to provinces
# --------------------------------------------------------------------------
downscaled <- expand_grid(
  gadm_name = province_shares$gadm_name,
  year = vn_national$year
) %>%
  left_join(province_shares %>% select(gadm_name, share), by = "gadm_name") %>%
  left_join(vn_national, by = "year") %>%
  mutate(
    dengue_total = round(national_cases * share),
    n_months = 12,
    source = "Downscaled"
  ) %>%
  select(gadm_name, year, dengue_total, n_months, source)

cat(sprintf("\nDownscaled: %d province-years\n", nrow(downscaled)))

# Verify totals match
verify <- downscaled %>%
  group_by(year) %>%
  summarise(total = sum(dengue_total), .groups = "drop") %>%
  left_join(vn_national, by = "year")

cat("\nVerification (downscaled vs national):\n")
print(verify)

# --------------------------------------------------------------------------
# 4. Combine all periods
# --------------------------------------------------------------------------
full_combined <- bind_rows(combined, downscaled) %>%
  arrange(gadm_name, year)

cat(sprintf("\nFull combined dataset:\n"))
cat(sprintf("  Years: %d-%d\n", min(full_combined$year), max(full_combined$year)))
cat(sprintf("  Provinces: %d\n", n_distinct(full_combined$gadm_name)))
cat(sprintf("  Province-years: %d\n", nrow(full_combined)))

cat("\nAnnual totals by source:\n")
print(full_combined %>%
        group_by(year, source) %>%
        summarise(total = sum(dengue_total), provinces = n_distinct(gadm_name),
                  .groups = "drop") %>%
        arrange(year), n = 35)

write_csv(full_combined, here("data", "processed", "vietnam_dengue_combined.csv"))
cat("\nSaved: data/processed/vietnam_dengue_combined.csv\n")
