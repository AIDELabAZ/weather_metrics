* Project: WB Weather
* Created on: April 2024
* Created by: jdm
* edited by: codex
* edited on: 27 Oct 2026
* Stata v.18.0

* does
	* produces summary graphs of weather values
	* produces summary table of measure inputs by country and year

* assumes
	* wxsum outputs in the shared weather_data refined folders

* TO DO:
	* create summary tables


**********************************************************************
**# 0 - setup
**********************************************************************

* define paths
	global		rootw 	= 	"$wraw"
	global		rooth 	= 	"$data/refined_data"
	global	export 	= 	"$data/results_data"
	global	sfig	= 	"$data/results_data/figures"
	global		xfig    =   "$data/results_data/figures/metric_paper"
	global	logout 	= 	"$data/regression_data/logs"

* load the shared product palette and figure styles
	include		"$code/analysis/viz_code/metric_style.do"

* retain the existing country-year means for the shared-legend composites
	tempfile	eth mwi ngr nga tza uga

* open log
	cap log close
	log 	using 		"$logout/sum_long", append


**********************************************************************
**# 1 - define rainfall inputs
**********************************************************************

* use product names from the wxsum output filenames in figure-legend order
	loc			products chirps cpc merra arc2 era tamsat

* retain the same fourteen rainfall metrics for the country-year means
	loc			metrics mean_season_ median_season_ sd_season_ total_season_ ///
				skew_season_ norain_ raindays_ percent_raindays_ dry_ ///
				dev_total_season_ z_total_season_ dev_raindays_ ///
				dev_norain_ dev_percent_raindays_
	loc			wide
	foreach metric of local metrics {
		loc			wide `wide' `metric'*
	}

* use temporary storage while appending waves; keep shared inputs unchanged
	tempfile	weather


**********************************************************************
**# 2 - ethiopia graphs
**********************************************************************

* identify the household variable used by each survey wave
	loc			ids household_id household_id2 household_id2 ///
				household_id household_id
	loc			waves : dir "$rootw/ethiopia" dirs "wave_*"
	loc			read_order = 0

* start a temporary country dataset without creating project weather copies
	clear
	gen byte	sat = .
	save		"`weather'", emptyok replace

* read the shared wxsum outputs for each wave and rainfall product
	foreach wave of local waves {
		loc			w = real(subinstr("`wave'", "wave_", "", .))
		loc			id : word `w' of `ids'
		loc			sources : dir "$rootw/ethiopia/`wave'/refined" dirs "*_up"

		foreach folder of local sources {
			forvalues s = 1/6 {
				loc			product : word `s' of `products'
				loc			files : dir ///
					"$rootw/ethiopia/`wave'/refined/`folder'" ///
					files "*_`product'rf.dta"
				if `"`files'"' == "" {
					display as error ///
						"No `product' rainfall file: ethiopia/`wave'/`folder'."
					error 601
				}

				foreach file of local files {
					use			`id' `wide' using ///
						"$rootw/ethiopia/`wave'/refined/`folder'/`file'", clear
					reshape long `metrics', i(`id') j(year)
					gen byte	sat = `s'

				* keep wave order when dropping repeated household-year records
					loc			read_order = `read_order' + 1
					gen int		file_order = `read_order'
					append		using "`weather'"
					save		"`weather'", replace
				}
			}
		}
	}

* retain the existing household identifiers and duplicate-removal rule
	sort		file_order
	drop		file_order
	replace		household_id = household_id2 if household_id == ""
	drop		household_id2
	order		sat, after(year)
	duplicates drop
	drop if		household_id == "00000000000000"
	duplicates drop household_id year sat, force

* calculate the same country-year means using all available years
	collapse	(mean) `metrics', by(year sat)
	label define sat 1 "CHIRPS" 2 "CPC" 3 "MERRA-2" ///
				4 "ARC2" 5 "ERA5" 6 "TAMSAT", replace
	label values sat sat

* change scale of percentage once, after averaging
	replace		percent_raindays_ = percent_raindays_ * 100


**********************************************************************
**## 2.1 - ethiopia mean daily rainfall
**********************************************************************

* copy the plotted means without changing the country data
	preserve
		keep		year sat `metrics'
		gen byte	country = 1
		save		"`eth'"
	restore

