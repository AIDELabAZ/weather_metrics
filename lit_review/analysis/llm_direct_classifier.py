"""
Direct LLM classifier: Qwen3-32B (4-bit, MLX) reads the full taxonomy JSON and
puts each extracted entry into one category, Other, or Unclassifiable in a
single step. No embedding, reranker, gate or rule lists; it is the comparison
point for the longer pipeline in fixed_label_classifier.py.

Runs in its own venv (mlx-lm needs transformers 5.x, the main pipeline uses
4.x):  ~/venvs/mlx/bin/python analysis/llm_direct_classifier.py \
           --entries entries.json --cache analysis/.llm_direct_cache.json
Normally called by llm_direct_overview.py ("classify" step), not by hand.

entries.json: {"Rainfall Metrics": [...], "Endogenous Variables": [...]}.

Per entry the model answers {"reason", "category", "runner_up"} (thinking off,
greedy decoding). category_prob is the model's probability of the category
string it wrote, i.e. the product of the token probabilities inside the
"category" value; a low value is a close call. The system prompt (the whole
taxonomy) is prefilled once per side and its KV cache reused for every entry.

The cache is keyed by model + system prompt, so editing a taxonomy JSON or the
prompt starts a fresh namespace instead of serving stale answers. Resumable.
"""

import argparse
import difflib
import hashlib
import json
import os
import re
import time

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_MODEL = "mlx-community/Qwen3-32B-4bit"
TAXONOMY_DIR = os.path.join(HERE, "taxonomies")
TAXONOMY_FILES = {
    "Rainfall Metrics": "rainfall_measures_taxonomy.json",
    "Endogenous Variables": "economic_concepts_taxonomy.json",
}
SIDE_INTRO = {
    "Rainfall Metrics": (
        "Each entry is the name of a rainfall (precipitation) variable that an economics paper used as an "
        "instrumental variable."),
    "Endogenous Variables": (
        "Each entry is the name of an endogenous variable that an economics paper instrumented with rainfall."),
}
PROMPT_VERSION = "direct-v1"

# --rules: the hand-written decision rules (Nov 18), appended after the categories. Bare rainfall ("rainfall",
# "precipitation", ...) is NOT in the prompt: it is handled after the model by the BARE_RAINFALL filter, as in
# 32b_direct, so the model's behaviour on everything else stays as close to 32b_direct as possible.
RULES = {
    "common": [
        "Classify whenever reasonably possible: assign the most plausible substantive category, even when the "
        "variable's precise construction is unknown.",
        "Reserve Unclassifiable for genuinely uninterpretable entries, such as x1, driving factor, corrupted text, "
        "or generic placeholders that provide no meaningful information about the variable.",
        "Use Other only as a last resort: the variable must be interpretable but genuinely outside the scope of "
        "every substantive category.",
    ],
    "Rainfall Metrics": [
        'Example: "rainfall shock" is Two-sided rainfall extremes, unless additional information clearly identifies '
        "a different construction.",
    ],
    "Endogenous Variables": [],
}


def rules_text(side: str) -> str:
    rules = RULES["common"] + RULES[side]
    return "\n\nDecision rules:\n" + "\n".join(f"{i}. {r}" for i, r in enumerate(rules, 1))


def load_taxonomy(side: str) -> dict:
    with open(os.path.join(TAXONOMY_DIR, TAXONOMY_FILES[side]), encoding="utf-8") as f:
        return json.load(f)


HINTS_TEXT = (
    "\n\nEach entry also comes with suggestions from two smaller models: the 5 categories an embedding model "
    "retrieved as most similar (with cosine similarity), re-scored by a reranker model (P(relevant), 0-1, each "
    "category scored independently), listed best reranker score first. Weigh them as evidence; they can be wrong, "
    "and you may choose any category in the taxonomy, including ones not suggested."
)


