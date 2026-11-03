# Project: WB Weather - metric
# Created on: 2 Nov 2026
# Created by: codex
# edited by: codex
# edited on: 3 Nov 2026
# Python 3
# does
	# assembles appendix frontiers, payoff candidates and spatial comparisons
# assumes
	# metric_app_fit.do has run; pypdf, reportlab and Poppler are installed
# TO DO:
	# done

import argparse
import csv
from io import BytesIO
import math
from pathlib import Path
import subprocess

from pypdf import PdfReader, PdfWriter, Transformation
from reportlab.pdfgen import canvas


##############################################################################
# 0 - setup and physical-size labels
##############################################################################

parser = argparse.ArgumentParser(description="Assemble the redesigned appendix figures.")
parser.add_argument("data", type=Path, help="Project data root used by Stata's $data.")
parser.add_argument("--pdftoppm", default="pdftoppm")
parser.add_argument("--keep-front", action="store_true",
	help="Preserve the approved frontier PDF and PNG without exporting them.")
args = parser.parse_args()
out = args.data / "results_data/additional_evidence/appendix"
figures = args.data / "results_data/figures/metric_paper"
countries = ((1, "Ethiopia"), (2, "Malawi"), (4, "Niger"),
	(5, "Nigeria"), (6, "Tanzania"), (7, "Uganda"))
ink = (38 / 255, 43 / 255, 47 / 255)
blue = (40 / 255, 86 / 255, 154 / 255)
copper = (194 / 255, 123 / 255, 65 / 255)
teal = (24 / 255, 105 / 255, 112 / 255)
plum = (124 / 255, 83 / 255, 117 / 255)
gray = (100 / 255, 105 / 255, 110 / 255)
red = (145 / 255, 48 / 255, 59 / 255)


def values(name):
	with (out / name).open(newline="", encoding="utf-8-sig") as source:
		return [{k: float(v) for k, v in row.items()} for row in csv.DictReader(source)]


def sheet(width, height):
	writer = PdfWriter()
	page = writer.add_blank_page(width, height)
	overlay = BytesIO()
	c = canvas.Canvas(overlay, pagesize=(width, height))
	return writer, page, overlay, c


def place(page, name, x, y, width, height):
	source = PdfReader(out / "fit" / name).pages[0]
	transform = Transformation().scale(width / float(source.mediabox.width),
		height / float(source.mediabox.height)).translate(x, y)
	page.merge_transformed_page(source, transform)


def text(c, x, y, label, size=12, bold=False, align="center"):
	c.setFillColorRGB(*ink)
	c.setFont("Helvetica-Bold" if bold else "Helvetica", size)
	getattr(c, {"center": "drawCentredString", "left": "drawString",
		"right": "drawRightString"}[align])(x, y, label)


def horizontal(c, x, y, width, low, high, ticks, log=False, size=11):
	c.setStrokeColorRGB(*ink)
	c.setLineWidth(.45)
	c.line(x, y, x + width, y)
	for value, label in ticks:
		fraction = math.log(value / low) / math.log(high / low) if log else (value - low) / (high - low)
		position = x + width * fraction
		c.line(position, y, position, y - 3)
		align = "left" if value == low else "right" if value == high else "center"
		text(c, position, y - 14, label, size, align=align)


def vertical(c, x, y, height, low, high, ticks, size=11):
	c.setStrokeColorRGB(*ink)
	c.setLineWidth(.45)
	c.line(x, y, x, y + height)
	for value, label in ticks:
		position = y + height * (value - low) / (high - low)
		c.line(x - 3, position, x, position)
		text(c, x - 6, position - 3.5, label, size, align="right")


def rotated(c, x, y, label, size=12.5):
	c.saveState()
	c.translate(x, y)
	c.rotate(90)
	text(c, 0, 0, label, size)
	c.restoreState()


def arrow_head(c, start, end, y, color, clearance=3):
	# Keep the tip outside the endpoint marker and cap its size to the actual gap.
	if start == end:
		return
	direction = 1 if end > start else -1
	available = max(0, abs(end - start) - 2 * clearance)
	length = min(5, available / 2)
	if length == 0:
		return
	tip = end - direction * clearance
	base = tip - direction * length
	c.setFillColorRGB(*color)
	p = c.beginPath()
	p.moveTo(tip, y)
	p.lineTo(base, y + length * .45)
	p.lineTo(base, y - length * .45)
	p.close()
	c.drawPath(p, fill=1, stroke=0)


