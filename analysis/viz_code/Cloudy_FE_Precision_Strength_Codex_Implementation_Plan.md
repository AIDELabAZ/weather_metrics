# Codex implementation plan: Rainfall coefficient-precision and first-stage strength figures

**Project:** *Cloudy With A Chance of Significance: Specification Search and the Illusion of Exogeneity in Remotely Sensed Weather Data*  
**Repository:** `AIDELabAZ/weather_metrics`  
**New file:** `analysis/viz_code/rainfall_diagnostics.do`  
**Input:** `$data/results_data/lsms_complete_results.dta`  
**Output directory:** `$data/results_data/figures/metric_paper` (follow the current project globals; do not hard-code personal Windows paths)  
**Scope:** Two final figures only. This is downstream analysis of *completed* regressions; do not modify or rerun the regression-generation script.

## 1. Task

Create one self-contained Stata visualization do-file that reads the **newly generated** `lsms_complete_results.dta`, matches the two rainfall specifications, performs only the transformations needed for the plots, and exports:

1. `rainfall_FE_coefficient_precision.pdf` and `.png`;
2. `rainfall_FE_strength_distribution.pdf` and `.png`.

The visual reference is the two prior prototypes, `rainfall_FE_coefficient_precision_prototype` and `rainfall_FE_strength_distribution_prototype`: six country panels (three columns by two rows), restrained teal/copper palette, white background, subtle gridlines, legible axes, compact legends, and minimal framing. **The new figures must use the NEW regressions and should not reproduce the prototypes' historical estimates.**

**Nonnegotiable figure rule:** Do not embed a main title, subtitle, figure number, caption, source, bottom note, explanatory annotation, or empty space reserved for any of these. All such text belongs in LaTeX. Allowed within the images: country/panel headings, axis titles and tick labels, an informative shared legend, and reference lines. Suggested LaTeX text is at the end of this plan; do not edit the manuscript.

Do not add bootstrap routines, coefficient-difference confidence intervals, regressions, other figures, data cleaning for other projects, or repository-wide formatting edits. Use Stata 19.5 and the repository's `AGENTS.md` conventions. This do-file should run separately once the current regression job has completed and its results file has been fully saved.

## 2. Source schema: verified from the attached `regressions(2).do`

The updated code estimates:

- `spec_id == "reg7"`: rainfall + year fixed effects (`regress ... i.year, vce(cluster hhid)`). **No household FE.**
- `spec_id == "reg2"`: rainfall + year fixed effects + household fixed effects (`xtreg ..., fe vce(cluster hhid)`).

The comparison is **reg2 versus reg7**, *not* reg2 versus the historical `reg1`. All model labels must say **"Year FE"** and **"Year + household FE"**; never label reg7 simply "without FE".

Saved variables include `country` (numeric; labelled), `outcome_var` (`lntf_yld` or `lncp_yld`), `weather_var` (full identifier such as `v05_rf1`), `spec_id` (string `reg2`/`reg7`), `regname` (numeric; 2 or 7), `paired_sample` (1 on target rows), `estimable` (1 for nonmissing coefficient with positive SE), `beta`, `stdrd_err`, `obs`, `nclusters`, `dfr`, and existing summary fields. The generated file also includes temperature-only reg2 rows. **Ignore them** in this task.

The updated regression file specifically creates the reg7 sample from the corresponding reg2 `e(sample)` and asserts identical observations before posting. The results file therefore contains an intended matched comparison, and downstream checks should still verify its keys and sample counts.

**Critical version check:** A historical `lsms_complete_results.dta` exists with 77,760 rows and columns such as `ext` but **without** `weather_var`, `spec_id`, `paired_sample`, or reg7. That historical file is not suitable here. If the expected new fields or any reg7 results are missing, stop with a useful error; do not silently substitute `reg1` or infer an extraction method.

Expected coverage if all countries and specifications are estimable: **6 countries x 2 outcomes x 14 rainfall metrics x 6 rainfall products = 1,008 matched pairs**, or 168 pairs per country and 84 per country/outcome. The updated estimator also writes some non-rainfall rows, so total dataset row count is *not* the relevant validation statistic. Treat 1,008 as an expectation, report actual coverage, and retain valid subsets only with an explicit accounting of exclusions.

## 3. Preflight and pairing (one shared dataset for both figures)

Implement these steps **once** near the start of the new do-file:

