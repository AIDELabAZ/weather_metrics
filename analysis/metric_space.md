# Spatial dependence and first-stage precision

<!-- edited by: codex; edited on: 2 Nov 2026 -->

## Appendix-only update, 2 Nov 2026

The current appendix uses existing saved estimates. With the project globals
set, run `do "$code/analysis/viz_code/metric_app.do"`, followed by
`python analysis/viz_code/metric_app.py "<project data directory>"`, using
the directory represented by `$data`. Supply `--pdftoppm "<executable>"` if
needed; the Python assembly requires pypdf and reportlab. Do not run the
historical estimation or bootstrap commands below for this appendix update.

The vector `space_panel` PDF and 3,200-pixel PNG combine a two-column/three-row
score grid (about 60% width) with the reg2 paired 1.96 dumbbell plot (about 40%).
All 60 score-bin means and six country shares reproduce saved results. Every
country has the same 168 specifications in each covariance comparison. The
auxiliary `space_share481` is retained; its values appear in the appendix table
rather than a third panel. The optional component plot is omitted.

Under `additional_evidence/exhibit3/`, the new outputs are:

- `spatial_variance_components.csv`: 2,016 fits with HH, HH+within-EA, and
  full 100-km variances, SEs, t-statistics, ratios and threshold flags.
- `spatial_components_summary.csv`: 216 country/outcome/model/threshold/step
  rows, retaining signed additions and common matched denominators.
- `spatial_bandwidth_audit.csv`: 288 rows for 50/100/200-km and 100-km
  adjacent-interval sensitivity, both models, both outcomes and pooled shares.
- `spatial_sample_audit.csv` and `spatial_sample_summary.csv`: original versus
  georeferenced household estimates, distinguishing coverage from covariance.

Four within-EA and 92 between-EA additions are negative and retained; all total
variances are positive. The direction of the threshold-share reduction is
unchanged across the audited variants, although its magnitude depends on the
bandwidth and lag choice. Geography still excludes 778 Tanzania and 1,847
Uganda panel observations. The SDD audit confirms the 168 same-current-EA
links (120 from 2012 and 48 from 2008).

The optional `metric_app_check.do` verification matched 24 direct Stata fits
and independently reproduced the hand-checkable covariance example. See
`additional_exhibits_QA.md` for actual numeric results and limitations, and
`metric_app.tex` for the two appendix figures and supporting tables. No
coefficient-change or bootstrap analysis forms part of this appendix update.

## Original estimation workflow

The commands below document the earlier full estimation and pilot workflow.
Run after the project globals and `metric_keys.do` have been established:

```stata
do "$code/analysis/reg_code/metric_geo.do"
do "$code/analysis/reg_code/metric_space.do" pilot
do "$code/analysis/reg_code/metric_space.do"
do "$code/analysis/viz_code/metric_space_vis.do"
do "$code/analysis/reg_code/metric_block.do"
```

The pilot uses seasonal total rainfall (`v05`) and rainy days (`v08`), all
six products, both outcomes, and both FE specifications. Full results retain
all 84 rainfall candidates. The primary exhibit uses reg2, year and household
FE; year-only reg7 results remain a separate comparison. No existing panel,
regression output, or household-bootstrap output is overwritten.

## Released geography and current coverage

`metric_geo.csv` records raw paths relative to `$raw`, coordinate variables,
released EA identifiers where supplied, and the actual household join keys.
Edit those mappings when the pending files are located, then rerun the same
commands. It contains no confidential coordinates or machine-specific paths.

The current roster has 28 country-wave input folders corresponding to 27
country/survey-year combinations. Tanzania's 2014 new and extended panels
are separate input folders for the same survey year. Both remain identified
in the crosswalk and coverage audit.

| Country | Panel Observations | Georeferenced Observations |
|---|---:|---:|
| Ethiopia | 10,674 | 10,664 |
| Malawi | 8,897 | 8,895 |
| Niger | 3,913 | 3,913 |
| Nigeria | 9,145 | 9,145 |
| Tanzania | 9,916 | 9,138 |
| Uganda | 11,692 | 9,845 |

Niger uses the released modified EA positions in `NER_EA_Offsets.dta`.
The user confirmed that `grappe` identifies the same EA in 2011 and 2014,
so both waves join to that file by their actual wave's grappe. This explicit
linkage does not infer household immobility or permanent EA links elsewhere.

Tanzania's 2014 new panel joins its cluster IDs to `npsy4.ea.offset.dta`:
all 1,778 analysis observations match. The extended panel uses a different
cluster coding, so its raw household file is linked to the new-panel EA
roster by the complete region, district, ward, village, and EA codes. This
roster uses all 3,352 raw new-panel households, not just the agricultural
analysis subset. Each complete key must identify one released centroid EA;
missing components are not matched. This recovers one of the 349 analysis
observations in the extended panel; the other 348 remain unlocated.
The 2019/20 and 2020/21 community modules contain `cm_gps__Latitude` and
`cm_gps__Longitude`, but every value in both fields is `**CONFIDENTIAL**`:
99 and 488 community records, respectively. Masked GPS values are not
converted to coordinates or imputed.