def legend(c, y, entries, width, size=12):
	c.setFont("Helvetica", size)
	lengths = [c.stringWidth(label, "Helvetica", size) + 32 for label, *_ in entries]
	x = (width - sum(lengths) - 18 * (len(entries) - 1)) / 2
	for length, (label, color, dashed, symbol) in zip(lengths, entries):
		c.setStrokeColorRGB(*color)
		c.setFillColorRGB(*color)
		c.setLineWidth(.9)
		c.setDash([5, 3] if dashed else [])
		if symbol not in ("square", "point", "openpoint"):
			c.line(x, y + 3, x + 22, y + 3)
		if symbol in ("circle", "point"):
			c.circle(x + 11, y + 3, 2.3, fill=1, stroke=0)
		elif symbol == "openpoint":
			c.setFillColorRGB(1, 1, 1)
			c.circle(x + 11, y + 3, 2.3, fill=1, stroke=1)
		elif symbol == "diamond":
			p = c.beginPath()
			p.moveTo(x + 11, y + 6)
			for point in ((x + 14, y + 3), (x + 11, y), (x + 8, y + 3)):
				p.lineTo(*point)
			p.close()
			c.drawPath(p, fill=1, stroke=0)
		elif symbol == "square":
			c.rect(x + 8.5, y + .5, 5, 5, fill=1, stroke=0)
		text(c, x + 30, y, label, size, align="left")
		x += length + 18
	c.setDash([])


def finish(writer, overlay, c, name):
	c.showPage()
	c.save()
	overlay.seek(0)
	writer.pages[0].merge_page(PdfReader(overlay).pages[0])
	path = figures / f"{name}.pdf"
	with path.open("wb") as target:
		writer.write(target)
	flags = subprocess.CREATE_NO_WINDOW if hasattr(subprocess, "CREATE_NO_WINDOW") else 0
	subprocess.run([args.pdftoppm, "-singlefile", "-scale-to-x", "3200",
		"-scale-to-y", "-1", "-png", str(path), str(path.with_suffix(""))],
		check=True, creationflags=flags)
	print(f"Created {name}.pdf and {name}.png")


##############################################################################
# 1 - country-outcome frontiers; color identifies FE, pattern identifies sample
##############################################################################

if not args.keep_front:
	front = values("front_fit_values.csv")
	ymin, ymax = front[0]["y_min"], front[0]["y_max"]
	width, height = 828, 576
	writer, page, overlay, c = sheet(width, height)
	left, gutter, cell_height = 44, 11, 148
	cell_width = (width - left - 8 - 3 * gutter) / 4
	for i, (country, name) in enumerate(countries):
		for outcome, outcome_name in ((1, "Value"), (2, "Maize")):
			row, column = i // 2, 2 * (i % 2) + outcome - 1
			x, y = left + column * (cell_width + gutter), 402 - row * 173
			place(page, f"front_{country}_{outcome}.pdf", x, y, cell_width, cell_height)
			text(c, x + cell_width / 2, y + cell_height + 8, f"{name} · {outcome_name}", 12.3, True)
			if column == 0:
				vertical(c, x, y, cell_height, ymin, ymax,
					[(v, f"{v:.2f}") for v in (-.1, 0, .1, .2, .3)], 11)
			if row == 2:
				horizontal(c, x, y, cell_width, 1, 84,
					[(k, str(k)) for k in (1, 3, 10, 40, 84)], log=True, size=11)
	rotated(c, 10, 303, "Selected First-Stage Partial Correlation", 12.5)
	text(c, width / 2, 28, "Number Of Candidate Instruments, K", 12.5)
	legend(c, 8, [("Year FE: Training", blue, False, None),
		("Year FE: Held-Out", blue, True, None),
		("Year + Household FE: Training", copper, False, None),
		("Year + Household FE: Held-Out", copper, True, None)], width, 12)
	finish(writer, overlay, c, "front_panel_fit")


##############################################################################
# 2 - paired search-gain arrows and the alternative scatter
##############################################################################

