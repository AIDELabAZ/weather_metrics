# Codex to-do: Final appendix figure revisions

**Scope:** Only three additional-evidence appendix figures. Use the latest `front_panel_fit(1).pdf`, `front_payoff_arrows.pdf`, and `space_panel_revised(2).pdf` as the visual starting points. Do not revise the underlying regressions, data selection, first-stage estimates, bootstrap procedures, or existing main-text figures. In particular, **do not modify, rerun, or reanalyze `boot_heat.pdf` or any underlying coefficient-change bootstrap.** Do not restore the deleted clustered-t selection or choice-frequency figures.

## 0. Short filenames and consistent terminology

Export the final PDFs and PNG previews using short filenames, and update **appendix-only** LaTeX references accordingly:

| Existing file | Final file | Purpose |
|---|---|---|
| `front_panel_fit.pdf` | **`front.pdf`** | Selection frontiers |
| `front_payoff_arrows.pdf` | **`gain.pdf`** | Training and held-out gains from search |
| `space_panel_revised.pdf` | **`space.pdf`** | First-stage spatial dependence and significance |

Do not keep producing suffixed files such as `_revised`, `_fit`, `_arrows`, or `(2)`. After verifying the three final files and their appendix references, remove superseded figure PDF/PNG exports from the project OneDrive output directory using the cleanup procedure in Section 6. Preserve unrelated and protected paper figures.

**Outcome vocabulary:** The existing paper's specification charts label the two dependent-variable categories **Quantity** and **Value**. Use **Quantity** for the maize-yield outcome and **Value** for farm production value in the panel headings of all three figures. In the figure note, define the labels once. Do not mix “Maize,” “Maize Yield,” “Maize Quantity,” “Farm Production Value,” and “Value” unpredictably across figures.

**Typography and capitalization:**

- **Bold panel headings**, including `(A)` / `(B)` and the accompanying outcome or panel description.
- **Do not bold** axis titles, axis tick labels, or country/tile titles.
- Use lowercase **“of”** in every label or title (not `Of`), unless starting the phrase. Prefer consistent sentence case in axes.
- Use **`km`**, never `Km` or `KM`.
- Do not add a redundant overall figure title inside the image; the LaTeX caption provides that title.
- Retain the current paper style: white background, subtle solid gridlines, dark-gray text, and the existing blue/orange fixed-effects palette.
- Use carefully measured whitespace. Axis tick labels, axis titles, legends, panel headings, and adjacent panels must not collide or appear crowded. Check them at the *final printed size*, not just at 100% zoom.

## 1. `front.pdf`: Reorder tiles into outcome blocks

**Preserve all data, lines, percentile bands, FE specifications, axis ranges and tick marks.** This is a rearrangement and text-formatting change, not a new analysis.

Build the same 12 frontier plots in a **3-row x 4-column grid**, grouped by outcome rather than country-outcome pairs:

| Row | Panel A, column 1: Quantity | Panel A, column 2: Quantity | Panel B, column 3: Value | Panel B, column 4: Value |
|---|---|---|---|---|
| 1 | Ethiopia | Malawi | Ethiopia | Malawi |
| 2 | Niger | Nigeria | Niger | Nigeria |
| 3 | Tanzania | Uganda | Tanzania | Uganda |

- Add **bold** block headings above the respective six-tile groups: **`(A) Quantity`** and **`(B) Value`**.
- Each individual tile title is **only the country name, not bold**. Remove `· Value`, `· Maize`, or similar suffixes.
- Align left and right outcome blocks. Use one modest gutter separating the blocks, but do not create excessive inter-panel white space. The title-to-tile gap should be modest, and every small multiple should be large enough to read.
- Preserve **common x and y scales** across all 12 small multiples, preserving comparable vertical magnitudes. Preserve the **existing descriptive dispersion ribbons** (do not drop or regenerate as invented confidence intervals).
- Set the **shared x-axis title exactly** to: **`Number of K Candidate Instruments`**. Preserve the current K tick locations and log scaling. Keep the existing y-axis title (first-stage partial correlation) unless required for typography.
- Preserve blue = year FE and orange = year + household FE; solid = training and dashed = held-out.
- Leave visible, noncramped gaps (roughly 6–10 pt at final size) between tick labels and axis titles, and between axis titles and legends. Make room by adjusting the overall layout, *not* by clipping text or shrinking it until illegible.
- Export `front.pdf` and `front.png`. The PDF must remain legible on a full landscape appendix page.

## 2. `gain.pdf`: Return to paired training-to-held-out arrows