The 2019/20 SDD panel has a separate bridge. `sdd_panel_key` links its
household IDs to earlier survey IDs; `hhfinal_npsy5sdd` supplies the current
region, district, ward, and EA. SDD district codes include the region prefix,
so that prefix is removed when comparing with the earlier waves' separate
region/district fields. Coordinates are reused only if all four current
administrative components agree with the linked earlier household record.
The most recent usable source is selected first: 2012, then 2010, then 2008.
This recovers 168 of the 312 SDD analysis observations: 120 from 2012 and 48
from 2008; the 2010 source adds no further observations in the current panel.
The other 144 do not have a verified same-EA coordinate link. Household-ID
continuity alone does not justify carrying a previous location forward.

The 2020/21 household file does retain the 2014 new-panel `clusterid` codes.
Those codes also persist for movers, so an unrestricted join would assign
some households the wrong location. The coordinate crosswalk therefore uses
the released 2014 centroid only when `hh_tracking_status == 1`, explicitly
labeled "HOUSEHOLD FOUND - ORIGINAL LOCATION". All 1,278 eligible analysis
observations have the same EA ID as their linked 2014 household record.
Other tracking statuses, including new locations and missing statuses,
remain unlocated. The 2014 coordinate vintage is recorded in the inventory;
it is not represented as newly released 2020/21 GPS.

