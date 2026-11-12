# Redesigned appendix figures: executed QA

<!-- edited by: codex; edited on: 2 Nov 2026 -->

The redesign uses existing saved estimates. No estimation model, outcome,
candidate set, sample, bootstrap result, or main-text exhibit changed. The
protected bootstrap heat map and its workflow were not revisited. No estimation
or bootstrap pipeline was executed. The earlier appendix figures remain as
auxiliary files; the revised LaTeX handoff includes the three redesigned figures.

## Reproduction and outputs

With the existing project globals established, run:

```stata
do "$code/analysis/viz_code/metric_app_fit.do"
```

Then assemble the native Stata vector components:

```text
python analysis/viz_code/metric_app_fit.py "<project data directory>"
```

The argument is the directory represented by `$data`. Supply
`--pdftoppm "<Poppler executable>"` if it is not on PATH. The existing Python
dependencies are pypdf and reportlab; no new package was installed. The run used
StataNow 19.5, Python 3.12.14, pypdf 6.10.0, reportlab 4.4.9, and Poppler.

The Stata log is
`$data/results_data/additional_evidence/appendix/metric_app_fit.log`.
It closed successfully on 2 November 2026. Components remain in
that folder's `fit/` subdirectory. Final PDFs and PNGs are in
`$data/results_data/figures/metric_paper/`:

| Figure | Vector PDF Canvas | PNG Preview |
|---|---|---|
| `front_panel_fit` | 11.5 x 8.0 in | 3,200 x 2,227 px |
| `front_increment_forest` | 7.25 x 4.85 in | 3,200 x 2,141 px |
| `space_panel_revised` | 11.5 x 8.5 in | 3,200 x 2,366 px |

All three are single-page vector PDFs with zero raster image objects. Every
plotting component is a native Stata PDF; pypdf places it without rasterizing,
and reportlab supplies physical-size shared labels and legends. The new scripts
generate only these three final figures.

## Frontier values, ribbons and mapping

Source: `additional_evidence/exhibit2/selection_frontier.dta`, primary rule 1.
The 12 cells follow the requested three-row/four-column country-outcome order.
Blue represents year FE (reg7); copper represents year plus household FE (reg2).
Solid lines are absolute training correlations; dashed lines are the same
selected instrument's held-out correlation oriented by its training sign.
Color identifies FE, not rainfall product. There is one four-item legend.

Every curve retains K=1,2,3,5,10,20,40,60,84 on a log axis. The original
`lo_train`, `hi_train`, `lo_valid`, and `hi_valid` values supply all four faint
ribbons, with held-out ribbons emphasized. No point was interpolated and no
curve was smoothed. The empirical endpoints are -0.1022962651 and 0.3657222370;
the common y range expands to **-0.12 to 0.38**, with ticks at -0.10, 0.00,
0.10, 0.20, 0.30. Thus no ribbon or median is cropped.

`front_fit_values.csv` contains 216 source rows, the exact medians/band
endpoints, attempted/valid/invalid counts, cell assignments, and axis limits.
An independent calculation from `selected_instruments.dta` reproduced all
216 medians and 864 band endpoints to tolerance 1e-9, including K=1,10,84 in
every cell. It first takes medians over candidate orderings within each
allocation/fold, then medians and empirical 10th/90th percentiles across the
100 allocation/fold summaries. The original four standalone frontier outputs
remain unchanged. FE and outcome mappings are exact: reg7 year FE, reg2
year/household FE, `lntf_yld` value, and `lncp_yld` maize.

Ribbons are descriptive across geographically grouped folds. They are not
confidence intervals. Repeated folds share observations; they are not 100
independent sampling replications. Households and connected EA-wave groups
remain grouped, without a distance buffer. At print size, household-FE
training/held-out differences remain visible, including Ethiopia, Niger,
Nigeria and Uganda maize; the scale was not altered to exaggerate them.

## Paired difference of incremental search gaps

For FE model s, calculate `G_s(K)=abs(r_train)-sign(r_train)*r_valid`, then
`D=[G_reg2(84)-G_reg2(1)]-[G_reg7(84)-G_reg7(1)]`. Calculate this at the same
country, outcome, allocation, fold and ordering before taking any median or
percentile. Positive D means household FE increases the extra search gap;
negative D means it reduces that gap. D is neither a coefficient nor an IV
estimate, nor the total gap at K=84.

