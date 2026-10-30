* Project: WB Weather
* Created on: April 2024
* Created by: jdm
* edited by: codex
* edited on: 30 Oct 2026
* Stata v.18.0

* does
	* produces fourteen six-panel rainfall summary figures

* assumes
	* wxsum outputs in the shared weather_data refined folders

* TO DO:
	* done


**********************************************************************
**# 0 - setup
**********************************************************************

* define paths
	global		rootw 	= 	"$wraw"
	global		xfig    =   "$data/results_data/figures/metric_paper"
	global		logout 	= 	"$data/regression_data/logs"

* load the shared product palette and figure styles
	include		"$code/analysis/viz_code/metric_style.do"

* store country-year means for the final six-panel figures
	tempfile	eth mwi ngr nga tza uga

* open log
	cap log close
	log 	using 		"$logout/metric_sum", append


**********************************************************************
**# 1 - define rainfall inputs
**********************************************************************

* assign canonical product IDs from the wxsum output filenames
	loc			products arc2 chirps cpc era merra tamsat

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
**# 2 - ethiopia summary data
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
	label define sat 1 "ARC2" 2 "CHIRPS" 3 "CPC" ///
				4 "ERA5" 5 "MERRA-2" 6 "TAMSAT", replace
	label values sat sat

* change scale of percentage once, after averaging
	replace		percent_raindays_ = percent_raindays_ * 100

* store country-year means for the final six-panel figures
	keep		year sat `metrics'
	gen byte	country = 1
	save		"`eth'"


**********************************************************************
**# 3 - malawi summary data
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
	label define sat 1 "ARC2" 2 "CHIRPS" 3 "CPC" ///
				4 "ERA5" 5 "MERRA-2" 6 "TAMSAT", replace
	label values sat sat

* change scale of percentage once, after averaging
	replace		percent_raindays_ = percent_raindays_ * 100

* store country-year means for the final six-panel figures
	keep		year sat `metrics'
	gen byte	country = 2
	save		"`mwi'"


**********************************************************************
**# 4 - niger summary data
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
	label define sat 1 "ARC2" 2 "CHIRPS" 3 "CPC" ///
				4 "ERA5" 5 "MERRA-2" 6 "TAMSAT", replace
	label values sat sat

* change scale of percentage once, after averaging
	replace		percent_raindays_ = percent_raindays_ * 100

* store country-year means for the final six-panel figures
	keep		year sat `metrics'
	gen byte	country = 3
	save		"`ngr'"


**********************************************************************
**# 5 - nigeria summary data
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
	label define sat 1 "ARC2" 2 "CHIRPS" 3 "CPC" ///
				4 "ERA5" 5 "MERRA-2" 6 "TAMSAT", replace
	label values sat sat

* change scale of percentage once, after averaging
	replace		percent_raindays_ = percent_raindays_ * 100

* store country-year means for the final six-panel figures
	keep		year sat `metrics'
	gen byte	country = 4
	save		"`nga'"


**********************************************************************
**# 6 - tanzania summary data
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
	label define sat 1 "ARC2" 2 "CHIRPS" 3 "CPC" ///
				4 "ERA5" 5 "MERRA-2" 6 "TAMSAT", replace
	label values sat sat

* change scale of percentage once, after averaging
	replace		percent_raindays_ = percent_raindays_ * 100

* store country-year means for the final six-panel figures
	keep		year sat `metrics'
	gen byte	country = 5
	save		"`tza'"


**********************************************************************
**# 7 - uganda summary data
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
	label define sat 1 "ARC2" 2 "CHIRPS" 3 "CPC" ///
				4 "ERA5" 5 "MERRA-2" 6 "TAMSAT", replace
	label values sat sat

* change scale of percentage once, after averaging
	replace		percent_raindays_ = percent_raindays_ * 100

* store country-year means for the final six-panel figures
	keep		year sat `metrics'
	gen byte	country = 6
	save		"`uga'"


**********************************************************************
**# 8 - six-panel rainfall summary figures
**********************************************************************

* combine the country-year means for all six panels
	use			"`eth'", clear
	append		using "`mwi'" "`ngr'" "`nga'" "`tza'" "`uga'"
	label define country 1 "{bf:Ethiopia}" 2 "{bf:Malawi}" 3 "{bf:Niger}" ///
				4 "{bf:Nigeria}" 5 "{bf:Tanzania}" 6 "{bf:Uganda}"
	label values country country


