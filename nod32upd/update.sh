#!/bin/bash

## @author    Samoylov Nikolay
## @project   NOD32 Update Script
## @copyright 2015 <github.com/tarampampam>
## @license   MIT <http://opensource.org/licenses/MIT>
## @github    https://github.com/tarampampam/nod32-update-mirror/
## @version   Look in 'settings.cfg'
##
## @depends   curl, wget, grep, sed, cut, cat, basename, 
##            unrar (if use official mirrors)

# *****************************************************************************
# ***                               Config                                   **
# *****************************************************************************

## Path to settings file
PathToSettingsFile=$(dirname $0)'/settings.cfg';

# *****************************************************************************
# ***                            END Config                                  **
# *****************************************************************************

## Load setting from file
if [ -f "$PathToSettingsFile" ]; then source $PathToSettingsFile; else
  echo -e "\e[1;31mCannot load settings ('$PathToSettingsFile') file. Exit\e[0m"; exit 1;
fi;

## Init global variables
WORKURL=''; USERNAME=''; PASSWD='';

## запомним начало запуска скрипта 
timeStartUpdate=$(date +%s);

## Helpers Functions ##########################################################

## Show log message in console
logmessage() {
  ## $1 = (not required) '-n' flag for echo output
  ## $2 = message to output
  [[ "$quiet" == true ]] && return 1;
  local mytime=[$(date +%H:%M:%S)];
  local flag='-e';
  local outtext='';
  if [[ "$1" == '-'* ]]; then 
    outtext=$2;
    [[ "$1" == *t* ]] && mytime='';
    [[ "$1" == *n* ]] && flag='-e -n';
      #local i;
      #for ((i=0; $i<${#1}; i=$(($i+1)))); do
      #  local char=${1:$i:1};
      #  case $char in
      #    t) mytime='';;
      #    n) flag=$flag''$char;;
      #  esac;  
      #done;
  else 
    outtext=$1;
  fi;
  echo $flag $mytime "$outtext";
}

## Write log file (if filename setted)
writeLog() {
  if [ ! -z "$LOGFILE" ]; then
    echo "[$(date +%Y-%m-%d/%H:%M:%S)] [$(basename $0)] - $1" >> "$LOGFILE";
  fi;
}

checkAvailability() {
  ## $1 = (not required) '-n' flag for echo output
  ## $2 = URL for checking (with slash at the and)

  flag=''; URL='';
  if [ "$1" == "-n" ]; then
    flag="-n "; URL=$2;
  else
    URL=$1;
  fi;

  headers=$(curl -A "$USERAGENT" --user $USERNAME:$PASSWD -Is $URL'update.ver');
  if [ "$(echo \"$headers\" | head -n 1 | cut -d' ' -f 2)" == '200' ]
  then
    logmessage -t $flag "${cGreen}Available${cNone}";
    return 0;
  else
    logmessage -t $flag "${cRed}Failed${cNone}";
    return 1;
  fi;
}

