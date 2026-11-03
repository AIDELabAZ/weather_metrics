# Cloudy: appendix-only implementation plan for additional-evidence exhibits

**Code baseline:** `AIDELabAZ/weather_metrics`, branch `metric-exhibits`, commit `567c3c1f437aa9ca2788a1ce37e2c22352fd10d1` (2 November 2026).  
**Audience:** Codex implementing figures, summary outputs, and validation.  
**Scope and placement:** **All new evidence belongs exclusively in the appendix.** Construct two combined appendix figures and the supporting audits described below. Reuse existing Exhibit 2 and Exhibit 3 estimates wherever possible. Do not rebuild or overwrite the published LSMS panel, modify any main-text figure, change main-text figure numbering, or revise the main-text narrative. The clustered-t selection figures and candidate-choice heat maps have already been dropped: **do not recreate them**.

**Explicit protected scope (nonnegotiable):** The existing bootstrap coefficient-change heat map is `boot_heat.pdf`. **Do not modify, regenerate, replace, renumber, re-estimate, revalidate, or otherwise revisit `boot_heat.pdf`, its underlying bootstrap estimates, confidence intervals, figure notes, or source workflow.** Do not run `metric_boot.do` or any bootstrap-analysis program, do not run `metric_block.do`, and do not perform any new inference for the change between the household-FE and year-FE coefficient estimates. Do not add a spatial adjustment to those coefficient differences. This assignment is **only** about the selection-frontier and first-stage spatial-inference appendix exhibits. Reading existing paper-style code for graphical conventions is allowed, but do not execute scripts that would remake unrelated figures.

## 1. Final figure decisions (implement these designs)

### Appendix Figure A: First-stage instrument-selection frontiers, four analytic panels

**Decision:** Combine `front_year_value`, `front_value`, `front_year_maize`, and `front_maize` in **one landscape figure**. Do **not** place the four existing six-country images in a conventional 2 × 2 collage: that would create 24 very small plots, duplicate country labels, and make the lines difficult to read.

Instead, rebuild the figure directly from `selection_frontier.dta` as a **six-row × four-column matrix**. Six rows identify countries once, in the paper's order; four columns are the analytic panels. This is one figure with four model/outcome comparisons, each broken out by country. Arrange the columns to put the FE comparison next to itself within each outcome:

```text
                                FARM PRODUCTION VALUE                 MAIZE YIELD
                          (A) Year FE  (B) Year + HH FE      (C) Year FE  (D) Year + HH FE
Ethiopia                    [frontier]      [frontier]          [frontier]      [frontier]
Malawi                      [frontier]      [frontier]          [frontier]      [frontier]
Niger                       [frontier]      [frontier]          [frontier]      [frontier]
Nigeria                     [frontier]      [frontier]          [frontier]      [frontier]
Tanzania                    [frontier]      [frontier]          [frontier]      [frontier]
Uganda                      [frontier]      [frontier]          [frontier]      [frontier]

               Number of candidate instruments, K: 1  2  3  5  10  20  40  60  84
               Blue solid: selected training partial correlation
               Copper dashed: same instrument in held-out data
```

**Specific graphical instructions:**

- Use the **same data underlying the four existing frontiers**, not a pooled six-country curve. Retain all 84 candidate metrics/products, the original K grid, fixed candidate orderings, and medians across splits.
- Do not plot all six countries in one axis: twelve overlapping curves per panel would obscure the result. Country should remain a row, not a color.
- One country label per row on the left, four clearly identified column headers, one two-item legend at the bottom. No repeated figure-level title inside the PDF; LaTeX supplies the caption.
- One common y-axis range across all 24 country-model cells, chosen to contain both training and held-out correlations. Mark zero with a thin gray solid line. Use the same log(K) horizontal scale everywhere. Draw x tick labels only along the bottom row and y ticks only on the first column where possible.
- Combined appendix figure: **plot the median lines without 10th–90th percentile bands** to preserve legibility. Preserve the four standalone PDF plots with their descriptive bands as optional diagnostic files; do not automatically include redundant standalone figures in the manuscript appendix. The note must make clear that these are medians over repeated geographically grouped partitions, not precision-adjusted confidence intervals.
- Avoid visual competition between FE/outcome headers and country labels. Target readable labels at the **actual** size of a 0.97-`\linewidth` landscape figure, not just in a full-screen preview. If a four-column six-row matrix fails a print-size legibility test, rework spacing and tick labels rather than shrinking all text further.

