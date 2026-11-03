# Appendix payoff figures: 3 Nov 2026 update

<!-- edited by: codex; edited on: 3 Nov 2026 -->

The paired search-gain arrows replace the incremental-gap forest plot. The
training-versus-held-out scatter is retained as the alternative for review.
The approved frontier remains unchanged. Spatial Panel B gains small neutral
arrowheads from household-clustered circles to spatial squares; its existing
gray circles, red squares, axes and panel arrangement are preserved.

## Reproduction

With the existing project globals established:

```stata
do "$code/analysis/viz_code/metric_app_fit.do" keepfront
```

Then run:

```text
python analysis/viz_code/metric_app_fit.py "<project data directory>" --keep-front
```

The argument is the directory represented by `$data`. Add
`--pdftoppm "<Poppler executable>"` if it is not on PATH. Both keep-front
options preserve the approved frontier files. No new dependency is needed.
The scripts edited are `metric_app_fit.do`, `metric_app_fit.py`, and the
appendix-only handoff `metric_app.tex`; the frontier/spatial READMEs link here.

The Stata log is
`$data/results_data/additional_evidence/appendix/metric_app_fit.log`.
The plotting run completed successfully on 3 November 2026. No estimation,
bootstrap, or unrelated visualization script was run.

## Data and summaries

Payoffs use saved `exhibit2/selected_instruments.dta`, primary selection rule 1.
The fit measure is unchanged: absolute training partial correlation, and
held-out partial correlation oriented by the selected instrument's training
sign. For each country/outcome/FE/allocation/fold/ordering, each gain is
`fit(84)-fit(1)`. Training and held-out gains use the same jointly valid pair
of candidate-set endpoints; undefined held-out fits are not set to zero.

First take medians over 20 candidate orderings within a fold, then medians
and **IQRs (25th-75th percentiles)** across 100 allocation/fold summaries.
These are descriptive spread intervals, not confidence intervals; repeated
folds reuse observations. This is not the earlier difference between FE gap
increments, nor a coefficient or IV estimate.

`appendix/front_payoff_values.csv` contains all 24 country/outcome/FE rows:
both median gains, their four IQR endpoints, valid/attempted pairs, valid
splits and plot limits. Both candidate figures read this same CSV. All cells
have 100 valid split summaries and 2,000 attempted ordering pairs. Valid pairs
are 2,000 except Niger:

| Outcome | Year FE | Year + Household FE |
|---|---:|---:|
| Farm Production Value | 1,996 | 1,993 |
| Maize Quantity | 1,995 | 1,992 |

The paired-arrow range is -0.08 to 0.23, containing every IQR endpoint
(-0.0551482 to 0.2039247) with 8% padding and outward rounding. Blue denotes
year FE; orange denotes year plus household FE. Filled/open circles identify
training/held-out gains. Solid/dashed bars identify their respective IQRs.
Arrowheads point from training to held-out; near-equal endpoints naturally
overlap rather than being moved apart. All 24 training medians exceed the
corresponding held-out medians; two household-FE held-out medians are negative.
This is descriptive evidence, not a test of differences.

The scatter uses square plot regions and identical -0.02 to 0.20 x/y ranges,
so its reference is exactly y=x and physically 45 degrees. Country abbreviations
are placed with short leaders while avoiding other labels and markers.
Whiskers are omitted from the scatter to keep the 12 points per panel readable.
Panel A is farm production value and Panel B is maize quantity in both candidates.
Outcome variables and transformations are unchanged.

Spatial components still use `exhibit3/score_summary.dta` and the matched
reg2 rows in `spatial_first_stage.dta`. The 60 score values and 12 outcome
shares retain their existing CSVs, with 84 matched specifications per
country/outcome. Physical-size arrowheads are added in the PDF assembly,
outside the endpoint markers. No data, marker, scale or spacing is changed.

## Executed checks and decision

- Recomputed all 48 payoff medians and 96 IQR endpoints directly from the
  saved selected-instrument records, with errors below 1e-9; pair counts match.
- Verified six countries, two outcomes, reg7/year FE and reg2/year-plus-household
  FE, paired K=1/K=84 endpoints, and all valid-split denominators before export.
- Confirmed the approved frontier PDF and PNG are byte-identical by SHA-256.
  Its bands, colors, legend and axes are preserved.
- Confirmed both spatial value CSVs are byte-identical. Panel A renders
  pixel-identically at 100 dpi; arrowheads point from HH circles to spatial
  squares in Panel B, with the existing 0-90% axis and markers.
- Checked the new arrow directions against the actual training/held-out values;
  both candidates use the same 24 summary rows and exact FE palette.
- Exported single-page vector PDFs with no raster image objects and 3,200-pixel
  PNG previews; reviewed the figures at their actual landscape inclusion sizes.

The letter-paper, one-inch-margin LaTeX proof compiled successfully without
overfull boxes. The selected payoff graphic prints at about 8.73 x 4.93 inches;
the spatial graphic retains its 7.24 x 5.35-inch inclusion size. Captions and
notes remain outside the images. Both payoff candidates use panel letters
only, with the outcome definitions supplied in the handoff note.

Final files under `$data/results_data/figures/metric_paper/`:

| Figure | Native PDF Canvas | PNG Preview | Use |
|---|---|---|---|
| `front_panel_fit` | 11.5 x 8.0 in | Unchanged | Approved Frontier |
| `front_payoff_arrows` | 11.5 x 6.5 in | 3,200 x 1,809 px | Selected Replacement |
| `front_payoff_scatter` | 11.5 x 6.3 in | 3,200 x 1,754 px | Review Alternative |
| `space_panel_revised` | 11.5 x 8.5 in | 3,200 x 2,366 px | Directional Comparison |

The arrow figure tells the training-to-held-out story clearly while retaining
the IQRs. It is therefore selected in `metric_app.tex`. The old forest is no
longer generated or included. Main-text figures and the protected bootstrap
heat map and workflow remain untouched. Earlier detailed audits remain in
`additional_exhibits_QA.md` and `appendix_figures_redesign_QA.md` as dated records.
