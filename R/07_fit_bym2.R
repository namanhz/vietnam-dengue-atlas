# ============================================================================
# 07_fit_bym2.R - Fit separate BYM2 models per year (ACA approach)
# ============================================================================
#
# Instead of a single spatiotemporal model, fit independent BYM2 models
# for each year. This allows the spatial pattern to vary freely across
# years, matching the Australian Cancer Atlas methodology.

library(INLA)
library(tidyverse)
library(here)

# --------------------------------------------------------------------------
# 1. Load data
# --------------------------------------------------------------------------
model_data <- read_csv(here("data", "processed", "model_data.csv"), show_col_types = FALSE)
adj_file <- here("data", "processed", "vietnam.adj")

years <- sort(unique(model_data$year))
n_provinces <- n_distinct(model_data$province_id)

cat(sprintf("Fitting separate BYM2 models for %d years (%d provinces each)\n",
            length(years), n_provinces))
cat(sprintf("Adjacency file: %s\n\n", adj_file))

# --------------------------------------------------------------------------
# 2. Fit BYM2 per year
# --------------------------------------------------------------------------
all_results <- list()
all_posteriors <- list()

t0_total <- Sys.time()

for (yr in years) {
  cat(sprintf("Year %d ... ", yr))
  t0 <- Sys.time()

  df_yr <- model_data %>%
    filter(year == yr) %>%
    mutate(id_space = province_id, E = expected, Y = observed)

  formula <- Y ~ 1 +
    f(id_space, model = "bym2",
      graph = adj_file,
      scale.model = TRUE,
      constr = TRUE,
      hyper = list(
        phi = list(prior = "pc", param = c(0.5, 2/3)),
        prec = list(prior = "pc.prec", param = c(1, 0.01))
      ))

  result <- inla(formula,
    family = "poisson",
    data = df_yr,
    E = E,
    control.compute = list(
      dic = TRUE, waic = TRUE, cpo = TRUE, config = TRUE,
      return.marginals.predictor = TRUE
    ),
    control.predictor = list(compute = TRUE, link = 1),
    verbose = FALSE
  )

  # Extract posteriors for this year
  fitted <- result$summary.fitted.values

  # Exceedance probabilities
  exc_prob <- sapply(result$marginals.fitted.values, function(m) {
    1 - inla.pmarginal(1, m)
  })

  # Spatial random effect
  spatial_re <- result$summary.random$id_space
  spatial_re_first_n <- spatial_re[1:n_provinces, ]

  posteriors_yr <- df_yr %>%
    select(gadm_name, year, observed, population, expected, sir_raw, province_id, time_id) %>%
    mutate(
      sir_mean = fitted$mean,
      sir_sd = fitted$sd,
      sir_q025 = fitted$`0.025quant`,
      sir_q50 = fitted$`0.5quant`,
      sir_q975 = fitted$`0.975quant`,
      cri_95_width = sir_q975 - sir_q025,
      exc_prob = exc_prob,
      evidence_level = case_when(
        exc_prob > 0.95 ~ "Very likely elevated",
        exc_prob > 0.80 ~ "Likely elevated",
        exc_prob > 0.20 & exc_prob <= 0.80 ~ "No clear evidence",
        exc_prob > 0.05 ~ "Likely lower",
        TRUE ~ "Very likely lower"
      ),
      incidence_raw = (observed / population) * 100000,
      incidence_smoothed = (sir_mean * expected / population) * 100000,
      spatial_rr = exp(spatial_re_first_n$mean),
      spatial_q025 = exp(spatial_re_first_n$`0.025quant`),
      spatial_q975 = exp(spatial_re_first_n$`0.975quant`)
    )

  all_posteriors[[as.character(yr)]] <- posteriors_yr

  # Store summary
  phi <- result$summary.hyperpar["Phi for id_space", "mean"]
  t1 <- Sys.time()
  cat(sprintf("%.1fs (phi=%.2f, DIC=%.0f)\n",
              as.numeric(t1 - t0, units = "secs"),
              phi, result$dic$dic))

  all_results[[as.character(yr)]] <- list(
    dic = result$dic$dic,
    waic = result$waic$waic,
    phi = phi
  )
}

t1_total <- Sys.time()
cat(sprintf("\nAll models fitted in %.1f seconds\n",
            as.numeric(t1_total - t0_total, units = "secs")))

# --------------------------------------------------------------------------
# 3. Combine posteriors
# --------------------------------------------------------------------------
posteriors <- bind_rows(all_posteriors)

cat(sprintf("\nCombined posteriors: %d rows\n", nrow(posteriors)))
cat(sprintf("  Provinces: %d\n", n_distinct(posteriors$province_id)))
cat(sprintf("  Years: %d\n", n_distinct(posteriors$year)))

# --------------------------------------------------------------------------
# 4. Compute temporal trend (national average SIR per year)
# --------------------------------------------------------------------------
temporal_trends <- posteriors %>%
  group_by(year, time_id) %>%
  summarise(
    temporal_rr = weighted.mean(sir_mean, population),
    temporal_q025 = weighted.mean(sir_q025, population),
    temporal_q975 = weighted.mean(sir_q975, population),
    .groups = "drop"
  ) %>%
  arrange(year)

# --------------------------------------------------------------------------
# 5. Extract spatial effects per year (for GeoJSON)
# --------------------------------------------------------------------------
spatial_effects <- posteriors %>%
  select(gadm_name, year, province_id, spatial_rr, spatial_q025, spatial_q975)

# Use the latest year's spatial effect for the GeoJSON default
spatial_latest <- spatial_effects %>%
  filter(year == max(year)) %>%
  select(gadm_name, province_id, spatial_rr, spatial_q025, spatial_q975)

# --------------------------------------------------------------------------
# 6. Save
# --------------------------------------------------------------------------
write_csv(posteriors, here("data", "output", "posteriors.csv"))
cat("Saved posteriors.csv\n")

write_csv(temporal_trends, here("data", "output", "temporal_trends.csv"))
cat("Saved temporal_trends.csv\n")

write_csv(spatial_latest, here("data", "output", "spatial_effects.csv"))
cat("Saved spatial_effects.csv\n")

# Model comparison table
comparison <- tibble(
  year = as.integer(names(all_results)),
  DIC = sapply(all_results, function(x) x$dic),
  WAIC = sapply(all_results, function(x) x$waic),
  phi = sapply(all_results, function(x) x$phi)
)
write_csv(comparison, here("output", "model_diagnostics", "yearly_model_comparison.csv"))
cat("\nYearly model comparison:\n")
print(comparison, n = 20)

cat("\n=== SUMMARY ===\n")
cat(sprintf("SIR range: %.3f - %.3f\n",
            min(posteriors$sir_mean), max(posteriors$sir_mean)))
cat(sprintf("Exceedance prob distribution:\n"))
print(table(posteriors$evidence_level))
