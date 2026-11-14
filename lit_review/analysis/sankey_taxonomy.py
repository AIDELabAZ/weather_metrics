"""
Fixed category taxonomy for the rainfall-IV -> endogenous-variable Sankeys.

Every model's extracted entries are classified into these SAME labels (see
fixed_label_classifier.py), so Sankeys across extraction models are directly
comparable.

The categories live in taxonomies/*.json, copied from
  OneDrive/weather_iv_lit/training/variable categories/
(Nov 2026: replaced the earlier hand-written dicts that were consolidated from
the per-run GPT-5 taxonomies). If you edit the OneDrive copies, copy them here
again. The classifier's cache key includes every definition, so an edit is
never served stale labels.

Each JSON has real categories plus two residual categories:
  Other          — a clearly identified measure/variable that fits no real
                   category (e.g. wind speed as a "rainfall" IV).
  Unclassifiable — text that can't be interpreted well enough to judge
                   category fit (codes, generic labels, fragments, rainfall
                   with unspecified construction).
Within the classifier these become "Other (<side>)" and
"Unclassifiable (<side>)" so the two Sankey sides never share a node name.

What the models see for a category is "<category>: <description>. Examples:
a; b; c" (rainfall has examples; the economic taxonomy doesn't). JEL codes
are kept in CATEGORY_INFO for the export tables but are not shown to the
models: they are anchors for people, and rerankers know JEL codes poorly.
"""

import json
import os

TAXONOMY_DIR = os.environ.get(
    "SANKEY_TAXONOMY_DIR", os.path.join(os.path.dirname(os.path.abspath(__file__)), "taxonomies")
)
TAXONOMY_FILES: dict[str, str] = {
    "Rainfall Metrics":     "rainfall_measures_taxonomy.json",
    "Endogenous Variables": "economic_concepts_taxonomy.json",
}
OTHER = "Other"
UNCLASSIFIABLE = "Unclassifiable"


def other_label(side_name: str) -> str:
    return f"{OTHER} ({side_name})"


def unclassifiable_label(side_name: str) -> str:
    return f"{UNCLASSIFIABLE} ({side_name})"


def residual_labels(side_name: str) -> set[str]:
    return {other_label(side_name), unclassifiable_label(side_name)}


def _definition(cat: dict) -> str:
    text = cat["description"].strip().rstrip(".")
    if cat.get("examples"):
        text += ". Examples: " + "; ".join(cat["examples"])
    return text


def _load(side_name: str) -> dict:
    with open(os.path.join(TAXONOMY_DIR, TAXONOMY_FILES[side_name]), encoding="utf-8") as f:
        tax = json.load(f)
    names = [c["category"] for c in tax["categories"]]
    missing = {OTHER, UNCLASSIFIABLE} - set(names)
    if missing or len(names) != len(set(names)):
        raise ValueError(f"{TAXONOMY_FILES[side_name]}: needs unique category names including "
                         f"{OTHER!r} and {UNCLASSIFIABLE!r} (missing: {missing or 'none'})")
    return tax


_RAW: dict[str, dict] = {side: _load(side) for side in TAXONOMY_FILES}

# Full JSON entries (description, examples, jel_codes), residuals included.
CATEGORY_INFO: dict[str, dict[str, dict]] = {
    side: {c["category"]: c for c in tax["categories"]} for side, tax in _RAW.items()
}
TAXONOMY_NOTES: dict[str, str] = {side: tax.get("note", "") for side, tax in _RAW.items()}

# Real categories only, in file order: {side: {category: definition shown to the models}}.
TAXONOMIES: dict[str, dict[str, str]] = {
    side: {name: _definition(c) for name, c in cats.items() if name not in (OTHER, UNCLASSIFIABLE)}
    for side, cats in CATEGORY_INFO.items()
}
# Other is a stage-2 candidate scored like any category. Unclassifiable is
# decided by stage 1 (INTERPRETABLE_DEFINITIONS) and is never a candidate, so
# its definition is only shown in the export tables.
OTHER_DEFINITIONS: dict[str, str] = {side: _definition(c[OTHER]) for side, c in CATEGORY_INFO.items()}
UNCLASSIFIABLE_DEFINITIONS: dict[str, str] = {
    side: _definition(c[UNCLASSIFIABLE]) for side, c in CATEGORY_INFO.items()
}

# Stage 1 ("can this entry be interpreted?"): what an interpretable entry IS,
# phrased positively because rerankers score negatively-defined documents
# unreliably. Must admit identifiable measures outside the taxonomy, since
# those go to Other in stage 2, not to Unclassifiable.
INTERPRETABLE_DEFINITIONS: dict[str, str] = {
    "Rainfall Metrics":
        "an interpretable, sufficiently specified measure: a rainfall or precipitation measure "
        "whose construction is identifiable, such as a total, mean, change, deviation from normal, "
        "relative or standardized anomaly, percentile, drought or excess-rainfall shock, count of "
        "rainy or dry days, wet or dry spell length, onset timing, short-duration intensity, "
        "within-season concentration, variability, a named index such as SPI or SPEI, cumulative "
        "shock exposure, long-run rainfall climate or a rainfall trend; or a clearly identified "
        "non-rainfall measure such as temperature or wind speed",
    "Endogenous Variables":
        "a specific, identifiable economic variable whose meaning is clear from its name, such as "
        "household income, consumption expenditure, crop yields, wages, school enrolment, child "
        "mortality, migration, conflict incidence, GDP growth, prices, exports or tax revenue",
}
# Side-specific reasons, beyond the shared ones, for answering "no" in stage 1.
UNCLASSIFIABLE_CUES: dict[str, str] = {
    "Rainfall Metrics":
        ", or a rainfall measure that does not indicate whether it is a total, mean, anomaly, "
        "shock or another construction",
    "Endogenous Variables": "",
}

# What each side's entries ARE, for the embedding/reranker instructions.
SIDE_DESCRIPTIONS: dict[str, str] = {
    "Rainfall Metrics":     "a rainfall-based instrumental variable",
    "Endogenous Variables": "an endogenous (instrumented) variable",
}