downloadFile() {
  ## $1 = (not required) '-n' flag for echo output
  ## $2 = URL to download
  ## $3 = save to file PATH

  flag=''; url=''; saveto='';
  if [ "$1" == "-n" ]; then
    flag="-n "; url=$2; saveto=$3;
  else
    url=$1; saveto=$2;
  fi;

  if [ -z "$wgetDelay" ]; then
    wgetDelay='0';
  fi;

  if [ -z "$wgetLimitSpeed" ]; then
    wgetLimitSpeed='102400k';
  fi;

  ## wget manual <http://www.gnu.org/software/wget/manual/wget.html>
  ##
  ## --cache=off    When set to off, disable server-side cache
  ## --timestamping Only those new files will be downloaded in the place
  ##                of the old ones.
  ## -v -d          Verbose and Debud output
  ## -U             Identify as agent-string to the HTTP server
  ## --limit-rate   Limit the download speed to amount bytes per second
  ## -e robots=off
  ## -w             Wait the specified number of seconds between the
  ##                retrievals
  ## --random-wait  This option causes the time between requests to vary
  ##                between 0 and 2 * wait seconds
  ## -P             Path to save file (dir)

  ## Save wget output to vareable and..
  wgetResult=$(wget \
    --cache=off \
    --timestamping \
    -v -d \
    -U "$USERAGENT" \
    --http-user="$USERNAME" \
    --http-password="$PASSWD" \
    --limit-rate=$wgetLimitSpeed \
    -e robots=off \
    -w $wgetDelay \
    --random-wait \
    -P $saveto \
    $url 2>&1);

  ## ..if we found string 'not retrieving' - download skipped..
  if [[ $wgetResult == *not\ retrieving* ]]; then
    logmessage -t $flag "${cYel}Skipped${cNone}";
    return 1;
  fi;

  ## ..also - if we found 'saved' string - download was executed..
  if [[ $wgetResult == *saved* ]]; then
    logmessage -t $flag "${cGreen}Complete${cNone}";
    return 0;
  fi;

  ## ..or resource not found
  if [[ $wgetResult == *ERROR\ \4\0\4* ]]; then
    logmessage -t $flag "${cRed}Not found${cNone}";
    return 2;
  fi;

  ## if no one substring founded - maybe error?
  logmessage -t $flag "${cRed}Error =(${cNone}\nWget debug info: \
    \n\n${cYel}$wgetResult${cNone}\n\n";
  return 3;
}

