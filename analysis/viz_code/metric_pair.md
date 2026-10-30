# Codex plan: Paired specification charts in Section 4

## Objective

Create **one landscape specification chart per country**, displaying the two specifications used in the revised *Cloudy* manuscript:

1. **Upper coefficient panel:** rainfall + year fixed effects (`reg7`).
2. **Lower coefficient panel:** rainfall + year and household fixed effects (`reg2`).
3. **Bottom strip:** one shared specification-indicator matrix, identifying the dependent variable, remote sensing product, and rainfall metric for each specification.

All three components must have **identical horizontal positions**. Sort the entire chart by the **signed `reg7` rainfall coefficient, from smallest to largest**. Do not independently sort `reg2`. Produce a separate chart for **each of the six countries**; all six will remain in the paper for now.

This is a layout and visualization task. **Do not rerun or change regressions, recalculate the bootstrap, or modify `lsms_complete_results.dta`.**

## Files, placement, and naming

- Read repository `AGENTS.md`, the **attached updated** `metric_coeff_vis(1).do` (corresponding to `analysis/viz_code/metric_coeff_vis.do`), `analysis/viz_code/metric_boot_vis.do`, `analysis/viz_code/metric_palette.do`, and `analysis/reg_code/regressions.do`.
- **Edit the existing `analysis/viz_code/metric_coeff_vis.do` directly. Do not create `metric_pair_vis.do` or any other new `.do` file.**
- The attached file currently contains `**# 0` setup, `**# 1` significance preparation, `**# 2` reg2 charts, `**# 3` reg7 charts, and `**# 4 - end matter` near its end. **Insert `**# 4 - paired specification charts` immediately before the current end matter and renumber that existing end matter to `**# 5 - end matter`.** Keep the final `log close` and `/* END */` after the new section.
- **Preserve Sections 0-3 unchanged** except for a minimal, necessary correction required to make Section 4 work (document any such correction). Do not delete or replace the existing single-specification charts.
- Within Section 4, reload `$root/lsms_complete_results` in a `preserve`/`restore` block (or otherwise isolate the section) so the new graphs use the correctly matched input regardless of transformations performed by Sections 1-3. Reuse path globals already established in Section 0; do not redefine or hard-code them.
- Input: `$data/results_data/lsms_complete_results.dta`.
- Output directory: `$data/results_data/figures/metric_paper` (`$xfig` in existing code). Save **PDF** (vector, intended for LaTeX) and **PNG** (high-resolution inspection); optionally EPS if required by the paper's existing workflow.
- Short output names: `eth_pair`, `mwi_pair`, `ngr_pair`, `nga_pair`, `tza_pair`, `uga_pair`.
- Follow the repository's Stata formatting and user-specific path globals. No hard-coded machine paths.

## Data selection, matching, and ordering

The current results file records both original and labeled identifiers. **Use the string fields** `spec_id`, `outcome_var`, and `weather_var` rather than the numeric `regname`, `sat`, or `reg_id` for pairing, because `reg_id` is unique to each individual regression.

1. Keep `paired_sample == 1`, `spec_id` in `reg7`/`reg2`, outcomes `lncp_yld` and `lntf_yld`, and rainfall variables matching `^v(0[1-9]|1[0-4])_rf[1-6]$`.
2. Verify uniqueness using `country outcome_var weather_var spec_id`; reshape or merge to one row per matched **country × outcome × full rainfall variable**.
3. Retain both estimated coefficients (`beta`), both 95% confidence-interval bounds (`ci_lo`, `ci_up`), p-values (`pval`), and estimation flags (`estimable`). Require both rows for a plotted pair and both estimates to be valid. Log missing/unmatched/non-estimable pairs by country and outcome; do not silently discard them.
4. Within each country **sort by `beta_reg7` ascending**, with `outcome_var` and `weather_var` as deterministic tie-breakers; assign a single `rank = 1, ..., N_country` to matched specifications. Apply **exactly that rank** to both coefficient panels and all three specification-indicator groups. The lower `reg2` panel should usually look unsorted; that is the point of the comparison.
5. Preserve original signed coefficients and CI endpoints in their original units. Do not standardize, take absolute values, pool different dependent variables, or substitute bootstrap coefficient differences. Keep both outcomes in each country chart.
6. Maximum expected count per country is `14 metrics × 6 products × 2 outcomes = 168 matched pairs`. Report realized N for each country; if less than 168, account explicitly for every missing or non-estimable pair.

**Model identities:** `reg7` = **year FE only**; `reg2` = **year + household FE**. Never use `reg3` (which includes inputs) or the historical `reg1`. Check that these identities hold in the results fields before plotting.

## Chart layout

