* Project: WB Weather
* Created on: April 2024
* Created by: jdm
* Edited by: jdm
* Last edit: 16 April 2024
* Stata v.18.0 

* does
	* merges weather data with Ethiopia ESS 3 data

* assumes
	* cleaned ESS 3 data
	* processed wave 3 weather data

* TO DO:
	* done

	
* **********************************************************************
* 0 - setup
* **********************************************************************

* define paths
	global	rootw 	= 	"$data/weather_data"
	global	rooth 	= 	"$data/household_data"
	global	export 	= 	"$data/results_data"
	global	sfig	= 	"$data/results_data/figures"
	global 	xfig    =   "$data/output/metric_paper/figures"
	global	logout 	= 	"$data/regression_data/logs"

* open log	
	cap log close 
	log 	using 		"$logout/sum_long", append

	
************************************************************************
**# 1 - process rainfall data
************************************************************************
	
	
************************************************************************
**## 1.A - ethiopia
************************************************************************

	* define local with all waves in it
		loc 		waveList : dir "$rootw/ethiopia" dirs "wave_*"
		display 	`waveList'
		
	* loop through all wave folder in country folders	
		foreach 	wave of local waveList {
	
		* define local with all satelites in it
			loc 		satList : dir "$rootw/ethiopia/`wave'/refined" dirs "*_rf*"
			display		`satList'
			
		* loop through each satelite folder in wave in country
			foreach 	sat of local satList {
		
			* define each file in the above local
				loc 		fileList : dir "$rootw/ethiopia/`wave'/refined/`sat'" files "*_x3_rf*.dta"
				display		`fileList'
				
			* loop through each file
				foreach 	file in `fileList' {	
	
				* merge weather data with household data
					use 		"$rootw/ethiopia/`wave'/refined/`sat'/`file'", clear
		
					drop 		sd_period_percent_raindays mean_period_percent_raindays ///
									sd_period_norain mean_period_norain sd_period_raindays ///
									mean_period_raindays sd_period_total_season ///
									mean_period_total_season
		
					reshape long mean_season_ median_season_ sd_season_ total_season_ ///
								skew_season_ norain_ raindays_ percent_raindays_ dry_ ///
								dev_total_season_ dev_total_season_ z_total_season_ dev_raindays_ ///
								dev_norain_ dev_percent_raindays_, i(household_id*) j(year)
		
				* define file naming criteria
					loc 		sat = substr("`file'", 10, 3)
					loc 		ext = substr("`file'", 7, 2)
			
				* generate variable to record extraction method
					gen 		`sat'_`ext' = "`sat'_`ext'"
					lab var 	`sat'_`ext' "Satellite/Extraction"			
							
					display		"$rootw/ethiopia/`wave'/refined/`sat'/`file'"
			
					save		"$export/ethiopia/`file'", replace
				}						
			}	
		}


************************************************************************
**## 1.B - malawi
************************************************************************

	* define local with all waves in it
		loc 		waveList : dir "$rootw/malawi" dirs "wave_*"
		display 	`waveList'
		
	* loop through all wave folder in country folders	
		foreach 	wave of local waveList {
	
		* define local with all satelites in it
			loc 		satList : dir "$rootw/malawi/`wave'/refined" dirs "*_rf*"
			display		`satList'
			
		* loop through each satelite folder in wave in country
			foreach 	sat of local satList {
		
			* define each file in the above local
				loc 		fileList : dir "$rootw/malawi/`wave'/refined/`sat'" files "*_x3_rf*.dta"
				display		`fileList'
				
			* loop through each file
				foreach 	file in `fileList' {	
	
				* merge weather data with household data
					use 		"$rootw/malawi/`wave'/refined/`sat'/`file'", clear
		
					drop 		sd_period_percent_raindays mean_period_percent_raindays ///
									sd_period_norain mean_period_norain sd_period_raindays ///
									mean_period_raindays sd_period_total_season ///
									mean_period_total_season
		
					reshape long mean_season_ median_season_ sd_season_ total_season_ ///
								skew_season_ norain_ raindays_ percent_raindays_ dry_ ///
								dev_total_season_ z_total_season_ dev_raindays_ ///
								dev_norain_ dev_percent_raindays_, i(*id) j(year)
		
				* define file naming criteria
					loc 		sat = substr("`file'", 9, 3)
					loc 		ext = substr("`file'", 6, 2)
			
				* generate variable to record extraction method
					gen 		`sat'_`ext' = "`sat'_`ext'"
					lab var 	`sat'_`ext' "Satellite/Extraction"			
							
					display		"$rootw/malawi/`wave'/refined/`sat'/`file'"
			
					save		"$export/malawi/`file'", replace
				}						
			}	
		}


************************************************************************
**## 1.D - niger
************************************************************************

	* define local with all waves in it
		loc 		waveList : dir "$rootw/niger" dirs "wave_*"
		display 	`waveList'
		
	* loop through all wave folder in country folders	
		foreach 	wave of local waveList {
	
		* define local with all satelites in it
			loc 		satList : dir "$rootw/niger/`wave'/refined" dirs "*_rf*"
			display		`satList'
			
		* loop through each satelite folder in wave in country
			foreach 	sat of local satList {
		
			* define each file in the above local
				loc 		fileList : dir "$rootw/niger/`wave'/refined/`sat'" files "*_x3_rf*.dta"
				display		`fileList'
				
			* loop through each file
				foreach 	file in `fileList' {	
	
				* merge weather data with household data
					use 		"$rootw/niger/`wave'/refined/`sat'/`file'", clear
		
					drop 		sd_period_percent_raindays mean_period_percent_raindays ///
									sd_period_norain mean_period_norain sd_period_raindays ///
									mean_period_raindays sd_period_total_season ///
									mean_period_total_season
		
					reshape long mean_season_ median_season_ sd_season_ total_season_ ///
								skew_season_ norain_ raindays_ percent_raindays_ dry_ ///
								dev_total_season_  z_total_season_ dev_raindays_ ///
								dev_norain_ dev_percent_raindays_, i(*hid*) j(year)
		
				* define file naming criteria
					loc 		sat = substr("`file'", 12, 3)
					loc 		ext = substr("`file'", 9, 2)
			
				* generate variable to record extraction method
					gen 		`sat'_`ext' = "`sat'_`ext'"
					lab var 	`sat'_`ext' "Satellite/Extraction"			
							
					display		"$rootw/niger/`wave'/refined/`sat'/`file'"
			
					save		"$export/niger/`file'", replace
				}						
			}	
		}


************************************************************************
**## 1.D - nigeria
************************************************************************

	* define local with all waves in it
		loc 		waveList : dir "$rootw/nigeria" dirs "wave_*"
		display 	`waveList'
		
	* loop through all wave folder in country folders	
		foreach 	wave of local waveList {
	
		* define local with all satelites in it
			loc 		satList : dir "$rootw/nigeria/`wave'/refined" dirs "*_rf*"
			display		`satList'
			
		* loop through each satelite folder in wave in country
			foreach 	sat of local satList {
		
			* define each file in the above local
				loc 		fileList : dir "$rootw/nigeria/`wave'/refined/`sat'" files "*_x3_rf*_n.dta"
				display		`fileList'
				
			* loop through each file
				foreach 	file in `fileList' {	
	
				* merge weather data with household data
					use 		"$rootw/nigeria/`wave'/refined/`sat'/`file'", clear
		
					drop 		sd_period_percent_raindays mean_period_percent_raindays ///
									sd_period_norain mean_period_norain sd_period_raindays ///
									mean_period_raindays sd_period_total_season ///
									mean_period_total_season
		
					reshape long mean_season_ median_season_ sd_season_ total_season_ ///
								skew_season_ norain_ raindays_ percent_raindays_ dry_ ///
								dev_total_season_  z_total_season_ dev_raindays_ ///
								dev_norain_ dev_percent_raindays_, i(hhid) j(year)
		
				* define file naming criteria
					loc 		sat = substr("`file'", 10, 3)
					loc 		ext = substr("`file'", 7, 2)
			
				* generate variable to record extraction method
					gen 		`sat'_`ext' = "`sat'_`ext'"
					lab var 	`sat'_`ext' "Satellite/Extraction"			
							
					display		"$rootw/nigeria/`wave'/refined/`sat'/`file'"
			
					save		"$export/nigeria/`file'", replace
				}						
			}	
		}


************************************************************************
**## 1.E - tanzania
************************************************************************

	* define local with all waves in it
		loc 		waveList : dir "$rootw/tanzania" dirs "wave_*"
		display 	`waveList'
		
	* loop through all wave folder in country folders	
		foreach 	wave of local waveList {
	
		* define local with all satelites in it
			loc 		satList : dir "$rootw/tanzania/`wave'/refined" dirs "*_rf*"
			display		`satList'
			
		* loop through each satelite folder in wave in country
			foreach 	sat of local satList {
		
			* define each file in the above local
				loc 		fileList : dir "$rootw/tanzania/`wave'/refined/`sat'" files "*_x3_rf*.dta"
				display		`fileList'
				
			* loop through each file
				foreach 	file in `fileList' {	
	
				* merge weather data with household data
					use 		"$rootw/tanzania/`wave'/refined/`sat'/`file'", clear
		
					drop 		sd_period_percent_raindays mean_period_percent_raindays ///
									sd_period_norain mean_period_norain sd_period_raindays ///
									mean_period_raindays sd_period_total_season ///
									mean_period_total_season
		
					reshape long mean_season_ median_season_ sd_season_ total_season_ ///
								skew_season_ norain_ raindays_ percent_raindays_ dry_ ///
								dev_total_season_  z_total_season_ dev_raindays_ ///
								dev_norain_ dev_percent_raindays_, i(*hhid) j(year)
		
				* define file naming criteria
					loc 		sat = substr("`file'", 10, 3)
					loc 		ext = substr("`file'", 7, 2)
			
				* generate variable to record extraction method
					gen 		`sat'_`ext' = "`sat'_`ext'"
					lab var 	`sat'_`ext' "Satellite/Extraction"			
							
					display		"$rootw/tanzania/`wave'/refined/`sat'/`file'"
			
					save		"$export/tanzania/`file'", replace
				}						
			}	
		}