* draw the country panel with the shared product styles
	sort		year
	twoway		(line mean_season_ year if sat == 1, `p1') ///
				(line mean_season_ year if sat == 2, `p2') ///
				(line mean_season_ year if sat == 3, `p3') ///
				(line mean_season_ year if sat == 4, `p4') ///
				(line mean_season_ year if sat == 5, `p5') ///
				(line mean_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Ethiopia}", size(4) color("38 43 47")) ///
				ytitle("Mean daily rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(1)7, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/eth_v01", replace)

	graph export	"$xfig/eth_v01.pdf", replace
	graph export	"$xfig/eth_v01.png", width(3200) replace
	graph export	"$xfig/eth_v01.eps", replace


**********************************************************************
**## 2.2 - ethiopia median daily rainfall
**********************************************************************

	sort		year
	twoway		(line median_season_ year if sat == 1, `p1') ///
				(line median_season_ year if sat == 2, `p2') ///
				(line median_season_ year if sat == 3, `p3') ///
				(line median_season_ year if sat == 4, `p4') ///
				(line median_season_ year if sat == 5, `p5') ///
				(line median_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Ethiopia}", size(4) color("38 43 47")) ///
				ytitle("Median daily rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(1)8, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/eth_v02", replace)

	graph export	"$xfig/eth_v02.pdf", replace
	graph export	"$xfig/eth_v02.png", width(3200) replace
	graph export	"$xfig/eth_v02.eps", replace


**********************************************************************
**## 2.3 - ethiopia variance daily rainfall
**********************************************************************

	sort		year
	twoway		(line sd_season_ year if sat == 1, `p1') ///
				(line sd_season_ year if sat == 2, `p2') ///
				(line sd_season_ year if sat == 3, `p3') ///
				(line sd_season_ year if sat == 4, `p4') ///
				(line sd_season_ year if sat == 5, `p5') ///
				(line sd_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Ethiopia}", size(4) color("38 43 47")) ///
				ytitle("SD of daily rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(2)14, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/eth_v03", replace)

	graph export	"$xfig/eth_v03.pdf", replace
	graph export	"$xfig/eth_v03.png", width(3200) replace
	graph export	"$xfig/eth_v03.eps", replace


**********************************************************************
**## 2.4 - ethiopia skew daily rainfall
**********************************************************************

	sort		year
	twoway		(line skew_season_ year if sat == 1, `p1') ///
				(line skew_season_ year if sat == 2, `p2') ///
				(line skew_season_ year if sat == 3, `p3') ///
				(line skew_season_ year if sat == 4, `p4') ///
				(line skew_season_ year if sat == 5, `p5') ///
				(line skew_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Ethiopia}", size(4) color("38 43 47")) ///
				ytitle("Skewness of daily rainfall", size(3) color("38 43 47")) ///
				ylabel(0.2(0.05)0.7, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/eth_v04", replace)

	graph export	"$xfig/eth_v04.pdf", replace
	graph export	"$xfig/eth_v04.png", width(3200) replace
	graph export	"$xfig/eth_v04.eps", replace


**********************************************************************
**## 2.5 - ethiopia total daily rainfall for the growing season
**********************************************************************

	sort		year
	twoway		(line total_season_ year if sat == 1, `p1') ///
				(line total_season_ year if sat == 2, `p2') ///
				(line total_season_ year if sat == 3, `p3') ///
				(line total_season_ year if sat == 4, `p4') ///
				(line total_season_ year if sat == 5, `p5') ///
				(line total_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Ethiopia}", size(4) color("38 43 47")) ///
				ytitle("Seasonal rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(200)1800, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/eth_v05", replace)

	graph export	"$xfig/eth_v05.pdf", replace
	graph export	"$xfig/eth_v05.png", width(3200) replace
	graph export	"$xfig/eth_v05.eps", replace


**********************************************************************
**## 2.6 - ethiopia deviations in total daily rainfall
**********************************************************************

	sort		year
	twoway		(line dev_total_season_ year if sat == 1, `p1') ///
				(line dev_total_season_ year if sat == 2, `p2') ///
				(line dev_total_season_ year if sat == 3, `p3') ///
				(line dev_total_season_ year if sat == 4, `p4') ///
				(line dev_total_season_ year if sat == 5, `p5') ///
				(line dev_total_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Ethiopia}", size(4) color("38 43 47")) ///
				ytitle("Deviation in seasonal rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(-500(100)750, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/eth_v06", replace)

	graph export	"$xfig/eth_v06.pdf", replace
	graph export	"$xfig/eth_v06.png", width(3200) replace
	graph export	"$xfig/eth_v06.eps", replace


**********************************************************************
**## 2.7 - ethiopia scaled deviations in total daily rainfall
**********************************************************************

	sort		year
	twoway		(line z_total_season_ year if sat == 1, `p1') ///
				(line z_total_season_ year if sat == 2, `p2') ///
				(line z_total_season_ year if sat == 3, `p3') ///
				(line z_total_season_ year if sat == 4, `p4') ///
				(line z_total_season_ year if sat == 5, `p5') ///
				(line z_total_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Ethiopia}", size(4) color("38 43 47")) ///
				ytitle("Standardized deviation in seasonal rainfall", size(3) color("38 43 47")) ///
				ylabel(-3(1)4, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/eth_v07", replace)

	graph export	"$xfig/eth_v07.pdf", replace
	graph export	"$xfig/eth_v07.png", width(3200) replace
	graph export	"$xfig/eth_v07.eps", replace


**********************************************************************
**## 2.8 - ethiopia rainfall days
**********************************************************************

	sort		year
	twoway		(line raindays_ year if sat == 1, `p1') ///
				(line raindays_ year if sat == 2, `p2') ///
				(line raindays_ year if sat == 3, `p3') ///
				(line raindays_ year if sat == 4, `p4') ///
				(line raindays_ year if sat == 5, `p5') ///
				(line raindays_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Ethiopia}", size(4) color("38 43 47")) ///
				ytitle("Rainy days", size(3) color("38 43 47")) ///
				ylabel(0(30)240, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/eth_v08", replace)

	graph export	"$xfig/eth_v08.pdf", replace
	graph export	"$xfig/eth_v08.png", width(3200) replace
	graph export	"$xfig/eth_v08.eps", replace


**********************************************************************
**## 2.9 - ethiopia deviations in rainfall days
**********************************************************************

	sort		year
	twoway		(line dev_raindays_ year if sat == 1, `p1') ///
				(line dev_raindays_ year if sat == 2, `p2') ///
				(line dev_raindays_ year if sat == 3, `p3') ///
				(line dev_raindays_ year if sat == 4, `p4') ///
				(line dev_raindays_ year if sat == 5, `p5') ///
				(line dev_raindays_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Ethiopia}", size(4) color("38 43 47")) ///
				ytitle("Deviation in rainy days", size(3) color("38 43 47")) ///
				ylabel(-90(30)90, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/eth_v09", replace)

	graph export	"$xfig/eth_v09.pdf", replace
	graph export	"$xfig/eth_v09.png", width(3200) replace
	graph export	"$xfig/eth_v09.eps", replace


**********************************************************************
**## 2.10 - ethiopia no rainfall days
**********************************************************************

	sort		year
	twoway		(line norain_ year if sat == 1, `p1') ///
				(line norain_ year if sat == 2, `p2') ///
				(line norain_ year if sat == 3, `p3') ///
				(line norain_ year if sat == 4, `p4') ///
				(line norain_ year if sat == 5, `p5') ///
				(line norain_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Ethiopia}", size(4) color("38 43 47")) ///
				ytitle("Dry days", size(3) color("38 43 47")) ///
				ylabel(0(30)240, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/eth_v10", replace)

	graph export	"$xfig/eth_v10.pdf", replace
	graph export	"$xfig/eth_v10.png", width(3200) replace
	graph export	"$xfig/eth_v10.eps", replace


**********************************************************************
**## 2.11 - ethiopia deviations in no rainfall days
**********************************************************************

	sort		year
	twoway		(line dev_norain_ year if sat == 1, `p1') ///
				(line dev_norain_ year if sat == 2, `p2') ///
				(line dev_norain_ year if sat == 3, `p3') ///
				(line dev_norain_ year if sat == 4, `p4') ///
				(line dev_norain_ year if sat == 5, `p5') ///
				(line dev_norain_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Ethiopia}", size(4) color("38 43 47")) ///
				ytitle("Deviation in dry days", size(3) color("38 43 47")) ///
				ylabel(-90(30)90, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/eth_v11", replace)

	graph export	"$xfig/eth_v11.pdf", replace
	graph export	"$xfig/eth_v11.png", width(3200) replace
	graph export	"$xfig/eth_v11.eps", replace


**********************************************************************
**## 2.12 - ethiopia share of rainy days
**********************************************************************

* draw the country panel with the shared product styles
	sort		year
	twoway		(line percent_raindays_ year if sat == 1, `p1') ///
				(line percent_raindays_ year if sat == 2, `p2') ///
				(line percent_raindays_ year if sat == 3, `p3') ///
				(line percent_raindays_ year if sat == 4, `p4') ///
				(line percent_raindays_ year if sat == 5, `p5') ///
				(line percent_raindays_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Ethiopia}", size(4) color("38 43 47")) ///
				ytitle("Share of rainy days (%)", size(3) color("38 43 47")) ///
				ylabel(0(20)100, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/eth_v12", replace)

	graph export	"$xfig/eth_v12.pdf", replace
	graph export	"$xfig/eth_v12.png", width(3200) replace
	graph export	"$xfig/eth_v12.eps", replace


**********************************************************************
**## 2.13 - ethiopia deviations in share of rainy days
**********************************************************************

	sort		year
	twoway		(line dev_percent_raindays_ year if sat == 1, `p1') ///
				(line dev_percent_raindays_ year if sat == 2, `p2') ///
				(line dev_percent_raindays_ year if sat == 3, `p3') ///
				(line dev_percent_raindays_ year if sat == 4, `p4') ///
				(line dev_percent_raindays_ year if sat == 5, `p5') ///
				(line dev_percent_raindays_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Ethiopia}", size(4) color("38 43 47")) ///
				ytitle("Deviation in share of rainy days", size(3) color("38 43 47")) ///
				ylabel(-0.4(0.1)0.4, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/eth_v13", replace)

	graph export	"$xfig/eth_v13.pdf", replace
	graph export	"$xfig/eth_v13.png", width(3200) replace
	graph export	"$xfig/eth_v13.eps", replace


**********************************************************************
**## 2.14 - ethiopia intra season dry spells
**********************************************************************

	sort		year
	twoway		(line dry_ year if sat == 1, `p1') ///
				(line dry_ year if sat == 2, `p2') ///
				(line dry_ year if sat == 3, `p3') ///
				(line dry_ year if sat == 4, `p4') ///
				(line dry_ year if sat == 5, `p5') ///
				(line dry_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Ethiopia}", size(4) color("38 43 47")) ///
				ytitle("Longest mid-window dry spell (days)", size(3) color("38 43 47")) ///
				ylabel(0(5)60, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/eth_v14", replace)

	graph export	"$xfig/eth_v14.pdf", replace
	graph export	"$xfig/eth_v14.png", width(3200) replace
	graph export	"$xfig/eth_v14.eps", replace


**********************************************************************
**# 3 - malawi graphs
**********************************************************************

* identify the household variable used by each survey wave
	loc			ids case_id y2_hhid case_id y3_hhid case_id y4_hhid
	loc			waves : dir "$rootw/malawi" dirs "wave_*"
	loc			read_order = 0

* start a temporary country dataset without creating project weather copies
	clear
	gen byte	sat = .
	save		"`weather'", emptyok replace

* read the shared wxsum outputs for each wave and rainfall product
	foreach wave of local waves {
		loc			w = real(subinstr("`wave'", "wave_", "", .))
		loc			id : word `w' of `ids'
		loc			sources : dir "$rootw/malawi/`wave'/refined" dirs "*_up"

		foreach folder of local sources {
			forvalues s = 1/6 {
				loc			product : word `s' of `products'
				loc			files : dir ///
					"$rootw/malawi/`wave'/refined/`folder'" ///
					files "*_`product'rf.dta"
				if `"`files'"' == "" {
					display as error ///
						"No `product' rainfall file: malawi/`wave'/`folder'."
					error 601
				}

				foreach file of local files {
					use			`id' `wide' using ///
						"$rootw/malawi/`wave'/refined/`folder'/`file'", clear
					reshape long `metrics', i(`id') j(year)
					gen byte	sat = `s'

				* keep wave order when dropping repeated household-year records
					loc			read_order = `read_order' + 1
					gen int		file_order = `read_order'
					append		using "`weather'"
					save		"`weather'", replace
				}
			}
		}
	}

* retain the existing household identifiers and duplicate-removal rule
	sort		file_order
	drop		file_order
	replace		y2_hhid = y3_hhid if y2_hhid == ""
	replace		y2_hhid = y4_hhid if y2_hhid == ""
	egen		hhid = group(y2_hhid)
	egen		hhid2 = group(case_id)
	replace		hhid = hhid2 if hhid == .
	drop		hhid2 y2_hhid case_id y3_hhid y4_hhid
	order		sat, after(year)
	duplicates drop
	duplicates drop hhid year sat, force

* calculate the same country-year means using all available years
	collapse	(mean) `metrics', by(year sat)
	label define sat 1 "CHIRPS" 2 "CPC" 3 "MERRA-2" ///
				4 "ARC2" 5 "ERA5" 6 "TAMSAT", replace
	label values sat sat

* change scale of percentage once, after averaging
	replace		percent_raindays_ = percent_raindays_ * 100


**********************************************************************
**## 3.1 - malawi mean daily rainfall
**********************************************************************

* copy the plotted means without changing the country data
	preserve
		keep		year sat `metrics'
		gen byte	country = 2
		save		"`mwi'"
	restore

* draw the country panel with the shared product styles
	sort		year
	twoway		(line mean_season_ year if sat == 1, `p1') ///
				(line mean_season_ year if sat == 2, `p2') ///
				(line mean_season_ year if sat == 3, `p3') ///
				(line mean_season_ year if sat == 4, `p4') ///
				(line mean_season_ year if sat == 5, `p5') ///
				(line mean_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Malawi}", size(4) color("38 43 47")) ///
				ytitle("Mean daily rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(1)8, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/mwi_v01", replace)

	graph export	"$xfig/mwi_v01.pdf", replace
	graph export	"$xfig/mwi_v01.png", width(3200) replace
	graph export	"$xfig/mwi_v01.eps", replace


**********************************************************************
**## 3.2 - malawi median daily rainfall
**********************************************************************

	sort		year
	twoway		(line median_season_ year if sat == 1, `p1') ///
				(line median_season_ year if sat == 2, `p2') ///
				(line median_season_ year if sat == 3, `p3') ///
				(line median_season_ year if sat == 4, `p4') ///
				(line median_season_ year if sat == 5, `p5') ///
				(line median_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Malawi}", size(4) color("38 43 47")) ///
				ytitle("Median daily rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(1)8, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/mwi_v02", replace)

	graph export	"$xfig/mwi_v02.pdf", replace
	graph export	"$xfig/mwi_v02.png", width(3200) replace
	graph export	"$xfig/mwi_v02.eps", replace


**********************************************************************
**## 3.3 - malawi variance daily rainfall
**********************************************************************

	sort		year
	twoway		(line sd_season_ year if sat == 1, `p1') ///
				(line sd_season_ year if sat == 2, `p2') ///
				(line sd_season_ year if sat == 3, `p3') ///
				(line sd_season_ year if sat == 4, `p4') ///
				(line sd_season_ year if sat == 5, `p5') ///
				(line sd_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Malawi}", size(4) color("38 43 47")) ///
				ytitle("SD of daily rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(2)14, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/mwi_v03", replace)

	graph export	"$xfig/mwi_v03.pdf", replace
	graph export	"$xfig/mwi_v03.png", width(3200) replace
	graph export	"$xfig/mwi_v03.eps", replace


**********************************************************************
**## 3.4 - malawi skew daily rainfall
**********************************************************************

	sort		year
	twoway		(line skew_season_ year if sat == 1, `p1') ///
				(line skew_season_ year if sat == 2, `p2') ///
				(line skew_season_ year if sat == 3, `p3') ///
				(line skew_season_ year if sat == 4, `p4') ///
				(line skew_season_ year if sat == 5, `p5') ///
				(line skew_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Malawi}", size(4) color("38 43 47")) ///
				ytitle("Skewness of daily rainfall", size(3) color("38 43 47")) ///
				ylabel(0.2(0.05)0.7, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/mwi_v04", replace)

	graph export	"$xfig/mwi_v04.pdf", replace
	graph export	"$xfig/mwi_v04.png", width(3200) replace
	graph export	"$xfig/mwi_v04.eps", replace


**********************************************************************
**## 3.5 - malawi total daily rainfall for the growing season
**********************************************************************

	sort		year
	twoway		(line total_season_ year if sat == 1, `p1') ///
				(line total_season_ year if sat == 2, `p2') ///
				(line total_season_ year if sat == 3, `p3') ///
				(line total_season_ year if sat == 4, `p4') ///
				(line total_season_ year if sat == 5, `p5') ///
				(line total_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Malawi}", size(4) color("38 43 47")) ///
				ytitle("Seasonal rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(200)1800, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/mwi_v05", replace)

	graph export	"$xfig/mwi_v05.pdf", replace
	graph export	"$xfig/mwi_v05.png", width(3200) replace
	graph export	"$xfig/mwi_v05.eps", replace


**********************************************************************
**## 3.6 - malawi deviations in total daily rainfall
**********************************************************************

	sort		year
	twoway		(line dev_total_season_ year if sat == 1, `p1') ///
				(line dev_total_season_ year if sat == 2, `p2') ///
				(line dev_total_season_ year if sat == 3, `p3') ///
				(line dev_total_season_ year if sat == 4, `p4') ///
				(line dev_total_season_ year if sat == 5, `p5') ///
				(line dev_total_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Malawi}", size(4) color("38 43 47")) ///
				ytitle("Deviation in seasonal rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(-500(100)750, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/mwi_v06", replace)

	graph export	"$xfig/mwi_v06.pdf", replace
	graph export	"$xfig/mwi_v06.png", width(3200) replace
	graph export	"$xfig/mwi_v06.eps", replace


**********************************************************************
**## 3.7 - malawi scaled deviations in total daily rainfall
**********************************************************************

	sort		year
	twoway		(line z_total_season_ year if sat == 1, `p1') ///
				(line z_total_season_ year if sat == 2, `p2') ///
				(line z_total_season_ year if sat == 3, `p3') ///
				(line z_total_season_ year if sat == 4, `p4') ///
				(line z_total_season_ year if sat == 5, `p5') ///
				(line z_total_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Malawi}", size(4) color("38 43 47")) ///
				ytitle("Standardized deviation in seasonal rainfall", size(3) color("38 43 47")) ///
				ylabel(-3(1)4, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/mwi_v07", replace)

	graph export	"$xfig/mwi_v07.pdf", replace
	graph export	"$xfig/mwi_v07.png", width(3200) replace
	graph export	"$xfig/mwi_v07.eps", replace


**********************************************************************
**## 3.8 - malawi rainfall days
**********************************************************************

	sort		year
	twoway		(line raindays_ year if sat == 1, `p1') ///
				(line raindays_ year if sat == 2, `p2') ///
				(line raindays_ year if sat == 3, `p3') ///
				(line raindays_ year if sat == 4, `p4') ///
				(line raindays_ year if sat == 5, `p5') ///
				(line raindays_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Malawi}", size(4) color("38 43 47")) ///
				ytitle("Rainy days", size(3) color("38 43 47")) ///
				ylabel(0(30)240, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/mwi_v08", replace)

	graph export	"$xfig/mwi_v08.pdf", replace
	graph export	"$xfig/mwi_v08.png", width(3200) replace
	graph export	"$xfig/mwi_v08.eps", replace


**********************************************************************
**## 3.9 - malawi deviations in rainfall days
**********************************************************************

	sort		year
	twoway		(line dev_raindays_ year if sat == 1, `p1') ///
				(line dev_raindays_ year if sat == 2, `p2') ///
				(line dev_raindays_ year if sat == 3, `p3') ///
				(line dev_raindays_ year if sat == 4, `p4') ///
				(line dev_raindays_ year if sat == 5, `p5') ///
				(line dev_raindays_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Malawi}", size(4) color("38 43 47")) ///
				ytitle("Deviation in rainy days", size(3) color("38 43 47")) ///
				ylabel(-90(30)90, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/mwi_v09", replace)

	graph export	"$xfig/mwi_v09.pdf", replace
	graph export	"$xfig/mwi_v09.png", width(3200) replace
	graph export	"$xfig/mwi_v09.eps", replace


**********************************************************************
**## 3.10 - malawi no rainfall days
**********************************************************************

	sort		year
	twoway		(line norain_ year if sat == 1, `p1') ///
				(line norain_ year if sat == 2, `p2') ///
				(line norain_ year if sat == 3, `p3') ///
				(line norain_ year if sat == 4, `p4') ///
				(line norain_ year if sat == 5, `p5') ///
				(line norain_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Malawi}", size(4) color("38 43 47")) ///
				ytitle("Dry days", size(3) color("38 43 47")) ///
				ylabel(0(30)240, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/mwi_v10", replace)

	graph export	"$xfig/mwi_v10.pdf", replace
	graph export	"$xfig/mwi_v10.png", width(3200) replace
	graph export	"$xfig/mwi_v10.eps", replace


**********************************************************************
**## 3.11 - malawi deviations in no rainfall days
**********************************************************************

	sort		year
	twoway		(line dev_norain_ year if sat == 1, `p1') ///
				(line dev_norain_ year if sat == 2, `p2') ///
				(line dev_norain_ year if sat == 3, `p3') ///
				(line dev_norain_ year if sat == 4, `p4') ///
				(line dev_norain_ year if sat == 5, `p5') ///
				(line dev_norain_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Malawi}", size(4) color("38 43 47")) ///
				ytitle("Deviation in dry days", size(3) color("38 43 47")) ///
				ylabel(-90(30)90, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/mwi_v11", replace)

	graph export	"$xfig/mwi_v11.pdf", replace
	graph export	"$xfig/mwi_v11.png", width(3200) replace
	graph export	"$xfig/mwi_v11.eps", replace


**********************************************************************
**## 3.12 - malawi share of rainy days
**********************************************************************

* draw the country panel with the shared product styles
	sort		year
	twoway		(line percent_raindays_ year if sat == 1, `p1') ///
				(line percent_raindays_ year if sat == 2, `p2') ///
				(line percent_raindays_ year if sat == 3, `p3') ///
				(line percent_raindays_ year if sat == 4, `p4') ///
				(line percent_raindays_ year if sat == 5, `p5') ///
				(line percent_raindays_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Malawi}", size(4) color("38 43 47")) ///
				ytitle("Share of rainy days (%)", size(3) color("38 43 47")) ///
				ylabel(0(20)100, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/mwi_v12", replace)

	graph export	"$xfig/mwi_v12.pdf", replace
	graph export	"$xfig/mwi_v12.png", width(3200) replace
	graph export	"$xfig/mwi_v12.eps", replace


**********************************************************************
**## 3.13 - malawi deviations in share of rainy days
**********************************************************************

	sort		year
	twoway		(line dev_percent_raindays_ year if sat == 1, `p1') ///
				(line dev_percent_raindays_ year if sat == 2, `p2') ///
				(line dev_percent_raindays_ year if sat == 3, `p3') ///
				(line dev_percent_raindays_ year if sat == 4, `p4') ///
				(line dev_percent_raindays_ year if sat == 5, `p5') ///
				(line dev_percent_raindays_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Malawi}", size(4) color("38 43 47")) ///
				ytitle("Deviation in share of rainy days", size(3) color("38 43 47")) ///
				ylabel(-0.4(0.1)0.4, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/mwi_v13", replace)

	graph export	"$xfig/mwi_v13.pdf", replace
	graph export	"$xfig/mwi_v13.png", width(3200) replace
	graph export	"$xfig/mwi_v13.eps", replace


**********************************************************************
**## 3.14 - malawi intra season dry spells
**********************************************************************

	sort		year
	twoway		(line dry_ year if sat == 1, `p1') ///
				(line dry_ year if sat == 2, `p2') ///
				(line dry_ year if sat == 3, `p3') ///
				(line dry_ year if sat == 4, `p4') ///
				(line dry_ year if sat == 5, `p5') ///
				(line dry_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Malawi}", size(4) color("38 43 47")) ///
				ytitle("Longest mid-window dry spell (days)", size(3) color("38 43 47")) ///
				ylabel(0(5)60, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/mwi_v14", replace)

	graph export	"$xfig/mwi_v14.pdf", replace
	graph export	"$xfig/mwi_v14.png", width(3200) replace
	graph export	"$xfig/mwi_v14.eps", replace


**********************************************************************
**# 4 - niger graphs
**********************************************************************

* identify the household variable used by each survey wave
	loc			ids hid hhid_y2
	loc			waves : dir "$rootw/niger" dirs "wave_*"
	loc			read_order = 0

* start a temporary country dataset without creating project weather copies
	clear
	gen byte	sat = .
	save		"`weather'", emptyok replace

* read the shared wxsum outputs for each wave and rainfall product
	foreach wave of local waves {
		loc			w = real(subinstr("`wave'", "wave_", "", .))
		loc			id : word `w' of `ids'
		loc			sources : dir "$rootw/niger/`wave'/refined" dirs "*_up"

		foreach folder of local sources {
			forvalues s = 1/6 {
				loc			product : word `s' of `products'
				loc			files : dir ///
					"$rootw/niger/`wave'/refined/`folder'" ///
					files "*_`product'rf.dta"
				if `"`files'"' == "" {
					display as error ///
						"No `product' rainfall file: niger/`wave'/`folder'."
					error 601
				}

				foreach file of local files {
					use			`id' `wide' using ///
						"$rootw/niger/`wave'/refined/`folder'/`file'", clear
					reshape long `metrics', i(`id') j(year)
					gen byte	sat = `s'

				* keep wave order when dropping repeated household-year records
					loc			read_order = `read_order' + 1
					gen int		file_order = `read_order'
					append		using "`weather'"
					save		"`weather'", replace
				}
			}
		}
	}

* retain the existing household identifiers and duplicate-removal rule
	sort		file_order
	drop		file_order
	replace		hid = hhid_y2 if hid == .
	drop		hhid_y2
	order		sat, after(year)
	duplicates drop
	duplicates drop hid year sat, force

* calculate the same country-year means using all available years
	collapse	(mean) `metrics', by(year sat)
	label define sat 1 "CHIRPS" 2 "CPC" 3 "MERRA-2" ///
				4 "ARC2" 5 "ERA5" 6 "TAMSAT", replace
	label values sat sat

* change scale of percentage once, after averaging
	replace		percent_raindays_ = percent_raindays_ * 100


**********************************************************************
**## 4.1 - niger mean daily rainfall
**********************************************************************

* copy the plotted means without changing the country data
	preserve
		keep		year sat `metrics'
		gen byte	country = 3
		save		"`ngr'"
	restore

* draw the country panel with the shared product styles
	sort		year
	twoway		(line mean_season_ year if sat == 1, `p1') ///
				(line mean_season_ year if sat == 2, `p2') ///
				(line mean_season_ year if sat == 3, `p3') ///
				(line mean_season_ year if sat == 4, `p4') ///
				(line mean_season_ year if sat == 5, `p5') ///
				(line mean_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Niger}", size(4) color("38 43 47")) ///
				ytitle("Mean daily rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(1)3, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/ngr_v01", replace)

	graph export	"$xfig/ngr_v01.pdf", replace
	graph export	"$xfig/ngr_v01.png", width(3200) replace
	graph export	"$xfig/ngr_v01.eps", replace


**********************************************************************
**## 4.2 - niger median daily rainfall
**********************************************************************

	sort		year
	twoway		(line median_season_ year if sat == 1, `p1') ///
				(line median_season_ year if sat == 2, `p2') ///
				(line median_season_ year if sat == 3, `p3') ///
				(line median_season_ year if sat == 4, `p4') ///
				(line median_season_ year if sat == 5, `p5') ///
				(line median_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Niger}", size(4) color("38 43 47")) ///
				ytitle("Median daily rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(1)8, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/ngr_v02", replace)

	graph export	"$xfig/ngr_v02.pdf", replace
	graph export	"$xfig/ngr_v02.png", width(3200) replace
	graph export	"$xfig/ngr_v02.eps", replace


**********************************************************************
**## 4.3 - niger variance daily rainfall
**********************************************************************

	sort		year
	twoway		(line sd_season_ year if sat == 1, `p1') ///
				(line sd_season_ year if sat == 2, `p2') ///
				(line sd_season_ year if sat == 3, `p3') ///
				(line sd_season_ year if sat == 4, `p4') ///
				(line sd_season_ year if sat == 5, `p5') ///
				(line sd_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Niger}", size(4) color("38 43 47")) ///
				ytitle("SD of daily rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(2)14, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/ngr_v03", replace)

	graph export	"$xfig/ngr_v03.pdf", replace
	graph export	"$xfig/ngr_v03.png", width(3200) replace
	graph export	"$xfig/ngr_v03.eps", replace


**********************************************************************
**## 4.4 - niger skew daily rainfall
**********************************************************************

	sort		year
	twoway		(line skew_season_ year if sat == 1, `p1') ///
				(line skew_season_ year if sat == 2, `p2') ///
				(line skew_season_ year if sat == 3, `p3') ///
				(line skew_season_ year if sat == 4, `p4') ///
				(line skew_season_ year if sat == 5, `p5') ///
				(line skew_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Niger}", size(4) color("38 43 47")) ///
				ytitle("Skewness of daily rainfall", size(3) color("38 43 47")) ///
				ylabel(0.2(0.05)0.7, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/ngr_v04", replace)

	graph export	"$xfig/ngr_v04.pdf", replace
	graph export	"$xfig/ngr_v04.png", width(3200) replace
	graph export	"$xfig/ngr_v04.eps", replace


**********************************************************************
**## 4.5 - niger total daily rainfall for the growing season
**********************************************************************

	sort		year
	twoway		(line total_season_ year if sat == 1, `p1') ///
				(line total_season_ year if sat == 2, `p2') ///
				(line total_season_ year if sat == 3, `p3') ///
				(line total_season_ year if sat == 4, `p4') ///
				(line total_season_ year if sat == 5, `p5') ///
				(line total_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Niger}", size(4) color("38 43 47")) ///
				ytitle("Seasonal rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(200)1800, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/ngr_v05", replace)

	graph export	"$xfig/ngr_v05.pdf", replace
	graph export	"$xfig/ngr_v05.png", width(3200) replace
	graph export	"$xfig/ngr_v05.eps", replace


**********************************************************************
**## 4.6 - niger deviations in total daily rainfall
**********************************************************************

	sort		year
	twoway		(line dev_total_season_ year if sat == 1, `p1') ///
				(line dev_total_season_ year if sat == 2, `p2') ///
				(line dev_total_season_ year if sat == 3, `p3') ///
				(line dev_total_season_ year if sat == 4, `p4') ///
				(line dev_total_season_ year if sat == 5, `p5') ///
				(line dev_total_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Niger}", size(4) color("38 43 47")) ///
				ytitle("Deviation in seasonal rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(-500(100)750, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/ngr_v06", replace)

	graph export	"$xfig/ngr_v06.pdf", replace
	graph export	"$xfig/ngr_v06.png", width(3200) replace
	graph export	"$xfig/ngr_v06.eps", replace


**********************************************************************
**## 4.7 - niger scaled deviations in total daily rainfall
**********************************************************************

	sort		year
	twoway		(line z_total_season_ year if sat == 1, `p1') ///
				(line z_total_season_ year if sat == 2, `p2') ///
				(line z_total_season_ year if sat == 3, `p3') ///
				(line z_total_season_ year if sat == 4, `p4') ///
				(line z_total_season_ year if sat == 5, `p5') ///
				(line z_total_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Niger}", size(4) color("38 43 47")) ///
				ytitle("Standardized deviation in seasonal rainfall", size(3) color("38 43 47")) ///
				ylabel(-3(1)4, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/ngr_v07", replace)

	graph export	"$xfig/ngr_v07.pdf", replace
	graph export	"$xfig/ngr_v07.png", width(3200) replace
	graph export	"$xfig/ngr_v07.eps", replace


**********************************************************************
**## 4.8 - niger rainfall days
**********************************************************************

	sort		year
	twoway		(line raindays_ year if sat == 1, `p1') ///
				(line raindays_ year if sat == 2, `p2') ///
				(line raindays_ year if sat == 3, `p3') ///
				(line raindays_ year if sat == 4, `p4') ///
				(line raindays_ year if sat == 5, `p5') ///
				(line raindays_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Niger}", size(4) color("38 43 47")) ///
				ytitle("Rainy days", size(3) color("38 43 47")) ///
				ylabel(0(30)240, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/ngr_v08", replace)

	graph export	"$xfig/ngr_v08.pdf", replace
	graph export	"$xfig/ngr_v08.png", width(3200) replace
	graph export	"$xfig/ngr_v08.eps", replace


**********************************************************************
**## 4.9 - niger deviations in rainfall days
**********************************************************************

	sort		year
	twoway		(line dev_raindays_ year if sat == 1, `p1') ///
				(line dev_raindays_ year if sat == 2, `p2') ///
				(line dev_raindays_ year if sat == 3, `p3') ///
				(line dev_raindays_ year if sat == 4, `p4') ///
				(line dev_raindays_ year if sat == 5, `p5') ///
				(line dev_raindays_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Niger}", size(4) color("38 43 47")) ///
				ytitle("Deviation in rainy days", size(3) color("38 43 47")) ///
				ylabel(-90(30)90, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/ngr_v09", replace)

	graph export	"$xfig/ngr_v09.pdf", replace
	graph export	"$xfig/ngr_v09.png", width(3200) replace
	graph export	"$xfig/ngr_v09.eps", replace


**********************************************************************
**## 4.10 - niger no rainfall days
**********************************************************************

	sort		year
	twoway		(line norain_ year if sat == 1, `p1') ///
				(line norain_ year if sat == 2, `p2') ///
				(line norain_ year if sat == 3, `p3') ///
				(line norain_ year if sat == 4, `p4') ///
				(line norain_ year if sat == 5, `p5') ///
				(line norain_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Niger}", size(4) color("38 43 47")) ///
				ytitle("Dry days", size(3) color("38 43 47")) ///
				ylabel(0(30)240, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/ngr_v10", replace)

	graph export	"$xfig/ngr_v10.pdf", replace
	graph export	"$xfig/ngr_v10.png", width(3200) replace
	graph export	"$xfig/ngr_v10.eps", replace


**********************************************************************
**## 4.11 - niger deviations in no rainfall days
**********************************************************************

	sort		year
	twoway		(line dev_norain_ year if sat == 1, `p1') ///
				(line dev_norain_ year if sat == 2, `p2') ///
				(line dev_norain_ year if sat == 3, `p3') ///
				(line dev_norain_ year if sat == 4, `p4') ///
				(line dev_norain_ year if sat == 5, `p5') ///
				(line dev_norain_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Niger}", size(4) color("38 43 47")) ///
				ytitle("Deviation in dry days", size(3) color("38 43 47")) ///
				ylabel(-90(30)90, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/ngr_v11", replace)

	graph export	"$xfig/ngr_v11.pdf", replace
	graph export	"$xfig/ngr_v11.png", width(3200) replace
	graph export	"$xfig/ngr_v11.eps", replace


**********************************************************************
**## 4.12 - niger share of rainy days
**********************************************************************

* draw the country panel with the shared product styles
	sort		year
	twoway		(line percent_raindays_ year if sat == 1, `p1') ///
				(line percent_raindays_ year if sat == 2, `p2') ///
				(line percent_raindays_ year if sat == 3, `p3') ///
				(line percent_raindays_ year if sat == 4, `p4') ///
				(line percent_raindays_ year if sat == 5, `p5') ///
				(line percent_raindays_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Niger}", size(4) color("38 43 47")) ///
				ytitle("Share of rainy days (%)", size(3) color("38 43 47")) ///
				ylabel(0(20)100, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/ngr_v12", replace)

	graph export	"$xfig/ngr_v12.pdf", replace
	graph export	"$xfig/ngr_v12.png", width(3200) replace
	graph export	"$xfig/ngr_v12.eps", replace


**********************************************************************
**## 4.13 - niger deviations in share of rainy days
**********************************************************************

	sort		year
	twoway		(line dev_percent_raindays_ year if sat == 1, `p1') ///
				(line dev_percent_raindays_ year if sat == 2, `p2') ///
				(line dev_percent_raindays_ year if sat == 3, `p3') ///
				(line dev_percent_raindays_ year if sat == 4, `p4') ///
				(line dev_percent_raindays_ year if sat == 5, `p5') ///
				(line dev_percent_raindays_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Niger}", size(4) color("38 43 47")) ///
				ytitle("Deviation in share of rainy days", size(3) color("38 43 47")) ///
				ylabel(-0.4(0.1)0.4, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/ngr_v13", replace)

	graph export	"$xfig/ngr_v13.pdf", replace
	graph export	"$xfig/ngr_v13.png", width(3200) replace
	graph export	"$xfig/ngr_v13.eps", replace


**********************************************************************
**## 4.14 - niger intra season dry spells
**********************************************************************

	sort		year
	twoway		(line dry_ year if sat == 1, `p1') ///
				(line dry_ year if sat == 2, `p2') ///
				(line dry_ year if sat == 3, `p3') ///
				(line dry_ year if sat == 4, `p4') ///
				(line dry_ year if sat == 5, `p5') ///
				(line dry_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Niger}", size(4) color("38 43 47")) ///
				ytitle("Longest mid-window dry spell (days)", size(3) color("38 43 47")) ///
				ylabel(0(5)60, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/ngr_v14", replace)

	graph export	"$xfig/ngr_v14.pdf", replace
	graph export	"$xfig/ngr_v14.png", width(3200) replace
	graph export	"$xfig/ngr_v14.eps", replace


**********************************************************************
**# 5 - nigeria graphs
**********************************************************************

* identify the household variable used by each survey wave
	loc			ids hhid hhid hhid hhid
	loc			waves : dir "$rootw/nigeria" dirs "wave_*"
	loc			read_order = 0

* start a temporary country dataset without creating project weather copies
	clear
	gen byte	sat = .
	save		"`weather'", emptyok replace

* read the shared wxsum outputs for each wave and rainfall product
	foreach wave of local waves {
		loc			w = real(subinstr("`wave'", "wave_", "", .))
		loc			id : word `w' of `ids'
		loc			sources : dir "$rootw/nigeria/`wave'/refined" dirs "*_up"

		foreach folder of local sources {
			forvalues s = 1/6 {
				loc			product : word `s' of `products'
				loc			files : dir ///
					"$rootw/nigeria/`wave'/refined/`folder'" ///
					files "*_`product'rf_n.dta"
				if `"`files'"' == "" {
					display as error ///
						"No `product' rainfall file: nigeria/`wave'/`folder'."
					error 601
				}

				foreach file of local files {
					use			`id' `wide' using ///
						"$rootw/nigeria/`wave'/refined/`folder'/`file'", clear
					reshape long `metrics', i(`id') j(year)
					gen byte	sat = `s'

				* keep wave order when dropping repeated household-year records
					loc			read_order = `read_order' + 1
					gen int		file_order = `read_order'
					append		using "`weather'"
					save		"`weather'", replace
				}
			}
		}
	}

* retain the existing household identifiers and duplicate-removal rule
	sort		file_order
	drop		file_order
	order		sat, after(year)
	duplicates drop
	duplicates drop hhid year sat, force

* calculate the same country-year means using all available years
	collapse	(mean) `metrics', by(year sat)
	label define sat 1 "CHIRPS" 2 "CPC" 3 "MERRA-2" ///
				4 "ARC2" 5 "ERA5" 6 "TAMSAT", replace
	label values sat sat

* change scale of percentage once, after averaging
	replace		percent_raindays_ = percent_raindays_ * 100


**********************************************************************
**## 5.1 - nigeria mean daily rainfall
**********************************************************************

* copy the plotted means without changing the country data
	preserve
		keep		year sat `metrics'
		gen byte	country = 4
		save		"`nga'"
	restore

* draw the country panel with the shared product styles
	sort		year
	twoway		(line mean_season_ year if sat == 1, `p1') ///
				(line mean_season_ year if sat == 2, `p2') ///
				(line mean_season_ year if sat == 3, `p3') ///
				(line mean_season_ year if sat == 4, `p4') ///
				(line mean_season_ year if sat == 5, `p5') ///
				(line mean_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Nigeria}", size(4) color("38 43 47")) ///
				ytitle("Mean daily rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(1)12, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/nga_v01", replace)

	graph export	"$xfig/nga_v01.pdf", replace
	graph export	"$xfig/nga_v01.png", width(3200) replace
	graph export	"$xfig/nga_v01.eps", replace


**********************************************************************
**## 5.2 - nigeria median daily rainfall
**********************************************************************

	sort		year
	twoway		(line median_season_ year if sat == 1, `p1') ///
				(line median_season_ year if sat == 2, `p2') ///
				(line median_season_ year if sat == 3, `p3') ///
				(line median_season_ year if sat == 4, `p4') ///
				(line median_season_ year if sat == 5, `p5') ///
				(line median_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Nigeria}", size(4) color("38 43 47")) ///
				ytitle("Median daily rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(1)8, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/nga_v02", replace)

	graph export	"$xfig/nga_v02.pdf", replace
	graph export	"$xfig/nga_v02.png", width(3200) replace
	graph export	"$xfig/nga_v02.eps", replace


**********************************************************************
**## 5.3 - nigeria variance daily rainfall
**********************************************************************

	sort		year
	twoway		(line sd_season_ year if sat == 1, `p1') ///
				(line sd_season_ year if sat == 2, `p2') ///
				(line sd_season_ year if sat == 3, `p3') ///
				(line sd_season_ year if sat == 4, `p4') ///
				(line sd_season_ year if sat == 5, `p5') ///
				(line sd_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Nigeria}", size(4) color("38 43 47")) ///
				ytitle("SD of daily rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(2)14, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/nga_v03", replace)

	graph export	"$xfig/nga_v03.pdf", replace
	graph export	"$xfig/nga_v03.png", width(3200) replace
	graph export	"$xfig/nga_v03.eps", replace


**********************************************************************
**## 5.4 - nigeria skew daily rainfall
**********************************************************************

	sort		year
	twoway		(line skew_season_ year if sat == 1, `p1') ///
				(line skew_season_ year if sat == 2, `p2') ///
				(line skew_season_ year if sat == 3, `p3') ///
				(line skew_season_ year if sat == 4, `p4') ///
				(line skew_season_ year if sat == 5, `p5') ///
				(line skew_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Nigeria}", size(4) color("38 43 47")) ///
				ytitle("Skewness of daily rainfall", size(3) color("38 43 47")) ///
				ylabel(0.2(0.05)0.7, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/nga_v04", replace)

	graph export	"$xfig/nga_v04.pdf", replace
	graph export	"$xfig/nga_v04.png", width(3200) replace
	graph export	"$xfig/nga_v04.eps", replace


**********************************************************************
**## 5.5 - nigeria total daily rainfall for the growing season
**********************************************************************

	sort		year
	twoway		(line total_season_ year if sat == 1, `p1') ///
				(line total_season_ year if sat == 2, `p2') ///
				(line total_season_ year if sat == 3, `p3') ///
				(line total_season_ year if sat == 4, `p4') ///
				(line total_season_ year if sat == 5, `p5') ///
				(line total_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Nigeria}", size(4) color("38 43 47")) ///
				ytitle("Seasonal rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(200)1800, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/nga_v05", replace)

	graph export	"$xfig/nga_v05.pdf", replace
	graph export	"$xfig/nga_v05.png", width(3200) replace
	graph export	"$xfig/nga_v05.eps", replace


**********************************************************************
**## 5.6 - nigeria deviations in total daily rainfall
**********************************************************************

	sort		year
	twoway		(line dev_total_season_ year if sat == 1, `p1') ///
				(line dev_total_season_ year if sat == 2, `p2') ///
				(line dev_total_season_ year if sat == 3, `p3') ///
				(line dev_total_season_ year if sat == 4, `p4') ///
				(line dev_total_season_ year if sat == 5, `p5') ///
				(line dev_total_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Nigeria}", size(4) color("38 43 47")) ///
				ytitle("Deviation in seasonal rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(-500(100)750, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/nga_v06", replace)

	graph export	"$xfig/nga_v06.pdf", replace
	graph export	"$xfig/nga_v06.png", width(3200) replace
	graph export	"$xfig/nga_v06.eps", replace


**********************************************************************
**## 5.7 - nigeria scaled deviations in total daily rainfall
**********************************************************************

	sort		year
	twoway		(line z_total_season_ year if sat == 1, `p1') ///
				(line z_total_season_ year if sat == 2, `p2') ///
				(line z_total_season_ year if sat == 3, `p3') ///
				(line z_total_season_ year if sat == 4, `p4') ///
				(line z_total_season_ year if sat == 5, `p5') ///
				(line z_total_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Nigeria}", size(4) color("38 43 47")) ///
				ytitle("Standardized deviation in seasonal rainfall", size(3) color("38 43 47")) ///
				ylabel(-3(1)4, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/nga_v07", replace)

	graph export	"$xfig/nga_v07.pdf", replace
	graph export	"$xfig/nga_v07.png", width(3200) replace
	graph export	"$xfig/nga_v07.eps", replace


**********************************************************************
**## 5.8 - nigeria rainfall days
**********************************************************************

	sort		year
	twoway		(line raindays_ year if sat == 1, `p1') ///
				(line raindays_ year if sat == 2, `p2') ///
				(line raindays_ year if sat == 3, `p3') ///
				(line raindays_ year if sat == 4, `p4') ///
				(line raindays_ year if sat == 5, `p5') ///
				(line raindays_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Nigeria}", size(4) color("38 43 47")) ///
				ytitle("Rainy days", size(3) color("38 43 47")) ///
				ylabel(0(30)240, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/nga_v08", replace)

	graph export	"$xfig/nga_v08.pdf", replace
	graph export	"$xfig/nga_v08.png", width(3200) replace
	graph export	"$xfig/nga_v08.eps", replace


**********************************************************************
**## 5.9 - nigeria deviations in rainfall days
**********************************************************************

	sort		year
	twoway		(line dev_raindays_ year if sat == 1, `p1') ///
				(line dev_raindays_ year if sat == 2, `p2') ///
				(line dev_raindays_ year if sat == 3, `p3') ///
				(line dev_raindays_ year if sat == 4, `p4') ///
				(line dev_raindays_ year if sat == 5, `p5') ///
				(line dev_raindays_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Nigeria}", size(4) color("38 43 47")) ///
				ytitle("Deviation in rainy days", size(3) color("38 43 47")) ///
				ylabel(-90(30)90, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/nga_v09", replace)

	graph export	"$xfig/nga_v09.pdf", replace
	graph export	"$xfig/nga_v09.png", width(3200) replace
	graph export	"$xfig/nga_v09.eps", replace


**********************************************************************
**## 5.10 - nigeria no rainfall days
**********************************************************************

	sort		year
	twoway		(line norain_ year if sat == 1, `p1') ///
				(line norain_ year if sat == 2, `p2') ///
				(line norain_ year if sat == 3, `p3') ///
				(line norain_ year if sat == 4, `p4') ///
				(line norain_ year if sat == 5, `p5') ///
				(line norain_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Nigeria}", size(4) color("38 43 47")) ///
				ytitle("Dry days", size(3) color("38 43 47")) ///
				ylabel(0(30)240, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/nga_v10", replace)

	graph export	"$xfig/nga_v10.pdf", replace
	graph export	"$xfig/nga_v10.png", width(3200) replace
	graph export	"$xfig/nga_v10.eps", replace


**********************************************************************
**## 5.11 - nigeria deviations in no rainfall days
**********************************************************************

	sort		year
	twoway		(line dev_norain_ year if sat == 1, `p1') ///
				(line dev_norain_ year if sat == 2, `p2') ///
				(line dev_norain_ year if sat == 3, `p3') ///
				(line dev_norain_ year if sat == 4, `p4') ///
				(line dev_norain_ year if sat == 5, `p5') ///
				(line dev_norain_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Nigeria}", size(4) color("38 43 47")) ///
				ytitle("Deviation in dry days", size(3) color("38 43 47")) ///
				ylabel(-90(30)90, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/nga_v11", replace)

	graph export	"$xfig/nga_v11.pdf", replace
	graph export	"$xfig/nga_v11.png", width(3200) replace
	graph export	"$xfig/nga_v11.eps", replace


**********************************************************************
**## 5.12 - nigeria share of rainy days
**********************************************************************

* draw the country panel with the shared product styles
	sort		year
	twoway		(line percent_raindays_ year if sat == 1, `p1') ///
				(line percent_raindays_ year if sat == 2, `p2') ///
				(line percent_raindays_ year if sat == 3, `p3') ///
				(line percent_raindays_ year if sat == 4, `p4') ///
				(line percent_raindays_ year if sat == 5, `p5') ///
				(line percent_raindays_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Nigeria}", size(4) color("38 43 47")) ///
				ytitle("Share of rainy days (%)", size(3) color("38 43 47")) ///
				ylabel(0(20)100, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/nga_v12", replace)

	graph export	"$xfig/nga_v12.pdf", replace
	graph export	"$xfig/nga_v12.png", width(3200) replace
	graph export	"$xfig/nga_v12.eps", replace


**********************************************************************
**## 5.13 - nigeria deviations in share of rainy days
**********************************************************************

	sort		year
	twoway		(line dev_percent_raindays_ year if sat == 1, `p1') ///
				(line dev_percent_raindays_ year if sat == 2, `p2') ///
				(line dev_percent_raindays_ year if sat == 3, `p3') ///
				(line dev_percent_raindays_ year if sat == 4, `p4') ///
				(line dev_percent_raindays_ year if sat == 5, `p5') ///
				(line dev_percent_raindays_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Nigeria}", size(4) color("38 43 47")) ///
				ytitle("Deviation in share of rainy days", size(3) color("38 43 47")) ///
				ylabel(-0.4(0.1)0.4, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/nga_v13", replace)

	graph export	"$xfig/nga_v13.pdf", replace
	graph export	"$xfig/nga_v13.png", width(3200) replace
	graph export	"$xfig/nga_v13.eps", replace


**********************************************************************
**## 5.14 - nigeria intra season dry spells
**********************************************************************

	sort		year
	twoway		(line dry_ year if sat == 1, `p1') ///
				(line dry_ year if sat == 2, `p2') ///
				(line dry_ year if sat == 3, `p3') ///
				(line dry_ year if sat == 4, `p4') ///
				(line dry_ year if sat == 5, `p5') ///
				(line dry_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Nigeria}", size(4) color("38 43 47")) ///
				ytitle("Longest mid-window dry spell (days)", size(3) color("38 43 47")) ///
				ylabel(0(5)60, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/nga_v14", replace)

	graph export	"$xfig/nga_v14.pdf", replace
	graph export	"$xfig/nga_v14.png", width(3200) replace
	graph export	"$xfig/nga_v14.eps", replace


**********************************************************************
**# 6 - tanzania graphs
**********************************************************************

* identify the household variable used by each survey wave
	loc			ids hhid y2_hhid y3_hhid y4_hhid y4_hhid sdd_hhid y5_hhid
	loc			waves : dir "$rootw/tanzania" dirs "wave_*"
	loc			read_order = 0

* start a temporary country dataset without creating project weather copies
	clear
	gen byte	sat = .
	save		"`weather'", emptyok replace

* read the shared wxsum outputs for each wave and rainfall product
	foreach wave of local waves {
		loc			w = real(subinstr("`wave'", "wave_", "", .))
		loc			id : word `w' of `ids'
		loc			sources : dir "$rootw/tanzania/`wave'/refined" dirs "*_up"

		foreach folder of local sources {
			forvalues s = 1/6 {
				loc			product : word `s' of `products'
				loc			files : dir ///
					"$rootw/tanzania/`wave'/refined/`folder'" ///
					files "*_`product'rf.dta"
				if `"`files'"' == "" {
					display as error ///
						"No `product' rainfall file: tanzania/`wave'/`folder'."
					error 601
				}

				foreach file of local files {
					use			`id' `wide' using ///
						"$rootw/tanzania/`wave'/refined/`folder'/`file'", clear
					reshape long `metrics', i(`id') j(year)
					gen byte	sat = `s'

				* keep wave order when dropping repeated household-year records
					loc			read_order = `read_order' + 1
					gen int		file_order = `read_order'
					append		using "`weather'"
					save		"`weather'", replace
				}
			}
		}
	}

* retain the existing household identifiers and duplicate-removal rule
	sort		file_order
	drop		file_order
	replace		hhid = y2_hhid if hhid == ""
	replace		hhid = y3_hhid if hhid == ""
	replace		hhid = y4_hhid if hhid == ""
	replace		hhid = sdd_hhid if hhid == ""
	replace		hhid = y5_hhid if hhid == ""
	drop		y2_hhid y3_hhid y4_hhid sdd_hhid y5_hhid
	order		sat, after(year)
	duplicates drop
	duplicates drop hhid year sat, force

* calculate the same country-year means using all available years
	collapse	(mean) `metrics', by(year sat)
	label define sat 1 "CHIRPS" 2 "CPC" 3 "MERRA-2" ///
				4 "ARC2" 5 "ERA5" 6 "TAMSAT", replace
	label values sat sat

* change scale of percentage once, after averaging
	replace		percent_raindays_ = percent_raindays_ * 100


**********************************************************************
**## 6.1 - tanzania mean daily rainfall
**********************************************************************

* copy the plotted means without changing the country data
	preserve
		keep		year sat `metrics'
		gen byte	country = 5
		save		"`tza'"
	restore

* draw the country panel with the shared product styles
	sort		year
	twoway		(line mean_season_ year if sat == 1, `p1') ///
				(line mean_season_ year if sat == 2, `p2') ///
				(line mean_season_ year if sat == 3, `p3') ///
				(line mean_season_ year if sat == 4, `p4') ///
				(line mean_season_ year if sat == 5, `p5') ///
				(line mean_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Tanzania}", size(4) color("38 43 47")) ///
				ytitle("Mean daily rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(1)8, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/tza_v01", replace)

	graph export	"$xfig/tza_v01.pdf", replace
	graph export	"$xfig/tza_v01.png", width(3200) replace
	graph export	"$xfig/tza_v01.eps", replace


**********************************************************************
**## 6.2 - tanzania median daily rainfall
**********************************************************************

	sort		year
	twoway		(line median_season_ year if sat == 1, `p1') ///
				(line median_season_ year if sat == 2, `p2') ///
				(line median_season_ year if sat == 3, `p3') ///
				(line median_season_ year if sat == 4, `p4') ///
				(line median_season_ year if sat == 5, `p5') ///
				(line median_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Tanzania}", size(4) color("38 43 47")) ///
				ytitle("Median daily rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(1)8, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/tza_v02", replace)

	graph export	"$xfig/tza_v02.pdf", replace
	graph export	"$xfig/tza_v02.png", width(3200) replace
	graph export	"$xfig/tza_v02.eps", replace


**********************************************************************
**## 6.3 - tanzania variance daily rainfall
**********************************************************************

	sort		year
	twoway		(line sd_season_ year if sat == 1, `p1') ///
				(line sd_season_ year if sat == 2, `p2') ///
				(line sd_season_ year if sat == 3, `p3') ///
				(line sd_season_ year if sat == 4, `p4') ///
				(line sd_season_ year if sat == 5, `p5') ///
				(line sd_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Tanzania}", size(4) color("38 43 47")) ///
				ytitle("SD of daily rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(2)14, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/tza_v03", replace)

	graph export	"$xfig/tza_v03.pdf", replace
	graph export	"$xfig/tza_v03.png", width(3200) replace
	graph export	"$xfig/tza_v03.eps", replace


**********************************************************************
**## 6.4 - tanzania skew daily rainfall
**********************************************************************

	sort		year
	twoway		(line skew_season_ year if sat == 1, `p1') ///
				(line skew_season_ year if sat == 2, `p2') ///
				(line skew_season_ year if sat == 3, `p3') ///
				(line skew_season_ year if sat == 4, `p4') ///
				(line skew_season_ year if sat == 5, `p5') ///
				(line skew_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Tanzania}", size(4) color("38 43 47")) ///
				ytitle("Skewness of daily rainfall", size(3) color("38 43 47")) ///
				ylabel(0.2(0.05)0.7, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/tza_v04", replace)

	graph export	"$xfig/tza_v04.pdf", replace
	graph export	"$xfig/tza_v04.png", width(3200) replace
	graph export	"$xfig/tza_v04.eps", replace


**********************************************************************
**## 6.5 - tanzania total daily rainfall for the growing season
**********************************************************************

	sort		year
	twoway		(line total_season_ year if sat == 1, `p1') ///
				(line total_season_ year if sat == 2, `p2') ///
				(line total_season_ year if sat == 3, `p3') ///
				(line total_season_ year if sat == 4, `p4') ///
				(line total_season_ year if sat == 5, `p5') ///
				(line total_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Tanzania}", size(4) color("38 43 47")) ///
				ytitle("Seasonal rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(200)1800, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/tza_v05", replace)

	graph export	"$xfig/tza_v05.pdf", replace
	graph export	"$xfig/tza_v05.png", width(3200) replace
	graph export	"$xfig/tza_v05.eps", replace


**********************************************************************
**## 6.6 - tanzania deviations in total daily rainfall
**********************************************************************

	sort		year
	twoway		(line dev_total_season_ year if sat == 1, `p1') ///
				(line dev_total_season_ year if sat == 2, `p2') ///
				(line dev_total_season_ year if sat == 3, `p3') ///
				(line dev_total_season_ year if sat == 4, `p4') ///
				(line dev_total_season_ year if sat == 5, `p5') ///
				(line dev_total_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Tanzania}", size(4) color("38 43 47")) ///
				ytitle("Deviation in seasonal rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(-500(100)750, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/tza_v06", replace)

	graph export	"$xfig/tza_v06.pdf", replace
	graph export	"$xfig/tza_v06.png", width(3200) replace
	graph export	"$xfig/tza_v06.eps", replace


**********************************************************************
**## 6.7 - tanzania scaled deviations in total daily rainfall
**********************************************************************

	sort		year
	twoway		(line z_total_season_ year if sat == 1, `p1') ///
				(line z_total_season_ year if sat == 2, `p2') ///
				(line z_total_season_ year if sat == 3, `p3') ///
				(line z_total_season_ year if sat == 4, `p4') ///
				(line z_total_season_ year if sat == 5, `p5') ///
				(line z_total_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Tanzania}", size(4) color("38 43 47")) ///
				ytitle("Standardized deviation in seasonal rainfall", size(3) color("38 43 47")) ///
				ylabel(-3(1)4, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/tza_v07", replace)

	graph export	"$xfig/tza_v07.pdf", replace
	graph export	"$xfig/tza_v07.png", width(3200) replace
	graph export	"$xfig/tza_v07.eps", replace


**********************************************************************
**## 6.8 - tanzania rainfall days
**********************************************************************

	sort		year
	twoway		(line raindays_ year if sat == 1, `p1') ///
				(line raindays_ year if sat == 2, `p2') ///
				(line raindays_ year if sat == 3, `p3') ///
				(line raindays_ year if sat == 4, `p4') ///
				(line raindays_ year if sat == 5, `p5') ///
				(line raindays_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Tanzania}", size(4) color("38 43 47")) ///
				ytitle("Rainy days", size(3) color("38 43 47")) ///
				ylabel(0(30)240, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/tza_v08", replace)

	graph export	"$xfig/tza_v08.pdf", replace
	graph export	"$xfig/tza_v08.png", width(3200) replace
	graph export	"$xfig/tza_v08.eps", replace


**********************************************************************
**## 6.9 - tanzania deviations in rainfall days
**********************************************************************

	sort		year
	twoway		(line dev_raindays_ year if sat == 1, `p1') ///
				(line dev_raindays_ year if sat == 2, `p2') ///
				(line dev_raindays_ year if sat == 3, `p3') ///
				(line dev_raindays_ year if sat == 4, `p4') ///
				(line dev_raindays_ year if sat == 5, `p5') ///
				(line dev_raindays_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Tanzania}", size(4) color("38 43 47")) ///
				ytitle("Deviation in rainy days", size(3) color("38 43 47")) ///
				ylabel(-90(30)90, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/tza_v09", replace)

	graph export	"$xfig/tza_v09.pdf", replace
	graph export	"$xfig/tza_v09.png", width(3200) replace
	graph export	"$xfig/tza_v09.eps", replace


**********************************************************************
**## 6.10 - tanzania no rainfall days
**********************************************************************

	sort		year
	twoway		(line norain_ year if sat == 1, `p1') ///
				(line norain_ year if sat == 2, `p2') ///
				(line norain_ year if sat == 3, `p3') ///
				(line norain_ year if sat == 4, `p4') ///
				(line norain_ year if sat == 5, `p5') ///
				(line norain_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Tanzania}", size(4) color("38 43 47")) ///
				ytitle("Dry days", size(3) color("38 43 47")) ///
				ylabel(0(30)240, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/tza_v10", replace)

	graph export	"$xfig/tza_v10.pdf", replace
	graph export	"$xfig/tza_v10.png", width(3200) replace
	graph export	"$xfig/tza_v10.eps", replace


**********************************************************************
**## 6.11 - tanzania deviations in no rainfall days
**********************************************************************

	sort		year
	twoway		(line dev_norain_ year if sat == 1, `p1') ///
				(line dev_norain_ year if sat == 2, `p2') ///
				(line dev_norain_ year if sat == 3, `p3') ///
				(line dev_norain_ year if sat == 4, `p4') ///
				(line dev_norain_ year if sat == 5, `p5') ///
				(line dev_norain_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Tanzania}", size(4) color("38 43 47")) ///
				ytitle("Deviation in dry days", size(3) color("38 43 47")) ///
				ylabel(-90(30)90, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/tza_v11", replace)

	graph export	"$xfig/tza_v11.pdf", replace
	graph export	"$xfig/tza_v11.png", width(3200) replace
	graph export	"$xfig/tza_v11.eps", replace


**********************************************************************
**## 6.12 - tanzania share of rainy days
**********************************************************************

* draw the country panel with the shared product styles
	sort		year
	twoway		(line percent_raindays_ year if sat == 1, `p1') ///
				(line percent_raindays_ year if sat == 2, `p2') ///
				(line percent_raindays_ year if sat == 3, `p3') ///
				(line percent_raindays_ year if sat == 4, `p4') ///
				(line percent_raindays_ year if sat == 5, `p5') ///
				(line percent_raindays_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Tanzania}", size(4) color("38 43 47")) ///
				ytitle("Share of rainy days (%)", size(3) color("38 43 47")) ///
				ylabel(0(20)100, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/tza_v12", replace)

	graph export	"$xfig/tza_v12.pdf", replace
	graph export	"$xfig/tza_v12.png", width(3200) replace
	graph export	"$xfig/tza_v12.eps", replace


**********************************************************************
**## 6.13 - tanzania deviations in share of rainy days
**********************************************************************

	sort		year
	twoway		(line dev_percent_raindays_ year if sat == 1, `p1') ///
				(line dev_percent_raindays_ year if sat == 2, `p2') ///
				(line dev_percent_raindays_ year if sat == 3, `p3') ///
				(line dev_percent_raindays_ year if sat == 4, `p4') ///
				(line dev_percent_raindays_ year if sat == 5, `p5') ///
				(line dev_percent_raindays_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Tanzania}", size(4) color("38 43 47")) ///
				ytitle("Deviation in share of rainy days", size(3) color("38 43 47")) ///
				ylabel(-0.4(0.1)0.4, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/tza_v13", replace)

	graph export	"$xfig/tza_v13.pdf", replace
	graph export	"$xfig/tza_v13.png", width(3200) replace
	graph export	"$xfig/tza_v13.eps", replace


**********************************************************************
**## 6.14 - tanzania intra season dry spells
**********************************************************************

	sort		year
	twoway		(line dry_ year if sat == 1, `p1') ///
				(line dry_ year if sat == 2, `p2') ///
				(line dry_ year if sat == 3, `p3') ///
				(line dry_ year if sat == 4, `p4') ///
				(line dry_ year if sat == 5, `p5') ///
				(line dry_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Tanzania}", size(4) color("38 43 47")) ///
				ytitle("Longest mid-window dry spell (days)", size(3) color("38 43 47")) ///
				ylabel(0(5)60, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/tza_v14", replace)

	graph export	"$xfig/tza_v14.pdf", replace
	graph export	"$xfig/tza_v14.png", width(3200) replace
	graph export	"$xfig/tza_v14.eps", replace


**********************************************************************
**# 7 - uganda graphs
**********************************************************************

* identify the household variable used by each survey wave
	loc			ids hhid hhid hhid hh hh hhid hhid hhid
	loc			waves : dir "$rootw/uganda" dirs "wave_*"
	loc			read_order = 0

* start a temporary country dataset without creating project weather copies
	clear
	gen byte	sat = .
	save		"`weather'", emptyok replace

* read the shared wxsum outputs for each wave and rainfall product
	foreach wave of local waves {
		loc			w = real(subinstr("`wave'", "wave_", "", .))
		loc			id : word `w' of `ids'
		loc			sources : dir "$rootw/uganda/`wave'/refined" dirs "*_up"

		foreach folder of local sources {
			forvalues s = 1/6 {
				loc			product : word `s' of `products'
				loc			files : dir ///
					"$rootw/uganda/`wave'/refined/`folder'" ///
					files "*_`product'rf_n.dta"
				if `"`files'"' == "" {
					display as error ///
						"No `product' rainfall file: uganda/`wave'/`folder'."
					error 601
				}

				foreach file of local files {
					use			`id' `wide' using ///
						"$rootw/uganda/`wave'/refined/`folder'/`file'", clear
					reshape long `metrics', i(`id') j(year)
					gen byte	sat = `s'

				* keep wave order when dropping repeated household-year records
					loc			read_order = `read_order' + 1
					gen int		file_order = `read_order'
					append		using "`weather'"
					save		"`weather'", replace
				}
			}
		}
	}

* retain the existing household identifiers and duplicate-removal rule
	sort		file_order
	drop		file_order
	replace		hhid = hh if hhid == ""
	drop		hh
	order		sat, after(year)
	duplicates drop
	duplicates drop hhid year sat, force

* calculate the same country-year means using all available years
	collapse	(mean) `metrics', by(year sat)
	label define sat 1 "CHIRPS" 2 "CPC" 3 "MERRA-2" ///
				4 "ARC2" 5 "ERA5" 6 "TAMSAT", replace
	label values sat sat

* change scale of percentage once, after averaging
	replace		percent_raindays_ = percent_raindays_ * 100


**********************************************************************
**## 7.1 - uganda mean daily rainfall
**********************************************************************

* copy the plotted means without changing the country data
	preserve
		keep		year sat `metrics'
		gen byte	country = 6
		save		"`uga'"
	restore

* draw the country panel with the shared product styles
	sort		year
	twoway		(line mean_season_ year if sat == 1, `p1') ///
				(line mean_season_ year if sat == 2, `p2') ///
				(line mean_season_ year if sat == 3, `p3') ///
				(line mean_season_ year if sat == 4, `p4') ///
				(line mean_season_ year if sat == 5, `p5') ///
				(line mean_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Uganda}", size(4) color("38 43 47")) ///
				ytitle("Mean daily rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(1)7, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/uga_v01", replace)

	graph export	"$xfig/uga_v01.pdf", replace
	graph export	"$xfig/uga_v01.png", width(3200) replace
	graph export	"$xfig/uga_v01.eps", replace


**********************************************************************
**## 7.2 - uganda median daily rainfall
**********************************************************************

	sort		year
	twoway		(line median_season_ year if sat == 1, `p1') ///
				(line median_season_ year if sat == 2, `p2') ///
				(line median_season_ year if sat == 3, `p3') ///
				(line median_season_ year if sat == 4, `p4') ///
				(line median_season_ year if sat == 5, `p5') ///
				(line median_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Uganda}", size(4) color("38 43 47")) ///
				ytitle("Median daily rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(1)8, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/uga_v02", replace)

	graph export	"$xfig/uga_v02.pdf", replace
	graph export	"$xfig/uga_v02.png", width(3200) replace
	graph export	"$xfig/uga_v02.eps", replace


**********************************************************************
**## 7.3 - uganda variance daily rainfall
**********************************************************************

	sort		year
	twoway		(line sd_season_ year if sat == 1, `p1') ///
				(line sd_season_ year if sat == 2, `p2') ///
				(line sd_season_ year if sat == 3, `p3') ///
				(line sd_season_ year if sat == 4, `p4') ///
				(line sd_season_ year if sat == 5, `p5') ///
				(line sd_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Uganda}", size(4) color("38 43 47")) ///
				ytitle("SD of daily rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(2)14, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/uga_v03", replace)

	graph export	"$xfig/uga_v03.pdf", replace
	graph export	"$xfig/uga_v03.png", width(3200) replace
	graph export	"$xfig/uga_v03.eps", replace


**********************************************************************
**## 7.4 - uganda skew daily rainfall
**********************************************************************

	sort		year
	twoway		(line skew_season_ year if sat == 1, `p1') ///
				(line skew_season_ year if sat == 2, `p2') ///
				(line skew_season_ year if sat == 3, `p3') ///
				(line skew_season_ year if sat == 4, `p4') ///
				(line skew_season_ year if sat == 5, `p5') ///
				(line skew_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Uganda}", size(4) color("38 43 47")) ///
				ytitle("Skewness of daily rainfall", size(3) color("38 43 47")) ///
				ylabel(0.2(0.05)0.7, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/uga_v04", replace)

	graph export	"$xfig/uga_v04.pdf", replace
	graph export	"$xfig/uga_v04.png", width(3200) replace
	graph export	"$xfig/uga_v04.eps", replace


**********************************************************************
**## 7.5 - uganda total daily rainfall for the growing season
**********************************************************************

	sort		year
	twoway		(line total_season_ year if sat == 1, `p1') ///
				(line total_season_ year if sat == 2, `p2') ///
				(line total_season_ year if sat == 3, `p3') ///
				(line total_season_ year if sat == 4, `p4') ///
				(line total_season_ year if sat == 5, `p5') ///
				(line total_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Uganda}", size(4) color("38 43 47")) ///
				ytitle("Seasonal rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(200)1800, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/uga_v05", replace)

	graph export	"$xfig/uga_v05.pdf", replace
	graph export	"$xfig/uga_v05.png", width(3200) replace
	graph export	"$xfig/uga_v05.eps", replace


**********************************************************************
**## 7.6 - uganda deviations in total daily rainfall
**********************************************************************

	sort		year
	twoway		(line dev_total_season_ year if sat == 1, `p1') ///
				(line dev_total_season_ year if sat == 2, `p2') ///
				(line dev_total_season_ year if sat == 3, `p3') ///
				(line dev_total_season_ year if sat == 4, `p4') ///
				(line dev_total_season_ year if sat == 5, `p5') ///
				(line dev_total_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Uganda}", size(4) color("38 43 47")) ///
				ytitle("Deviation in seasonal rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(-500(100)750, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/uga_v06", replace)

	graph export	"$xfig/uga_v06.pdf", replace
	graph export	"$xfig/uga_v06.png", width(3200) replace
	graph export	"$xfig/uga_v06.eps", replace


**********************************************************************
**## 7.7 - uganda z-score in total daily rainfall
**********************************************************************

	sort		year
	twoway		(line z_total_season_ year if sat == 1, `p1') ///
				(line z_total_season_ year if sat == 2, `p2') ///
				(line z_total_season_ year if sat == 3, `p3') ///
				(line z_total_season_ year if sat == 4, `p4') ///
				(line z_total_season_ year if sat == 5, `p5') ///
				(line z_total_season_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Uganda}", size(4) color("38 43 47")) ///
				ytitle("Standardized deviation in seasonal rainfall", size(3) color("38 43 47")) ///
				ylabel(-3(1)4, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/uga_v07", replace)

	graph export	"$xfig/uga_v07.pdf", replace
	graph export	"$xfig/uga_v07.png", width(3200) replace
	graph export	"$xfig/uga_v07.eps", replace


**********************************************************************
**## 7.8 - uganda rainfall days
**********************************************************************

	sort		year
	twoway		(line raindays_ year if sat == 1, `p1') ///
				(line raindays_ year if sat == 2, `p2') ///
				(line raindays_ year if sat == 3, `p3') ///
				(line raindays_ year if sat == 4, `p4') ///
				(line raindays_ year if sat == 5, `p5') ///
				(line raindays_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Uganda}", size(4) color("38 43 47")) ///
				ytitle("Rainy days", size(3) color("38 43 47")) ///
				ylabel(0(30)240, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/uga_v08", replace)

	graph export	"$xfig/uga_v08.pdf", replace
	graph export	"$xfig/uga_v08.png", width(3200) replace
	graph export	"$xfig/uga_v08.eps", replace


**********************************************************************
**## 7.9 - uganda deviations in rainfall days
**********************************************************************

	sort		year
	twoway		(line dev_raindays_ year if sat == 1, `p1') ///
				(line dev_raindays_ year if sat == 2, `p2') ///
				(line dev_raindays_ year if sat == 3, `p3') ///
				(line dev_raindays_ year if sat == 4, `p4') ///
				(line dev_raindays_ year if sat == 5, `p5') ///
				(line dev_raindays_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Uganda}", size(4) color("38 43 47")) ///
				ytitle("Deviation in rainy days", size(3) color("38 43 47")) ///
				ylabel(-90(30)90, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/uga_v09", replace)

	graph export	"$xfig/uga_v09.pdf", replace
	graph export	"$xfig/uga_v09.png", width(3200) replace
	graph export	"$xfig/uga_v09.eps", replace


**********************************************************************
**## 7.10 - uganda no rainfall days
**********************************************************************

	sort		year
	twoway		(line norain_ year if sat == 1, `p1') ///
				(line norain_ year if sat == 2, `p2') ///
				(line norain_ year if sat == 3, `p3') ///
				(line norain_ year if sat == 4, `p4') ///
				(line norain_ year if sat == 5, `p5') ///
				(line norain_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Uganda}", size(4) color("38 43 47")) ///
				ytitle("Dry days", size(3) color("38 43 47")) ///
				ylabel(0(30)240, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/uga_v10", replace)

	graph export	"$xfig/uga_v10.pdf", replace
	graph export	"$xfig/uga_v10.png", width(3200) replace
	graph export	"$xfig/uga_v10.eps", replace


**********************************************************************
**## 7.11 - uganda deviations in no rainfall days
**********************************************************************

	sort		year
	twoway		(line dev_norain_ year if sat == 1, `p1') ///
				(line dev_norain_ year if sat == 2, `p2') ///
				(line dev_norain_ year if sat == 3, `p3') ///
				(line dev_norain_ year if sat == 4, `p4') ///
				(line dev_norain_ year if sat == 5, `p5') ///
				(line dev_norain_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Uganda}", size(4) color("38 43 47")) ///
				ytitle("Deviation in dry days", size(3) color("38 43 47")) ///
				ylabel(-90(30)90, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/uga_v11", replace)

	graph export	"$xfig/uga_v11.pdf", replace
	graph export	"$xfig/uga_v11.png", width(3200) replace
	graph export	"$xfig/uga_v11.eps", replace


**********************************************************************
**## 7.12 - uganda share of rainy days
**********************************************************************

* draw the country panel with the shared product styles
	sort		year
	twoway		(line percent_raindays_ year if sat == 1, `p1') ///
				(line percent_raindays_ year if sat == 2, `p2') ///
				(line percent_raindays_ year if sat == 3, `p3') ///
				(line percent_raindays_ year if sat == 4, `p4') ///
				(line percent_raindays_ year if sat == 5, `p5') ///
				(line percent_raindays_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Uganda}", size(4) color("38 43 47")) ///
				ytitle("Share of rainy days (%)", size(3) color("38 43 47")) ///
				ylabel(0(20)100, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/uga_v12", replace)

	graph export	"$xfig/uga_v12.pdf", replace
	graph export	"$xfig/uga_v12.png", width(3200) replace
	graph export	"$xfig/uga_v12.eps", replace


**********************************************************************
**## 7.13 - uganda deviations in share of rainy days
**********************************************************************

	sort		year
	twoway		(line dev_percent_raindays_ year if sat == 1, `p1') ///
				(line dev_percent_raindays_ year if sat == 2, `p2') ///
				(line dev_percent_raindays_ year if sat == 3, `p3') ///
				(line dev_percent_raindays_ year if sat == 4, `p4') ///
				(line dev_percent_raindays_ year if sat == 5, `p5') ///
				(line dev_percent_raindays_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Uganda}", size(4) color("38 43 47")) ///
				ytitle("Deviation in share of rainy days", size(3) color("38 43 47")) ///
				ylabel(-0.4(0.1)0.4, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/uga_v13", replace)

	graph export	"$xfig/uga_v13.pdf", replace
	graph export	"$xfig/uga_v13.png", width(3200) replace
	graph export	"$xfig/uga_v13.eps", replace


**********************************************************************
**## 7.14 - uganda intra season dry spells
**********************************************************************

	sort		year
	twoway		(line dry_ year if sat == 1, `p1') ///
				(line dry_ year if sat == 2, `p2') ///
				(line dry_ year if sat == 3, `p3') ///
				(line dry_ year if sat == 4, `p4') ///
				(line dry_ year if sat == 5, `p5') ///
				(line dry_ year if sat == 6, `p6'), ///
				`frame' `years' legend(off) ///
				title("{bf:Uganda}", size(4) color("38 43 47")) ///
				ytitle("Longest mid-window dry spell (days)", size(3) color("38 43 47")) ///
				ylabel(0(5)60, `grid' `ticks' angle(horizontal)) ///
				saving("$sfig/uga_v14", replace)

	graph export	"$xfig/uga_v14.pdf", replace
	graph export	"$xfig/uga_v14.png", width(3200) replace
	graph export	"$xfig/uga_v14.eps", replace


**********************************************************************
**# 8 - combine country panels
**********************************************************************

* reuse the plotted means; do not recalculate the country-year series
	use			"`eth'", clear
	append		using "`mwi'" "`ngr'" "`nga'" "`tza'" "`uga'"
	label define country 1 "{bf:Ethiopia}" 2 "{bf:Malawi}" 3 "{bf:Niger}" ///
				4 "{bf:Nigeria}" 5 "{bf:Tanzania}" 6 "{bf:Uganda}"
	label values country country


**********************************************************************
**## 8.1 - mean daily rainfall (mm)
**********************************************************************

* draw six country panels with one product legend
	sort		country year
	twoway		(line mean_season_ year if sat == 1, `p1') ///
				(line mean_season_ year if sat == 2, `p2') ///
				(line mean_season_ year if sat == 3, `p3') ///
				(line mean_season_ year if sat == 4, `p4') ///
				(line mean_season_ year if sat == 5, `p5') ///
				(line mean_season_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("Mean daily rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(, `grid' `ticks' angle(horizontal)) ///
				subtitle(, size(3.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) yrescale iyaxes iylabel iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v01.pdf", replace
	graph export	"$xfig/all_v01.png", width(3200) replace
	graph export	"$xfig/all_v01.eps", replace


**********************************************************************
**## 8.2 - median daily rainfall (mm)
**********************************************************************

* draw six country panels with one product legend
	sort		country year
	twoway		(line median_season_ year if sat == 1, `p1') ///
				(line median_season_ year if sat == 2, `p2') ///
				(line median_season_ year if sat == 3, `p3') ///
				(line median_season_ year if sat == 4, `p4') ///
				(line median_season_ year if sat == 5, `p5') ///
				(line median_season_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("Median daily rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(, `grid' `ticks' angle(horizontal)) ///
				subtitle(, size(3.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) yrescale iyaxes iylabel iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v02.pdf", replace
	graph export	"$xfig/all_v02.png", width(3200) replace
	graph export	"$xfig/all_v02.eps", replace


**********************************************************************
**## 8.3 - sd of daily rainfall (mm)
**********************************************************************

* draw six country panels with one product legend
	sort		country year
	twoway		(line sd_season_ year if sat == 1, `p1') ///
				(line sd_season_ year if sat == 2, `p2') ///
				(line sd_season_ year if sat == 3, `p3') ///
				(line sd_season_ year if sat == 4, `p4') ///
				(line sd_season_ year if sat == 5, `p5') ///
				(line sd_season_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("SD of daily rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(, `grid' `ticks' angle(horizontal)) ///
				subtitle(, size(3.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) yrescale iyaxes iylabel iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v03.pdf", replace
	graph export	"$xfig/all_v03.png", width(3200) replace
	graph export	"$xfig/all_v03.eps", replace


**********************************************************************
**## 8.4 - skewness of daily rainfall
**********************************************************************

* draw six country panels with one product legend
	sort		country year
	twoway		(line skew_season_ year if sat == 1, `p1') ///
				(line skew_season_ year if sat == 2, `p2') ///
				(line skew_season_ year if sat == 3, `p3') ///
				(line skew_season_ year if sat == 4, `p4') ///
				(line skew_season_ year if sat == 5, `p5') ///
				(line skew_season_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("Skewness of daily rainfall", size(3) color("38 43 47")) ///
				ylabel(, `grid' `ticks' angle(horizontal)) ///
				subtitle(, size(3.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) yrescale iyaxes iylabel iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v04.pdf", replace
	graph export	"$xfig/all_v04.png", width(3200) replace
	graph export	"$xfig/all_v04.eps", replace


**********************************************************************
**## 8.5 - seasonal rainfall (mm)
**********************************************************************

* draw six country panels with one product legend
	sort		country year
	twoway		(line total_season_ year if sat == 1, `p1') ///
				(line total_season_ year if sat == 2, `p2') ///
				(line total_season_ year if sat == 3, `p3') ///
				(line total_season_ year if sat == 4, `p4') ///
				(line total_season_ year if sat == 5, `p5') ///
				(line total_season_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("Seasonal rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(, `grid' `ticks' angle(horizontal)) ///
				subtitle(, size(3.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) yrescale iyaxes iylabel iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v05.pdf", replace
	graph export	"$xfig/all_v05.png", width(3200) replace
	graph export	"$xfig/all_v05.eps", replace


**********************************************************************
**## 8.6 - deviation in seasonal rainfall (mm)
**********************************************************************

* draw six country panels with one product legend
	sort		country year
	twoway		(line dev_total_season_ year if sat == 1, `p1') ///
				(line dev_total_season_ year if sat == 2, `p2') ///
				(line dev_total_season_ year if sat == 3, `p3') ///
				(line dev_total_season_ year if sat == 4, `p4') ///
				(line dev_total_season_ year if sat == 5, `p5') ///
				(line dev_total_season_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("Deviation in seasonal rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(, `grid' `ticks' angle(horizontal)) ///
				subtitle(, size(3.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) yrescale iyaxes iylabel iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v06.pdf", replace
	graph export	"$xfig/all_v06.png", width(3200) replace
	graph export	"$xfig/all_v06.eps", replace


**********************************************************************
**## 8.7 - standardized deviation in seasonal rainfall
**********************************************************************

* draw six country panels with one product legend
	sort		country year
	twoway		(line z_total_season_ year if sat == 1, `p1') ///
				(line z_total_season_ year if sat == 2, `p2') ///
				(line z_total_season_ year if sat == 3, `p3') ///
				(line z_total_season_ year if sat == 4, `p4') ///
				(line z_total_season_ year if sat == 5, `p5') ///
				(line z_total_season_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("Standardized deviation in seasonal rainfall", size(3) color("38 43 47")) ///
				ylabel(, `grid' `ticks' angle(horizontal)) ///
				subtitle(, size(3.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) yrescale iyaxes iylabel iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v07.pdf", replace
	graph export	"$xfig/all_v07.png", width(3200) replace
	graph export	"$xfig/all_v07.eps", replace


**********************************************************************
**## 8.8 - rainy days
**********************************************************************

* draw six country panels with one product legend
	sort		country year
	twoway		(line raindays_ year if sat == 1, `p1') ///
				(line raindays_ year if sat == 2, `p2') ///
				(line raindays_ year if sat == 3, `p3') ///
				(line raindays_ year if sat == 4, `p4') ///
				(line raindays_ year if sat == 5, `p5') ///
				(line raindays_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("Rainy days", size(3) color("38 43 47")) ///
				ylabel(, `grid' `ticks' angle(horizontal)) ///
				subtitle(, size(3.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) yrescale iyaxes iylabel iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v08.pdf", replace
	graph export	"$xfig/all_v08.png", width(3200) replace
	graph export	"$xfig/all_v08.eps", replace


**********************************************************************
**## 8.9 - deviation in rainy days
**********************************************************************

* draw six country panels with one product legend
	sort		country year
	twoway		(line dev_raindays_ year if sat == 1, `p1') ///
				(line dev_raindays_ year if sat == 2, `p2') ///
				(line dev_raindays_ year if sat == 3, `p3') ///
				(line dev_raindays_ year if sat == 4, `p4') ///
				(line dev_raindays_ year if sat == 5, `p5') ///
				(line dev_raindays_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("Deviation in rainy days", size(3) color("38 43 47")) ///
				ylabel(, `grid' `ticks' angle(horizontal)) ///
				subtitle(, size(3.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) yrescale iyaxes iylabel iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v09.pdf", replace
	graph export	"$xfig/all_v09.png", width(3200) replace
	graph export	"$xfig/all_v09.eps", replace


**********************************************************************
**## 8.10 - dry days
**********************************************************************

* draw six country panels with one product legend
	sort		country year
	twoway		(line norain_ year if sat == 1, `p1') ///
				(line norain_ year if sat == 2, `p2') ///
				(line norain_ year if sat == 3, `p3') ///
				(line norain_ year if sat == 4, `p4') ///
				(line norain_ year if sat == 5, `p5') ///
				(line norain_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("Dry days", size(3) color("38 43 47")) ///
				ylabel(, `grid' `ticks' angle(horizontal)) ///
				subtitle(, size(3.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) yrescale iyaxes iylabel iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v10.pdf", replace
	graph export	"$xfig/all_v10.png", width(3200) replace
	graph export	"$xfig/all_v10.eps", replace


**********************************************************************
**## 8.11 - deviation in dry days
**********************************************************************

* draw six country panels with one product legend
	sort		country year
	twoway		(line dev_norain_ year if sat == 1, `p1') ///
				(line dev_norain_ year if sat == 2, `p2') ///
				(line dev_norain_ year if sat == 3, `p3') ///
				(line dev_norain_ year if sat == 4, `p4') ///
				(line dev_norain_ year if sat == 5, `p5') ///
				(line dev_norain_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("Deviation in dry days", size(3) color("38 43 47")) ///
				ylabel(, `grid' `ticks' angle(horizontal)) ///
				subtitle(, size(3.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) yrescale iyaxes iylabel iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v11.pdf", replace
	graph export	"$xfig/all_v11.png", width(3200) replace
	graph export	"$xfig/all_v11.eps", replace


**********************************************************************
**## 8.12 - share of rainy days (%)
**********************************************************************

* draw six country panels with one product legend
	sort		country year
	twoway		(line percent_raindays_ year if sat == 1, `p1') ///
				(line percent_raindays_ year if sat == 2, `p2') ///
				(line percent_raindays_ year if sat == 3, `p3') ///
				(line percent_raindays_ year if sat == 4, `p4') ///
				(line percent_raindays_ year if sat == 5, `p5') ///
				(line percent_raindays_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("Share of rainy days (%)", size(3) color("38 43 47")) ///
				ylabel(0(20)100, `grid' `ticks' angle(horizontal)) ///
				subtitle(, size(3.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v12.pdf", replace
	graph export	"$xfig/all_v12.png", width(3200) replace
	graph export	"$xfig/all_v12.eps", replace


**********************************************************************
**## 8.13 - deviation in share of rainy days
**********************************************************************

* draw six country panels with one product legend
	sort		country year
	twoway		(line dev_percent_raindays_ year if sat == 1, `p1') ///
				(line dev_percent_raindays_ year if sat == 2, `p2') ///
				(line dev_percent_raindays_ year if sat == 3, `p3') ///
				(line dev_percent_raindays_ year if sat == 4, `p4') ///
				(line dev_percent_raindays_ year if sat == 5, `p5') ///
				(line dev_percent_raindays_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("Deviation in share of rainy days", size(3) color("38 43 47")) ///
				ylabel(, `grid' `ticks' angle(horizontal)) ///
				subtitle(, size(3.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) yrescale iyaxes iylabel iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v13.pdf", replace
	graph export	"$xfig/all_v13.png", width(3200) replace
	graph export	"$xfig/all_v13.eps", replace


**********************************************************************
**## 8.14 - longest dry spell (days)
**********************************************************************

* draw six country panels with one product legend
	sort		country year
	twoway		(line dry_ year if sat == 1, `p1') ///
				(line dry_ year if sat == 2, `p2') ///
				(line dry_ year if sat == 3, `p3') ///
				(line dry_ year if sat == 4, `p4') ///
				(line dry_ year if sat == 5, `p5') ///
				(line dry_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("Longest mid-window dry spell (days)", size(3) color("38 43 47")) ///
				ylabel(, `grid' `ticks' angle(horizontal)) ///
				subtitle(, size(3.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) yrescale iyaxes iylabel iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v14.pdf", replace
	graph export	"$xfig/all_v14.png", width(3200) replace
	graph export	"$xfig/all_v14.eps", replace

* close the log
	log close

/* END */
