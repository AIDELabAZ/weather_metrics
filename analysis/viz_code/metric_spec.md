# Codex plan: update metric specification charts

## Task and scope

Update the existing specification charts in `analysis/viz_code/metric_coeff_vis.do` to use the paper's established product palette and a taller layout suitable for an 11 x 8.5 inch landscape US-letter page. The attached `tza_all2.png` is the representative chart. **First update and inspect `tza_all2`; then apply the approved changes consistently to the other five `*_all2` country charts.** Do not rewrite other parts of this ~8,800-line do-file or unrelated graph families. Follow the repository's `AGENTS.md` and Stata house style.

Do not modify regressions, results, sort order, sample restrictions, coefficients, confidence intervals, significance criteria, or the three stacked specification-identifier variables. Preserve existing output basenames and paths. Titles, subtitles, and figure notes belong in LaTeX, not inside the exported graph.

## Critical correctness fix: remote sensing product identifiers

**Authoritative mapping confirmed by the researcher.** Throughout this project, the rainfall-product codes are:

| Numeric `sat` | Product | Color RGB from `metric_palette.do` |
| --- | --- | --- |
| 1 | ARC2 | `82 116 170` |
| 2 | CHIRPS | `29 132 147` |
| 3 | CPC | `111 143 82` |
| 4 | ERA5 | `194 123 65` |
| 5 | MERRA-2 | `136 102 163` |
| 6 | TAMSAT | `182 94 109` |

The attached `metric_coeff_vis.do` currently overrides the `sat` labels and gives incorrect names for IDs 1-5. It also labels the product indicator rows incorrectly. Correct both. **Treat the researcher-confirmed mapping in the table above as authoritative;** validate that `sat`, the `weather_var` suffix (`rf1` through `rf6`), and value labels in `lsms_complete_results.dta` agree. If data or code contradict the mapping, stop and report the conflict rather than silently changing the product identities or plotted values. The canonical product order is alphabetical and should govern legends.

The product indicator coordinate is currently `k2 = sat + 4`, so its y-axis labels should read:

- y=5 ARC2; y=6 CHIRPS; y=7 CPC; y=8 ERA5; y=9 MERRA-2; y=10 TAMSAT.

**Across the entire visualization pipeline, do not assume that a locally generated numeric product code uses the canonical mapping.** Some figures recode products internally. In particular, `analysis/viz_code/metric_sum.do` currently constructs a local `sat` numbering and labels `1 = CHIRPS`, `2 = CPC`, `3 = MERRA-2`, `4 = ARC2`, `5 = ERA5`, `6 = TAMSAT` for its descriptive-statistics plots. This disagrees with the researcher-confirmed canonical mapping. Determine which underlying source files actually correspond to each product, then recode the local `sat` variable and update series selectors and labels together. **Never merely rename legend labels:** that could cause the CHIRPS label/color to be attached to ARC2 values or vice versa.

## Project-wide audit of product assignment in figures

**Expand verification beyond `metric_coeff_vis.do`.** Review every visualization do-file in `analysis/viz_code` that assigns or displays rainfall-product labels, including at least `metric_sum.do`, `metric_coeff_vis.do`, `metric_diag.do`, other `metric_*.do` files (such as bootstrap, coefficient, p-value, and strength variants), and any other figure script using the same six rainfall products. Search for `label define`, `label values`, `legend()`, `sat`, `product`, `rf1`-`rf6`, product-name strings, and conditional `if sat == ...` series selections. Include output-producing helper files, not just final plotting commands.

For **every figure using these rainfall products**:

1. Trace the product's identity to the input variable/filename and the code that constructs its numeric ID. Validate the full chain: source -> product ID -> plotted subset -> legend/axis label -> palette color. Use the canonical table above for all final product IDs, and the same named colors from `metric_palette.do`.
2. If a figure internally uses a noncanonical 1-6 coding, **recode the numeric variable to canonical IDs and update every dependent `if` condition, legend key, and label accordingly**. Preserve which observations belong to each physical source product, the statistics themselves, and their year/country alignment.
3. For Figures 2 and 3 (`all_v01`, `all_v12`) specifically, check `metric_sum.do` and verify that the observed trajectories and legend names/colors remain attached to the correct products after any recoding. The current 1=CHIRPS local labelling is **not** the canonical numbering and requires investigation, not a blind string substitution.
4. Check regression-based figures (`metric_coeff_vis.do`, `metric_diag.do`, etc.) against the actual `sat` and `weather_var` values in `lsms_complete_results.dta`. For scripts that read a different dataset or use different product conventions, document the conversion explicitly.
5. Audit scripts for the privacy and mismeasurement papers as well if they display the same named products. Do not rewrite unrelated analysis or silently change their historical datasets: apply necessary label corrections only when the data provenance confirms the same six product identities; otherwise record the discrepancy for review.
6. Produce a compact **product-mapping audit** in the implementation summary (source file, original numeric mapping, confirmed product identity, final legend/labels, checks performed). Report any unverified series rather than asserting that all mappings are correct.

This audit is a correctness requirement, not permission for a wholesale graph redesign. Keep unrelated appearance and substantive analyses unchanged.