## Parse data from passed content of ini section
getValueFromINI() {
  local sourceData=$1; local paramName=$2;
  ## 1. Get value "platform=%OUR_VALUE%"
  ## 2. Remove illegal characters
  #echo $(echo "$sourceData" | sed -n '/^'$paramName'=\(.*\)$/s//\1/p' | tr -d "\r" | tr -d "\n");
  echo $(echo "$sourceData" | grep "^$paramName=" | sed s/$paramName=//);
}

## Create some directory
createDir() {
  local dirPath=$1;
  if [ ! -d $dirPath ]; then
    logmessage -n "Create $dirPath.. "; mkdir -p $dirPath >/dev/null 2>&1;
    if [ -d "$dirPath" ]; then
      logmessage -t $msgOk; else logmessage -t $msgErr;
    fi;
  fi;
}

## Remove some directory
removeDir() {
  local dirPath=$1;
  if [ -d $dirPath ]; then
    logmessage -n "Remove $dirPath.. "; rm -R -f $dirPath >/dev/null 2>&1;
    if [ ! -d "$dirPath" ]; then
      logmessage -t $msgOk; else logmessage -t $msgErr;
    fi;
  fi;
}

## Download update.ver from $1 and unzip to $2
function downloadSource() { 
  local sourceUrl=$1;
  local saveToPath=$2;
  
  ## Path to DOWNLOADED 'update.ver' file
  local mainVerFile=$pathToTempDir'update.ver';
  ## Path to RESULT 'update.ver' file
  local newVerFile=$mainVerFile'.new';

  ## Download source 'update.ver' file
  logmessage -n "Downloading $sourceUrl""update.ver.. ";
  downloadFile $sourceUrl'update.ver' $pathToTempDir;
  if [ ! -f $mainVerFile ]; then
    logmessage "${cRed}$mainVerFile after download not exists, stopping${cNone}";
    writeLog "Download \"$sourceUrl""update.ver\" failed";
    return 1;
  fi;

  ## Delete old file, if exists
  if [ -f $newVerFile ]; then rm -f $newVerFile; fi;

  ## Check - 'update.ver' packed with RAR or not?
  ## Get first 3 chars if file..
  fileHeader=$(head -c 3 $mainVerFile);
  ## ..and compare with template
  if [ "$fileHeader" == "Rar" ]; then
    ## Check - installed 'unrar' or not
    if [[ ! -n $(type -P unrar) ]]; then
      logmessage "${cRed}$mainVerFile packed by RAR, but i cannot find 'unrar' in your system :(, exit${cNone}"
      writeLog "Unpacking .ver file error (unrar not exists)";
      exit 1;
    else
      mv $pathToTempDir'update.ver' $pathToTempDir'update.rar';
      logmessage -n "Unpacking update.ver.. ";
      ## Make unpack (without 'cd' not working O_o)
      cd $pathToTempDir; unrar x -y -inul 'update.rar' $pathToTempDir;
      if [ -f $pathToTempDir'update.ver' ]; then
        logmessage -t $msgOk;
        isOfficialUpdate=true;
        rm -f 'update.rar';
      else
        logmessage -t "${cRed}Error while unpacking update.ver file, exit${cNone}";
        writeLog "Unpacking .ver file error (operation failed)";
        exit 1;
      fi;
    fi;
  fi;
}
## Here we go! ################################################################

echo "  _  _         _ _______   __  __ _";
echo " | \| |___  __| |__ /_  ) |  \/  (_)_ _ _ _ ___ _ _";
echo " | .' / _ \/ _' ||_ \/ /  | |\/| | | '_| '_/ _ \ '_|";
echo " |_|\_\___/\__,_|___/___| |_|  |_|_|_| |_| \___/_|  //j.mp/GitNod32Mirror";
echo "";
echo -e " ${cYel}Hint${cNone}: If you want quit from \
'parsing & writing new update.ver file' or \n quit from 'Download files' - press 'q'; \
${cGray}for more options use '${cYel}--help ${cGray}'or '${cYel}-h${cGray}'${cNone}";
echo ;

## Run script with params #####################################################

## render all script param with recursion
handleParam(){
  ## $* - all incoming params of script
  local opt;
  for opt in $*; do
    ## render keys with -- and ''
    #echo -e "${cYel}[$*]${cNone}\nopt='$opt'";
    if [ $(echo $opt | grep ^\-\-) ] || [ ! $(echo $opt | grep ^\-) ]; then
      #echo --opt=\'$opt\';
      case $opt in
        --flush)         flush;;
        --nolimit)       nolimit;;
        --quiet)         quiet=true;;
        --nomain)        nomain=true;;
        --random)        random true;;
        --checkver)      checkVerFile=true;;
        --checksubdir=*) checkSubdir $opt;;
        --help)    helpPrint;;
        *) echo -n $0; echo -e ": illegal option -- ${cYel}$opt${cNone}";
           echo -e "For help you can use flag '${cYel}--help ${cNone}'or '${cYel}-h${cNone}'";
           exit 1;;
      esac;
      continue;
    fi;
    ## render params with -
    local i;
    for ((i=1; $i<${#opt}; i=$(($i+1)))); do
      local char=${opt:$i:1};
      #echo -char=\'$char\';
      case "$char" in
        -) ;;
        =) break;;
        f) $FUNCNAME --flush;;
        l) $FUNCNAME --nolimit;;
        q) $FUNCNAME --quiet;;
        m) $FUNCNAME --nomain;;
        r) $FUNCNAME --random;;
        c) $FUNCNAME --checkver;;
        s) $FUNCNAME --checksubdir=$(echo $opt | sed 's/^.*=//');
           $FUNCNAME --nomain;;
        h) $FUNCNAME --help;;
        *) echo -n $0; echo -e ": illegal param -- ${cYel}$char${cNone}";
           echo -e "For help you can use flag '${cYel}--help ${cNone}'or '${cYel}-h${cNone}'";
           exit 1;;
      esac;
    done;
  done;
}

## --flush
## Remove all files (temp and base) (except .hidden)
flush(){
  ## Remove temp directory
  if [ -d "$pathToTempDir" ]; then
    logmessage -n "Remove $pathToTempDir.. ";
    rm -R -f $pathToTempDir;
    logmessage -t $msgOk;
  fi;

  if [ "$(ls $pathToSaveBase)" ]; then
    logmessage -n "Remove all files (except .hidden) in $pathToSaveBase.. ";
    rm -R -f $pathToSaveBase*;
    logmessage -t $msgOk;
  fi;
  writeLog "Files storage erased";
  exit 0;
}