**Appendix-figure deliverable:** `front_panel.pdf` and `front_panel.png` under `$data/results_data/figures/metric_paper/`. Keep the four original standalone frontier PDFs. No `front_t_*` or `front_choice_*` output.

### Appendix Figure B: Spatial dependence and first-stage inference, TWO panels

**Decision:** Use **two**, not three, panels in the **appendix figure**. The left panel establishes the spatial dependence mechanism; the right panel shows its inferential consequence. The `|t|>4.81` plot is less informative visually because the spatially adjusted rates are nearly zero. Summarize its numeric results in an accompanying **appendix table or note**, not as a third panel. Do not add a separate spatial figure to the main text.

```text
┌──────────────────────────────────────┬─────────────────────────────┐
│ (A) Dependence in first-stage scores │ (B) Share with |t| > 1.96   │
│                                      │                             │
│ Ethiopia           Malawi            │ Ethiopia     ◆─────●        │
│ [distance plot]    [distance plot]   │ Malawi       ◆────●          │
│ Niger              Nigeria           │ Niger        ◆────●          │
│ [distance plot]    [distance plot]   │ Nigeria      ◆────●          │
│ Tanzania           Uganda            │ Tanzania      ◆──●           │
│ [distance plot]    [distance plot]   │ Uganda       ◆─────●         │
│                                      │                             │
│ Distance between EAs (km)            │ Share of specifications (%) │
└──────────────────────────────────────┴─────────────────────────────┘
```

(The connector positions in this ASCII layout are schematic, **not** estimates.)

- **Panel A (approximately 60% width):** Reformat `space_score` as a **2-column × 3-row** country grid rather than the existing 3 × 2. Keep total rainfall and rainy-days series, the five current distance bins, a common vertical range, and a zero reference line. Place its two-series legend once below Panel A. Label the y-axis precisely **"Mean Standardized Score Cross-Product"** (the measure is not a Pearson correlation).
- **Panel B (approximately 40% width):** Reformat `space_share` as the existing six-country horizontal dumbbell chart, with household-clustered estimates (blue circles) and 100-km spatial estimates (copper diamonds), connected by light gray lines. Use a common 0–70% x-axis unless updated estimates exceed that range; do not automatically crop values. Include only `reg2` (year + household FE) in Panel B. Keep a two-item legend below Panel B.
- These panels have **different visual density**. Do not force them into equal-width columns or vertically stack two unreformatted full-width PDFs. Compose vector output from the Stata component graphs with a reproducible PDF assembly step (or reproduce the two unequal-width panels in one LaTeX figure). Do not rasterize the PDF panels to create the combined PDF.
- Panel A shows *score dependence*, not rainfall autocorrelation; Panel B shows *threshold-crossing frequencies*, not a formal test of the difference between two frequencies.

**Appendix-figure deliverable:** `space_panel.pdf` and `space_panel.png` in the manuscript figures folder. Retain `space_share481.pdf` as an auxiliary output, but do not insert it as a separate appendix figure unless the numerical table or note proves inadequate. Figure notes and any appendix text must report the actual percentages from `spatial_shares.csv`, not estimates read from the PDF.

### Required style match to the existing Cloudy figures

Review the **actual paper-style scripts read-only before plotting**: `analysis/viz_code/metric_style.do`, `metric_palette.do`, and the relevant sections of `metric_coeff_vis.do` and `metric_sum_vis.do`. Reuse their Stata conventions rather than introducing a new plotting aesthetic. **Do not run `metric_coeff_vis.do`**, because it also generates existing paper figures:

