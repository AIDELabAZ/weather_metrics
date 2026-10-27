# Codex implementation plan: Redesign Cloudy Figures 2 and 3

**Project:** *Cloudy With A Chance of Significance: Specification Search and the Illusion of Exogeneity in Remotely Sensed Weather Data*  
**Repository:** `AIDELabAZ/weather_metrics`  
**Primary Stata file:** `analysis/viz_code/metric_sum.do`  
**Scope:** Figure 2 (`all_v01`) and Figure 3 (`all_v12`) only  
**Status:** Implementation specification. Do not treat this document as evidence that code has been changed or tested.

## 1. Task and nonnegotiable constraints

Restyle the two existing descriptive figures to match the clean visual language of the prototype figures `rainfall_FE_coefficient_precision_prototype` and `rainfall_FE_strength_distribution_prototype`. The result should be suitable for insertion into a LaTeX manuscript at journal publication size.

**The exported figure image must NOT contain a figure title, subtitle, figure number, bottom note, caption, source note, or interpretive prose.** Those elements belong exclusively in LaTeX. The figure **may and should** include country/panel headings, axis titles, tick labels, one shared legend, and reference lines when they directly serve interpretation. Do not reserve blank space for a missing title or note.

- This is a **visual redesign**, not a change in descriptive statistics, sampling, geographic coverage, years, extraction methods, or interpretation.
- Retain the time-series line-chart form. Do not convert these figures to boxplots, distributions, or a different statistic.
- Preserve the six-country, three-column by two-row arrangement and the series for all six remote-sensing products.
- Preserve existing filenames, Stata globals, data-directory mappings, and paths. The directory restructuring is handled separately. **Do not modify** regression code, `projectdo.do`, or the 12 other rainfall-metric figures as part of this task.
- Follow repository `AGENTS.md` and the existing Stata 18 house style. Make a focused change on a feature branch. Do not combine this work with unrelated merge-conflict resolution or a repo-wide reformat.
- Do not modify a manuscript `.tex` file as part of the figure-code task. Suggested LaTeX text appears at the end of this brief for review, not automatic insertion.

## 2. Current figures and source code (verified)

The October 26, 2026 manuscript PDF shows these figures on PDF pages 34 and 35, respectively. Section 3.3 explains that the analysis computes the **country-year mean of each rainfall metric** and plots it across six remote-sensing products.

| Manuscript figure | Meaning | Stata series | Six-panel export | Individual panel examples |
|---|---|---|---|---|
| Figure 2 | Mean daily rainfall during the growing season, in millimeters | `mean_season_` | `all_v01.png`, `all_v01.eps` | `eth_v01.gph`, `mwi_v01.gph` |
| Figure 3 | Share of growing-season days with rain, in percent | `percent_raindays_` | `all_v12.png`, `all_v12.eps` | `eth_v12.gph`, `mwi_v12.gph` |

**Exact source:** `analysis/viz_code/metric_sum.do`. The country blocks are Sections 2-7; the combined exports are in Section 8. In the current file, each country has its own `twoway line` graph and `graph combine` joins six graphs with `col(3)`. Countries are ordered Ethiopia, Malawi, Niger, Nigeria, Tanzania, Uganda. The script uses extraction-specific input files matching `*_x3_rf*.dta`, collapses to `by(year sat)`, and converts `percent_raindays_` to percentage units by multiplying by 100. Keep that source-data and transformation logic unchanged.

The present charts include six separate legends (one under each panel), overly small text after combination, and relatively saturated/inconsistent colors. The redesign should remove these presentational problems while preserving the plotted observations.

## 3. Shared visual specification

Create a small reusable style helper, suggested path `analysis/viz_code/cloudy_graph_style.do`. It should define **style only** (colors, text/line sizes, graph-region defaults, legend settings); it must not read, merge, collapse, or alter data. If the repo already has an equivalent graph-style helper, reuse it rather than adding a duplicate. Do not impose new third-party dependencies unless already installed.

### Palette

Match the prototypes' restrained teal/copper identity, extending it to **six distinct product colors**. Two colors alone cannot distinguish the six time-series lines.

| Product | Suggested color | Hex | RGB for Stata |
|---|---|---|---|
| CHIRPS | Teal | `#237E8F` | `35 126 143` |
| CPC | Muted copper/ochre | `#C27B45` | `194 123 69` |
| MERRA-2 | Slate blue | `#5D7795` | `93 119 149` |
| ARC2 | Charcoal/slate | `#58636B` | `88 99 107` |
| ERA5 | Muted plum | `#9C7698` | `156 118 152` |
| TAMSAT | Muted olive | `#7F916B` | `127 145 107` |

