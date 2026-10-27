# Codex implementation plan: common product colors and paired FE coefficient differences

**Paper:** *Cloudy With A Chance of Significance*  
**Repository:** `AIDELabAZ/weather_metrics`  
**Purpose:** (1) replace outcome colors with remote-sensing-product colors in the existing coefficient-precision figure; (2) apply that same product-to-color mapping to manuscript Figures 2 and 3; (3) implement a new, separate Stata analysis to estimate and plot household-cluster-bootstrap confidence intervals for paired coefficient differences.  
**Status:** Implementation instructions. Do not treat this document as executed or validated Stata code.

## 0. Ground rules and source inventory

1. Read the repository's `AGENTS.md` and inspect the *current local working tree*, including uncommitted files, before editing. Prefer the most recent local code over an older GitHub snapshot. The earlier visualization implementation may be local and not yet committed.
2. Read `analysis/reg_code/regressions.do` (the user's latest `regressions(2).do`), the existing FE diagnostic figure do-file (previously planned as `analysis/viz_code/cloudy_rainfall_fe_diagnostics.do`), `analysis/viz_code/metric_sum.do`, and `analysis/viz_code/metric_coeff_vis.do` as the reference for the manuscript's specification-chart grammar.
3. Reference the **real-data**, not historical prototype, figures: `rainfall_FE_coefficient_precision.pdf` and `rainfall_FE_strength_distribution.pdf`. Do not substitute the earlier prototype estimates.
4. Stay within `analysis/viz_code/` for new analysis and style files. Do not modify `regressions.do`, the cleaned panel, data-directory setup, unrelated country-wave code, or the manuscript. Avoid unrelated formatting changes. Use the existing `$code` and `$data` globals, not absolute Windows paths.
5. **Nonnegotiable publication-figure rule:** No embedded main titles, subtitles, figure numbers, explanatory annotations, captions, bottom notes, or space reserved for them. LaTeX supplies all of these. Panel country names, axis labels, tick labels, relevant reference lines, and a shared legend are allowed. Suggest LaTeX text separately; do not edit `.tex` files.
6. All output charts should be vector PDFs plus high-resolution PNG previews. Keep the canonical figure filenames, and provide visual previews for review. Do not commit confidential LSMS/weather data or generated `.dta` files.

## 1. One stable six-product palette

Define a small reusable style/helper file, for example `analysis/viz_code/cloudy_product_palette.do`, with six named product colors and modest neutral styling. Stata RGB triples are supplied below; hex codes are for design review. **Colors belong to product names, not arbitrarily to numeric `sat` codes.** Keep the existing overall look: white background, dark-gray text, subtle gray gridlines, minimal borders, no shaded panels.

| Remote-sensing product | Suggested hex | RGB | Visual role |
|---|---|---|---|
| ARC2 | `#5274AA` | `82 116 170` | muted slate blue |
| CHIRPS | `#1D8493` | `29 132 147` | teal (prototype anchor) |
| CPC RF | `#6F8F52` | `111 143 82` | muted olive green |
| ERA5 RF | `#C27B41` | `194 123 65` | copper (prototype anchor) |
| MERRA-2 RF | `#8866A3` | `136 102 163` | muted violet |
| TAMSAT | `#B65E6D` | `182 94 109` | muted rose |

These are **proposed**, not mandatory, numeric values. Codex should render a six-item sample and adjust only if necessary for white-background contrast and color-vision accessibility. Prefer this muted palette to saturated default Stata colors. Use supplementary line patterns in Figures 2 and 3 so the series are also distinguishable in grayscale. Define colors in exactly one source; do not retype different RGB values in the three graphics.

### Critical product-mapping check

**Verify the actual source-to-ID mapping before assigning a color.** Existing code is inconsistent:

- `analysis/reg_code/regressions.do` labels rainfall suffixes `rf1=ARC2`, `rf2=CHIRPS`, `rf3=CPC RF`, `rf4=ERA5 RF`, `rf5=MERRA-2 RF`, `rf6=TAMSAT`.
- The current `analysis/viz_code/metric_sum.do` labels `rf1_x3=CHIRPS`, `rf2_x3=CPC`, `rf3_x3=MERRA-2`, `rf4_x3=ARC2`, `rf5_x3=ERA5`, `rf6_x3=TAMSAT`.

The two code paths may use different naming conventions. Trace the descriptive-series files (`*_x3_rf*.dta`) back to their actual weather-product sources; do not merely trust an existing `label define` command. Confirm the regression-series product suffixes separately. If an existing legend is incorrect, make a targeted, documented correction supported by provenance; if the mapping cannot be established, **stop rather than create misleading product colors**. No comparison should rely solely on numerical codes having identical meaning across pipelines.

The resulting convention must be: **CHIRPS teal everywhere, ERA5 copper everywhere, etc.** regardless of whether its local identifier is `rf1`, `rf2`, or another numeric code.

## 2. Update the existing coefficient-precision figure

**Existing output:** `rainfall_FE_coefficient_precision.pdf` and `.png`.  
**File to change:** the current FE-diagnostics visualization do-file; locate its actual local filename. Do not write a competing second figure generator.

Keep all the original matching, transformations, countries, axes, reference lines, and points:

- Comparison: `reg2` (year + household FE) against `reg7` (year FE only), both using the same household-year estimation sample.
- Each point: one matched country x outcome x rainfall metric x product specification.
- Horizontal axis: `log2(abs(beta_reg2)/abs(beta_reg7))`.
- Vertical axis: `log2(se_reg2/se_reg7)`.
- Preserve the diagonal `y=x`, horizontal/vertical zero rules, six country panels in a 3 x 2 layout, and existing log-ratio exclusion accounting.
- **Change only the visual grouping**: eliminate the two-series color distinction between maize quantity and farm production value. Both outcomes remain in the plotted sample, with the same marker shape. Color every point by its correctly identified **remote-sensing product** using the six-color palette. No outcome-specific colors or separate outcome legend.
- Add exactly one shared six-product legend, ideally below the country panels without encroaching on the plotting area. Do not add six country-specific legends. The outcome dimension remains available for later subgroup analysis but is not encoded in this version.
- Use moderate point transparency/small markers for overlap; compare the result visually with the real-data two-color figure. Preserve the full data even if the display window excludes extreme values; log any display-only clipping as before.

**Validation:** Identical country-specific plot counts, x/y coordinates, summary statistics, filtering rules, and reference geometry before versus after this change. The only intended content change is the six-product color/legend encoding. Tabulate counts by product to ensure no missing or misclassified series.

## 3. Apply identical product colors to Figures 2 and 3

**Code:** `analysis/viz_code/metric_sum.do`.  
**Figure 2:** `all_v01`, six-country annual **mean daily rainfall** (`mean_season_`).  
**Figure 3:** `all_v12`, six-country annual **share of rainy days** (`percent_raindays_`, in percent).

- Modify only the six country graphs contributing to `all_v01` and the six contributing to `all_v12`, plus the necessary graph-combination and style-helper logic. Do not restyle the other 12 rainfall metrics or refactor the upstream weather processing.
- Replace the existing six series colors with the corresponding **verified product-name colors** from Section 1. Preserve the original years, country coverage, annual aggregation, units, missing observations, line geometry, and percent scaling. Never multiply an already-percent variable by 100 a second time.
- Preserve the six-country small-multiple arrangement and one shared product legend per composite; use supplementary line patterns as needed, not just color. A single reusable palette file should determine the colors in Figures 2 and 3 as well as in the coefficient-precision plot.
- Keep the agreed publication layout: no embedded title, subtitle, bottom note, or explanatory text. Country headings, axis labels, and one legend remain. Retain vector PDF/PNG production and existing canonical output basenames; preserve EPS too if used by the manuscript.
- For `all_v01`, keep interpretable country-specific rainfall scales. For `all_v12`, retain a common 0-100% vertical axis. Do not make changes to these scales as part of the color-only request unless necessary to restore existing agreed rendering.

**Validation:** Verify the actual country-year-product values and line counts are identical to the pre-change versions (apart from any separately documented correction to demonstrably wrong product labels). Ensure that the color named CHIRPS in Figures 2/3 is exactly the color used for CHIRPS points in the precision graph.

## 4. New standalone bootstrap coefficient-difference analysis

**New Stata file:** `analysis/viz_code/cloudy_rainfall_fe_bootstrap.do` (or similarly descriptive name if the file already exists locally; do not overwrite a different implementation).  
**Read-only inputs:**

- `$data/results_data/lsms_complete_results.dta` for **model identifiers, reference coefficients, observation counts, and the paired regression inventory**.
- `$data/regression_data/lsms_panel.dta` for **household-level estimation and resampling**.

**Important:** The aggregate results file does not contain the covariance between the paired estimates and cannot support the requested bootstrap by itself. The bootstrap analysis **must re-estimate** the two first-stage regressions on resampled household panel data. This is intentionally separate from `regressions.do` and does not require changing how the original results file is generated.

### 4.1 Statistical target and pair inventory

For each valid `country x outcome_var x weather_var` pair, calculate the **signed** coefficient change:

`delta = beta_reg2 - beta_reg7`.

- `reg7`: `reg y x i.year` on the original `reg2` sample (year FE only).
- `reg2`: `xtreg y x i.year, fe` on that same sample (year plus household FE).
- Use the same sample membership as the current `regressions.do`: run original `reg2`, capture `e(sample)`, and run `reg7` on exactly those records. Only then bootstrap that fixed comparison sample.
- Restrict to the six countries, two outcomes (`lncp_yld`, `lntf_yld`), 14 rainfall metrics (`v01`-`v14`), and six products (`rf1`-`rf6`). No temperature or extraction-loop expansion.
- Expected maximum: **1,008 pairs** (6 x 2 x 14 x 6). Preserve all initially valid pairs, including coefficients with different signs; do not select on significance. Non-estimable cases need an explicit reason and count.
- Validate uniqueness by country/outcome/full weather variable; use the full name such as `v05_rf1`, not a truncated metric code. Reconcile original `beta_reg7`, `beta_reg2`, `e(N)`, and cluster counts to the saved `lsms_complete_results.dta`; stop or flag unexpected differences before starting long bootstrap runs. Do not silently change samples.

### 4.2 Household-cluster bootstrap (one paired resample)

For each specification:

1. Restrict the panel to its **original common `reg2`/`reg7` estimation sample**. Compute and record original (signed) `beta_reg7`, `beta_reg2`, and `delta`.
2. Resample **household clusters (`hhid`) with replacement**, retaining the entire sequence of observed household-year records together. Both models must be estimated on **the same drawn households in each replication**. Never bootstrap individual panel rows, and never bootstrap the coefficient table.
3. When a household is drawn multiple times, give each resampled copy its **own bootstrap panel identifier**, not the original `hhid`. Stata's `bootstrap, cluster(hhid) idcluster(boot_hhid)` approach is appropriate. The FE estimator must use the **resampled** panel identifier. Follow Stata's official panel bootstrap examples, accounting for the observed-sample invocation and `xtset` state; do not merely copy an untested syntax sketch.
4. Re-estimate both year-FE and household+year-FE models in each draw, compute the **difference within that draw**, and return it as one replication statistic. This captures the covariance between the estimators. **Do not** bootstrap two regressions separately and subtract their confidence intervals or standard errors.
5. Use the nonparametric **percentile 95% CI** as the primary interval: empirical 2.5th and 97.5th percentiles of the valid paired-difference bootstrap distribution. Report the number of attempted and successful replications, and do not silently accept widespread failed draws.
6. The original regressions used `vce(cluster hhid)`. The bootstrap itself provides sampling variability through household-cluster resampling, so computing a separate cluster-robust SE within each draw is not required solely to construct percentile intervals. Verify observed *coefficient* equivalence and bootstrap panel identity in a test case.
7. Make the seed reproducible, preferably deterministic by country/outcome/metric/product so results do not change with the order in which the loop is run.

Stata's official panel bootstrap guidance: <https://www.stata.com/support/faqs/statistics/bootstrap-with-panel-data/>. In particular, verify behavior of `cluster()` and `idcluster()` for repeated household draws.

### 4.3 Coefficient standardization for comparison across rainfall metrics

Rainfall metrics have different units. Save **both** the raw and standardized signed differences; the specification chart should default to the standardized scale.

On the *original fixed common estimation sample*, calculate `SD_x` for the rainfall metric and `SD_y` for the outcome. Define a single positive standardization factor for each pair:

`scale = SD_x / SD_y`.

Then calculate:

`delta_std = delta * scale`,  `CI_std = CI_raw * scale`.

This gives the change in the standardized rainfall coefficient, per one original-sample SD of rainfall and in original-sample SDs of the outcome. **Keep the factor fixed across bootstrap draws** so raw and standardized confidence intervals are directly comparable. Record the SDs and factor alongside the results. Flag zero or missing SDs; do not silently replace them. Do not use the different `SD_x` of each bootstrap resample to re-scale the point estimates in this first implementation.

Important: `delta` is **signed**. Negative `delta` is not synonymous with attenuation when the original coefficient is negative. Do not take absolute values of the difference, even though the earlier coefficient-precision plot used absolute coefficient magnitudes.

### 4.4 Computation and failure handling

A naive full run of 1,008 specifications x 999 resamples x two regression fits is approximately **two million estimations**. Do not start this automatically just because `projectdo.do` is run.

- Provide explicit `pilot` and `full` run modes near the top of the new do-file, with country/outcome/weather subset options and a reproducible `reps` parameter.
- **Pilot:** First verify one valid pair end-to-end (20-50 replicates), including a household drawn twice. Then test a small group with e.g. 99 reps. Confirm identical observations per pair, coefficient reconstruction, storage, and chart formatting.
- **Full:** Make `reps(999)` or another user-selected production setting available. Run the complete inventory only when explicitly selected. Estimate and log total runtime from the pilot; do not silently reduce replications or pick attractive specifications to save time.
- Save/checkpoint completed pair results so interrupted runs can resume without repeating finished work. Provide a clear policy for replacing old checkpoints when code, seed, or replication count changes. Avoid committing generated datasets.
- Handle or log missing coefficients, collinear weather variables, too few independent households, and bootstrap iterations that cannot estimate both models. Require a reasonable success fraction and report failures per pair; no fake zero values for unsuccessful draws.
- Do not add a second-stage IV model or inference procedure to this task.

### 4.5 Saved output: bootstrap results table

Save a compact, analysis-ready Stata dataset such as:

`$data/results_data/rainfall_FE_bootstrap_differences.dta`

One row per attempted pair with:

- `country`, `outcome_var`, `weather_var`, rainfall metric ID, **verified product name/ID**;
- original `beta_reg7`, `beta_reg2`, `delta_raw`, `delta_std`;
- `sd_weather`, `sd_outcome`, `scale`;
- `ci_lo_raw`, `ci_hi_raw`, `ci_lo_std`, `ci_hi_std`, bootstrap SE;
- original `N`, original number of household clusters;
- requested and successful replication counts, seed, run mode, bootstrap CI method, and failure/status information.

Keep the raw replicate distributions in separate optional files only when useful for diagnostics; do not require them to generate the final specification chart. Do not modify `lsms_complete_results.dta` or `lsms_panel.dta`.

### 4.6 New bootstrap coefficient-difference specification charts

Use the manuscript's **existing specification-chart grammar** in `analysis/viz_code/metric_coeff_vis.do`, rather than introducing boxplots:

- **One chart per country** as the first output, containing all valid 14 metrics x six products x two outcomes (up to 168 points per country). Offer an optional country-by-outcome version if the primary country plots are too dense; do not replace the default or silently drop an outcome.
- Horizontal axis: sequential specification rank, sorted by **signed `delta_std`** within the country; vertical axis: standardized coefficient difference, `reg2 - reg7`.
- Point marks for `delta_std` with **vertical 95% percentile-bootstrap confidence intervals**, and a thin horizontal reference at zero. Keep positive and negative estimates visible. If a different orientation is more faithful to the manuscript's current specification charts, justify and document that change rather than changing the plotted statistic.
- Reproduce the existing lower specification-indicator strips (outcome, remote-sensing product, rainfall metric), with legible labels. Use the same product colors as Section 1 for point markers or the product strip, with neutral, low-contrast interval whiskers to avoid clutter. The verified product-color mapping must be identical to Figures 2/3 and the coefficient-precision figure.
- Distinguish intervals that cross zero from those that do not using a subtle marker treatment or a concise Stata summary; avoid declaring a coefficient change significant solely from whether the two **individual** regression CIs overlap.
- Export vector PDF and high-resolution PNG to the established `$data/results_data/figures/metric_paper` (or the existing active Cloudy figure directory). Use descriptive canonical basenames, e.g. `rainfall_FE_bootstrap_coefficient_difference_<country>.pdf` and `.png`.
- No embedded figure title, subtitle, figure number, explanatory bottom note, or manuscript caption. Country headings, axes, legible specification indicators, a legend where necessary, and the zero reference are permitted.

**Separate LaTeX caption suggestion (not embedded):** *Changes in Rainfall Coefficients After Introducing Household Fixed Effects*. The note should define `delta_std`, confirm year FE in both specifications, identify household-cluster percentile bootstrap intervals, and describe the original-sample standardization.

## 5. Validation and acceptance criteria

### Color/figure consistency

- [ ] Exactly six product-name colors defined once and reused across all product-coded plots.
- [ ] CHIRPS has the same teal in Figures 2, 3, the precision figure, and the bootstrap specification charts; the other five products are also consistent.
- [ ] Product-name mapping verified against source-file provenance; any genuine original labeling error documented, not silently propagated.
- [ ] Coefficient-precision x/y coordinates, denominators, zero/diagonal reference lines, and samples unchanged; **both outcomes still represented**, now color-coded by product.
- [ ] Figures 2 and 3 preserve numerical annual product series, years, units, panel order, and 0-100% percent scale in Figure 3; only approved labeling/color styling changed.
- [ ] Every exported figure has **no embedded main title, subtitle, caption, figure number, or bottom note**; legends, axis labels, country panels, and reference lines remain.

### Bootstrap integrity

- [ ] Original year-FE and year+household-FE coefficients reproduce the matched `reg7` and `reg2` point estimates in the saved regression results (within numerical tolerance).
- [ ] Both coefficients in each bootstrap replication come from **the same resampled households**, using new IDs for multiply drawn households in the FE model.
- [ ] Household clustering is preserved; individual household-years are never resampled independently.
- [ ] Raw and standardized **signed** differences and their percentile CIs are saved; no rescaling by bootstrap-sample SDs.
- [ ] All intended country/outcome/product/metric pairs are represented or have documented failure/exclusion reasons. Expected maximum 1,008 pairs; report actual counts.
- [ ] Pilot and production modes, deterministic seeds, failed-replication logs, and restart/checkpoint behavior are tested.
- [ ] Charts reproduce the saved bootstrap results table exactly and retain the original specification-chart indicator rows.
- [ ] No changes to original regression scripts, source .dta files, raw microdata, or manuscript.

## 6. Implementation order and deliverables

1. Audit the current working tree, original/product mappings, and existing plotting scripts. Save baseline PDFs/PNGs for comparison.
2. Add/update one six-product palette helper; update **only** the coefficient-precision coloring/legend and Figures 2/3 styling. Render and visually check these three figures. Make a focused commit.
3. Add standalone bootstrap do-file. Run small synthetic or real-data pilot; validate household resampling and point estimates. Save a pilot results table and country specification-chart preview. Make a separate focused commit.
4. Run the full bootstrap only when explicitly selected. Save the validated complete table and country charts as outputs, not tracked source files.
5. Return changed-file list, verification results, sample counts, bootstrap success/failure counts, run settings, previews, and commit/PR links. Clearly label any steps not executed because the full panel or Stata is unavailable.

### Suggested short Codex instruction

> Read `AGENTS.md` and `Cloudy_Product_Palette_and_Bootstrap_Codex_Plan.md`. First replace dependent-variable coloring in `rainfall_FE_coefficient_precision` with six verified remote-sensing-product colors; apply those same named product colors to `all_v01` (Figure 2) and `all_v12` (Figure 3) without changing the data. Keep all titles, subtitles, and bottom notes out of the figures. Then add a separate Stata do-file in `analysis/viz_code` to household-cluster-bootstrap the **paired, signed** `reg2-reg7` coefficient difference, using identical resampled households in both models, save percentile CIs and standardized differences, and generate country-specific specification charts in the manuscript's existing style. Do a small, verified pilot first; do not launch the full ~1,008-pair bootstrap automatically, and do not modify the existing regression-generation file. Report verification, files, figures, and commits.