- `scheme(stcolor)`; white graph and plot backgrounds; dark gray axes/labels (`"38 43 47"`); thin **solid** pale gridlines (`"242 244 246"` or the established equivalent); no colorful backgrounds, thick grids, outer boxes, or artificial drop shadows.
- The canonical colors include ARC2 blue (`"40 86 154"`) and ERA5 copper (`"194 123 65"`). For these figures they distinguish **two statistical objects**, not remote sensing products: keep the legend explicit to prevent product confusion. Blue = training/household clustering/seasonal rainfall; copper = held-out/spatial adjustment/rainy days. Preserve line patterns and marker shapes as additional cues for black-and-white printing.
- Country order: Ethiopia, Malawi, Niger, Nigeria, Tanzania, Uganda. Labels/ticks, legend size, line width, and margins should visually match the existing `strength_dist`, `coef_precision`, `all_v01`, and `all_v12` PDFs at print size. Keep panel designations (A), (B), etc., but **no overarching graphic title or interpretation inside the image**.
- Export vector PDFs and approximately 3,200-pixel-wide PNG previews. All labels and legends must remain legible when the complete figure is included in LaTeX at `width=.97\linewidth` inside the user's existing `landscape`/`figure`/`minipage` structure. Visually inspect the final PDF **at that printed width**, including panel headers and legend alignment.

## 2. Exhibit 2: additional computation and validation

**Existing sources:**

- `$data/results_data/additional_evidence/exhibit2/selection_frontier.dta`
- `selected_instruments.dta`, `front_increment.csv`, `front_table.csv`, `split_audit.csv`, `sample_audit.csv`, and `baseline_comparison.csv`
- Code: `analysis/reg_code/metric_front.do`, `metric_front.mata`, `metric_fe.mata`, `analysis/viz_code/metric_front_vis.do`

### 2A. Quantify *incremental* selection optimism, not only the total training–validation gap

For every identical **country × outcome × allocation × held-out fold × candidate ordering × selection rule** comparison, define

```text
G(K) = absolute training partial correlation of the selected instrument
       − sign(training partial correlation) × held-out partial correlation

Increment = G(84) − G(1)
FE contrast = Increment(year + household FE) − Increment(year FE)
```

Use exactly the **same** split and random candidate ordering when pairing the FE models. This pairing is already supported by the recorded seeds, but verify it before collapsing.

Generate `front_increment_comparison.csv` with country, outcome, FE specification, median increment, 10th and 90th percentiles across the independent split units used for descriptive visualization, K=1/K=84 median gaps, sign of increment, valid comparisons, and the paired FE contrast. Report medians across fold/allocation summaries rather than treating the 20 orderings from a given held-out fold as independent observations. A positive `G(84)-G(1)` is evidence of **additional selection-related in-sample optimism** beyond the K=1 baseline; the raw `G(84)` alone is not sufficient because geographically held-out estimates may differ even when K=1.

Create a **small optional appendix diagnostic dot plot** (`front_increment.pdf`, `.png`) with six country rows, a zero line, and paired maize/value results showing the FE contrast. Include it as a separate appendix figure only if the actual estimates add information not readily visible in Appendix Figure A; otherwise retain the CSV and plot as supporting analysis. Do not make it an additional panel of the composite figure.

### 2B. Integrity checks

1. Confirm 84 unique metric-product candidates in every country/outcome common sample; unchanged outcome transforms; 20 allocations × 5 folds; 20 nested candidate orderings per fold; and unchanged estimates under a repeated deterministic run.
2. Confirm no household or connected EA-wave group appears in both training and validation. Document explicitly that these are geographically **grouped** splits, *not* distance-buffered spatial validation; avoid calling any gap a pure causal estimate of p-hacking.
3. Reproduce all K=1,10,84 plotted medians from `selected_instruments.dta` and check `G(84)-G(1)` from raw matched orderings. Confirm training maximum absolute partial correlation is nondecreasing in K within every individual ordering.
4. Audit sample exclusions and the few undefined candidates/validations. Report valid denominators; never recode an undefined held-out correlation to zero. Distinguish sample-driven changes from deviations from the published first-stage estimates.
5. Check that each column of `front_panel` draws the correct `spec` (`reg7` year FE; `reg2` year + household FE) and outcome (`lntf_yld` production value; `lncp_yld` maize). Check common y-axis bounds and comparison orientation.
6. Keep descriptive bands in the four standalone diagnostic plots labeled as **10th–90th percentile dispersion across geographically grouped held-out partitions**, never as bootstrap confidence intervals.

## 3. Exhibit 3: additional computation and validation

**Existing sources:**

