# ============================================================================
# 05_compute_expected.R - Compute expected cases via indirect standardization
# ============================================================================

library(tidyverse)
library(here)

# --------------------------------------------------------------------------
# 1. Load data
# --------------------------------------------------------------------------
annual <- read_csv(here("data", "processed", "vietnam_dengue_annual.csv"),
                   show_col_types = FALSE)
pop <- read_csv(here("data", "processed", "vietnam_population.csv"),
                show_col_types = FALSE)
lookup <- read_csv(here("data", "processed", "province_lookup.csv"),
                   show_col_types = FALSE)

# --------------------------------------------------------------------------
# 2. Map OpenDengue names to GADM names
# --------------------------------------------------------------------------
annual <- annual %>%
  left_join(lookup %>% select(opendengue_name, gadm_name),
            by = c("province_clean" = "opendengue_name")) %>%
  filter(!is.na(gadm_name))

cat(sprintf("Province-years with matched GADM names: %d\n", nrow(annual)))
cat(sprintf("Matched provinces: %d\n", n_distinct(annual$gadm_name)))

# Aggregate (Ha Tay cases already merged into Hanoi in 02_clean)
# But if multiple OpenDengue names map to same GADM, sum them
cases <- annual %>%
  group_by(gadm_name, year) %>%
  summarise(observed = sum(dengue_total, na.rm = TRUE), .groups = "drop")

# --------------------------------------------------------------------------
# 3. Join with population
# --------------------------------------------------------------------------
model_data <- cases %>%
  left_join(pop, by = c("gadm_name" = "province", "year"))

missing_pop <- model_data %>% filter(is.na(population))
if (nrow(missing_pop) > 0) {
  cat(sprintf("WARNING: %d province-years missing population:\n", nrow(missing_pop)))
  print(distinct(missing_pop, gadm_name))
}

model_data <- model_data %>% filter(!is.na(population))

# --------------------------------------------------------------------------
# 4. Compute expected cases (indirect standardization)
# --------------------------------------------------------------------------
national_rates <- model_data %>%
  group_by(year) %>%
  summarise(
    total_cases = sum(observed),
    total_pop = sum(population),
    national_rate = total_cases / total_pop,
    .groups = "drop"
  )

cat("\nNational dengue rates by year:\n")
print(national_rates %>%
        mutate(rate_per_100k = round(national_rate * 100000, 1)),
      n = 20)

model_data <- model_data %>%
  left_join(national_rates %>% select(year, national_rate), by = "year") %>%
  mutate(
    expected = population * national_rate,
    expected = pmax(expected, 0.001),
    sir_raw = observed / expected
  )

# --------------------------------------------------------------------------
# 5. Complete province-year grid
# --------------------------------------------------------------------------
all_provinces <- sort(unique(model_data$gadm_name))
all_years <- sort(unique(model_data$year))

complete <- expand_grid(gadm_name = all_provinces, year = all_years) %>%
  left_join(model_data, by = c("gadm_name", "year"))

# Fill missing with 0 observed
missing_rows <- complete %>% filter(is.na(observed))
if (nrow(missing_rows) > 0) {
  cat(sprintf("\n%d province-years missing (filling with 0 cases):\n", nrow(missing_rows)))

  complete <- complete %>%
    left_join(pop %>% rename(pop_fill = population),
              by = c("gadm_name" = "province", "year")) %>%
    left_join(national_rates %>% select(year, national_rate) %>%
                rename(rate_fill = national_rate), by = "year") %>%
    mutate(
      observed = replace_na(observed, 0),
      population = coalesce(population, pop_fill),
      national_rate = coalesce(national_rate, rate_fill),
      expected = coalesce(expected, pmax(population * national_rate, 0.001)),
      sir_raw = observed / expected
    ) %>%
    select(gadm_name, year, observed, population, expected, sir_raw)
}

# --------------------------------------------------------------------------
# 6. Add numeric IDs for INLA
# --------------------------------------------------------------------------
province_ids <- complete %>%
  distinct(gadm_name) %>%
  arrange(gadm_name) %>%
  mutate(province_id = row_number())

time_ids <- complete %>%
  distinct(year) %>%
  arrange(year) %>%
  mutate(time_id = row_number())

complete <- complete %>%
  left_join(province_ids, by = "gadm_name") %>%
  left_join(time_ids, by = "year")

# --------------------------------------------------------------------------
# 7. Save
# --------------------------------------------------------------------------
write_csv(complete, here("data", "processed", "model_data.csv"))
write_csv(province_ids, here("data", "processed", "province_ids.csv"))
write_csv(time_ids, here("data", "processed", "time_ids.csv"))

cat(sprintf("\nModel data: %d observations\n", nrow(complete)))
cat(sprintf("  Provinces: %d\n", n_distinct(complete$province_id)))
cat(sprintf("  Years: %d (%d-%d)\n", length(all_years), min(all_years), max(all_years)))
cat(sprintf("  Zero-case province-years: %d (%.1f%%)\n",
            sum(complete$observed == 0),
            100 * mean(complete$observed == 0)))
cat(sprintf("\nRaw SIR summary:\n"))
print(summary(complete$sir_raw))