**Use `front_payoff_arrows.pdf` as the starting design. Discontinue `front_payoff_levels.pdf`, `front_payoff_scatter.pdf`, and `front_increment_forest.pdf` as final exhibit candidates.**

### What the figure displays

For a given country, outcome, FE model, split, and candidate ordering, define the gain when the available candidate set grows from one rainfall instrument to all 84:

\[
\Delta_{\mathrm{train}} = R_{\mathrm{train}}(84)-R_{\mathrm{train}}(1), \qquad
\Delta_{\mathrm{heldout}} = R_{\mathrm{heldout}}(84)-R_{\mathrm{heldout}}(1).
\]

Use the **same first-stage partial-correlation statistic**, chosen-in-training instrument, split definitions, and candidate orderings as `front.pdf`. Compute paired differences at the split/ordering level **before** reporting medians and descriptive intervals. Do not change the estimation or selection algorithm.

- **Filled circles** = training gain.
- **Open circles** = held-out gain.
- **Blue** = year FE.
- **Orange** = year + household FE.
- A subtle arrow points **from the filled training circle to the open held-out circle**, with its arrowhead visible even for short segments.
- The separation between circles shows how much of the apparent training gain survives out-of-sample; this distinction, not an abstract “optimism” score, is the figure's purpose.

### Layout, titles and axis

- Show two side-by-side panels with complete, **bold** headings: **`(A) Quantity`** and **`(B) Value`**, in that order, to match `front.pdf`.
- The six country names appear in each panel, **not bold**, and in the usual order: Ethiopia, Malawi, Niger, Nigeria, Tanzania, Uganda.
- Keep the compact paired-arrow design and the currently sensible axis range. Do not add large empty margins.
- Replace the vague x-axis title with **`Change in First-Stage Partial Correlation`**. This states the **unit** directly: an absolute difference in correlation coefficients (e.g., 0.05 correlation units), *not* 5% and not a change in t-statistics. Do **not** expand the axis title with “searching 84 rather than 1 instrument”; that belongs only in the appendix text and figure note.
- Use one shared x-axis title and a shared legend, with **additional vertical buffer** between x-axis tick labels, the x-axis title, and the legend. Target 6–10 pt clear separation between adjacent text bounding boxes at final printed size; prioritize legibility over cramming everything into a small bottom strip.
- Explicitly identify both visual dimensions in the legend: blue/orange FE specification, and filled/open training/held-out circles. Keep it on at most two compact rows if needed.

### Make the two dispersion intervals unambiguous

The current intervals can look detached or misaligned with the markers. **A marker must sit exactly on the horizontal centerline of its own interval.** Do not vertically offset dots above or below the line and do not offset the interval away from its dot.

Distinguish the two *overlapping* descriptive intervals for each FE-country pair by **different physical heights** rather than displacing their centers:

- Draw the **training** interval first, with a taller capped whisker (for example, ~8 pt total cap height at final size).
- Draw the **held-out** interval on top, with a shorter capped whisker (for example, ~4 pt total cap height).
- Keep the horizontal interval strokes slim and in the same FE color as the corresponding dot. Consider reducing opacity on the taller interval so the shorter one remains visible.
- Both whiskers remain centered on the same FE-country y-coordinate, and both markers lie on that coordinate. Their x positions and endpoints come from their **own respective estimates and quantiles**. Never alter their numerical endpoints to make the intervals literally nest; differing cap heights are only a visual distinction.
- If whiskers still visually merge, use a *very small* shared vertical offset between **FE pairs** (blue/orange), not between a dot and its own interval, and retain the country row grouping.

**Statistical language:** The saved intervals are descriptive percentiles across geographically grouped held-out exercises, **not conventional 95% confidence intervals**. Preserve the existing percentile definition or explicitly document whether it is IQR or p10–p90; do not label these intervals CIs or imply inferential significance.

### Figure note (outside image)

Define (i) Quantity and Value, (ii) K=1 and K=84, (iii) the calculation as an absolute change in the partial-correlation coefficient, (iv) the filled/open symbol distinction and arrow direction, and (v) the descriptive percentile interval and unit of replication. The note may be detailed; the axis must stay short.

Export `gain.pdf` and `gain.png`.

## 3. `space.pdf`: Improve arrows, markers and labels

Preserve the existing **two-panel structure** and the underlying first-stage spatial results. Do not alter estimates, distance bins, bandwidths, significance thresholds, panels, or numerical axis ranges.

### Panel A: score dependence by distance

