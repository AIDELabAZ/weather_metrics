# Cloudy With A Chance of Significance: Specification Search and the Illusion of Exogeneity in Remotely Sensed Weather Data

This repository contains code for replicating the statistical analysis in Michler, J.D., Josephson, A., Agme, C., and Kilic, T. (2026). "Cloudy With A Chance of Significance: Specification Search and the Illusion of Exogeneity in Remotely Sensed Weather Data." *Unpublished*.

This README was last updated on 26 October 2026.

 ## Index

 - [Project Team](#project-team)
 - [Data cleaning](#data-cleaning)
 - [Running the pipeline](#running-the-pipeline)
 - [Pre-requisites](#pre-requisites)
 - [Folder structure](#folder-structure)

## Project Team

Contributors:
* Jeffrey D. Michler [jdmichler@arizona.edu] (Conceptualizaiton, Analysis, Supervision, Visualization, Writing)
* Anna Josephson [aljosephson@arizona.edu] (Conceptualizaiton, Analysis, Supervision, Visualization, Writing)
* Talip Kilic (Conceptualization, Resources, Writing)
* Siobhan Murray (Conceptualization, Writing)
* Chandrakant Agme (Analysis, Visualization, Writing)
* Kieran Douglas (Analysis, Data curation)
* Brian McGreal (Data curation)
* Alison Conley (Data curation)
* Emil Kee-Tui (Data curation)
* Reece Branham (Data curation)
* Rodrigo Guerra Su (Data curation)
* Jacob Taylor (Data curation)

## Data cleaning

The code in this repository is primarily for replicating the cleaning of the household LSMS-ISA data. This requires downloading this repo and the household data from the World Bank webiste. The `projectdo.do` should then replicate the data cleaning process.

### Running the pipeline

`projectdo.do` is the entry point; `setup_paths.do` defines the shared inputs and
project-specific outputs. Run from the repository root in Stata 18 or newer:

```stata
do projectdo.do "" "" "setup"
do projectdo.do "" "" "packages"
do projectdo.do "" "" "metrics"
do projectdo.do "" "" "households"
do projectdo.do "" "" "panel"
do projectdo.do "" "" "regressions"
```

The arguments are the repository root, shared data root, and stage. Empty root
arguments use the current working directory and the `WEATHER_AGRICULTURE_DATA`
environment variable, respectively. If that environment variable is unset, the
shared data root defaults to
`<USERPROFILE>/OneDrive - University of Arizona/weather_and_agriculture`.
Paths can also be supplied explicitly; personal paths belong in local invocations,
rather than committed code.

`$rawlsms` points to `raw_lsms_data`, `$weatherdata` to `weather_data`, and `$data`
to `weather_metrics_data`, all under the shared data root. `$weatherwork` points
to `$data/refined_data/weather` for project-specific daily conversions and
regenerated weather metrics, leaving shared historical weather files intact.
Household section
outputs go to `refined_data/<country>/wave_<n>` without another `refined` level.
Generated Nigerian conversion tables also go under the project refined data;
original conversion inputs stay under `raw_lsms_data`.

Run `metrics` once to regenerate weather metrics with `wxsum` from existing daily
files. It reads project daily conversions when present, otherwise shared daily
inputs. Nigeria wave 4's shared archive uses `raw 2` and `daily 2`; the code handles
those archive locations explicitly. `households` then uses the project's
regenerated weather. The separate `weather` stage also repeats CSV conversion;
`figures` runs
the existing visualization scripts. `all` runs weather processing, household
cleaning/merging, panel construction, and regressions in order; it can take several
hours. Stages stop at the first error. Legacy figures remain separate: those scripts
still expect extraction-method metadata (`ext`) and older result-variable contracts,
and have not been migrated to the current regression schema.
The `packages` stage installs missing declared dependencies; ordinary runs do not
download packages or change permanent Stata settings. `wxsum` replaces the
deprecated weather package and is installed from its author's GitHub distribution.

#### Weather-engine migration

All 84 weather calls in 31 wave scripts use `wxsum` through
`analysis/reg_code/wxsum_metrics.do`. The adapter retains file names, household
identifiers, wide variable names, and year-major ordering consumed by wave builds.
Season endpoints remain day 1 of the first and final month, inclusive. Deviations
and z-scores retain the full available period as their reference, with at least
two nonmissing seasons; they do not use wxsum's default rolling ten-year reference.

The migration intentionally adopts corrected wxsum definitions and can change
estimates relative to historical weather outputs:

- GDD is a sum of degrees above 10°C, capped at 30°C, rather than a count of days
  with temperatures between those bounds.
- Skewness uses wxsum's skewness statistic, replacing `(mean - median) / sd`.
- Rain-day shares use observed days; seasons with no observed days remain missing.
- Dry spells use wxsum's rain threshold and missing-day handling. `dry` remains
  the intra-season spell, consistent with the historical variable's role.

The old percentile-bin columns remain available for wave-file compatibility;
their shares exclude missing days. These are within-season percentile bins,
not wxsum's absolute-temperature bins. The final panel already excludes them.
Derived weather datasets retain wxsum's version/settings characteristics and
adapter provenance. Historical shared weather outputs remain available for
comparison, and should not be mixed with regenerated inputs.
The adapter retains `sd_season_*`, so the existing `v03`/`v17` mappings remain
standard deviations despite their historical "Variance" labels.
`panel_build.do` retains its historical zero fill for missing weather metrics
before estimation; weather-level missing values are preserved in the regenerated
metric files.

Path verification with synthetic input folders:

```stata
do analysis/reg_code/tests/project_paths.do "<new-scratch-directory>"
do analysis/reg_code/tests/wxsum_migration.do
```

The regression output filenames remain `reg_results.dta` and
`lsms_complete_results.dta`. The rainfall comparison pairs `reg7` (rainfall plus
year effects) with `reg2` (also household effects) on identical observations and
household-clustered standard errors. Pair using `country`, `outcome_var`, and the
full `weather_var`, with `spec_id` identifying the specification. Historical
`reg1`–`reg6` and their numeric IDs are preserved. For synthetic regression
verification, run `analysis/reg_code/tests/cloudy_comparison.do` with a new
scratch directory and, optionally, an original `regressions.do` as the second
argument to compare historical results.

### Pre-requisites

#### Stata req's

  * The data processing and analysis requires a number of user-written Stata programs. From SSC:
    1. `blindschemes`
    3. `mdesc`
    4. `estout`
    5. `distinct`
    6. `winsor2`
    7. `unique`
    8. `palettes`
    9. `catplot`
    10. `colrspace`
    11. `carryforward`
    12. `missings`
    13. `coefplot`

From software author webpages
    1. `wxsum`: `net install wxsum, from("https://raw.githubusercontent.com/jdavidm/wxsum/main/")`
    2. `xfill`

#### Folder structure

The [OSF project page][1] provides more details on the data cleaning.

For the household cleaning code to run, the public use microdata must be downloaded from the [World Bank Microdata Library][2]. Furthermore, the data needs to be placed in the following folder structure:<br>

```text
weather_and_agriculture/
|-- raw_lsms_data/                  shared household inputs
|   `-- <country>/wave_<n>/raw/
|-- weather_data/                   shared raw, daily, and refined weather
|   `-- <country>/wave_<n>/
`-- weather_metrics_data/           project-specific outputs
    |-- refined_data/<country>/
    |   |-- wave_<n>/
    |   `-- logs/
    |-- refined_data/weather/<country>/
    |   |-- wave_<n>/daily/<survey>/
    |   |-- wave_<n>/refined/<survey>/
    |   `-- logs/
    |-- merged_data/<country>/
    |   |-- wave_<n>/
    |   `-- logs/
    |-- regression_data/
    |   |-- <country>/
    |   |-- lsms_panel.dta
    |   `-- logs/
    `-- results_data/
        |-- reg_results.dta
        |-- lsms_complete_results.dta
        |-- <country>/
        |-- tables/
        |-- figures/
        `-- logs/
```

  [1]: https://osf.io/8hnz5/
  [2]: https://www.worldbank.org/en/programs/lsms/initiatives/lsms-ISA
  [3]: https://openknowledge.worldbank.org/handle/10986/36643
