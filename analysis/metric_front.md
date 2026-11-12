# Rainfall selection frontier

<!-- edited by: codex; edited on: 12 Nov 2026 -->

## Appendix-only update, 3 Nov 2026

The current update runs `metric_app_fit.do`, followed by
`metric_app_fit.py "<project data directory>"`. It creates the direct
`front_payoff_levels` optimism exhibit and refreshes spacing in `front_panel_fit`
and `space_panel_revised`. Optimism is training gain minus held-out gain from
K=1 to K=84, calculated before aggregation. Points are medians across split
summaries; whiskers are descriptive IQRs. Earlier payoff candidates are no longer
generated. See `metric_payoff.md` and `metric_app.tex` for the current commands,
counts, checks and appendix handoff.
The earlier workflow below remains an auxiliary reproducibility path.

### Earlier appendix design

The earlier appendix design uses saved estimates; it does not require another frontier
run. After the project globals are set, run:

```stata
do "$code/analysis/viz_code/metric_app.do"
```

Then run `python analysis/viz_code/metric_app.py "<project data directory>"`,
using the directory represented by `$data`. Supply `--pdftoppm "<executable>"`
if Poppler is not on PATH. Python requires pypdf and reportlab. This produces
the vector `front_panel` and `space_panel` PDFs and 3,200-pixel PNG previews.
The four standalone frontier files below remain unchanged auxiliary outputs.

`front_panel` uses a six-country-row/four-column matrix: value reg7, value reg2,
maize reg7, maize reg2. Every cell retains all nine K points, log K and the
same -0.1 to 0.4 y range. Only median curves are plotted; the standalone plots
retain descriptive 10th-90th percentile bands.

`front_increment_comparison.csv` pairs G(84)-G(1) within the same allocation,
fold, ordering and selection rule, then pairs the reg2-minus-reg7 increment.
Orderings are summarized within a fold/allocation before summarizing the 100
fold/allocation values. This is descriptive dispersion, not independent
sampling replications. All primary cells have 100 valid summaries; Niger has
a few undefined raw comparisons that remain missing. The new auxiliary
`front_increment` plot is not automatically included as a third appendix figure.

The completed appendix review reproduces all 216 frontier points, checks all
20 allocations for household/geographic-group leakage, and replays 720 saved
candidate choices exactly. The optional verification is
`do "$code/analysis/reg_code/metric_app_check.do"`. See
`additional_exhibits_QA.md` for executed checks, denominators and sample
restrictions, and `metric_app.tex` for the appendix-only manuscript blocks.

## Consolidated estimation entry point

`metric_front.do` contains the fixed-effects, geographic-fold and selection
routines previously loaded from `metric_fe.mata` and `metric_front.mata`. Its
existing pilot and full-run commands, seeds, samples and output names are
unchanged. Shared spatial, bootstrap and appendix-check callers use
`do "$code/analysis/reg_code/metric_front.do" routines` to define the functions
without reading data, changing frames, opening logs or running estimation.
`metric_space.mata` remains the separate spatial-covariance dependency.

## Original estimation workflow

The commands below rebuild the original estimates, rather than the saved-result
appendix update above. Run after `projectdo.do` has established `$code`, `$raw`,
and `$data`:

```stata
do "$code/analysis/reg_code/metric_keys.do"
do "$code/analysis/reg_code/metric_front.do" 5 20
do "$code/analysis/reg_code/metric_front.do"
do "$code/analysis/viz_code/metric_front_vis.do"
```

The five-allocation pilot has separate `_pilot` outputs. The full run uses
20 allocations of five folds and 20 random candidate orderings. Allocation
`r` uses seed `20261031+r`. Candidate orderings use seed
`20261031+10000*country+100*allocation+held_out_fold`, shared across outcomes
and fixed-effects specifications. Each ordering considers the nested sets
`K=1,2,3,5,10,20,40,60,84`.

## Inputs and geographic grouping

The analysis reads the existing `regression_data/lsms_panel.dta`, including
its inverse-hyperbolic-sine outcomes and country-specific rainfall years.
It does not rebuild, re-transform, or overwrite that panel. The country
append scripts verify the current mapping: `rf1` ARC2, `rf2` CHIRPS, `rf3`
CPC, `rf4` ERA5, `rf5` MERRA-2, and `rf6` TAMSAT. `candidates.csv` records
all 84 original weather names and metric/product identifiers.

`metric_keys.do` reconstructs the original country-household identifiers
before applying the same string grouping used by `panel_build.do`.
Household/year joins recover the EA identifiers dropped by the country
append scripts. Tanzania uses its wave-specific cluster IDs rather than
the incomplete geography inherited by the appended long-panel file.
Malawi uses the baseline EA retained in its first-wave long/short-panel
files. Uganda uses parish blocks defined by district, subcounty, and parish;
these are coarser than EAs. Its original cross-wave household links are
reconstructed before identifiers are discarded. No IDs are joined on year
alone.