## --nolimit
## Disable download speed limit and off delay
nolimit(){
  wgetDelay=''; wgetLimitSpeed='';
}

## --quiet
## quiet mode
quiet=false;

## --random WORKURL
## random WORKURL from update.ver [HOSTS] for $getFreeKey" = true
random(){
 if [ -n "$*" ]; then randomServer=true; fi;
 if [ -n "$randomServer" ]; then return 0; fi;
 return 1;
}

## --checkver
## check if need update mirror for actual
#checkVerFile=false;

## --check
## Check only included sub-dirs
checkSubdir() {
  local ver=$(echo $1 | sed 's/^.*=//');
  local check;
  checkSubdirsList=();
  logmessage -n "You check update..";
  [[ all == "$ver" ]] && ver=345678;
  [[ "$ver" == *3* ]] && check=true && logmessage -nt " v3" && nomain=false;
  [[ "$ver" == *4* ]] && check=true && logmessage -nt " v4" && checkSubdirsList+=('v4');
  [[ "$ver" == *5* ]] && check=true && logmessage -nt " v5" && checkSubdirsList+=('v5');
  [[ "$ver" == *6* ]] && check=true && logmessage -nt " v6" && checkSubdirsList+=('v6');
  [[ "$ver" == *7* ]] && check=true && logmessage -nt " v7" && checkSubdirsList+=('v7');
  [[ "$ver" == *8* ]] && check=true && logmessage -nt " v8" && checkSubdirsList+=('v8');
  [[ ! "$check" ]] && echo -e " ${cRed}Error${cNone}
Illigal param -- $1;  use - all, 3, 4, 5, 6, 7, 8" && exit 1;
  echo ;
}

#--help
helpPrint(){
  echo "-f, --flush         - remove all files (except .hidden) in $pathToSaveBase";
  echo "-l, --nolimit       - unlimit download speed & disable delay";
  echo "-q, --quiet         - quiet mode";
  echo -e "-m, --nomain        - do not create main mirror (if you need v4 or v8,
                      that may be you don need main mirror with v3 updates)";
  echo "-r, --random        - random WORK mirror if getFreeKey=true";
  echo "-c, --checkver      - check if need update mirror for actual";
  echo "-s=, --checksubdir= - checkSubdir options: 3, 4, 5, 6, 7, 8, all";
  echo "-h, --help          - this help"
  exit 1;
}

pressKeyBoard() {
  read -s -t 0.1 -n 1 INPUT;
    if [[ "$INPUT" = q ]];then
      logmessage -t "${cGray}>${cNone}";
      local version=$(echo "$saveToPath" | sed "s|${pathToSaveBase}||" | sed 's/\///');
      [ -z "$version" ] && version=v3;
      logmessage "${cRed}Stop update NOD32 $version${cNone}";
    return 0;
  fi;
  return 1;
}
## Prepare ####################################################################

## render all script params with recursion
handleParam $*;

###############################################################################
## If you want get updates from official servers using 'getkey.sh' ############
## (freeware keys), leave this code (else - comment|remove). ##################
## Use it for educational or information purposes only! #######################