gains = values("front_payoff_values.csv")
assert len(gains) == 24
assert {v["country"] for v in gains} == {c for c, _ in countries}
assert {v["outcome"] for v in gains} == {1, 2}
assert {v["spec"] for v in gains} == {2, 7}
xmin, xmax = gains[0]["x_min"], gains[0]["x_max"]
width, height = 828, 468
writer, page, overlay, c = sheet(width, height)
left, gap, cell_width, cell_height, bottom = 84, 92, 319, 365, 60
for outcome, title in ((1, "(A)"), (2, "(B)")):
	x = left + (outcome - 1) * (cell_width + gap)
	place(page, f"payoff_arrows_{outcome}.pdf", x, bottom, cell_width, cell_height)
	for v in gains:
		if v["outcome"] != outcome:
			continue
		row = next(i for i, (country, _) in enumerate(countries) if country == v["country"])
		position = row + 1 + (-.18 if v["spec"] == 7 else .18)
		y = bottom + cell_height * (1 - (position - .5) / 6)
		start = x + cell_width * (v["train"] - xmin) / (xmax - xmin)
		end = x + cell_width * (v["holdout"] - xmin) / (xmax - xmin)
		arrow_head(c, start, end, y, blue if v["spec"] == 7 else copper)
	text(c, x + cell_width / 2, bottom + cell_height + 14, title, 13.5, True)
	for i, (_, country) in enumerate(countries):
		text(c, x - 9, bottom + cell_height * (1 - (i + .5) / 6) - 4,
			country, 13, align="right")
	ticks = [(i / 100, f"{i / 100:.2f}") for i in range(-5, 21, 5)]
	horizontal(c, x, bottom, cell_width, xmin, xmax, ticks, size=12)
text(c, width / 2, 31, "Search Gain In First-Stage Partial Correlation", 13)
legend(c, 10, [("Year FE", blue, False, None),
	("Year + Household FE", copper, False, None),
	("Training", ink, False, "point"), ("Held-Out", ink, False, "openpoint")], width, 12)
finish(writer, overlay, c, "front_payoff_arrows")


def country_labels(c, points, bounds):
	# Place short labels near the actual points, avoiding labels and marker boxes.
	boxes = [(x - 4, y - 4, x + 4, y + 4) for x, y, *_ in points]
	for x, y, label, color in points:
		label_width = c.stringWidth(label, "Helvetica", 11.5)
		options = []
		for dx in (8, -label_width - 8, 22, -label_width - 22, 36, -label_width - 36):
			for dy in (7, -14, 21, -28, 35, -42):
				a, b = x + dx, y + dy
				rect = (a - 2, b - 3, a + label_width + 2, b + 11)
				if rect[0] < bounds[0] or rect[1] < bounds[1] or rect[2] > bounds[2] or rect[3] > bounds[3]:
					continue
				if any(rect[0] < r[2] and rect[2] > r[0] and
					rect[1] < r[3] and rect[3] > r[1] for r in boxes):
					continue
				options.append((dx * dx + dy * dy, a, b, rect))
		if not options:
			raise ValueError(f"Country label needs more room: {label}")
		_, a, b, rect = min(options)
		boxes.append(rect)
		c.setStrokeColorRGB(*color)
		c.setLineWidth(.45)
		c.line(x, y, min(max(x, a), a + label_width), b + 3)
		c.setFillColorRGB(*color)
		c.setFont("Helvetica", 11.5)
		c.drawString(a, b, label)


width, height = 828, 453.6
writer, page, overlay, c = sheet(width, height)
left, gap, cell_width, bottom = 54, 36, 365, 56
smin, smax = gains[0]["s_min"], gains[0]["s_max"]
abbreviations = {1: "ETH", 2: "MWI", 4: "NER", 5: "NGA", 6: "TZA", 7: "UGA"}
ticks = [(i / 100, f"{i / 100:.2f}") for i in range(0, 21, 5)]
for outcome, title in ((1, "(A)"), (2, "(B)")):
	x = left + (outcome - 1) * (cell_width + gap)
	place(page, f"payoff_scatter_{outcome}.pdf", x, bottom, cell_width, cell_width)
	text(c, x + cell_width / 2, bottom + cell_width + 12, title, 13.5, True)
	horizontal(c, x, bottom, cell_width, smin, smax, ticks, size=12)
	vertical(c, x, bottom, cell_width, smin, smax, ticks, size=12)
	points = [(x + (v["train"] - smin) / (smax - smin) * cell_width,
		bottom + (v["holdout"] - smin) / (smax - smin) * cell_width,
		abbreviations[int(v["country"])], blue if v["spec"] == 7 else copper)
		for v in gains if v["outcome"] == outcome]
	country_labels(c, points, (x + 3, bottom + 3, x + cell_width - 3, bottom + cell_width - 3))