The saved selection code resets the seed to
`20261031+10000*country+100*allocation+held_out_fold` before generating each
model's candidate permutations. FE and outcome do not enter that seed. The
new calculation also verifies identical K=1 candidates for every valid pair;
the earlier deterministic permutation validation remains applicable.

`front_forest_values.csv` contains the 12 plotted rows, full paired medians
and endpoints, valid raw pairs, attempted orderings and accepted fold counts:

| Country | Outcome | Median D | P10 | P90 | Valid Raw Pairs | Valid Folds |
|---|---|---:|---:|---:|---:|---:|
| Ethiopia | Value | -0.000312 | -0.099367 | 0.138287 | 2,000 | 100 |
| Ethiopia | Maize | 0.043508 | -0.053517 | 0.176643 | 2,000 | 100 |
| Malawi | Value | -0.008314 | -0.099851 | 0.106727 | 2,000 | 100 |
| Malawi | Maize | 0.000576 | -0.080176 | 0.078040 | 2,000 | 100 |
| Niger | Value | 0.005036 | -0.195792 | 0.146056 | 1,993 | 100 |
| Niger | Maize | 0.086862 | -0.042400 | 0.201845 | 1,992 | 100 |
| Nigeria | Value | -0.003415 | -0.066519 | 0.052516 | 2,000 | 100 |
| Nigeria | Maize | -0.022033 | -0.131152 | 0.086725 | 2,000 | 100 |
| Tanzania | Value | 0.010485 | -0.094825 | 0.111083 | 2,000 | 100 |
| Tanzania | Maize | 0.010293 | -0.064698 | 0.084933 | 2,000 | 100 |
| Uganda | Value | 0.028438 | -0.036326 | 0.088287 | 2,000 | 100 |
| Uganda | Maize | 0.034363 | -0.046410 | 0.108774 | 2,000 | 100 |

All 12 cells attempt 2,000 paired orderings: 20 allocations x five folds x
20 orderings. Undefined raw comparisons remain missing. Within-fold medians
precede across-fold median/p10/p90 calculations; marginal FE percentiles are
never subtracted. The raw paired calculation reproduces the earlier verified
`front_increment_comparison` summary and an independent raw-pair calculation
to tolerance 1e-9. Direct signs are positive for Niger maize (+0.0868624755)
and negative for Nigeria maize (-0.0220333231).

The legacy `exhibit2/front_increment.csv` uses a single median across all raw
orderings, rather than first aggregating within folds. A direct comparison
therefore initially differed by up to 0.0092364013 for the 24 model-specific
increment medians. Reproducing its documented pooled-ordering definition
matches all 24 legacy values to maximum error 4.858e-17. This resolves the
comparison: the new figure deliberately follows the plan's fold-first
aggregation. The legacy CSV remains unchanged. In particular, D cannot be
obtained by subtracting those marginal legacy medians or percentiles.

The full interval endpoints span -0.195792 to 0.201845 (rounded); the x axis
therefore expands to **-0.22 to 0.22**, with 0.05 tick spacing. No interval is
cropped. Every interval crosses zero; the plot deliberately assigns no
significance colors or hypothesis-test labels. There are two compact outcome
panels, one charcoal circular marker per country, and no legend.

## Spatial score diagnostics and matched shares

Panel A reads contemporaneous `score_summary.dta` values, retaining the existing
median across six products and two outcomes for each metric. The two series
remain seasonal rainfall v05 and rainy days v08; they were not relabeled as
outcomes. Dark teal solid circles and muted plum dashed diamonds identify the
metrics. The five bins use equally spaced categorical positions: 0-25, 25-50,
50-100, 100-200, 200-300 km. There are five observed points per curve, no smooth
curve, and no fabricated uncertainty bands. The axis title is "Mean Standardized
First-Stage Score Cross-Product"; vertical scales differ across countries.

Bounds include zero and 13% empirical-span padding, rounded outward to small
fractions of a readable tick interval:

