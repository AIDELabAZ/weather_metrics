# Appendix exhibits: executed review

<!-- edited by: codex; edited on: 2 Nov 2026 -->

The appendix plan was executed on 2 November 2026 using the existing selection
and spatial estimates. No estimator logic, original LSMS panel, main-text
figure, caption, numbering, or narrative was changed. The protected bootstrap
heat map, its estimates and workflow were not revisited. No bootstrap program,
removed clustered-t/choice figure, or coordinate-displacement analysis ran.

## Reproduction

After `projectdo.do` has established the existing project globals, run:

```stata
do "$code/analysis/viz_code/metric_app.do"
```

Then assemble the native Stata PDF components, supplying the same project data
directory represented by `$data`:

```text
python analysis/viz_code/metric_app.py "<project data directory>"
```

If Poppler is not on PATH, append `--pdftoppm "<path to pdftoppm executable>"`.
The assembly uses Python 3, pypdf, reportlab, and Poppler. The executed runtime
was StataNow 19.5, Python 3.12.14, pypdf 6.10.0, and reportlab 4.4.9. No new
Stata package is required. No full frontier or spatial re-estimation is needed.

The optional one-time verification is separate from production:

```stata
do "$code/analysis/reg_code/metric_app_check.do"
```

The completed production and verification logs are
`$data/results_data/additional_evidence/appendix/metric_app.log` and
`metric_app_check.log`. The latter closed successfully at 15:17:22; the final
production run closed at 15:25:20. These logs and generated data remain outside
Git. The appendix-only manuscript fragment is `analysis/metric_app.tex`.

## Delivered figures and layout

Files are under `$data/results_data/figures/metric_paper/`:

| Figure | PDF Size | PNG Size | Placement |
|---|---|---|---|
| `front_panel` | 9 x 5.5 in | 3,200 x 1,956 px | Appendix Figure A |
| `space_panel` | 9 x 5 in | 3,200 x 1,778 px | Appendix Figure B |
| `front_increment` | 9 x 4.2 in | 3,200 x 1,493 px | Auxiliary diagnostic only |

Each final PDF is one vector page with zero raster image objects. All three
were visually reviewed at 873 pixels wide, representing a 0.97 x 9-inch
landscape text width at 100 dpi. The matrix has one country label per row,
four correctly assigned outcome/model columns, one bottom legend, log K,
and a common -0.1 to 0.4 vertical range containing every median. All nine K
values remain plotted; five bottom tick labels avoid crowding. Country labels
are 9.5 pt, column headers 9 pt, ticks 8 pt, and legend text 8.5 pt before the
0.97 inclusion scaling. Blue solid and copper dashed lines retain distinct
patterns for monochrome printing. No dispersion band is plotted in the matrix.

The spatial composite uses native Stata components with approximately 60/40
widths, a two-column/three-row score grid, and one legend below each panel.
Its score range is -0.1 to 0.3; the share range is 0 to 70 percent, containing
all values. The scores are standardized cross-products, not correlations.
Both composites use the established white backgrounds, dark gray labels,
thin solid pale grids, blue/copper colors, and thin solid gray zero lines.

All 216 frontier points match the saved primary-rule estimates to tolerance
1e-10, with the correct column mapping (value reg7, value reg2, maize reg7,
maize reg2). All 60 plotted score-bin means and six paired shares reproduce
their saved sources to tolerance 1e-10 and 1e-9, respectively. These are layout
changes, not replacement estimates. The four standalone frontiers with
descriptive bands and `space_share481` were retained unchanged. The optional
component figure was omitted because its table is sufficient. The incremental
optimism plot is informative about country/outcome heterogeneity but remains
auxiliary; the LaTeX fragment includes only the two required figures.

## Selection integrity and incremental optimism

There are 84 unique metric-product candidates, 201,600 candidate records,
864,000 selected-instrument records, and 2,400 accepted partition/model records.
The design retains 20 allocations x five folds x 20 candidate orderings,
nested K=1,2,3,5,10,20,40,60,84, two outcomes, two FE models, and two selection
rules. No folds were rejected. All 20 allocations passed household and
connected-EA-wave leakage checks. These splits are geographically grouped,
not distance-buffered: neighboring distinct EAs may fall on opposite sides.

