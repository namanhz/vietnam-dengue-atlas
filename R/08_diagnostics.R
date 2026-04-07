# ============================================================================
# 08_diagnostics.R - Model diagnostics and sensitivity analysis
# ============================================================================

library(INLA)
library(tidyverse)
library(spdep)
library(sf)
library(here)
source(here("R", "utils", "inla_helpers.R"))

# --------------------------------------------------------------------------
# 1. Load model and data
# --------------------------------------------------------------------------
result <- readRDS(here("data", "output", "bym2_model.rds"))
model_data <- read_csv(here("data", "processed", "model_data.csv"), show_col_types = FALSE)
vnm <- st_read(here("data", "processed", "vietnam_provinces_ordered.gpkg"), quiet = TRUE)

diag_dir <- here("output", "model_diagnostics")

# --------------------------------------------------------------------------
# 2. CPO diagnostics
# --------------------------------------------------------------------------
cat("=== CPO DIAGNOSTICS ===\n")
cpo <- result$cpo$cpo
pit <- result$cpo$pit

cat(sprintf("CPO failures: %d / %d\n", sum(result$cpo$failure > 0), length(cpo)))
cat(sprintf("Mean log-CPO: %.4f\n", mean(log(cpo), na.rm = TRUE)))

# PIT histogram (should be uniform if model is well-calibrated)
pdf(file.path(diag_dir, "pit_histogram.pdf"), width = 8, height = 6)
hist(pit, breaks = 20, freq = FALSE,
     main = "PIT Histogram (should be uniform)",
     xlab = "PIT values", col = "lightblue", border = "white")
abline(h = 1, col = "red", lty = 2, lwd = 2)
dev.off()
cat("Saved PIT histogram\n")

# --------------------------------------------------------------------------
# 3. Posterior predictive check
# --------------------------------------------------------------------------
cat("\n=== POSTERIOR PREDICTIVE CHECK ===\n")
fitted_means <- result$summary.fitted.values$mean * model_data$expected

pdf(file.path(diag_dir, "observed_vs_fitted.pdf"), width = 8, height = 8)
plot(model_data$observed, fitted_means,
     pch = 16, cex = 0.5, col = rgb(0, 0, 0, 0.3),
     xlab = "Observed cases", ylab = "Fitted (posterior mean * E)",
     main = "Observed vs Fitted Cases",
     log = "xy")
abline(0, 1, col = "red", lwd = 2)
dev.off()
cat("Saved observed vs fitted plot\n")

cor_val <- cor(log1p(model_data$observed), log1p(fitted_means))
cat(sprintf("Correlation (log scale): %.4f\n", cor_val))

# --------------------------------------------------------------------------
# 4. Residual spatial autocorrelation (Moran's I)
# --------------------------------------------------------------------------
cat("\n=== RESIDUAL SPATIAL AUTOCORRELATION ===\n")

# Compute residuals (observed / fitted) for each year
nb <- poly2nb(vnm, queen = TRUE)
lw <- nb2listw(nb, style = "W", zero.policy = TRUE)

# Average residuals across time
avg_residuals <- model_data %>%
  mutate(
    fitted = result$summary.fitted.values$mean * expected,
    residual = (observed - fitted) / sqrt(fitted + 1)  # Pearson-type residual
  ) %>%
  group_by(province_id) %>%
  summarise(mean_residual = mean(residual, na.rm = TRUE), .groups = "drop") %>%
  arrange(province_id)

moran_test <- moran.test(avg_residuals$mean_residual, lw, zero.policy = TRUE)
cat(sprintf("Moran's I on mean residuals: %.4f (p = %.4f)\n",
            moran_test$estimate[1], moran_test$p.value))

if (moran_test$p.value < 0.05) {
  cat("WARNING: Significant residual spatial autocorrelation remains.\n")
  cat("Consider adding space-time interaction term.\n")
} else {
  cat("No significant residual spatial autocorrelation. Model captures spatial structure.\n")
}

# --------------------------------------------------------------------------
# 5. Sensitivity analysis: alternative priors
# --------------------------------------------------------------------------
cat("\n=== SENSITIVITY ANALYSIS ===\n")

