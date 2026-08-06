############################################
# model evaluation code
############################################
### Reads a model output CSV and the human-validated CSV for the 20% of data
### excluded from training, cleans/normalizes/merges them by filename, and reports:
###   - confusion matrices for the binary identification fields
###   - cross-encoder semantic similarity for the free-text fields
### Call evaluate_model() once per model's output CSV (gemini, gpt, llama, gemma, ...).
############################################
library(tidyverse)
library(caret)
library(reticulate)

############################################
# Paths
############################################
human_path <- "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data/removed_20.csv"
merged_dir <- "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/finetune_data"

model_paths <- list(
  # gemini = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/finetune_gemini_aistudio_output.csv",
  gpt_baseline = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/gpt/baseline/baseline_gpt_output.csv",
  gpt_rag      = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/gpt/rag/rag_gpt_output.csv",
  gpt_finetune = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/gpt/finetune/gpt_finetune_output.csv"
  # llama = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/llama_finetune_output.csv",
  # gemma = "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output/gemma_finetune_output.csv"
)

# Where the LaTeX comparison table (built at the bottom of this script) is written.
tex_output_path <- "/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_iv_lit/training/models/output"

# Display labels for model_paths keys, used as column headers in the LaTeX table.
# Column order in the table follows names(model_paths): Zero-shot, RAG, Fine-tuned.
model_display_names <- c(
  gpt_baseline = "Zero-shot",
  gpt_rag      = "RAG",
  gpt_finetune = "Fine-tuned"
)

############################################
# Cross-encoder setup (once for the whole session)
############################################
# Create env only once; comment out after first successful run:
virtualenv_create("bert_env")
use_virtualenv("bert_env", required = TRUE)

py_install(c("torch", "transformers", "sentence-transformers"))

