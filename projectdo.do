* Project: WB Weather - metric 
* Created on: Jan 2024
* Created by: cda
* Stata v.18.0

* does
	* establishes an identical workspace between users
	* sets globals that define absolute paths
	* serves as the starting point to find any do-file, dataset or output
	* runs all do-files needed for data work
	* loads any user written packages needed for analysis

* assumes
	* access to all data and code

* TO DO:
	* complete


* **********************************************************************
* 0 - setup
* **********************************************************************

* set $pack to 0 to skip package installation
	global 			pack 	0
		
* Specify Stata version in use
    global stataVersion 18.0    // set Stata version
    version $stataVersion

* **********************************************************************
* 0 (a) - Create user specific paths
* **********************************************************************

* Define root folder globals
if `"`c(username)'"' == "jdmichler" {
    global code "C:/Users/jdmichler/git/AIDELabAZ/weather_metrics"
    global data "C:/Users/jdmichler/OneDrive - University of Arizona/weather_and_agriculture"
	global email "jdmichler@arizona.edu"
	global driver "C:\Users\jdmichler\AppData\Local\Google\Chrome\chromedriver.exe"
}

if `"`c(username)'"' == "annal" {
    global code "C:/Users/aljosephson/git/weather_metrics"
    global data "C:/Users/aljosephson/OneDrive - University of Arizona/weather_and_agriculture"
}

if `"`c(username)'"' == "Chandrakant Agme" {
    global 		code  	"C:/Users/Chandrakant Agme/Documents/GitHub/weather_metrics"
	global 		data	"C:/Users/Chandrakant Agme/University of Arizona/Michler, Jeffrey David - (jdmichler) - weather_metrics"
	 }	
if `"`c(username)'"' == "kieran" {
    global 		code  	"/Users/kieran/Documents/GitHub/weather_metrics"
	global 		data	"/Users/kieran/Library/CloudStorage/OneDrive-UniversityofArizona/weather_and_agriculture"
	global 		email 	"kieran@arizona.edu"
	global 		driver 	"/Users/kieran/Documents/RANDOM/ChromeTesting/chromedriver"
	 }			
* **********************************************************************
* 0 (b) - Check if any required packages are installed:
* **********************************************************************

* install packages if global is set to 1
if $pack == 1 {
	
	* for packages/commands, make a local containing any required packages
    * temporarily set delimiter to ; so can break the line
    #delimit ;		
	loc userpack = "blindschemes mdesc estout distinct winsor2 unique 
                    palettes catplot colrspace carryforward missings 
                    coefplot" ;
    #delimit cr
	
	* install packages that are on ssc	
		foreach package in `userpack' {
			capture : which `package', all
			if (_rc) {
				capture window stopbox rusure "You are missing some packages." "Do you want to install `package'?"
				if _rc == 0 {
					capture ssc install `package', replace
					if (_rc) {
						window stopbox rusure `"This package is not on SSC. Do you want to proceed without it?"'
					}
				}
				else {
					exit 199
				}
			}
		}

	* install -xfill and dm89_1 - packages
		net install xfill, 	replace from(https://www.sealedenvelope.com/)
		
	* update all ado files
		ado update, update

	* set graph and Stata preferences
		set scheme plotplain, perm
		set more off
}

* **********************************************************************
* 1 - run weather data cleaning .do file
* **********************************************************************
