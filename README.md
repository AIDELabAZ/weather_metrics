# Variable Selection in Economic Applications of Remotely Sensed Weather Data: Evidence from the LSMS-ISA

This repository contains code for replicating the statistical analysis in Agme, C., Josephson, A., Michler, J.D., Kilic, T., and Murray, S. (2024). "Variable Selection in Economic Applications of Remotely Sensed Weather Data: Evidence from the LSMS-ISA." *Unpublished*.

This README was last updated on 3 September 2024. 

 ## Index

 - [Project Team](#project-team)
 - [Data cleaning](#data-cleaning)
 - [Pre-requisites](#pre-requisites)
 - [Folder structure](#folder-structure)

## Project Team

Contributors:
* Jeffrey D. Michler [jdmichler@arizona.edu] (Conceptualizaiton, Analysis, Supervision, Visualization, Writing)
* Anna Josephson [aljosephson@arizona.edu] (Conceptualizaiton, Analysis, Supervision, Visualization, Writing)
* Talip Kilic (Conceptualization, Resources, Writing)
* Siobhan Murray (Conceptualization, Writing)
* Chandrakant Agme (Analysis, Visualization, Writing)
* Kieran Douglas (Analysis, Data curation)
* Brian McGreal (Data curation)
* Alison Conley (Data curation)
* Emil Kee-Tui (Data curation)
* Reece Branham (Data curation)
* Rodrigo Guerra Su (Data curation)
* Jacob Taylor (Data curation)

## Data cleaning

The code in this repository is primarily for replicating the cleaning of the household LSMS-ISA data. This requires downloading this repo and the household data from the World Bank webiste. The `projectdo.do` should then replicate the data cleaning process.

### Pre-requisites

#### Stata req's

  * The data processing and analysis requires a number of user-written Stata programs. From SSC:
    1. `blindschemes`
    3. `mdesc`
    4. `estout`
    5. `distinct`
    6. `winsor2`
    7. `unique`
    8. `palettes`
    9. `catplot`
    10. `colrspace`
    11. `carryforward`
    12. `missings`
    13. `coefplot`

From software author webpages
    1. `WeatherConfig`
    2. `xfill`

#### Folder structure

The [OSF project page][1] provides more details on the data cleaning.

For the household cleaning code to run, the public use microdata must be downloaded from the [World Bank Microdata Library][2]. Furthermore, the data needs to be placed in the following folder structure:<br>

```stata
weather_metric
├────household_data      
│    └──country          /* one dir for each country */
│       ├──wave          /* one dir for each wave */
│       └──logs
├──weather_data
│    └──country          /* one dir for each country */
│       ├──wave          /* one dir for each wave */
│       └──logs
├──merged_data
│    └──country          /* one dir for each country */
│       ├──wave          /* one dir for each wave */
│       └──logs
├──regression_data
│    ├──country          /* one dir for each country */
│    └──logs
└────results_data        /* overall analysis */
     ├─country          /* one dir for each country */
     ├──tables
     ├──figures
     └──logs
```

  [1]: https://osf.io/8hnz5/
  [2]: https://www.worldbank.org/en/programs/lsms/initiatives/lsms-ISA
  [3]: https://openknowledge.worldbank.org/handle/10986/36643
