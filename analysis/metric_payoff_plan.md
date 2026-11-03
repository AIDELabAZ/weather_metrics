# Implementation plan for Codex

## Goal
Create a new appendix exhibit that replaces the current `front_payoff_scatter` idea with a more interpretable plot of **selection optimism**, and clean up spacing in the existing `space_panel_revised` and `front_panel_fit` figures so labels, titles, and legends are less cramped.

This plan has two parts:

1. **Build a new payoff figure** that directly plots the quantity we care about.
2. **Revise figure spacing/layout** in `space_panel_revised` and `front_panel_fit` without changing their substantive content.

---

## Part I. Replace the payoff scatter with a direct plot of selection optimism

### A. Substantive target
The current payoff scatter is too indirect. It asks the reader to compare the distance of points from a 45-degree line, which is hard to see and hard to interpret.

Instead, directly plot **selection optimism**:

\[
\text{Selection optimism}
=
\bigl[R_{\text{train}}(84)-R_{\text{train}}(1)\bigr]
-
\bigl[R_{\text{heldout}}(84)-R_{\text{heldout}}(1)\bigr]
\]

Interpretation:
- A value near **0** means the gains from searching over many rainfall metrics largely generalize out of sample.
- A **positive** value means the in-sample payoff to search is larger than the out-of-sample payoff, i.e. evidence of selection optimism / overfitting.
- Larger positive values imply more scope for selective inference.

### B. Figure design
Create a new figure, tentatively named:
- output file: `front_payoff_levels.pdf`
- code section name: `payoff levels` or `selection optimism paired-dot plot`

Use a **two-panel paired-dot plot**:
- **Panel A:** farm production value
- **Panel B:** maize yield

Within each panel:
- One horizontal row per country:
  - Ethiopia
  - Malawi
  - Niger
  - Nigeria
  - Tanzania
  - Uganda
- Plot **two points per country**:
  - **Year FE**
  - **Year + household FE**
- Connect the two points with a thin horizontal segment so the reader immediately sees how the quantity changes when household FE are added.
- Add a vertical reference line at **0**.

This should be a **landscape-friendly appendix figure** that uses space efficiently. Do **not** spread 12 points across an almost empty full-width page.

### C. Recommended encoding
Use the same visual language already used elsewhere in the paper:
- Keep the figure background, line weights, and typography consistent with `front_panel_fit` and `space_panel_revised`.
- Use only two specification colors, consistent across the paper:
  - **Year FE** = blue/teal family already used in the first-stage figures.
  - **Year + household FE** = orange/rust family already used in the first-stage figures.
- Use the **same meaning of color everywhere in this figure**.
- Avoid introducing new symbol meanings that conflict with other appendix exhibits.

Suggested marks:
- Year FE: filled circle
- Year + household FE: filled square
- Thin gray connector line between the two points for each country

### D. Dispersion / uncertainty
This figure should not just plot point estimates.

For each country-specification-outcome combination, compute and plot a measure of dispersion around the selection-optimism estimate. Preferred order:

1. **Interquartile range (IQR)** across repeated sample splits / resamples, if the underlying frontier routine stores split-level results.
2. If available and computationally sensible, use **10th-90th percentile whiskers** instead of or in addition to IQR.
3. If split-level information is not stored, compute and plot a simpler descriptive spread using whatever repeated frontier values are already generated internally.

Do **not** fabricate conventional confidence intervals if the underlying routine does not support them. This is a descriptive appendix exhibit.

Visually:
- Plot a horizontal whisker or linerange for each dot.
- Keep whiskers thin and understated.
- The dot should remain visually primary.

### E. Computation details Codex should verify
Codex should verify exactly how the existing frontier objects are built before computing the new quantity.

For each outcome and FE specification:
1. Recover the frontier results used to make `front_panel_fit`.
2. Verify the number of candidate instruments searched over is **84** (14 rainfall metrics × 6 remote sensing products).
3. Define the baseline **1** consistently with the frontier code.
   - If `R(1)` means the expected fit when choosing a single instrument without search, preserve that exact definition.
   - If the existing code uses a different baseline (e.g. first draw, random draw mean, or order-statistic baseline), preserve that logic and document it in comments.
4. Compute, for each repeated split or simulation draw:
   - training gain = `R_train(84) - R_train(1)`
   - heldout gain = `R_test(84) - R_test(1)` (or the held-out analog actually used)
   - selection optimism = training gain − heldout gain
5. Aggregate to the displayed country-level point estimate using the median or mean. Preferred default: **median** if the distribution is skewed; otherwise mean is fine.
6. Store a tidy dataset with variables like:
   - `country`
   - `outcome`
   - `spec` (year FE vs year + hh FE)
   - `optimism_center`
   - `optimism_p25`
   - `optimism_p75`
   - optional `optimism_p10`, `optimism_p90`

### F. Axis sizing and layout
This is crucial. The figure should be compact and readable, not dominated by white space.

#### Y-axis
- Use the six countries as discrete rows.
- Keep row spacing tight but readable.
- Make sure country labels have enough left margin.

#### X-axis
Codex should **inspect the realized range in the data first**, then set a tight common x-range across both panels.

