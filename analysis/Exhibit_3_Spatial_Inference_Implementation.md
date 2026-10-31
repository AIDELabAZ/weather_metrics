# Exhibit 3: Spatial Dependence and First-Stage Precision

**Project:** *Cloudy With A Chance of Significance*  
**Purpose:** Measure the geographic dependence in first-stage regression scores, then assess whether household-clustered standard errors overstate first-stage precision when nearby households experience correlated shocks.  
**Proposed placement:** One new two-part exhibit in the results or appendix, depending on findings.  
**Status:** Implementation plan, not empirical results.

## 1. Why the existing data are sufficient

**Use the publicly released, modified EA coordinates. Do not obtain confidential household GPS coordinates or run a displacement-error analysis.** The GPS information needed here is typically distributed in the **geovariables files in the raw survey directory for each country-wave**.

Michler, Josephson, Kilic, and Murray (2022), *Privacy Protection, Measurement Error, and the Integration of Remote Sensing and Socioeconomic Survey Data*, *Journal of Development Economics* **158**, 102927, compared anonymized locations with confidential household locations across LSMS-ISA surveys and remote sensing weather products. It found that common geographic anonymization procedures had, on average, **limited to no effect on estimated weather–agricultural productivity relationships**. This supports using the released EA coordinates as the geography for the present exercise. The new question concerns **spatial dependence in regression errors and first-stage inference**, which the 2022 paper did not itself estimate.

Paper: https://doi.org/10.1016/j.jdeveco.2022.102927. Relevant discussion: abstract and pp. 2, 5, 15, and 23.

## 2. Research question and new evidence

Rainfall experienced by nearby households is correlated, especially when multiple EAs share weather grid cells or large-scale weather systems. The relevant inferential question is **not whether rainfall is spatially correlated**, but whether **first-stage regression scores** are correlated across households in ways not captured by clustering only at the household level.

Two empirical outputs are needed:

1. **Spatial correlogram of first-stage regression scores:** New measurement of how the covariance relevant for the rainfall coefficient changes with distance between EAs.
2. **Spatially adjusted first-stage precision:** Re-estimated standard errors and shares of specifications exceeding the paper's first-stage t-statistic thresholds, holding coefficients and estimation samples fixed.

**Logical contribution:** If spatial dependence in the relevant scores is positive and materially increases estimated coefficient uncertainty, the effective amount of independent first-stage information is smaller than household clustering suggests. This would strengthen the weak-relevance argument through a distinct mechanism. A null or opposite result must be reported as such; spatially robust standard errors are not automatically larger.

## 3. Repository and raw data locations

