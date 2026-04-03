#!/bin/bash

RUNNING_ON_PI=false


if [ "$RUNNING_ON_PI" = true ]; then
    # PI specific section
    cd /home/pi/Scripts/Gribs

    export LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu:$LD_LIBRARY_PATH

    # The next line updates PATH for the Google Cloud SDK.
    if [ -f '/home/pi/google-cloud-sdk/path.bash.inc' ]; then . '/home/pi/google-cloud-sdk/path.bash.inc'; fi

    # The next line enables shell command completion for gcloud.
    if [ -f '/home/pi/google-cloud-sdk/completion.bash.inc' ]; then . '/home/pi/google-cloud-sdk/completion.bash.inc'; fi
fi



echo "Starting script"

# Download files from the KNMI OpenData API
python3 KNMI.py
rm -f ./extracted/HA43*
tar -xvf KNMIdownload.tar
echo "Extracted files from KNMIdownload.tar"
mv HA43* ./extracted/
echo "Moved files to ./extracted/"

grib_copy  -w indicatorOfParameter=33/34,level=10 ./extracted/HA43* KNMI43Wind.grib
grib_copy  -w indicatorOfParameter=11,level=2 ./extracted/HA43* KNMI43Temperature.grib
grib_copy  -w indicatorOfParameter=17 ./extracted/HA43* KNMI43DewPointTemp.grib
grib_copy  -w indicatorOfParameter=61 ./extracted/HA43* KNMI43Precipitation.grib  

#instead of simple copy, we need to reassign to mean sea level LevelType
grib_filter -o KNMI43Pressure.grib fix_pressure_filter.txt ./extracted/HA43*

grib_copy  -w indicatorOfParameter=52 ./extracted/HA43* KNMI43HumidityFraction.grib
#convert humidity fraction to percentage humidity
python3 ScaleFraction.py KNMI43HumidityFraction.grib KNMI43Humidity.grib

grib_copy  -w indicatorOfParameter=162 ./extracted/HA43* KNMI43GustU.grib  
grib_copy  -w indicatorOfParameter=163 ./extracted/HA43* KNMI43GustV.grib  
python3 CombineGusts.py KNMI43GustU.grib KNMI43GustV.grib KNMI43Gusts.grib

grib_copy  -w indicatorOfParameter=71 ./extracted/HA43* KNMI43CloudCoverRaw.grib  
grib_filter -o KNMI43CloudCoverFraction.grib fix_tcdc_filter.txt KNMI43CloudCoverRaw.grib
#this might be more efficient, but would need to be tuned and tested
#grib_filter -o KNMI43CloudCoverFraction.grib fix_tcdc_filter.txt ./extracted/HA43*
python3 ScaleFraction.py KNMI43CloudCoverFraction.grib KNMI43CloudCover.grib

echo "Written out all individual files, now combining them into one file"
grib_copy KNMI43Wind.grib KNMI43Temperature.grib KNMI43DewPointTemp.grib KNMI43Precipitation.grib KNMI43Pressure.grib KNMI43Humidity.grib KNMI43Gusts.grib KNMI43CloudCover.grib KNMI43-ModelArea-alltime-allparams.grib

cdo sellonlatbox,3,4.5,51.2,52 KNMI43-ModelArea-alltime-allparams.grib KNMI43-Zealand-alltime-allparams.grib   
cdo sellonlatbox,0,9,51,56 KNMI43-ModelArea-alltime-allparams.grib KNMI43-NorthSea-alltime-allparams.grib   
cdo sellonlatbox,0,2,49.3,51 KNMI43-ModelArea-alltime-allparams.grib KNMI43-Channel-alltime-allparams.grib   
cdo sellonlatbox,4.5,7.5,52.9,53.8 KNMI43-ModelArea-alltime-allparams.grib KNMI43-WaddenSea-alltime-allparams.grib   
cdo sellonlatbox,0,5,51,54 KNMI43-ModelArea-alltime-allparams.grib KNMI43-NorthSeaSouth-alltime-allparams.grib   
cdo sellonlatbox,5,5.9,52.2,53.1 KNMI43-ModelArea-alltime-allparams.grib KNMI43-LakeIJssel-alltime-allparams.grib   

