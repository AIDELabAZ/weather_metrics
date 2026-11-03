# Final appendix figures

<!-- edited by: codex; edited on: 3 Nov 2026 -->

## Reproduction and scope

After `projectdo.do` establishes the project globals, run:

```stata
do "$code/analysis/viz_code/metric_app_vis.do"
```

The single native Stata script reads saved exhibit2/exhibit3 results, includes
only the shared `metric_style.do`, and exports exactly three PDF/PNG pairs.
It performs no estimation, bootstrap, Python assembly or subsidiary do-file
execution. The single log is `$data/results_data/logs/metric_app_vis.log`.
The complete run from the `analysis` checkout closed successfully on 3 November
2026 at 15:33:31 using StataNow 19.5. No new package was installed.

## Outputs and executed checks

Outputs are under `$data/results_data/figures/metric_paper/`:

| Figure | PDF canvas | PNG pixels | Content |
|---|---|---|---|
| `front` | 9 x 5.4 in | 3,200 x 1,920 | Twelve frontiers in Quantity/Value blocks |
| `gain` | 9 x 5.3 in | 3,200 x 1,884 | Paired training-to-held-out search gains |
| `space` | 9 x 6 in | 3,200 x 2,133 | Score dependence and matched significance shares |

All PDFs have one vector page and zero raster image objects. PDF renders and
the corresponding PNGs were inspected. The appendix-only `metric_app.tex`
compiled successfully on letter paper with one-inch margins: three landscape
figure pages and one page of unchanged supporting tables. The final insertion
size has no clipping, overlapping labels or LaTeX overfull boxes. Bold text
is confined to panel/outcome headings; country names, axes and ticks are regular.
Lowercase `of` and `km` are used consistently. No remaining visual defect was
identified. Very short gain arrows use a small bend; numerical endpoints,
marker positions and interval centers are unchanged.

- Outcome mapping was checked against `metric_coeff_vis.do`: Quantity is
  `lncp_yld` (source outcome 2); Value is `lntf_yld` (source outcome 1).
- The candidate grid has 14 metrics across six products. All 216 frontier rows,
  including training/held-out medians and p10/p90 endpoints, reproduce
  `exhibit2/selection_frontier.dta` to relative tolerance 1e-9. All nine K values,
  log scaling, common -.12 to .38 range and original four series are retained.
- Gain differences use matched allocation/fold/ordering keys at K=1 and K=84,
  before medians over 20 orderings and medians/IQRs across 100 grouped exercises.
  All 24 gain rows and their two medians/four IQR endpoints reproduce the saved
  `appendix/front_payoff_values.csv` at relative tolerance 1e-9. The minimal
  `appendix/gain_summary.dta/.csv` records plotted values and counts.
- Existing undefined Niger raw pairs remain missing: valid counts are
  Value reg2 1,993/reg7 1,996 and Quantity reg2 1,992/reg7 1,995, out of 2,000.
  Other cells have 2,000 pairs; every cell still has all 100 fold summaries.
  No new exclusion or inferential claim was introduced.
- Panel A uses the same 60 saved score-bin values and existing country-specific
  scale calculation. The native spatial canvas applies affine display
  coordinates without changing scores, categorical distance bins or axis limits.
- Panel B retains 84 matched specifications for each country/outcome. Pooled
  household and 100 km spatial shares reproduce `exhibit3/spatial_shares.dta`
  to absolute tolerance 1e-9. Arrows point household-to-spatial, with heads at
  two-thirds of the segment. Triangles distinguish the two Panel A metrics;
  diamonds/squares distinguish the two Panel B covariance methods.

## Source consolidation and integration

The surviving visualization source is `analysis/viz_code/metric_app_vis.do`.
The appendix handoff is `analysis/metric_app.tex`; `metric_front.md` documents
the current entry point. Only these approved source/documentation changes and
the tracked obsolete plotting deletion are integrated into `analysis`.
The analysis checkout was first fast-forwarded to `28d9892`; unrelated feature
branch model/geography changes were not merged.

Removed from the source feature worktree after testing:

- `analysis/viz_code/metric_app.do`
- `analysis/viz_code/metric_app_fit.do`
- `analysis/viz_code/metric_app.py`
- `analysis/viz_code/metric_app_fit.py`
- `analysis/viz_code/metric_front_vis.do`
- `analysis/viz_code/metric_space_vis.do`

Only `metric_front_vis.do` was tracked on the updated `analysis` base; the other
five obsolete helpers were already absent there. Current documentation no longer
instructs users to run deleted helpers. Earlier scientific QA records on the
feature branch are explicitly archived. `analysis/reg_code/metric_app_check.do`
is retained there because its geographic leakage checks, SDD links, direct Stata
fits, deterministic replay and independent covariance example are not replaced
by visualization checks. It was not run in this task. Estimation sources and
the shared style/palette files are unchanged.

## Verified OneDrive cleanup

After replacement exports and appendix references were validated, 84 individually
inventoried obsolete graphics were removed and verified absent. No wildcard or
recursive directory deletion was used. Thirty files were the PDF/PNG pairs for:

| Removed base | Removed base | Removed base |
|---|---|---|
| `front_increment` | `front_maize` | `front_value` |
| `front_panel` | `front_panel_fit` | `front_payoff_arrows` |
| `front_payoff_levels` | `front_payoff_scatter` | `front_year_maize` |
| `front_year_value` | `space_panel` | `space_panel_revised` |
| `space_score` | `space_share` | `space_share481` |

The other 54 removed files were disposable PDFs in
`additional_evidence/appendix/components/` and `additional_evidence/appendix/fit/`:

- Components: `front_<1-6>_<1-4>`, `space_a`, `space_b` (26 PDFs).
- Fit: `front_<1,2,4,5,6,7>_<1-2>`, `forest_<1-2>`,
  `payoff_arrows_<1-2>`, `payoff_levels_<1-2>`, `payoff_scatter_<1-2>`,
  `score_<1,2,4,5,6,7>`, `share_<1-2>` (28 PDFs).

All appendix `includegraphics` references use the three final short names.
No other manuscript reference to a deleted graphic was found. Sizes and
modification times for all 76 unrelated figure files matched their pre-cleanup
inventory. Primary datasets, numeric summaries, logs and private inputs were
retained. The coefficient-change bootstrap, its figures and main-text workflows
were not modified, run or reanalyzed.