The project [repository](https://github.com/AIDELabAZ/weather_and_agriculture) uses `$code` for scripts and `$data` for local data. The documented raw household folder convention is:

```text
$data/household_data/<country>/wave_<n>/raw/
```

with `country` in `ethiopia`, `malawi`, `niger`, `nigeria`, `tanzania`, `uganda`. The *Cloudy* manuscript's household summary covers **27 survey waves**; use the *current analysis roster* to identify the active country-wave files rather than assuming that the older 2024 repository has every current raw file.

**Verified example from the code repository:**

- `ethiopia/household_code/wave_1/2011_geovars.do` loads `$data/household_data/ethiopia/wave_1/raw/Pub_ETH_HouseholdGeovariables_Y1.dta` and merges by `household_id`.
- That historical cleaning script **keeps only an agroecological-zone variable** (`aez`) from the geovariables file, so the coordinates may **not** survive in the refined or regression datasets. Recover them from **raw geovariables** rather than assuming they are already present in the final panel.
- Existing panel-building code (`analysis/reg_code/panel_build.do`) harmonizes country-specific IDs into `hhid`; the observation-level panel historically resides at `$data/regression_data/lsms_panel.dta`. Verify the latest file used for Figures 4–6.

### Required first deliverable: Geovariables inventory

Create `geo_inventory.csv`, one record per country-wave, with:

`country | wave | raw_geofile | coordinate_variable_names | EA_id_variable | household_join_key | coordinates_available | distinct_EAs | households_matched | share_matched | remarks`.

**Discovery procedure:** Recursively search each country's active wave raw folder for filenames containing `geo`, `geovariab`, `gps`, or equivalent national survey terms; inspect variable names and labels for latitude, longitude, EA/cluster, and household IDs. Inspect the wave's cleaning script to determine the original key. Do **not** assume uniform naming across countries or waves; do **not** infer that a file with `geovariables` in its name necessarily contains usable latitude and longitude without inspecting it. Log unavailable files and variable mappings.

## 4. Build and verify a georeferenced panel

1. Start from the exact **observation-level panel** that generated the current `reg2` (year + household FE) and `reg7` (year FE) regressions. Do **not** start from the 1,008-row `rainfall_FE_bootstrap_differences.dta` aggregate file; it contains no observation-level residuals.
2. Extract from each raw geovariables file the **released modified EA latitude/longitude**, raw join identifiers, EA identifier, country, and wave. Retain those variables in a separate geospatial crosswalk instead of altering the original cleaning pipeline.
3. Merge geovariables to the appropriate **country-wave household raw or intermediate data**, verify `1:1` / `m:1` key cardinality as appropriate, and then carry the crosswalk into the harmonized panel using the same identifiers as the original survey cleaning scripts. **Never merge on year alone.** If necessary, capture the household ID crosswalk *before* the existing country append scripts drop original EA or household identifiers.
4. Define `ea_wave_id` as a unique country × survey-wave × EA key; keep original IDs in separate columns. Do not treat numeric EA codes as globally unique across countries or waves.
5. Check whether the same household appears under multiple EA identifiers or coordinates across waves. Preserve its **wave-specific observed EA location** for each observation, while preserving its single `hhid` for household-cluster inference. Do not manufacture a permanent EA ID across waves where no documented cross-wave EA linkage exists.
6. Validate latitude range `[-90,90]`, longitude range `[-180,180]`, country membership, unique EA–wave coordinates, coordinate duplicates expected from multiple households in an EA, survey-year alignment, and nonmissing GPS coverage in the **actual regression sample**.
7. Export a coverage table by country, wave, and outcome showing the number and share of regression observations and households successfully georeferenced. Report whether restricting to georeferenced observations changes the sample or the original first-stage coefficients.
8. If georeferencing loses observations, recompute **both** household-clustered and spatial standard errors **on the same georeferenced sample**. Never compare standard errors from different samples.

Deliverables: `geovariables_crosswalk.dta`, `lsms_panel_geo.dta` (or an equivalent read-only derived file), and `geo_merge_audit.csv`.

## 5. Estimate first-stage regression scores

Use the actual *Cloudy* first-stage equation for each country, rainfall metric, remote sensing product, and outcome. Start with the household-FE model:

$$Y_{ht}=\alpha_h+\gamma_t+\beta Z_{ht}+u_{ht}.$$

For each fitted specification, use the **Frisch–Waugh–Lovell residual of rainfall**, $\widetilde Z_{ht}$, after absorbing household and year fixed effects, and the **full regression residual**, $\widehat u_{ht}$. The scalar contribution to the score for the rainfall coefficient is

$$q_{ht}=\widetilde Z_{ht}\,\widehat u_{ht}.$$

Calculate one score per observation, retaining `country`, `hhid`, `year`, `ea_wave_id`, modified latitude/longitude, `metric`, `product`, `outcome`, and an unambiguous specification identifier.

**Why scores, not rainfall correlations?** The covariance of these score contributions enters the sampling variance of $\widehat\beta$. Correlated rainfall levels alone do not establish that household-clustered standard errors are inappropriate.

For the figure's correlogram, prespecify a limited set of economically interpretable metrics, such as **seasonal total rainfall and rainy days**, estimated for all six products and both outcomes. Do not choose the metrics after examining which exhibit looks strongest. For the inference comparison, extend to the complete **1,008** country × metric × product × outcome specifications.

## 6. Spatial dependence diagnostic

Within each country and the **same rainfall/survey year**:

1. Aggregate the observation-level score to the EA-year level, $A_{et}=\sum_{h\in(e,t)}q_{ht}$. Retain the number of households contributing to each EA-year score.
2. Calculate great-circle (Haversine) distances between **different EAs** using their released coordinates. Do not pair observations from different countries. Restrict pairwise distance computations to candidate neighbors within 200 km using a spatial neighbor index rather than building a dense all-EA distance matrix.
3. For a descriptive correlogram, normalize EA-year scores within specification and year, accounting for different EA sample sizes (e.g., first divide by $\sqrt{n_{et}}$, then standardize across EAs). Plot the average product of standardized scores for EA pairs within distance bands **0–25, 25–50, 50–100, 100–200 km**, with 200–300 km as a reference where feasible. Document whether the plot reports correlations or standardized cross-products; use the same definition everywhere.
4. Collapse over the **prespecified** rainfall specifications using equal weights for each specification. If showing a median correlogram across products/outcomes, label it explicitly as a *median of specification-specific diagnostics*, not as a pooled estimate based on independent observations.
5. Distinguish within-EA cross-household dependence (all households at the same EA coordinate) from **across-EA** distance dependence. Within-EA covariance matters for standard errors but should not crowd the inter-EA distance plot.

**Caution for interpretation:** Year fixed effects impose finite-sample restrictions on residuals. A negative long-distance reference value can arise mechanically and should not be interpreted as evidence of negative meteorological dependence without checking the score construction. The correlogram establishes new descriptive evidence; formal inference comes from the covariance estimator below.

## 7. Spatially adjusted standard errors

**Baseline:** Reproduce the original household-clustered standard error on precisely the same georeferenced observations, retaining unrestricted serial correlation within households. The spatial adjustment should add **contemporaneous covariance across different households**, avoiding double-counting the own-household terms already covered by household clustering.

For a single rainfall regressor after partialling out fixed effects, define

$$G_h=\sum_t q_{ht},\qquad \Omega_{HH}=\sum_h G_h^2,$$

and the EA-year sum $A_{et}$ above. Under an initial working assumption that the additional between-household spatial dependence is **contemporaneous**, compute

$$\Omega_{SP}(b)=\sum_t\left[\sum_{e,e'}K\!\left(\frac{d_{ee'}}{b}\right) A_{et}A_{e't}
-\sum_{h\in t}q_{ht}^2\right],$$

