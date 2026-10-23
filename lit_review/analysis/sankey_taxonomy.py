"""
Fixed category taxonomy for the rainfall-IV -> endogenous-variable Sankeys.

Every model's extracted entries are classified into these SAME labels (see
fixed_label_classifier.py), so Sankeys across extraction models are directly
comparable — unlike the old per-run LLM taxonomy, where each run invented its
own category names and splits.

Labels were consolidated from the category sets the per-run GPT-5 taxonomy
produced across the full-corpus GPT-4.1 run and the five frontier baselines.
The definition after each label is what the embedding model and reranker
actually see ("<label>: <definition>"), so edit definitions — not just
labels — when a category is systematically missing entries it should catch.

Anything that fits no label (or scores below the backbone's threshold) goes to
"Other (<side>)", which sankey_iv_clustering excludes from the diagram.
"""

RAIN_TAXONOMY: dict[str, str] = {
    "Rainfall Level":
        "total, average, cumulative or annual rainfall or precipitation amount; "
        "unspecified rainfall measured in levels",
    "Seasonal & Monthly Rainfall":
        "rainfall during a season, month, week, growing season or monsoon; "
        "planting-season or harvest-season precipitation",
    "Daily & Event-Specific Rainfall":
        "rainfall on a specific day or date, such as election-day, protest-day "
        "or survey-day rain; daily precipitation",
    "Shocks & Anomalies":
        "rainfall shocks, surprises, deviations from the long-run mean or "
        "historical norm, standardized rainfall z-scores",
    "Variability & Volatility":
        "standard deviation, coefficient of variation, or volatility of rainfall "
        "over time or space",
    "Changes & Growth":
        "first differences, year-on-year changes or growth rates of rainfall",
    "Log & Nonlinear Transformations":
        "log rainfall, squared rainfall, polynomial or other nonlinear "
        "transformations of rainfall",
    "Lagged Rainfall":
        "rainfall in previous years or periods, lags of rainfall, rainfall "
        "during early life or in utero",
    "Drought & Wetness Indices":
        "drought indicators and indices such as SPI, SPEI or PDSI; "
        "drought or wetness dummies; soil moisture",
    "Extremes, Thresholds & Rainy Days":
        "extreme rainfall, floods, heavy-rain events, number of rainy, wet or "
        "dry days or months, rainfall percentiles or binary threshold indicators",
    "Timing & Onset":
        "monsoon or rainy-season onset, withdrawal, delay or timing of rainfall",
    "Spatially Specific Rainfall":
        "rainfall in a particular location such as origin region, upstream area, "
        "neighbouring region, or spatially weighted rainfall",
    "Interactions":
        "rainfall interacted with another variable, such as crop share, "
        "irrigation, soil type or exposure weights",
    "Snow & Other Hydrometeorology":
        "snowfall, snowpack, snowmelt, river flow, runoff, humidity, storms or "
        "other non-rainfall water-related weather measures",
}

ENDOG_TAXONOMY: dict[str, str] = {
    "Economic Growth & Macro Performance":
        "GDP, GDP per capita, economic growth, recessions, aggregate output or "
        "macroeconomic volatility",
    "Agriculture":
        "agricultural production, crop yields, farm income, agricultural "
        "productivity, land use, farming practices or rural economy",
    "Household Income & Consumption":
        "household or individual income, earnings, wages, consumption, "
        "expenditure, income shocks",
    "Poverty & Inequality":
        "poverty rates, income or wealth inequality, Gini coefficients",
    "Labor & Employment":
        "employment, unemployment, labor supply, hours worked, labor force "
        "participation, child labor",
    "Prices & Inflation":
        "inflation, consumer prices, food prices, commodity prices, price levels",
    "Trade & Exchange Rates":
        "exports, imports, trade openness, terms of trade, exchange rates",
    "Finance, Credit & Savings":
        "credit, loans, banking, financial access, savings, investment, "
        "interest rates, monetary aggregates",
    "Public Finance & Governance":
        "government spending, taxation, public debt, institutions, corruption, "
        "democracy, state capacity, public services",
    "Elections & Political Participation":
        "voter turnout, vote shares, election outcomes, referendums, political "
        "participation or attitudes",
    "Conflict, Crime & Unrest":
        "civil conflict, war, violence, crime, protests, riots, social unrest",
    "Health & Nutrition":
        "health outcomes, child health, anthropometrics, birth weight, mortality, "
        "morbidity, disease cases, epidemics, nutrition, food security",
    "Education & Human Capital":
        "schooling, school enrolment, test scores, educational attainment, "
        "cognitive skills, human capital",
    "Migration & Urbanization":
        "migration, displacement, urbanization, city growth, population movement",
    "Demographics & Family":
        "population, fertility, births, marriage, household size, gender "
        "composition, women's empowerment",
    "Remittances, Aid & Transfers":
        "remittances, foreign aid, cash transfers, social protection, "
        "humanitarian assistance",
    "Environment & Pollution":
        "air pollution, emissions, deforestation, vegetation, water quality, "
        "environmental degradation",
    "Natural Disasters & Weather Damages":
        "natural disasters, disaster damages and losses, weather or climate "
        "conditions treated as endogenous",
    "Energy & Natural Resources":
        "energy production or consumption, electricity, hydropower, oil, mining, "
        "natural resource rents",
    "Infrastructure & Public Goods":
        "roads, irrigation infrastructure, water supply, sanitation, dams, "
        "public goods provision",
    "Firms, Industry & Structural Change":
        "firm performance, profits, manufacturing, industrial output, "
        "structural transformation, sectoral composition",
    "Technology, Information & Media":
        "technology adoption, internet or mobile phone use, innovation, "
        "information, news media",
    "Social Capital & Networks":
        "trust, social networks, peer effects, cooperation, social capital, "
        "cultural norms",
}

TAXONOMIES: dict[str, dict[str, str]] = {
    "Rainfall Metrics":     RAIN_TAXONOMY,
    "Endogenous Variables": ENDOG_TAXONOMY,
}

# Other is scored as a label like any other (always included among the
# reranker's candidates) rather than decided by a score threshold — reranker
# scores aren't calibrated across backbones, so a threshold tuned on one
# would make "Other" mean something different on another.
OTHER_DEFINITIONS: dict[str, str] = {
    "Rainfall Metrics":
        "not a rainfall or precipitation measure: temperature, wind, a time window, "
        "a unit, a location name, or a sentence fragment",
    "Endogenous Variables":
        "not a meaningful economic variable: a lag or time window specification, a unit, "
        "a location name, a variable code, or a sentence fragment",
}

# What each side's entries ARE, for the embedding/reranker instructions.
SIDE_DESCRIPTIONS: dict[str, str] = {
    "Rainfall Metrics":     "a rainfall-based instrumental variable",
    "Endogenous Variables": "an endogenous (instrumented) variable",
}
