# Appendix exhibit redesign plan for Codex

## Goal
Revise the appendix-only additional-evidence exhibits so that they (i) match the visual language of the paper, (ii) use space efficiently, (iii) make the substantive message immediately legible, and (iv) preserve the underlying empirical content. This plan covers all three items discussed most recently:

1. keep `front_panel_fit.pdf` as-is,
2. revise `space_panel_revised.pdf` only by adding directional arrows,
3. replace `front_increment_forest.pdf` with a new figure, while also generating one alternative candidate figure for review.

Do **not** modify the bootstrap heatmap or any main-text figures.

---

## General style requirements
Apply these requirements to all revised appendix exhibits.

- Match the style of the figures already in the paper.
- No figure title, subtitle, or note inside the image itself.
- Use the same font family, line weights, and general theme already used in the current paper figures.
- Use light, solid gridlines.
- Avoid excessive panel spacing and avoid unused axis range.
- Keep margins tight so the plotted content fills the page well.
- Use consistent color semantics across related appendix exhibits:
  - **Year FE** = blue
  - **Year + household FE** = orange
- If training and held-out quantities both appear in the same figure, distinguish them by marker fill / line treatment, **not** by introducing a new color mapping.
- Do not recycle the same color-shape combination to mean different things within the same figure.
- Output PDF files with publication-friendly dimensions and efficient use of an 8.5x11 landscape page.

---

## Part I. `front_panel_fit.pdf`

### Decision
Keep this figure unchanged.

### Codex task
- Do **not** redesign `front_panel_fit.pdf`.
- Only touch the code if necessary for cleanup or refactoring.
- If the script is refactored, verify that the exported figure is visually identical to the current approved version.

### Verification
- Same number of panels, same data, same confidence bands, same legend, same axis ranges, same colors.
- No accidental dropping of confidence bands.

---

## Part II. `space_panel_revised.pdf`

### Decision
Retain the current layout and content. Add directional arrows so the reader can immediately see that each comparison moves from the blue dot to the red square.

### Codex task
Revise the code that produces `space_panel_revised.pdf` as follows:

1. **Keep the current panel structure and data unchanged.**
2. In the panel where blue dots are connected to red squares, add **small arrowheads** to the connectors.
3. Arrows should point:
   - **from the blue dot**
   - **to the red square**
4. The connectors should remain visually secondary to the endpoints.
5. Arrowheads should be large enough to read in print, but not so large that they clutter the panel.
6. Do not expand the axis range or panel spacing.

### Recommended implementation details
- Keep endpoint markers exactly as they are now.
- Use a neutral connector color or the current connector color.
- Draw arrowheads behind or beneath the endpoint markers so the markers remain visually crisp.
- If there is any panel that does not involve a blue-dot to red-square comparison, do not add arrows there.

### Verification
- The revised panel should read directionally at a glance.
- The arrows should not materially change the current look of the figure.
- The figure should remain compact and readable at the same page size now used.

---

## Part III. Replace `front_increment_forest.pdf`

### Problem with the current figure
`front_increment_forest.pdf` is not effective. The point estimates are visually near zero, the figure uses too much space for too little information, and the plot does not make the substantive message obvious. The replacement figure should directly show the core claim:

> searching over more candidate rainfall instruments can improve apparent fit in training data, but those gains do not necessarily survive in held-out data.

The replacement should use the same underlying split-based results already created for the frontier exhibits.

---

## Part III-A. Preferred replacement: paired search-gain arrows

### Output
Create a new candidate figure, e.g. `front_payoff_arrows.pdf`.

### What the figure should show
For each **country** and each **fixed-effects specification**:
- compute the gain from searching over more instruments in the **training** data,
- compute the corresponding gain in the **held-out** data,
- plot those two gains as a pair and connect them with an arrow.

This should be done separately for the two outcomes.

### Quantities to compute
For each outcome, country, split, and FE specification, use the same fit statistic already used in `front_panel_fit.pdf`. Do **not** redefine the fit metric.

Let:
- `fit_train(k)` = training fit when the search considers the top `k` candidate instruments,
- `fit_holdout(k)` = held-out fit for the same selected instrument.

Then compute:

- `delta_train = fit_train(84) - fit_train(1)`
- `delta_holdout = fit_holdout(84) - fit_holdout(1)`

where 84 is the full candidate set already used in the frontier exercise, and 1 is the no-search baseline.

If the underlying exercise uses a slightly different maximum than 84 because of filtering, use the actual maximum used in the final frontier code, but keep the concept identical.

### How to summarize across splits
For each country x FE specification x outcome:
- compute the **median** of `delta_train` across repeated splits,
- compute the **median** of `delta_holdout` across repeated splits,
- compute descriptive dispersion for each quantity across splits.

Use **IQR** (25th to 75th percentile) as the default descriptive spread. If IQR is too visually tiny, use 10th to 90th percentiles, but label this clearly in the code comments.

These are **descriptive spread intervals**, not confidence intervals.

### Layout
- One figure with **two panels**:
  - Panel A: farm production value
  - Panel B: maize quantity
