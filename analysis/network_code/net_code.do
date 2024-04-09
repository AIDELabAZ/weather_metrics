* Project: WB Weather
* Created on: March 2024
* Created by: jdm
* Edited by: jdm
* Last edit: 28 March 2024
* Stata v.18.0 

* does
	* reads in excel file with papers
	* makes network visualziation 

* assumes
	* paper data file
	* nwcommands

* TO DO:
	* everything

	
************************************************************************
**# 0 - setup
************************************************************************

* define paths
	global	root 	= 	"$data/output/iv_lit"
	global	stab 	= 	"$data/results_data/tables"
	global	xtab 	= 	"$data/output/metric_paper/tables"
	global	sfig	= 	"$data/results_data/figures"	
	global 	xfig    =   "$data/output/metric_paper/figures"
	global	logout 	= 	"$data/results_data/logs"

* open log	
	cap log close
	log 	using 	"$logout/network_viz", append

	
************************************************************************
**# 1 - load and transform data
************************************************************************

* load data
	import excel		"$root/220 Papers_Outcome-rainfall.xlsx", sheet("Sheet1") ///
							firstrow case(lower) allstring clear

* clean data
	drop				if outcomecategory == ""
	drop				if rainfallvariable == ""

* rename
	rename				outcomecategory outcome
	rename				rainfallvariable rain
	
************************************************************************
**# 2 - create network data
************************************************************************
	
* declare data a network
	nwset				rain outcome, name(rainnet)
	nwset,				detail

	nwset 				outcome rain, edgelist

	nwplot, 			lab layout(grid, columns(20))
	nwplot, 			scatteropt(mfcolor(green) msymbol(D))
	nwplot, 			scatteropt(mfcolor(green) msymbol(D)) lab
	nwplot, 			lab layout(grid, columns(20))
	nwplot, 			arrowfactor(4)
	nwplot, 			arcbend(2)
	nwplot, 			arcbend(2) lab
	nwplot, 			arcbend(10) lab
	nwplot, 			arcbend(20) lab
	nwplot, 			arcstyle(automatic)
	nwplot, 			arcstyle(curved)
	nwplot, 			arcstyle(curved) lab
	nwplot, 			arrowbarbfactor(10) arcstyle(curved) lab
	nwplot, 			arrowbarbfactor(0.5) arcstyle(curved) lab
	nwplot, 			arrowgap(0.5) arcstyle(curved) lab
	nwplot, 			arrowgap(10) arcstyle(curved) lab
	nwplot, 			arcsplines(10) arcstyle(curved) lab
	nwplot, 			arcsplines(100) arcstyle(curved) lab
	nwplot, 			arcsplines(100) arcstyle(curved) aspectratio(10) lab
	nwplot, 			arcsplines(100) arcstyle(curved) aspectratio(100) lab
	nwplot, 			arcsplines(100) arcstyle(curved) aspectratio(1) lab
	nwplot, 			arcsplines(100) arcstyle(curved) aspectratio(0.1) lab
	nwplot, 			arcsplines(100) arcstyle(curved) aspectratio(1) circle lab
	nwplot, 			arcsplines(100) arcstyle(curved) aspectratio(1) nodefactor(2) lab
	nwplot, 			arcsplines(100) arcstyle(curved) aspectratio(1) nodefactor(0.2) lab
	nwplot, 			layout (grid, columns(5)) lab nodefactor(1) edgefactor(0.5) arrowfactor(0.5) arrowbarbfactor(.2) scheme(s1network)
	nwplot, 			layout (mds) lab nodefactor(1) edgefactor(0.5) arrowfactor(0.5) arrowbarbfactor(.2) scheme(s1network)
	nwplot, 			layout (grid, columns(4)) lab edgepatternpalette (dash) nodefactor(1) edgefactor(0.5) arrowfactor(0.5) arrowbarbfactor(.2) scheme(s1network)
	nwplot, 			layout (grid, columns(4)) lab edgepatternpalette (dash_dot) nodefactor(1) edgefactor(0.5) arrowfactor(0.5) arrowbarbfactor(.2) scheme(s1network)
	nwplot, 			layout (grid, columns(4)) lab edgepatternpalette (dash_dot) edgecolorpalette(styellow) ///
						nodefactor(1) edgefactor(0.5) arrowfactor(0.5) arrowbarbfactor(.2)scheme(s1network)
	nwplot, 			layout (grid, columns(4)) label(_nodelab) labelopt(mlabsize(small) ///
						mlabcolor(red))edgepatternpalette (dash) nodefactor(1) edgefactor(0.5) arrowfactor(0.5) arrowbarbfactor(.2) scheme(s1network)
	nwplot, 			layout (circle) label(_nodelab) labelopt(mlabsize(small) mlabcolor(red)) ///
						edgepatternpalette (dash) nodefactor(1) edgefactor(0.5) arrowfactor(0.5) arrowbarbfactor(.2) scheme(s1network)
	nwplot, 			layout (grid, columns(4)) label(_nodelab) labelopt(mlabsize(small) mlabcolor(red)) ///
						edgepatternpalette (dash) nodefactor(1) edgefactor(0.5) arcstyle(curved) arrowfactor(0.5) arrowbarbfactor(.2) scheme(s1network) aspectratio (1.75)
	nwplot, 			layout (circle) label(_nodelab) labelopt(mlabsize(vsmall) mlabcolor(red)) edgepatternpalette (dash) ///
						edgecolorpalette (black) nodefactor(1) edgefactor(0.5) arcstyle(curved) arrowfactor(1) arrowbarbfactor(2) scheme(s1network)
	nwplot, 			layout (grid, columns(5)) label(_nodelab) labelopt(mlabsize(vsmall) mlabcolor(red)) ///
						edgepatternpalette (dash) edgecolorpalette (black) nodefactor(1) edgefactor(0.5) arcstyle(curved) ///
						arrowfactor(1) arrowbarbfactor(2) scheme(s1network)
************************************************************************
**# 7 - end matter
************************************************************************


* close the log
	log	close

/* END */		