def system_prompt(side: str, tax: dict, rules: bool = False, context: bool = False, hints: bool = False) -> str:
    lines = []
    for i, c in enumerate(tax["categories"], 1):
        line = f"{i}. {c['category']}: {c['description'].strip().rstrip('.')}."
        if c.get("examples"):
            line += " Examples: " + "; ".join(c["examples"]) + "."
        if c.get("jel_codes"):
            line += " JEL anchors: " + ", ".join(c["jel_codes"]) + "."
        lines.append(line)
    return (
        "You classify variable names from economics papers into a fixed taxonomy.\n"
        f"{SIDE_INTRO[side]} The names were extracted from the papers by a language model. "
        + ("Each entry comes with context from its paper (title, dependent variable, and the paper's extracted "
           "rainfall and endogenous variables); use it to interpret the entry. "
           if context else
           "Only the extracted name is available, with no other context from the paper. ")
        + "Names may be lower-cased, abbreviated, truncated, or contain extraction errors.\n\n"
        f"TAXONOMY: {tax['title']}\n"
        f"Guidance: {tax['note']}\n\n"
        "Categories (answer with one of these names exactly as written):\n"
        + "\n".join(lines)
        + (rules_text(side) if rules else "")
        + (HINTS_TEXT if hints else "")
        + "\n\nAnswer with one JSON object and nothing else:\n"
        '{"reason": "<one short sentence, at most 20 words>", "category": "<exact category name>", '
        '"runner_up": "<exact name of the next most plausible category>"}'
    )


