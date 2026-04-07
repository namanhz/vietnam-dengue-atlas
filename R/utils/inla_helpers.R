# ============================================================================
# utils/inla_helpers.R - Helper functions for INLA model output
# ============================================================================

library(INLA)

#' Extract exceedance probability P(theta > threshold) from INLA marginals
#' @param marginals List of posterior marginals from INLA
#' @param threshold Threshold value (default 1.0 for SIR > 1)
#' @return Numeric vector of exceedance probabilities
compute_exceedance_prob <- function(marginals, threshold = 1.0) {
  sapply(marginals, function(m) {
    1 - inla.pmarginal(threshold, m)
  })
}

#' Extract posterior summary from INLA fitted values
#' @param result INLA result object
#' @param transform Function to apply (e.g., exp for log-link)
#' @return Data frame with mean, sd, and quantiles
extract_fitted_summary <- function(result, transform = exp) {
  fitted <- result$summary.fitted.values
  data.frame(
    mean = transform(fitted$mean),
    sd = fitted$sd,
    q025 = transform(fitted$`0.025quant`),
    q10 = transform(fitted$`0.1quant`),
    q50 = transform(fitted$`0.5quant`),
    q90 = transform(fitted$`0.9quant`),
    q975 = transform(fitted$`0.975quant`)
  )
}

#' Compute PIT (Probability Integral Transform) values for Poisson model
#' @param result INLA result object
#' @param observed Vector of observed counts
#' @return Vector of PIT values
compute_pit <- function(result, observed) {
  cpo <- result$cpo$pit
  cpo[is.na(cpo)] <- 0.5  # Replace failures with 0.5
  cpo
}

#' Extract random effect summary
#' @param result INLA result object
#' @param effect_name Name of the random effect
#' @return Data frame with posterior summaries
extract_random_effect <- function(result, effect_name) {
  re <- result$summary.random[[effect_name]]
  if (is.null(re)) stop(sprintf("Random effect '%s' not found", effect_name))
  re
}
