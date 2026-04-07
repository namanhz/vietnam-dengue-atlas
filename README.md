# Vietnam Dengue Atlas

**Author:** Nam Anh Le, National Economics University

Interactive web application visualising Bayesian spatial estimates of dengue incidence across Vietnam's 63 provinces. Inspired by the [Australian Cancer Atlas](https://atlas.cancer.org.au/).

## Features

- **Single-page atlas layout** — map and province detail side-by-side, no tab switching
- **Choropleth map** of smoothed SIR, exceedance probabilities, or incidence rates by province and year (1994-2010)
- **Province detail panel** — click any province to see SIR, credible intervals, evidence classification, gradient bar, time series, and summary statistics
- **Methodology modal** — full statistical methodology with LaTeX equations accessible via button
- **Year animation** — animate through 1994-2010 to see the spatial pattern evolve

## Visualisation Design

### Layout

The app uses a single-page design with three zones:

| Zone | Description |
|------|-------------|
| **Header bar** | Dark (#24292f) top bar with title, measure selector, year slider, methodology button |
| **Map (left, ~70%)** | Full-height Leaflet choropleth on CartoDB Positron (no labels) basemap |
| **Detail panel (right, 360px)** | Province statistics panel, populated on click |

### Choropleth Colour Scales

Four measures are available, each with a purpose-designed colour ramp:

#### 1. Smoothed SIR (Standardised Incidence Ratio)

Diverging blue-to-red scale **centred at SIR = 1.0** (national average) on a **log10 scale**. The log transformation ensures that SIR = 0.5 (half the national rate) and SIR = 2.0 (double the national rate) are equidistant from the midpoint, which is the correct behaviour for a ratio measure.

| SIR | log10(SIR) | Colour | Hex | Interpretation |
|-----|-----------|--------|-----|----------------|
| 0.1 | -1.0 | Deep blue | `#2166AC` | ~90% below national average |
| 0.2 | -0.7 | Medium blue | `#4393C3` | ~80% below average |
| 0.5 | -0.3 | Light blue | `#92C5DE` | ~50% below average |
| 0.8 | -0.1 | Pale blue | `#D1E5F0` | Slightly below average |
| **1.0** | **0.0** | **White/neutral** | **transition** | **National average** |
| 1.3 | +0.1 | Pale red | `#FDDBC7` | Slightly above average |
| 2.0 | +0.3 | Light red | `#F4A582` | ~2x national average |
| 5.0 | +0.7 | Medium red | `#D6604D` | ~5x national average |
| 10.0 | +1.0 | Deep red | `#B2182B` | ~10x national average |

**Why log scale?** SIR is a ratio — multiplicative deviations should be visually symmetric. On a linear scale, SIR = 0.5 (halved risk) would occupy the same visual distance as SIR = 1.5 (50% increase), which misrepresents the magnitude of the deviation. On log10 scale, equal visual distances correspond to equal multiplicative changes. The domain is log10(0.1) = -1 to log10(10) = +1, with log10(1.0) = 0 at the exact midpoint (white/neutral colour).

This is an 8-class diverging palette from ColorBrewer RdBu.

#### 2. Exceedance Probability P(SIR > 1)

Diverging blue-to-red scale over [0, 1]:

| P(SIR>1) | Colour | Interpretation |
|-----------|--------|----------------|
| 0 - 0.05 | Deep blue `#2166AC` | Very likely lower than average |
| 0.05 - 0.20 | Medium blue `#4393C3` | Likely lower |
| 0.20 - 0.40 | Light blue `#D1E5F0` | Possibly lower |
| 0.40 - 0.60 | Near white `#F7F7F7` | Inconclusive |
| 0.60 - 0.80 | Light red `#FDDBC7` | Possibly elevated |
| 0.80 - 0.95 | Medium red `#D6604D` | Likely elevated |
| 0.95 - 1.0 | Deep red `#B2182B` | Very likely elevated |

This is the most decision-relevant quantity — it directly answers "is this province's risk meaningfully above average?"

#### 3 & 4. Raw / Smoothed Incidence Rate (per 100,000)

Sequential red scale (8-class OrRd):

`#FFF5F0` → `#FEE0D2` → `#FCBBA1` → `#FC9272` → `#FB6A4A` → `#EF3B2C` → `#CB181D` → `#99000D`

Domain is **fixed across all years** at [0, 98th percentile of all province-year values] to ensure consistent colour meaning when animating through years. Without a fixed domain, the same shade of red could mean 50/100k in one year and 500/100k in another, misleading the viewer.

### Province Detail Panel

When a province is clicked, the right panel displays:

1. **Header** — Province name, year, rank among 63 provinces
2. **SIR Card** — Large SIR value (28px bold), 95% credible interval, evidence badge
3. **Evidence Badge** — Colour-coded classification:
   - Red badge (`#cf222e` on `#ffebe9`): "Very likely elevated" (P > 0.95)
   - Yellow badge (`#9a6700` on `#fff8c5`): "Likely elevated" (P > 0.80)
   - Grey badge (`#656d76` on `#f0f2f5`): "No clear difference" (0.20 < P < 0.80)
   - Blue badge (`#0550ae` on `#ddf4ff`): "Likely lower" (P < 0.20)
   - Green badge (`#116329` on `#dafbe1`): "Very likely lower" (P < 0.05)
4. **Gradient Bar** — Horizontal bar from blue (lower) to red (higher), with a triangle marker showing where the province falls. Position is computed on log10 scale: endpoints are SIR = 0.1 (left, log10 = -1) and SIR = 10.0 (right, log10 = +1), with SIR = 1.0 (log10 = 0) at the exact centre. Marker position = (log10(SIR) + 1) / 2 * 100%, clamped to [3%, 97%]
5. **Time Series** — Compact Plotly chart (200px) showing annual SIR with 95% CrI ribbon (blue fill) and national average reference line (red dashed at SIR=1)
6. **Statistics Table** — Observed cases, expected cases, population, smoothed incidence per 100k, P(SIR > 1)

### Map Interaction

- **Hover**: Rich HTML tooltip with province name, selected measure value, case count, 95% CrI, and exceedance probability
- **Click**: Populates the right panel with full province details
- **Zoom bounds**: Locked to Vietnam region (lat 7.5-24, lng 101-115), zoom range 5-12
- **Highlight**: On hover, province border thickens to 2px white with increased fill opacity

### Typography and Theme

- **Font**: System font stack (`-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto`)
- **Header**: Dark background (#24292f), white text, 64px height
- **Body**: Light background (#f6f8fa), white cards, subtle borders (#d0d7de)
- **Numbers**: Tabular numerals (`font-variant-numeric: tabular-nums`) for aligned columns
- **Section titles**: 11px uppercase with letter-spacing, muted colour — used for "Annual Trend", "Statistics"

## Statistical Model

BYM2 spatiotemporal model (Riebler et al., 2016) fitted via R-INLA:

- Poisson likelihood with expected case offset (indirect standardisation)
- BYM2 spatial random effect with PC priors (phi = 0.69: 69% spatially structured)
- RW1 temporal random effect
- Full posterior inference: SIR, 95% credible intervals, exceedance probabilities
- Sensitivity analysis across 4 model specifications (prior variants, RW1 vs RW2)

See [docs/methodology.md](docs/methodology.md) for the full statistical methodology.

## Data Sources

- **Dengue cases**: [OpenDengue V1.3](https://github.com/OpenDengue/master-repo) (Clarke et al., 2024) — monthly province-level data, 1994-2010
- **Administrative boundaries**: [GADM 4.1](https://gadm.org/) Vietnam Level 1 (63 provinces)
- **Population**: Vietnam General Statistics Office (GSO) — 1999 and 2009 census with intercensal interpolation

## Reproduction

### Prerequisites

- R >= 4.5
- Rtools (Windows) or build tools (Linux/Mac)

### Steps

```bash
# 1. Install packages (INLA + CRAN dependencies)
Rscript R/00_setup.R

# 2. Download data (OpenDengue + GADM shapefiles)
Rscript R/01_download_data.R

# 3. Run pipeline (scripts 02-10 in order)
Rscript R/02_clean_opendengue.R
Rscript R/03_match_provinces.R
Rscript R/04_prepare_population.R
Rscript R/05_compute_expected.R
Rscript R/06_build_adjacency.R
Rscript R/07_fit_bym2.R
Rscript R/08_diagnostics.R
Rscript R/09_extract_posteriors.R
Rscript R/10_export_geojson.R

# 4. Launch Shiny app
Rscript -e "shiny::runApp('app/', port=4040)"
```

## Project Structure

```
R/                Statistical pipeline (numbered scripts 00-10)
  utils/          Shared functions (name matching, INLA helpers)
app/              Shiny web application
  R/              Shiny modules (map, province detail)
  www/            CSS styles
data/raw/         Downloaded data (gitignored)
data/processed/   Cleaned intermediate files
data/output/      Model results and frontend data (GeoJSON, posteriors, trends)
docs/             Statistical methodology documentation
output/           Diagnostic figures and model comparison tables
```

## References

1. Clarke et al. (2024). "OpenDengue: data from the OpenDengue database." *Sci Data*, 11:296.
2. Riebler et al. (2016). "An intuitive Bayesian spatial model for disease mapping that accounts for scaling." *Stat Methods Med Res*, 25(4):1145-1165.
3. Simpson et al. (2017). "Penalising model component complexity." *Statistical Science*, 32(1):1-28.
4. Dong et al. (2020). "Development of the Australian Cancer Atlas." *Int J Health Geographics*, 19:1-16.
5. Sorbye & Rue (2014). "Scaling intrinsic Gaussian Markov random field priors in spatial modelling." *Spatial Statistics*, 8:39-51.

## License

MIT
