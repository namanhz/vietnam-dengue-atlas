# Statistical Methodology

**Author:** Nam Anh Le, National Economics University

## Overview

The Vietnam Dengue Atlas presents Bayesian spatiotemporal estimates of dengue incidence across Vietnam's 63 provinces. The methodology follows established disease mapping approaches, particularly the BYM2 model (Riebler et al., 2016), as used in the Australian Cancer Atlas (Dong et al., 2020).

## Data Sources

- **Dengue cases (1994-2010)**: OpenDengue database V1.3 (Clarke et al., 2024). Monthly province-level case counts from passive surveillance.
- **Dengue cases (2011-2017)**: Vietnam General Department of Preventive Medicine (GDPM) Communicable Disease Yearbooks ("Nien giam"), parsed from official Excel publications (epix-project/gdpm, GitHub). Monthly province-level case counts.
- **Population**: Vietnam General Statistics Office (GSO) census data (1999 and 2009 censuses) with province-specific intercensal growth rate interpolation and extrapolation.
- **Administrative boundaries**: GADM version 4.1, admin level 1 (63 provinces).

**Data availability note**: Province-level dengue surveillance data for Vietnam is publicly available only through 2017. Post-2017 data (including the major 2019 epidemic with ~580,000 national cases) exists within the Vietnamese Ministry of Health surveillance system but is not publicly released.

## Study Design

This is an ecological study of province-level dengue incidence in Vietnam. The unit of analysis is the province-year.

## Expected Cases (Indirect Standardisation)

Expected cases are computed via indirect standardisation:

$$E_{it} = P_{it} \times r_t$$

where $P_{it}$ is the population of province $i$ in year $t$, and $r_t = \sum_i Y_{it} / \sum_i P_{it}$ is the national dengue rate in year $t$. The Standardised Incidence Ratio (SIR) is $\theta_{it} = Y_{it} / E_{it}$.

## Statistical Model

### BYM2 Spatiotemporal Model

Observed counts $Y_{it}$ are modelled as:

$$Y_{it} \sim \text{Poisson}(E_{it} \cdot \theta_{it})$$

$$\log(\theta_{it}) = \beta_0 + b_i + \gamma_t$$

where:
- $\beta_0$ is an overall intercept
- $b_i$ is a BYM2 spatial random effect for province $i$
- $\gamma_t$ is a first-order random walk (RW1) temporal effect for year $t$

### Choice of Likelihood: Poisson vs Negative Binomial

Dengue case counts are often overdispersed relative to the Poisson assumption. However, in the BYM2 framework, extra-Poisson variation is explicitly accommodated through the unstructured spatial component $v_i$. The IID random effect $v_i \sim N(0, 1)$ within the BYM2 decomposition acts as a province-level overdispersion term, absorbing excess variability that cannot be explained by spatial structure alone. This is a well-known property of the BYM class of models (Lawson, 2018): the inclusion of unstructured random effects at the observational level renders a separate overdispersion parameter largely redundant.

This was verified empirically by comparing the Poisson BYM2 model against a Negative Binomial alternative. The Negative Binomial model produced near-identical posterior estimates for the relative risks $\theta_{it}$, with negligible improvement in WAIC, confirming that the random effects adequately capture the overdispersion structure. The Poisson likelihood is therefore retained for parsimony and interpretability.

### BYM2 Spatial Component

The BYM2 model (Riebler et al., 2016) reparameterises the classic Besag-York-Mollié model as:

$$b_i = \frac{1}{\sqrt{\tau_b}} \left( \sqrt{\phi} \cdot u_i^* + \sqrt{1-\phi} \cdot v_i \right)$$

where:
- $u_i^*$ is a scaled ICAR (intrinsic conditional autoregressive) component capturing spatially structured variation
- $v_i \sim N(0, 1)$ is an unstructured (IID) component
- $\phi \in [0, 1]$ is the mixing parameter: $\phi = 1$ means purely spatial, $\phi = 0$ means purely unstructured
- $\tau_b$ is the overall precision (inverse variance)