Every primary-rule training maximum absolute partial correlation is
nondecreasing within its ordering. All plotted medians were independently
reproduced from selected records, including K=1,10,84. A deterministic replay
of Niger farm-value allocation 1/fold 1 reproduced all 720 recorded choices
across the two models and rules; repeating selection returned identical choices.
The original panel's 54,237 keys and both existing outcome columns agree with
the georeferenced copy. No outcome transform was replaced.

For each raw matched ordering, `G(K)` is absolute training partial correlation
minus training-sign-oriented held-out correlation. The increment is
`G(84)-G(1)`. FE contrasts subtract the reg7 increment from the reg2 increment
before aggregation, pairing the same allocation, fold, ordering, selection
rule, and K=1 candidate. First take the median over the 20 orderings within a
fold/allocation; then summarize the 100 fold/allocation values. Folds and
repeated allocations reuse observations; their dispersion is descriptive,
not 100 independent sampling replications or a confidence interval.

Primary-rule median paired FE contrasts:

| Country | Farm Production Value | Maize Yield |
|---|---:|---:|
| Ethiopia | -0.000312 | 0.043508 |
| Malawi | -0.008314 | 0.000576 |
| Niger | 0.005036 | 0.086862 |
| Nigeria | -0.003415 | -0.022033 |
| Tanzania | 0.010485 | 0.010293 |
| Uganda | 0.028438 | 0.034363 |

`front_increment_comparison.csv` contains 48 country/outcome/model/rule rows,
including increment median/p10/p90, baseline/selected gaps, sign, attempted and
valid comparisons, valid splits, and paired FE contrasts. Every primary cell
has 100 valid fold/allocation summaries. Raw valid K1/K84 comparisons are
2,000 per cell except Niger: farm value 1,993 (reg2) and 1,996 (reg7), with
1,993 paired FE comparisons; maize 1,992 and 1,995, with 1,992 paired comparisons.
Undefined held-out estimates remain missing, never zero. Across the complete
saved files, 110 candidate estimates and 510 selected validations are undefined.

The common-sample sequence is outcome availability, complete weather, then
removal of households with only one usable wave. The weather step recovers
pre-replacement missingness without altering genuine zero rainfall or the panel.

| Country | Outcome | Panel N | Outcome N | Weather N | One-Wave Excluded | Common N | Households |
|---|---|---:|---:|---:|---:|---:|---:|
| Ethiopia | Value | 10,674 | 10,674 | 10,664 | 1,469 | 9,195 | 3,859 |
| Ethiopia | Maize | 10,674 | 5,904 | 5,897 | 1,490 | 4,407 | 1,998 |
| Malawi | Value | 8,897 | 8,897 | 8,897 | 1,031 | 7,866 | 2,802 |
| Malawi | Maize | 8,897 | 7,866 | 7,866 | 1,090 | 6,776 | 2,504 |
| Niger | Value | 3,913 | 3,913 | 3,911 | 725 | 3,186 | 1,593 |
| Niger | Maize | 3,913 | 3,492 | 3,492 | 666 | 2,826 | 1,413 |
| Nigeria | Value | 9,145 | 9,145 | 9,145 | 465 | 8,680 | 2,947 |
| Nigeria | Maize | 9,145 | 3,976 | 3,976 | 874 | 3,102 | 1,198 |
| Tanzania | Value | 9,916 | 9,916 | 9,859 | 1,406 | 8,453 | 3,366 |
| Tanzania | Maize | 9,916 | 7,341 | 7,316 | 1,467 | 5,849 | 2,357 |
| Uganda | Value | 11,692 | 11,692 | 11,692 | 873 | 10,819 | 3,130 |
| Uganda | Maize | 11,692 | 6,156 | 6,156 | 1,185 | 4,971 | 1,687 |

The refreshed `front_table.csv`, `sample_audit.csv`, `split_audit.csv`, and
`baseline_comparison.csv` retain the sample and valid-rate denominators.
Incremental optimism describes added selection-related in-sample optimism
beyond K=1; neither the raw gap nor the FE contrast identifies a causal
p-hacking effect.