All households sharing an EA-wave or parish-wave belong to one connected
group, including links created by households changing location. Groups are
assigned together to folds, with randomized ordering and greedy balancing
of household counts within the group's initial geographic stratum. The
fold dataset contains every household's group and all 20 allocations.
Households and EA-wave groups cannot cross training/validation boundaries.
These are geographically grouped splits, not a distance-buffer design;
nearby but distinct EAs can still share a fold boundary. A distance-buffer
extension requires the separately verified coordinate crosswalk.

The existing panel replaces missing rainfall with zero. The new analysis
recovers pre-replacement missingness from country-complete files and
excludes those records without changing the published panel. It then forms
one common sample per country/outcome across all 84 instruments, retaining
households with at least two usable waves. Genuine zero rainfall remains
zero. `sample_audit.csv` reports outcome missingness, weather exclusions,
one-wave exclusions, households, EA-waves, and year counts. Each fold must
retain all of the country's common-sample years and at least two repeated
households in both partitions; rejected folds are retained in the audit.

## Estimation and outputs

The primary model is `reg2`: year and household fixed effects. `reg7`, year
fixed effects alone, is secondary. Outcome and rainfall residuals are
computed separately in each partition. The two-way calculation first
demeans by household and then projects out the household-demeaned year
indicators; it supports the actual unbalanced panel. Clustered standard
errors use household score sums and the same finite-sample correction as
Stata's existing models. The parameter count uses the rank of the demeaned
year indicators, accommodating disconnected survey cohorts. See the
[Stata xtreg manual](https://www.stata.com/manuals/xtxtreg.pdf).

The primary selection rule maximizes absolute training partial correlation.
The alternative maximizes the absolute household-clustered t-statistic.
Exact ties are broken by the candidate's first appearance in the ordering;
this matters for rainfall transformations that become equivalent after FE.
Held-out correlation always retains its sign, oriented by the selected
instrument's training sign. Undefined candidate estimates remain recorded;
they cannot win selection. Failed selections are counted separately rather
than coded as zero strength or as failures to exceed a threshold.

Results are separate from the existing regression and bootstrap files under
`results_data/additional_evidence/exhibit2/`:

- `panel_keys.dta`, `folds.dta`, and `candidates.dta` preserve reusable keys.
- `candidate_scores.dta` stores every candidate's two partition estimates.
- `selected_instruments.dta` records every selection, rank, sign, fold size,
  and effective candidate count.
- `baseline_comparison.csv` compares all common-sample coefficients and SEs
  with the original regression-result rows, including sample differences.
- `split_audit.csv` records partition sizes, households, years, and rejections.
- `front_table.csv` reports K=1,10,84, median training/validation correlations,
  median gap, sign reversals, and validation shares above |t|=1.96 and 4.81.
- `front_increment.csv` reports the median paired increment G(84)-G(1).
- `choice_frequency.csv` records all 84 choices, including zero frequencies.

The figures first take medians over candidate orderings within a held-out
fold, then plot medians and 10th-90th percentiles across folds. Bands are
descriptive dispersion, not confidence intervals. Threshold shares are
equal-weight averages of fold-specific shares among valid selected records;
attempted, valid, and invalid denominators are included. Choice frequencies
at K=84 count all 20 orderings per fold, preserving equal fold weights when
equivalent candidates tie.

Four PDF/PNG figures are saved in `figures/metric_paper/`: separate
value/maize frontiers (`front_value`, `front_maize`) and year-only FE
frontiers (`front_year_value`, `front_year_maize`).
K is displayed on a logarithmic axis, labeled at every declared set size.
Existing figures and the household bootstrap are not overwritten.

## Executed review, 31 Oct 2026

The full run produced 201,600 candidate records, 864,000 selection records,
2,400 accepted partition/model records, and 1,008 baseline reg2/reg7 pairs.
No folds were rejected. All 20 allocations passed household and EA-wave
leakage checks, and primary training strength was monotone in K.
Batch coefficients and household-clustered SEs matched direct Stata fits
for both outcomes and both specifications in a held-out fold of each country
to relative tolerance 1e-8. Verification fits are not part of the production
scripts.

The audit recovered 69 rows with pre-replacement missing rainfall. Across
the full candidate-score file, 110 records had undefined estimates, and
510 selection records lacked an estimable validation statistic. These
records are retained and are excluded from valid-rate denominators.
Outcome-specific one-wave household exclusions and sample-driven baseline
differences are reported in the accompanying audit CSVs.