Uganda now also covers all 2,190 observations in 2013/14 and all 1,868 in
2015/16. The downloaded files use lowercase `hhid`; the 2013/14 values match
`hh` in `unps4_merged`, which provides the bridge to the panel's `HHID`.
No 2019/20 coordinates have been located. The linked
[2018/19 geofile](https://microdata.worldbank.org/catalog/3795/data-dictionary/F109?file_name=unps_geovars_2018_19)
belongs to wave 7, which the current panel excludes; it is not substituted
for wave 8's observed location. Locations are reused only through the
documented stable-EA/current-location linkages above.

Original IDs are recovered from the existing household/append intermediates:
Ethiopia's `household_id2`, Malawi's long/short-panel wave identifiers,
Nigeria's original `hhid`, Tanzania's wave-specific IDs/cluster codes, and Uganda's
reconstructed panel links. Malawi's baseline family ID alone is not a unique
tracked-unit key. Joins preserve each country's existing panel identifiers.

Global coordinate ranges and broad country envelopes flag implausible
positions. The envelopes are checks rather than exact national boundaries.
Suppressed or missing coordinates remain missing. Released EA codes are
retained where available. When no EA code is released, identical released
coordinate pairs define location groups; these are explicitly identified
in the inventory. Grouping identical positions leaves the covariance kernel
unchanged. Cross-wave reuse is restricted to the documented EA linkages.

`geo_inventory.csv` reports every active input folder, source variables,
matched keys, valid-coordinate coverage, and distinct EA/location groups.
`geo_merge_audit.csv` reports the actual outcome-specific regression coverage.
`geovariables_crosswalk.dta` preserves original keys and wave-specific locations;
`lsms_panel_geo.dta` is a separate copy of the existing panel with this crosswalk.
Large Tanzania/Uganda sample restrictions must accompany any interpretation.

## Scores, kernels, and finite-sample correction

Each outcome and rainfall variable are residualized on the specified FE.
For each separate single-instrument fit, the score is residualized rainfall
times the full regression residual. This reuses `metric_fe.mata`; year-FE
rank accounts for disconnected household cohorts. All variance estimators
for a fit use the same observations and the same coefficient.

The household component is the sum of squared household score sums, retaining
unrestricted own-household serial covariance. Contemporaneous spatial terms
use EA/location-year score sums with a triangular kernel at 50, 100, and
200 km. The primary bandwidth is 100 km. Diagonal location terms retain
cross-household dependence at the same released position; subtracting the
individual squared scores avoids counting own-household terms twice.

Distances are Haversine great-circle kilometers with radius 6,371.0088 km.
A geographic cell index restricts the search before calculating distances.
Sparse neighbor lists extend to 300 km for the diagnostic reference band and
are cached by country, shared by both outcomes and all rainfall candidates.
The estimator never constructs a dense all-location distance matrix.

The same household-cluster small-sample factor, G/(G-1) times (N-1)/(N-k),
multiplies the household and spatial components. The effective parameter
count k uses the rank returned by the same QR projection that removes year
effects. This avoids a separate SVD rank counting a redundant year effect
on the expanded SDD sample. Raw spatial variances
and covariance components are retained. Nonpositive variances are flagged;
no arbitrary positive floor or silent replacement is applied.

An additional 100-km sensitivity includes adjacent *survey intervals* with
temporal Bartlett weight 0.5. Its own-household weighted cross-wave terms
are subtracted because household clustering already includes them. A missing
survey wave is not treated as an adjacent interval. This sensitivity does
not claim robustness to arbitrary between-household dependence at all lags.

## Descriptive diagnostics and figures

The correlogram uses only the prespecified total-rainfall and rainy-day
scores. Each location-year score sum is divided by the square root of its
household count, then standardized across locations within specification
and year. Distance-bin values are mean standardized cross-products, weighted
by the number of eligible pairs across years. They are not Pearson
correlations. The figure takes the median across six products and two
outcomes, giving each specification equal weight. Contemporaneous and
adjacent-interval diagnostics remain separate in the saved results.
Year FE impose finite-sample score restrictions; a negative long-distance
reference value need not indicate negative meteorological dependence.

Three new PDF/PNG figures are created in `figures/metric_paper/`:

- `space_score`: six-country score dependence on the available geography.
- `space_share`: paired household/100-km shares above |t|=1.96.
- `space_share481`: the corresponding appendix comparison at |t|=4.81.

`spatial_shares.csv` includes 50/100/200-km, adjacent-interval, and year-only
FE comparisons. Each paired share uses exactly the same estimable
specifications in its household and spatial numerator. Attempted,
household-estimable, matched, and invalid-variance counts are reported;
unavailable results are not coded as zero significance.

## Saved results and executed validation

Outputs are under `results_data/additional_evidence/exhibit3/`. The
`spatial_first_stage` DTA/CSV retains signed coefficients and t-statistics,
all SEs, raw variances, covariance components, sample sizes, warnings, and
original weather/specification identifiers. `geo_model_comparison.csv`
compares household estimates on the georeferenced sample with the original
regression rows, separating coverage effects from covariance changes.
`score_correlogram` and `score_summary` retain the diagnostic denominators.
Wide score files under `scores/` preserve every observation's household,
year, released location, outcome/specification, and `q_<weather_var>` scores.
This avoids repeating the same identifiers in millions of long-format rows.

Executed with StataNow 19.5 using built-in Stata/Mata commands and no new
production packages. The initial 240 pilot fits matched direct Stata
coefficients, household-clustered SEs, and observation counts to relative
tolerance 1e-8. Independent chord-distance searches reproduced the initial
five-country cached neighbor lists. All 12 updated-sample fits for CHIRPS
total rainfall, both outcomes and both FE models in Niger, Tanzania, and
Uganda also matched direct Stata estimates to relative tolerance 1e-8.
After the EA-based update, four additional Tanzania fits (CHIRPS total
rainfall, both outcomes and FE specifications) passed the same comparison.
The four fits on the expanded SDD sample also pass after the QR-rank
correction, with the same relative tolerance of 1e-8.
A separate, hand-checkable example independently reproduced the covariance
calculation, including same-location households, a mover, serial household
terms, and the adjacent-interval subtraction, to tolerance 1e-10. Those
verification fits/examples are not part of the production scripts.

The updated full run saved 2,016 specification rows: 1,008 estimated reg2
fits and 1,008 estimated reg7 fits. All estimated fits have positive spatial
variances at every prespecified bandwidth and in the adjacent-interval
sensitivity. Each country's primary paired comparison contains 168
specifications. The crosswalk covers 51,600 of the original 54,237 panel
observations; the estimation samples also exclude missing outcomes.

## Triggered bootstrap pilot

The 100-km adjustment reduces threshold-crossing shares in all six countries,
triggering the plan's subset assessment. `metric_block.do` pilots
CHIRPS total rainfall and rainy days, both outcomes, and all six countries:
24 declared cells after Niger's coordinates were located. Both designs use the
identical georeferenced sample and preserve each household's observed panel
history. The existing 1,008-by-1,000 household-bootstrap files remain untouched.

The geographic design uses 100-km equirectangular cells connected through
household histories, so no household or cell is divided between blocks.
This linkage can produce blocks larger than an individual grid cell. There
are 199 draws per design/cell. Design d uses seed
`20261031+1000*country+10*outcome+d`. Household resampling is d=1; geographic
resampling is d=2. Integer resampling frequencies produce the same
coefficients as copied household histories with separate FE, avoiding
thousands of redundant full regression commands. An actual-sample weighted
comparison verified the statistic against Stata frequency-weighted fits.

The statistic is reg2 minus reg7, standardized by the original georeferenced
sample's weather/outcome SD ratio. `block_boot_draws.dta` retains all 9,552
attempts. `block_boot_pilot.csv` records the 48 distributions, successful and
failed draws, and percentile intervals. Intervals require at least 95%
successful replications. `block_boot_comparison.csv` compares interval widths
only when both designs are complete.

The 20 comparisons outside Malawi completed all 199 draws. Malawi has only
two connected geographic blocks; its four geographic distributions have
151 or 156 successful draws and do not meet the required success rate.
Their intervals and significance indicators remain unavailable. This is a
design limitation, not evidence of zero uncertainty. The pilot is not a
replacement for the paper's production bootstrap or a claim of unrestricted
spatial-temporal robustness. Coordinate coverage, block design, and the
adjacent-interval sensitivity must be assessed before interpreting the full
bootstrap's significance rates as spatially robust.

With the expanded household histories, Uganda has eight connected geographic
blocks for farm value and seven for maize; Niger has 43 and 38, respectively.
Tanzania has 71 blocks in each outcome sample after adding the SDD matches.
The updated run contains 44 complete distributions and four incomplete
Malawi geographic distributions. Large connected blocks and the remaining
coordinate restrictions remain part of the pilot's interpretation.