rotated(c, 12, bottom + cell_width / 2, "Held-Out Search Gain", 13)
text(c, width / 2, 27, "Training Search Gain", 13)
legend(c, 7, [("Year FE", blue, False, "point"),
	("Year + Household FE", copper, False, "point")], width, 12)
finish(writer, overlay, c, "front_payoff_scatter")


##############################################################################
# 3 - metric-specific score diagnostics and outcome-specific relevance shares
##############################################################################

scores = values("space_fit_values.csv")
shares = values("space_outcome_values.csv")
width, height = 828, 612
writer, page, overlay, c = sheet(width, height)
text(c, 16, 600, "(A) First-Stage Score Dependence By Distance", 13, True, "left")
left, gutter, cell_height = 46, 26, 111.6
cell_width = (width - left - 6 - 2 * gutter) / 3
for i, (country, name) in enumerate(countries):
	x, y = left + (i % 3) * (cell_width + gutter), 465.4 - (i // 3) * 127.6
	entry = next(v for v in scores if v["country"] == country)
	low, high, step = entry["y_min"], entry["y_max"], entry["y_step"]
	place(page, f"score_{country}.pdf", x, y, cell_width, cell_height)
	text(c, x + cell_width / 2, y + cell_height + 8, name, 12.8, True)
	digits = 3 if step < .01 else 2
	first, last = math.ceil(low / step - 1e-8), math.floor(high / step + 1e-8)
	ticks = [(n * step, f"{n * step:.{digits}f}") for n in range(first, last + 1)]
	vertical(c, x, y, cell_height, low, high, ticks, 11.5)
	if i >= 3:
		horizontal(c, x, y, cell_width, .5, 5.5,
			list(enumerate(("0-25", "25-50", "50-100", "100-200", "200-300"), 1)), size=11.5)
rotated(c, 10, 457, "Mean Standardized First-Stage Score Cross-Product", 12.8)
text(c, width / 2, 307.5, "EA Distance Bin (Km)", 12.8)
legend(c, 289.5, [("Seasonal Rainfall", teal, False, "circle"),
	("Rainy Days", plum, True, "diamond")], width, 12.5)
text(c, 16, 270, "(B) Outcome-Specific First-Stage Significance", 13, True, "left")
left, cell_width, cell_height = 99, 715, 86.4
xmax = shares[0]["x_max"]
for outcome, title, y in ((1, "Farm Production Value", 157), (2, "Maize Yield", 45)):
	place(page, f"share_{outcome}.pdf", left, y, cell_width, cell_height)
	for i, (country, _) in enumerate(countries):
		entry = next(v for v in shares if v["country"] == country and v["outcome"] == outcome)
		row_y = y + cell_height * (1 - (i + .5) / 6)
		start = left + cell_width * entry["share_hh"] / xmax
		end = left + cell_width * entry["share_sp"] / xmax
		arrow_head(c, start, end, row_y, (170 / 255,) * 3)
	text(c, left + cell_width / 2, y + cell_height + 7, title, 12.8, True)
	for i, (_, country) in enumerate(countries):
		text(c, left - 8, y + cell_height * (1 - (i + .5) / 6) - 4,
			country, 12.8, align="right")
	if outcome == 2:
		horizontal(c, left, y, cell_width, 0, xmax,
			[(v, str(v)) for v in range(0, int(xmax) + 1, 10)], size=11.5)
text(c, width / 2, 18, "Share Of First-Stage Specifications With |t| > 1.96 (%)", 12.8)
legend(c, 3, [("Household-Clustered SE", gray, False, "point"),
	("Spatial SE (100 Km)", red, False, "square")], width, 12.5)
finish(writer, overlay, c, "space_panel_revised")