- Within each panel:
  - y-axis = country
  - x-axis = search gain in fit
  - each country has two FE rows or two slightly offset FE entries:
    - Year FE (blue)
    - Year + household FE (orange)
- For each country x FE entry:
  - plot the **training gain** as a filled circle,
  - plot the **held-out gain** as an open circle,
  - connect them with an arrow from training to held-out,
  - add horizontal dispersion bars for both if they remain readable.

### Visual encoding
- Color encodes FE specification only:
  - blue = Year FE
  - orange = Year + household FE
- Marker fill encodes sample type:
  - filled = training
  - open = held-out
- Arrow direction goes from training to held-out.

### Sizing and spacing
This is critical.

- Use a landscape page efficiently.
- Avoid large empty space to the right of the largest point.
- Determine x-axis range from the empirical min/max of the summarized gains.
- Add only about 5\% to 10\% padding on each side.
- If all gains are positive, the left bound can be set slightly below zero for context.
- If some held-out gains are negative, extend just enough left to show them cleanly.
- Increase the vertical space devoted to the plotted rows so the country labels and FE offsets are easy to read.
- Keep panel gap modest.

### What this figure is meant to communicate
The immediate visual story should be:
- training gains are often larger than held-out gains,
- the gap between them is the amount by which apparent payoffs to searching fail to generalize,
- this can differ across FE specifications and across outcomes.

### Verification checks
Codex should explicitly verify:
1. that `delta_train` and `delta_holdout` are computed from the same split and same candidate-search routine,
2. that the fit statistic matches the one used in `front_panel_fit.pdf`,
3. that the arrow direction runs from training to held-out,
4. that the figure remains readable when printed on an 8.5x11 landscape page.

---

## Part III-B. Alternative candidate: training-gain vs held-out-gain scatter

### Output
Create a second candidate figure, e.g. `front_payoff_scatter.pdf`.

### Purpose
This is an alternative visualization in case the paired-arrow figure is less effective with the actual data.

### What the figure should show
For each country and FE specification, plot:
- x-axis = median `delta_train`
- y-axis = median `delta_holdout`

using the same `delta_train` and `delta_holdout` definitions above.

### Layout
- One figure with **two panels**:
  - Panel A: farm production value
  - Panel B: maize quantity
- One point per country x FE specification in each panel.

### Visual encoding
- Color encodes FE specification only:
  - blue = Year FE
  - orange = Year + household FE
- Use direct text labels for countries if feasible.
- If direct labels create overlap, use simple country abbreviations and repel labels.
- Add a **45-degree reference line**.

### Optional uncertainty display
If visually feasible, add:
- horizontal whiskers for the spread of `delta_train` across splits,
- vertical whiskers for the spread of `delta_holdout` across splits.

Do this only if the panel remains readable. If whiskers create clutter, drop them.

### Sizing and spacing
- Make the plotted region close to square within each panel.
- Set x and y limits tightly around the actual data with modest padding.
- Include zero on both axes if it helps interpret whether gains are positive.
- Keep panel spacing tight.

### What this figure is meant to communicate
Points below the 45-degree line indicate that apparent gains in training exceed gains in held-out data. The farther below the line, the less the search payoff generalizes.

### Verification checks
Codex should explicitly verify:
1. that the same summarized data feed both the paired-arrow figure and the scatter figure,
2. that the 45-degree line is correctly defined,
3. that country labels are legible and do not collide badly.

---

## Part IV. Data and code checks
Codex should add explicit checks in the code before exporting the new figures.

### Required checks
1. Confirm that the summarized frontier data are built from the correct underlying split-level results.
2. Confirm that the number of countries and outcomes matches the intended design.
3. Confirm that the FE labels are correct:
   - Year FE
   - Year + household FE
4. Confirm that the search range uses the intended baseline (`k = 1`) and final candidate set (`k = 84`, or the actual full-search maximum if filtered).
5. Confirm that no confidence bands are dropped from `front_panel_fit.pdf`.
6. Confirm that the new appendix figures use the same approved blue/orange FE palette.
7. Confirm that the arrow directions in `space_panel_revised.pdf` and `front_payoff_arrows.pdf` are correct.

---

## Part V. Deliverables
Codex should produce:

1. the updated `space_panel_revised.pdf` with directional arrows,
2. the unchanged but re-verified `front_panel_fit.pdf`,
3. the new preferred figure `front_payoff_arrows.pdf`,
4. the new alternative figure `front_payoff_scatter.pdf`,
5. a short log or README note stating:
   - which scripts were edited,
   - what data objects feed each figure,
   - what checks were run,
   - whether the spread intervals are IQR or 10th--90th percentile.

---

## Part VI. Decision rule after generation
After generating the figures:

- If `front_payoff_arrows.pdf` tells the story clearly, use it and discard the old forest plot.
- If the paired-arrow figure is too messy but the scatter makes the pattern obvious, use `front_payoff_scatter.pdf` instead.
- If neither figure is compelling with the actual data, drop the increment exhibit entirely rather than keep an uninformative graphic.

