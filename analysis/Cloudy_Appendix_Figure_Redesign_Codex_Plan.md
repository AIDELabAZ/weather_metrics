# Cloudy: Codex implementation plan for redesigned appendix figures

**Code baseline:** `AIDELabAZ/weather_metrics`, branch `metric-exhibits`, commit `567c3c1f437aa9ca2788a1ce37e2c22352fd10d1` (2 November 2026).  
**Deliverable:** Three publication-ready appendix figures, PDF and PNG, plus the minimal numeric audits and reproducible plotting code described below.  
**Reference visuals:** The three **conceptual mockups** supplied in the conversation. Reproduce their compact layout and visual hierarchy, **not their invented numerical values, smooth shapes, or apparent confidence intervals**. Use the actual saved estimates and empirical dispersion.

## 0. Nonnegotiable scope

- **All new exhibits are appendix-only.** Do not change the main-text figures, captions, narrative, or figure numbering.
- **Leave the existing bootstrap coefficient-change heat map (`boot_heat.pdf`) entirely alone.** Do not modify it, rerun its bootstrap, recalculate its confidence intervals, or execute `metric_boot.do`, `metric_block.do`, or unrelated figure-generation scripts.
- Do not recreate the discarded clustered-t selection frontiers or candidate-choice heat maps.
- Prefer rebuilding **graphics from existing saved numeric results**, not rerunning the validated selection and spatial estimation pipelines.
- Match the manuscript's existing visual style. Inspect `analysis/viz_code/metric_style.do`, `metric_palette.do`, and the relevant plotting sections of `metric_coeff_vis.do` and `metric_sum_vis.do` **read-only**. Use `scheme(stcolor)`, white graph and plot regions, dark gray axes (`38 43 47`), thin **solid** pale gray gridlines (`242 244 246`), modest headers, and consistent text sizing. Do not use colorful backgrounds, borders around every panel, heavy gridlines, or oversized legends.
- Color and markers must have a **stable meaning within a figure**. Avoid reusing the same blue-circle/orange-diamond pairing to denote different concepts in adjacent figures. Legends must explicitly define the visual encoding.

## 1. Figure 1: redesign `front_panel` as 12 compact country-by-outcome frontiers

### Research question

As researchers search among more rainfall metrics/products, do the gains in **training** first-stage association generalize to **held-out** observations, and does this differ between year FE and year-plus-household FE?

### Exact layout

Use a **3-row × 4-column** matrix of 12 small multiples, **one country–outcome pair per cell**:

| Row | Column 1 | Column 2 | Column 3 | Column 4 |
|---|---|---|---|---|
| 1 | Ethiopia: production value | Ethiopia: maize | Malawi: production value | Malawi: maize |
| 2 | Niger: production value | Niger: maize | Nigeria: production value | Nigeria: maize |
| 3 | Tanzania: production value | Tanzania: maize | Uganda: production value | Uganda: maize |

Each cell contains **four** observed lines, with **no fitted smoothing or interpolated observations**:

| FE model | Training | Held-out |
|---|---|---|
| Year FE (`reg7`) | blue **solid** | blue **dashed** |
| Year + household FE (`reg2`) | copper **solid** | copper **dashed** |

Use line type to encode training versus held-out, and color to encode FE specification. Across the matrix, a single compact four-item legend suffices. Do not color by product: each curve summarizes selection across 84 instrument candidates.

### Dispersion ribbons: restore them, but label them correctly

The existing `selection_frontier.dta` provides medians and **10th–90th percentile dispersion across held-out geographic folds** (after first summarizing candidate orderings within each fold). Plot **faint ribbons** around training and held-out series, prioritizing held-out ribbons if all four are visually too dense. Use the saved `lo_train`, `hi_train`, `lo_valid`, and `hi_valid` fields where applicable.

These are **descriptive percentile bands, not 95% confidence intervals**. Do not relabel them as 95% CIs or fabricate inferential uncertainty. Do not substitute artificially narrow ribbons to imitate the mockup. If genuine inferential CIs are later needed, they require a separately specified resampling procedure; do not invent them in this redesign.

