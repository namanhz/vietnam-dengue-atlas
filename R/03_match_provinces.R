# ============================================================================
# 03_match_provinces.R - Match province names between OpenDengue and GADM
# ============================================================================
#
# OpenDengue uses ALL CAPS English names: "AN GIANG", "HA NOI", "BINH DUONG"
# GADM uses Vietnamese diacritics in NAME_1 and ASCII in VARNAME_1
# Strategy: normalize both, fuzzy match, then manual corrections

library(tidyverse)
library(sf)
library(stringi)
library(stringdist)
library(here)

# --------------------------------------------------------------------------
# 1. Load GADM shapefile
# --------------------------------------------------------------------------
vnm <- st_read(here("data", "raw", "gadm", "gadm41_VNM_1.shp"), quiet = TRUE)
cat(sprintf("GADM features: %d\n", nrow(vnm)))

# Show all GADM provinces
gadm_info <- vnm %>%
  st_drop_geometry() %>%
  select(GID_1, NAME_1, VARNAME_1, TYPE_1)

cat("\nGADM provinces:\n")
print(as_tibble(gadm_info), n = 70)

# --------------------------------------------------------------------------
# 2. Filter out disputed island groups (no population)
# --------------------------------------------------------------------------
vnm <- vnm %>%
  filter(!grepl("Hoang Sa|Truong Sa|Paracel|Spratly", NAME_1, ignore.case = TRUE))

cat(sprintf("\nAfter filtering disputed islands: %d features\n", nrow(vnm)))

# --------------------------------------------------------------------------
# 3. Load OpenDengue province names
# --------------------------------------------------------------------------
od_names <- readLines(here("data", "processed", "opendengue_province_names.txt"))
cat(sprintf("OpenDengue province names: %d\n", length(od_names)))

# --------------------------------------------------------------------------
# 4. Build matching: normalize both sides
# --------------------------------------------------------------------------
normalize <- function(x) {
  x <- tolower(x)
  x <- stri_trans_general(x, "Latin-ASCII")
  x <- gsub("[^a-z0-9 ]", " ", x)
  x <- gsub("\\s+", " ", trimws(x))
  x
}

od_norm <- normalize(od_names)
gadm_norm <- normalize(vnm$NAME_1)
gadm_var_norm <- normalize(vnm$VARNAME_1)

# --------------------------------------------------------------------------
# 5. Multi-pass matching
# --------------------------------------------------------------------------
results <- data.frame(
  od_name = od_names,
  od_norm = od_norm,
  gadm_idx = NA_integer_,
  method = NA_character_,
  stringsAsFactors = FALSE
)

# Pass 1: Exact normalized match
for (i in seq_along(od_names)) {
  idx <- which(gadm_norm == od_norm[i])
  if (length(idx) == 1) {
    results$gadm_idx[i] <- idx
    results$method[i] <- "exact"
  }
}
cat(sprintf("\nPass 1 (exact): %d matched\n", sum(!is.na(results$gadm_idx))))

# Pass 2: Match against VARNAME_1 (often space-collapsed ASCII)
for (i in seq_along(od_names)) {
  if (!is.na(results$gadm_idx[i])) next
  # VARNAME_1 often has no spaces: "AnGiang" -> compare without spaces
  od_nospace <- gsub(" ", "", od_norm[i])
  gadm_var_nospace <- gsub(" ", "", tolower(gadm_var_norm))
  idx <- which(gadm_var_nospace == od_nospace)
  if (length(idx) == 1) {
    results$gadm_idx[i] <- idx
    results$method[i] <- "varname"
  }
}
cat(sprintf("Pass 2 (varname): %d matched\n", sum(!is.na(results$gadm_idx))))