- Use a complete **bold** heading: **`(A) First-stage score dependence by distance`**.
- The current y-axis phrase **`Mean Standardized First-Stage Score Cross-Product`** is needlessly technical. Replace it with **`First-Stage Score Dependence`**. The figure note should explain that each plotted value is the mean product of standardized first-stage scores for pairs of EAs in the indicated distance bin. “Cross-product” is mathematically descriptive but does not add useful interpretive information on the axis.
- Do not replace the value with a differently computed correlation or covariance merely to simplify the label.
- Keep the existing tight, **country-specific vertical ranges**, because these make short-distance differences legible. Do not impose a common 0–0.3 y-range.
- Remove circles from this figure entirely. For the two measures in Panel A use **upward triangles for seasonal rainfall** and **downward triangles for rainy days** (or two other distinct, unused noncircular shapes). Retain the existing line/color distinction.
- Country titles **not bold**. Correct `Km` to `km` in the distance axis/title and all related legends/notes.

### Panel B: spatially adjusted significance

- Use a complete **bold** heading: **`(B) Outcome-specific first-stage significance`**.
- Use **diamonds for household-clustered SEs** and **squares for spatial SEs (100 km)**. Neither series may use circles. Keep the existing two endpoint colors and the comparison's meaning.
- Use the **same short outcome titles** as `front.pdf`: **Quantity** and **Value** (not alternating between “Maize Yield”, “Farm Production Value”, and abbreviated labels). Use consistent ordering, preferably Quantity first, Value second.
- Darken the direction arrows substantially: use a medium-to-dark neutral gray (approximately RGB 75/80/85), medium line width, and a distinct arrowhead around two-thirds of the way from the household-clustered diamond toward the spatial square. For all comparisons, arrow direction must be **household-clustered → spatial** (often right-to-left); place the arrowhead on the segment, not tucked beneath the square.
- Do not use the same marker shape in Panel A for one concept and Panel B for an unrelated concept: triangle-up/triangle-down in A; diamond/square in B.
- Keep the current buffer between panels, axes, titles, and legends; fix any residual crowding without adding large dead margins.
- Use lowercase **`of`** and **`km`** consistently, including the x-axis title and spatial SE legend.

Export `space.pdf` and `space.png`.

## 4. QA and deliverables

1. Verify outcome coding against the manuscript and existing specification-chart axes: **Quantity = maize yield; Value = farm production value**. If there is any discrepancy in existing code labels, document and resolve the mapping before export.
2. Verify the four `front.pdf` series and the percentile bands are unchanged numerically after rearrangement.
3. Verify `gain.pdf` uses the same paired exercises at K=1 and K=84; training and held-out gains must be computed before aggregation. Confirm each dot sits on its own interval and interval endpoints/quantiles are unchanged.
4. Verify spatial arrow directions and markers in a full-resolution rendered page. Make the arrowheads recognizable at ordinary appendix print size.
5. Confirm all panel headings are **bold** and all axis titles, tick labels, and country/tile titles are **not bold**; check lowercase `of` and `km` everywhere.
6. Inspect exported PNGs and PDFs side by side at final intended appendix insertion width; fix collisions, clipping, crowded axis-to-legend spacing, excessive whitespace, and mismatched legend descriptions.
7. Update **appendix-only** LaTeX figure paths and notes to `front.pdf`, `gain.pdf`, and `space.pdf`. No edits to main-text figures, no bootstrap re-estimation or revalidation, and no changes to `boot_heat.pdf` or its code/results.
8. Provide a short QA summary identifying scripts changed, output files, data sources, and any remaining visual limitations.
9. Complete the visualization-code consolidation, targeted OneDrive cleanup, and `analysis`-branch push described in Sections 5–7. These are part of this task, not optional follow-up work.


## 5. Consolidate the appendix visualization code into `metric_app_vis.do`

**Required final source:** `analysis/viz_code/metric_app_vis.do` (one standalone Stata visualization script for all three appendix figures).

Use the actual repository house style as the template, particularly `analysis/viz_code/metric_coeff_vis.do` (the repository spelling is `coeff`, not `coef`) and `metric_sum_vis.do`. Their conventions are authoritative. The script must be readable, sequential, commented, and independently executable **after** `projectdo.do` establishes project globals and the requisite saved estimation data exist.

### 5.1. Standard header, paths, logging, and shared style

Start with the same concise header fields as the other visualization scripts: project, created/edited dates and authors, Stata version, `does`, `assumes`, and `TO DO`. Follow the established section delimiter syntax `**********************************************************************` and `**#` / `**##`, with **`**# 0 - setup`** first.