### Axes: use the ACTUAL empirical magnitude

**Important correction:** The earlier written plan mistakenly specified a 0.15–0.95 y-axis and the mockups showed correlations approaching 0.9. **Those values are synthetic mockup numbers, not the estimates in the attached figures.** The actual frontier figures mostly lie between approximately 0 and 0.30, with some sign-oriented held-out values below zero.

- **Y range:** begin with **−0.05 to 0.35** shared across all 12 cells; major ticks at **0.00, 0.10, 0.20, 0.30**. Recalculate the global min/max across all four lines **and their percentile ribbons** before finalizing. Only expand the range if real data require it. Do not impose a 0-to-1 scale. Draw a thin gray zero line.
- **K values:** the code estimates **K = 1, 2, 3, 5, 10, 20, 40, 60, 84**, not K = 12, 24, 36, etc. Retain these exact nine plotted values.
- **X scale:** use **log(K)** so the early selection gains remain visible; label ticks **1, 3, 10, 40, 84** (or at most all nine labels if legible). Show x-axis tick labels primarily on the bottom row. Never interpolate additional K values.
- **Axis labels:** one shared left-side y title, `Selected first-stage partial correlation`; one shared bottom x title, `Number of candidate instruments, K`. Use `Year FE` / `Year + household FE` in the legend, not in repeated cell headings.
- **Country/outcome headings:** short strip labels, e.g. `Ethiopia · Value`, `Ethiopia · Maize`; no long subtitles inside cells.

### Dimensions, margins, and typographic targets

- **Full graphic canvas: 11.5 in wide × 8.0 in high**, suitable for a landscape appendix page. A slightly taller version (up to 8.25 in) is acceptable if needed for the legend.
- **No large external margins:** approximately **0.35 in left**, **0.15–0.25 in right/top**, **0.50–0.65 in bottom** for the single legend/x label; allow additional left space only for the shared y title.
- **Inter-panel gutters:** target approximately **0.12–0.18 in horizontally** and **0.18–0.25 in vertically**, not blank bands comparable to a full panel height.
- Each plotting rectangle should retain approximately **2.5–2.65 in of width** and **1.95–2.15 in of height**, after headers/ticks. Check actual output dimensions; a nominal 11.5-in canvas is insufficient if the plot regions occupy only half of it.
- Small-multiple country headings approximately **8–9 pt at final PDF print size**; axis ticks approximately **7–8 pt**; shared axis titles and legend approximately **8–9 pt**. Use the paper's actual typography as the reference.
- Export both a **vector PDF** and a PNG preview at **at least 3200 px wide**. Inspect the PDF at the **actual LaTeX inclusion size**, not only at 200% zoom.

### Checks

1. Check all 12 cells against the original four frontier files for values at K = 1, 10, 84 and for sign orientation of held-out associations.
2. Check exact series mappings: `reg7` = year FE; `reg2` = year + household FE; `lntf_yld` = production value; `lncp_yld` = maize yield.
3. Confirm the ribbons have the documented 10th–90th percentile meaning and that none is cropped by the chosen y-axis range.
4. Confirm training–holdout differences are visibly resolvable in the household-FE cells, especially Ethiopia/Niger/Nigeria/Uganda maize, **without falsifying the y scale or smoothing the data**.

**Outputs:** `front_panel_fit.pdf`, `front_panel_fit.png`.

## 2. Figure 2: replace `front_increment` with a compact, interpretable paired-difference plot

### What the statistic means (must appear in the figure note)

For FE specification `s`, define the sign-oriented training–validation gap at candidate-set size K as

\[
G_s(K)=|r_{\mathrm{train},s}(K)|-\operatorname{sign}(r_{\mathrm{train},s}(K))\,r_{\mathrm{heldout},s}(K).
\]

Define the incremental search gap for that FE model as `ΔG_s = G_s(84) − G_s(1)`. The plotted quantity is

\[
D=\Delta G_{\mathrm{year+HH\ FE}}-\Delta G_{\mathrm{year\ FE}}.
\]