py_run_string("
from sentence_transformers import CrossEncoder
import numpy as np

_ce_model = CrossEncoder('cross-encoder/stsb-roberta-large')

def ce_similarity(texts1, texts2, batch_size=32):
    pairs = list(zip(texts1, texts2))
    scores = _ce_model.predict(pairs, batch_size=batch_size)
    return np.array(scores, dtype=float)
")

ce_score_pairs <- function(x, y, batch_size = 32L) {
  stopifnot(length(x) == length(y))

  ok <- !(is.na(x) | is.na(y))
  out <- rep(NA_real_, length(x))

  if (any(ok)) {
    out[ok] <- py$ce_similarity(
      as.character(x[ok]),
      as.character(y[ok]),
      batch_size = as.integer(batch_size)
    )
  }
  out
}

similarity_metrics <- function(v) {
  r <- range(v, na.rm = TRUE)
  c(
    n      = sum(!is.na(v)),
    mean   = mean(v, na.rm = TRUE),
    median = median(v, na.rm = TRUE),
    sd     = sd(v, na.rm = TRUE),
    min    = r[1],
    max    = r[2]
  )
}

############################################
# Shared cleaning helpers
############################################
clean_filenames <- function(df) {
  df %>%
    mutate(
      filename = filename %>%
        str_remove_all("\\.pdf$") %>%
        str_replace_all(" copy( \\d+)?$", "") %>%
        iconv(to = "ASCII//TRANSLIT", sub = "") %>%
        str_squish()
    )
}

clean_doi <- function(df) {
  df %>%
    mutate(
      doi = doi %>%
        str_remove("^https?://(dx\\.)?doi\\.org/") %>%
        str_remove("^https?://") %>%
        str_squish()
    )
}

############################################
# Clean human data (fixed schema, shared across every model)
############################################
human_data <- read_csv(human_path, na = c("n/a", "NA", ""))

human_data_clean <- human_data %>%
  rename(
    ptitle  = title,
    rainmet = rain_var,
    endog   = end_var,
    depen   = dep_var,
    iv      = iv_var
  ) %>%
  mutate(
    filename_human = filename,  # preserve original human filename
    ptitle   = tolower(iconv(ptitle,   to = "UTF-8", sub = "byte")),
    filename = tolower(iconv(filename, to = "UTF-8", sub = "byte")),
    rainmet  = tolower(iconv(rainmet,  to = "UTF-8", sub = "byte")),
    doi      = tolower(iconv(doi,      to = "UTF-8", sub = "byte")),
    endog    = tolower(iconv(endog,    to = "UTF-8", sub = "byte")),
    depen    = tolower(iconv(depen,    to = "UTF-8", sub = "byte")),
    iv       = tolower(iconv(iv,       to = "UTF-8", sub = "byte")),
    iv_bin   = as.numeric(iv_bin),
    rain_bin = as.numeric(rain_bin),
    emp_bin  = as.numeric(emp_bin),
    end_bin  = as.numeric(end_bin)
  ) %>%
  clean_filenames() %>%
  clean_doi() %>%
  mutate(
    iv_bin   = ifelse(is.na(iv_bin),   0, iv_bin),
    rain_bin = ifelse(is.na(rain_bin), 0, rain_bin),
    emp_bin  = ifelse(is.na(emp_bin),  0, emp_bin),
    end_bin  = ifelse(is.na(end_bin),  0, end_bin)
  )

############################################
# Per-model evaluation
############################################
evaluate_model <- function(model_path, model_label) {
  cat("\n============================\nEvaluating:", model_label, "\n============================\n")

  model_data <- read_csv(model_path, na = c("n/a", "NA", ""))

  model_data_clean <- model_data %>%
    rename(
      filename = `File Name`,
      doi      = DOI,
      iv_bin   = `Instrumental Variable Used`,
      rain_bin = `Instrumental Variable Rainfall`,
      ptitle   = `Title`,
      rainmet  = `Rainfall Instrument`,
      endog    = `Endogenous Variable(s)`,
      depen    = `Dependent Variable(s)`,
      iv       = `Instrumental Variable(s)`,
      emp_bin  = `Empirical Analysis`,
      end_bin  = `Endogeneity Problem`
    ) %>%
    mutate(
      filename_model = filename,  # preserve original model filename
      ptitle   = tolower(iconv(ptitle,   to = "UTF-8", sub = "byte")),
      filename = tolower(iconv(filename, to = "UTF-8", sub = "byte")),
      rainmet  = tolower(iconv(rainmet,  to = "UTF-8", sub = "byte")),
      doi      = tolower(iconv(doi,      to = "UTF-8", sub = "byte")),
      endog    = tolower(iconv(endog,    to = "UTF-8", sub = "byte")),
      depen    = tolower(iconv(depen,    to = "UTF-8", sub = "byte")),
      iv       = tolower(iconv(iv,       to = "UTF-8", sub = "byte")),
      iv_bin   = as.numeric(iv_bin),
      rain_bin = as.numeric(rain_bin),
      emp_bin  = as.numeric(emp_bin),
      end_bin  = as.numeric(end_bin)
    ) %>%
    clean_filenames() %>%
    clean_doi() %>%
    mutate(
      iv_bin   = ifelse(is.na(iv_bin),   0, iv_bin),
      rain_bin = ifelse(is.na(rain_bin), 0, rain_bin),
      emp_bin  = ifelse(is.na(emp_bin),  0, emp_bin),
      end_bin  = ifelse(is.na(end_bin),  0, end_bin)
    )

  merged_data <- human_data_clean %>%
    inner_join(model_data_clean, by = "filename", suffix = c("_human", "_model")) %>%
    rename(filename_merged = filename)

  # confusionMatrix requires data/reference to be factors with the same levels
  merged_data <- merged_data %>%
    mutate(
      iv_bin_human   = factor(iv_bin_human,   levels = c(0, 1)),
      iv_bin_model   = factor(iv_bin_model,   levels = c(0, 1)),
      rain_bin_human = factor(rain_bin_human, levels = c(0, 1)),
      rain_bin_model = factor(rain_bin_model, levels = c(0, 1)),
      emp_bin_human  = factor(emp_bin_human,  levels = c(0, 1)),
      emp_bin_model  = factor(emp_bin_model,  levels = c(0, 1)),
      end_bin_human  = factor(end_bin_human,  levels = c(0, 1)),
      end_bin_model  = factor(end_bin_model,  levels = c(0, 1))
    )

  cm_iv   <- confusionMatrix(merged_data$iv_bin_model,   merged_data$iv_bin_human,   positive = "1")
  cm_rain <- confusionMatrix(merged_data$rain_bin_model, merged_data$rain_bin_human, positive = "1")
  cm_emp  <- confusionMatrix(merged_data$emp_bin_model,  merged_data$emp_bin_human,  positive = "1")
  cm_end  <- confusionMatrix(merged_data$end_bin_model,  merged_data$end_bin_human,  positive = "1")

  cat("\nConfusion Matrix for hasIV:\n")
  print(cm_iv)

  cat("\nConfusion Matrix for isRainfall:\n")
  print(cm_rain)

  cat("\nConfusion Matrix for emp_bin:\n")
  print(cm_emp)

  cat("\nConfusion Matrix for end_bin:\n")
  print(cm_end)

  # Accuracy/Sensitivity/Specificity/Precision/F1/Balanced Accuracy per binary
  # field, for the LaTeX comparison table built at the bottom of this script —
  # same numbers already printed above via confusionMatrix(), just captured in
  # a tidy structure too. caret's byClass already computes Precision, F1, and
  # Balanced Accuracy directly (verified via byClass field names), so no need
  # to derive them by hand.
  binary_row <- function(field_name, cm) {
    data.frame(
      field             = field_name,
      accuracy          = cm$overall[["Accuracy"]],
      sensitivity       = cm$byClass[["Sensitivity"]],
      specificity       = cm$byClass[["Specificity"]],
      precision         = cm$byClass[["Precision"]],
      f1                = cm$byClass[["F1"]],
      balanced_accuracy = cm$byClass[["Balanced Accuracy"]]
    )
  }
  binary_metrics <- bind_rows(
    binary_row("Empirical Analysis",  cm_emp),
    binary_row("Endogeneity Problem", cm_end),
    binary_row("Has IV",              cm_iv),
    binary_row("Is Rainfall IV",      cm_rain)
  )

  merged_data$rainmet_similarity <- ce_score_pairs(merged_data$rainmet_human, merged_data$rainmet_model)
  merged_data$endog_similarity   <- ce_score_pairs(merged_data$endog_human,   merged_data$endog_model)
  merged_data$doi_similarity     <- ce_score_pairs(merged_data$doi_human,     merged_data$doi_model)
  merged_data$depen_similarity   <- ce_score_pairs(merged_data$depen_human,   merged_data$depen_model)
  merged_data$ptitle_similarity  <- ce_score_pairs(merged_data$ptitle_human,  merged_data$ptitle_model)
  merged_data$iv_similarity      <- ce_score_pairs(merged_data$iv_human,      merged_data$iv_model)

  # Written here (not right after the join) so the per-paper *_similarity
  # columns are included — downstream analyses (e.g. density plots of the
  # score spread) need the raw per-paper values, not just the aggregate
  # mean/sd in similarity_summary below.
  write_csv(merged_data, file.path(merged_dir, paste0("merged_data_", model_label, ".csv")))

  similarity_summary <- data.frame(
    field = c("rainmet", "endog", "doi", "depen", "ptitle", "iv"),
    rbind(
      similarity_metrics(merged_data$rainmet_similarity),
      similarity_metrics(merged_data$endog_similarity),
      similarity_metrics(merged_data$doi_similarity),
      similarity_metrics(merged_data$depen_similarity),
      similarity_metrics(merged_data$ptitle_similarity),
      similarity_metrics(merged_data$iv_similarity)
    ),
    row.names = NULL,
    check.names = FALSE
  )

  cat("\nSemantic similarity summary:\n")
  print(similarity_summary)

  confusion_tables <- list(
    "Empirical Analysis"  = cm_emp$table,
    "Endogeneity Problem" = cm_end$table,
    "Has IV"              = cm_iv$table,
    "Is Rainfall IV"      = cm_rain$table
  )

  invisible(list(merged_data = merged_data, binary = binary_metrics, similarity = similarity_summary, confusion = confusion_tables))
}

############################################
# Run for every model
############################################
results <- setNames(
  lapply(names(model_paths), function(m) evaluate_model(model_paths[[m]], m)),
  names(model_paths)
)

############################################
# LaTeX comparison table (binary + similarity metrics, all models side by side)
############################################
# One combined table: a binary-classification block (Accuracy/Sensitivity/
# Specificity per field) on top, a semantic-similarity block (mean score per
# field) below, models as columns throughout. Requires \usepackage{booktabs}
# in the LaTeX document that \input{}s this file.
build_latex_comparison_table <- function(results, model_keys, model_labels, out_path) {
  # Accept either a full file path or a directory — if out_path is (or looks
  # like) a directory, write "model_comparison.tex" inside it rather than
  # erroring on file() trying to open a directory for writing.
  if (dir.exists(out_path) || grepl("/$", out_path)) {
    out_path <- file.path(out_path, "model_comparison.tex")
  }

  binary_field_order  <- c("Empirical Analysis", "Endogeneity Problem", "Has IV", "Is Rainfall IV")
  binary_metric_order <- c("Accuracy", "Sensitivity", "Specificity", "Precision", "F1", "Balanced Accuracy")
  binary_metric_keys  <- c(
    "Accuracy"          = "accuracy",
    "Sensitivity"       = "sensitivity",
    "Specificity"       = "specificity",
    "Precision"         = "precision",
    "F1"                = "f1",
    "Balanced Accuracy" = "balanced_accuracy"
  )
  similarity_field_order <- c(
    ptitle  = "Title",
    doi     = "DOI",
    depen   = "Dependent Variable(s)",
    endog   = "Endogenous Variable(s)",
    iv      = "Instrument(s)",
    rainmet = "Rainfall Instrument"
  )

  fmt <- function(x) ifelse(is.na(x), "--", sprintf("%.3f", x))

  n_models  <- length(model_keys)
  col_spec  <- paste0("ll", strrep("c", n_models))
  header    <- paste(model_labels, collapse = " & ")

  lines <- c(
    "\\begin{table}[htbp]",
    "\\centering",
    "\\caption{Comparison of extraction performance across GPT variants}",
    "\\label{tab:model_comparison}",
    sprintf("\\begin{tabular}{%s}", col_spec),
    "\\toprule",
    sprintf(" & & %s \\\\", header),
    "\\midrule",
    sprintf("\\multicolumn{%d}{l}{\\textit{Binary Classification Metrics}} \\\\", n_models + 2)
  )

  for (field in binary_field_order) {
    for (i in seq_along(binary_metric_order)) {
      metric     <- binary_metric_order[i]
      metric_key <- binary_metric_keys[[metric]]
      row_label  <- if (i == 1) field else ""
      vals <- sapply(model_keys, function(m) {
        v <- results[[m]]$binary[[metric_key]][results[[m]]$binary$field == field]
        if (length(v) == 0) NA else v
      })
      lines <- c(lines, sprintf("%s & %s & %s \\\\", row_label, metric, paste(fmt(vals), collapse = " & ")))
    }
  }

  lines <- c(
    lines, "\\midrule",
    sprintf("\\multicolumn{%d}{l}{\\textit{Semantic Similarity}} \\\\", n_models + 2)
  )

  # Each field gets two rows: mean, then (SD) below it.
  for (key in names(similarity_field_order)) {
    label <- similarity_field_order[[key]]
    mean_vals <- sapply(model_keys, function(m) {
      v <- results[[m]]$similarity$mean[results[[m]]$similarity$field == key]
      if (length(v) == 0) NA else v
    })
    sd_vals <- sapply(model_keys, function(m) {
      v <- results[[m]]$similarity$sd[results[[m]]$similarity$field == key]
      if (length(v) == 0) NA else v
    })
    sd_display <- ifelse(is.na(sd_vals), "--", sprintf("(%.3f)", sd_vals))

    lines <- c(lines, sprintf("%s & & %s \\\\", label, paste(fmt(mean_vals), collapse = " & ")))
    lines <- c(lines, sprintf(" & & %s \\\\", paste(sd_display, collapse = " & ")))
  }

  lines <- c(
    lines, "\\midrule",
    sprintf("\\multicolumn{%d}{l}{\\footnotesize Parenthetical values denote SD.} \\\\", n_models + 2)
  )

  lines <- c(lines, "\\bottomrule", "\\end{tabular}", "\\end{table}")

  dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
  writeLines(lines, out_path)
  cat("\nLaTeX comparison table written to:", out_path, "\n")
}

build_latex_comparison_table(
  results,
  model_keys   = names(model_paths),
  model_labels = model_display_names[names(model_paths)],
  out_path     = tex_output_path
)

############################################
# Similarity KDE grid 
############################################
# A 2x2 small-multiples grid — one panel per free-text field, one density
# curve per model — showing the SHAPE of the per-paper similarity scores
# (results[[m]]$merged_data already carries them, added right after
# ce_score_pairs() above), not just the mean/sd already in the LaTeX table.
# Two models can share a mean while looking completely different here (e.g.
# a bimodal hit-or-miss model vs. a consistently-mediocre one).
build_similarity_density_plot <- function(results, model_keys, model_labels, out_path) {
  if (dir.exists(out_path) || grepl("/$", out_path)) {
    out_path <- file.path(out_path, "similarity_kdensities.png")
  }

  field_cols <- c(
    ptitle_similarity  = "Title",
    doi_similarity     = "DOI",
    depen_similarity   = "Dependent Variable(s)",
    endog_similarity   = "Endogenous Variable(s)",
    iv_similarity      = "Instrument(s)",
    rainmet_similarity = "Rainfall Instrument"
  )

  density_data <- bind_rows(lapply(model_keys, function(m) {
    md <- results[[m]]$merged_data
    bind_rows(lapply(names(field_cols), function(col) {
      vals <- md[[col]]
      vals <- vals[!is.na(vals)]
      if (length(vals) == 0) return(NULL)
      data.frame(model = model_labels[[m]], field = field_cols[[col]], value = vals)
    }))
  }))

  density_data$model <- factor(density_data$model, levels = unname(model_labels[model_keys]))
  density_data$field <- factor(density_data$field, levels = unname(field_cols))

  # Same 3-slot categorical palette used elsewhere for these models (blue/
  # orange/aqua) — validated for CVD-safety at this series count.
  palette <- c("#08B2E3", "#484D6D", "#57A773")
  model_colors <- setNames(palette[seq_along(model_keys)], unname(model_labels[model_keys]))

  n_facet_rows <- ceiling(length(field_cols) / 2)

  # One vertical line per (field, model) at that group's mean similarity —
  # drawn from a separate summary data frame so each facet gets its own set
  # of lines rather than one global mean across all fields.
  mean_lines <- density_data %>%
    group_by(field, model) %>%
    summarise(mean_value = mean(value, na.rm = TRUE), .groups = "drop")

  p <- ggplot(density_data, aes(x = value, color = model, fill = model)) +
    geom_density(linewidth = 0.3, alpha = 0.1) +
    geom_vline(
      data = mean_lines,
      aes(xintercept = mean_value, color = model),
      linetype = "dashed", linewidth = 0.6, show.legend = FALSE
    ) +
    facet_wrap(~ field, ncol = 2, scales = "free_y") +
    scale_color_manual(values = model_colors) +
    scale_fill_manual(values = model_colors) +
    coord_cartesian(xlim = c(0, 1)) +
    labs(
      title = "Semantic Similarity Score Distributions — Zero-shot vs. RAG vs. Fine-tuned",
      x = "Cross-encoder similarity",
      y = "Density",
      color = NULL, fill = NULL
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title    = element_text(hjust = 0),
      panel.grid.minor = element_blank(),
      strip.text    = element_text(face = "bold", hjust = 0),
      legend.position = "top"
    )

  # 3.2 per facet row + 1.6 fixed for title/legend — reproduces the original
  # height=8 at 2 rows (4 fields), scales up cleanly as fields are added.
  dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_path, plot = p, width = 11, height = 3.2 * n_facet_rows + 1.6, dpi = 150, bg = "white")
  cat("\nSimilarity KDE grid written to:", out_path, "\n")
}