grib_copy  -w P1=0/1/2/3/4/5/6/7/8/9/10/11/12/13/14/15/16/17/18/19/20/21/22/23/24/25/26/27/28/29/30 KNMI43-ModelArea-alltime-allparams.grib KNMI43-ModelArea-nextday-allparams.grib
grib_copy  -w P1=0/1/2/3/4/5/6/7/8/9/10/11/12/13/14/15/16/17/18/19/20/21/22/23/24/25/26/27/28/29/30 KNMI43-Zealand-alltime-allparams.grib KNMI43-Zealand-nextday-allparams.grib
grib_copy  -w P1=0/1/2/3/4/5/6/7/8/9/10/11/12/13/14/15/16/17/18/19/20/21/22/23/24/25/26/27/28/29/30 KNMI43-NorthSea-alltime-allparams.grib KNMI43-NorthSea-nextday-allparams.grib
grib_copy  -w P1=0/1/2/3/4/5/6/7/8/9/10/11/12/13/14/15/16/17/18/19/20/21/22/23/24/25/26/27/28/29/30 KNMI43-Channel-alltime-allparams.grib KNMI43-Channel-nextday-allparams.grib
grib_copy  -w P1=0/1/2/3/4/5/6/7/8/9/10/11/12/13/14/15/16/17/18/19/20/21/22/23/24/25/26/27/28/29/30 KNMI43-WaddenSea-alltime-allparams.grib KNMI43-WaddenSea-nextday-allparams.grib
grib_copy  -w P1=0/1/2/3/4/5/6/7/8/9/10/11/12/13/14/15/16/17/18/19/20/21/22/23/24/25/26/27/28/29/30 KNMI43-NorthSeaSouth-alltime-allparams.grib KNMI43-NorthSeaSouth-nextday-allparams.grib
grib_copy  -w P1=0/1/2/3/4/5/6/7/8/9/10/11/12/13/14/15/16/17/18/19/20/21/22/23/24/25/26/27/28/29/30 KNMI43-LakeIJssel-alltime-allparams.grib KNMI43-LakeIJssel-nextday-allparams.grib

grib_copy  -w indicatorOfParameter=33/34,level=10 KNMI43-ModelArea-alltime-allparams.grib KNMI43-ModelArea-alltime-windonly.grib
grib_copy  -w indicatorOfParameter=33/34,level=10 KNMI43-Zealand-alltime-allparams.grib KNMI43-Zealand-alltime-windonly.grib
grib_copy  -w indicatorOfParameter=33/34,level=10 KNMI43-NorthSea-alltime-allparams.grib KNMI43-NorthSea-alltime-windonly.grib
grib_copy  -w indicatorOfParameter=33/34,level=10 KNMI43-Channel-alltime-allparams.grib KNMI43-Channel-alltime-windonly.grib
grib_copy  -w indicatorOfParameter=33/34,level=10 KNMI43-WaddenSea-alltime-allparams.grib KNMI43-WaddenSea-alltime-windonly.grib
grib_copy  -w indicatorOfParameter=33/34,level=10 KNMI43-NorthSeaSouth-alltime-allparams.grib KNMI43-NorthSeaSouth-alltime-windonly.grib
grib_copy  -w indicatorOfParameter=33/34,level=10 KNMI43-LakeIJssel-alltime-allparams.grib KNMI43-LakeIJssel-alltime-windonly.grib

grib_copy  -w P1=0/1/2/3/4/5/6/7/8/9/10/11/12/13/14/15/16/17/18/19/20/21/22/23/24/25/26/27/28/29/30 KNMI43-ModelArea-alltime-windonly.grib KNMI43-ModelArea-nextday-windonly.grib
grib_copy  -w P1=0/1/2/3/4/5/6/7/8/9/10/11/12/13/14/15/16/17/18/19/20/21/22/23/24/25/26/27/28/29/30 KNMI43-Zealand-alltime-windonly.grib KNMI43-Zealand-nextday-windonly.grib
grib_copy  -w P1=0/1/2/3/4/5/6/7/8/9/10/11/12/13/14/15/16/17/18/19/20/21/22/23/24/25/26/27/28/29/30 KNMI43-NorthSea-alltime-windonly.grib KNMI43-NorthSea-nextday-windonly.grib
grib_copy  -w P1=0/1/2/3/4/5/6/7/8/9/10/11/12/13/14/15/16/17/18/19/20/21/22/23/24/25/26/27/28/29/30 KNMI43-Channel-alltime-windonly.grib KNMI43-Channel-nextday-windonly.grib
grib_copy  -w P1=0/1/2/3/4/5/6/7/8/9/10/11/12/13/14/15/16/17/18/19/20/21/22/23/24/25/26/27/28/29/30 KNMI43-WaddenSea-alltime-windonly.grib KNMI43-WaddenSea-nextday-windonly.grib
grib_copy  -w P1=0/1/2/3/4/5/6/7/8/9/10/11/12/13/14/15/16/17/18/19/20/21/22/23/24/25/26/27/28/29/30 KNMI43-NorthSeaSouth-alltime-windonly.grib KNMI43-NorthSeaSouth-nextday-windonly.grib
grib_copy  -w P1=0/1/2/3/4/5/6/7/8/9/10/11/12/13/14/15/16/17/18/19/20/21/22/23/24/25/26/27/28/29/30 KNMI43-LakeIJssel-alltime-windonly.grib KNMI43-LakeIJssel-nextday-windonly.grib

mv KNMI43-* ./downloads/

#upload to Google Storage, as backend of website www.weatherfiles.com
echo "Uploading grib files to Google Storage"
gsutil -m cp ./downloads/KNMI43-*.grib gs://weatherfiles.com
echo "Upload complete"
