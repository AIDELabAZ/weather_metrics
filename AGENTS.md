# Agent guidance for `weather_metrics`

This repository supports reproducible research on remote-sensing weather data and agricultural outcomes. Most analysis is written in Stata 18.

## Scientific and coding conventions

- Follow the [lab's house style](https://jdavidm.github.io/learn-stata/materials/02-house-style/) in every file. Use documented, numbered and bookmarked sections, tabs for command/object alignment and nested blocks, readable continuation lines, and lowercase commands. Preserve case-sensitive data names and existing workflow structure. Apply style corrections without redesigning the workflow.

- Preserve existing estimation specifications, identifiers, output contracts, and historical replication behavior unless a task explicitly changes them. Distinguish historical specifications from newly proposed exploratory analyses.
- Use the repository's existing Stata style, country/weather/outcome loops, and long-format `postfile` workflow. Make targeted edits; avoid unrelated refactoring or new dependencies.
- In `analysis/reg_code/regressions.do`, the weather regressions use household-clustered standard errors (`vce(cluster hhid)`). Do not replace this with observation-level robust errors.
- The Cloudy rainfall comparison requires the **same year fixed effects and estimation observations** in both specifications. Historical `reg1` is rainfall only; `reg7` is rainfall plus year fixed effects; `reg2` is rainfall plus year and household fixed effects.
- Match paired estimates using country, outcome, and the **full original weather variable name** (e.g., `v05_rf1`), which identifies both rainfall metric and remote-sensing product. Keep a separate specification identifier.
- The relevant outcomes are `lntf_yld` and `lncp_yld`, with rainfall metrics `v01`-`v14` across products `rf1`-`rf6`. The current regression file does **not** loop over weather-extraction methods; do not add such a loop without explicit instruction.
- Keep regression estimation and saved metadata separate from downstream statistical transformations, figures, instrument-strength assessments, and the paired coefficient bootstrap. The bootstrap will require household-level panel data and resampling at household level; aggregate regression-result rows are not a valid bootstrap sampling unit.
- Leave current data-root globals, output filenames, and directory structure unchanged unless explicitly tasked. Paper-specific path migration is a separate future task.
- Do not commit raw LSMS microdata, private weather/location files, generated datasets, personal machine paths, or credentials.

## Implementation and verification

- Work on a feature branch based on `analysis`; prepare a reviewed change for merge into `analysis`. Do not modify `main`.
- Where possible, run the Stata file with the user's local panel dataset, check matching estimation samples, verify unique regression identifiers, and reconcile expected counts. If Stata or the data are unavailable, distinguish static checks from executed tests.
- Preserve the existing `reg_results.dta` and `lsms_complete_results.dta` output filenames.
- Report any unexpected exclusions, non-estimable weather coefficients, or schema changes rather than silently dropping rows.