1. Read the existing result file via `$data/results_data/lsms_complete_results.dta`, after checking that it exists.
2. Confirm required variables and model identifiers exist; verify the result contains `spec_id == "reg2"` and `spec_id == "reg7"`.
3. Restrict to `paired_sample == 1`, `spec_id` in `("reg2", "reg7")`, `outcome_var` in `("lncp_yld", "lntf_yld")`, and rainfall names matching `^v(0[1-9]|1[0-4])_rf[1-6]$`. This produces 14 metrics x 6 products, with **no extraction-method dimension**.
4. Verify `isid country outcome_var weather_var spec_id` before reshaping. Do not pair on `reg_id`: that identifies *individual regressions*, not pairs.
5. Keep only fields needed for plots and diagnostics, then reshape wide using `i(country outcome_var weather_var)` and `j(spec_id) string`, obtaining `beta_reg2`, `beta_reg7`, `stdrd_err_reg2`, `stdrd_err_reg7`, plus `estimable`, `obs`, and `nclusters` by specification. Before `reshape`, drop variables that differ across specifications (`reg_id`, `regname`, `dfr`, etc.) unless they are explicitly included as wide stubs.
6. Report missing `reg2` or `reg7` counterparts. For complete pairs, assert `obs_reg2 == obs_reg7` and `nclusters_reg2 == nclusters_reg7`; flag any mismatch rather than silently merging samples. Remember that matching counts do not *prove* identical records, but the estimation do-file contains an upstream `e(sample)` equality check.
7. For the common analytical set, require both `estimable_reg2 == 1` and `estimable_reg7 == 1`, `beta` nonmissing, and both SEs strictly positive. Exclude non-estimable pairs **symmetrically**, so each country/model curve has the same denominator. **Do not** filter on significance or coefficient sign.
8. Keep the labelled country order **Ethiopia, Malawi, Niger, Nigeria, Tanzania, Uganda**. Encode outcome categories consistently: `lncp_yld` = **Cereal quantity**; `lntf_yld` = **Farm production value**. Labels can be shortened in legends if necessary.
9. Store this paired dataset in memory or a `tempfile`; use `preserve`/`restore` for each figure. Do not overwrite the input `.dta` or change its schema. An optional logged QC summary is fine; no permanent intermediate dataset is required.

Before plotting, display a compact QC summary in the Stata Results/log: total source rows, filtered comparison rows, unmatched/non-estimable pairs, number of valid pairs by country/outcome, sample-size mismatches, and maximum `|t|` by specification. **These are console/log diagnostics, not text inside the figures.**

## 4. Figure A: Coefficient magnitude versus precision

**Output basename:** `rainfall_precision`.

Each point represents one matched `country x outcome x rainfall metric x product` pair. Compute in **double precision**:

```stata
* Name suffixes refer to specification IDs, not rainfall products.
gen double x_beta = ln(abs(beta_reg2) / abs(beta_reg7)) / ln(2)
gen double y_se   = ln(stdrd_err_reg2 / stdrd_err_reg7) / ln(2)
```

Use these formulas only where `abs(beta_reg2)>0`, `abs(beta_reg7)>0`, and the positive-SE conditions hold. Exact zero coefficients yield undefined log ratios: count and report them; exclude them **from this figure only**, without removing their valid t-statistics from Figure B. Do not transform the sign of a coefficient into its magnitude without retaining that distinction in the LaTeX note.

**Interpretation to preserve in the plot geometry:**

- `x_beta < 0`: absolute coefficient is smaller when household FE is included.
- `y_se > 0`: cluster-robust standard error increases when household FE is included.
- The **dashed line `y_se = x_beta`** is the locus of unchanged absolute t-statistic; points **above** it have lower `|t|` with household FE.
- Add thin horizontal and vertical solid zero reference lines. Put the interpretation in the *LaTeX figure note*, not as annotation inside the plot.

**Design:**

- Use six small-multiple country panels, 3 columns x 2 rows, with a common x scale and common y scale across panels. Use a light grid, white background, strong but unobtrusive country names, and thin neutral reference lines.
- Color by **outcome**: cereal quantity teal **RGB `34 127 144`** (`#227F90`); farm production value muted copper **RGB `190 118 64`** (`#BE7640`). Use moderately transparent, small markers to show overlap, with one shared two-category legend. These colors are sampled from the previous prototype's visible line colors.
- Suggested x-axis wording: `Change in |rainfall coefficient| (log2 ratio)`; y-axis: `Change in standard error (log2 ratio)`. Stata graph text can use readable `log2` typography; LaTeX supplies any elaborate math notation.
- As a starting visual domain, use approximately `[-4.5, 4.5]` for `x_beta`, matching the prototype. **Do not silently winsorize, cap, or drop values.** Compute the actual range first; if excluding points from the visible window, keep the full data intact, count the off-window points in the log, and choose a sensible shared plotting range. Preserve negative y-values (SE decreases) when present. If extreme ratios make the panel unreadable, document any display-window choice for the later LaTeX note.
- Do not draw country sample-size labels, claims such as "weaker above diagonal", titles, subtitles, or bottom notes inside panels.

