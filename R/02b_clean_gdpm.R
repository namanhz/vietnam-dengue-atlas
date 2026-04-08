# ============================================================================
# 02b_clean_gdpm.R - Parse GDPM yearbooks 2011-2017 for province-level dengue
# ============================================================================
#
# The Excel files have encoding issues with Vietnamese characters.
# Solution: use positional mapping (63 rows = 63 provinces in fixed order).
# Order verified from 2017 yearbook SXH sheet.

library(tidyverse)
library(readxl)
library(here)

raw_dir <- here("data", "raw", "gdpm_raw")

# --------------------------------------------------------------------------
# 1. Fixed positional mapping: yearbook row order -> GADM VARNAME_1
# --------------------------------------------------------------------------
# Verified from 2017 yearbook. This order is standard for Vietnamese yearbooks.
gadm_varname_order <- c(
  "Ha Noi", "Hai Phong", "Thai Binh", "Nam Dinh", "Ha Nam", "Ninh Binh",
  "Thanh Hoa", "Bac Giang", "Bac Ninh", "Phu Tho", "Vinh Phuc",
  "Hai Duong", "Hung Yen", "Thai Nguyen", "Bac Kan", "Quang Ninh",
  "Hoa Binh", "Nghe An", "Ha Tinh", "Lai Chau", "Lang Son",
  "Tuyen Quang", "Ha Giang", "Cao Bang", "Yen Bai", "Lao Cai",
  "Son La", "Dien Bien", "Quang Binh", "Quang Tri", "Thua Thien Hue",
  "Da Nang", "Quang Nam", "Quang Ngai", "Binh Dinh", "Phu Yen",
  "Khanh Hoa", "Ninh Thuan", "Binh Thuan", "Ho Chi Minh",
  "Ba Ria - Vung Tau", "Dong Nai", "Tien Giang", "Long An",
  "Lam Dong", "Tay Ninh", "Can Tho", "Soc Trang", "An Giang",
  "Ben Tre", "Tra Vinh", "Vinh Long", "Dong Thap", "Binh Duong",
  "Binh Phuoc", "Kien Giang", "Ca Mau", "Bac Lieu", "Hau Giang",
  "Dak Lak", "Dak Nong", "Gia Lai", "Kon Tum"
)

stopifnot(length(gadm_varname_order) == 63)

# Map varnames to GADM NAME_1
lookup <- read_csv(here("data", "processed", "province_lookup.csv"), show_col_types = FALSE)
varname_to_name <- lookup %>%
  select(gadm_varname, gadm_name) %>%
  distinct() %>%
  filter(!is.na(gadm_varname))

# --------------------------------------------------------------------------
# 2. Parse yearbook: extract morbidity from SXH sheet
# --------------------------------------------------------------------------
parse_yearbook <- function(filepath, year) {
  d <- read_excel(filepath, sheet = "SXH", col_names = FALSE)

  # Identify data rows (skip headers, M/C indicator rows, empty rows)
  raw_col1 <- as.character(d[[1]])
  mc_rows <- which(apply(d, 1, function(r) {
    any(grepl("^\\s*M\\s*$|^\\s*C\\s*$", as.character(r)))
  }))
  header_rows <- which(is.na(raw_col1) | raw_col1 == "" |
                         grepl("Tinh|T.pho|TØnh|province", raw_col1, ignore.case = TRUE))
  skip <- unique(c(mc_rows, header_rows))

  data_rows <- setdiff(seq_len(nrow(d)), skip)
  # Filter to rows with non-empty first column
  data_rows <- data_rows[!is.na(raw_col1[data_rows]) & raw_col1[data_rows] != ""]

  if (length(data_rows) != 63) {
    warning(sprintf("Year %d: expected 63 data rows, got %d", year, length(data_rows)))
  }

  # Morbidity columns: every other column starting from 2
  case_cols <- seq(2, min(25, ncol(d)), by = 2)

  results <- list()
  for (i in seq_along(data_rows)) {
    row_idx <- data_rows[i]
    prov <- if (i <= 63) gadm_varname_order[i] else NA_character_

    for (m in seq_len(min(12, length(case_cols)))) {
      val <- as.numeric(d[[case_cols[m]]][row_idx])
      results[[length(results) + 1]] <- data.frame(
        gadm_varname = prov,
        year = year,
        month = m,
        dengue_cases = ifelse(is.na(val), 0, val),
        stringsAsFactors = FALSE
      )
    }
  }

  bind_rows(results)
}

# --------------------------------------------------------------------------
# 3. Parse all yearbooks 2011-2017
# --------------------------------------------------------------------------
all_data <- list()

for (yr in 2011:2017) {
  f <- file.path(raw_dir, sprintf("nien_giam_%d.xls", yr))
  if (!file.exists(f)) { cat(sprintf("MISSING: %d\n", yr)); next }

  cat(sprintf("Parsing %d ... ", yr))
  tryCatch({
    d <- parse_yearbook(f, yr)
    cat(sprintf("%d rows, %d provinces\n", nrow(d), n_distinct(d$gadm_varname)))
    all_data[[as.character(yr)]] <- d
  }, error = function(e) cat(sprintf("ERROR: %s\n", conditionMessage(e))))
}

gdpm <- bind_rows(all_data) %>% filter(!is.na(gadm_varname))

# Map to GADM NAME_1
gdpm <- gdpm %>%
  left_join(varname_to_name, by = "gadm_varname")

cat(sprintf("\nGDPM total: %d monthly records\n", nrow(gdpm)))
cat(sprintf("Matched to GADM: %d\n", sum(!is.na(gdpm$gadm_name))))

# --------------------------------------------------------------------------
# 4. Aggregate to annual
# --------------------------------------------------------------------------
gdpm_annual <- gdpm %>%
  filter(!is.na(gadm_name)) %>%
  group_by(gadm_name, year) %>%
  summarise(dengue_total = sum(dengue_cases, na.rm = TRUE),
            n_months = n(), .groups = "drop")

cat(sprintf("\nGDPM annual: %d province-years, %d provinces\n",
            nrow(gdpm_annual), n_distinct(gdpm_annual$gadm_name)))

# --------------------------------------------------------------------------
# 5. Merge with OpenDengue (1994-2010)
# --------------------------------------------------------------------------
od_annual <- read_csv(here("data", "processed", "vietnam_dengue_annual.csv"),
                      show_col_types = FALSE)

# Map OpenDengue names to GADM names
od_mapped <- od_annual %>%
  left_join(lookup %>% select(opendengue_name, gadm_name),
            by = c("province_clean" = "opendengue_name")) %>%
  filter(!is.na(gadm_name)) %>%
  group_by(gadm_name, year) %>%
  summarise(dengue_total = sum(dengue_total, na.rm = TRUE),
            n_months = sum(n_months), .groups = "drop") %>%
  mutate(source = "OpenDengue")

# Combine
combined <- bind_rows(
  od_mapped,
  gdpm_annual %>% mutate(source = "GDPM")
)

cat(sprintf("\nCombined: %d province-years\n", nrow(combined)))
cat(sprintf("Years: %d-%d\n", min(combined$year), max(combined$year)))
cat(sprintf("Provinces: %d\n", n_distinct(combined$gadm_name)))

cat("\nAnnual totals:\n")
print(combined %>%
        group_by(year, source) %>%
        summarise(total = sum(dengue_total), provinces = n_distinct(gadm_name),
                  .groups = "drop") %>%
        arrange(year), n = 30)

write_csv(combined, here("data", "processed", "vietnam_dengue_combined.csv"))
cat("\nSaved: data/processed/vietnam_dengue_combined.csv\n")