def match_category(text: str, names: list[str]) -> str:
    t = (text or "").strip().strip(".").lower()
    for n in names:
        if n.lower() == t:
            return n
    close = difflib.get_close_matches(t, [n.lower() for n in names], n=1, cutoff=0.85)
    return next(n for n in names if n.lower() == close[0]) if close else ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--entries", required=True)
    ap.add_argument("--cache", required=True)
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--limit", type=int, default=0, help="only the first N new entries per side (testing)")
    ap.add_argument("--max-tokens", type=int, default=160)
    ap.add_argument("--rules", action="store_true", help="append the decision rules (RULES) to the prompt")
    args = ap.parse_args()

    import mlx.core as mx
    from mlx_lm import load
    from mlx_lm.generate import generate_step
    from mlx_lm.models.cache import make_prompt_cache, trim_prompt_cache

    with open(args.entries, encoding="utf-8") as f:
        entries = json.load(f)
    cache_db = {}
    if os.path.exists(args.cache):
        with open(args.cache, encoding="utf-8") as f:
            cache_db = json.load(f)

    def save():
        tmp = args.cache + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(cache_db, f, ensure_ascii=False, indent=0)
        os.replace(tmp, args.cache)

    print(f"Loading {args.model} ...", flush=True)
    model, tok = load(args.model)
    eos = set(tok.eos_token_ids)

    for side, side_entries in entries.items():
        tax = load_taxonomy(side)
        names = [c["category"] for c in tax["categories"]]
        # Items are plain names, or {"id", "entry", "context", "hints"} (keyed by id): context = paper context for
        # one entry in one paper, hints = embedder/reranker suggestions text. Either may be "".
        items = [x if isinstance(x, dict) else {"id": x, "entry": x} for x in side_entries]
        for x in items:
            x.setdefault("context", "")
            x.setdefault("hints", "")
        with_context = any(x["context"] for x in items)
        with_hints = any(x["hints"] for x in items)
        sys_text = system_prompt(side, tax, rules=args.rules, context=with_context, hints=with_hints)
        ns = f"{args.model}|{PROMPT_VERSION}|" + hashlib.sha256(sys_text.encode()).hexdigest()[:16]
        done = cache_db.setdefault(ns, {"side": side, "model": args.model, "prompt": sys_text, "results": {}})["results"]
        todo = [x for x in items if x["id"] not in done]
        if args.limit:
            todo = todo[: args.limit]
        print(f"\n[{side}] {len(items)} entries, {len(todo)} to classify (namespace {ns.split('|')[-1]})",
              flush=True)
        if not todo:
            continue

        def render(item, retry=None):
            user = f"Entry: {item['entry']}"
            if item["context"]:
                user += f"\n\nPaper context:\n{item['context']}"
            if item["hints"]:
                user += f"\n\nSuggestions from the smaller models:\n{item['hints']}"
            msgs = [{"role": "system", "content": sys_text}, {"role": "user", "content": user}]
            if retry:  # (previous answer, bad name): ask once more for an exact category name
                msgs += [{"role": "assistant", "content": retry[0]},
                         {"role": "user", "content": f'"{retry[1]}" is not one of the category names. Answer again '
                                                     "with the same JSON format, using a category name exactly as "
                                                     "written in the list."}]
            return tok.apply_chat_template(msgs, add_generation_prompt=True, enable_thinking=False, tokenize=False)

        def ask(item, retry=None):
            full = render(item, retry)
            assert full.startswith(probe[:cut])
            suffix_ids = tok.encode(full[cut:], add_special_tokens=False)
            pieces, lps = [], []
            for token, logprobs in generate_step(mx.array(suffix_ids), model, max_tokens=args.max_tokens,
                                                 prompt_cache=prompt_cache):
                token = int(token)
                if token in eos:
                    break
                pieces.append(tok.decode([token]))
                lps.append(float(logprobs[token].item()))
                if "}" in pieces[-1]:
                    break
            trim_prompt_cache(prompt_cache, prompt_cache[0].offset - n_prefix)
            text = "".join(pieces)
            m = re.search(r"\{.*\}", text, re.S)
            try:
                obj = json.loads(m.group(0), strict=False) if m else {}  # entries can contain control chars
            except json.JSONDecodeError:
                obj = {}
            # Probability of the category value: tokens overlapping its span in the output.
            prob = None
            mm = re.search(r'"category"\s*:\s*"([^"]*)"', text)
            if mm:
                lo, hi = mm.span(1)
                pos, s = 0, 0.0
                for p, lp in zip(pieces, lps):
                    if pos < hi and pos + len(p) > lo:
                        s += lp
                    pos += len(p)
                prob = round(float(2.718281828459045 ** s), 4)
            return text, obj, prob

        probe = render({"entry": "x", "context": "", "hints": ""})
        cut = probe.index("<|im_start|>user")
        prefix_ids = tok.encode(probe[:cut], add_special_tokens=False)
        prompt_cache = make_prompt_cache(model)
        ids = mx.array(prefix_ids)
        for i in range(0, len(prefix_ids), 2048):
            model(ids[None, i:i + 2048], cache=prompt_cache)
            mx.eval([c.state for c in prompt_cache])
        n_prefix = prompt_cache[0].offset
        print(f"  system prompt: {n_prefix} tokens (cached)", flush=True)

        t0 = time.time()
        for k, item in enumerate(todo, 1):
            entry = item["entry"]
            text, obj, prob = ask(item)
            cat = match_category(obj.get("category", ""), names)
            retried = False
            if not cat:
                retried = True
                text2, obj2, prob2 = ask(item, retry=(text, obj.get("category", "") or text))
                if match_category(obj2.get("category", ""), names):
                    text, obj, prob = text2, obj2, prob2
                    cat = match_category(obj.get("category", ""), names)
            done[item["id"]] = {
                "entry": entry,
                "category": cat,
                "runner_up": match_category(obj.get("runner_up", ""), names),
                "reason": obj.get("reason", ""),
                "category_prob": prob,
                "retried": retried,
                "raw": text,
            }
            if not done[item["id"]]["category"]:
                print(f"  ! unparsed for {entry!r}: {text!r}", flush=True)
            if k % 25 == 0 or k == len(todo):
                rate = (time.time() - t0) / k
                print(f"  {k}/{len(todo)}  {rate:.1f}s/entry  ~{rate * (len(todo) - k) / 60:.0f} min left",
                      flush=True)
                save()
        save()
    print("done", flush=True)


if __name__ == "__main__":
    main()
