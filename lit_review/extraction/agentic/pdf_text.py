"""
PDF -> text for the agentic extractor.

Unlike extraction/*/*_gpt.py::extract_relevant_sections (which keyword-filters
paragraphs and collapses newlines), this keeps page and line structure so a
sectionizer can see headings. PyMuPDF only; retries for OneDrive file hydration.
"""
import re
import time

import fitz  # PyMuPDF

MAX_CHARS = 60_000


def extract_pages(pdf_path, max_retries=4, base_delay=3.0):
    """Return list[str], one entry per page (plain text). [] on total failure."""
    last_err = None
    for attempt in range(max_retries):
        try:
            with fitz.open(pdf_path) as doc:
                return [page.get_text("text") for page in doc]
        except Exception as e:  # noqa: BLE001 - OneDrive placeholder / corrupt file
            last_err = e
            time.sleep(base_delay * (attempt + 1))
    print(f"    [pdf_text] failed to open {pdf_path}: {last_err}")
    return []


def build_document(pdf_path, max_chars=MAX_CHARS):
    """
    Return (doc_text, meta).
      doc_text: pages joined with '[[page N]]' markers, capped at max_chars.
      meta: {"n_pages", "truncated", "empty"}
    """
    pages = extract_pages(pdf_path)
    if not pages:
        return "", {"n_pages": 0, "truncated": False, "empty": True}

    parts = []
    for i, txt in enumerate(pages, 1):
        txt = re.sub(r"[ \t]+\n", "\n", txt or "")
        txt = re.sub(r"\n{3,}", "\n\n", txt).strip()
        parts.append(f"[[page {i}]]\n{txt}")
    full = "\n\n".join(parts)

    truncated = len(full) > max_chars
    if truncated:
        full = full[:max_chars]
    return full, {
        "n_pages": len(pages),
        "truncated": truncated,
        "empty": len(full.strip()) < 200,
    }


_WS = re.compile(r"\s+")
_KEEP = re.compile(r"[^a-z0-9 ]+")
_LIG = {"ﬀ": "ff", "ﬁ": "fi", "ﬂ": "fl", "ﬃ": "ffi", "ﬄ": "ffl"}


def norm_for_match(s):
    """Aggressive normalization so a model 'quote' can be checked against PyMuPDF
    text despite ligatures (fi/fl), the comma->semicolon CSV artifact, hyphenation,
    smart quotes, and 2-column line-break noise: everything -> lowercase word stream."""
    s = (s or "").lower()
    for k, v in _LIG.items():
        s = s.replace(k, v)
    s = s.replace("-\n", "").replace("­", "")
    s = _KEEP.sub(" ", s)
    s = _WS.sub(" ", s)
    return s.strip()


def quote_in_text(quote, doc_text, min_len=10):
    """True if `quote` appears in `doc_text` after aggressive normalization, or if
    >=70% of its 4-word shingles do (tolerates minor drift / column interleave)."""
    q = norm_for_match(quote)
    if len(q) < min_len:
        return False
    d = norm_for_match(doc_text)
    if q in d:
        return True
    words = q.split()
    if len(words) < 6:
        return False
    shingles = [" ".join(words[i:i + 4]) for i in range(0, len(words) - 3, 2)]
    if not shingles:
        return False
    hit = sum(1 for sh in shingles if sh in d)
    return hit / len(shingles) >= 0.70
