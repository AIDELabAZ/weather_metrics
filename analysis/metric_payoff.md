# Appendix selection optimism and spacing update

<!-- edited by: codex; edited on: 3 Nov 2026 -->

The current payoff exhibit is `front_payoff_levels`: a direct paired-dot plot
of selection optimism. The earlier arrow/scatter candidates are no longer
generated or included in the handoff. Frontier and spatial content is preserved,
with more room around axis labels, panel headings and legends.

## Reproduction

After the existing project globals have been established:

```stata
do "$code/analysis/viz_code/metric_app_fit.do"
```

Then run:

```text
python analysis/viz_code/metric_app_fit.py "<project data directory>"
```

The argument is the directory represented by `$data`. Supply
`--pdftoppm "<Poppler executable>"` if it is not on PATH. No new dependency is
required. Both scripts now refresh all three current figures in one run.
The Stata log is `additional_evidence/appendix/metric_app_fit.log` under
`$data/results_data`. The appendix-only handoff is `analysis/metric_app.tex`.

## Definition, baseline and descriptive spread

The saved `exhibit2/candidates.dta` contains exactly 84 unique metric/product
pairs: 14 rainfall metrics crossed with six products. The primary frontier
rule selects on absolute training partial correlation. K=1 is the first
candidate in the same random candidate ordering, not the best of 84 or an
average over an independently drawn baseline. K=84 considers the complete set.

For each country, outcome, FE specification, allocation, held-out fold and
candidate ordering, the code computes:

```text
R_train(K) = abs(r_train(K))
R_heldout(K) = sign(r_train(K)) * r_valid(K)
optimism = [R_train(84)-R_train(1)] - [R_heldout(84)-R_heldout(1)]
```

This uses `exhibit2/selected_instruments.dta`, primary rule 1, without changing
the outcome transforms or selection routine. Optimism is calculated before
aggregation. It is not the difference of separately computed median gains,
and it is not the earlier reg2-minus-reg7 contrast of gap increments.

First take the median over 20 orderings within an allocation/fold, then the
median and **IQR (25th-75th percentiles)** across 100 allocation/fold summaries.
Undefined paired gains remain missing. Repeated folds reuse observations;
IQRs are descriptive spread, not confidence intervals or tests of FE differences.

The tidy `appendix/front_payoff_levels.dta` and `.csv` contain all 24
country/outcome/specification rows: `optimism_center`, `optimism_p25`,
`optimism_p75`, paired/attempted counts, valid split counts and axis limits.
Country IDs are 1 Ethiopia, 2 Malawi, 4 Niger, 5 Nigeria, 6 Tanzania, 7 Uganda;
outcomes are 1 farm production value and 2 maize yield. Reg7 is year FE;
reg2 is year plus household FE. All cells have 100 valid split summaries and
2,000 attempted ordering pairs. Valid pairs are 2,000 except Niger:

| Outcome | Year FE | Year + Household FE |
|---|---:|---:|
| Farm Production Value | 1,996 | 1,993 |
| Maize Yield | 1,995 | 1,992 |

## Figure decisions

The optimism plot uses two stacked outcome panels. Both FE centers share the
same country row and a thin gray horizontal connector. Blue filled circles
represent year FE; orange filled squares represent year plus household FE.
Thin IQR bars are offset slightly above/below the row to keep overlapping
intervals readable; their x values are unchanged and short stems link each
bar to its point. A zero reference and two-entry bottom legend complete the plot.

Observed centers range from -0.0098054 to 0.0746358. IQR endpoints range from
-0.0447697 to 0.1311368. The common axis is **-0.06 to 0.15**, with 8% empirical
span padding and outward rounding. Three year-FE centers are negative, and
19 of 24 IQRs contain zero. The requested figure is retained; these broad
spreads limit strong interpretation. No significance colors or inferential
claims are added.

The frontier retains all 12 cells, both FE models, the nine exact K values,
log K, four lines and all four descriptive ribbons per cell. Its -0.12 to
0.38 y range is unchanged. The left margin increases from 44 to 66 points;
plot-row gaps increase from 25 to 31 points. Tick/title and title/legend gaps
increase separately, with additional room above the top strip labels.

The spatial figure retains its two top-level panels, categorical distance
bins, country-specific score scales, both outcomes, 84 matched specifications
per country/outcome, gray circles/red squares, and directional arrows.
The score-grid left margin increases from 46 to 64 points; plot-row gaps
increase from 16 to 30 points. Both local legends have more room below their
axis titles, and the bottom legend has a larger outer margin. The share axis
remains 0-90%, containing the observed maximum 82.143% with modest padding.

## Executed review

- Independently recomputed all 24 optimism medians and 48 IQR endpoints from
  saved raw selected-instrument rows; differences are below 1e-9. Valid paired
  counts and all 100 split summaries match the exported tidy table.
- Verified the 84-candidate grid, K=1/K=84 pairing, six countries, two outcomes,
  FE identifiers and palette, and that every displayed IQR is inside its axis.
- Frontier median/ribbon CSV and both spatial plotting-value CSVs are
  byte-identical before and after the layout revision. No plotted quantity
  or descriptive ribbon was removed or recomputed differently.
- Exported three single-page vector PDFs with no raster image objects,
  plus 3,200-pixel PNG previews. Reviewed the figures at actual inclusion size.
- Compiled the appendix-only LaTeX handoff on letter paper with one-inch
  margins and reviewed its captions, labels, notes and spacing.

| Figure | Native PDF Canvas | Use |
|---|---|---|
| `front_panel_fit` | 11.5 x 8.0 in | Frontier With More Spacing |
| `front_payoff_levels` | 8.5 x 6.0 in | Direct Selection Optimism |
| `space_panel_revised` | 11.5 x 8.5 in | Spatial Comparison With More Spacing |

Outputs remain under `$data/results_data/figures/metric_paper/`. No estimator,
bootstrap, main-text figure, or protected heat-map workflow was run or changed.