Default guidance:
- Choose a symmetric or near-symmetric range around zero if the data permit.
- Add only about **5\% to 10\% padding** beyond the min/max displayed values.
- Do **not** let Stata choose a wide default range that leaves half the figure blank.

If the realized optimism values are all positive and fairly concentrated, e.g. something like 0 to 0.12, then use something like:
- x-range = `0` to a value just above the maximum
- keep the zero line visible at the left boundary.

If they straddle zero, use a centered range, e.g. `-0.02` to `0.12` or similar, based on actual values.

#### Panel arrangement
- Arrange the two panels **side-by-side** if they remain readable.
- If side-by-side makes the country labels too cramped, switch to **stacked panels**.
- Preferred default: **stacked panels** in the appendix, because it gives more vertical room for country labels and uncertainty whiskers.

### G. Titles, labels, legend
No in-figure title if the paper style omits titles. But keep clean axis titles.

Suggested axis text:
- x-axis: `Selection optimism in first-stage fit`
- subtitle in notes can define it as the training gain minus held-out gain from searching over rainfall instruments.

Legend:
- only two entries:
  - `Year FE`
  - `Year + household FE`
- place the legend at the bottom, centered, with enough separation from the x-axis title.
- increase legend spacing so it does not crowd the axis title.

### H. If the resulting figure is still weak
Codex should save the paired-dot plot even if it is not visually dramatic. But if the resulting estimates are essentially all near zero with overlapping spreads and the figure carries no clear message, note that in comments so we can decide whether to drop it.

---

## Part II. Improve spacing and buffer in `space_panel_revised` and `front_panel_fit`

The current complaint is not about the substantive content. It is about **cramped spacing**:
- axis labels too close to tick labels
- axis titles too close to panel content
- legends too close to axis titles
- overall layout feels compressed

Codex should revise both figures with the specific goal of creating more breathing room.

### A. General layout rules
Apply these rules to both `space_panel_revised` and `front_panel_fit`:

1. **Increase plot margins** around each panel.
2. **Increase outer graph margins**, especially:
   - bottom margin for x-axis title + legend
   - left margin for y-axis titles and long tick labels
3. **Increase the gap between axis tick labels and axis titles**.
4. **Increase the gap between the plotted region and the legend**.
5. **Reduce dead white space caused by loose axis ranges**, while still preserving a small visual buffer.

### B. Specific instructions for `space_panel_revised`
This figure is already close to working. Keep the content and structure, but improve readability.

#### Content to preserve
- Keep the revised direction arrows from blue dots to red squares.
- Keep the same basic panel content.
- Keep the same substantive variables.

#### Spacing fixes
- Increase space between panel A/B/C plotting regions and the shared legend.
- Increase bottom margin so the x-axis title does not collide with the legend.
- Increase left margin so the y-axis titles and country labels are easier to read.
- If panel labels (`A`, `B`, etc.) are used, give them a bit more padding from the plotting area.

#### Axis range discipline
- Tighten ranges to the realized data values with small padding only.
- Do not use broad default ranges that create excess empty space.

### C. Specific instructions for `front_panel_fit`
This figure is also conceptually strong, but it looks cramped.

#### Content to preserve
- Preserve the confidence bands.
- Preserve the frontier logic.
- Preserve the comparison between training and held-out fit.

#### Spacing fixes
- Increase vertical space between panels if needed.
- Increase separation between x-axis tick labels and x-axis title.
- Increase separation between x-axis title and legend.
- Increase left margin so y-axis titles fit comfortably.
- If the figure has a shared legend, push it slightly lower and center it cleanly.

#### Axis range discipline
- Keep x-axis limits tight to the support of the frontier curves.
- Avoid long flat stretches of empty axis space.
- Use only modest padding at the ends.

---

## Part III. Style consistency with the paper
For all revised appendix figures, make them look like they belong with the existing paper figures.

### A. Match existing style
Use the same overall house style already established in the paper:
- same font family and general sizing hierarchy
- same background treatment
- same solid/light gridline treatment
- same line thickness conventions
- same legend styling
- same country ordering

### B. Avoid style conflicts
- Do not reuse the same color/symbol combination to mean different things within the same figure.
- Within a figure, one visual encoding should have one meaning only.
- Keep the number of legend dimensions small.

### C. Output
Save publication-ready PDFs and any intermediate tidy datasets if helpful.

Suggested outputs:
- `front_payoff_levels.pdf`
- updated `front_panel_fit.pdf`
- updated `space_panel_revised.pdf`

If code organization matters, add the new payoff plot to the existing appendix exhibit script rather than creating a disconnected one-off script, unless the current file structure strongly suggests a separate plotting module.

---

## Deliverables for Codex
1. Revised code that generates the new paired-dot **selection optimism** figure.
2. Revised code for `space_panel_revised` with more spacing/buffer and preserved arrows.
3. Revised code for `front_panel_fit` with more spacing/buffer and preserved confidence bands.
4. A short note in comments documenting:
   - how selection optimism is defined in the code,
   - what summary statistic is plotted,
   - what uncertainty/spread measure is plotted,
   - and any decisions about axis ranges.