************************************************************************
**## 1.F - uganda
************************************************************************

	* define local with all waves in it
		loc 		waveList : dir "$rootw/uganda" dirs "wave_*"
		display 	`waveList'
		
	* loop through all wave folder in country folders	
		foreach 	wave of local waveList {
	
		* define local with all satelites in it
			loc 		satList : dir "$rootw/uganda/`wave'/refined" dirs "*_rf*"
			display		`satList'
			
		* loop through each satelite folder in wave in country
			foreach 	sat of local satList {
		
			* define each file in the above local
				loc 		fileList : dir "$rootw/uganda/`wave'/refined/`sat'" files "*_x3_rf*_n.dta"
				display		`fileList'
				
			* loop through each file
				foreach 	file in `fileList' {	
	
				* merge weather data with household data
					use 		"$rootw/uganda/`wave'/refined/`sat'/`file'", clear
		
					drop 		sd_period_percent_raindays mean_period_percent_raindays ///
									sd_period_norain mean_period_norain sd_period_raindays ///
									mean_period_raindays sd_period_total_season ///
									mean_period_total_season
		
					reshape long mean_season_ median_season_ sd_season_ total_season_ ///
								skew_season_ norain_ raindays_ percent_raindays_ dry_ ///
								dev_total_season_  z_total_season_ dev_raindays_ ///
								dev_norain_ dev_percent_raindays_, i(hhid) j(year)
		
				* define file naming criteria
					loc 		sat = substr("`file'", 11, 3)
					loc 		ext = substr("`file'", 8, 2)
			
				* generate variable to record extraction method
					gen 		`sat'_`ext' = "`sat'_`ext'"
					lab var 	`sat'_`ext' "Satellite/Extraction"			
							
					display		"$rootw/uganda/`wave'/refined/`sat'/`file'"
			
					save		"$export/uganda/`file'", replace
				}						
			}	
		}


************************************************************************
**# 2 - ethiopia graphs
************************************************************************

* open first weather file
	use 		"$export/ethiopia/essy1_x3_rf1", clear

* define each file in the above local
	loc 		fileList : dir "$export/ethiopia" files "*_x3_rf*.dta"
	display		`fileList'
				
* loop through each file
	foreach 	file in `fileList' {	
	
	* merge weather data with household data
		append		using "$export/ethiopia/`file'"
				}	
				
* clean up data
	replace 	household_id = household_id2 if household_id == ""
	gen			sat = rf1_x3
	replace		sat = rf2_x3 if sat == ""
	replace		sat = rf3_x3 if sat == ""
	replace		sat = rf4_x3 if sat == ""
	replace		sat = rf5_x3 if sat == ""	
	replace		sat = rf6_x3 if sat == ""
	
	drop		rf1_x3 rf2_x3 rf3_x3 rf4_x3 rf5_x3 rf6_x3 household_id2
	order		sat, after(year)
	
	duplicates	drop
	drop if		household_id == "00000000000000"
	*** 2.14 million observations
	
	duplicates drop household_id year sat, force
	*** 1.9 million observations
	
	collapse 	(mean) mean_season_ median_season_ sd_season_ total_season_ ///
					skew_season_ norain_ raindays_ percent_raindays_ dry_ ///
					dev_total_season_ z_total_season_ dev_raindays_ ///
					dev_norain_ dev_percent_raindays_, by(year sat)
	*** 210 observations
	
	gen			sat1 = 1 if sat == "rf1_x3"
	replace		sat1 = 2 if sat == "rf2_x3"
	replace		sat1 = 3 if sat == "rf3_x3"
	replace		sat1 = 4 if sat == "rf4_x3"
	replace		sat1 = 5 if sat == "rf5_x3"
	replace		sat1 = 6 if sat == "rf6_x3"
	label 		define sat 1 "CHIRPS" 2 "CPC" 3 "MERRA-2" 4 "ARC2" 5 "ERA5" 6 "TAMSAT"
	label 		values sat1 sat
	drop		sat
	rename		sat1 sat
	order		sat, after(year)
	