- **D > 0:** searching from 1 to 84 instruments increases the training–validation gap **more with household FE** than with year FE.
- **D < 0:** the extra search gap is **smaller with household FE**.
- The plotted D is a **difference of search-induced gaps**, not a first-stage coefficient, not the total training–validation gap, and not an IV estimate.

Compute the difference **within the same allocation, held-out fold, and candidate ordering**, then summarize. Verify that FE versions use the same candidate permutation as documented. Do **not** calculate D by subtracting independently aggregated marginal percentiles.

### Exact visual layout

- Use two vertically stacked, **compact** forest-plot panels, **top production value**, **bottom maize yield**.
- Each panel has six country rows, in the standard order: Ethiopia, Malawi, Niger, Nigeria, Tanzania, Uganda.
- Each row has **one dark charcoal circular marker** for the median D and **one horizontal descriptive 10th–90th percentile interval** across the paired geographic-split distribution. Avoid implying that these are 95% confidence intervals. Use the same color/shape for all 12 observations; the sign is already conveyed by location relative to zero.
- Thin vertical zero reference line. Add the meaning `HH FE increases search gap` to the positive side, `HH FE reduces search gap` to the negative side, preferably in a **short caption/note** rather than allocating substantial plot area to annotations.
- One x-axis label: `Extra search-induced training–validation gap with household FE`.
- No legend is required: there is a single series. Do not color observations red/green as if the percentile bands were hypothesis tests.

### Axes and size

- **Observed median D range** in the supplied `front_increment.pdf` is approximately **−0.022 to +0.086**, not −0.15 to +0.25 as in the synthetic mockup.
- **Initial x range:** **−0.04 to +0.11**, major ticks **−0.04, −0.02, 0.00, 0.02, 0.04, 0.06, 0.08, 0.10**. **However, calculate the empirical percentile intervals first and expand these bounds to contain all intervals with a small margin. Never crop an interval to meet the suggested range.** If intervals are so wide that the plot is unreadable, retain the full data and report that limitation rather than censoring results.
- Canvas **7.25 in × 4.6–5.0 in** (portrait-page width, not a landscape sheet). Narrow panel gap, approximately **0.15–0.22 in**.
- Each panel should use nearly the full available width; short country labels on the left. Target **9 pt** country labels, **8–9 pt** ticks, and no unnecessary blank header strip.

### Checks

1. Verify D's sign using direct calculations for at least one country/outcome with a clearly positive D (e.g. Niger maize) and one negative D (e.g. Nigeria maize in the attached median summary).
2. Report sample sizes/number of accepted folds and candidate orderings, and whether the 10th–90th percentile range is calculated across **paired folds** after within-fold aggregation.
3. Caption the intervals **descriptive across-split dispersion**; do not call them confidence intervals or mark statistical significance from whether an interval crosses zero.
4. Check that the compact figure is legible as a standard-width portrait appendix figure.

**Outputs:** `front_increment_forest.pdf`, `front_increment_forest.png`.

## 3. Figure 3: redesign `space_panel` as a dense two-part figure

Retain two top-level panels: **(A) first-stage score dependence by distance** and **(B) first-stage significance under household versus spatial SEs**. Do not add the old `|t| > 4.81` dot figure as a third panel; keep its findings in appendix text/table.

### Panel A: score cross-products by EA distance

**Critical measurement point:** The existing `space_score.pdf` compares **seasonal total rainfall (v05)** and **rainy days (v08)**, taking a median over products/outcomes. It **does not** contain separate series for farm production value and maize yield. Do **not** relabel the two metric series as the two outcomes just to match the schematic mockup. Creating outcome-specific diagnostics is optional only if explicitly computed from the saved score results and clearly labeled.