build_similarity_density_plot(
  results,
  model_keys   = names(model_paths),
  model_labels = model_display_names[names(model_paths)],
  out_path     = tex_output_path
)

############################################
# Confusion matrices LaTeX
############################################
# Raw Prediction x Reference counts for each binary field, one table per
# field with a column-pair per model — the counts behind the summary
# accuracy/sensitivity/etc. already in model_comparison.tex.
build_confusion_matrices_tex <- function(results, model_keys, model_labels, out_path) {
  if (dir.exists(out_path) || grepl("/$", out_path)) {
    out_path <- file.path(out_path, "confusion_matrices.tex")
  }

  field_order <- c("Empirical Analysis", "Endogeneity Problem", "Has IV", "Is Rainfall IV")
  n_models    <- length(model_keys)
  col_spec    <- paste0("l", strrep("cc", n_models))

  model_header <- paste(
    sapply(model_labels[model_keys], function(lbl) sprintf("\\multicolumn{2}{c}{%s}", lbl)),
    collapse = " & "
  )
  ref_header <- paste(rep("Ref. 0 & Ref. 1", n_models), collapse = " & ")
  cmidrules  <- paste(
    sapply(seq_len(n_models), function(i) sprintf("\\cmidrule(lr){%d-%d}", 2 * i, 2 * i + 1)),
    collapse = " "
  )

  lines <- c()
  for (field_idx in seq_along(field_order)) {
    field      <- field_order[field_idx]
    label_slug <- gsub("[^a-z]", "", tolower(field))

    lines <- c(lines,
      "\\begin{table}[htbp]", "\\centering",
      sprintf("\\caption{Confusion matrix: %s}", field),
      sprintf("\\label{tab:cm_%s}", label_slug),
      sprintf("\\begin{tabular}{%s}", col_spec),
      "\\toprule",
      sprintf(" & %s \\\\", model_header),
      cmidrules,
      sprintf("Predicted & %s \\\\", ref_header),
      "\\midrule"
    )

    for (pred_class in c("0", "1")) {
      cells <- unlist(lapply(model_keys, function(m) {
        tbl <- results[[m]]$confusion[[field]]
        if (is.null(tbl)) return(c("--", "--"))
        c(as.character(tbl[pred_class, "0"]), as.character(tbl[pred_class, "1"]))
      }))
      lines <- c(lines, sprintf("%s & %s \\\\", pred_class, paste(cells, collapse = " & ")))
    }

    lines <- c(lines, "\\bottomrule", "\\end{tabular}", "\\end{table}")
    if (field_idx < length(field_order)) lines <- c(lines, "", "\\vspace{1em}", "")
  }

  dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
  writeLines(lines, out_path)
  cat("\nConfusion matrices LaTeX written to:", out_path, "\n")
}

