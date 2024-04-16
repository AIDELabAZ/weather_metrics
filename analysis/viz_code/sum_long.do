* Project: WB Weather
* Created on: Aug 2020
* Created by: mcg
* Stata v.16

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
								dev_total_season_ z_total_season_ dev_raindays_ ///
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
								dev_total_season_ z_total_season_ dev_raindays_ ///
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
								dev_total_season_ z_total_season_ dev_raindays_ ///
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
								dev_total_season_ z_total_season_ dev_raindays_ ///
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
								dev_total_season_ z_total_season_ dev_raindays_ ///
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
**# 2 - append data sets
************************************************************************

	
************************************************************************
**## 2.A - ethiopia
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
	
	sort		year
	twoway 		(line mean_season_ year if sat == "rf1_x3") ///
				(line mean_season_ year if sat == "rf2_x3") ///
				(line mean_season_ year if sat == "rf3_x3") ///
				(line mean_season_ year if sat == "rf4_x3") ///
				(line mean_season_ year if sat == "rf5_x3") ///
				(line mean_season_ year if sat == "rf6_x3") 
	
************************************************************************
**# 3 - end matter, clean up to save
************************************************************************
	
* prepare for export
	qui: compress
	summarize 
	sort household_id2
	
* save file
	customsave 	, idvar(household_id2) filename("essy3_merged.dta") ///
		path("`export'") dofile(ess3_build) user($user)
		
* close the log
	log	close

/* END */