- Keep a **2-row × 3-column** grid of countries in paper order (Ethiopia, Malawi, Niger / Nigeria, Tanzania, Uganda).
- Show **seasonal rainfall** as a dark teal solid line with circle markers, and **rainy days** as a muted plum dashed line with diamond markers. One two-item legend directly underneath the country grid.
- The original data have **five distance bins**: `0–25`, `25–50`, `50–100`, `100–200`, `200–300 km`. Use **equally spaced categorical positions** for these five bins so the three short-distance bins are not compressed by the wide 100–300-km tail. State the bins accurately on the x-axis; this is a bin-category display, **not** a continuously scaled kilometre axis. Do not replace five actual bin values with invented smooth 0–100-km curves.
- Caption the measure exactly as **`Mean standardized first-stage score cross-product`**, not `correlation` or an unqualified `covariance`. Keep the zero reference line.
- The original Nigeria short-distance score is approximately **0.26** (seasonal rainfall). The previous proposed common y range `−0.01 to 0.20` would **crop a real observation**. Do not use it.
- **Preferred y scaling:** modest **country-specific y ranges**, each expanded approximately 10–15% beyond its observed min/max (including zero) and rounded to readable ticks, to reveal meaningful differences in Ethiopia/Malawi/Uganda without flattening them because of Nigeria. Explicitly note `Vertical scales differ across countries`. Alternatively, if a common y-axis is necessary, use approximately **−0.05 to +0.30**, but only if print-size inspection shows the smaller-country patterns remain legible. Do not sacrifice the smaller patterns merely to preserve a common axis.
- Do **not** fabricate confidence bands around these diagnostic means. Add descriptive bands only if an actual, well-defined uncertainty calculation is implemented, documented, and visually useful; otherwise retain clear points and lines.

### Panel B: outcome-specific first-stage significance, compact dumbbells

- Divide Panel B into **two closely stacked outcome-specific strips**, `Farm production value` and `Maize yield`, with **six country rows** in each.
- Within each country/outcome draw one **gray filled circle** for the household-clustered percentage and one **dark red square** for the 100-km spatial-SE percentage. Connect with a light gray horizontal segment. These marker/color meanings are constant throughout Panel B and are **not** used in Panel A.
- Compute each outcome-specific share from `spatial_first_stage.dta` using **matched regressions** with valid `t_hh` and `t_sp100`; each country/outcome should have up to **84 candidate specifications** (14 metrics × 6 products). Recheck exact denominators; report differences instead of treating invalid results as nonsignificant.
- Threshold: **`|t| > 1.96`**, household and year FE (`reg2`) only. Do not pool outcomes for this redesigned Panel B.
- **Observed pooled-country percentages** in the old figure span approximately **13% to 60%**, but outcome-specific percentages can differ. Compute the maximum and minimum first. Start with x-axis **0–70%** or **0–80%** if required, ticks every **10 or 20 percentage points**, and **expand if any actual outcome-specific value exceeds the range**. Do not start at 15%, which could hide low values; also do not default to 0–100% if the data fit tightly below 70–80%.
- Use one shared x-axis title `Share of first-stage specifications with |t| > 1.96 (%)`; one small legend for the two SE types, below Panel B or along the bottom of the combined figure.
- If the outcome-specific decomposition shows additional meaningful heterogeneity, retain it; do not revert to pooled 12 dots merely because that is simpler to code.

### Overall spatial layout and sizing

- Use **11.5 in × 8.25–8.5 in** landscape canvas to support six Panel-A plots plus 12 country rows in Panel B without tiny labels.
- Allocate approximately **53–57% of the usable height to Panel A** and **43–47% to Panel B**, after headers/legends. Panel A's 2 × 3 country cells should each occupy roughly **3.35–3.55 in wide × 1.55–1.80 in high**. Panel B's two strips should have country rows separated by at least **0.20–0.24 in**.
- Avoid the prior split that used too much empty horizontal space in Panel B or excessive vertical buffers between Panel A and Panel B. Keep a **0.12–0.20 in main-panel gap** and compact legends.
- Use separate local legends, not one ambiguous four-item legend combining rainfall-metric categories and SE-type categories.
- Export vector PDF and high-resolution PNG, and verify the stacked Panel-B labels at actual LaTeX size.

### Checks

