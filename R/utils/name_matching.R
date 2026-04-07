# ============================================================================
# utils/name_matching.R - Province name matching utilities
# ============================================================================

library(stringi)
library(stringdist)

#' Strip Vietnamese diacritics to ASCII
strip_diacritics <- function(x) {
  stringi::stri_trans_general(x, "Latin-ASCII")
}

#' Normalize province name for matching
#' Lowercase, strip diacritics, remove common prefixes, collapse whitespace
normalize_province <- function(x) {
  x <- tolower(x)
  x <- strip_diacritics(x)
  # Remove common province type prefixes
  x <- gsub("\\b(tinh|thanh pho|thanh\\s+pho|province|city|municipality)\\b", "", x)
  # Remove punctuation except hyphens
  x <- gsub("[^a-z0-9 -]", "", x)
  # Collapse multiple spaces
  x <- trimws(gsub("\\s+", " ", x))
  x
}

#' Multi-pass fuzzy matching of province names
#' @param source_names Character vector of names to match (e.g., OpenDengue)
#' @param target_names Character vector of target names (e.g., GADM NAME_1)
#' @param target_varnames Optional character vector of ASCII variant names (GADM VARNAME_1)
#' @param threshold Jaro-Winkler similarity threshold (default 0.85)
#' @return Data frame with source_name, matched_target, match_method, similarity
match_provinces <- function(source_names, target_names,
                            target_varnames = NULL, threshold = 0.85) {

  results <- data.frame(
    source_name = source_names,
    matched_target = NA_character_,
    match_method = NA_character_,
    similarity = NA_real_,
    stringsAsFactors = FALSE
  )

  src_norm <- normalize_province(source_names)
  tgt_norm <- normalize_province(target_names)

  # Pass 1: Exact match on normalized names
  for (i in seq_along(source_names)) {
    if (!is.na(results$matched_target[i])) next
    idx <- which(tgt_norm == src_norm[i])
    if (length(idx) == 1) {
      results$matched_target[i] <- target_names[idx]
      results$match_method[i] <- "exact_normalized"
      results$similarity[i] <- 1.0
    }
  }

  # Pass 2: Match against VARNAME_1 (ASCII variant) if available
  if (!is.null(target_varnames)) {
    var_norm <- normalize_province(target_varnames)
    for (i in seq_along(source_names)) {
      if (!is.na(results$matched_target[i])) next
      idx <- which(var_norm == src_norm[i])
      if (length(idx) == 1) {
        results$matched_target[i] <- target_names[idx]
        results$match_method[i] <- "varname_match"
        results$similarity[i] <- 1.0
      }
    }
  }

  # Pass 3: Fuzzy match (Jaro-Winkler) on normalized names
  unmatched <- which(is.na(results$matched_target))
  if (length(unmatched) > 0) {
    dist_mat <- stringdistmatrix(src_norm[unmatched], tgt_norm, method = "jw")
    sim_mat <- 1 - dist_mat

    for (j in seq_along(unmatched)) {
      i <- unmatched[j]
      best_idx <- which.max(sim_mat[j, ])
      best_sim <- sim_mat[j, best_idx]
      if (best_sim >= threshold) {
        results$matched_target[i] <- target_names[best_idx]
        results$match_method[i] <- "fuzzy_jw"
        results$similarity[i] <- round(best_sim, 4)
      }
    }
  }

  # Report unmatched
  still_unmatched <- which(is.na(results$matched_target))
  if (length(still_unmatched) > 0) {
    cat("WARNING: Unmatched provinces:\n")
    cat(paste(" -", source_names[still_unmatched]), sep = "\n")
    cat("\nThese require manual matching in province_lookup.csv\n")
  }

  results
}