The ratio compares the *same weather metric and product* across two specifications, so the differing physical units across rainfall metrics do not invalidate the comparison.

## 5. Figure B: Empirical first-stage strength survival curves

**Output basename:** `rainfall_strength`.

Use the **same matched-pair set** from Section 3, including valid zero coefficients that Figure A may need to omit. For each pair, calculate the absolute cluster-robust first-stage t-statistics:

```stata
gen double abs_t_reg7 = abs(beta_reg7 / stdrd_err_reg7)
gen double abs_t_reg2 = abs(beta_reg2 / stdrd_err_reg2)
```

The x-axis is the threshold `t >= 0`; the y-axis is the empirical share of **all valid paired specifications in that country** with `abs_t >= t`. This is a *survival curve*, not a CDF and not a histogram. A threshold of zero must have share 1. Use **the same denominator for both curves in each country**, pooling the two outcomes and all 14 metrics x 6 products. Do not average country shares together.

**Construction:** Build a fine grid such as `t=0, 0.05, ..., 15` (or exact data-driven step coordinates), calculate shares directly from the complete country sample at every threshold, and plot line/step curves. Observations with `abs_t > 15` must still be counted in the survival fraction at all displayed lower thresholds. Do not truncate the data *before* calculating the survival curves.

**Design:**

- Six country panels (3 columns x 2 rows); fixed y-axis `[0,1]`; shared x-axis approximately `[0,15]`. Use a common legend rather than one legend per country.
- **Teal (`#227F90`)**: `Year FE` (`reg7`). **Copper (`#BE7640`)**: `Year + household FE` (`reg2`). Colors distinguish the *models* in this figure; in Figure A they distinguish the *outcomes*. Make the legends explicit.
- Use medium-weight solid lines, no point markers, no shaded uncertainty bands.
- Add subtle vertical reference rules at **`|t| = 1.96`** (dotted, conventional large-sample two-sided 5% benchmark) and **`|t| = sqrt(23.1) ~= 4.81`** (dashed, the one-instrument 23.1 effective-F reference expressed on a t scale). Put the meaning and methodological context of these references in the LaTeX note; do not embed explanatory labels in the image.
- Suggested axes: x `Absolute cluster-robust t-statistic`; y `Share of specifications above threshold`.
- Keep actual survival-curve values, not smoothed or fitted representations. Distinguish the empirical first-stage Wald diagnostic `t^2` from any separately computed IV model's overall F-statistic; do not substitute Stata `e(F)` or use historical `reg1`.

The new results include year FE in **both** models. The previously drawn historical strength prototype used a different no-FE baseline; expect its shape and threshold crossings to change.

## 6. Graph implementation and output requirements

- Implement in **one new file only**, `analysis/viz_code/rainfall_diagnostics.do`. Do not modify `regressions.do`, `projectdo.do`, `metric_sum.do`, or the manuscript. Read `AGENTS.md` and the existing graphics conventions before coding.
- Use the globals already established by `projectdo.do`, especially `$data`. Avoid machine-dependent absolute paths and do not create or modify directories outside the established project outputs. Check/create only the approved figure output subfolder if missing.
- If a reusable `cloudy_graph_style.do` exists from the Figure 2/3 redesign, import its compatible palette and neutral styling; otherwise define a small set of colors locally in this new script. Do not introduce an unrelated graph-style dependency merely to complete this task.
- **Prefer Stata-native `twoway` with `by(country, cols(3))`** where that produces the desired small multiples and a single shared legend; test Stata's actual legend and `by()` syntax. If necessary, use six country graphs and a combined shared-legend method already available in the project. Avoid six duplicated legends. Prevent Stata's default "Graphs by ..." note from appearing by specifying an empty by-graph note.
- Do not add a figure title, subtitle, caption, bottom note, sample-size annotation, or explanatory prose in any graph option. Country headings, shared legend, axes, and reference rules are permitted. Do not leave unnecessary blank margins for removed text.
- Export **vector PDF** for LaTeX and high-resolution **PNG** (target 3000-3600 px wide) for review; preserve consistent physical aspect ratio. Save optional `.gph` files only if useful for reproducibility. Output exactly the two named figure basenames above.
- Keep visual emphasis on the data: white graph/plot backgrounds; neutral dark text (`#262B2F`), very pale gray grids (`#E8EBED`); minimal borders; restrained strokes and symbols; strong legibility at the manuscript's printed size. Avoid colorful shading, decorative callouts, six separate legends, or excessive axis labels.
- Do not overwrite the prior prototype files. It is acceptable to overwrite the *new* canonical outputs on reruns.

## 7. Validation and acceptance tests

**Data integrity**

