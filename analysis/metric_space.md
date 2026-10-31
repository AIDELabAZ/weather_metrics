# Spatial dependence and first-stage precision

<!-- edited by: codex; edited on: 31 Oct 2026 -->

Run after the project globals and `metric_keys.do` have been established:

```stata
do "$code/analysis/reg_code/metric_geo.do"
do "$code/analysis/reg_code/metric_space.do" pilot
do "$code/analysis/reg_code/metric_space.do"
do "$code/analysis/viz_code/metric_space_vis.do"
do "$code/analysis/reg_code/metric_block.do"
```

The pilot uses seasonal total rainfall (`v05`) and rainy days (`v08`), all
six products, both outcomes, and both FE specifications. Full results retain
all 84 rainfall candidates. The primary exhibit uses reg2, year and household
FE; year-only reg7 results remain a separate comparison. No existing panel,
regression output, or household-bootstrap output is overwritten.

## Released geography and current coverage

`metric_geo.csv` records raw paths relative to `$raw`, coordinate variables,
released EA identifiers where supplied, and the actual household join keys.
Edit those mappings when the pending files are located, then rerun the same
commands. It contains no confidential coordinates or machine-specific paths.

The current roster has 28 country-wave input folders corresponding to 27
country/survey-year combinations. Tanzania's 2014 new and extended panels
are separate input folders for the same survey year. Both remain identified
in the crosswalk and coverage audit.

| Country | Panel Observations | Georeferenced Observations |
|---|---:|---:|
| Ethiopia | 10,674 | 10,664 |
| Malawi | 8,897 | 8,895 |
| Niger | 3,913 | 0 |
| Nigeria | 9,145 | 9,145 |
| Tanzania | 9,916 | 5,913 |
| Uganda | 11,692 | 5,787 |

Niger's inspected geovariables file contains no latitude/longitude fields.
Its coordinate files are pending. The available Tanzania geography covers
2008, 2010, and 2012 rainfall years; Uganda covers 2009, 2010, and 2011.
Later-wave coordinates for both countries are pending. The user is locating
these files. No location is carried forward from an earlier wave.

Original IDs are recovered from the existing household/append intermediates:
Ethiopia's `household_id2`, Malawi's long/short-panel wave identifiers,
Nigeria's original `hhid`, Tanzania's wave-specific IDs, and Uganda's
reconstructed panel links. Malawi's baseline family ID alone is not a unique
tracked-unit key. Joins preserve each country's existing panel identifiers.

Global coordinate ranges and broad country envelopes flag implausible
positions. The envelopes are checks rather than exact national boundaries.
Suppressed or missing coordinates remain missing. Released EA codes are
retained where available. When no EA code is released, identical modified
coordinate pairs define location groups; these are explicitly identified
in the inventory. Grouping identical positions leaves the covariance kernel
unchanged. The analysis does not infer permanent EA identities across waves.

`geo_inventory.csv` reports every active input folder, source variables,
matched keys, valid-coordinate coverage, and distinct EA/location groups.
`geo_merge_audit.csv` reports the actual outcome-specific regression coverage.
`geovariables_crosswalk.dta` preserves original keys and wave-specific locations;
`lsms_panel_geo.dta` is a separate copy of the existing panel with this crosswalk.
Large Tanzania/Uganda sample restrictions must accompany any interpretation.

## Scores, kernels, and finite-sample correction

Each outcome and rainfall variable are residualized on the specified FE.
For each separate single-instrument fit, the score is residualized rainfall
times the full regression residual. This reuses `metric_fe.mata`; year-FE
rank accounts for disconnected household cohorts. All variance estimators
for a fit use the same observations and the same coefficient.

The household component is the sum of squared household score sums, retaining
unrestricted own-household serial covariance. Contemporaneous spatial terms
use EA/location-year score sums with a triangular kernel at 50, 100, and
200 km. The primary bandwidth is 100 km. Diagonal location terms retain
cross-household dependence at the same released position; subtracting the
individual squared scores avoids counting own-household terms twice.

Distances are Haversine great-circle kilometers with radius 6,371.0088 km.
A geographic cell index restricts the search before calculating distances.
Sparse neighbor lists extend to 300 km for the diagnostic reference band and
are cached by country, shared by both outcomes and all rainfall candidates.
The estimator never constructs a dense all-location distance matrix.

The same household-cluster small-sample factor, G/(G-1) times (N-1)/(N-k),
multiplies the household and spatial components. The effective parameter
count k matches the identifiable FE specification. Raw spatial variances
and covariance components are retained. Nonpositive variances are flagged;
no arbitrary positive floor or silent replacement is applied.

An additional 100-km sensitivity includes adjacent *survey intervals* with
temporal Bartlett weight 0.5. Its own-household weighted cross-wave terms
are subtracted because household clustering already includes them. A missing
survey wave is not treated as an adjacent interval. This sensitivity does
not claim robustness to arbitrary between-household dependence at all lags.