Neutrals: white background `#FFFFFF`; dark text/axes `#262B2F`; unobtrusive grid `#E7EAED`; secondary labeling `#70777D`. These are explicit implementation defaults, not claims that the prior PNG used precisely these RGB values. The two principal hues should remain visually close to the supplied prototypes.

Use **one stable color and line-pattern mapping per product** in both figures and all country panels; include different line patterns as a secondary identifier so lines remain distinguishable in grayscale. Keep stroke widths consistent and thick enough to survive reduction in LaTeX (approximately 0.8-1.1 pt at final size; tune against rendered previews). No point markers on annual series. Avoid a Stata rainbow scheme, shaded panel backgrounds, heavy gridlines, thick boxes, and decorative separators.

### Layout and labeling

- White graph and plot backgrounds with no visible surrounding box; restrained left/bottom axes and very light horizontal gridlines (not a full grid lattice).
- **Six country panels in a 3 x 2 grid**, aligned, with compact **bold country names** only. These country names are panel identifiers, **not figure titles**.
- **One shared legend** for the six remote-sensing products, preferably centered below the six panels (or immediately above them if markedly clearer). Never repeat the legend six times. The shared legend is permitted; a bottom explanatory note is not.
- Give the data panels most of the available export area. Avoid the large top/bottom margins of the current paper graphics. Ensure panel text remains legible at the actual size used in LaTeX.
- Preserve the chronological year axis, including the full observation range (currently displayed as 1983-2017). Use aligned, legible x-axis ticks across panels, e.g. approximately every five years; do not interpolate missing years or alter data coverage. It is acceptable to show x-axis labels primarily on the bottom row if the meaning remains unambiguous.
- Use concise axis titles and tick labels. It is acceptable to reduce repeated axis titles where the six-panel figure has a clearly readable shared axis label; do not remove the unit of measurement.
- Prefer a **vector PDF** for LaTeX plus high-resolution PNG for review. Preserve legacy EPS output if used by the existing manuscript and retain canonical filenames. Produce review previews before replacing canonical outputs.

## 4. Figure-specific instructions

### Figure 2: Mean daily rainfall (`all_v01`)

**Retain** the plotted annual country mean `mean_season_`, six rainfall products, six countries, and temporal coverage. Y-axis unit: **mm per day**; recommended concise axis title is `Mean daily rainfall (mm)`.

Country-specific y-axis scales currently differ substantially (roughly 0-3 in Niger versus 0-12 in Nigeria). Retain independent, clearly labeled country scales in the first redesign rather than silently imposing a common scale. Readers primarily need to compare products and time variation **within** each country. If a shared scale is proposed as an alternative, provide a separate preview, not a replacement.

Keep the six annual time series visually separate with stable product colors and supplemental line patterns. Do not add trends, smoothers, confidence bands, averages across products, or new reference lines.

### Figure 3: Share of rainy days (`all_v12`)

**Retain** the plotted annual country mean `percent_raindays_` and the existing multiplication by 100; do not multiply by 100 twice. Units are **percent**, and rainy days correspond to the original metric definition (at least 1 mm of rain). Recommended y-axis title: `Share of rainy days (%)`.

**Use the same 0-100% y-axis across all six country panels**, with readable major ticks (e.g. 0, 20, 40, 60, 80, 100). Identical limits here support direct cross-country comparison and prevent the visually misleading rescaling of proportions. Retain the same year-axis layout, country order, legend, product colors, and visual treatment as Figure 2.

## 5. Critical preflight: verify product-label mapping

Before final export, **trace the `rf1`-`rf6` identifiers to the actual input dataset provenance**. The existing code is inconsistent:

- `analysis/viz_code/metric_sum.do` currently labels `rf1` as **CHIRPS**, `rf2` as **CPC**, `rf3` as **MERRA-2**, `rf4` as **ARC2**, `rf5` as **ERA5**, and `rf6` as **TAMSAT**.
- `ethiopia/household_code/eth_append_built.do` maps rainfall variable suffixes as `rf1` **ARC2**, `rf2` **CHIRPS**, `rf3` **CPC**, `rf4` **ERA5**, `rf5` **MERRA-2**, and `rf6` **TAMSAT**.

These code paths may refer to different file-generation conventions. **Do not assume either mapping is correct just because it appears in a label definition.** Check the original extracted file names, their creation code, and/or documented provenance to establish which product each `*_x3_rf*.dta` contains. If the discrepancy is real, report it to the researcher and propose the correction **separately** from the aesthetic redesign; do not silently change legends or series assignments. Do not finalize misleading product labels.

## 6. Implementation sequence

