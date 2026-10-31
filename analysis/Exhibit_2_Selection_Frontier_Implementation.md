# Exhibit 2: The First-Stage Selection Frontier

**Project:** *Cloudy With A Chance of Significance*  
**Purpose:** Quantify how much apparent first-stage relevance a researcher can obtain by selecting among 84 plausible rainfall instruments, and determine how much of that apparent strength survives evaluation on held-out households.  
**Proposed placement:** Main-text results, with disaggregated outcome and selection-rule results in the appendix.  
**Status:** Implementation plan, not empirical results.

## 1. Research question and identifying logic

Within a country and agricultural outcome, the paper provides 14 rainfall metrics constructed from six remote sensing products: **84 candidate instruments**. A researcher who chooses the apparently strongest candidate after looking at the first stage may select a high estimate partly because of sampling variation. The magnitude of this *selection premium* is an empirical question.

**New evidence:** Compare the apparent first-stage relationship of an instrument selected in one sample with its relationship in a geographically separated validation sample. Vary the number of instruments the researcher is allowed to consider from 1 to 84.

**Interpretation:** A growing training–validation gap as the candidate set expands constitutes evidence of selection-induced first-stage optimism. It is *not* evidence that the original authors of the reviewed papers actually searched across 84 candidates, nor does it establish an exclusion-restriction violation. If validation performance rises in tandem with training performance, the larger choice set may instead be locating genuinely better instruments.

## 2. Existing project assets