## Spatial covariance decomposition and sensitivity

All 2,016 existing fits (1,008 per FE model) retain the same coefficients and
observations when changing covariance. The appendix computes:

```text
V_HH = correction * omega_hh / xx^2
V_HH+EA = correction * (omega_hh + omega_within_ea) / xx^2
V_100 = correction * (omega_hh + omega_within_ea + omega_pair100) / xx^2
```

The algebra reproduces saved household SEs and 100-km variances. Four within-EA
and 92 between-EA covariance additions are negative and remain signed. No total
variance is missing or nonpositive at any audited bandwidth or lag sensitivity.
No component is truncated and no variance is floored. All primary country
comparisons have the same 168 estimable specifications (84 per outcome).

Reg2 pooled threshold shares, percent:

| Country | HH >1.96 | HH+EA >1.96 | 100 Km >1.96 | HH >4.81 | 100 Km >4.81 |
|---|---:|---:|---:|---:|---:|
| Ethiopia | 49.405 | 19.048 | 15.476 | 3.571 | 0.000 |
| Malawi | 50.000 | 41.667 | 33.929 | 12.500 | 0.000 |
| Niger | 38.690 | 21.429 | 16.667 | 4.167 | 0.000 |
| Nigeria | 30.952 | 17.857 | 12.500 | 0.595 | 0.000 |
| Tanzania | 25.000 | 20.238 | 18.452 | 0.000 | 0.000 |
| Uganda | 60.119 | 54.762 | 42.262 | 25.595 | 0.000 |

Both within-EA and distinct-neighbor terms matter; their relative contributions
vary by country. The table avoids a redundant third composite panel.

Reg2 pooled spatial shares above 1.96, percent:

| Country | 50 Km | 100 Km | 200 Km | 100 Km + Adjacent Interval |
|---|---:|---:|---:|---:|
| Ethiopia | 18.452 | 15.476 | 16.071 | 12.500 |
| Malawi | 39.286 | 33.929 | 33.929 | 27.976 |
| Niger | 19.643 | 16.667 | 16.667 | 14.881 |
| Nigeria | 14.286 | 12.500 | 12.500 | 12.500 |
| Tanzania | 19.048 | 18.452 | 13.095 | 17.262 |
| Uganda | 51.786 | 42.262 | 34.524 | 38.095 |

Magnitude depends on bandwidth and adjacent-interval covariance. The spatial
share never exceeds its paired household share across all 288 audited
country/outcome-or-pooled/model/bandwidth/threshold groups, although ties occur.
Shares need not be monotone in bandwidth (Ethiopia rises slightly from 100 to
200 km). At 4.81, every primary 100-km share is zero. The 50-km Uganda share is
4.167%; the other 50-km shares and all 200-km/adjacent-interval shares are zero.
These are descriptive frequencies, not tests of differences between shares.

`spatial_variance_components.csv` has 2,016 fits with original weather/model
identifiers, signed additions, SEs, absolute t-statistics, threshold flags,
ratios and sample counts. `spatial_components_summary.csv` has 216 group/step
rows. `spatial_bandwidth_audit.csv` has 288 rows, with both outcomes separately
and pooled, both models, both thresholds, all four spatial variants, attempted
and matched counts, variance flags and mean/median SE ratios.

## Geography and sample composition

The geographic copy covers 51,600 of 54,237 panel observations, excluding 2,637.
Joins are unique at the required household/year or released-location keys.
Missing/confidential coordinates are not imputed. Released modified positions
are the working geography; no displacement simulation is introduced.

| Country | Panel N | Georeferenced N | Excluded |
|---|---:|---:|---:|
| Ethiopia | 10,674 | 10,664 | 10 |
| Malawi | 8,897 | 8,895 | 2 |
| Niger | 3,913 | 3,913 | 0 |
| Nigeria | 9,145 | 9,145 | 0 |
| Tanzania | 9,916 | 9,138 | 778 |
| Uganda | 11,692 | 9,845 | 1,847 |

