# Project: WB Weather - metric
# Created on: 2 Nov 2026
# Created by: codex
# edited by: codex
# edited on: 2 Nov 2026
# Python 3
# does
	# assembles three redesigned appendix figures from native Stata vectors
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


def legend(c, y, entries, width, size=12):
	c.setFont("Helvetica", size)
	lengths = [c.stringWidth(label, "Helvetica", size) + 32 for label, *_ in entries]
	x = (width - sum(lengths) - 18 * (len(entries) - 1)) / 2
	for length, (label, color, dashed, symbol) in zip(lengths, entries):
		c.setStrokeColorRGB(*color)
		c.setFillColorRGB(*color)
		c.setLineWidth(.9)
		c.setDash([5, 3] if dashed else [])
		if symbol not in ("square", "point"):
			c.line(x, y + 3, x + 22, y + 3)
		if symbol in ("circle", "point"):
			c.circle(x + 11, y + 3, 2.3, fill=1, stroke=0)
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
# 2 - paired difference of increments, with descriptive fold percentiles
##############################################################################

forest = values("front_forest_values.csv")
xmin, xmax = forest[0]["x_min"], forest[0]["x_max"]
width, height = 522, 349.2
writer, page, overlay, c = sheet(width, height)
left, cell_width, cell_height = 85, 425, 115.2
for outcome, title, y in ((1, "Farm Production Value", 209.8), (2, "Maize Yield", 68.8)):
	place(page, f"forest_{outcome}.pdf", left, y, cell_width, cell_height)
	text(c, left + cell_width / 2, y + cell_height + 10, title, 11, True)
	for i, (_, country) in enumerate(countries):
		text(c, left - 8, y + cell_height * (1 - (i + .5) / 6) - 3.5,
			country, 10.5, align="right")
	if outcome == 2:
		ticks = [(i / 100, f"{i / 100:.2f}") for i in range(-20, 21, 5)]
		horizontal(c, left, y, cell_width, xmin, xmax, ticks, size=10)
text(c, width / 2, 29, "Extra Search-Induced Training-Validation Gap With Household FE", 10.5)
finish(writer, overlay, c, "front_increment_forest")


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