build_confusion_matrices_tex(
  results,
  model_keys   = names(model_paths),
  model_labels = model_display_names[names(model_paths)],
  out_path     = tex_output_path
)

############################################
# Classification scoreboard 
############################################
# One column per binary field, one row per metric, one dot per model at
# that (metric, field) — unconnected, so it's a direct side-by-side
# comparison of all three models on each metric rather than a line implying
# trend across metrics (which don't have a natural order/scale to trend
# along). Vertical guides at 50% (chance) and 80% (a common "good enough"
# bar) give fixed reference points across every panel.
build_classification_scoreboard_plot <- function(results, model_keys, model_labels, out_path) {
  if (dir.exists(out_path) || grepl("/$", out_path)) {
    out_path <- file.path(out_path, "classification_scoreboard.png")
  }

  field_order  <- c("Empirical Analysis", "Endogeneity Problem", "Has IV", "Is Rainfall IV")
  metric_order <- c("Accuracy", "Sensitivity", "Specificity", "Precision", "F1", "Balanced Accuracy")
  metric_keys  <- c(
    "Accuracy"          = "accuracy",
    "Sensitivity"       = "sensitivity",
    "Specificity"       = "specificity",
    "Precision"         = "precision",
    "F1"                = "f1",
    "Balanced Accuracy" = "balanced_accuracy"
  )

  dot_data <- bind_rows(lapply(model_keys, function(m) {
    b <- results[[m]]$binary
    bind_rows(lapply(field_order, function(field) {
      row <- b[b$field == field, ]
      data.frame(
        model  = model_labels[[m]],
        field  = field,
        metric = metric_order,
        value  = as.numeric(row[1, metric_keys[metric_order]]) * 100
      )
    }))
  }))

  dot_data$model  <- factor(dot_data$model, levels = unname(model_labels[model_keys]))
  dot_data$field  <- factor(dot_data$field, levels = field_order)
  # rev() so Accuracy (first in metric_order) plots at the top.
  dot_data$metric <- factor(dot_data$metric, levels = rev(metric_order))

  # Same 3-slot model palette used for the KDE density plot, so a model's
  # color means the same thing everywhere in this script's output.
  palette      <- c("#08B2E3", "#484D6D", "#57A773")
  model_colors <- setNames(palette[seq_along(model_keys)], unname(model_labels[model_keys]))

  # Manual per-model y-offset (rather than ggplot's position_dodge, which
  # dodges along x by default) so dots land at fixed, predictable rows.
  offsets <- setNames(seq(0.22, -0.22, length.out = length(model_keys)), unname(model_labels[model_keys]))
  dot_data$metric_num <- as.numeric(dot_data$metric) + offsets[as.character(dot_data$model)]

  p <- ggplot(dot_data, aes(x = value, y = metric_num, color = model)) +
    geom_vline(xintercept = c(50, 80), color = "#D6D6D6", linewidth = 0.5) +
    geom_point(size = 2.6) +
    scale_color_manual(values = model_colors, name = NULL) +
    scale_x_continuous(limits = c(0, 100), breaks = c(0, 50, 100)) +
    scale_y_continuous(breaks = seq_along(metric_order), labels = rev(metric_order),
                        limits = c(0.5, length(metric_order) + 0.5)) +
    facet_wrap(~ field, nrow = 1) +
    labs(x = "Performance (%)", y = NULL, title = "Classification performance by field") +
    theme_minimal(base_size = 11) +
    theme(
      panel.grid.minor = element_blank(),
      panel.grid.major.y = element_blank(),
      strip.text        = element_text(face = "bold"),
      plot.title         = element_text(hjust = 0),
      legend.position    = "top"
    )

  dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
  ggsave(out_path, plot = p, width = 12, height = 4.3, dpi = 150, bg = "white")
  cat("\nClassification scoreboard written to:", out_path, "\n")
}

build_classification_scoreboard_plot(
  results,
  model_keys   = names(model_paths),
  model_labels = model_display_names[names(model_paths)],
  out_path     = tex_output_path
)

