# Rainfall selection frontier

<!-- edited by: codex; edited on: 3 Nov 2026 -->

## Current appendix figures

After `projectdo.do` establishes `$code` and `$data`, run:

```stata
do "$code/analysis/viz_code/metric_app_vis.do"
```

This single native Stata script reads the completed exhibit2/exhibit3 saved
results and creates only `front.pdf/png`, `gain.pdf/png`, and `space.pdf/png`
under `$data/results_data/figures/metric_paper`. It opens one log at
`$data/results_data/logs/metric_app_vis.log`. No external assembly or estimation
is required. See `metric_app_QA.md` and `metric_app.tex` for validation and the
appendix-only manuscript handoff.

## Original estimation workflow

Run after `projectdo.do` has established `$code`, `$raw`, and `$data`:

```stata
do "$code/analysis/reg_code/metric_keys.do"
do "$code/analysis/reg_code/metric_front.do" 5 20
do "$code/analysis/reg_code/metric_front.do"
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
Stata's existing models. See the [Stata xtreg manual](https://www.stata.com/manuals/xtxtreg.pdf).

The primary selection rule maximizes absolute training partial correlation.
The alternative maximizes the absolute household-clustered t-statistic.
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
at K=84 count each fold once because ordering does not change its winner.

Eight new PDF/PNG figures are saved in `figures/metric_paper/`: separate
value/maize frontiers (`front_value`, `front_maize`), clustered-t selection
(`front_t_*`), year-only FE (`front_year_*`), and choice maps (`front_choice_*`).
K is displayed on a logarithmic axis, labeled at every declared set size.
Existing figures and the household bootstrap are not overwritten.
