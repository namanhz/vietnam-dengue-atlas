# ============================================================================
# 09_extract_posteriors.R - Extract posterior summaries for visualization
# ============================================================================

library(INLA)
library(tidyverse)
library(here)
source(here("R", "utils", "inla_helpers.R"))

# --------------------------------------------------------------------------
# 1. Load model and data
# --------------------------------------------------------------------------
result <- readRDS(here("data", "output", "bym2_model.rds"))
model_data <- read_csv(here("data", "processed", "model_data.csv"), show_col_types = FALSE)
province_ids <- read_csv(here("data", "processed", "province_ids.csv"), show_col_types = FALSE)
time_ids <- read_csv(here("data", "processed", "time_ids.csv"), show_col_types = FALSE)

# --------------------------------------------------------------------------
# 2. Extract fitted values (SIR = exp(linear predictor))
# --------------------------------------------------------------------------
cat("Extracting posterior summaries...\n")

fitted <- result$summary.fitted.values
cat("Available fitted value columns:", paste(names(fitted), collapse = ", "), "\n")

posteriors <- model_data %>%
  mutate(
    sir_mean  = fitted$mean,
    sir_sd    = fitted$sd,
    sir_q025  = fitted$`0.025quant`,
    sir_q50   = fitted$`0.5quant`,
    sir_q975  = fitted$`0.975quant`,
    cri_95_width = sir_q975 - sir_q025
  )

# --------------------------------------------------------------------------
# 3. Compute exceedance probabilities
# --------------------------------------------------------------------------
cat("Computing exceedance probabilities...\n")
exc_prob <- compute_exceedance_prob(result$marginals.fitted.values, threshold = 1.0)
posteriors$exc_prob <- exc_prob

# Classify evidence level (following Australian Cancer Atlas approach)
posteriors <- posteriors %>%
  mutate(
    evidence_level = case_when(
      exc_prob > 0.95 ~ "Very likely elevated",
      exc_prob > 0.80 ~ "Likely elevated",
      exc_prob > 0.20 & exc_prob <= 0.80 ~ "No clear evidence",
      exc_prob > 0.05 ~ "Likely lower",
      TRUE ~ "Very likely lower"
    )
  )

# --------------------------------------------------------------------------
# 4. Extract spatial random effect (time-invariant)
# --------------------------------------------------------------------------
spatial_re <- result$summary.random$id_space %>%
  filter(row_number() <= n_distinct(model_data$province_id)) %>%
  mutate(
    province_id = row_number(),
    spatial_rr = exp(mean),  # Relative risk from spatial effect alone
    spatial_q025 = exp(`0.025quant`),
    spatial_q975 = exp(`0.975quant`)
  ) %>%
  select(province_id, spatial_rr, spatial_q025, spatial_q975)

spatial_re <- spatial_re %>%
  left_join(province_ids, by = "province_id")

# --------------------------------------------------------------------------
# 5. Extract temporal trend (province-invariant)
# --------------------------------------------------------------------------
temporal_re <- result$summary.random$id_time %>%
  mutate(
    time_id = row_number(),
    temporal_rr = exp(mean),
    temporal_q025 = exp(`0.025quant`),
    temporal_q975 = exp(`0.975quant`)
  ) %>%
  select(time_id, temporal_rr, temporal_q025, temporal_q975)

temporal_re <- temporal_re %>%
  left_join(time_ids, by = "time_id")

# --------------------------------------------------------------------------
# 6. Compute incidence rates per 100,000
# --------------------------------------------------------------------------
posteriors <- posteriors %>%
  mutate(
    incidence_raw = (observed / population) * 100000,
    incidence_smoothed = (sir_mean * expected / population) * 100000
  )

# --------------------------------------------------------------------------
# 7. Save outputs
# --------------------------------------------------------------------------
# Full posteriors (province-year level)
write_csv(posteriors, here("data", "output", "posteriors.csv"))
cat(sprintf("Saved posteriors: %d rows\n", nrow(posteriors)))

# Spatial random effect (province level)
write_csv(spatial_re, here("data", "output", "spatial_effects.csv"))
cat(sprintf("Saved spatial effects: %d provinces\n", nrow(spatial_re)))

# Temporal trend (year level)
write_csv(temporal_re, here("data", "output", "temporal_trends.csv"))
cat(sprintf("Saved temporal trends: %d time periods\n", nrow(temporal_re)))

# --------------------------------------------------------------------------
# 8. Summary statistics
# --------------------------------------------------------------------------
cat("\n=== POSTERIOR SUMMARY ===\n")
cat("\nSmoothed SIR distribution:\n")
print(summary(posteriors$sir_mean))

cat("\nExceedance probability distribution:\n")
print(summary(posteriors$exc_prob))

cat("\nEvidence level counts:\n")
print(table(posteriors$evidence_level))

cat("\nTop 10 provinces by mean spatial relative risk:\n")
spatial_re %>%
  arrange(desc(spatial_rr)) %>%
  head(10) %>%
  select(gadm_name, spatial_rr, spatial_q025, spatial_q975) %>%
  print()

cat("\nBottom 10 provinces by mean spatial relative risk:\n")
spatial_re %>%
  arrange(spatial_rr) %>%
  head(10) %>%
  select(gadm_name, spatial_rr, spatial_q025, spatial_q975) %>%
  print()
