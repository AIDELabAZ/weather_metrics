* Project: WB Weather
* Created on: May 2020
* Created by: ek
* Edited on: 7 June 2024
* Edited by: jdm
* Stata v.18

* does
	* merges weather data into ngr household data

* assumes
	* cleaned Ngr household data
	* processed wave 2 weather data

* TO DO:
	* complete

	
* **********************************************************************
* 0 - setup
* **********************************************************************

* define paths
	loc		rootw 	= 	"$data/weather_data/niger/wave_2/refined/ecvmay2_up"
	loc		rooth 	= 	"$data/household_data/niger/wave_2/refined"
	loc		export 	= 	"$data/merged_data/niger/wave_2"
	loc		logout 	= 	"$data/merged_data/niger/logs"
	
* open log	
	cap 	log			 close
	log 	using 		"`logout'/ECVMA_2014_build", append
	
	
* **********************************************************************
* 1 - merge all household data with rainfall data
* **********************************************************************

* import the .dta houeshold file
	use 		"`rooth'/hhfinal_ecvma2.dta", clear
	
* generate variable to record data source
	gen 		data = "ecvmay2"
	lab var 	data "Data Source"

* define each file in the above local
	loc 		fileList : dir "`rootw'" files "*rf.dta"
	
* loop through each file in the above local
	foreach 	file in `fileList' {	
	
		* merge weather data with household data
			merge 	1:1 hhid_y2 using "`rootw'/`file'"	
	
		* drop files that did not merge
			drop 	if 	_merge != 3
			drop 		_merge
		
		*drop variables for all years but 2014
			drop 		mean_season_1983- dry_2013
			drop 		mean_period_total_season- z_total_season_2013
			drop 		mean_period_raindays- dev_raindays_2013
			drop 		mean_period_norain- dev_norain_2013
			drop 		mean_period_percent_raindays- dev_percent_raindays_2013
		
		* define file naming criteria
			loc 		sat = substr("`file'", 9, 5)		
		
		* rename variables by dropping the year suffix
			gen 		v01_`sat' = mean_season_2014 if year == 2014
			lab var		v01_`sat' "Mean Daily Rainfall"
		
			gen 		v02_`sat' = median_season_2014 if year == 2014
			lab var		v02_`sat' "Median Daily Rainfall"

			gen 		v03_`sat' = sd_season_2014 if year == 2014
			lab var		v03_`sat' "Variance of Daily Rainfall"

			gen 		v04_`sat' = skew_season_2014 if year == 2014
			lab var		v04_`sat' "Skew of Daily Rainfall"

			gen 		v05_`sat' = total_season_2014 if year == 2014
			lab var		v05_`sat' "Total Rainfall"

			gen 		v06_`sat' = dev_total_season_2014 if year == 2014
			lab var		v06_`sat' "Deviation in Total Rainfalll"

			gen 		v07_`sat' = z_total_season_2014 if year == 2014
			lab var		v07_`sat' "Z-Score of Total Rainfall"	

			gen 		v08_`sat' = raindays_2014 if year == 2014
			lab var		v08_`sat' "Rainy Days"

			gen 		v09_`sat' = dev_raindays_2014 if year == 2014
			lab var		v09_`sat' "Deviation in Rainy Days"

			gen 		v10_`sat' = norain_2014 if year == 2014	
			lab var		v10_`sat' "No Rain Days"

			gen 		v11_`sat' = dev_norain_2014 if year == 2014
			lab var		v11_`sat' "Deviation in No Rain Days"

			gen 		v12_`sat' = percent_raindays_2014 if year == 2014
			lab var		v12_`sat' "% Rainy Days"

			gen 		v13_`sat' = dev_percent_raindays_2014 if year == 2014
			lab var		v13_`sat' "Deviation in % Rainy Days"

			gen 		v14_`sat' = dry_2014 if year == 2014
			lab var		v14_`sat' "Longest Dry Spell"
		
		* drop year variables
			drop 		*2014
}

* **********************************************************************
* 2 - merge temperature data with household data
* **********************************************************************

* define each file in the above local
	loc 		fileList : dir "`rootw'" files "*tp.dta"
	
* loop through each file in the above local
	foreach 	file in `fileList' {	
	
	* merge weather data with household data
		merge 	1:1 hhid_y2 using "`rootw'/`file'"	
	
		* drop files that did not merge
			drop 	if 	_merge != 3
			drop 		_merge
		
		* drop variables for all years but 2014
			drop 		mean_season_1983- tempbin1002013
			drop 		mean_gdd- z_gdd_2013
		
		* define file naming criteria
			loc 		sat = substr("`file'", 9, 5)	
		
		* rename variables but dropping the year suffix
			gen 		v15_tp_`sat' = mean_season_2014 if year == 2014
			lab var		v15_tp_`sat' "Mean Daily Temperature"

			gen 		v16_tp_`sat' = median_season_2014 if year == 2014
			lab var		v16_tp_`sat' "Median Daily Temperature"

			gen 		v17_tp_`sat' = sd_season_2014 if year == 2014
			lab var		v17_tp_`sat' "Variance of Daily Temperature"

			gen 		v18_tp_`sat' = skew_season_2014 if year == 2014
			lab var		v18_tp_`sat' "Skew of Daily Temperature"	

			gen 		v19_tp_`sat' = gdd_2014 if year == 2014
			lab var		v19_tp_`sat' "Growing Degree Days (GDD)"	

			gen 		v20_tp_`sat' = dev_gdd_2014 if year == 2014
			lab var		v20_tp_`sat' "Deviation in GDD"	

			gen 		v21_tp_`sat' = z_gdd_2014 if year == 2014
			lab var		v21_tp_`sat' "Z-Score of GDD"	

			gen 		v22_tp_`sat' = max_season_2014 if year == 2014
			lab var		v22_tp_`sat' "Maximum Daily Temperature"

			gen 		v23_tp_`sat' = tempbin202014 if year == 2014
			lab var		v23_tp_`sat' "Temperature Bin 0-20"	

			gen 		v24_tp_`sat' = tempbin402014 if year == 2014
			lab var		v24_tp_`sat' "Temperature Bin 20-40"	

			gen 		v25_tp_`sat' = tempbin602014 if year == 2014
			lab var		v25_tp_`sat' "Temperature Bin 40-60"	

			gen 		v26_tp_`sat' = tempbin802014 if year == 2014
			lab var		v26_tp_`sat' "Temperature Bin 60-80"	

			gen 		v27_tp_`sat' = tempbin1002014 if year == 2014
			lab var		v27_tp_`sat' "Temperature Bin 80-100"
		
		* drop year variables
			drop 		*2014
}

* save file
	qui: compress
	summarize 
	
	save 			"`export'/ecvmay2_merged.dta", replace
	
* close the log
	log	close

/* END */