1. **Confirm branch and environment.** Read `AGENTS.md`, inspect current `analysis/viz_code/metric_sum.do` on the branch to be edited, identify output directory globals and the current `all_v01`/`all_v12` graphs. Create an isolated feature branch. Do not change the directory-migration work in other branches.
2. **Record the baseline.** If source data are accessible, save existing Figure 2 and 3 exports for visual comparison and record the country-year-product observations and values underlying each. Do not rerun unrelated regression code.
3. **Verify labels** as specified in Section 5. Raise the discrepancy before finalizing if unresolved.
4. **Implement a reusable style helper.** Keep the exact product-to-color/pattern mapping in one place; restrict changes to the two targeted metrics and graph-combination logic. Do not restyle the remaining 12 metrics yet.
5. **Restyle 12 country panels**: six for `v01`, six for `v12`. Keep data identical; use white backgrounds, bold country headings, readable axes and product lines; remove individual legends where combining panels.
6. **Build two 3 x 2 composites** with **one shared six-product legend** each. Prefer the repository's existing graph-combination workflow; use `grc1leg2` only if it is already installed and works correctly, or another Stata-native method that preserves country-specific axes and one legend. Avoid converting the underlying descriptive dataset to a different aggregation merely to obtain a shared legend.
7. **Export review files**, such as `all_v01_redesign.pdf`/`.png` and `all_v12_redesign.pdf`/`.png`, alongside existing outputs. Use a large PNG width (about 2800-3600 px) and check vector PDF rendering. On approval, retain the canonical `all_v01`/`all_v12` output names in the reproducible script, with EPS where necessary for legacy compilation.
8. **Document and test.** Render both graphs, inspect at manuscript insertion size, validate series equality to the baseline, then commit a focused diff and report exactly what was modified. Do not alter LaTeX captions without a separate instruction.

## 7. Acceptance criteria

- [ ] The result consists of **exactly two redesigned manuscript composites**: Figure 2 (`all_v01`) and Figure 3 (`all_v12`), with six country panels each.
- [ ] **No embedded figure titles, subtitles, figure numbers, explanatory bottom notes, or captions.** Country/panel names, axis titles and labels, and the product legend are retained.
- [ ] The six-product legend appears **once per composite**, not once per country.
- [ ] Consistent muted palette and line-pattern assignments across both figures, with teal and copper as anchor colors.
- [ ] Figure 2 retains sensible **country-specific** y-axis limits in mm; Figure 3 uses a **common 0-100%** y-axis.
- [ ] Identical country/year/product values and sample coverage compared with the original figures; no changes to `collapse`, `duplicates`, extraction, percentage conversion, or underlying rainfall data.
- [ ] The product identifier mapping has been verified against actual source-file provenance, or explicitly flagged as unresolved (never silently relabeled).
- [ ] PDFs look crisp in the manuscript; PNGs are legible when reduced to actual LaTeX size; no clipped country headers, legend items, axis labels, or panel data.
- [ ] No unrelated Stata files, other rainfall-metric charts, data paths, or `.tex` files changed.
- [ ] If data or Stata are not accessible, report **static-only review** and do not claim plots were generated or numerical equivalence was established.

## 8. Suggested LaTeX text (separate from figure images; do not auto-insert)

These are editorial suggestions. Verify the sample years and the interpretation of `x3` before publication.

**Figure 2 title:** *Mean Daily Rainfall Across Remote Sensing Products*  
**Optional subtitle:** *Country-level time series, 1983-2017*  
**Proposed figure note:** “Each panel reports annual country means of growing-season mean daily rainfall from six remotely sensed precipitation products. Values are measured in millimeters per day. Vertical scales differ across countries.”

**Figure 3 title:** *Share of Rainy Days Across Remote Sensing Products*  
**Optional subtitle:** *Country-level time series, 1983-2017*  
**Proposed figure note:** “Each panel reports annual country means of the share of growing-season days with at least 1 mm of rain, measured as a percentage. All panels use a common 0-100% scale.”

All of the text in this section belongs in the **LaTeX caption/note system**, not in the exported figures.

## 9. What Codex should return

- A focused PR or commit containing the style helper (if created) and narrowly scoped changes to `analysis/viz_code/metric_sum.do`.
- Two PDF and PNG figure previews, or a clear explanation of why execution was not possible.
- A short validation report: data/series unchanged, product labels verified or flagged, output dimensions, and any required Stata graph package.
- A brief list of the separate proposed LaTeX figure titles/subtitles/notes. **No LaTeX edits unless expressly requested.**

**Suggested Codex prompt:** “Read `AGENTS.md` and this implementation plan. Redesign only the current Cloudy Figures 2 and 3 in `analysis/viz_code/metric_sum.do`. Follow the exact aesthetic and no-embedded-caption constraints, verify remote-sensing product labels, generate review previews if Stata/data are available, and report a focused diff. Do not touch unrelated code, data paths, or the manuscript.”