- Produce **one figure per country** on an approximately **11 × 8.5 inch landscape** canvas. The figure has three vertically stacked, full-width components: upper coefficient plot, lower coefficient plot, and a **single** indicator strip. Start with roughly 30% / 30% / 40% of the usable height; adjust after visually checking the 14 metric labels.
- Panel labels *within the plot area* may read **`Year FE`** and **`Year + household FE`**. Do not include an overall title, subtitle, or explanatory bottom note; these belong in LaTeX.
- Plot coefficient point estimates and their **existing 95% confidence intervals** in **both** coefficient panels. Preserve the established significant/nonsignificant visual distinction and use correct `pval <= 0.05` classification; neither significance nor coefficient sign should be inferred from chart ordering.
- Both coefficient panels must have the **same vertical coefficient scale within each country**, calculated using the valid CI bounds across **both** specifications and including zero. Use the same reference line at zero. Country-specific coefficient ranges are acceptable. Do not clip intervals without reporting them.
- Both coefficient panels and the indicator strip must have an identical x range (e.g. `0.5` to `N_country + 0.5`) and aligned plot regions. Show specification-rank ticks and label once, preferably at the bottom. **Visually verify that a vertical line at any rank passes through the corresponding point and indicator dots in all three components.** `graph combine` is acceptable only if it actually achieves this alignment; adjust margins/axes or use a single graph with coordinated axes if necessary.
- Keep the specification-indicator matrix **once, at the bottom**, not repeated for each coefficient panel. It has two outcome rows, six remote-sensing-product rows, and fourteen rainfall-metric rows, plus clear group headers and adequate inter-group spacing. Keep the existing metric names, including appropriate units/wording. Make left-side labels large enough to read at landscape-letter page size.
- Reuse the white background, restrained gray axes, and faint solid gridlines from the newer *Cloudy* figures. Use panel spacing and typography consistent with Figures 2 and 3. No embedded figure title or footnote.
- Keep existing marker opacity, point sizes, and confidence-interval line widths unless a technical change is required to preserve clarity; do **not** increase sizes or opacity solely for visual redesign.

## Product identities and palette

Load the established palette with `include "$code/analysis/viz_code/metric_palette.do"`. Product identities are **authoritatively**:

| ID / `_rf#` | Product | Palette local |
| --- | --- | --- |
| 1 | ARC2 | `arc2` |
| 2 | CHIRPS | `chirps` |
| 3 | CPC | `cpc` |
| 4 | ERA5 | `era5` |
| 5 | MERRA-2 | `merra2` |
| 6 | TAMSAT | `tamsat` |

Color the six product-indicator **rows** using these product colors. Use neutral colors for outcome and metric indicator rows. The specification coefficients themselves can retain the existing significant/nonsignificant colors so their interpretation is not confused with product colors. Keep any product labels in **alphabetical order**: ARC2, CHIRPS, CPC, ERA5, MERRA-2, TAMSAT. Validate the mapping against the full `weather_var` suffix; never reuse the outdated product-number ordering in portions of `metric_coeff_vis.do`.

## Construction approach (entirely inside Section 4)

1. Build a clean paired dataset and assign the `reg7`-based rank once. Use `tempfile`/`preserve` as needed; do not save or commit regression microdata or results files.
2. Build the two coefficient graphs from this same indexed dataset. Apply the same y-scale, x-scale, coefficient/CI conventions, and shared zero line.
3. Build the product/metric/outcome indicator strip from the same indexed dataset. Include just one set of row labels and group headings.
4. Combine the three components without changing the rank alignment or creating redundant legends. If graphical layering is more reliable than `graph combine`, use that instead. Ensure consistent plotting width; avoid squeezing the 168 ranks into a narrow panel.
5. Export each country figure to PDF/PNG and inspect at **actual 11 × 8.5 inch page scale**. A higher PNG resolution alone is not a substitute for legible labels.
6. Avoid changing existing figure files such as `eth_all2` until the new paired versions are reviewed; create distinct outputs with the `_pair` suffix. New section executes as part of the existing `metric_coeff_vis.do` run, not as a separate invocation.

## Acceptance criteria

- Six country charts generated in both PDF and PNG; main manuscript can include all six.
- All code lives in **new Section 4 of `metric_coeff_vis.do`**, immediately before renumbered Section 5 end matter; there is no additional `.do` file.
- Existing Sections 0-3 continue producing their historical outputs without being replaced or silently changed.
- Each figure has exactly **two coefficient panels (reg7 above reg2)** and **one shared indicator matrix below**.
- Every panel uses **the same ordered specification IDs**, ranked by **signed reg7 coefficient ascending**, with stable tie-breakers.
- For each country, report pair counts, number of omitted specifications and reasons; reconcile the maximum of 168 pairs.
- Test several ranks (first, middle, last, and both outcomes) against source result rows: country, outcome, rainfall metric, product, `reg7` coefficient/CI, `reg2` coefficient/CI, and significance must match.
- Verify product mapping and labels as specified above; inspect colored indicators for at least one example of each product.
- Compare both coefficient panels' y-axis limits and confirm all valid 95% CIs are visible.
- Check no overall titles/subtitles/bottom notes, no repeated indicator strips, no independent `reg2` sorting, and no clipped or overlapping text at letter-landscape size.
- Report what tests were **actually run** (Stata on real data vs static review), plus output paths. Commit only source code, not generated data or figures unless repository practice explicitly requires figures.

## Scope limits

Do not update the first-stage strength curves, the coefficient-precision figure, bootstrap charts, or the regression-generating `.do` file in this task. Keep existing single-specification charts intact for comparison until the paired charts are approved. No LaTeX manuscript edits are needed.

## Ready-to-paste Codex instruction

Read `AGENTS.md`, the current `analysis/viz_code/metric_coeff_vis.do` (the attached `metric_coeff_vis(1).do` is the reference), and this `metric_pair.md`. **Do not create a new Stata file.** Add a new **Section 4** to the existing `metric_coeff_vis.do`, immediately before its existing `**# 4 - end matter`; renumber end matter to Section 5. Preserve Sections 0-3 and existing figures. In Section 4, generate six landscape charts with **reg7 above reg2**, both ranked once by the signed **reg7** coefficient, and one shared specification-indicator matrix. Verify exact pairing, product labels/colors, and horizontal alignment. Run Stata and inspect the PDFs if available; report discrepancies and make only a focused commit to the existing file.