************************************************************************
**## 2.1 - ethiopia mean daily rainfall
************************************************************************

	sort		year
	twoway 		(line mean_season_ year if sat == 1, lcolor(gray)) ///
				(line mean_season_ year if sat == 2, color(vermillion) ) ///
				(line mean_season_ year if sat == 3, color(sea)) ///
				(line mean_season_ year if sat == 4, color(turquoise)) ///
				(line mean_season_ year if sat == 5, color(reddish)) ///
				(line mean_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Ethiopia") ///
				ytitle("Mean Daily Rainfall (mm)") ylabel(0(1)15, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT")) saving("$sfig/eth_v01", replace)
			
	graph export 	"$xfig\eth_v01.png", width(1400) replace
	
	
************************************************************************
**## 2.2 - ethiopia median daily rainfall
************************************************************************

	sort		year
	twoway 		(line median_season_ year if sat == 1, lcolor(gray)) ///
				(line median_season_ year if sat == 2, color(vermillion) ) ///
				(line median_season_ year if sat == 3, color(sea)) ///
				(line median_season_ year if sat == 4, color(turquoise)) ///
				(line median_season_ year if sat == 5, color(reddish)) ///
				(line median_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Ethiopia") ///
				ytitle("Median Daily Rainfall (mm)") ylabel(0(1)10, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/eth_v02", replace)
			
	graph export 	"$xfig\eth_v02.png", width(1400) replace
	
************************************************************************
**## 2.3 - ethiopia variance daily rainfall
************************************************************************

	sort		year
	twoway 		(line sd_season_ year if sat == 1, lcolor(gray)) ///
				(line sd_season_ year if sat == 2, color(vermillion) ) ///
				(line sd_season_ year if sat == 3, color(sea)) ///
				(line sd_season_ year if sat == 4, color(turquoise)) ///
				(line sd_season_ year if sat == 5, color(reddish)) ///
				(line sd_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Ethiopia") ///
				ytitle("Variance of Daily Rainfall (mm)") ylabel(0(2)20, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/eth_v03", replace)
			
	graph export 	"$xfig\eth_v03.png", width(1400) replace
	
************************************************************************
**## 2.4 - ethiopia skew daily rainfall
************************************************************************

	sort		year
	twoway 		(line skew_season_ year if sat == 1, lcolor(gray)) ///
				(line skew_season_ year if sat == 2, color(vermillion) ) ///
				(line skew_season_ year if sat == 3, color(sea)) ///
				(line skew_season_ year if sat == 4, color(turquoise)) ///
				(line skew_season_ year if sat == 5, color(reddish)) ///
				(line skew_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Ethiopia") ///
				ytitle("Skew of Daily Rainfall (mm)") ylabel(0(0.05)0.75, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/eth_v04", replace)
			
	graph export 	"$xfig\eth_v04.png", width(1400) replace
	
************************************************************************
**## 2.5 - ethiopia total daily rainfall for the growing season
************************************************************************

	sort		year
	twoway 		(line total_season_ year if sat == 1, lcolor(gray)) ///
				(line total_season_ year if sat == 2, color(vermillion) ) ///
				(line total_season_ year if sat == 3, color(sea)) ///
				(line total_season_ year if sat == 4, color(turquoise)) ///
				(line total_season_ year if sat == 5, color(reddish)) ///
				(line total_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Ethiopia") ///
				ytitle("Total Daily Rainfall (mm)") ylabel(0(200)2000, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/eth_v05", replace)
			
	graph export 	"$xfig\eth_v05.png", width(1400) replace
	
************************************************************************
**## 2.6 - ethiopia deviations in total daily rainfall
************************************************************************

	sort		year
	twoway 		(line dev_total_season_ year if sat == 1, lcolor(gray)) ///
				(line dev_total_season_ year if sat == 2, color(vermillion) ) ///
				(line dev_total_season_ year if sat == 3, color(sea)) ///
				(line dev_total_season_ year if sat == 4, color(turquoise)) ///
				(line dev_total_season_ year if sat == 5, color(reddish)) ///
				(line dev_total_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Ethiopia") ///
				ytitle("Deviations in Total Daily Rainfall (mm)") ylabel(-500(100)750, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/eth_v06", replace)
			
	graph export 	"$xfig\eth_v06.png", width(1400) replace
	
************************************************************************
**## 2.7 - ethiopia scaled deviations in total daily rainfall
************************************************************************

	sort		year
	twoway 		(line z_total_season_ year if sat == 1, lcolor(gray)) ///
				(line z_total_season_ year if sat == 2, color(vermillion) ) ///
				(line z_total_season_ year if sat == 3, color(sea)) ///
				(line z_total_season_ year if sat == 4, color(turquoise)) ///
				(line z_total_season_ year if sat == 5, color(reddish)) ///
				(line z_total_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Ethiopia") ///
				ytitle("Scaled Deviations in Total Daily Rainfall (mm)") ylabel(-5(1)5, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/eth_v07", replace)
			
	graph export 	"$xfig\eth_v07.png", width(1400) replace
	
************************************************************************
**## 2.8 - ethiopia rainfall days
************************************************************************

	sort		year
	twoway 		(line raindays_ year if sat == 1, lcolor(gray)) ///
				(line raindays_ year if sat == 2, color(vermillion) ) ///
				(line raindays_ year if sat == 3, color(sea)) ///
				(line raindays_ year if sat == 4, color(turquoise)) ///
				(line raindays_ year if sat == 5, color(reddish)) ///
				(line raindays_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Ethiopia") ///
				ytitle("Rainfall Days") ylabel(0(30)300, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/eth_v08", replace)
			
	graph export 	"$xfig\eth_v08.png", width(1400) replace
	
************************************************************************
**## 2.9 - ethiopia deviations in rainfall days
************************************************************************

	sort		year
	twoway 		(line dev_raindays_ year if sat == 1, lcolor(gray)) ///
				(line dev_raindays_ year if sat == 2, color(vermillion) ) ///
				(line dev_raindays_ year if sat == 3, color(sea)) ///
				(line dev_raindays_ year if sat == 4, color(turquoise)) ///
				(line dev_raindays_ year if sat == 5, color(reddish)) ///
				(line dev_raindays_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Ethiopia") ///
				ytitle("Deviations in Rainfall Days") ylabel(-150(30)150, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/eth_v09", replace)
			
	graph export 	"$xfig\eth_v09.png", width(1400) replace
	
************************************************************************
**## 2.10 - ethiopia no rainfall days
************************************************************************

	sort		year
	twoway 		(line norain_ year if sat == 1, lcolor(gray)) ///
				(line norain_ year if sat == 2, color(vermillion) ) ///
				(line norain_ year if sat == 3, color(sea)) ///
				(line norain_ year if sat == 4, color(turquoise)) ///
				(line norain_ year if sat == 5, color(reddish)) ///
				(line norain_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Ethiopia") ///
				ytitle("No Rainfall Days") ylabel(0(30)300, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/eth_v10", replace)
			
	graph export 	"$xfig\eth_v10.png", width(1400) replace
	
************************************************************************
**## 2.11 - ethiopia deviations in no rainfall days
************************************************************************

	sort		year
	twoway 		(line dev_norain_ year if sat == 1, lcolor(gray)) ///
				(line dev_norain_ year if sat == 2, color(vermillion) ) ///
				(line dev_norain_ year if sat == 3, color(sea)) ///
				(line dev_norain_ year if sat == 4, color(turquoise)) ///
				(line dev_norain_ year if sat == 5, color(reddish)) ///
				(line dev_norain_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Ethiopia") ///
				ytitle("Deviations in No Rainfall Days") ylabel(-120(30)120, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/eth_v11", replace)
			
	graph export 	"$xfig\eth_v11.png", width(1400) replace
	
************************************************************************
**## 2.12 - ethiopia share of rainy days
************************************************************************

	sort		year
	twoway 		(line percent_raindays_ year if sat == 1, lcolor(gray)) ///
				(line percent_raindays_ year if sat == 2, color(vermillion) ) ///
				(line percent_raindays_ year if sat == 3, color(sea)) ///
				(line percent_raindays_ year if sat == 4, color(turquoise)) ///
				(line percent_raindays_ year if sat == 5, color(reddish)) ///
				(line percent_raindays_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Ethiopia") ///
				ytitle("Share of Rainy Days") ylabel(0(0.2)2, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/eth_v12", replace)
			
	graph export 	"$xfig\eth_v12.png", width(1400) replace
	
************************************************************************
**## 2.13 - ethiopia deviations in share of rainy days
************************************************************************

	sort		year
	twoway 		(line dev_percent_raindays_ year if sat == 1, lcolor(gray)) ///
				(line dev_percent_raindays_ year if sat == 2, color(vermillion) ) ///
				(line dev_percent_raindays_ year if sat == 3, color(sea)) ///
				(line dev_percent_raindays_ year if sat == 4, color(turquoise)) ///
				(line dev_percent_raindays_ year if sat == 5, color(reddish)) ///
				(line dev_percent_raindays_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Ethiopia") ///
				ytitle("Deviations in Share of Rainy Days") ylabel(-1(0.2)1, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/eth_v13", replace)
			
	graph export 	"$xfig\eth_v13.png", width(1400) replace
	
************************************************************************
**## 2.14 - ethiopia intra season dry spells
************************************************************************

	sort		year
	twoway 		(line dry_ year if sat == 1, lcolor(gray)) ///
				(line dry_ year if sat == 2, color(vermillion) ) ///
				(line dry_ year if sat == 3, color(sea)) ///
				(line dry_ year if sat == 4, color(turquoise)) ///
				(line dry_ year if sat == 5, color(reddish)) ///
				(line dry_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Ethiopia") ///
				ytitle("Intra-season Dry Spell") ylabel(0(5)75, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/eth_v14", replace)
			
	graph export 	"$xfig\eth_v14.png", width(1400) replace
	

************************************************************************
**# 3 - malawi graphs
************************************************************************

* open first weather file
	use 		"$export/malawi/ihps_x3_rf1", clear

* define each file in the above local
	loc 		fileList : dir "$export/malawi" files "*_x3_rf*.dta"
	display		`fileList'
				
* loop through each file
	foreach 	file in `fileList' {	
	
	* merge weather data with household data
		append		using "$export/malawi/`file'"
				}	
				
* clean up data
	replace 	y2_hhid = y3_hhid if y2_hhid == ""
	egen		hhid = group(y2_hhid)
	egen		hhid2 = group(case_id)
	replace		hhid = hhid2 if hhid == .
	drop		hhid2 y2_hhid case_id y3_hhid
	
	gen			sat = rf1_x3
	replace		sat = rf2_x3 if sat == ""
	replace		sat = rf3_x3 if sat == ""
	replace		sat = rf4_x3 if sat == ""
	replace		sat = rf5_x3 if sat == ""	
	replace		sat = rf6_x3 if sat == ""
	
	drop		rf1_x3 rf2_x3 rf3_x3 rf4_x3 rf5_x3 rf6_x3
	order		hhid
	order		sat, after(year)
	
	duplicates	drop
	*** 3.83 million observations
	
	duplicates drop hhid year sat, force
	*** 2.5 million observations
	
	collapse 	(mean) mean_season_ median_season_ sd_season_ total_season_ ///
					skew_season_ norain_ raindays_ percent_raindays_ dry_ ///
					dev_total_season_ z_total_season_ dev_raindays_ ///
					dev_norain_ dev_percent_raindays_, by(year sat)
	*** 204 observations
	
	gen			sat1 = 1 if sat == "rf1_x3"
	replace		sat1 = 2 if sat == "rf2_x3"
	replace		sat1 = 3 if sat == "rf3_x3"
	replace		sat1 = 4 if sat == "rf4_x3"
	replace		sat1 = 5 if sat == "rf5_x3"
	replace		sat1 = 6 if sat == "rf6_x3"
	label 		define sat 1 "CHIRPS" 2 "CPC" 3 "MERRA-2" 4 "ARC2" 5 "ERA5" 6 "TAMSAT"
	label 		values sat1 sat
	drop		sat
	rename		sat1 sat
	order		sat, after(year)	

	
************************************************************************
**## 3.1 - malawi mean daily rainfall
************************************************************************

	sort		year
	twoway 		(line mean_season_ year if sat == 1, lcolor(gray)) ///
				(line mean_season_ year if sat == 2, color(vermillion) ) ///
				(line mean_season_ year if sat == 3, color(sea)) ///
				(line mean_season_ year if sat == 4, color(turquoise)) ///
				(line mean_season_ year if sat == 5, color(reddish)) ///
				(line mean_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Malawi") ///
				ytitle("Mean Daily Rainfall (mm)") ylabel(0(1)15, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT")) saving("$sfig/mwi_v01", replace)
			
	graph export 	"$xfig\mwi_v01.png", width(1400) replace

************************************************************************
**## 3.2 - malawi median daily rainfall
************************************************************************

	sort		year
	twoway 		(line median_season_ year if sat == 1, lcolor(gray)) ///
				(line median_season_ year if sat == 2, color(vermillion) ) ///
				(line median_season_ year if sat == 3, color(sea)) ///
				(line median_season_ year if sat == 4, color(turquoise)) ///
				(line median_season_ year if sat == 5, color(reddish)) ///
				(line median_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Malawi") ///
				ytitle("Median Daily Rainfall (mm)") ylabel(0(1)10, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/mwi_v02", replace)
			
	graph export 	"$xfig\mwi_v02.png", width(1400) replace
	
************************************************************************
**## 3.3 - malawi variance daily rainfall
************************************************************************

	sort		year
	twoway 		(line sd_season_ year if sat == 1, lcolor(gray)) ///
				(line sd_season_ year if sat == 2, color(vermillion) ) ///
				(line sd_season_ year if sat == 3, color(sea)) ///
				(line sd_season_ year if sat == 4, color(turquoise)) ///
				(line sd_season_ year if sat == 5, color(reddish)) ///
				(line sd_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Malawi") ///
				ytitle("Variance of Daily Rainfall (mm)") ylabel(0(2)20, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/mwi_v03", replace)
			
	graph export 	"$xfig\mwi_v03.png", width(1400) replace
	
************************************************************************
**## 3.4 - malawi skew daily rainfall
************************************************************************

	sort		year
	twoway 		(line skew_season_ year if sat == 1, lcolor(gray)) ///
				(line skew_season_ year if sat == 2, color(vermillion) ) ///
				(line skew_season_ year if sat == 3, color(sea)) ///
				(line skew_season_ year if sat == 4, color(turquoise)) ///
				(line skew_season_ year if sat == 5, color(reddish)) ///
				(line skew_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Malawi") ///
				ytitle("Skew of Daily Rainfall (mm)") ylabel(0(0.05)0.75, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/mwi_v04", replace)
			
	graph export 	"$xfig\mwi_v04.png", width(1400) replace
	
************************************************************************
**## 3.5 - malawi total daily rainfall for the growing season
************************************************************************

	sort		year
	twoway 		(line total_season_ year if sat == 1, lcolor(gray)) ///
				(line total_season_ year if sat == 2, color(vermillion) ) ///
				(line total_season_ year if sat == 3, color(sea)) ///
				(line total_season_ year if sat == 4, color(turquoise)) ///
				(line total_season_ year if sat == 5, color(reddish)) ///
				(line total_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Malawi") ///
				ytitle("Total Daily Rainfall (mm)") ylabel(0(200)2000, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/mwi_v05", replace)
			
	graph export 	"$xfig\mwi_v05.png", width(1400) replace
	
************************************************************************
**## 3.6 - malawi deviations in total daily rainfall
************************************************************************

	sort		year
	twoway 		(line dev_total_season_ year if sat == 1, lcolor(gray)) ///
				(line dev_total_season_ year if sat == 2, color(vermillion) ) ///
				(line dev_total_season_ year if sat == 3, color(sea)) ///
				(line dev_total_season_ year if sat == 4, color(turquoise)) ///
				(line dev_total_season_ year if sat == 5, color(reddish)) ///
				(line dev_total_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Malawi") ///
				ytitle("Deviations in Total Daily Rainfall (mm)") ylabel(-500(100)750, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/mwi_v06", replace)
			
	graph export 	"$xfig\mwi_v06.png", width(1400) replace
	
************************************************************************
**## 3.7 - malawi scaled deviations in total daily rainfall
************************************************************************

	sort		year
	twoway 		(line z_total_season_ year if sat == 1, lcolor(gray)) ///
				(line z_total_season_ year if sat == 2, color(vermillion) ) ///
				(line z_total_season_ year if sat == 3, color(sea)) ///
				(line z_total_season_ year if sat == 4, color(turquoise)) ///
				(line z_total_season_ year if sat == 5, color(reddish)) ///
				(line z_total_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Malawi") ///
				ytitle("Scaled Deviations in Total Daily Rainfall (mm)") ylabel(-5(1)5, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/mwi_v07", replace)
			
	graph export 	"$xfig\mwi_v07.png", width(1400) replace
	
************************************************************************
**## 3.8 - malawi rainfall days
************************************************************************

	sort		year
	twoway 		(line raindays_ year if sat == 1, lcolor(gray)) ///
				(line raindays_ year if sat == 2, color(vermillion) ) ///
				(line raindays_ year if sat == 3, color(sea)) ///
				(line raindays_ year if sat == 4, color(turquoise)) ///
				(line raindays_ year if sat == 5, color(reddish)) ///
				(line raindays_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Malawi") ///
				ytitle("Rainfall Days") ylabel(0(30)300, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/mwi_v08", replace)
			
	graph export 	"$xfig\mwi_v08.png", width(1400) replace
	
************************************************************************
**## 3.9 - malawi deviations in rainfall days
************************************************************************

	sort		year
	twoway 		(line dev_raindays_ year if sat == 1, lcolor(gray)) ///
				(line dev_raindays_ year if sat == 2, color(vermillion) ) ///
				(line dev_raindays_ year if sat == 3, color(sea)) ///
				(line dev_raindays_ year if sat == 4, color(turquoise)) ///
				(line dev_raindays_ year if sat == 5, color(reddish)) ///
				(line dev_raindays_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Malawi") ///
				ytitle("Deviations in Rainfall Days") ylabel(-150(30)150, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/mwi_v09", replace)
			
	graph export 	"$xfig\mwi_v09.png", width(1400) replace
	
************************************************************************
**## 3.10 - malawi no rainfall days
************************************************************************

	sort		year
	twoway 		(line norain_ year if sat == 1, lcolor(gray)) ///
				(line norain_ year if sat == 2, color(vermillion) ) ///
				(line norain_ year if sat == 3, color(sea)) ///
				(line norain_ year if sat == 4, color(turquoise)) ///
				(line norain_ year if sat == 5, color(reddish)) ///
				(line norain_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Malawi") ///
				ytitle("No Rainfall Days") ylabel(0(30)300, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/mwi_v10", replace)
			
	graph export 	"$xfig\mwi_v10.png", width(1400) replace
	
************************************************************************
**## 3.11 - malawi deviations in no rainfall days
************************************************************************

	sort		year
	twoway 		(line dev_norain_ year if sat == 1, lcolor(gray)) ///
				(line dev_norain_ year if sat == 2, color(vermillion) ) ///
				(line dev_norain_ year if sat == 3, color(sea)) ///
				(line dev_norain_ year if sat == 4, color(turquoise)) ///
				(line dev_norain_ year if sat == 5, color(reddish)) ///
				(line dev_norain_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Malawi") ///
				ytitle("Deviations in No Rainfall Days") ylabel(-120(30)120, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/mwi_v11", replace)
			
	graph export 	"$xfig\mwi_v11.png", width(1400) replace
	
************************************************************************
**## 3.12 - malawi share of rainy days
************************************************************************

	sort		year
	twoway 		(line percent_raindays_ year if sat == 1, lcolor(gray)) ///
				(line percent_raindays_ year if sat == 2, color(vermillion) ) ///
				(line percent_raindays_ year if sat == 3, color(sea)) ///
				(line percent_raindays_ year if sat == 4, color(turquoise)) ///
				(line percent_raindays_ year if sat == 5, color(reddish)) ///
				(line percent_raindays_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Malawi") ///
				ytitle("Share of Rainy Days") ylabel(0(0.2)2, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/mwi_v12", replace)
			
	graph export 	"$xfig\mwi_v12.png", width(1400) replace
	
************************************************************************
**## 3.13 - malawi deviations in share of rainy days
************************************************************************

	sort		year
	twoway 		(line dev_percent_raindays_ year if sat == 1, lcolor(gray)) ///
				(line dev_percent_raindays_ year if sat == 2, color(vermillion) ) ///
				(line dev_percent_raindays_ year if sat == 3, color(sea)) ///
				(line dev_percent_raindays_ year if sat == 4, color(turquoise)) ///
				(line dev_percent_raindays_ year if sat == 5, color(reddish)) ///
				(line dev_percent_raindays_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Malawi") ///
				ytitle("Deviations in Share of Rainy Days") ylabel(-1(0.2)1, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/mwi_v13", replace)
			
	graph export 	"$xfig\mwi_v13.png", width(1400) replace
	
************************************************************************
**## 3.14 - malawi intra season dry spells
************************************************************************

	sort		year
	twoway 		(line dry_ year if sat == 1, lcolor(gray)) ///
				(line dry_ year if sat == 2, color(vermillion) ) ///
				(line dry_ year if sat == 3, color(sea)) ///
				(line dry_ year if sat == 4, color(turquoise)) ///
				(line dry_ year if sat == 5, color(reddish)) ///
				(line dry_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Malawi") ///
				ytitle("Intra-season Dry Spell") ylabel(0(5)75, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/mwi_v14", replace)
			
	graph export 	"$xfig\mwi_v14.png", width(1400) replace
	
************************************************************************
**# 4 - niger graphs
************************************************************************

* open first weather file
	use 		"$export/niger/ecvmay1_x3_rf1", clear

* define each file in the above local
	loc 		fileList : dir "$export/niger" files "*_x3_rf*.dta"
	display		`fileList'
				
* loop through each file
	foreach 	file in `fileList' {	
	
	* merge weather data with household data
		append		using "$export/niger/`file'"
				}	
				
* clean up data
	replace 	hid = hhid_y2 if hid == .
	drop		hhid_y2
	
	gen			sat = rf1_x3
	replace		sat = rf2_x3 if sat == ""
	replace		sat = rf3_x3 if sat == ""
	replace		sat = rf4_x3 if sat == ""
	replace		sat = rf5_x3 if sat == ""	
	replace		sat = rf6_x3 if sat == ""
	
	drop		rf1_x3 rf2_x3 rf3_x3 rf4_x3 rf5_x3 rf6_x3
	order		sat, after(year)
	
	duplicates	drop
	*** 1.64 million observations
	
	duplicates drop hid year sat, force
	*** 1.63 million observations
	
	collapse 	(mean) mean_season_ median_season_ sd_season_ total_season_ ///
					skew_season_ norain_ raindays_ percent_raindays_ dry_ ///
					dev_total_season_ z_total_season_ dev_raindays_ ///
					dev_norain_ dev_percent_raindays_, by(year sat)
	*** 210 observations
	
	gen			sat1 = 1 if sat == "rf1_x3"
	replace		sat1 = 2 if sat == "rf2_x3"
	replace		sat1 = 3 if sat == "rf3_x3"
	replace		sat1 = 4 if sat == "rf4_x3"
	replace		sat1 = 5 if sat == "rf5_x3"
	replace		sat1 = 6 if sat == "rf6_x3"
	label 		define sat 1 "CHIRPS" 2 "CPC" 3 "MERRA-2" 4 "ARC2" 5 "ERA5" 6 "TAMSAT"
	label 		values sat1 sat
	drop		sat
	rename		sat1 sat
	order		sat, after(year)	

************************************************************************
**## 4.1 - niger mean daily rainfall
************************************************************************

	sort		year
	twoway 		(line mean_season_ year if sat == 1, lcolor(gray)) ///
				(line mean_season_ year if sat == 2, color(vermillion) ) ///
				(line mean_season_ year if sat == 3, color(sea)) ///
				(line mean_season_ year if sat == 4, color(turquoise)) ///
				(line mean_season_ year if sat == 5, color(reddish)) ///
				(line mean_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Niger") ///
				ytitle("Mean Daily Rainfall (mm)") ylabel(0(1)15, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT")) saving("$sfig/ngr_v01", replace)
			
	graph export 	"$xfig\ngr_v01.png", width(1400) replace
	
************************************************************************
**## 4.2 - niger median daily rainfall
************************************************************************

	sort		year
	twoway 		(line median_season_ year if sat == 1, lcolor(gray)) ///
				(line median_season_ year if sat == 2, color(vermillion) ) ///
				(line median_season_ year if sat == 3, color(sea)) ///
				(line median_season_ year if sat == 4, color(turquoise)) ///
				(line median_season_ year if sat == 5, color(reddish)) ///
				(line median_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Niger") ///
				ytitle("Median Daily Rainfall (mm)") ylabel(0(1)10, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/ngr_v02", replace)
			
	graph export 	"$xfig\ngr_v02.png", width(1400) replace
	
************************************************************************
**## 4.3 - niger variance daily rainfall
************************************************************************

	sort		year
	twoway 		(line sd_season_ year if sat == 1, lcolor(gray)) ///
				(line sd_season_ year if sat == 2, color(vermillion) ) ///
				(line sd_season_ year if sat == 3, color(sea)) ///
				(line sd_season_ year if sat == 4, color(turquoise)) ///
				(line sd_season_ year if sat == 5, color(reddish)) ///
				(line sd_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Niger") ///
				ytitle("Variance of Daily Rainfall (mm)") ylabel(0(2)20, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/ngr_v03", replace)
			
	graph export 	"$xfig\ngr_v03.png", width(1400) replace
	
************************************************************************
**## 4.4 - niger skew daily rainfall
************************************************************************

	sort		year
	twoway 		(line skew_season_ year if sat == 1, lcolor(gray)) ///
				(line skew_season_ year if sat == 2, color(vermillion) ) ///
				(line skew_season_ year if sat == 3, color(sea)) ///
				(line skew_season_ year if sat == 4, color(turquoise)) ///
				(line skew_season_ year if sat == 5, color(reddish)) ///
				(line skew_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Niger") ///
				ytitle("Skew of Daily Rainfall (mm)") ylabel(0(0.05)0.75, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/ngr_v04", replace)
			
	graph export 	"$xfig\ngr_v04.png", width(1400) replace
	
************************************************************************
**## 4.5 - niger total daily rainfall for the growing season
************************************************************************

	sort		year
	twoway 		(line total_season_ year if sat == 1, lcolor(gray)) ///
				(line total_season_ year if sat == 2, color(vermillion) ) ///
				(line total_season_ year if sat == 3, color(sea)) ///
				(line total_season_ year if sat == 4, color(turquoise)) ///
				(line total_season_ year if sat == 5, color(reddish)) ///
				(line total_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Niger") ///
				ytitle("Total Daily Rainfall (mm)") ylabel(0(200)2000, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/ngr_v05", replace)
			
	graph export 	"$xfig\ngr_v05.png", width(1400) replace
	
************************************************************************
**## 4.6 - niger deviations in total daily rainfall
************************************************************************

	sort		year
	twoway 		(line dev_total_season_ year if sat == 1, lcolor(gray)) ///
				(line dev_total_season_ year if sat == 2, color(vermillion) ) ///
				(line dev_total_season_ year if sat == 3, color(sea)) ///
				(line dev_total_season_ year if sat == 4, color(turquoise)) ///
				(line dev_total_season_ year if sat == 5, color(reddish)) ///
				(line dev_total_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Niger") ///
				ytitle("Deviations in Total Daily Rainfall (mm)") ylabel(-500(100)750, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/ngr_v06", replace)
			
	graph export 	"$xfig\ngr_v06.png", width(1400) replace
	
************************************************************************
**## 4.7 - niger scaled deviations in total daily rainfall
************************************************************************

	sort		year
	twoway 		(line z_total_season_ year if sat == 1, lcolor(gray)) ///
				(line z_total_season_ year if sat == 2, color(vermillion) ) ///
				(line z_total_season_ year if sat == 3, color(sea)) ///
				(line z_total_season_ year if sat == 4, color(turquoise)) ///
				(line z_total_season_ year if sat == 5, color(reddish)) ///
				(line z_total_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Niger") ///
				ytitle("Scaled Deviations in Total Daily Rainfall (mm)") ylabel(-5(1)5, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/ngr_v07", replace)
			
	graph export 	"$xfig\ngr_v07.png", width(1400) replace
	
************************************************************************
**## 4.8 - niger rainfall days
************************************************************************

	sort		year
	twoway 		(line raindays_ year if sat == 1, lcolor(gray)) ///
				(line raindays_ year if sat == 2, color(vermillion) ) ///
				(line raindays_ year if sat == 3, color(sea)) ///
				(line raindays_ year if sat == 4, color(turquoise)) ///
				(line raindays_ year if sat == 5, color(reddish)) ///
				(line raindays_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Niger") ///
				ytitle("Rainfall Days") ylabel(0(30)300, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/ngr_v08", replace)
			
	graph export 	"$xfig\ngr_v08.png", width(1400) replace
	
************************************************************************
**## 4.9 - niger deviations in rainfall days
************************************************************************

	sort		year
	twoway 		(line dev_raindays_ year if sat == 1, lcolor(gray)) ///
				(line dev_raindays_ year if sat == 2, color(vermillion) ) ///
				(line dev_raindays_ year if sat == 3, color(sea)) ///
				(line dev_raindays_ year if sat == 4, color(turquoise)) ///
				(line dev_raindays_ year if sat == 5, color(reddish)) ///
				(line dev_raindays_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Niger") ///
				ytitle("Deviations in Rainfall Days") ylabel(-150(30)150, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/ngr_v09", replace)
			
	graph export 	"$xfig\ngr_v09.png", width(1400) replace
	
************************************************************************
**## 4.10 - niger no rainfall days
************************************************************************

	sort		year
	twoway 		(line norain_ year if sat == 1, lcolor(gray)) ///
				(line norain_ year if sat == 2, color(vermillion) ) ///
				(line norain_ year if sat == 3, color(sea)) ///
				(line norain_ year if sat == 4, color(turquoise)) ///
				(line norain_ year if sat == 5, color(reddish)) ///
				(line norain_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Niger") ///
				ytitle("No Rainfall Days") ylabel(0(30)300, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/ngr_v10", replace)
			
	graph export 	"$xfig\ngr_v10.png", width(1400) replace
	
************************************************************************
**## 4.11 - niger deviations in no rainfall days
************************************************************************

	sort		year
	twoway 		(line dev_norain_ year if sat == 1, lcolor(gray)) ///
				(line dev_norain_ year if sat == 2, color(vermillion) ) ///
				(line dev_norain_ year if sat == 3, color(sea)) ///
				(line dev_norain_ year if sat == 4, color(turquoise)) ///
				(line dev_norain_ year if sat == 5, color(reddish)) ///
				(line dev_norain_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Niger") ///
				ytitle("Deviations in No Rainfall Days") ylabel(-120(30)120, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/ngr_v11", replace)
			
	graph export 	"$xfig\ngr_v11.png", width(1400) replace
	
************************************************************************
**## 4.12 - niger share of rainy days
************************************************************************

	sort		year
	twoway 		(line percent_raindays_ year if sat == 1, lcolor(gray)) ///
				(line percent_raindays_ year if sat == 2, color(vermillion) ) ///
				(line percent_raindays_ year if sat == 3, color(sea)) ///
				(line percent_raindays_ year if sat == 4, color(turquoise)) ///
				(line percent_raindays_ year if sat == 5, color(reddish)) ///
				(line percent_raindays_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Malawi") ///
				ytitle("Share of Rainy Days") ylabel(0(0.2)2, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/ngr_v12", replace)
			
	graph export 	"$xfig\ngr_v12.png", width(1400) replace
	
************************************************************************
**## 4.13 - niger deviations in share of rainy days
************************************************************************

	sort		year
	twoway 		(line dev_percent_raindays_ year if sat == 1, lcolor(gray)) ///
				(line dev_percent_raindays_ year if sat == 2, color(vermillion) ) ///
				(line dev_percent_raindays_ year if sat == 3, color(sea)) ///
				(line dev_percent_raindays_ year if sat == 4, color(turquoise)) ///
				(line dev_percent_raindays_ year if sat == 5, color(reddish)) ///
				(line dev_percent_raindays_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Niger") ///
				ytitle("Deviations in Share of Rainy Days") ylabel(-1(0.2)1, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/ngr_v13", replace)
			
	graph export 	"$xfig\ngr_v13.png", width(1400) replace
	
************************************************************************
**## 4.14 - niger intra season dry spells
************************************************************************

	sort		year
	twoway 		(line dry_ year if sat == 1, lcolor(gray)) ///
				(line dry_ year if sat == 2, color(vermillion) ) ///
				(line dry_ year if sat == 3, color(sea)) ///
				(line dry_ year if sat == 4, color(turquoise)) ///
				(line dry_ year if sat == 5, color(reddish)) ///
				(line dry_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Niger") ///
				ytitle("Intra-season Dry Spell") ylabel(0(5)75, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/ngr_v14", replace)
			
	graph export 	"$xfig\ngr_v14.png", width(1400) replace
	
************************************************************************
**# 5 - nigeria graphs
************************************************************************

* open first weather file
	use 		"$export/nigeria/ghsy1_x3_rf1_n", clear

* define each file in the above local
	loc 		fileList : dir "$export/nigeria" files "*_x3_rf*.dta"
	display		`fileList'
				
* loop through each file
	foreach 	file in `fileList' {	
	
	* merge weather data with household data
		append		using "$export/nigeria/`file'"
				}	
				
* clean up data
	gen			sat = rf1_x3
	replace		sat = rf2_x3 if sat == ""
	replace		sat = rf3_x3 if sat == ""
	replace		sat = rf4_x3 if sat == ""
	replace		sat = rf5_x3 if sat == ""	
	replace		sat = rf6_x3 if sat == ""
	
	drop		rf1_x3 rf2_x3 rf3_x3 rf4_x3 rf5_x3 rf6_x3
	order		sat, after(year)
	
	duplicates	drop
	*** 2.08 million observations
	
	duplicates drop hhid year sat, force
	*** 1.11 million observations
	
	collapse 	(mean) mean_season_ median_season_ sd_season_ total_season_ ///
					skew_season_ norain_ raindays_ percent_raindays_ dry_ ///
					dev_total_season_ z_total_season_ dev_raindays_ ///
					dev_norain_ dev_percent_raindays_, by(year sat)
	*** 210 observations
	
	gen			sat1 = 1 if sat == "rf1_x3"
	replace		sat1 = 2 if sat == "rf2_x3"
	replace		sat1 = 3 if sat == "rf3_x3"
	replace		sat1 = 4 if sat == "rf4_x3"
	replace		sat1 = 5 if sat == "rf5_x3"
	replace		sat1 = 6 if sat == "rf6_x3"
	label 		define sat 1 "CHIRPS" 2 "CPC" 3 "MERRA-2" 4 "ARC2" 5 "ERA5" 6 "TAMSAT"
	label 		values sat1 sat
	drop		sat
	rename		sat1 sat
	order		sat, after(year)	

************************************************************************
**## 5.1 - nigeria mean daily rainfall
************************************************************************

	sort		year
	twoway 		(line mean_season_ year if sat == 1, lcolor(gray)) ///
				(line mean_season_ year if sat == 2, color(vermillion) ) ///
				(line mean_season_ year if sat == 3, color(sea)) ///
				(line mean_season_ year if sat == 4, color(turquoise)) ///
				(line mean_season_ year if sat == 5, color(reddish)) ///
				(line mean_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Nigeria") ///
				ytitle("Mean Daily Rainfall (mm)") ylabel(0(1)15, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT")) saving("$sfig/nga_v01", replace)
			
	graph export 	"$xfig\nga_v01.png", width(1400) replace
	
************************************************************************
**## 5.2 - nigeria median daily rainfall
************************************************************************

	sort		year
	twoway 		(line median_season_ year if sat == 1, lcolor(gray)) ///
				(line median_season_ year if sat == 2, color(vermillion) ) ///
				(line median_season_ year if sat == 3, color(sea)) ///
				(line median_season_ year if sat == 4, color(turquoise)) ///
				(line median_season_ year if sat == 5, color(reddish)) ///
				(line median_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Nigeria") ///
				ytitle("Median Daily Rainfall (mm)") ylabel(0(1)10, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/nga_v02", replace)
			
	graph export 	"$xfig\nga_v02.png", width(1400) replace
	
************************************************************************
**## 5.3 - nigeria variance daily rainfall
************************************************************************

	sort		year
	twoway 		(line sd_season_ year if sat == 1, lcolor(gray)) ///
				(line sd_season_ year if sat == 2, color(vermillion) ) ///
				(line sd_season_ year if sat == 3, color(sea)) ///
				(line sd_season_ year if sat == 4, color(turquoise)) ///
				(line sd_season_ year if sat == 5, color(reddish)) ///
				(line sd_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Nigeria") ///
				ytitle("Variance of Daily Rainfall (mm)") ylabel(0(2)20, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/nga_v03", replace)
			
	graph export 	"$xfig\nga_v03.png", width(1400) replace
	
************************************************************************
**## 5.4 - nigeria skew daily rainfall
************************************************************************

	sort		year
	twoway 		(line skew_season_ year if sat == 1, lcolor(gray)) ///
				(line skew_season_ year if sat == 2, color(vermillion) ) ///
				(line skew_season_ year if sat == 3, color(sea)) ///
				(line skew_season_ year if sat == 4, color(turquoise)) ///
				(line skew_season_ year if sat == 5, color(reddish)) ///
				(line skew_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Nigeria") ///
				ytitle("Skew of Daily Rainfall (mm)") ylabel(0(0.05)0.75, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/nga_v04", replace)
			
	graph export 	"$xfig\nga_v04.png", width(1400) replace
	
************************************************************************
**## 5.5 - nigeria total daily rainfall for the growing season
************************************************************************

	sort		year
	twoway 		(line total_season_ year if sat == 1, lcolor(gray)) ///
				(line total_season_ year if sat == 2, color(vermillion) ) ///
				(line total_season_ year if sat == 3, color(sea)) ///
				(line total_season_ year if sat == 4, color(turquoise)) ///
				(line total_season_ year if sat == 5, color(reddish)) ///
				(line total_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Nigeria") ///
				ytitle("Total Daily Rainfall (mm)") ylabel(0(200)2000, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/nga_v05", replace)
			
	graph export 	"$xfig\nga_v05.png", width(1400) replace
	
************************************************************************
**## 5.6 - nigeria deviations in total daily rainfall
************************************************************************

	sort		year
	twoway 		(line dev_total_season_ year if sat == 1, lcolor(gray)) ///
				(line dev_total_season_ year if sat == 2, color(vermillion) ) ///
				(line dev_total_season_ year if sat == 3, color(sea)) ///
				(line dev_total_season_ year if sat == 4, color(turquoise)) ///
				(line dev_total_season_ year if sat == 5, color(reddish)) ///
				(line dev_total_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Nigeria") ///
				ytitle("Deviations in Total Daily Rainfall (mm)") ylabel(-500(100)750, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/nga_v06", replace)
			
	graph export 	"$xfig\nga_v06.png", width(1400) replace
	
************************************************************************
**## 5.7 - nigeria scaled deviations in total daily rainfall
************************************************************************

	sort		year
	twoway 		(line z_total_season_ year if sat == 1, lcolor(gray)) ///
				(line z_total_season_ year if sat == 2, color(vermillion) ) ///
				(line z_total_season_ year if sat == 3, color(sea)) ///
				(line z_total_season_ year if sat == 4, color(turquoise)) ///
				(line z_total_season_ year if sat == 5, color(reddish)) ///
				(line z_total_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Nigeria") ///
				ytitle("Scaled Deviations in Total Daily Rainfall (mm)") ylabel(-5(1)5, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/nga_v07", replace)
			
	graph export 	"$xfig\nga_v07.png", width(1400) replace
	
************************************************************************
**## 5.8 - nigeria rainfall days
************************************************************************

	sort		year
	twoway 		(line raindays_ year if sat == 1, lcolor(gray)) ///
				(line raindays_ year if sat == 2, color(vermillion) ) ///
				(line raindays_ year if sat == 3, color(sea)) ///
				(line raindays_ year if sat == 4, color(turquoise)) ///
				(line raindays_ year if sat == 5, color(reddish)) ///
				(line raindays_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Nigeria") ///
				ytitle("Rainfall Days") ylabel(0(30)300, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/nga_v08", replace)
			
	graph export 	"$xfig\nga_v08.png", width(1400) replace
	
************************************************************************
**## 5.9 - nigeria deviations in rainfall days
************************************************************************

	sort		year
	twoway 		(line dev_raindays_ year if sat == 1, lcolor(gray)) ///
				(line dev_raindays_ year if sat == 2, color(vermillion) ) ///
				(line dev_raindays_ year if sat == 3, color(sea)) ///
				(line dev_raindays_ year if sat == 4, color(turquoise)) ///
				(line dev_raindays_ year if sat == 5, color(reddish)) ///
				(line dev_raindays_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Nigeria") ///
				ytitle("Deviations in Rainfall Days") ylabel(-150(30)150, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/nga_v09", replace)
			
	graph export 	"$xfig\nga_v09.png", width(1400) replace
	
************************************************************************
**## 5.10 - nigeria no rainfall days
************************************************************************

	sort		year
	twoway 		(line norain_ year if sat == 1, lcolor(gray)) ///
				(line norain_ year if sat == 2, color(vermillion) ) ///
				(line norain_ year if sat == 3, color(sea)) ///
				(line norain_ year if sat == 4, color(turquoise)) ///
				(line norain_ year if sat == 5, color(reddish)) ///
				(line norain_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Nigeria") ///
				ytitle("No Rainfall Days") ylabel(0(30)300, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/nga_v10", replace)
			
	graph export 	"$xfig\nga_v10.png", width(1400) replace
	
************************************************************************
**## 5.11 - nigeria deviations in no rainfall days
************************************************************************

	sort		year
	twoway 		(line dev_norain_ year if sat == 1, lcolor(gray)) ///
				(line dev_norain_ year if sat == 2, color(vermillion) ) ///
				(line dev_norain_ year if sat == 3, color(sea)) ///
				(line dev_norain_ year if sat == 4, color(turquoise)) ///
				(line dev_norain_ year if sat == 5, color(reddish)) ///
				(line dev_norain_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Nigeria") ///
				ytitle("Deviations in No Rainfall Days") ylabel(-120(30)120, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/nga_v11", replace)
			
	graph export 	"$xfig\nga_v11.png", width(1400) replace
	
************************************************************************
**## 5.12 - nigeria share of rainy days
************************************************************************

	sort		year
	twoway 		(line percent_raindays_ year if sat == 1, lcolor(gray)) ///
				(line percent_raindays_ year if sat == 2, color(vermillion) ) ///
				(line percent_raindays_ year if sat == 3, color(sea)) ///
				(line percent_raindays_ year if sat == 4, color(turquoise)) ///
				(line percent_raindays_ year if sat == 5, color(reddish)) ///
				(line percent_raindays_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Nigeria") ///
				ytitle("Share of Rainy Days") ylabel(0(0.2)2, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/nga_v12", replace)
			
	graph export 	"$xfig\nga_v12.png", width(1400) replace
	
************************************************************************
**## 5.13 - nigeria deviations in share of rainy days
************************************************************************

	sort		year
	twoway 		(line dev_percent_raindays_ year if sat == 1, lcolor(gray)) ///
				(line dev_percent_raindays_ year if sat == 2, color(vermillion) ) ///
				(line dev_percent_raindays_ year if sat == 3, color(sea)) ///
				(line dev_percent_raindays_ year if sat == 4, color(turquoise)) ///
				(line dev_percent_raindays_ year if sat == 5, color(reddish)) ///
				(line dev_percent_raindays_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Nigeria") ///
				ytitle("Deviations in Share of Rainy Days") ylabel(-1(0.2)1, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/nga_v13", replace)
			
	graph export 	"$xfig\nga_v13.png", width(1400) replace
	
************************************************************************
**## 5.14 - nigeria intra season dry spells
************************************************************************

	sort		year
	twoway 		(line dry_ year if sat == 1, lcolor(gray)) ///
				(line dry_ year if sat == 2, color(vermillion) ) ///
				(line dry_ year if sat == 3, color(sea)) ///
				(line dry_ year if sat == 4, color(turquoise)) ///
				(line dry_ year if sat == 5, color(reddish)) ///
				(line dry_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Nigeria") ///
				ytitle("Intra-season Dry Spell") ylabel(0(5)75, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/nga_v14", replace)
			
	graph export 	"$xfig\nga_v14.png", width(1400) replace
	
************************************************************************
**# 6 - tanzania graphs
************************************************************************

* open first weather file
	use 		"$export/tanzania/npsy1_x3_rf1", clear

* define each file in the above local
	loc 		fileList : dir "$export/tanzania" files "*_x3_rf*.dta"
	display		`fileList'
				
* loop through each file
	foreach 	file in `fileList' {	
	
	* merge weather data with household data
		append		using "$export/tanzania/`file'"
				}	
				
* clean up data
	replace 	hhid = y2_hhid if hhid == ""
	replace 	hhid = y3_hhid if hhid == ""
	replace 	hhid = y4_hhid if hhid == ""
	drop		y2_hhid y3_hhid y4_hhid
	
	gen			sat = rf1_x3
	replace		sat = rf2_x3 if sat == ""
	replace		sat = rf3_x3 if sat == ""
	replace		sat = rf4_x3 if sat == ""
	replace		sat = rf5_x3 if sat == ""	
	replace		sat = rf6_x3 if sat == ""
	
	drop		rf1_x3 rf2_x3 rf3_x3 rf4_x3 rf5_x3 rf6_x3
	order		sat, after(year)
	
	duplicates	drop
	*** 3.17 million observations
	
	duplicates drop hhid year sat, force
	*** 2.93 million observations
	
	collapse 	(mean) mean_season_ median_season_ sd_season_ total_season_ ///
					skew_season_ norain_ raindays_ percent_raindays_ dry_ ///
					dev_total_season_ z_total_season_ dev_raindays_ ///
					dev_norain_ dev_percent_raindays_, by(year sat)
	*** 204 observations
	
	gen			sat1 = 1 if sat == "rf1_x3"
	replace		sat1 = 2 if sat == "rf2_x3"
	replace		sat1 = 3 if sat == "rf3_x3"
	replace		sat1 = 4 if sat == "rf4_x3"
	replace		sat1 = 5 if sat == "rf5_x3"
	replace		sat1 = 6 if sat == "rf6_x3"
	label 		define sat 1 "CHIRPS" 2 "CPC" 3 "MERRA-2" 4 "ARC2" 5 "ERA5" 6 "TAMSAT"
	label 		values sat1 sat
	drop		sat
	rename		sat1 sat
	order		sat, after(year)	

************************************************************************
**## 6.1 - tanzania mean daily rainfall
************************************************************************

	sort		year
	twoway 		(line mean_season_ year if sat == 1, lcolor(gray)) ///
				(line mean_season_ year if sat == 2, color(vermillion) ) ///
				(line mean_season_ year if sat == 3, color(sea)) ///
				(line mean_season_ year if sat == 4, color(turquoise)) ///
				(line mean_season_ year if sat == 5, color(reddish)) ///
				(line mean_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Tanzania") ///
				ytitle("Mean Daily Rainfall (mm)") ylabel(0(1)10, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT")) saving("$sfig/tza_v01", replace)
			
	graph export 	"$xfig\tza_v01.png", width(1400) replace
	
************************************************************************
**## 6.2 - tanzania median daily rainfall
************************************************************************

	sort		year
	twoway 		(line median_season_ year if sat == 1, lcolor(gray)) ///
				(line median_season_ year if sat == 2, color(vermillion) ) ///
				(line median_season_ year if sat == 3, color(sea)) ///
				(line median_season_ year if sat == 4, color(turquoise)) ///
				(line median_season_ year if sat == 5, color(reddish)) ///
				(line median_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Tanzania") ///
				ytitle("Median Daily Rainfall (mm)") ylabel(0(1)10, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/tza_v02", replace)
			
	graph export 	"$xfig\tza_v02.png", width(1400) replace
	
************************************************************************
**## 6.3 - tanzania variance daily rainfall
************************************************************************

	sort		year
	twoway 		(line sd_season_ year if sat == 1, lcolor(gray)) ///
				(line sd_season_ year if sat == 2, color(vermillion) ) ///
				(line sd_season_ year if sat == 3, color(sea)) ///
				(line sd_season_ year if sat == 4, color(turquoise)) ///
				(line sd_season_ year if sat == 5, color(reddish)) ///
				(line sd_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Tanzania") ///
				ytitle("Variance of Daily Rainfall (mm)") ylabel(0(2)20, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/tza_v03", replace)
			
	graph export 	"$xfig\tza_v03.png", width(1400) replace
	
************************************************************************
**## 6.4 - tanzania skew daily rainfall
************************************************************************

	sort		year
	twoway 		(line skew_season_ year if sat == 1, lcolor(gray)) ///
				(line skew_season_ year if sat == 2, color(vermillion) ) ///
				(line skew_season_ year if sat == 3, color(sea)) ///
				(line skew_season_ year if sat == 4, color(turquoise)) ///
				(line skew_season_ year if sat == 5, color(reddish)) ///
				(line skew_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Tanzania") ///
				ytitle("Skew of Daily Rainfall (mm)") ylabel(0(0.05)0.75, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/tza_v04", replace)
			
	graph export 	"$xfig\tza_v04.png", width(1400) replace
	
************************************************************************
**## 6.5 - tanzania total daily rainfall for the growing season
************************************************************************

	sort		year
	twoway 		(line total_season_ year if sat == 1, lcolor(gray)) ///
				(line total_season_ year if sat == 2, color(vermillion) ) ///
				(line total_season_ year if sat == 3, color(sea)) ///
				(line total_season_ year if sat == 4, color(turquoise)) ///
				(line total_season_ year if sat == 5, color(reddish)) ///
				(line total_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Tanzania") ///
				ytitle("Total Daily Rainfall (mm)") ylabel(0(200)2000, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/tza_v05", replace)
			
	graph export 	"$xfig\tza_v05.png", width(1400) replace
	
************************************************************************
**## 6.6 - tanzania deviations in total daily rainfall
************************************************************************

	sort		year
	twoway 		(line dev_total_season_ year if sat == 1, lcolor(gray)) ///
				(line dev_total_season_ year if sat == 2, color(vermillion) ) ///
				(line dev_total_season_ year if sat == 3, color(sea)) ///
				(line dev_total_season_ year if sat == 4, color(turquoise)) ///
				(line dev_total_season_ year if sat == 5, color(reddish)) ///
				(line dev_total_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Tanzania") ///
				ytitle("Deviations in Total Daily Rainfall (mm)") ylabel(-500(100)750, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/tza_v06", replace)
			
	graph export 	"$xfig\tza_v06.png", width(1400) replace
	
************************************************************************
**## 6.7 - tanzania scaled deviations in total daily rainfall
************************************************************************

	sort		year
	twoway 		(line z_total_season_ year if sat == 1, lcolor(gray)) ///
				(line z_total_season_ year if sat == 2, color(vermillion) ) ///
				(line z_total_season_ year if sat == 3, color(sea)) ///
				(line z_total_season_ year if sat == 4, color(turquoise)) ///
				(line z_total_season_ year if sat == 5, color(reddish)) ///
				(line z_total_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Tanzania") ///
				ytitle("Scaled Deviations in Total Daily Rainfall (mm)") ylabel(-5(1)5, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/tza_v07", replace)
			
	graph export 	"$xfig\tza_v07.png", width(1400) replace
	
************************************************************************
**## 6.8 - tanzania rainfall days
************************************************************************

	sort		year
	twoway 		(line raindays_ year if sat == 1, lcolor(gray)) ///
				(line raindays_ year if sat == 2, color(vermillion) ) ///
				(line raindays_ year if sat == 3, color(sea)) ///
				(line raindays_ year if sat == 4, color(turquoise)) ///
				(line raindays_ year if sat == 5, color(reddish)) ///
				(line raindays_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Tanzania") ///
				ytitle("Rainfall Days") ylabel(0(30)300, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/tza_v08", replace)
			
	graph export 	"$xfig\tza_v08.png", width(1400) replace
	
************************************************************************
**## 6.9 - tanzania deviations in rainfall days
************************************************************************

	sort		year
	twoway 		(line dev_raindays_ year if sat == 1, lcolor(gray)) ///
				(line dev_raindays_ year if sat == 2, color(vermillion) ) ///
				(line dev_raindays_ year if sat == 3, color(sea)) ///
				(line dev_raindays_ year if sat == 4, color(turquoise)) ///
				(line dev_raindays_ year if sat == 5, color(reddish)) ///
				(line dev_raindays_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Tanzania") ///
				ytitle("Deviations in Rainfall Days") ylabel(-150(30)150, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/tza_v09", replace)
			
	graph export 	"$xfig\tza_v09.png", width(1400) replace
	
************************************************************************
**## 6.10 - tanzania no rainfall days
************************************************************************

	sort		year
	twoway 		(line norain_ year if sat == 1, lcolor(gray)) ///
				(line norain_ year if sat == 2, color(vermillion) ) ///
				(line norain_ year if sat == 3, color(sea)) ///
				(line norain_ year if sat == 4, color(turquoise)) ///
				(line norain_ year if sat == 5, color(reddish)) ///
				(line norain_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Tanzania") ///
				ytitle("No Rainfall Days") ylabel(0(30)300, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/tza_v10", replace)
			
	graph export 	"$xfig\tza_v10.png", width(1400) replace
	
************************************************************************
**## 6.11 - tanzania deviations in no rainfall days
************************************************************************

	sort		year
	twoway 		(line dev_norain_ year if sat == 1, lcolor(gray)) ///
				(line dev_norain_ year if sat == 2, color(vermillion) ) ///
				(line dev_norain_ year if sat == 3, color(sea)) ///
				(line dev_norain_ year if sat == 4, color(turquoise)) ///
				(line dev_norain_ year if sat == 5, color(reddish)) ///
				(line dev_norain_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Tanzania") ///
				ytitle("Deviations in No Rainfall Days") ylabel(-120(30)120, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/tza_v11", replace)
			
	graph export 	"$xfig\tza_v11.png", width(1400) replace
	
************************************************************************
**## 6.12 - tanzania share of rainy days
************************************************************************

	sort		year
	twoway 		(line percent_raindays_ year if sat == 1, lcolor(gray)) ///
				(line percent_raindays_ year if sat == 2, color(vermillion) ) ///
				(line percent_raindays_ year if sat == 3, color(sea)) ///
				(line percent_raindays_ year if sat == 4, color(turquoise)) ///
				(line percent_raindays_ year if sat == 5, color(reddish)) ///
				(line percent_raindays_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Tanzania") ///
				ytitle("Share of Rainy Days") ylabel(0(0.2)2, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/tza_v12", replace)
			
	graph export 	"$xfig\tza_v12.png", width(1400) replace
	
************************************************************************
**## 6.13 - tanzania deviations in share of rainy days
************************************************************************

	sort		year
	twoway 		(line dev_percent_raindays_ year if sat == 1, lcolor(gray)) ///
				(line dev_percent_raindays_ year if sat == 2, color(vermillion) ) ///
				(line dev_percent_raindays_ year if sat == 3, color(sea)) ///
				(line dev_percent_raindays_ year if sat == 4, color(turquoise)) ///
				(line dev_percent_raindays_ year if sat == 5, color(reddish)) ///
				(line dev_percent_raindays_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Tanzania") ///
				ytitle("Deviations in Share of Rainy Days") ylabel(-1(0.2)1, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/tza_v13", replace)
			
	graph export 	"$xfig\tza_v13.png", width(1400) replace
	
************************************************************************
**## 6.14 - tanzania intra season dry spells
************************************************************************

	sort		year
	twoway 		(line dry_ year if sat == 1, lcolor(gray)) ///
				(line dry_ year if sat == 2, color(vermillion) ) ///
				(line dry_ year if sat == 3, color(sea)) ///
				(line dry_ year if sat == 4, color(turquoise)) ///
				(line dry_ year if sat == 5, color(reddish)) ///
				(line dry_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Tanzania") ///
				ytitle("Intra-season Dry Spell") ylabel(0(5)75, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/tza_v14", replace)
			
	graph export 	"$xfig\tza_v14.png", width(1400) replace
			

************************************************************************
**# 7 - uganda graphs
************************************************************************

* open first weather file
	use 		"$export/uganda/unpsy1_x3_rf1_n", clear

* define each file in the above local
	loc 		fileList : dir "$export/uganda" files "*_x3_rf*.dta"
	display		`fileList'
				
* loop through each file
	foreach 	file in `fileList' {	
	
	* merge weather data with household data
		append		using "$export/uganda/`file'"
				}	
				
* clean up data
	gen			sat = rf1_x3
	replace		sat = rf2_x3 if sat == ""
	replace		sat = rf3_x3 if sat == ""
	replace		sat = rf4_x3 if sat == ""
	replace		sat = rf5_x3 if sat == ""	
	replace		sat = rf6_x3 if sat == ""
	
	drop		rf1_x3 rf2_x3 rf3_x3 rf4_x3 rf5_x3 rf6_x3
	order		sat, after(year)
	
	duplicates	drop
	*** 738955 observations
	
	duplicates drop hhid year sat, force
	*** 681,450 observations
	
	collapse 	(mean) mean_season_ median_season_ sd_season_ total_season_ ///
					skew_season_ norain_ raindays_ percent_raindays_ dry_ ///
					dev_total_season_ z_total_season_ dev_raindays_ ///
					dev_norain_ dev_percent_raindays_, by(year sat)
	*** 210 observations
	
	gen			sat1 = 1 if sat == "rf1_x3"
	replace		sat1 = 2 if sat == "rf2_x3"
	replace		sat1 = 3 if sat == "rf3_x3"
	replace		sat1 = 4 if sat == "rf4_x3"
	replace		sat1 = 5 if sat == "rf5_x3"
	replace		sat1 = 6 if sat == "rf6_x3"
	label 		define sat 1 "CHIRPS" 2 "CPC" 3 "MERRA-2" 4 "ARC2" 5 "ERA5" 6 "TAMSAT"
	label 		values sat1 sat
	drop		sat
	rename		sat1 sat
	order		sat, after(year)	

************************************************************************
**## 7.1 - uganda mean daily rainfall
************************************************************************

	sort		year
	twoway 		(line mean_season_ year if sat == 1, lcolor(gray)) ///
				(line mean_season_ year if sat == 2, color(vermillion) ) ///
				(line mean_season_ year if sat == 3, color(sea)) ///
				(line mean_season_ year if sat == 4, color(turquoise)) ///
				(line mean_season_ year if sat == 5, color(reddish)) ///
				(line mean_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Uganda") ///
				ytitle("Mean Daily Rainfall (mm)") ylabel(0(1)10, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT")) saving("$sfig/uga_v01", replace)
			
	graph export 	"$xfig\uga_v01.png", width(1400) replace
	
************************************************************************
**## 7.2 - uganda median daily rainfall
************************************************************************

	sort		year
	twoway 		(line median_season_ year if sat == 1, lcolor(gray)) ///
				(line median_season_ year if sat == 2, color(vermillion) ) ///
				(line median_season_ year if sat == 3, color(sea)) ///
				(line median_season_ year if sat == 4, color(turquoise)) ///
				(line median_season_ year if sat == 5, color(reddish)) ///
				(line median_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Uganda") ///
				ytitle("Median Daily Rainfall (mm)") ylabel(0(1)10, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/uga_v02", replace)
			
	graph export 	"$xfig\uga_v02.png", width(1400) replace
	
************************************************************************
**## 7.3 - uganda variance daily rainfall
************************************************************************

	sort		year
	twoway 		(line sd_season_ year if sat == 1, lcolor(gray)) ///
				(line sd_season_ year if sat == 2, color(vermillion) ) ///
				(line sd_season_ year if sat == 3, color(sea)) ///
				(line sd_season_ year if sat == 4, color(turquoise)) ///
				(line sd_season_ year if sat == 5, color(reddish)) ///
				(line sd_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Uganda") ///
				ytitle("Variance of Daily Rainfall (mm)") ylabel(0(2)20, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/uga_v03", replace)
			
	graph export 	"$xfig\uga_v03.png", width(1400) replace
	
************************************************************************
**## 7.4 - uganda skew daily rainfall
************************************************************************

	sort		year
	twoway 		(line skew_season_ year if sat == 1, lcolor(gray)) ///
				(line skew_season_ year if sat == 2, color(vermillion) ) ///
				(line skew_season_ year if sat == 3, color(sea)) ///
				(line skew_season_ year if sat == 4, color(turquoise)) ///
				(line skew_season_ year if sat == 5, color(reddish)) ///
				(line skew_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Uganda") ///
				ytitle("Skew of Daily Rainfall (mm)") ylabel(0(0.05)0.75, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/uga_v04", replace)
			
	graph export 	"$xfig\uga_v04.png", width(1400) replace
	
************************************************************************
**## 7.5 - uganda total daily rainfall for the growing season
************************************************************************

	sort		year
	twoway 		(line total_season_ year if sat == 1, lcolor(gray)) ///
				(line total_season_ year if sat == 2, color(vermillion) ) ///
				(line total_season_ year if sat == 3, color(sea)) ///
				(line total_season_ year if sat == 4, color(turquoise)) ///
				(line total_season_ year if sat == 5, color(reddish)) ///
				(line total_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Uganda") ///
				ytitle("Total Daily Rainfall (mm)") ylabel(0(200)2000, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/uga_v05", replace)
			
	graph export 	"$xfig\uga_v05.png", width(1400) replace
	
************************************************************************
**## 7.6 - uganda deviations in total daily rainfall
************************************************************************

	sort		year
	twoway 		(line dev_total_season_ year if sat == 1, lcolor(gray)) ///
				(line dev_total_season_ year if sat == 2, color(vermillion) ) ///
				(line dev_total_season_ year if sat == 3, color(sea)) ///
				(line dev_total_season_ year if sat == 4, color(turquoise)) ///
				(line dev_total_season_ year if sat == 5, color(reddish)) ///
				(line dev_total_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Uganda") ///
				ytitle("Deviations in Total Daily Rainfall (mm)") ylabel(-500(100)750, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/uga_v06", replace)
			
	graph export 	"$xfig\uga_v06.png", width(1400) replace
	
************************************************************************
**## 7.7 - uganda scaled deviations in total daily rainfall
************************************************************************

	sort		year
	twoway 		(line z_total_season_ year if sat == 1, lcolor(gray)) ///
				(line z_total_season_ year if sat == 2, color(vermillion) ) ///
				(line z_total_season_ year if sat == 3, color(sea)) ///
				(line z_total_season_ year if sat == 4, color(turquoise)) ///
				(line z_total_season_ year if sat == 5, color(reddish)) ///
				(line z_total_season_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Uganda") ///
				ytitle("Scaled Deviations in Total Daily Rainfall (mm)") ylabel(-5(1)5, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/uga_v07", replace)
			
	graph export 	"$xfig\uga_v07.png", width(1400) replace
	
************************************************************************
**## 7.8 - uganda rainfall days
************************************************************************

	sort		year
	twoway 		(line raindays_ year if sat == 1, lcolor(gray)) ///
				(line raindays_ year if sat == 2, color(vermillion) ) ///
				(line raindays_ year if sat == 3, color(sea)) ///
				(line raindays_ year if sat == 4, color(turquoise)) ///
				(line raindays_ year if sat == 5, color(reddish)) ///
				(line raindays_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Uganda") ///
				ytitle("Rainfall Days") ylabel(0(30)300, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/uga_v08", replace)
			
	graph export 	"$xfig\uga_v08.png", width(1400) replace
	
************************************************************************
**## 7.9 - uganda deviations in rainfall days
************************************************************************

	sort		year
	twoway 		(line dev_raindays_ year if sat == 1, lcolor(gray)) ///
				(line dev_raindays_ year if sat == 2, color(vermillion) ) ///
				(line dev_raindays_ year if sat == 3, color(sea)) ///
				(line dev_raindays_ year if sat == 4, color(turquoise)) ///
				(line dev_raindays_ year if sat == 5, color(reddish)) ///
				(line dev_raindays_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Uganda") ///
				ytitle("Deviations in Rainfall Days") ylabel(-150(30)150, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/uga_v09", replace)
			
	graph export 	"$xfig\uga_v09.png", width(1400) replace
	
************************************************************************
**## 7.10 - uganda no rainfall days
************************************************************************

	sort		year
	twoway 		(line norain_ year if sat == 1, lcolor(gray)) ///
				(line norain_ year if sat == 2, color(vermillion) ) ///
				(line norain_ year if sat == 3, color(sea)) ///
				(line norain_ year if sat == 4, color(turquoise)) ///
				(line norain_ year if sat == 5, color(reddish)) ///
				(line norain_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Uganda") ///
				ytitle("No Rainfall Days") ylabel(0(30)300, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/uga_v10", replace)
			
	graph export 	"$xfig\uga_v10.png", width(1400) replace
	
************************************************************************
**## 7.11 - uganda deviations in no rainfall days
************************************************************************

	sort		year
	twoway 		(line dev_norain_ year if sat == 1, lcolor(gray)) ///
				(line dev_norain_ year if sat == 2, color(vermillion) ) ///
				(line dev_norain_ year if sat == 3, color(sea)) ///
				(line dev_norain_ year if sat == 4, color(turquoise)) ///
				(line dev_norain_ year if sat == 5, color(reddish)) ///
				(line dev_norain_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Uganda") ///
				ytitle("Deviations in No Rainfall Days") ylabel(-120(30)120, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/uga_v11", replace)
			
	graph export 	"$xfig\uga_v11.png", width(1400) replace
	
************************************************************************
**## 7.12 - uganda share of rainy days
************************************************************************

	sort		year
	twoway 		(line percent_raindays_ year if sat == 1, lcolor(gray)) ///
				(line percent_raindays_ year if sat == 2, color(vermillion) ) ///
				(line percent_raindays_ year if sat == 3, color(sea)) ///
				(line percent_raindays_ year if sat == 4, color(turquoise)) ///
				(line percent_raindays_ year if sat == 5, color(reddish)) ///
				(line percent_raindays_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Uganda") ///
				ytitle("Share of Rainy Days") ylabel(0(0.2)2, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/uga_v12", replace)
			
	graph export 	"$xfig\uga_v12.png", width(1400) replace
	
************************************************************************
**## 7.13 - uganda deviations in share of rainy days
************************************************************************

	sort		year
	twoway 		(line dev_percent_raindays_ year if sat == 1, lcolor(gray)) ///
				(line dev_percent_raindays_ year if sat == 2, color(vermillion) ) ///
				(line dev_percent_raindays_ year if sat == 3, color(sea)) ///
				(line dev_percent_raindays_ year if sat == 4, color(turquoise)) ///
				(line dev_percent_raindays_ year if sat == 5, color(reddish)) ///
				(line dev_percent_raindays_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Uganda") ///
				ytitle("Deviations in Share of Rainy Days") ylabel(-1(0.2)1, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/uga_v13", replace)
			
	graph export 	"$xfig\uga_v13.png", width(1400) replace
	
************************************************************************
**## 7.14 - uganda intra season dry spells
************************************************************************

	sort		year
	twoway 		(line dry_ year if sat == 1, lcolor(gray)) ///
				(line dry_ year if sat == 2, color(vermillion) ) ///
				(line dry_ year if sat == 3, color(sea)) ///
				(line dry_ year if sat == 4, color(turquoise)) ///
				(line dry_ year if sat == 5, color(reddish)) ///
				(line dry_ year if sat == 6, color(ananas) ///
				xtitle("Year") xscale(r(1983(2)2017)) title("Uganda") ///
				ytitle("Intra-season Dry Spell") ylabel(0(5)75, nogrid ///
				labsize(small)) xlabel(1983(4)2017, nogrid labsize(small))), ///
				legend(pos(6) col(3) label(1 "CHIRPS") label(2 "CPC") ///
				label(3 "MERRA-2") label(4 "ARC2") label(5 "ERA5") ///
				label(6 "TAMSAT"))  saving("$sfig/uga_v14", replace)
			
	graph export 	"$xfig\uga_v14.png", width(1400) replace
							
	
************************************************************************
**# 8 - end matter, clean up to save
************************************************************************
	

* close the log
	log	close

/* END */