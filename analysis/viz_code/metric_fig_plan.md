# Metrics paper: figure refinements and product-specific strength curves

**Codex task.** Make targeted changes to the existing visualization code for *Cloudy With A Chance of Significance*. This is a figure-generation task, not a regression or data-cleaning task. Work from the **current local repository**, including any uncommitted figure code; consult `AGENTS.md` and follow the repository's Stata style. Use a feature branch and provide a focused diff. Do not edit or commit raw data.

## 1. Identify the active figure code

Locate the code actually generating the four current outputs (search by exported filename, rather than assuming the newest code is on GitHub):

| Figure | Current output basename | Expected source |
|---|---|---|
| Paper Figure 2: mean daily rainfall | `all_v01` | `analysis/viz_code/metric_sum.do` |
| Paper Figure 3: share of rainy days | `all_v12` | `analysis/viz_code/metric_sum.do` |
| Coefficient magnitude versus precision | `coef_precision` | Current FE-figure do-file under `analysis/viz_code/` |
| First-stage strength survival curves | `strength_dist` | Current FE-figure do-file under `analysis/viz_code/` |

**Naming:** Any newly created `.do` file under `analysis/viz_code/` must start with `metric_` and have a brief name. Reuse the existing generator where feasible; do not create competing scripts that generate the same figure. Do not rename existing canonical outputs. Write the additional experimental figure as `strength_product.pdf` and `strength_product.png` in the established metrics-paper figure output directory. Respect existing `$code`, `$data`, and figure-output path globals.

## 2. Visual changes to existing figures

Apply the following to **Figures 2 and 3, `coef_precision`, and `strength_dist`**, keeping their current six-country (three columns by two rows) layouts, all underlying data, and analytical definitions unchanged.

1. **Distinguish ARC2 from CHIRPS more clearly.** Keep the current CHIRPS teal. Darken ARC2 to a distinctly blue/navy hue; a starting point is `#28569A` (Stata RGB `40 86 154`). Preserve the other four product colors, unless a verified mapping correction requires reassigning them. Use the *same six named product colors* everywhere. If a palette/helper already exists, modify it rather than defining colors in multiple places. Do not confuse a product's name with a numerical product ID.
2. **Alphabetize all remote-sensing-product legends in the metrics-paper figures:** `ARC2`, `CHIRPS`, `CPC`, `ERA5`, `MERRA-2`, `TAMSAT`. This includes Figures 2 and 3, the coefficient-precision figure, and the experimental strength figure. Audit other *metrics-paper* figure-generating files for product legends and make their **legend order only** alphabetical where relevant; do not restyle or alter unrelated figures. Do not touch privacy or mismeasurement figures. Use Stata legend ordering rather than changing the underlying series or product-to-color mapping. For the existing two-line strength figure, preserve the meaningful specification order: `Year FE`, then `Year + household FE`.
3. **Gridlines:** make existing gridlines **solid, lighter gray, and less prominent**; preserve their positions and widths. Reference lines (zero axes, `y=x`, and vertical strength thresholds) remain distinguishable with their existing patterns. The request for solid gridlines does **not** apply to those reference lines or data-series patterns.
4. **Panel headings:** reduce the size of country names by approximately 10-15%, retaining bold text, exact country names, and panel order. Country headings are permitted; do not add a main figure title.
5. **Absolutely do not change opacity/transparency or make lines thicker.** Preserve existing scatter-marker size/alpha and **all data-series line widths**. Preserve the existing time-series line-pattern assignments in Figures 2 and 3. Do not change marker sizes, series interpolation, smoothing, or y-axis limits.
6. **No embedded main titles, subtitles, bottom notes, figure numbers, captions, or explanatory text.** These are authored in LaTeX. Retain only country headings, axes/tick labels, legends, and essential reference lines.

### Coefficient-precision horizontal axis

The current x-axis spans about `-9` to `+9` in log2 units. Use a narrower display window of **`-6` to `+6`** initially, with readable ticks (e.g., `-6 -3 0 3 6`). Keep a common x-axis across the six panels and keep the **y-axis unchanged**. Do not winsorize the data, modify stored ratios, or remove outliers from the underlying analysis. If Stata expands the axis to include data automatically, restrict **plotting only** to the desired window. Report, by country and overall, the count of observations hidden by that plotting window, plus invalid/nonfinite log ratios already excluded. Retain the original denominator for any descriptive calculations. If clipping is substantial, report the problem and propose an alternative range instead of silently increasing it.