**In the preamble define the paths and open the log using the house conventions**. The existing `metric_coeff_vis.do` uses `$root`, `$xfig`, and `$logout` globals; `projectdo.do` establishes `$data` and `$code` and creates output directories. Mirror the working project patterns; do not hard-code a username or an absolute local/OneDrive path:

```stata
**********************************************************************
**# 0 - setup
**********************************************************************

* define paths
    global root     "$data/results_data"
    global xfig     "$root/figures/metric_paper"
    global logout   "$root/logs"

* saved inputs for the three appendix plots
    local front     "$root/additional_evidence/exhibit2"
    local space     "$root/additional_evidence/exhibit3"
    local appendix  "$root/additional_evidence/appendix"

* open one log for the complete visualization script
    cap log close
    log using "$logout/metric_app_vis.log", text replace

* one shared style include; metric_style.do already includes metric_palette.do
    include "$code/analysis/viz_code/metric_style.do"
```

This is a **structure example**, not permission to overwrite globals needed elsewhere. Check the actual scripts and `projectdo.do` first; adjust the locations only if the existing repository conventions require it. Close the log **once at the end** (`log close`). Do not create several per-figure logs in auxiliary scripts. Avoid duplicated palette/style definitions: `metric_style.do` already includes `metric_palette.do`.

### 5.2. No subsidiary scripts or external assembly

`metric_app_vis.do` must be **self-contained** for figure preparation, reshaping/aggregation of saved results, graph construction, layout, and exports. It may only `include` the shared `metric_palette.do` and/or `metric_style.do` (loading `metric_style.do` alone normally suffices).

**Forbidden from `metric_app_vis.do`:**

- `do`, `run`, or `include` of any other `.do` file, notably `metric_app.do`, `metric_app_fit.do`, `metric_front_vis.do`, `metric_space_vis.do`, or `metric_app_check.do`;
- generating and executing temporary/subsidiary `.do` files;
- calling out to Python (`metric_app.py`, `metric_app_fit.py`, etc.), shell commands, or another figure-assembly application;
- writing intermediate per-tile PDF/PNG fragments solely to reassemble them in a second language;
- running the full original model-estimation code as a side effect of making figures.

Use standard Stata graph construction and **in-memory named graphs / `graph combine`**, as appropriate, so `metric_app_vis.do` can create and export **`front.pdf`, `gain.pdf`, `space.pdf` and their PNG previews directly**. Use `tempfile`, temporary variables, `preserve`/`restore`, and locals to keep scratch data transient rather than cluttering OneDrive. Store a minimal tidy plotting dataset only when it is actually needed for documentation or verification, not as an intermediary for an external plotting language.

### 5.3. Clear top-to-bottom program structure

Use approximately this section structure, aligned with the repository's numbering conventions:

```text
0 - setup (paths, single log, shared style, useful locals)
1 - validate saved exhibit inputs and build common plotting summaries
2 - selection frontiers: Quantity and Value blocks -> front.pdf/png
3 - training/held-out search gains and dispersion -> gain.pdf/png
4 - first-stage score dependence and significance -> space.pdf/png
5 - final consistency checks and log close
```

Do not over-engineer a separate package of helper programs or do-files. Within these sections, include short comments that explain non-obvious choices: how candidate orderings are paired, how percentiles are aggregated, how marker/whisker heights are drawn, and how arrowheads are placed. Use the user's exact labels, punctuation, casing, and marker rules from Sections 0–4 above.

**Separate visualization from estimation.** Start from saved, previously validated data in `exhibit2` and `exhibit3`; perform only the minimal grouping/collapsing needed to plot the existing quantities. Do not rerun/re-estimate the first stages, the weather regressions, or bootstrap. Keep `boot_heat.pdf`, its data, and bootstrap code completely untouched.

### 5.4. In-script verification and fail-fast behavior

- Assert required saved input files and variables exist and have expected country/outcome/specification coverage.
- Assert the 84-instrument candidate grid and correctly matched K=1/K=84 ordering/fold keys for `gain.pdf`.
- Verify the 10th--90th descriptive frontier bands and the saved source values; do not relabel these as confidence intervals.
- Check the displayed Quantity/Value definitions and medians/percentiles against the previously saved exhibit summaries.
- Check that the spatial percentage denominators and 100 km adjustment match the saved results.
- Do not suppress errors with `capture` except for harmless cleanup such as `cap log close`.
- Produce the three **final** PDF/PNG pairs in a single complete execution, with no extra ``preview-v2`` outputs or figure fragments.
- Review all three final-size PDF renders; typography, whitespace, legends, markers, and arrowheads must match Sections 0–4.

## 6. Remove obsolete appendix helper scripts and OneDrive graphics