Tanzania's exclusions are 348 extended-panel 2014 observations, 144 SDD
observations, and 286 in 2020/21. The SDD audit confirms 168/312 located:
120 use 2012 positions and 48 use 2008; 2010 adds none. The linked earlier
household's region/district/ward/EA must match the current SDD administrative
key, after removing the region prefix from SDD district codes. All 168 satisfy
the key restriction, preserve unique panel keys, and use the recorded source
vintage. Household-ID continuity alone is not used to assign movers a location.
Uganda excludes all 1,845 wave-8 observations and two missing 2011 coordinates.
Country-wave coverage remains in `geo_inventory.csv` and `geo_merge_audit.csv`.

The sample audit distinguishes original regression results from household
clustering on the geographic sample, then from covariance changes on that
same sample. For reg2, Tanzania value N changes 9,916 to 9,138 (households
4,804 to 4,637); maize 7,341 to 6,756 (3,837 to 3,688). Uganda value changes
11,692 to 9,845 (4,003 to 3,718); maize 6,156 to 5,214 (2,872 to 2,619).
Median geographic/original HH-SE ratios are 1.062/1.066 for Tanzania
value/maize and 1.155/1.193 for Uganda. Thus original-to-geographic differences
cannot be attributed solely to spatial covariance. `spatial_sample_audit.csv`
has 2,016 matched rows with coefficients, SEs, N, households, t-statistics and
ratios; `spatial_sample_summary.csv` has 24 country/outcome/model summaries.
Coefficient magnitudes across rainfall units are not interpreted as comparable
standardized effects.

## Independent executed checks and failures

The prespecified direct-Stata check ran 24 fits: Ethiopia, Niger and Tanzania;
CHIRPS total rainfall and rainy days; both outcomes; reg2 and reg7. Saved
coefficients, household-clustered SEs and N agree. Maximum relative coefficient
error is 1.619e-14; maximum HH-SE error is 2.137e-13, below 1e-8. Repeating
native fits differs by at most 9.749e-17, below 1e-12. Results are in
`additional_evidence/appendix/direct_stata_audit.csv`.

The plan's hand-checkable covariance example ran independently: 12 observations,
six households, two periods, equatorial locations 0, 0.2 and 1 degree longitude,
and one mover. Explicit ordered observation-pair sums include own-household
serial covariance, same-EA distinct households, neighboring EAs inside 100 km,
outside-cutoff pairs, and the adjacent-interval own-household subtraction.
The direct correction is `(6/5)*(11/9)`, using independently obtained residual
scores and rainfall sums of squares. All raw components and 50/100/200-km/lag
variances agree to relative tolerance 1e-10.

| Toy Metric | HH Meat | Within-EA Addition | Between-EA 100-Km Addition | Lag Addition | V100 | V100+Lag |
|---|---:|---:|---:|---:|---:|---:|
| v05 | 42.483310 | -2.626646 | -9.403383 | -6.015014 | 0.097378 | 0.078144 |
| v08 | 85.121350 | -5.422748 | -28.552992 | -16.987870 | 0.192312 | 0.128436 |

`spatial_toy_audit.csv` saves the ten independent quantities beside the ten
production quantities for each metric. The completed verification has no failed
assertions. During development, the test harness needed two corrections: reading
a Stata matrix through `st_matrix`, and comparing repeated floating-point fits
at numerical tolerance rather than requiring bitwise identity. Neither required
changing estimation code or dropping an empirical result.

Additional figure-value checks confirmed all source matches and vector exports.
The handoff is appendix-only: it lets the manuscript establish numbering, uses
distinct `app:` labels, and includes numerical 4.81 and covariance-component
tables. The complete handoff was compiled and reviewed using letter paper,
one-inch margins, and `width=.97\linewidth` in the prescribed landscape layout.
The installed MiKTeX lacked `pdflscape`, so the proof used its installed
`lscape` package (the same landscape text layout); no package was installed.
Both figures fit on separate landscape pages, with the two tables on a third
page and no overfull boxes. The proof's page rotation was set for visual review.
