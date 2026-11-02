# Project: WB Weather - metric
# Created on: 2 Nov 2026
# Created by: codex
# edited by: codex
# edited on: 2 Nov 2026
# Python 3
# does
	# assembles the appendix figures from native Stata vector components
# assumes
	# metric_app.do has run; pypdf, reportlab and Poppler are installed
# TO DO:
	# done

import argparse
from io import BytesIO
import math
from pathlib import Path
import subprocess

from pypdf import PdfReader, PdfWriter, Transformation
from reportlab.pdfgen import canvas


##############################################################################
# 0 - setup and vector placement
##############################################################################

parser = argparse.ArgumentParser(description="Assemble the two appendix figures.")
parser.add_argument("data", type=Path, help="Project data root used by Stata's $data.")
parser.add_argument("--pdftoppm", default="pdftoppm")
args = parser.parse_args()
parts = args.data / "results_data/additional_evidence/appendix/components"
figures = args.data / "results_data/figures/metric_paper"
blue = (40 / 255, 86 / 255, 154 / 255)
copper = (194 / 255, 123 / 255, 65 / 255)
ink = (38 / 255, 43 / 255, 47 / 255)
countries = ("Ethiopia", "Malawi", "Niger", "Nigeria", "Tanzania", "Uganda")


def place(target, source, x, y, width, height):
	page = PdfReader(source).pages[0]
	transform = Transformation().scale(width / float(page.mediabox.width),
		height / float(page.mediabox.height)).translate(x, y)
	target.merge_transformed_page(page, transform)


def finish(writer, overlay, name):
	overlay.seek(0)
	writer.pages[0].merge_page(PdfReader(overlay).pages[0])
	path = figures / f"{name}.pdf"
	with path.open("wb") as output:
		writer.write(output)
	flags = subprocess.CREATE_NO_WINDOW if hasattr(subprocess, "CREATE_NO_WINDOW") else 0
	subprocess.run([args.pdftoppm, "-singlefile", "-scale-to-x", "3200",
		"-scale-to-y", "-1", "-png", str(path), str(path.with_suffix(""))],
		check=True, creationflags=flags)
	print(f"Created {name}.pdf and {name}.png")


##############################################################################
# 1 - one six-row, four-column frontier matrix
##############################################################################

width, height = 648, 396
writer = PdfWriter()
page = writer.add_blank_page(width, height)
overlay = BytesIO()
c = canvas.Canvas(overlay, pagesize=(width, height))
left, gutter, gap, top = 92, 12, 9, height - 48
cell_width = (width - left - 8 - 3 * gutter) / 4
cell_height = cell_width * 1.35 / 4
centres = [left + i * (cell_width + gutter) + cell_width / 2 for i in range(4)]
c.setFillColorRGB(*ink)
c.setFont("Helvetica-Bold", 11)
c.drawCentredString((centres[0] + centres[1]) / 2, height - 15, "Farm Production Value")
c.drawCentredString((centres[2] + centres[3]) / 2, height - 15, "Maize Yield")
c.setFont("Helvetica", 9)
for x, label in zip(centres, ("(A) Year FE", "(B) Year + HH FE", "(C) Year FE", "(D) Year + HH FE")):
	c.drawCentredString(x, height - 34, label)
for row, country in enumerate(countries):
	y = top - (row + 1) * cell_height - row * gap
	c.setFillColorRGB(*ink)
	c.setFont("Helvetica-Bold", 9.5)
	c.drawString(25, y + cell_height / 2 - 3, country)
	for column in range(4):
		x = left + column * (cell_width + gutter)
		place(page, parts / f"front_{row + 1}_{column + 1}.pdf", x, y, cell_width, cell_height)
		c.setStrokeColorRGB(*ink)
		c.setLineWidth(.4)
		c.setFont("Helvetica", 8)
		if column == 0:
			c.line(x, y, x, y + cell_height)
			for value in (-.1, 0, .2, .4):
				position = y + (value + .1) / .5 * cell_height
				c.line(x - 3, position, x, position)
				c.drawRightString(x - 6, position - 2.7, f"{value:.1f}")
		if row == 5:
			c.line(x, y, x + cell_width, y)
			for k in (1, 3, 10, 40, 84):
				position = x + math.log(k) / math.log(84) * cell_width
				c.line(position, y, position, y - 3)
				c.drawCentredString(position, y - 12, str(k))
c.setFont("Helvetica", 9)
c.saveState()
c.translate(10, top - (6 * cell_height + 5 * gap) / 2)
c.rotate(90)
c.drawCentredString(0, 0, "Selected First-Stage Partial Correlation")
c.restoreState()
c.drawCentredString(width / 2, 18, "Number Of Candidate Instruments Considered, K")
labels = ("Selected In Training", "Same Instrument In Held-Out Data")
legend_width = sum(c.stringWidth(label, "Helvetica", 8.5) + 25 for label in labels) + 20
x = (width - legend_width) / 2
c.setFont("Helvetica", 8.5)
for color, label, dashed in zip((blue, copper), labels, (False, True)):
	c.setStrokeColorRGB(*color)
	c.setLineWidth(.75)
	c.setDash([4, 3] if dashed else [])
	c.line(x, 8, x + 18, 8)
	c.setFillColorRGB(*ink)
	c.drawString(x + 25, 5, label)
	x += 25 + c.stringWidth(label, "Helvetica", 8.5) + 20
c.showPage()
c.save()
finish(writer, overlay, "front_panel")


##############################################################################
# 2 - spatial score dependence and paired relevance shares, 60/40 widths
##############################################################################

writer = PdfWriter()
page = writer.add_blank_page(648, 360)
place(page, parts / "space_a.pdf", 0, 0, 378, 334.8)
place(page, parts / "space_b.pdf", 396, 0, 252, 334.8)
overlay = BytesIO()
c = canvas.Canvas(overlay, pagesize=(648, 360))
c.setFillColorRGB(*ink)
c.setFont("Helvetica-Bold", 10)
c.drawString(8, 346, "(A) Dependence In First-Stage Scores")
c.drawString(402, 346, "(B) Share With |t| > 1.96")
c.showPage()
c.save()
finish(writer, overlay, "space_panel")