The ICAR component $u_i^*$ is scaled so that the geometric mean of its marginal variances equals 1, following the approach of Sørbye and Rue (2014). This scaling is critical: it ensures that the hyperparameters $\tau_b$ and $\phi$ have consistent interpretation regardless of the adjacency graph structure (i.e., regardless of the number and arrangement of provinces). Without scaling, the same value of $\tau_b$ would imply different levels of spatial variation for different maps, making prior specification and comparison across studies problematic.

This parameterisation has two advantages: (1) $\phi$ is directly interpretable as the proportion of spatial variation that is structured, and (2) the marginal variance is constant regardless of the graph structure.

### Temporal Component: RW1 vs RW2

The temporal trend $\gamma_t$ follows a first-order random walk (RW1):

$$\gamma_t | \gamma_{t-1} \sim N(\gamma_{t-1}, \tau_\gamma^{-1})$$

RW1 produces piecewise linear trends, while the alternative RW2 (second-order random walk) produces smoother, locally quadratic trends. RW1 was selected on both empirical and substantive grounds. Empirically, model comparison via WAIC favoured RW1 over RW2 (WAIC 1,228,126 vs 1,244,728). Substantively, dengue in Vietnam exhibits sudden epidemic peaks (e.g., 1998, 2007, 2010) followed by sharp declines. RW1 is better suited to capturing such abrupt year-to-year shifts, whereas RW2's smoothness penalty would over-regularise these transitions.

### Space-Time Interaction

The current model assumes an additive structure: the spatial pattern $b_i$ is time-invariant, and the temporal trend $\gamma_t$ is spatially uniform. This implies, for example, that if a province has twice the national risk in one year, it has twice the risk in all years. This is a simplifying assumption.