## Descriptive diagnostics and figures

The correlogram uses only the prespecified total-rainfall and rainy-day
scores. Each location-year score sum is divided by the square root of its
household count, then standardized across locations within specification
and year. Distance-bin values are mean standardized cross-products, weighted
by the number of eligible pairs across years. They are not Pearson
correlations. The figure takes the median across six products and two
outcomes, giving each specification equal weight. Contemporaneous and
adjacent-interval diagnostics remain separate in the saved results.
Year FE impose finite-sample score restrictions; a negative long-distance
reference value need not indicate negative meteorological dependence.

Three new PDF/PNG figures are created in `figures/metric_paper/`:

- `space_score`: six-country score dependence, with pending geography labeled.
- `space_share`: paired household/100-km shares above |t|=1.96.
- `space_share481`: the corresponding appendix comparison at |t|=4.81.

`spatial_shares.csv` includes 50/100/200-km, adjacent-interval, and year-only
FE comparisons. Each paired share uses exactly the same estimable
specifications in its household and spatial numerator. Attempted,
household-estimable, matched, and invalid-variance counts are reported;
unavailable results are not coded as zero significance.

## Saved results and executed validation

Outputs are under `results_data/additional_evidence/exhibit3/`. The
`spatial_first_stage` DTA/CSV retains signed coefficients and t-statistics,
all SEs, raw variances, covariance components, sample sizes, warnings, and
original weather/specification identifiers. `geo_model_comparison.csv`
compares household estimates on the georeferenced sample with the original
regression rows, separating coverage effects from covariance changes.
`score_correlogram` and `score_summary` retain the diagnostic denominators.
Wide score files under `scores/` preserve every observation's household,
year, released location, outcome/specification, and `q_<weather_var>` scores.
This avoids repeating the same identifiers in millions of long-format rows.

Executed with StataNow 19.5 using built-in Stata/Mata commands and no new
production packages. All 240 available-country pilot fits matched direct
Stata coefficients, household-clustered SEs, and observation counts to
relative tolerance 1e-8. Independent chord-distance neighbor searches
reproduced every cached pair: 136,355 Ethiopia; 841,623 Malawi; 182,319
Nigeria; 99,408 Tanzania; 295,878 Uganda. The pending Niger list is empty.
A separate, hand-checkable example independently reproduced the covariance
calculation, including same-location households, a mover, serial household
terms, and the adjacent-interval subtraction, to tolerance 1e-10. Those
verification fits/examples are not part of the production scripts.

The full run saved 2,016 specification rows: 840 estimated reg2 fits and
840 estimated reg7 fits, with 336 Niger rows explicitly marked as missing
coordinates. All estimated fits have positive spatial variances at every
prespecified bandwidth and in the adjacent-interval sensitivity. Each
available country's primary paired comparison contains 168 specifications.

## Triggered bootstrap pilot

The 100-km adjustment reduces threshold-crossing shares in all five available
countries, triggering the plan's subset assessment. `metric_block.do` pilots
CHIRPS total rainfall and rainy days, both outcomes, and the five currently
available countries: 20 declared cells. Both resampling designs use the
identical georeferenced sample and preserve each household's observed panel
history. The existing 1,008-by-1,000 household-bootstrap files remain untouched.

The geographic design uses 100-km equirectangular cells connected through
household histories, so no household or cell is divided between blocks.
This linkage can produce blocks larger than an individual grid cell. There
are 199 draws per design/cell. Design d uses seed
`20261031+1000*country+10*outcome+d`. Household resampling is d=1; geographic
resampling is d=2. Integer resampling frequencies produce the same
coefficients as copied household histories with separate FE, avoiding
thousands of redundant full regression commands. An actual-sample weighted
comparison verified the statistic against Stata frequency-weighted fits.

The statistic is reg2 minus reg7, standardized by the original georeferenced
sample's weather/outcome SD ratio. `block_boot_draws.dta` retains all 7,960
attempts. `block_boot_pilot.csv` records the 40 distributions, successful and
failed draws, and percentile intervals. Intervals require at least 95%
successful replications. `block_boot_comparison.csv` compares interval widths
only when both designs are complete.

The 16 comparisons outside Malawi completed all 199 draws. Malawi has only
two connected geographic blocks; its four geographic distributions have
151 or 156 successful draws and do not meet the required success rate.
Their intervals and significance indicators remain unavailable. This is a
design limitation, not evidence of zero uncertainty. The pilot is not a
replacement for the paper's production bootstrap or a claim of unrestricted
spatial-temporal robustness. Coordinate coverage, block design, and the
adjacent-interval sensitivity must be assessed before interpreting the full
bootstrap's significance rates as spatially robust.