## Product colors and other marks

1. Reuse `analysis/viz_code/metric_palette.do` via `include`; do not maintain a second independent product palette. Its product colors should match Figures 2 and 3 and the coefficient-precision figure. If the local palette is newer, inspect the authoritative local file and use those RGB values consistently.
2. The current `twoway scatter k1 k2 k3 obs` draws all product indicators in one color. Split the `k2` product-indicator layer into six conditional scatter layers, one for each `sat` ID, and color them with their corresponding product color. Keep their positions and marker sizes unchanged.
3. Use restrained neutral gray/slate tones for the `k1` dependent-variable indicators and `k3` rainfall-metric indicators. The six named accent colors should identify products, not unrelated categories.
4. Preserve the significant vs. nonsignificant distinction in the upper coefficient-and-CI plot. Use two contrasting neutral tones (e.g., dark charcoal for significant estimates and medium gray for nonsignificant estimates), rather than an ARC2- or CHIRPS-colored marker that might misleadingly imply a product identity. Match CI bar colors to the corresponding estimate group; preserve their existing widths and transparency levels.
5. Use the existing dark slate reference-line color from `metric_diag.do` if replacing the current maroon zero/reference lines. Keep the meaning, locations, and widths of reference lines unchanged.
6. Preserve marker sizes, data-series line widths, and opacity/transparency settings. **Do not enlarge markers, thicken CI bars, or increase opacity.**
7. The significance legend must still show `n.s.` and `p < 0.05`, and point to the correct layers after splitting the product series. Recalculate `legend(order(...))` indices: the original `order(4 5)` will no longer be valid. Do not introduce a redundant six-product legend: the six product rows already provide labeled product identities.
8. Use a white background and the paper's faint solid gray gridlines. Do not retain a bright default Stata palette.

## Layout: taller landscape specification chart

The present graphs use `xsize(10) ysize(4)` and the uploaded EPS has a 720 x 288 pt bounding box (a 10:4 aspect ratio). Change the `*_all2` charts to approximately **`xsize(11) ysize(8.5)`** (an 11 x 8.5 inch landscape ratio). This is an aspect-ratio redesign, not merely a higher-resolution export.

- Keep the main coefficient plot above the three descriptor bands: rainfall metric, remote sensing product, and dependent variable. Preserve the existing x sorting, variable values, and 0-168 specification positions.
- Use the added vertical space to make the left y-axis row labels readable. Increase `ylabel()` label text size from `vsmall` to an appropriate print-readable size, targeting at least approximately 8-9 pt when the figure is placed on a landscape letter page. Adjust left-side graph margins as necessary for the long labels (e.g., `Deviation in Percent Rainy Days`), while preserving the right-hand coefficient axis.
- Retain all 14 rainfall metric labels, all six product names, both outcome names, and the three bold section labels. Do not abbreviate or omit labels merely to fit them.
- Retain the legend and both axes. Remove the placeholder `title(" ")` if it wastes vertical space. Do not add a figure title, subtitle, or note.
- Keep x-axis ticks legible and do not allow label overlap. Avoid distorting the 95% intervals, coefficient scaling, or indicator coordinates.
- Retain `.eps` vector export and existing filenames. Upgrade `.png` export to at least 3000 pixels wide for usable print previews. An additional `.pdf` export with the same basename is acceptable if it works reliably in Stata.

## Small directly relevant code checks

- The current source contains `replace b_ns = . if p <= .05`. Verify whether `p` exists; if this is the evident typo, use `pval <= .05` without otherwise altering statistical definitions.
- The source uses `legend(order(4 5))`; recompute indices after adding conditional scatter plots.
- The chart includes a red vertical `xline(...)` whose position varies by country. Preserve these original positions during this style update, unless you find a genuine bug; report any uncertainty about their meaning rather than moving them.

## Verification and deliverables

1. Show a before/after `tza_all2` PNG. Check at *actual 11 x 8.5 inch landscape print size*, not just at zoomed screen resolution. All y-axis labels must be fully visible and not touch each other; no clipping, collision, or unreadably small text. The upper confidence interval markers and the right-side coefficient scale must remain intact.
2. Confirm with a small tabulation that `sat` IDs and `weather_var` suffixes agree in the regression input; verify and document the source-to-ID mapping for descriptive figures, including `all_v01` and `all_v12`. Check the source-product identity behind every modified label and provide the product-mapping audit described above.
3. Confirm the number of plotted observations, row placements, sort order, coefficients, confidence intervals, and significance statuses are unchanged. Only aesthetics and corrected **labels** should change.
4. After the Tanzania pilot passes, apply the same style to the other five country-specific `*_all2` charts. Check each exported EPS/PNG (and PDF if made).
5. **Audit Figures 2 and 3 for correct product-to-ID mapping**; fix mapping/legend/series-selector discrepancies if found, but do not otherwise restyle those figures. Do not modify the regression generator or source data. Extend the product-identity audit to every relevant visualization script as described above.
6. Commit the focused changes on a feature branch. In your report, name the affected files, show before/after output, list checks actually run, and identify anything that could not be tested.