## 3. Verify product identity before recoloring

A potential product-index inconsistency exists between the regression and descriptive-statistics pipelines. For example, historical regression code labels `rf1` as ARC2 and `rf2` as CHIRPS, while the descriptive-statistics code has labeled `rf1_x3` as CHIRPS and `rf4_x3` as ARC2. **Neither numbering scheme should be assumed correct merely because it is already labeled.**

- Trace product names to the upstream raw/refined weather filenames and merge/rename rules used to construct each figure's input. Determine whether the conventions genuinely differ by pipeline.
- Verify each of six products in both `metric_sum.do` and the coefficient/strength results (`lsms_complete_results.dta`). Produce a short audit table: source file/suffix, verified product name, assigned color, and figure(s) using it.
- Only after verification, assign the product colors and alphabetic legend labels. Correct a demonstrably wrong mapping only with an explicit record of what changed. **If product identity cannot be verified, report the blocker and do not guess.**
- This is a metadata/provenance check: do not rerun upstream regressions or change source data.

## 4. Add an experimental 12-curve strength figure

**Keep the original two-curve `strength_dist` figure.** Create an **additional** version using the same Stata regression-results input and the same six country panels, y-axis (share of specifications above threshold), x-axis (absolute cluster-robust t-statistic), and existing vertical reference thresholds.

- Within **each country**, draw **12 curves**: one `Year FE` curve and one `Year + household FE` curve for **each of the six verified remote-sensing products** (6 products x 2 specifications). This is 12 per panel, not 12 across all six panels.
- The `Year FE` specification is `reg7`; the `Year + household FE` specification is `reg2`. Match on country, outcome, and full weather-variable name. Preserve identical eligibility/paired-sample handling across both specifications, as in the existing strength analysis. Use all eligible rainfall metrics and both outcomes rather than selecting convenient subsets.
- **Encode product by its existing six colors**. Encode specification by **line pattern**, e.g., solid for `Year FE` and dashed for `Year + household FE`. Keep current data-series **line widths unchanged**; do not alter opacity. The new line patterns are necessary to distinguish the two specifications that share a product color.
- Compute each empirical survival curve as the fraction of that country-product-specification's eligible regression estimates satisfying `abs(t) >= threshold`. Use the observed absolute cluster-robust t-statistics; do not smooth, interpolate for effect, substitute p-values, or alter the benchmark thresholds. Keep the same displayed x-range as `strength_dist` for comparability.
- Present a legible legend with **products in alphabetic order** and the meaning of the two line patterns. A compact six-product color key plus two-pattern specification key is preferred if feasible in Stata. Otherwise, use 12 combined legend entries grouped by product in alphabetical order, with `Year FE` before `Year + household FE` within each product. Do not use a legend so large that it obscures panels.
- Export `strength_product.pdf` (vector) and `strength_product.png` (high-resolution preview). Treat this as an **exploratory alternative**, not a replacement for `strength_dist` and not automatically a manuscript figure.

## 5. Verification and delivery

1. Re-render Figures 2 and 3, `coef_precision`, `strength_dist`, and new `strength_product`. Compare old/new plots to verify the only intended changes are colors (ARC2), legend order, gridline pattern/color, country-heading sizes, and the precision x-axis display window.
2. Confirm numerical country-year-product series, country ordering, data-point coordinates, sample eligibility, threshold definitions, and the original strength survival curves **have not changed**. Preserve the distinct Figure 2 country-specific rainfall y scales and Figure 3 common 0-100% y scale.
3. For the 12-curve plot, report eligible observation counts by country x product x specification; confirm the two FE models are drawn from the same paired specification inventory. As a check, the pooled country strength curve should agree with the **count-weighted average** of its six product curves at common thresholds, assuming the same eligible observations.
4. Inspect PDF/PNG at the intended LaTeX reproduction width. Check color contrast, legend readability, solid pale grids, preserved series widths and point opacity, and absence of any embedded main title/subtitle/note.
5. Provide a concise summary of edited/new files, verified mapping table, clipping counts, rendered previews, and checks performed versus not performed. Do not change `regressions.do`, panel-building code, paths, data, or manuscript files. Do not automatically rerun regressions or the bootstrap.

**Important:** The author will write the LaTeX figure titles and notes separately; **do not** put any suggested titles or notes inside the graphics or this implementation task's deliverable figures.