if [ "$getFreeKey" = true ] && [ -f "$pathToGetFreeKey" ]; then
  nodKey=$(bash "$pathToGetFreeKey" | tail -n 1);
  logmessage -n "Getting valid key from '$pathToGetFreeKey'.. "
  if [ ! "$nodKey" == "error" ]; then
    nodUsername=${nodKey%%:*} nodPassword=${nodKey#*:};
    if [ ! -z $nodUsername ] && [ ! -z $nodPassword ]; then
      logmessage -t "$msgOk ($nodUsername:$nodPassword)";
      WORKURL='http://update.eset.com/eset_upd/';
      USERNAME=$nodUsername; PASSWD=$nodPassword;
      if random && downloadSource $WORKURL $pathToTempDir; then
        logmessage -n "Random change sourceUrl $WORKURL ->";
        # found random url from update.ver
        URLs=`cat $pathToTempDir'update.ver' | grep 'Other=' | sed 's/,/\n/g; s/[1-9]0\+@//g; s/Other=//;s/ //g'`;
        count=`echo "$URLs" | wc -l`;
        if [[ "$count" == 0 ]]; then
          logmessage -t ".. $msgErr";
          writeLog  "Random change sourceUrl $WORKURL -> $WORKURL2 - ERROR"
        else
          num=0;
          while [[ "$num" == 0 ]]; do num=$(($RANDOM*$count/32768)); done;
          WORKURL2=`echo "$URLs" | sed -n "${num}p"`;
          logmessage -t " $WORKURL2.. $msgOk";
          writeLog  "Random change sourceUrl $WORKURL -> $WORKURL2"
          WORKURL=$WORKURL2;
        fi;
      fi;
      updServer0=($WORKURL $USERNAME $PASSWD);
    else
      logmessage -t $msgErr;
    fi;
  else
    logmessage -t $msgErr;
  fi;
fi;

## End of code for 'getkey.sh' ################################################
###############################################################################


## Check URL in 'updServer{N}[0]' for availability
##   Limit of servers in settings = {0..N}
for i in {0..10}; do
  ## Get server URL
  eval CHECKSERVER=\${updServer$i[0]};

  ## Begin checking server
  if [ ! "$CHECKSERVER" == "" ]; then
    logmessage -n "Checking server $CHECKSERVER.. "
    ## Make check
    eval USERNAME=\${updServer$i[1]};
    eval   PASSWD=\${updServer$i[2]};
    if checkAvailability $CHECKSERVER; then
      ## If avaliable - set global values..
      WORKURL=$CHECKSERVER;
      ## ..by array items
      break;
    fi;
  fi;
done

## If no one is available
if [ "$WORKURL" == "" ]; then
  logmessage "${cRed}No available server, exit${cNone}"
  writeLog "FATAL - No available server";
  exit 1;
fi;

## Remove old temp directory
removeDir $pathToTempDir;
## Create base directory
createDir $pathToSaveBase;
## Create temp directory
createDir $pathToTempDir;

## Begin work #################################################################

## MAIN function - Making mirror by url (read 'update.ver', take sections
##   (validate/edit), write new 'update.ver', download files, declared in new
##   'update.ver')
function makeMirror() {
  ## $1 = From (url,  ex.: http://nod32.com/not_upd/)
  local sourceUrl=$1;
  ## $2 = To   (path, ex.: /home/username/nod_upd/)
  local saveToPath=$2;

  ## Path to DOWNLOADED 'update.ver' file
  local mainVerFile=$pathToTempDir'update.ver';
  ## Path to RESULT 'update.ver' file
  local newVerFile=$mainVerFile'.new';
  ## Here we will store all parsed filenames from 'update.ver'
  local filesArray=();
  local isOfficialUpdate=false;

  ## download update.ver zip from $WORKURL to $pathToTempDir and unzip
  if ! downloadSource $sourceUrl $saveToPath; then return 1; fi;
  
#############################################################
  ## delete old files if it not in $mainVerFile
  local str=`cat $mainVerFile`;
    for file in $(find $saveToPath -type f -iname \*nup | grep $saveToPath'e' | sed 's/.*\///' | tr '\n' ' '); do
      if [ -z "`echo "$str" | grep $file`" ]; then
      logmessage "File '$saveToPath$file' - ${cRed}need delete${cNone}";
      writeLog "File '$saveToPath$file' - need delete"
      #rm $saveToPath$file;
    fi;
  done;
############################################################

  ## find version update
  local diffVerFile=$saveToPath'update.diff.ver';
  local diffVerFileNew=$diffVerFile'.new';

  if [[ "$checkVerFile" == true ]]; then
    [ -f $diffVerFileNew ] && rm -f $diffVerFileNew;
    sed \
    -e '/HOST/d; /\[.*/b; /date=/b; /file=/b; /version=/b' \
    -e d $mainVerFile |\
    tr '\n' ' ' |\
    sed 's/\r//g; s/\[/\n\[/g' |\
    grep 'version=' \
    > $diffVerFileNew;

    if [ -f $diffVerFile ]; then
      local version=$(echo "$saveToPath" | sed "s|${pathToSaveBase}||" | sed 's/\///');
      [ -z "$version" ] && version=v3;
      if [ ! "`diff -E -b -B -w $diffVerFileNew $diffVerFile`" ]; then
        ## actual version files
        #mv $diffVerFileNew $diffVerFile;
        ## TODO: теперь нужно проверить целостность файлов согласно размерам
        rm -f $diffVerFileNew;
        logmessage "${cGreen}Base $version actual${cNone}, stop update mirror";
        writeLog "Base $version actual, stop update mirror";
        return 1;
      else
        logmessage "${cYel}Base $version note actual${cNone}, continue work";
        writeLog "Base $version note actual, continue work";
      fi;
      rm -f $diffVerFile;
    fi;
  fi;

  #cat $mainVerFile;
  ## Use function from read_ini.sh
  logmessage -n "Parsing & writing new update.ver file ${cGray}(gray dots = skipped sections)${cNone} "

  echo -en "[HOSTS]\n$(cat $mainVerFile | grep 'Other')\n\
;; This mirror created by <github.com/tarampampam/nod32-update-mirror> ;;\n" > $newVerFile;

  local sizeArray;
  OLD_IFS=$IFS; IFS=[
  for section in `cat $mainVerFile | sed '1s/\[//; s/^ *//'`; do
    IFS=$OLD_IFS;
    ## for exit from makeMirror, return 1
    if pressKeyBoard; then return 1; fi;
    #logmessage $SectionName;
    ## 1. Get section content (text between '[' and next '[')
    local sectionContent=$(echo "[$section" | tr -d "\r");
    # echo "$sectionContent"; exit 1;
    local filePlatform=$(getValueFromINI "$sectionContent" "platform");
    #echo $filePlatform; exit 1;
    if [ ! -z $filePlatform ] && [[ "`echo ${updPlatforms[@]}`" == *$filePlatform* ]]; then
      ## $filePlatform founded in $updPlatforms
      ## Second important field - is 'type='
      local fileType=$(getValueFromINI "$sectionContent" "type");
      #echo "$fileType"; exit 1;
      if [ ! -z $fileType ] && [[ `echo ${updTypes[@]}` == *$fileType* ]]; then
        ## $fileType founded in $updTypes
        ## And 3rd fields - 'level=' or 'language='

        ## Whis is flag-var
        local writeSection=false;

        ## Check update file level
        local fileLevel=$(getValueFromINI "$sectionContent" "level");
        ## NOD32 **Base** Update File <is here>
        [ ! -z $fileLevel ] && [[ "`echo ${updLevels[@]}`" == *$fileLevel* ]] && writeSection=true;

        ## Check component language
        local fileLanguage=$(getValueFromINI "$sectionContent" "language");
        ## NOD32 **Component** Update File <is here>
        [ ! -z $fileLanguage ] && [[ "`echo ${updLanguages[@]}`" == *$fileLanguage* ]] && writeSection=true;

        ## Write active section to new update.ver file
        if [ "$writeSection" = true ]; then
        ## Save file size in array
        local size=$(getValueFromINI "$sectionContent" "size");
        sizeArray+=($size);
        #echo "$sectionContent"; echo;
          ## get 'file=THIS_IS_OUR_VALUE'
          local fileNamePath=$(getValueFromINI "$sectionContent" "file");
          if [ ! -z "$fileNamePath" ]; then
            ## If path contains '://'
            if [[ $fileNamePath == *\:\/\/* ]]; then
              ## IF path is FULL
              ## (ex.: http://nod32mirror.com/nod_upd/em002_32_l0.nup)
              ## Save value 'as is' - with full path
              filesArray+=($fileNamePath);
            else
              if [[ $fileNamePath == \/* ]]; then
                ## IF path with some 'parent directory' (is slash in path)
                ## (ex.: /nod_upd/em002_32_l0.nup)
                ## Write at begin server name
                ## Anyone know how faster trin string to parts?!
                local protocol=$(echo $WORKURL | awk -F/ '{print $1}');
                local host=$(echo $WORKURL | awk -F/ '{print $3}');
                filesArray+=($protocol'//'$host''$fileNamePath);
              else
                ## IF filename ONLY
                ## (ex.: em002_32_l0.nup)
                ## Write at begin full WORKURL (passed in $sourceUrl)
                filesArray+=($sourceUrl''$fileNamePath);
              fi;
            fi;
            ## Replace fileNamePath
            local newFileNamePath='';
            if [ "$createLinksOnly" = true ]; then
              ## get full path to file (pushed in $filesArray)
              if [ "$isOfficialUpdate" = true ]; then
                ## If is official update - add user:pass to url string
                ##   (ex.: http://someurl.com/path/file.nup ->
                ##   -> http://user:pass@someurl.com/path/file.nup)
                local inputUrl=${filesArray[@]:(-1)};
                ## Anyone know how faster trin string to parts?!
                local protocol=$(echo $inputUrl | awk -F/ '{print $1}');
                local host=$(echo $inputUrl | awk -F/ '{print $3}');
                local mirrorHttpAuth='';
                if [ ! -z $USERNAME''$PASSWD ]; then
                  mirrorHttpAuth=$USERNAME':'$PASSWD'@';
                fi;
                newFileNamePath=$protocol'//'$mirrorHttpAuth''$host''$fileNamePath;
              else
                ## Else - return full url (ex.: http://someurl.com/path/file.nup)
                newFileNamePath=${filesArray[@]:(-1)};
              fi;
            else
              justFileName=${fileNamePath##*/};
              newFileNamePath=$justFileName;
            fi;
          fi;
          ## Echo (test) last (recently added) download task
          #echo ${filesArray[${#filesArray[@]}-1]};
          #echo $newFileNamePath;
          ## Mare replace 'file=...' in section
          sectionContent=$(echo "${sectionContent/$fileNamePath/$newFileNamePath}");
          logmessage -t "$sectionContent" >> $newVerFile;
        fi;
      fi;
    fi;
    if [ "$writeSection" = true ]; then
      logmessage -nt '.';
    else
      logmessage -nt "${cGray}.${cNone}";
    fi;
  done; logmessage -t " $msgOk";
  IFS=$OLD_IFS;

  if [ "$createLinksOnly" = true ]; then
    logmessage "'createLinksOnly' is 'true', download files is ${cYel}skipped${cNone}"
  else
    ## delete all symlinks for clear
    #logmessage "${cYel}Remove all symlinks${cNone} from $saveToPath";
    #find $saveToPath -type l -delete;

    local dlNum=0;
    local dlTotal=${#filesArray[@]};
    ## Download all files from 'filesArray'
    for item in ${filesArray[*]}; do
      ## for exit from makeMirror, return 1
      if pressKeyBoard; then return 1; fi;
      # Inc counter
      dlNum=$((dlNum+1));
      logmessage -n "Download file $item ($dlNum of $dlTotal).. ";
      ## если такой update file есть, то сделаем symlink
      local itemName=$(echo $item | sed 's/.*\///');
      local size=${sizeArray[$(($dlNum-1))]};
      [ -f ${saveToPath}${itemName} ] &&
        local sizeItem=$(du -b ${saveToPath}${itemName} | awk '{print $1}');
      if [ "$sizeItem" = "$size" ];then
        logmessage -t "${cYel}Skipped ${cGray}[$(($size/1024)) KB]${cNone}";
        continue;
      fi;
      #local files=$(find $pathToSaveBase -iname $itemName -type f);
      ## если файлы с таким именем нашлись, то может не придется их качать
      #if [ "$files" ]; then
      #  ## проверяем на наличие линка если не существует и размер подходящий, то сделаем его
      #  for i in $files; do
      #    local sizeI=$(du -b $i | awk '{print $1}');
      #    if [ "$size" = "$sizeI" ]; then
      #      ## если размер файла не изменился или он уже существует, то skip
      #      if [ "$saveToPath$itemName" = "$i" ]; then # && [ -f "$i" ]; then
      #        logmessage -t "${cYel}Skipped ${cGray}[${size}B]${cNone}";
      #        break;
      #      fi;
      #      ## Create symlink
      #      logmessage -t "${cYel}Create symlink${cNone}";
      #      writeLog "$item - create symlink to $i";
      #      ln -s "$i" "$saveToPath$itemName";
      #     break;
      #    fi;
      #  done;
      #  ## если симлинк или файл есть и мы его обработали, то переходим к следующему файлу
      #  [ -f $item ] && [ "$size" = "$sizeI" ] && continue;
      #fi;
      if downloadFile $item $saveToPath; then
        writeLog "$item Saved";
        DownloadFileCount=$(( $DownloadFileCount + 1 ));
        downloadFileSize=$(( $downloadFileSize + $size ));
      fi;
    done;
    logmessage "Mirroring \"${sourceUrl}\" -> \"${saveToPath}\" ${cGreen}complete${cNone}";
    logmessage "Spend time: $(( ($(date +%s) - $timeStartUpdate)/60 ))min.";
    writeLog "Mirroring \"${sourceUrl}\" -> \"${saveToPath}\" complete";
  fi;

  ## Delete old file, if exists local
  [ -f "${saveToPath}update.ver" ] && rm -f "${saveToPath}update.ver";
  [ -f "$newVerFile" ] && mv "$newVerFile" "${saveToPath}update.ver";
  logmessage "File ${saveToPath}update.ver ${cYel}update${cNone}";
  writeLog "File ${saveToPath}update.ver update";
  ## for diff.ver
  [ -f $diffVerFileNew ] && 
  mv $diffVerFileNew $diffVerFile &&
  logmessage "File $diffVerFile ${cYel}update${cNone}" &&
  writeLog "File $diffVerFile update";
}

## Create (update) main mirror
if [[ "$nomain" == true ]]; then
  logmessage "Do not create main mirror";
  writeLog "Do not create main mirror";
else
  makeMirror $WORKURL $pathToSaveBase;
fi;

## Create (update) (if available) subdirs with updates
if [ ! -z "$checkSubdirsList" ]; then
  for item in ${checkSubdirsList[*]}; do
    checkUrl=$WORKURL''$item'/';

    logmessage -n "Checking $checkUrl.. ";
    if checkAvailability $checkUrl; then
      downloadPath=$pathToSaveBase''$item'/';
      mkdir -p $downloadPath;
      makeMirror "$checkUrl" "$downloadPath";
    fi;
  done;
fi;

## Finish work ################################################################

## Remove old temp directory
removeDir $pathToTempDir;

if [ "$createTimestampFile" = true ]; then
  logmessage -n "Create timestamp file.. ";
  timestampFile=$pathToSaveBase'lastevent.txt';
  echo $(date "+%Y-%m-%d %H:%M:%S") > $timestampFile;
  if [ -f "$timestampFile" ]; then
    logmessage -t $msgOk; else logmessage -t $msgErr;
  fi;
fi;

if [ "$createRobotsFile" = true ]; then
  robotsTxtFile=$pathToSaveBase'robots.txt';
  if [ ! -f $robotsTxtFile ]; then
    logmessage -n "Create 'robots.txt'.. ";
    echo -e "User-agent: *\r\nDisallow: /\r\n" > $robotsTxtFile;
    if [ -f "$robotsTxtFile" ]; then
      logmessage -t $msgOk; else logmessage -t $msgErr;
    fi;
  fi;
fi;

if [ -n "$DownloadFileCount" ]; then
  logmessage "Count of download update files: [$DownloadFileCount], \
general size: $((downloadFileSize/1024/1024))MB, \
spend time: $(( ($(date +%s) - $timeStartUpdate)/60 )) min.";
fi;
