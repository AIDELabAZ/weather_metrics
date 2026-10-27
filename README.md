# Cloudy With A Chance of Significance: Specification Search and the Illusion of Exogeneity in Remotely Sensed Weather Data

This repository contains code for replicating the statistical analysis in Michler, J.D., Josephson, A., Agme, C., and Kilic, T. (2026). "Cloudy With A Chance of Significance: Specification Search and the Illusion of Exogeneity in Remotely Sensed Weather Data." *Unpublished*.

<!-- edited by: codex; edited on: 27 Oct 2026 -->

This README was last updated on 27 Oct 2026.

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

`projectdo.do` keeps the original numbered sections and run blocks. Run it in
Stata 18 or newer, and edit/select the relevant blocks
as before. The original block-comment choices are preserved: weather processing,
household processing, and panel/regression calls are commented out; the analysis
calls in section 4 are active. Those legacy figure scripts still require their
older result-variable contracts and have not been migrated.

Section 0.1 identifies the local machine using `c(username)`, as in the original
master. Copy an existing user block and edit the username, repository path
(`$code`), and shared data path (`$base`) for your machine. Each user's data
path can point to their own storage location. No environment variable is required.
The master stops with a message if the username has no configured block.

The input and output globals immediately below those blocks can also be edited
if the inputs and project outputs live in separate locations. `setup_paths.do`
uses these globals to create output folders; it does not choose or change paths.
To initialize paths and folders without running analysis, select and run section
0.1 of `projectdo.do`.

`$raw` points to `raw_lsms_data`, `$wraw` to `weather_data`, and `$data`
to `weather_metrics_data`, all under the shared data root. Weather processing
uses the shared `$wraw/<country>/wave_<n>` tree throughout: converters read CSV
files from `raw/<source>` and save daily Stata files to `daily/<source>`;
the wxsum scripts read those daily files and save metrics to `refined/<source>`.
Directory setup discovers source names from the raw folders and creates the
corresponding daily and refined folders. Projects read the shared refined files
without making additional weather copies. Run weather processing when creating
or deliberately rebuilding the shared files, rather than for every project.
Household outputs go to
`refined_data/<country>/wave_<n>` without another `refined` level. Generated
Nigerian conversion tables also go under the project refined data; original
conversion inputs stay under `raw_lsms_data`.

Section 1 calls the existing country weather master files. Individual wave
`*_weather.do` files can be run directly to recompute shared metrics from existing
shared daily files. Household builds read the corresponding shared refined files.
Inputs must follow the documented folder structure; duplicate archive folders
such as `raw 2` and `daily 2` are not selected automatically.

The original `$pack` switch controls package installation: keep `pack` at 0 to
skip it, or set it to 1 to execute section 0.2. The weather dependency is now
`wxsum`, installed from its author's GitHub distribution.

#### Weather-engine migration

All 84 weather calls use `wxsum` directly inside the 31 country-wave weather
scripts. Those scripts retain file names, household identifiers, wide variable
names, and year-major ordering consumed by wave builds.
Season endpoints remain day 1 of the first and final month, inclusive. Deviations
and z-scores retain the full available period as their reference, with at least
two nonmissing seasons; they do not use wxsum's default rolling ten-year reference.
All countries use GDD bounds of 10°C and 30°C and a heat threshold of 30°C.
Rainfall calls use a rainy-day threshold of 1 in the rainfall data's units.

The migration adopts wxsum definitions and can change
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
Derived weather datasets retain wxsum's version/settings characteristics.
Rebuilding shared refined files replaces the previous
metrics at those paths; projects using them should use the same weather version.
The weather scripts retain `sd_season_*`, so the existing `v03`/`v17` mappings remain
standard deviations despite their historical "Variance" labels.
`panel_build.do` retains its historical zero fill for missing weather metrics
before estimation; weather-level missing values are preserved in the regenerated
metric files.

Path verification with synthetic input folders:

```stata
	do			analysis/reg_code/tests/project_paths.do "<new-scratch-directory>"
	do			tests/weather/shared_weather.do "<another-new-scratch-directory>"
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
|   `-- <country>/
|       |-- wave_<n>/
|       |   |-- raw/<source>/       CSV inputs
|       |   |-- daily/<source>/     daily Stata files
|       |   `-- refined/<source>/   wxsum metrics
|       `-- logs/
`-- weather_metrics_data/           project-specific outputs
    |-- refined_data/<country>/
    |   |-- wave_<n>/
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