- `$data/results_data/additional_evidence/exhibit3/spatial_first_stage.dta`
- `spatial_shares.csv`, `score_summary.csv`, `geo_model_comparison.csv`, `geo_merge_audit.csv`, and `geo_inventory.csv`
- Code: `analysis/reg_code/metric_geo.do`, `metric_geo.csv`, `metric_space.do`, `metric_space.mata`, `metric_fe.mata`, and `analysis/viz_code/metric_space_vis.do`

### 3A. Decompose the variance increase into within-EA and between-EA contributions

The code already stores `omega_hh`, `omega_within_ea`, `omega_pair100`, `xx`, and `correction`. For **each existing matched regression**, calculate three variance estimates using exactly the same coefficient and observation sample:

```text
V_HH        = correction × omega_hh / xx²
V_HH+EA     = correction × (omega_hh + omega_within_ea) / xx²
V_Spatial100= correction × (omega_hh + omega_within_ea + omega_pair100) / xx²
```

Preserve the raw signed covariance additions: a covariance component can be negative. Do not truncate negative components, invent variance shares that add mechanically to 100%, or take a square root of a nonpositive estimate. Flag nonpositive variances and report the denominator of estimable specifications.

Output `spatial_variance_components.csv` with the three SEs, absolute t-statistics, additive variance terms, SE ratios, indicator for `|t|>1.96`/`4.81`, country, outcome, FE specification, metric/product, and counts. Create `spatial_components_summary.csv` reporting **country-level threshold shares** at each of the three steps. This establishes whether the first-stage inference changes mostly because households share an EA or because shocks remain correlated across **distinct** nearby EAs.

An optional appendix visualization (`space_components.pdf`, `.png`) may use three horizontal dots per country (HH only; HH+EA; full spatial) for the share exceeding 1.96, but only if it provides a clearer decomposition than the summary table. **Do not add it as a third panel of Appendix Figure B.** If informative, it may appear as a separate appendix figure; otherwise retain the table only.

### 3B. Bandwidth, temporal, and sample-composition audit

Using the **same matched estimation sample** in each comparison:

1. Recompute country/outcome/FE shares with `|t|>1.96` and `|t|>4.81` for household clustering and 50-, 100-, 200-km spatial covariance, plus the already coded 100-km adjacent-interval sensitivity.
2. Save `spatial_bandwidth_audit.csv`: attempted specifications, successful matched specifications, bad/nonpositive variances, mean/median SE ratios, and threshold shares. Show both `reg2` and `reg7`, with each outcome separately as well as the pooled country-level shares. Report where the direction or size of the inference change depends on bandwidth or added adjacent-interval dependence.
3. Verify primary 100-km shares against the attached `space_share`/`space_share481` figures using the saved numeric output. Confirm that Panel B's HH and spatial percentages always use exactly the same 168 candidate specifications per country (or transparently report a different matched denominator if one arises).
4. Compare baseline original regressions and the **georeferenced common sample** in `geo_model_comparison.csv`: N, households, coefficients, HH SE, and t-statistics. Separate change due to **dropping ungeoreferenced observations** from change due solely to the **covariance estimator**. Highlight the larger geography restrictions in Tanzania and Uganda; retain country-wave coverage in an appendix audit.
5. Validate the 2019/20 Tanzania SDD linkage added in commit `567c3c1`: 168 newly located analysis observations (120 from 2012 and 48 from 2008), same-current-EA administrative key requirements, no incorrect duplication or carried-forward coordinates for movers, and correct handling of unavailable data. The released modified coordinates are the intended working geography: **do not introduce a GPS-displacement simulation or measurement-error exercise**.
6. Independently confirm a small prespecified subset of `reg2` and `reg7` coefficients and household SEs against direct Stata and verify the spatial covariance summations on a hand-checkable synthetic example, including within-EA pairs, 100-km neighbors, serial household dependence, and adjacent-interval subtraction. Document the actual test output instead of claiming checks were passed without running them.

## 4. Appendix layout and LaTeX handoff

Export **two combined appendix-figure PDFs** (plus PNG previews): `front_panel` and `space_panel`. These are intended to be placed in an appendix section, not the main results section. Retain the four standalone frontiers with dispersion bands, `space_share481`, and any validated component/selection-gap diagnostics as auxiliary reproducibility files; they should not all be inserted as extra figures without demonstrated incremental value. **Do not edit, renumber, or replace any main-text figures.**

