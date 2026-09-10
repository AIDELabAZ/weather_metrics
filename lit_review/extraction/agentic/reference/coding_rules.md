# Coding rules — metadata extraction

Transcribed from `weather_iv_lit/training/training_new_labels/Prompts for Constructing
Training Data.docx` (the rules the human coders followed to produce `training_all_new.xlsx`
/ `train_80.csv` / `removed_20.csv`). These are the authoritative definitions. Extract using
**only** the provided article text; if the requested information is not in the text, answer
`n/a`.

## Hierarchical gating (enforced)

```
empirical_analysis
├── dependent_variables            (only if empirical_analysis == 1)
└── endogeneity_problem            (only if empirical_analysis == 1)
    ├── endogenous_variables       (only if endogeneity_problem == 1)
    └── iv_used                    (only if endogeneity_problem == 1)
        ├── instruments            (only if iv_used == 1)
        └── rainfall_iv            (only if iv_used == 1)
            └── rainfall_instrument (only if rainfall_iv == 1)
```

When a gate fails, **every field below it is `n/a`** — do not guess. (A downstream cascade
in the script also blanks these, but you should already emit `n/a`.)

## Fields

### title
The title of the paper or document. There will always be a title. It is at the top of the
first page (main heading before authors/abstract). Include a subtitle if it is in the same
heading. Exclude authors, affiliations, journal headers/footers, section headers. Ignore
footnote markers (`*`, `†`, superscripts).

### doi
The DOI of THIS article (version of record), not a DOI in the references. Look in the first
page / front matter for `doi:`, `DOI`, `https://doi.org/`. Remove the URL/prefix, remove
spaces/line breaks, strip trailing punctuation, output lowercase (`10.xxxx/xxxx`). If no DOI
exists, answer `n/a`.

### empirical_analysis  (binary 0/1)
Does the paper contain **empirical quantitative analysis via regression or similar
statistical methods** — done in THIS article (not a summary of other papers)? Scan for data
sections, econometric/empirical-strategy descriptions, model equations with error terms,
coefficient tables with standard errors / p-values, and estimation techniques (OLS, IV, DiD,
GMM, …). Do NOT infer from topic / title / abstract alone. Exclude purely theoretical work,
qualitative/descriptive-only work, and simulation/calibration-only work.
`1` if yes, `0` if no. If `0`, all subsequent fields are `n/a`.

### dependent_variables  (list; gate: empirical_analysis == 1)
The **dependent / outcome variable(s)** in the main regression(s) — the left-hand-side
measure(s) of the study's main outcome, modelled as a function of the explanatory variables.
There will always be one if the paper is empirical; sometimes more than one (separate with
`; `). Exclude first-stage outcomes, right-hand-side variables (treatments / endogenous
regressors / instruments / controls / covariates / fixed effects), mediators, moderators.
Keep names exactly as written in the paper/table (including any log / ln / differences /
units if shown).

### endogeneity_problem  (binary 0/1; gate: empirical_analysis == 1)
In the MAIN empirical analysis, do the authors **treat any regressor as endogenous**
(correlated with the error term) **and address it explicitly**? Look for statements that a
regressor is endogenous plus a method to address it (IV / 2SLS / 3SLS / LIML, control
function / 2SRI, GMM with instruments, endogenous switching, first stage, weak-IV /
overidentification tests). Do NOT count a generic mention of "endogeneity" with no actual
endogenous regressor in the main specs. `1` / `0`. If `0`, all subsequent fields are `n/a`.

### endogenous_variables  (list; gate: endogeneity_problem == 1)
The specific **explanatory / independent variable(s) the authors claim is endogenous** in
the main analysis. Look for "we instrument X", "X is endogenous", first-stage descriptions /
tables, reduced form, weak-IV / overid tests. Exclude instruments, dependent variables,
ordinary controls. **Rainfall, precipitation, other weather events, or natural phenomena
like pollution measured in PM will never be the endogenous variable.** Multiple → `; `.
Keep names exactly as written.

### iv_used  (binary 0/1; gate: endogeneity_problem == 1)
Do the authors **implement an IV-type estimator with excluded instruments** to address the
endogeneity? Look for an actual excluded-instrument set used in a first stage / reduced form;
2SLS / IV / 3SLS / LIML; IV-Probit; control function / 2SRI; GMM with instruments; explicit
discussion of relevance and the exclusion restriction; first-stage equations / tables;
weak-instrument / overidentification tests. Authors often write that they "instrument" for
the endogenous variable. **Be careful:** sometimes authors discuss an IV but conclude it is
not necessary or not possible and end up not using one — that is `0`. Do NOT count
non-statistical uses of "instrument" (survey instrument, measurement instrument), or papers
that use only RCT / RDD / DiD / event study without an IV first stage. `1` / `0`. If `0`,
all subsequent fields are `n/a`.

### instruments  (list; gate: iv_used == 1)
The exact **excluded instrument(s)** the authors say is their "instrument" — used in the
first stage to predict the endogenous regressor and excluded from the second stage. Look for
"we instrument X with Z", "Z is our instrument", "excluded instrument", first-stage /
reduced-form equations or tables. Exclude the endogenous regressors themselves, dependent
variables, and regular controls. Multiple → `; `. Keep names exactly as written.

### rainfall_iv  (binary 0/1; gate: iv_used == 1)
Is **any excluded instrument based on rainfall / precipitation**? Scan first-stage
equations / tables for a rainfall variable predicting the endogenous regressor, plus
relevance / exclusion discussion. Authors may not literally write "rainfall" — watch for:
rain, rainfall, precip, precipitation, `rain_dev`, `rain_anom`, `rain_shock`, `rain_gs`
(growing season), SPI, SPEI, PDSI, "rainfall z-score", "weather shocks", "hydro-
meteorological index", "water availability", "soil moisture anomaly", drought, monsoon
onset. If a rainfall variable appears in the first stage but **not** as a control in the
second stage, it is probably the instrument. If it appears **in the second stage**, it
cannot be an instrument. Do NOT count precipitation used only as a regressor / control /
interaction / exposure / outcome. Do NOT count ENSO or other climate indices unless the text
explicitly states they are precipitation-based AND used as the excluded instrument. `1` /
`0`. If `0`, `rainfall_instrument` is `n/a`.

### rainfall_instrument  (list; gate: rainfall_iv == 1)
**Exactly how the paper measures / constructs the rainfall (weather-shock) instrument** —
precise variable name(s), e.g. "growing-season total rainfall", "mean daily rainfall", "day
of monsoon onset", "days without rain", "rainfall deviations from the long-run average",
"coefficient of variation of rainfall". Pay attention to transformations (deviation,
z-score) and thresholds and windows / statistics / units. **Do NOT** answer with a bare
broad term like `rainfall`, `precipitation`, or `rainfall and humidity` on their own —
unless it is part of a fuller phrase such as "rainfall deviations (from long-term average)"
or "unexpected rainfall shocks defined as the deviation from the long-run precipitation
trend". Make sure the metric is actually used in the IV first stage, not a second-stage
control or a passing mention. Multiple → `; `.

## Evidence (for every non-`n/a` field)

- `quote`: copy the sentence(s) from the article that identify the value. It must contain
  the value name **and** a statement that makes its role clear (e.g. the word "endogenous"
  for `endogenous_variables`; "instrument" for `instruments` / `rainfall_instrument`). Copy
  verbatim; do not paraphrase; do not include unrelated text.
- `section`: the **highest-level** section heading where you found it (not a subsection),
  e.g. `Introduction`, `Data`, `Empirical strategy`, `Results`. Use `abstract` for the
  abstract.