The repository [AIDELabAZ/weather_and_agriculture](https://github.com/AIDELabAZ/weather_and_agriculture) documents these locations:

| Item | Existing location or reference |
|---|---|
| User-specific code/data roots | `projectdo.do`, globals `$code` and `$data` |
| Combined household/weather panel | `$data/regression_data/lsms_panel.dta` in the historical pipeline; locate the **current** panel used to generate Figures 4–6 before proceeding |
| Panel construction | `$code/analysis/reg_code/panel_build.do` |
| Historical estimation scripts | `$code/analysis/reg_code/regressions.do` and related scripts |
| Existing visualization conventions | `$code/analysis/viz_code/` |
| Existing result data | `$data/results_data/` |

The historical repository contains identifiers `country`, `hhid`, `year`, agricultural outcomes `lntf_yld` and `lncp_yld`, and rainfall variables with prefixes `v01`–`v14` and `rf1`–`rf6`. **Inspect the current data and regression scripts before using these names.** In the current *Cloudy* analysis, the matched specifications being compared are *year FE* (`reg7`) and *year + household FE* (`reg2`); names and conventions in older repository scripts differ.

This exercise requires the **observation-level panel**, not the 1,008-row bootstrap summary file.

## 3. Construct the analysis dataset

1. Load the exact household–weather panel underlying the current first-stage results. Reuse the paper's outcome transformations, growing-season alignment, rainfall variables, and country-specific year definition.
2. Define a canonical key: `(country, household_id, survey_year)`; confirm one record per household and survey year and preserve original identifiers needed for downstream merges.
3. Create an explicit candidate dictionary linking `(rainfall_metric, product)` to one regression variable. Verify **14 × 6 = 84 distinct candidates** per country. Map products to ARC2, CHIRPS, CPC, ERA5, MERRA-2, and TAMSAT. Do not assume that the older `rf1`–`rf6` ordering holds in a newer file without checking.
4. Analyze the two outcomes separately: value of production per hectare and primary-crop yield per hectare. Thus there are **6 × 2 × 84 = 1,008** country–outcome–instrument combinations before splitting.
5. For each country–outcome pair, establish a **fixed common estimation sample across all 84 instruments**. Avoid letting the chosen instrument change the set of households. Report missingness, number of unique households, EAs, and years; distinguish genuine zeros from missing weather data. Do not silently replace missing instrument values with zero.
6. Re-estimate the original *year + household FE* first stages on this common sample and compare coefficients, standard errors, and t-statistics with the published input data. Record any sample-driven discrepancies. Keep the *year FE* model as a secondary comparison, not the main selection frontier.

## 4. Spatially grouped, repeated sample splits

**Unit of assignment:** Geographic EA groups (or spatial blocks formed from EAs), **not household-year observations**. Every observation from a household must stay in one fold. Use the displaced EA coordinates described in Exhibit 3 if available; otherwise start with stable EA identifiers. The object here is independent validation, not a study of coordinate displacement.

**Primary design:** Repeated five-fold, geographically grouped cross-validation.

1. Within each country, assign spatial blocks or stable EAs to five balanced folds, stratifying geographically (e.g., by region or agroecological zone) so each fold includes multiple climatic areas and enough multi-wave households. Keep all observations of a household together even if its EA identifier changes across waves.
2. In each repetition, fit on four folds (approximately 80\% of grouped observations) and evaluate on the omitted fold. Repeat with **20 pre-recorded fold allocations** (100 train/test comparisons per country–outcome pair). Pilot five allocations first; expand only after checking runtime and validation sample sizes.
3. Confirm that household FE are estimable in both partitions, particularly in Niger's two-wave panel. Record effective numbers of households with repeated observations and survey-year coverage in every fold. Rebalance or reject folds failing predeclared minimum requirements; log every rejection.
4. Keep exactly the same train/test assignment across all 84 candidates and both outcomes (subject to the outcome-specific common sample). Generate and save a reusable fold-assignment dataset with fixed random seeds.
5. As a stricter secondary check, apply a geographic buffer between training and validation blocks where sample size permits. Do **not** use a buffer that destroys the remaining within-household panel; report the loss of sample size.

A validation split only at the household level would allow heavily correlated or identical weather shocks to appear in both samples. Geographic grouping is therefore preferable for the paper's question.

## 5. Selection and validation algorithm

Predeclare the nested candidate-set sizes:

`K = 1, 2, 3, 5, 10, 20, 40, 60, 84`.

For each country, outcome, cross-validation split, and random permutation of the 84 candidate instruments:

1. Regress the outcome and each candidate rainfall variable on the **same year and household fixed effects in the training data**, and calculate the within-sample partial correlation

   $$r_{k,S}=\operatorname{corr}(M_S Y,\,M_S Z_k),$$

   where $M_S$ removes the fixed effects **within sample** $S$.
2. Select the candidate with the highest absolute training partial correlation among the first $K$ candidates in the random permutation:

   $$k^*(K)=\operatorname*{arg\,max}_{k\in\mathcal K(K)}|r_{k,\mathrm{train}}|.$$

   This yields a dimensionless selection metric and avoids directly comparing t-statistics from samples of different sizes.
3. Evaluate the *same selected metric–product pair* in the validation sample, estimating its fixed-effects partial correlation separately. Orient its sign according to the training result:

   $$R_{\mathrm{train}}(K)=|r_{k^*,\mathrm{train}}|,\qquad
   R_{\mathrm{valid}}(K)=\operatorname{sign}(r_{k^*,\mathrm{train}})\,r_{k^*,\mathrm{valid}}.$$

   **Do not take the absolute value in validation.** Otherwise, sign reversals would appear as positive strength.
4. Calculate the training–validation gap $G(K)=R_{\mathrm{train}}(K)-R_{\mathrm{valid}}(K)$. The key incremental statistic is $G(84)-G(1)$, because even selection from one prespecified candidate can produce a training–validation gap due to sampling variation or geographic heterogeneity.
5. Repeat across folds and randomized candidate orderings, preserving correlation among the original instruments. Do not simulate 84 independent synthetic variables.
6. Save the selected metric, product, signed coefficients, correlations, cluster-robust t-statistics, split sizes, rank, and fold identifiers for every run.

**Important practical extension:** Repeat the exercise with the more realistic selection rule `max |household-clustered t|` in the training data. This **is not equivalent** to maximizing absolute partial correlation when the variance estimator is cluster robust. Continue to display dimensionless partial correlations in the main graph, and report the share of selected instruments that pass the paper's reference t-statistic thresholds in validation. Do not compare raw training and validation t-statistic levels as if sample sizes were equal.

Efficient implementation: residualize the outcome once per split; residualize the 84 instruments in batches; compute the correlation and selection statistics from cached arrays instead of re-running separate full fixed-effects models for every value of $K$.

## 6. New figure and tables

**Proposed exhibit title:** *The Return to Searching for Rainfall Instruments*.

**Main figure:** Six country panels in a 2 × 3 layout. Horizontal axis: **Number of Candidate Instruments Considered** ($K$; label each prespecified value). Vertical axis: **Selected First-Stage Partial Correlation**, displayed in percentage points or correlation units with the same scale across countries. Two curves:

- **Selected in training**: median $R_{\mathrm{train}}(K)$ across repeated held-out folds.
- **Same instrument in held-out data**: median *signed* $R_{\mathrm{valid}}(K)$.

Use a fixed, easily distinguishable pair of line styles/colors. Show the two outcomes either as an explicitly identified second figure or as pooled summaries with equal weighting across outcomes; do **not** double-count observations by pooling raw records. If the six-country pooled-outcome plot is too cluttered, produce separate value and quantity versions, and select one for the main text. Thin 10th–90th percentile bands across splits are **descriptive dispersion**, not inferential confidence intervals. Use existing project graph style, no titles embedded inside the PDF (LaTeX captions supply titles), simple solid grids, and PDF + PNG exports.

**Companion descriptive table:** For $K=1,10,84$, provide median training correlation, median held-out signed correlation, median gap, share of selected coefficients with reversed signs, and share passing $|t|>1.96$ and $|t|>4.81$ in validation, by country and outcome. Explain denominators and whether thresholds refer to household-clustered t-statistics.

**Appendix:** (a) separate outcome panels, (b) training selection by clustered $|t|$, (c) year-FE-only model, (d) geographic-buffer validation if feasible, and (e) choice-frequency plot for the selected metric–product pairs.

## 7. Quality assurance and acceptance tests

- [ ] Reconstruct the 84 candidate instruments, each with a unique metric–product key, and reproduce baseline counts: 6 countries × 2 outcomes × 84 instruments = 1,008 combinations.
- [ ] Verify the current paper's fixed-effects specification, transformations, sample, and coefficient estimates before the new computations.
- [ ] All 84 candidates use identical observations for a given country, outcome, and split; no silent sample switching.
- [ ] No household is split between training and validation; no wave-specific duplicate household IDs; no EA/block leaks across folds.
- [ ] All training residualizations and validation residualizations are performed **separately**; no fitted fixed effects or demeaning parameters are imported from the training sample into validation.
- [ ] Under primary absolute-partial-correlation selection, training strength is weakly increasing in $K$ **within each split and candidate ordering**. If not, fix the implementation.
- [ ] `K=1` gives a random prespecified candidate (not a retrospectively chosen best instrument); `K=84` considers all 84 candidates.
- [ ] Confirm that sign reversals produce **negative** oriented held-out correlations.
- [ ] Audit holdout sample size, within-household variation, zero-variance regressors, non-estimable fixed effects, and geographic imbalance.
- [ ] Run sensitivity to the alternate cluster-t selection rule; report any change in conclusion.
- [ ] Do not label percentile bands across correlated repetitions as conventional confidence intervals.

## 8. Proposed files and handoff

| Output | Suggested path under project roots |
|---|---|
| Main Stata implementation | `$code/analysis/reg_code/exhibit2_selection_frontier.do` |
| Plotting script | `$code/analysis/viz_code/exhibit2_selection_frontier_viz.do` |
| Fold assignments | `$data/results_data/additional_evidence/exhibit2/folds.dta` |
| All candidate-level estimates | `$data/results_data/additional_evidence/exhibit2/candidate_scores.dta` |
| Selected-pair records | `$data/results_data/additional_evidence/exhibit2/selected_instruments.dta` |
| Collapsed plotting data | `$data/results_data/additional_evidence/exhibit2/selection_frontier.dta` |
| Figure | `$data/results_data/figures/exhibit2_selection_frontier.pdf` and `.png` |
| Reproducibility logs | `$data/results_data/additional_evidence/exhibit2/logs/` |

Implementation must reuse `$code` and `$data` from `projectdo.do`, use deterministic seeds, save a short README recording any variable-name mappings, and **not overwrite existing Figures 4–6 or their underlying results**.

## 9. Decision rule for the manuscript

**Include in the main text** if allowing more candidate rainfall instruments systematically increases apparent training strength without commensurate increases in held-out strength, particularly after household FE. **Qualify the claim** if both increase similarly. **Do not claim selection-induced optimism** from a simple train–test gap at $K=84$ without comparing it with the $K=1$ baseline and documenting the effect of geographically grouped validation.

**Primary sources:** Current *Cloudy* manuscript, Figures 4–6 and D.1–D.2; repository `projectdo.do`, `analysis/reg_code/panel_build.do`, and `analysis/reg_code/regressions.do`. Research motivation: Keane, Neal, and Vu, *Instrument Hacking*, NBER Working Paper 35633 (2026), subject to citation verification before inclusion in the manuscript.