| Country | Y Minimum | Y Maximum | Tick Spacing |
|---|---:|---:|---:|
| Ethiopia | -0.020 | 0.064 | 0.020 |
| Malawi | -0.008 | 0.013 | 0.005 |
| Niger | -0.040 | 0.110 | 0.050 |
| Nigeria | -0.060 | 0.300 | 0.100 |
| Tanzania | -0.030 | 0.120 | 0.050 |
| Uganda | -0.016 | 0.072 | 0.020 |

The largest score, Nigeria seasonal rainfall 0.258245, remains inside its axis.
All 60 plotted bin means reproduce the saved source to tolerance 1e-10.
`space_fit_values.csv` records all means, source pair/specification counts,
and country-specific scales. The measure is not a rainfall autocorrelation,
Pearson correlation, or unqualified covariance.

Panel B reads `spatial_first_stage.dta`, reg2 only, requiring valid household
and 100-km t-statistics on the same regression. Gray filled circles identify
household clustering; dark red squares identify spatial SEs. Country order is
unchanged within each of two outcome strips. Each country/outcome has **84
attempted and 84 matched specifications, zero invalid**, using strict |t|>1.96:

| Country | Value HH (%) | Value Spatial (%) | Maize HH (%) | Maize Spatial (%) |
|---|---:|---:|---:|---:|
| Ethiopia | 52.381 | 17.857 | 46.429 | 13.095 |
| Malawi | 36.905 | 22.619 | 63.095 | 45.238 |
| Niger | 45.238 | 16.667 | 32.143 | 16.667 |
| Nigeria | 39.286 | 13.095 | 22.619 | 11.905 |
| Tanzania | 17.857 | 10.714 | 32.143 | 26.190 |
| Uganda | 82.143 | 55.952 | 38.095 | 28.571 |

The actual minimum/maximum are 10.7142857% and 82.1428571%, requiring a shared
**0-90%** axis with 10-point ticks. All 12 shares reproduce an independent
matched calculation to tolerance 1e-9. Recombining outcomes with their matched
denominators reproduces every saved pooled `spatial_shares` value to tolerance
1e-10, with 168 matched specifications per country. Differences between
outcomes are retained. `space_outcome_values.csv` records all points and counts.

The 50/100/200-km and adjacent-interval sensitivity shares and 4.81 results
remain in the previously verified audit tables; no extra figure is generated.
The LaTeX handoff includes numerical appendix tables for both sensitivities
and 4.81. All primary 100-km shares above 4.81 are zero; the 50-km Uganda
share is 4.167%. Geographic restrictions remain unchanged, including 778
unlocated Tanzania and 1,847 unlocated Uganda panel observations. They must
not be interpreted as covariance-driven exclusions.

## Print-size review and final status

`metric_app.tex` uses landscape pages for the first and third figures and a
portrait figure for the paired forest plot. Labels remain distinct appendix
labels and ordinary captions leave numbering to the manuscript. A letter-paper,
one-inch-margin proof compiled using installed MiKTeX/lscape with no overfull
boxes: three figure pages and one page of supporting tables.

Landscape images are limited to 5.35 inches high as well as 0.97 linewidth so
captions and notes fit the 6.5-inch landscape text height. This prints the
frontier at about 7.69 x 5.35 inches and the spatial figure at 7.24 x 5.35 inches.
The portrait forest prints at about 6.31 x 4.22 inches. Typography is sized for
those actual dimensions: frontier headings about 8.2 pt, ticks 7.4 pt and legend
8.0 pt; spatial headings/country labels about 8.1 pt, ticks 7.2 pt; forest country
labels about 9.1 pt and ticks 8.7 pt. All pages were rendered and visually
reviewed at 100 dpi at that inclusion size.

The frontier plotting rectangles are about 2.58 x 2.06 inches on the native
canvas, with compact gutters. Spatial Panel-A rectangles are about 3.35 x 1.55
inches; Panel-B country rows are 0.20 inch apart on the native canvas. Separate
local legends identify metric and SE encodings. No outcome, FE, or product
meaning is reassigned to imitate conceptual mockup values.

Final numerical and export checks passed. The legacy aggregation discrepancy
was explained and reconciled; no unexpected exclusion occurred. Broad empirical
intervals and sample/geography restrictions are retained and described. No new confidence interval,
significance test, or coefficient-change inference was introduced.