In principle, a space-time interaction term $\delta_{it}$ (Knorr-Held, 2000; Types I–IV) would allow the spatial pattern to evolve over time. A Type I interaction (IID $\delta_{it}$) was evaluated but did not meaningfully improve WAIC while substantially increasing model complexity (adding $63 \times 17 = 1{,}071$ additional random effects). The residual spatial autocorrelation detected in diagnostics (Moran's I = 0.39, $p < 0.001$) suggests some interaction structure exists, but the additional flexibility did not translate into improved predictive performance for this dataset. The additive model is therefore retained for the atlas, noting that space-time interaction is a natural extension for future work with finer temporal resolution (e.g., monthly data).

## Prior Specification

Penalised Complexity (PC) priors (Simpson et al., 2017) are used, which penalise departure from a simpler base model:

| Parameter | PC Prior | Interpretation |
|-----------|----------|---------------|
| $\phi$ (BYM2 mixing) | $P(\phi < 0.5) = 2/3$ | A priori, spatial structure likely accounts for less than half the total variation |
| $\sigma_b$ (spatial SD) | $P(\sigma_b > 1) = 0.01$ | Very unlikely that spatial standard deviation on log-RR scale exceeds 1 (≈3-fold risk variation) |
| $\sigma_\gamma$ (temporal SD) | $P(\sigma_\gamma > 0.5) = 0.01$ | Very unlikely that year-to-year temporal SD exceeds 0.5 |

These are weakly informative priors that allow the data to dominate while preventing implausible extreme values. Sensitivity analysis confirmed that results are robust to doubling and halving the PC prior scale parameters (see Diagnostics).

## Model Fitting

The model is fitted using Integrated Nested Laplace Approximations (INLA; Rue et al., 2009) via the R-INLA package. INLA provides fast, accurate approximate Bayesian inference for latent Gaussian models, which is well-suited to spatial disease mapping applications.

## Key Outputs

### Smoothed SIR
The posterior mean of $\theta_{it}$ provides a smoothed estimate of the relative risk in province $i$, year $t$. Values above 1 indicate higher-than-expected incidence; below 1 indicates lower.

### Credible Intervals
95% posterior credible intervals for each province-year SIR quantify uncertainty. Narrower intervals indicate more precise estimates (typically for provinces with larger populations).

### Exceedance Probabilities
$P(\theta_{it} > 1 | \text{data})$ — the posterior probability that a province has elevated risk. This is the most decision-relevant quantity:
- **> 95%**: Very likely elevated risk
- **80-95%**: Likely elevated risk
- **20-80%**: Inconclusive
- **5-20%**: Likely lower risk
- **< 5%**: Very likely lower risk

## Diagnostics

- **DIC and WAIC**: Information criteria for model comparison across four specifications (main model, tighter/looser spatial priors, RW2 temporal). Results were stable: WAIC ranged from 1,228,099 to 1,244,728, with the main model performing within 27 units of the best.
- **PIT (Probability Integral Transform)**: Cross-validated calibration check. The PIT histogram showed some departure from uniformity, consistent with the additive model's inability to capture all space-time interaction structure.
- **CPO (Conditional Predictive Ordinate)**: 46/1,071 observations (4.3%) had CPO failures, predominantly in province-years with very low expected counts.
- **Moran's I on residuals**: Moran's I = 0.39 ($p < 0.001$) on time-averaged residuals, indicating residual spatial autocorrelation. This is attributable to the absence of a space-time interaction term (see above).
- **Sensitivity analysis**: Models refitted with halved/doubled PC prior parameters and RW2 temporal structure. Posterior estimates of province-level SIR were robust across all specifications (rank correlations > 0.99).
- **Overdispersion check**: Poisson BYM2 compared against Negative Binomial; negligible difference in fit confirmed that random effects absorb extra-Poisson variation.

## Design Choices

### Descriptive Mapping Without Covariates

The atlas adopts a purely descriptive mapping approach, consistent with the Australian Cancer Atlas (Dong et al., 2020). The spatial random effect $b_i$ intentionally captures all province-level variation in dengue risk, including contributions from climate, urbanisation, vector ecology, healthcare infrastructure, and socioeconomic factors. This is a deliberate design choice, not a limitation: the goal is to identify *where* risk is elevated and *how certain* the estimate is, not to attribute risk to specific causes.

A covariate-adjusted model (e.g., incorporating ERA5 climate variables or urbanisation indices) would decompose the spatial effect into explained and residual components. This is a natural extension for aetiological analysis but would fundamentally change the interpretation of the mapped quantities — from "total relative risk" to "residual risk after adjustment." For a public-health atlas intended to support surveillance prioritisation, the unadjusted estimates are more directly actionable.

## Limitations

1. **Ecological fallacy**: Province-level associations do not imply individual-level risk factors.
2. **Reporting bias**: Dengue surveillance varies across provinces; under-reporting is likely, particularly in rural and northern provinces.
3. **Case definition changes**: Diagnostic criteria for dengue may have changed over the study period.
4. **Population estimates**: Intercensal population figures are extrapolated from census benchmarks using a uniform growth rate assumption.
5. **Additive spatiotemporal structure**: The model does not include a space-time interaction term, implying that the relative spatial pattern of risk is constant over time. Residual diagnostics suggest this assumption is approximate.

## References

1. Clarke et al. (2024). "OpenDengue: data from the OpenDengue database." *Scientific Data*, 11:296.
2. Dong et al. (2020). "Development of the Australian Cancer Atlas." *International Journal of Health Geographics*, 19:1-16.
3. Knorr-Held, L. (2000). "Bayesian modelling of inseparable space-time variation in disease risk." *Statistics in Medicine*, 19(17-18):2555-2567.
4. Lawson, A.B. (2018). *Bayesian Disease Mapping: Hierarchical Modeling in Spatial Epidemiology*. 3rd edition. CRC Press.
5. Riebler et al. (2016). "An intuitive Bayesian spatial model for disease mapping that accounts for scaling." *Statistical Methods in Medical Research*, 25(4):1145-1165.
6. Rue et al. (2009). "Approximate Bayesian inference for latent Gaussian models by using integrated nested Laplace approximations." *JRSS-B*, 71(2):319-392.
7. Simpson et al. (2017). "Penalising model component complexity: A principled, practical approach to constructing priors." *Statistical Science*, 32(1):1-28.
8. Sørbye, S.H. and Rue, H. (2014). "Scaling intrinsic Gaussian Markov random field priors in spatial modelling." *Spatial Statistics*, 8:39-51.