1. Panel A uses **first-stage score cross-products**, not raw rainfall autocorrelation. Verify values against `score_summary.csv` or `score_correlogram.dta` at all five bins; do not turn a five-bin diagnostic into a smooth curve.
2. Panel B reproduces the original pooled `space_share.pdf` country-level shares **when the two outcomes are recombined with the correct weights and matched denominators**. Do not expect the separate outcome lines to equal the pooled figure.
3. Check that household and spatial percentages share exactly the same estimable regression set within each country/outcome.
4. Report 50-, 100-, and 200-km sensitivity and the `|t| > 4.81` shares in an **appendix audit table or note**, not extra overlarge figures. These already-computed supporting statistics are out of scope for any changes to `boot_heat.pdf`.

**Outputs:** `space_panel_revised.pdf`, `space_panel_revised.png`.

## 4. Shared execution and QA requirements

### Code and sources

Prefer a new appendix-only graph script, e.g. `analysis/viz_code/metric_appendix_redesign.do`, with helper routines for panel assembly if necessary. Reading old figure code for style guidance is fine; **do not run scripts that regenerate existing published figures**.

Use saved results, including:

- `results_data/additional_evidence/exhibit2/selection_frontier.dta`
- `results_data/additional_evidence/exhibit2/selected_instruments.dta`
- `results_data/additional_evidence/exhibit2/front_increment.csv` (for checking against the plotted medians)
- `results_data/additional_evidence/exhibit3/spatial_first_stage.dta`
- `results_data/additional_evidence/exhibit3/score_summary.csv` and `spatial_shares.csv`

Create only the necessary additional **paired incremental-difference summary** and **outcome-specific spatial share** numeric outputs, with explicit denominators and the values used for every plotted point/band.

### Graph assembly and LaTeX

- Compose real vector graphics from Stata/PDF outputs; do not enlarge low-resolution screenshots.
- Use the existing manuscript's appendix orientation environment; **Figure 1 and Figure 3 are landscape**, Figure 2 fits a standard portrait page width.
- The graph files should have **no redundant overall figure caption**, as LaTeX supplies the caption and figure number. Panel headings are fine.
- Do not crop observed lines or percentile intervals merely to satisfy an initial axis recommendation. Derive final bounds from actual values, round them to clean ticks, and leave only modest padding.
- Do not call descriptive fold-percentile ribbons or whiskers `95% confidence intervals`; use `10th–90th percentile across geographically grouped folds` where appropriate.
- Verify that colors, line patterns, and symbols remain distinguishable in grayscale.

### Acceptance criteria

1. **No synthetic mockup numbers appear in final graphs.** Numerical summaries match saved real-data outputs, subject only to explicit, documented reaggregation.
2. **No data are cropped.** Every plotted central value and band endpoint lies inside the axes with small padding; all ranges are checked programmatically.
3. **Panels fill their available canvas.** At final manuscript size there are no oversized gutters, empty regions, or legends consuming entire rows; plot regions remain readable.
4. Figure 1 restores empirical **10th–90th percentile ribbons**, retains the actual nine K values, and makes the training–holdout gap visible.
5. Figure 2 displays the properly paired difference-of-increments and descriptive dispersion, clearly defines zero, and fits a portrait-page width.
6. Figure 3 uses the correct rainfall-metric labels in Panel A, shows the five actual distance bins, and separates outcomes in Panel B with matched denominators.
7. All figures look visually consistent with the existing manuscript figures and have PDF/PNG outputs, short appendix-only LaTeX captions/notes, and a single QA log listing exact numeric ranges, figure sizes, and verified samples.
8. **No changes or recalculations anywhere in the `boot_heat.pdf` workflow or existing main-text exhibits.**

## 5. Final deliverables

- `front_panel_fit.pdf` and `.png`
- `front_increment_forest.pdf` and `.png`
- `space_panel_revised.pdf` and `.png`
- `appendix_figures_redesign_QA.md` documenting axes, sizes, source datasets, dispersion definitions, matched counts, and spot-checked values
- An appendix-only `.tex` handoff containing three `\includegraphics` blocks with accurate notes, no main-text edits

**Priority:** accurate empirical values and interpretable uncertainty first; dense, readable layout second; visual consistency third. This is a **visualization revision**, not authorization to change the underlying results or bootstrap heat map.