where $K(x)=\max(1-x,0)$ is the triangular spatial kernel, $d_{ee'}$ is kilometers between the released EA coordinates for year $t$, and $b$ is the spatial bandwidth. The subtraction removes the contemporaneous own-household terms counted in $\Omega_{HH}$. Pairs of different households in the **same EA** contribute through $d_{ee}=0$; pairs in different EAs contribute according to distance. Calculate the resulting scalar sandwich variance as

$$\widehat{\mathrm{Var}}(\widehat\beta;b)=
\frac{\Omega_{HH}+\Omega_{SP}(b)}{\left(\sum_{ht}\widetilde Z_{ht}^{\,2}\right)^2},$$

with clearly documented finite-sample corrections. **Benchmark the household component against Stata's original household-clustered variance** on the same sample before adding spatial terms. Use a vetted panel-spatial-HAC implementation or independently cross-check a custom Mata implementation; the formulas describe the intended covariance components, not a substitute for implementation validation.

**Primary bandwidth:** 100 km. **Prespecified alternatives:** 50 km and 200 km. Do not choose the bandwidth based on which one makes instruments weakest. Compute distances using an appropriate geodesic or projected-kilometer procedure; do not use Euclidean distance on raw longitude/latitude degrees.

**Additional check:** Examine whether *between-household, cross-year* dependence appears material. If it does, extend the covariance estimator to temporal lags (e.g., one survey interval or a calendar-year kernel) **without double-counting the unrestricted own-household covariance**. Do not claim the contemporaneous-only adjustment is fully spatial-temporal robust in that case.

For each specification save `beta`, `se_hh`, `se_sp50`, `se_sp100`, `se_sp200`, signed and absolute t-statistics, within-sample N, unique households, unique EA-years, survey years, and any calculation warnings. Spatial standard errors may increase **or decrease**. Do not discard decreases, force nonnegative estimates to an arbitrary floor, or silently replace numerical failures with missing.

## 8. Exhibit and companion outputs

**Proposed exhibit title:** *Spatial Dependence and First-Stage Precision*.

**Panel A: Spatial dependence in first-stage scores.** Plot distance on the horizontal axis and mean/median standardized first-stage score cross-products on the vertical axis. Use six small country panels or a single aligned six-country figure, depending on readability. Show the reference at zero; identify the prespecified metrics and whether lines summarize products and outcomes. The purpose is to show **how far the relevant residual dependence extends**, not simply how far rainfall correlations extend.

**Panel B: Consequence for instrument relevance.** For each country, show a **paired horizontal dot plot** with two values: the share of its 168 matched specifications satisfying $|t|>1.96$ using household clustering, and the share using 100-km spatially adjusted inference. Connect each pair with a thin line. Use consistent ordering and a 0–100\% horizontal axis. If useful, produce a separate appendix version for $|t|>4.81$. Distinguish this pairwise change from statistical significance of the **difference in shares**, which is not independently estimated here.

Optional appendix figure: country × product heat map of the median ratio `se_sp100/se_hh`; this is a useful breakdown but **not a substitute for Panels A and B**, which provide the new evidence and its consequences.

Match the existing paper's visual conventions: no main title embedded in the exported PDF, six-country layout where appropriate, no decorative badges, restrained palette, simple solid gridlines, and PDF plus PNG at print resolution. A figure caption should identify the modified EA coordinates and explain that spatial covariance is calculated from regression scores.

## 9. Implementation sequence and acceptance tests

### Stage A: Geographic merge (required before econometrics)

- [ ] Inventory geovariables for all active 27 country-waves, with raw paths and identified coordinate/key variables.
- [ ] Document which cleaning scripts drop EA identifiers or latitude/longitude and recover those fields **before** they are discarded.
- [ ] Check merge cardinality, country and wave assignments, plausible EA coordinates, and matched coverage in each *current* first-stage sample.
- [ ] Do not impose a simulated GPS displacement correction or require confidential coordinates.

### Stage B: Pilot spatial diagnostics

- [ ] Fit a predeclared subset: total rainfall and rainy days × six products × two outcomes × six countries.
- [ ] Verify that beta and **household-clustered SE** agree with Stata's existing model on the exact common sample.
- [ ] Validate score residualization with Frisch–Waugh–Lovell orthogonality checks; numerically check score sums and regressor residualization.
- [ ] Check EA-year score sums against underlying observation-level scores and neighbor-pair counts.
- [ ] Inspect the score correlogram before selecting how many panels to show; retain all prespecified results regardless of pattern.
- [ ] Validate a hand-calculated small synthetic sample (known coordinates and scores) against the custom/spatial-HAC estimator, including within-EA cross-household pairs and repeat-household observations.

### Stage C: Full inference exercise

- [ ] Process all **1,008** country–metric–product–outcome specifications with **year + household FE**, reusing the original estimation sample where GPS coverage permits.
- [ ] Precompute and reuse 50/100/200-km spatial neighbor lists by country and survey-year to avoid a dense $N^2$ loop inside 1,008 regressions.
- [ ] Verify that coefficients do **not change** across household and spatial variance estimators when the sample and fixed effects are the same.
- [ ] Reproduce Figure 4's country-level exceedance shares on the common georeferenced sample **before** switching the standard error estimator.
- [ ] Confirm there is no double-counting of within-household covariance when spatial cross-household terms are added.
- [ ] Inspect exceptions: undefined t-statistics, degenerate rainfall variables, negative variance estimates, very few EA groups, or large GPS coverage losses. Log rather than silently exclude.
- [ ] Produce the main figure and a CSV of headline country shares. Append bandwidth and year-FE-only results rather than mixing them into the main exhibit.

## 10. Consequences for the existing bootstrap evidence

The existing Figure 6 uses 1,000 **household-cluster bootstrap** replications for coefficient differences when household FE are added. If the new exhibit finds material **cross-household spatial dependence in the relevant scores**, household-only bootstrap intervals may also be too narrow. This is not an automatic conclusion about the sign or significance of the Figure 6 coefficients, but it does imply that the bootstrap **must be re-evaluated before interpreting its significance rates as spatially robust**.

**Follow-up only if warranted:** Design a geographic-block bootstrap or other spatially valid method that preserves household panel histories and cross-household dependence. First implement it on a **predeclared subset of cells** from Figure 6 and compare with the original household bootstrap; do not launch another 1,008 × 1,000-replication run without demonstrating a meaningful inferential difference.

## 11. Proposed files and handoff

| Output | Suggested path under project roots |
|---|---|
| Coordinate inventory and extraction | `$code/analysis/reg_code/exhibit3_geo_inventory.do` |
| Crosswalk construction and merge | `$code/analysis/reg_code/exhibit3_geo_merge.do` |
| Score and covariance estimation | `$code/analysis/reg_code/exhibit3_spatial_inference.do` (Mata helper permitted) |
| Plotting | `$code/analysis/viz_code/exhibit3_spatial_inference_viz.do` |
| Inventory | `$data/results_data/additional_evidence/exhibit3/geo_inventory.csv` |
| Georeferenced crosswalk | `$data/results_data/additional_evidence/exhibit3/geovariables_crosswalk.dta` |
| Merge audit | `$data/results_data/additional_evidence/exhibit3/geo_merge_audit.csv` |
| First-stage score diagnostics | `$data/results_data/additional_evidence/exhibit3/score_correlogram.dta` |
| All first-stage inference records | `$data/results_data/additional_evidence/exhibit3/spatial_first_stage.dta` |
| Figures | `$data/results_data/figures/exhibit3_spatial_dependence.pdf` and `.png` |
| Log files | `$data/results_data/additional_evidence/exhibit3/logs/` |

Do not overwrite the published analysis datasets or Figure 6 bootstrap outputs. Save data provenance, package versions, estimation syntax, bandwidths, and country-wave coverage in an accompanying README.

## 12. Decision rule for the manuscript

**Include as additional evidence of weak first stages** if: (i) first-stage regression scores exhibit substantively meaningful positive spatial dependence across EAs and (ii) accounting for it materially reduces first-stage precision or the share crossing the paper's reference thresholds. If spatial score dependence is negligible, spatial uncertainty is not systematically larger, or GPS coverage changes the estimation sample substantially, the exercise belongs as a documented diagnostic rather than a new central claim.

**Primary sources:** Michler et al. (2022), *Journal of Development Economics* 158:102927; current *Cloudy* manuscript, Figures 4–6 and D.1; GitHub `projectdo.do`, `analysis/reg_code/panel_build.do`, and `ethiopia/household_code/wave_1/2011_geovars.do`. Source-derived claims and procedures above are distinguished from the **proposed new** spatial-HAC and diagnostic methods.