# Pass 3: Fuzzy match (Jaro-Winkler)
unmatched <- which(is.na(results$gadm_idx))
if (length(unmatched) > 0) {
  available_gadm <- setdiff(seq_len(nrow(vnm)), results$gadm_idx[!is.na(results$gadm_idx)])

  for (i in unmatched) {
    sims <- 1 - stringdist(od_norm[i], gadm_norm[available_gadm], method = "jw")
    best_local <- which.max(sims)
    if (sims[best_local] >= 0.80) {
      results$gadm_idx[i] <- available_gadm[best_local]
      results$method[i] <- sprintf("fuzzy_%.2f", sims[best_local])
      available_gadm <- setdiff(available_gadm, results$gadm_idx[i])
    }
  }
}
cat(sprintf("Pass 3 (fuzzy): %d matched\n", sum(!is.na(results$gadm_idx))))

# --------------------------------------------------------------------------
# 6. Manual corrections for known problem cases
# --------------------------------------------------------------------------
manual_map <- c(
  "HA NOI" = "Hà Nội",
  "HO CHI MINH" = "Hồ Chí Minh city",
  "DA NANG" = "Đà Nẵng",
  "HAI PHONG" = "Hải Phòng",
  "CAN THO" = "Cần Thơ",
  "BA RIA-VUNG TAU" = "Bà Rịa - Vũng Tàu",
  "DAK LAK" = "Đắk Lắk",
  "DAK NONG" = "Đắk Nông",
  "THUA THIEN - HUE" = "Thừa Thiên Huế"
)

for (od in names(manual_map)) {
  gadm <- manual_map[od]
  i <- which(results$od_name == od & is.na(results$gadm_idx))
  j <- which(vnm$NAME_1 == gadm)
  if (length(i) == 1 && length(j) == 1) {
    results$gadm_idx[i] <- j
    results$method[i] <- "manual"
  }
}
cat(sprintf("After manual: %d matched\n", sum(!is.na(results$gadm_idx))))

# --------------------------------------------------------------------------
# 7. Build final lookup table
# --------------------------------------------------------------------------
results$gadm_name <- ifelse(!is.na(results$gadm_idx), vnm$NAME_1[results$gadm_idx], NA)
results$gadm_gid <- ifelse(!is.na(results$gadm_idx), vnm$GID_1[results$gadm_idx], NA)
results$gadm_varname <- ifelse(!is.na(results$gadm_idx), vnm$VARNAME_1[results$gadm_idx], NA)
results$gadm_type <- ifelse(!is.na(results$gadm_idx), vnm$TYPE_1[results$gadm_idx], NA)

lookup <- results %>%
  select(opendengue_name = od_name, gadm_name, gadm_gid, gadm_varname, gadm_type, method)

cat("\n=== MATCHING RESULTS ===\n")
cat(sprintf("Matched: %d / %d\n", sum(!is.na(lookup$gadm_name)), nrow(lookup)))
print(as_tibble(lookup), n = 70)

# Report unmatched
unmatched_od <- lookup %>% filter(is.na(gadm_name))
if (nrow(unmatched_od) > 0) {
  cat("\nUnmatched OpenDengue provinces:\n")
  cat(paste(" -", unmatched_od$opendengue_name), sep = "\n")
}

unmatched_gadm <- vnm$NAME_1[!vnm$NAME_1 %in% lookup$gadm_name]
if (length(unmatched_gadm) > 0) {
  cat("\nUnmatched GADM provinces (no dengue data):\n")
  cat(paste(" -", unmatched_gadm), sep = "\n")
}

# --------------------------------------------------------------------------
# 8. Save
# --------------------------------------------------------------------------
write_csv(lookup, here("data", "processed", "province_lookup.csv"))
cat(sprintf("\nSaved province lookup: data/processed/province_lookup.csv\n"))

# Save filtered and ordered shapefile
vnm_matched <- vnm %>%
  filter(NAME_1 %in% lookup$gadm_name[!is.na(lookup$gadm_name)]) %>%
  arrange(NAME_1)

st_write(vnm_matched, here("data", "processed", "vietnam_provinces.gpkg"),
         delete_dsn = TRUE, quiet = TRUE)
cat(sprintf("Saved filtered shapefile: %d provinces\n", nrow(vnm_matched)))