adj_file <- here("data", "processed", "vietnam.adj")

df <- model_data %>%
  mutate(
    id_space = province_id,
    id_time = time_id,
    E = expected,
    Y = observed
  )

# Model A: Tighter spatial prior (halved SD)
cat("Fitting Model A: tighter spatial prior (P(sigma > 0.5) = 0.01)...\n")
formula_a <- Y ~ 1 +
  f(id_space, model = "bym2", graph = adj_file,
    scale.model = TRUE, constr = TRUE,
    hyper = list(
      phi = list(prior = "pc", param = c(0.5, 2/3)),
      prec = list(prior = "pc.prec", param = c(0.5, 0.01))  # Tighter
    )) +
  f(id_time, model = "rw1", scale.model = TRUE, constr = TRUE,
    hyper = list(prec = list(prior = "pc.prec", param = c(0.5, 0.01))))

result_a <- inla(formula_a, family = "poisson", data = df, E = E,
                 control.compute = list(dic = TRUE, waic = TRUE),
                 verbose = FALSE)

# Model B: Looser spatial prior (doubled SD)
cat("Fitting Model B: looser spatial prior (P(sigma > 2) = 0.01)...\n")
formula_b <- Y ~ 1 +
  f(id_space, model = "bym2", graph = adj_file,
    scale.model = TRUE, constr = TRUE,
    hyper = list(
      phi = list(prior = "pc", param = c(0.5, 2/3)),
      prec = list(prior = "pc.prec", param = c(2, 0.01))  # Looser
    )) +
  f(id_time, model = "rw1", scale.model = TRUE, constr = TRUE,
    hyper = list(prec = list(prior = "pc.prec", param = c(0.5, 0.01))))

result_b <- inla(formula_b, family = "poisson", data = df, E = E,
                 control.compute = list(dic = TRUE, waic = TRUE),
                 verbose = FALSE)

# Model C: RW2 instead of RW1 for temporal trend
cat("Fitting Model C: RW2 temporal trend...\n")
formula_c <- Y ~ 1 +
  f(id_space, model = "bym2", graph = adj_file,
    scale.model = TRUE, constr = TRUE,
    hyper = list(
      phi = list(prior = "pc", param = c(0.5, 2/3)),
      prec = list(prior = "pc.prec", param = c(1, 0.01))
    )) +
  f(id_time, model = "rw2", scale.model = TRUE, constr = TRUE,
    hyper = list(prec = list(prior = "pc.prec", param = c(0.5, 0.01))))

result_c <- inla(formula_c, family = "poisson", data = df, E = E,
                 control.compute = list(dic = TRUE, waic = TRUE),
                 verbose = FALSE)

# Compare models
comparison <- tribble(
  ~Model,                        ~DIC,            ~WAIC,
  "Main (BYM2 + RW1)",          result$dic$dic,   result$waic$waic,
  "A: Tighter spatial prior",   result_a$dic$dic,  result_a$waic$waic,
  "B: Looser spatial prior",    result_b$dic$dic,  result_b$waic$waic,
  "C: RW2 temporal",            result_c$dic$dic,  result_c$waic$waic
)

cat("\nModel comparison:\n")
print(comparison)
write_csv(comparison, file.path(diag_dir, "model_comparison.csv"))
cat("\nSaved model comparison table\n")

# --------------------------------------------------------------------------
# 6. Summary report
# --------------------------------------------------------------------------
cat("\n=== DIAGNOSTIC SUMMARY ===\n")
cat(sprintf("PIT uniformity: %s\n",
            ifelse(ks.test(pit[!is.na(pit)], "punif")$p.value > 0.05,
                   "PASS (uniform)", "FAIL (non-uniform)")))
cat(sprintf("Residual spatial autocorrelation: %s\n",
            ifelse(moran_test$p.value > 0.05,
                   "PASS (not significant)", "FAIL (significant)")))
cat(sprintf("Best model by WAIC: %s\n",
            comparison$Model[which.min(comparison$WAIC)]))
cat(sprintf("Best model by DIC: %s\n",
            comparison$Model[which.min(comparison$DIC)]))