**First inventory; then delete after the single-script replacement is tested.** The current `metric-exhibits` branch contains Codex-created files including:

- `analysis/viz_code/metric_app.do`
- `analysis/viz_code/metric_app_fit.do`
- `analysis/viz_code/metric_app.py`
- `analysis/viz_code/metric_app_fit.py`
- `analysis/reg_code/metric_app_check.do`
- older `analysis/viz_code/metric_front_vis.do` and `metric_space_vis.do`

There is no `metric_app_vis.do` yet committed on the inspected remote branches; check whether Codex has already created it locally, and use that working file if present rather than discarding new work.

**Remove** `metric_app.do` and `metric_app_fit.do` after transferring any essential saved-result preparation into `metric_app_vis.do` and verifying the output. Remove their Python assembly helpers if no longer used. Inspect `metric_app_check.do`, `metric_front_vis.do`, and `metric_space_vis.do` before deleting: remove those **only if** their remaining purposes are entirely superseded and all necessary QA and downstream dependencies are preserved. The user requests removal of the redundant Codex-generated appendix-visualization `.do` files; do **not** indiscriminately remove unrelated Stata source or model-estimation programs. In particular, preserve `metric_coeff_vis.do`, `metric_sum_vis.do`, `metric_palette.do`, `metric_style.do` and any used regression-generation code.

### Targeted OneDrive graphic cleanup

The output location is the project-specific OneDrive path resolved through `projectdo.do`, normally **`$data/results_data/figures/metric_paper`**. After the final three PDF/PNG pairs are validated and appendix paths changed, inventory old graphics created by the appendix visualization exercise (for example `front_panel*.pdf/png`, `front_payoff*.pdf/png`, `front_increment*.pdf/png`, `space_panel*.pdf/png`, and unused per-tile composites). Remove only **unused, generated, superseded** `.pdf` and `.png` files from OneDrive; retain the authoritative `front`, `gain`, and `space` pairs. Check all manuscript/appendix `\includegraphics` paths and other references **before** removing any file. If an older graphic remains referenced or is used for an independently required exhibit, retain it and report why.

**Do not** run broad wildcard deletions over `metric_paper`. Especially protect **`boot_heat.pdf` and its PNG, every other main-text graphic, primary results/data files, and user-created material**. Intermediate output in `additional_evidence/appendix/components` or `.../fit` can be removed if it contains only disposable generated figure fragments and nothing is still consuming them. Record the names of removed scripts and graphics in the QA summary.

## 7. Integrate and push the finished work to the `analysis` branch

**Target repository:** `AIDELabAZ/weather_metrics`  
**Target branch:** `analysis` (not `metric-exhibits`, not `main`).

The inspected remote currently has both `analysis` and `metric-exhibits`, and some app-visualization sources exist only on `metric-exhibits`. Use the user's up-to-date local worktree as the source of truth. Move/cherry-pick **only the relevant approved source changes** into `analysis`; do not blindly merge unrelated or older experimentation.

Codex must:

1. Check `git status`, the current branch, and whether the local tree contains uncommitted work. Do not overwrite or lose existing changes.
2. Fetch and update the `analysis` branch safely (`git fetch`, then switch to `analysis` and fast-forward/reconcile as appropriate). No force push.
3. Place the final `analysis/viz_code/metric_app_vis.do` and any necessary appendix-only LaTeX/QA updates on `analysis`, and stage the explicit deletion of redundant helper files that were tracked on the source branch. Remove references to any deleted helper scripts in drivers/readmes, without altering non-appendix workflows.
4. Execute the **single** `metric_app_vis.do` using the existing saved data, inspect all three exported PDFs/PNGs at publication size, and verify the log exits cleanly. Check `git diff --check` and review the staged diff.
5. Commit the approved code/documentation and targeted tracked deletions with a descriptive message. Push using **`git push origin analysis`**; do not force push. Confirm the pushed commit SHA and remote branch. Ensure the OneDrive output cleanup described above is also complete.
6. In the final Codex response, report: the remote branch/SHA, the surviving source files, deleted `.do`/Python files, cleaned OneDrive graphics, generated PDF/PNG paths, and any items that could not be executed because data or OneDrive access was unavailable. Never state that the OneDrive cleanup or figure generation succeeded without directly verifying it.

**Definition of done:** The approved appendix changes are reproducible by running one house-style Stata visualization script, all three figure exports are verified and referenced consistently, obsolete appendix-specific helpers and unused OneDrive graphics are removed safely, and the committed work is present on remote `analysis`. The coefficient-change bootstrap and existing main-text exhibits are unchanged.