**********************************************************************
**## 8.1 - mean daily rainfall (mm)
**********************************************************************

* draw six country panels with one product legend
	quietly summarize	mean_season_, meanonly
	loc			ymax = ceil(r(max) / 2) * 2
	sort		country year
	twoway		(line mean_season_ year if sat == 1, `p1') ///
				(line mean_season_ year if sat == 2, `p2') ///
				(line mean_season_ year if sat == 3, `p3') ///
				(line mean_season_ year if sat == 4, `p4') ///
				(line mean_season_ year if sat == 5, `p5') ///
				(line mean_season_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("Mean Daily Rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(2)`ymax', format(%9.0fc) ///
				`pale' `ticks' angle(horizontal)) ///
				subtitle(, size(2.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v01.pdf", replace
	graph export	"$xfig/all_v01.png", width(3200) replace


**********************************************************************
**## 8.2 - median daily rainfall (mm)
**********************************************************************

* draw six country panels with one product legend
	quietly summarize	median_season_, meanonly
	loc			ymax = ceil(r(max) / 2) * 2
	sort		country year
	twoway		(line median_season_ year if sat == 1, `p1') ///
				(line median_season_ year if sat == 2, `p2') ///
				(line median_season_ year if sat == 3, `p3') ///
				(line median_season_ year if sat == 4, `p4') ///
				(line median_season_ year if sat == 5, `p5') ///
				(line median_season_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("Median Daily Rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(2)`ymax', format(%9.0fc) ///
				`grid' `ticks' angle(horizontal)) ///
				subtitle(, size(3.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v02.pdf", replace
	graph export	"$xfig/all_v02.png", width(3200) replace


**********************************************************************
**## 8.3 - sd of daily rainfall (mm)
**********************************************************************

* draw six country panels with one product legend
	quietly summarize	sd_season_, meanonly
	loc			ymax = ceil(r(max) / 5) * 5
	sort		country year
	twoway		(line sd_season_ year if sat == 1, `p1') ///
				(line sd_season_ year if sat == 2, `p2') ///
				(line sd_season_ year if sat == 3, `p3') ///
				(line sd_season_ year if sat == 4, `p4') ///
				(line sd_season_ year if sat == 5, `p5') ///
				(line sd_season_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("SD Of Daily Rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(5)`ymax', format(%9.0fc) ///
				`grid' `ticks' angle(horizontal)) ///
				subtitle(, size(3.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v03.pdf", replace
	graph export	"$xfig/all_v03.png", width(3200) replace


**********************************************************************
**## 8.4 - skewness of daily rainfall
**********************************************************************

* draw six country panels with one product legend
	quietly summarize	skew_season_, meanonly
	loc			ymax = ceil(r(max) / 2) * 2
	sort		country year
	twoway		(line skew_season_ year if sat == 1, `p1') ///
				(line skew_season_ year if sat == 2, `p2') ///
				(line skew_season_ year if sat == 3, `p3') ///
				(line skew_season_ year if sat == 4, `p4') ///
				(line skew_season_ year if sat == 5, `p5') ///
				(line skew_season_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("Skewness Of Daily Rainfall", size(3) color("38 43 47")) ///
				ylabel(0(2)`ymax', format(%9.0fc) ///
				`grid' `ticks' angle(horizontal)) ///
				subtitle(, size(3.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v04.pdf", replace
	graph export	"$xfig/all_v04.png", width(3200) replace


**********************************************************************
**## 8.5 - seasonal rainfall (mm)
**********************************************************************

* draw six country panels with one product legend
	quietly summarize	total_season_, meanonly
	loc			ymax = ceil(r(max) / 500) * 500
	sort		country year
	twoway		(line total_season_ year if sat == 1, `p1') ///
				(line total_season_ year if sat == 2, `p2') ///
				(line total_season_ year if sat == 3, `p3') ///
				(line total_season_ year if sat == 4, `p4') ///
				(line total_season_ year if sat == 5, `p5') ///
				(line total_season_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("Seasonal Rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(0(500)`ymax', format(%9.0fc) ///
				`grid' `ticks' angle(horizontal)) ///
				subtitle(, size(3.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v05.pdf", replace
	graph export	"$xfig/all_v05.png", width(3200) replace


**********************************************************************
**## 8.6 - deviation in seasonal rainfall (mm)
**********************************************************************

* draw six country panels with one product legend
	quietly summarize	dev_total_season_, meanonly
	loc			ymin = floor(min(0, r(min)) / 250) * 250
	loc			ymax = ceil(r(max) / 250) * 250
	sort		country year
	twoway		(line dev_total_season_ year if sat == 1, `p1') ///
				(line dev_total_season_ year if sat == 2, `p2') ///
				(line dev_total_season_ year if sat == 3, `p3') ///
				(line dev_total_season_ year if sat == 4, `p4') ///
				(line dev_total_season_ year if sat == 5, `p5') ///
				(line dev_total_season_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("Deviation In Seasonal Rainfall (mm)", size(3) color("38 43 47")) ///
				ylabel(`ymin'(250)`ymax', format(%9.0fc) ///
				`grid' `ticks' angle(horizontal)) ///
				subtitle(, size(3.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v06.pdf", replace
	graph export	"$xfig/all_v06.png", width(3200) replace


**********************************************************************
**## 8.7 - standardized deviation in seasonal rainfall
**********************************************************************

* draw six country panels with one product legend
	quietly summarize	z_total_season_, meanonly
	loc			ymin = floor(min(0, r(min)) / 1) * 1
	loc			ymax = ceil(r(max) / 1) * 1
	sort		country year
	twoway		(line z_total_season_ year if sat == 1, `p1') ///
				(line z_total_season_ year if sat == 2, `p2') ///
				(line z_total_season_ year if sat == 3, `p3') ///
				(line z_total_season_ year if sat == 4, `p4') ///
				(line z_total_season_ year if sat == 5, `p5') ///
				(line z_total_season_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("Standardized Deviation In Seasonal Rainfall", size(3) color("38 43 47")) ///
				ylabel(`ymin'(1)`ymax', format(%9.0fc) ///
				`grid' `ticks' angle(horizontal)) ///
				subtitle(, size(3.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v07.pdf", replace
	graph export	"$xfig/all_v07.png", width(3200) replace


**********************************************************************
**## 8.8 - rainy days
**********************************************************************

* draw six country panels with one product legend
	quietly summarize	raindays_, meanonly
	loc			ymax = ceil(r(max) / 50) * 50
	sort		country year
	twoway		(line raindays_ year if sat == 1, `p1') ///
				(line raindays_ year if sat == 2, `p2') ///
				(line raindays_ year if sat == 3, `p3') ///
				(line raindays_ year if sat == 4, `p4') ///
				(line raindays_ year if sat == 5, `p5') ///
				(line raindays_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("Rainy Days", size(3) color("38 43 47")) ///
				ylabel(0(50)`ymax', format(%9.0fc) ///
				`grid' `ticks' angle(horizontal)) ///
				subtitle(, size(3.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v08.pdf", replace
	graph export	"$xfig/all_v08.png", width(3200) replace


**********************************************************************
**## 8.9 - deviation in rainy days
**********************************************************************

* draw six country panels with one product legend
	quietly summarize	dev_raindays_, meanonly
	loc			ymin = floor(min(0, r(min)) / 20) * 20
	loc			ymax = ceil(r(max) / 20) * 20
	sort		country year
	twoway		(line dev_raindays_ year if sat == 1, `p1') ///
				(line dev_raindays_ year if sat == 2, `p2') ///
				(line dev_raindays_ year if sat == 3, `p3') ///
				(line dev_raindays_ year if sat == 4, `p4') ///
				(line dev_raindays_ year if sat == 5, `p5') ///
				(line dev_raindays_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("Deviation In Rainy Days", size(3) color("38 43 47")) ///
				ylabel(`ymin'(20)`ymax', format(%9.0fc) ///
				`grid' `ticks' angle(horizontal)) ///
				subtitle(, size(3.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v09.pdf", replace
	graph export	"$xfig/all_v09.png", width(3200) replace


**********************************************************************
**## 8.10 - dry days
**********************************************************************

* draw six country panels with one product legend
	quietly summarize	norain_, meanonly
	loc			ymax = ceil(r(max) / 50) * 50
	sort		country year
	twoway		(line norain_ year if sat == 1, `p1') ///
				(line norain_ year if sat == 2, `p2') ///
				(line norain_ year if sat == 3, `p3') ///
				(line norain_ year if sat == 4, `p4') ///
				(line norain_ year if sat == 5, `p5') ///
				(line norain_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("Dry Days", size(3) color("38 43 47")) ///
				ylabel(0(50)`ymax', format(%9.0fc) ///
				`grid' `ticks' angle(horizontal)) ///
				subtitle(, size(3.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v10.pdf", replace
	graph export	"$xfig/all_v10.png", width(3200) replace


**********************************************************************
**## 8.11 - deviation in dry days
**********************************************************************

* draw six country panels with one product legend
	quietly summarize	dev_norain_, meanonly
	loc			ymin = floor(min(0, r(min)) / 20) * 20
	loc			ymax = ceil(r(max) / 20) * 20
	sort		country year
	twoway		(line dev_norain_ year if sat == 1, `p1') ///
				(line dev_norain_ year if sat == 2, `p2') ///
				(line dev_norain_ year if sat == 3, `p3') ///
				(line dev_norain_ year if sat == 4, `p4') ///
				(line dev_norain_ year if sat == 5, `p5') ///
				(line dev_norain_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("Deviation In Dry Days", size(3) color("38 43 47")) ///
				ylabel(`ymin'(20)`ymax', format(%9.0fc) ///
				`grid' `ticks' angle(horizontal)) ///
				subtitle(, size(3.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v11.pdf", replace
	graph export	"$xfig/all_v11.png", width(3200) replace


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
				ytitle("Share Of Rainy Days (%)", size(3) color("38 43 47")) ///
				ylabel(0(20)100, `pale' `ticks' angle(horizontal)) ///
				subtitle(, size(2.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v12.pdf", replace
	graph export	"$xfig/all_v12.png", width(3200) replace


**********************************************************************
**## 8.13 - deviation in share of rainy days
**********************************************************************

* draw six country panels with one product legend
	quietly summarize	dev_percent_raindays_, meanonly
	loc			ymin = floor(min(0, r(min)) / 0.1) * 0.1
	loc			ymax = ceil(r(max) / 0.1) * 0.1
	sort		country year
	twoway		(line dev_percent_raindays_ year if sat == 1, `p1') ///
				(line dev_percent_raindays_ year if sat == 2, `p2') ///
				(line dev_percent_raindays_ year if sat == 3, `p3') ///
				(line dev_percent_raindays_ year if sat == 4, `p4') ///
				(line dev_percent_raindays_ year if sat == 5, `p5') ///
				(line dev_percent_raindays_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("Deviation In Share Of Rainy Days", size(3) color("38 43 47")) ///
				ylabel(`ymin'(0.1)`ymax', format(%4.1f) ///
				`grid' `ticks' angle(horizontal)) ///
				subtitle(, size(3.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v13.pdf", replace
	graph export	"$xfig/all_v13.png", width(3200) replace


**********************************************************************
**## 8.14 - longest dry spell (days)
**********************************************************************

* draw six country panels with one product legend
	quietly summarize	dry_, meanonly
	loc			ymax = ceil(r(max) / 10) * 10
	sort		country year
	twoway		(line dry_ year if sat == 1, `p1') ///
				(line dry_ year if sat == 2, `p2') ///
				(line dry_ year if sat == 3, `p3') ///
				(line dry_ year if sat == 4, `p4') ///
				(line dry_ year if sat == 5, `p5') ///
				(line dry_ year if sat == 6, `p6'), ///
				`frame' `years' `key' ///
				ytitle("Longest Mid-Window Dry Spell (Days)", size(3) color("38 43 47")) ///
				ylabel(0(10)`ymax', format(%9.0fc) ///
				`grid' `ticks' angle(horizontal)) ///
				subtitle(, size(3.8) color("38 43 47") nobox fcolor(white)) ///
				by(country, cols(3) iscale(1) ///
				legend(pos(6)) note("") imargin(small) ///
				graphregion(color(white) margin(small))) ///
				xsize(7.2) ysize(4.7)

	graph export	"$xfig/all_v14.pdf", replace
	graph export	"$xfig/all_v14.png", width(3200) replace



**********************************************************************
**# 9 - end matter
**********************************************************************

* close the log
	log close

/* END */