- [ ] New result file contains `reg7`, `reg2`, `weather_var`, `spec_id`, and paired flags; stale historical results trigger an explanatory error.
- [ ] Only rainfall `v01`-`v14` and products `rf1`-`rf6` are included; no temperature variables or extraction-method assumptions.
- [ ] `isid country outcome_var weather_var spec_id` before pairing; no duplicate matched pairs after reshaping.
- [ ] Expected coverage is 1,008 total pairs (168/country, 84/country/outcome) if all estimates are valid; actual exclusions are clearly tabulated.
- [ ] Both models use identical saved observation counts and household-cluster counts in every retained pair.
- [ ] Neither figure filters by p-value, coefficient sign, nor product; zero-beta exclusions apply only to undefined log ratios in Figure A.

**Numerical checks**

- [ ] Confirm a handful of plotted `x_beta`, `y_se`, and `abs_t` values by hand against raw `beta`/`stdrd_err` in the `.dta`.
- [ ] Verify `log2(|beta_reg2|/|beta_reg7|) - log2(se_reg2/se_reg7)` equals `log2(|t_reg2|/|t_reg7|)` for positive-magnitude pairs, within numerical tolerance.
- [ ] Confirm each country/model survival curve begins at 1, is weakly decreasing, and stays in `[0,1]`.
- [ ] At selected thresholds, independently verify plotted survival percentages from `count if abs_t >= threshold` divided by the matched-pair denominator.
- [ ] Verify no observations above the right-hand display limit were removed from the denominator; report any display-only clipping in the log.

**Visual checks**

- [ ] Both plots have the same six-country order, 3 x 2 layout, white-background visual identity, and consistent teal/copper colors.
- [ ] Figure A has a diagonal plus zero reference lines, and Figure B has the two stipulated vertical threshold rules.
- [ ] Each plot has exactly **one shared legend**. Legend labels correctly reflect whether colors denote outcome or FE specification.
- [ ] Absolutely **no embedded figure title, subtitle, figure number, caption, bottom note, or interpretation text**.
- [ ] Rendered PDFs and PNGs have readable axis units, no clipped legends or markers, and appropriate sizing at final LaTeX insertion scale.

If the new results are still being written or Stata/data access is unavailable, implement the file with validation guards and state clearly what could not be executed. Do **not** claim the final figures have been regenerated from the new regressions before the new `.dta` has actually been read.

## 8. Suggested LaTeX captions and notes (do not render in graphics)

**Figure A title:** *Household Fixed Effects, Rainfall Coefficients, and Precision*  
**Optional subtitle:** *Changes relative to specifications with year fixed effects*  
**Suggested note:** "Each point represents a matched country-outcome-rainfall metric-product specification. Both models include year fixed effects. The horizontal axis shows the log2 ratio of absolute rainfall coefficients with and without household fixed effects; the vertical axis shows the corresponding log2 ratio of cluster-robust standard errors. The dashed diagonal indicates no change in the absolute t-statistic."

**Figure B title:** *Household Fixed Effects and First-Stage Strength*  
**Optional subtitle:** *The distribution of cluster-robust first-stage t-statistics*  
**Suggested note:** "Each curve shows the fraction of matched rainfall specifications whose absolute cluster-robust t-statistic exceeds the indicated threshold, pooling rainfall metrics, products, and both agricultural outcomes within country. Both specifications include year fixed effects; the orange curve also controls for household fixed effects. Vertical lines identify the 1.96 conventional significance reference and the square root of the 23.1 one-instrument effective-F benchmark."

These are proposals for the LaTeX caption/note system only; do not insert or edit `.tex` files.

## 9. Codex deliverables

1. A focused commit/PR adding only `analysis/viz_code/rainfall_diagnostics.do` (except minimal necessary existing style-helper reuse).
2. Two PNG and two PDF figures **generated from the new `lsms_complete_results.dta`**, or a precise explanation of what prevented execution.
3. A brief console/log QC summary: pair counts by country/outcome, non-estimable/zero-beta counts, any sample-count mismatches, and the display range used.
4. Confirmation that the script performs no regressions and neither modifies the input `.dta` nor changes paths or manuscript text.

**Paste into Codex:**

> Read `AGENTS.md` and this plan. Add `analysis/viz_code/rainfall_diagnostics.do` to read the newly completed `lsms_complete_results.dta`, match the `reg7` and `reg2` rainfall regressions, validate sample/cluster counts, and produce the coefficient-precision scatter panels and first-stage strength survival-curve panels. Match the prototype visual style, but leave figure titles, subtitles, and all bottom notes in LaTeX. Do not alter regression-generation files, compute bootstrap intervals, or use historical `reg1` results. Generate PDF/PNG previews and report QC counts. Make a focused commit for review.
