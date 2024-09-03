* Project: WB Weather
* Created on: Aug 2020
* Created by: mcg
* Edited on: 7 June 2024
* Edited by: jdm
* Stata v.18

* does
	* merges weather data with Ethiopia ESS 5 data

* assumes
	* cleaned ESS 5 data
	* processed wave 5 weather data

* TO DO:
	* done

	
* **********************************************************************
* 0 - setup
* **********************************************************************

* define paths
	global		rootw 	= 	"$data/weather_data/ethiopia/wave_5/refined/essy5_up"
	global		rooth 	= 	"$data/household_data/ethiopia/wave_5/refined"
	global		export 	= 	"$data/merged_data/ethiopia/wave_5"
	global		logout 	= 	"$data/merged_data/ethiopia/logs"

* open log	
	cap log 	close 
	log 		using 		"$logout/ess5_build", append

	
* **********************************************************************
* 1 - merge rainfall data with household data
* **********************************************************************

* import the .dta houeshold file
	use 		"$rooth/hhfinal_ess5.dta", clear
	
* rename year 1 household id
	isid		household_id
	
* define each file in the above local
	loc 		fileList : dir "$rootw" files "*rf.dta"
	
* loop through each file in the above local
	foreach 	file in `fileList' {	
	
	* merge weather data with household data
		merge 	1:1 household_id using "$rootw/`file'"	
	
		* drop files that did not merge
			drop 	if 	_merge != 3
			drop 		_merge
		
		*drop variables for all years but 2021
			drop 		mean_season_1983- dry_2020
			drop 		mean_period_total_season- z_total_season_2020
			drop 		mean_period_raindays- dev_raindays_2020
			drop 		mean_period_norain- dev_norain_2020
			drop 		mean_period_percent_raindays- dev_percent_raindays_2020
		
		* define file naming criteria
			loc 		sat = substr("`file'", 7, 5)		
		
		* rename variables by dropping the year suffix
			gen 		v01_`sat' = mean_season_2021 if year == 2021
			lab var		v01_`sat' "Mean Daily Rainfall"
		
			gen 		v02_`sat' = median_season_2021 if year == 2021
			lab var		v02_`sat' "Median Daily Rainfall"

			gen 		v03_`sat' = sd_season_2021 if year == 2021
			lab var		v03_`sat' "Variance of Daily Rainfall"

			gen 		v04_`sat' = skew_season_2021 if year == 2021
			lab var		v04_`sat' "Skew of Daily Rainfall"

			gen 		v05_`sat' = total_season_2021 if year == 2021
			lab var		v05_`sat' "Total Rainfall"

			gen 		v06_`sat' = dev_total_season_2021 if year == 2021
			lab var		v06_`sat' "Deviation in Total Rainfalll"

			gen 		v07_`sat' = z_total_season_2021 if year == 2021
			lab var		v07_`sat' "Z-Score of Total Rainfall"	

			gen 		v08_`sat' = raindays_2021 if year == 2021
			lab var		v08_`sat' "Rainy Days"

			gen 		v09_`sat' = dev_raindays_2021 if year == 2021
			lab var		v09_`sat' "Deviation in Rainy Days"

			gen 		v10_`sat' = norain_2021 if year == 2021	
			lab var		v10_`sat' "No Rain Days"

			gen 		v11_`sat' = dev_norain_2021 if year == 2021
			lab var		v11_`sat' "Deviation in No Rain Days"

			gen 		v12_`sat' = percent_raindays_2021 if year == 2021
			lab var		v12_`sat' "% Rainy Days"

			gen 		v13_`sat' = dev_percent_raindays_2021 if year == 2021
			lab var		v13_`sat' "Deviation in % Rainy Days"

			gen 		v14_`sat' = dry_2021 if year == 2021
			lab var		v14_`sat' "Longest Dry Spell"
		
		* drop year variables
			drop 		*2021						
			
			display		"$rootw/`file'"				
}	


* **********************************************************************
* 2 - merge temperature data with household data
* **********************************************************************
	
* define each file in the above local
	loc 		fileList : dir "$rootw" files "*tp.dta"
	
* loop through each file in the above local
	foreach 	file in `fileList' {	
	
	* merge weather data with household data
		merge 	1:1 household_id using "$rootw/`file'"	
	
		* drop files that did not merge
			drop 	if 	_merge != 3
			drop 		_merge
		
		* drop variables for all years but 2021
			drop 		mean_season_1983- tempbin1002020
			drop 		mean_gdd- z_gdd_2020
		
		* define file naming criteria
			loc 		sat = substr("`file'", 7, 5)
		
		* rename variables but dropping the year suffix
			gen 		v15_`sat' = mean_season_2021 if year == 2021
			lab var		v15_`sat' "Mean Daily Temperature"

			gen 		v16_`sat' = median_season_2021 if year == 2021
			lab var		v16_`sat' "Median Daily Temperature"

			gen 		v17_`sat' = sd_season_2021 if year == 2021
			lab var		v17_`sat' "Variance of Daily Temperature"

			gen 		v18_`sat' = skew_season_2021 if year == 2021
			lab var		v18_`sat' "Skew of Daily Temperature"	

			gen 		v19_`sat' = gdd_2021 if year == 2021
			lab var		v19_`sat' "Growing Degree Days (GDD)"	

			gen 		v20_`sat' = dev_gdd_2021 if year == 2021
			lab var		v20_`sat' "Deviation in GDD"	

			gen 		v21_`sat' = z_gdd_2021 if year == 2021
			lab var		v21_`sat' "Z-Score of GDD"	

			gen 		v22_`sat' = max_season_2021 if year == 2021
			lab var		v22_`sat' "Maximum Daily Temperature"

			gen 		v23_`sat' = tempbin202021 if year == 2021
			lab var		v23_`sat' "Temperature Bin 0-20"	

			gen 		v24_`sat' = tempbin402021 if year == 2021
			lab var		v24_`sat' "Temperature Bin 20-40"	

			gen 		v25_`sat' = tempbin602021 if year == 2021
			lab var		v25_`sat' "Temperature Bin 40-60"	

			gen 		v26_`sat' = tempbin802021 if year == 2021
			lab var		v26_`sat' "Temperature Bin 60-80"	

			gen 		v27_`sat' = tempbin1002021 if year == 2021
			lab var		v27_`sat' "Temperature Bin 80-100"
		
		* drop year variables
			drop 		*2021		
			
			display		"$rootw/`file'"					
}


* **********************************************************************
* 3 - end matter, clean up to save
* **********************************************************************
	
* prepare for export
	qui: compress
	sort household_id
	
* save file
	save 				"$export/essy5_merged.dta", replace
		
* close the log
	log	close

/* END */