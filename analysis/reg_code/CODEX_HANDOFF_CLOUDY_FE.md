# Codex implementation handoff: Cloudy rainfall FE comparisons

**Status:** Design approved for implementation; estimation changes not yet made.

**Repository:** AIDELabAZ/weather_metrics
**Base branch:** `analysis`
**Target file:** `analysis/reg_code/regressions.do`
**Related:** `analysis/reg_code/panel_build.do` and root `AGENTS.md`

## Purpose

Extend the existing long-format Stata regression results so later scripts can construct:
1. a paired rainfall-coefficient/standard-error comparison;
2. first-stage-strength survival curves or densities; and
3. specification charts of paired coefficient changes with *future* cluster-bootstrap confidence intervals.

**Do not** create graphs, bootstrap confidence intervals, z/F statistics, standardized coefficients, or downstream transformations in this task. Preserve all existing output filenames and directory globals. The user will migrate paths to paper-specific directories later; leave that alone for now.

## Estimation specification

- The current file loops by country, weather variable, and outcome and uses `postfile`. Preserve that structure. Do not introduce an extraction-method loop.
- Outcomes: `lntf_yld` (value of production per ha), `lncp_yld` (primary cereal/maize quantity per ha as named in code).
- Rainfall metrics `v01` to `v14`, rainfall products `rf1` to `rf6`. Preserve the existing temperature, nonlinear, and input models for historical reproducibility.
- **`reg1`:** Historical weather-only regression, no fixed effects; retain its existing meaning.
- **`reg7`:** Add weather plus *year fixed effects only*: `reg y weather i.year if country == l, vce(cluster hhid)`.
- **`reg2`:** Existing weather plus year and household FE: `xtreg y weather i.year if country == l, fe vce(cluster hhid)`.
- The comparison of interest is `reg7` against `reg2`. Do not change `reg1` into `reg7`.
- Make both models use identical *actual* household-year observations, not merely equal counts. Establish a common comparison sample up front. Preserve existing `reg2` estimates where possible, and report if sample alignment changes them.
- Match one country × outcome × full weather variable name, e.g., `v05_rf1`. Six countries × 2 outcomes × 14 rainfall metrics × 6 rainfall products = **1,008 intended pairs**, **2,016 paired estimation results**, subject to actual estimability. This is the no-extractions subset used in the current paper.

## Output schema

Keep `$results/reg_results.dta` and `$results/lsms_complete_results.dta`.

Preserve existing result fields, numerical codes and value labels. Add:
- `weather_var`: original untruncated variable identifier, e.g. `v05_rf1`;
- `pair_id`: same for `reg7` and `reg2`, different across country, outcome, and full weather variable; separate from per-regression `reg_id`;
- `n_clusters`: distinct household clusters used in each regression, using stored estimation results where valid;
- `sd_weather` and `sd_outcome`: standard deviations on the *common paired regression sample*; describe the denominator convention; preserve data without doing coefficient standardization;
- `obs` (or reliable alias), `dfr`, and double-precision `beta` and `stdrd_err`;
- model identity sufficient to establish inclusion of year FE and household FE, either unambiguous `regname` coding or explicit flags.

No requirement to store every resampled bootstrap result or household-level panel observation here. The downstream bootstrap will re-open `lsms_panel.dta` and run both models under household-cluster resampling. Do not claim bootstrap intervals can be reconstructed from the aggregate coefficient table alone.

Do not impose arbitrary new exclusions based on statistical significance. Fail with an informative message or report non-estimable specifications instead of silently dropping data.

## Existing code hazards

- After `postclose`, the current file does `drop if loglike == .`. This risks removing `xtreg, fe` estimates because stored likelihood metadata differ by estimator. Audit and remove the unsafe drop/filter or replace it with an estimator-neutral validity check. Document any omitted/non-estimable regressions.
- The significance code has a typo: `replace b_ns = . if p <= .05` should reference `pval`.
- Current `aux_reg` mapping covers only `reg1`-`reg6`, despite an existing `reg7` label; add mapping for `reg7`.
- Check existing label continuations (`////`) and ensure do-file parses and runs.
- When pairing models, note that duplicate `country` × `weather_var` × `depvar` within the `reg2` and `reg7` subset indicates an implementation error. Verify `isid pair_id regname` and that `reg_id` is unique on the full output.

## Tests and delivery

1. Work on a new feature branch based on `analysis`, not `main`; open a PR to `analysis` for review.
2. Check model syntax, Stata return values, precision of posted results, and schema/value-label compatibility.
3. If Stata 18 and `$data/regression_data/lsms_panel.dta` are accessible locally, run the complete code. Report pair counts by country/outcome and absent/non-estimable cells; verify same actual sample membership for each pair and cluster counts.
4. Verify `reg2` results agree with their old counterparts when samples have not changed. Explain any discrepancies.
5. Confirm no new extraction loops, changes to filenames/paths, data commits, figure production, bootstrapping, z/F calculations, or standardization.
6. Commit a focused diff and report PR link plus results of checks. If the analysis data or Stata are unavailable, say explicitly that tests were static only and do not claim a successful full run.

## Design boundary

We will decide later whether new figures are grouped by country, outcome, product, or metric. Preserve identifiers that allow each. The later coefficient-difference figure must distinguish coefficient changes from loss of precision and respect original rainfall metric units; the future standardized contrasts are computed downstream. The later weak-IV analysis will use cluster-robust information and appropriate critical values; do not add instrument tests in this regression-generation do-file.