Prepare **appendix-only** LaTeX blocks following the paper's existing structure: `landscape` → `figure[!htbp]` → `minipage{\linewidth}` → `\caption{}` and `\label{}` → centered `\includegraphics[width=.97\linewidth,keepaspectratio]{Figures/<name>.pdf}` → `\footnotesize \textit{Note}: ...`. Do not put the paper's main title or explanatory notes inside the PDF. Escape LaTeX special characters (e.g., `\%`). Use ordinary `\caption{}` (letting the manuscript's appendix setup supply appendix figure numbering) and distinct appendix labels such as `\label{app:front_panel}` and `\label{app:space_panel}`. Do not assign main-text figure numbers, change existing labels, or add main-text citations to these appendices. Draft captions and notes grounded in the **verified** estimates; distinguish descriptive across-fold dispersion from statistical confidence intervals and describe the spatial working covariance structure accurately.

Recommended **appendix figure** titles for those LaTeX blocks:

- **Figure A:** `First-Stage Instrument Selection In and Out of Sample`
- **Figure B:** `Spatial Dependence and First-Stage Instrument Strength`

Suggested panel labels for Figure A: `(A) Production value: Year FE`; `(B) Production value: Year + household FE`; `(C) Maize yield: Year FE`; `(D) Maize yield: Year + household FE`. Figure B: `(A) Spatial dependence in first-stage scores`; `(B) Share with |t| > 1.96`.

## 5. Deliverables and acceptance criteria

**Code edits:** Prefer adding appendix-specific plotting/audit scripts or make minimal edits to `analysis/viz_code/metric_front_vis.do` and `metric_space_vis.do`. Add short reusable computational do/Mata routines only if the saved results are insufficient; avoid modifying already-validated estimator logic. Update `analysis/metric_front.md` and `metric_space.md` with exact commands, definitions, appendix figure names, and audit results. Do not alter or run unrelated visualization or bootstrap scripts.

**Combined appendix figures:**

- `$data/results_data/figures/metric_paper/front_panel.pdf` and `.png`
- `$data/results_data/figures/metric_paper/space_panel.pdf` and `.png`

**Supporting outputs (appendix tables/notes where warranted; otherwise reproducibility files):**

- Exhibit 2: `front_increment_comparison.csv`, optional `front_increment.pdf`/`.png`, refreshed descriptive `front_table.csv` and audits.
- Exhibit 3: `spatial_variance_components.csv`, `spatial_components_summary.csv`, `spatial_bandwidth_audit.csv`, optional `space_components.pdf`/`.png`; preserve `space_share481.pdf` as an auxiliary reproducibility file.
- `additional_exhibits_QA.md` summarizing counts, comparisons, failed checks, data restrictions, interpretation, and the commands used to reproduce both composite PDFs.
- Two LaTeX-ready figure blocks (in a `.tex` handoff file), with verified appendix notes and labels consistent with the manuscript.

**Do not declare the work complete until:**

1. The new combined figures reproduce the four original frontiers and the two chosen spatial quantities exactly, apart from intentional layout changes.
2. The frontiers use the same K axis, same y scale, correct FE/outcome labels, unchanged country order, and a single legend. Visual inspection at actual manuscript landscape width confirms legibility.
3. The spatial figure's first panel shows **first-stage score cross-products**, not rainfall correlations, and the second uses identical paired samples. The plotted values agree with the audit CSV to graph-rounding precision.
4. Geographic joins are one-to-one at the required keys, valid and invalid counts are explicit, and the 50/100/200-km results are checked for stability.
5. The within-EA/between-EA decomposition algebraically reproduces the existing 100-km spatial variances. No variance component is silently truncated.
6. Neither removed clustered-t/choice-frequency figures nor a coordinate-displacement analysis is generated.
7. No existing main-text figure, caption, number, or narrative is changed, and the protected bootstrap heat-map files and calculations are left entirely untouched.
8. Both combined exhibits, their appendix-only LaTeX blocks, and supporting audit files are delivered and visually verified.

**Prioritize:** correctness and identification logic first, then clear visual comparisons, then minimal code churn. If any new result fails validation, document the failure and stop short of appendix claims based on that result. The protected bootstrap heat map is out of scope regardless of the outcome of these checks.
