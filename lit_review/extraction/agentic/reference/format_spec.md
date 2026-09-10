# Output format spec

The final CSV must match what `analysis/model_eval.R` consumes (identical to the other GPT
model outputs). This spec governs the `final_value` the judge emits for each field.

## Binaries — `empirical_analysis`, `endogeneity_problem`, `iv_used`, `rainfall_iv`

- Exactly one of: `"1"`, `"0"`, `"n/a"`. No justification text, no extra words.
- `"n/a"` only because a gate above it failed (or the text genuinely doesn't let you decide).
  A failed gate always wins.

## Variable lists — `dependent_variables`, `endogenous_variables`, `instruments`,
## `rainfall_instrument`

- One line. Multiple values separated by `"; "` (semicolon + space).
- `"n/a"` if the gate failed or nothing qualifies.
- Each value: the variable **name as written in the paper / table**, keeping any
  `log` / `ln` / difference / unit / window / statistic. Do **not** rewrite into your own
  words.
- Trim to the name: drop leading labels ("the dependent variable is", "we use", "such as",
  "which is", "that", trailing "where …" clauses), surrounding quotes/dashes.
- Drop any candidate longer than ~10 words — it's a sentence, not a variable name.
- De-duplicate case-insensitively; keep the first surface form.
- `rainfall_instrument` specifically: never a bare `rainfall` / `precipitation` /
  `rainfall and humidity` — see `coding_rules.md` (must be a constructed metric or a fuller
  phrase).

## `title`

- The title text only. No quotes, no labels, no author line, no journal header. Keep the
  subtitle if it's part of the same heading.

## `doi`

- Lowercase, normalized `10.xxxx/xxxx`. Strip `doi:` / `https://doi.org/` / `http://dx.doi.org/`
  prefixes, internal whitespace/newlines, trailing punctuation.
- `"n/a"` if the article has no DOI.

## `section` (evidence field, not scored)

- The highest-level heading, lower- or title-case as printed. `abstract` for the abstract.
  If sectionizing failed, `full text`.

## `consensus` (per field, judge output)

- `"agree"` — reader A and reader B agree and the verifier confirms the quote is present and
  supports the value.
- `"resolved"` — they differed; the judge picked the better-supported value (may be reader
  B's alternative).
- `"review"` — unresolved disagreement, the quote could not be found in the paper, or
  confidence is low. Emit the best available value anyway, but flag it.
