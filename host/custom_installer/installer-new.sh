#!/bin/bash
#
# IHC CAPTAIN INSTALLER
#

if [ -n "$INSIDEGITHUB" ]; then
	TERM="xterm-color"
	GITSPINCOUNT=0
	INGIT=true
else
	INGIT=false
fi

# make sure we fail if we need to fail on pipes
set -uo pipefail


# colors for prompts - will be needed right away for initial checks
case "$TERM" in
	dumb|vt220)
		RTXT=""
		GTXT=""
		LGTXT=""
		BTXT=""
		WTXT=""
	;;
	*)
		RTXT="\e[0;31m"
		GTXT="\e[0;32m"
		LGTXT="\e[1;32m"
		#no color
		BTXT="\e[0m"
		#bold white
		WTXT="\e[1;37m"
	;;
esac


# Must have commands
CMDS=("apt-get" "echo" "tr" "date" "command" "crontab" "id" "seq" "printf" "pwd" "grep" "find" "mktemp" "mkdir" "chown" "tar" "sed" "sh" "ln" "usermod" "systemctl")
for CMDchk in "${CMDS[@]}"; do
	if ( ! command -v "$CMDchk" > /dev/null 2>&1 ); then
		clear
		echo "IHC Captain installer"
		echo -e "${RTXT}Fatal fejl:${BTXT} $CMDchk kommandoen mangler - kan ikke gennemfÃ¸re installationen uden - beklager."
		echo
		exit 1
	fi
done

# Set charset to first UTF8 found - to handle danish chars in length calc
LC_ALL=$( (locale -a|grep -i -m1 'C.UTF-8') || (locale -a|grep -i -m1 '.utf8'))

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Used for quick checking arguments so its up here because we need the right away
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
LASTARGFOUND=""
checkForArg(){
	if [ -z "$CMDPARMS" ]; then
		return 1
	fi
	LASTARGFOUND=$1
	local i=1;
	local found=1
	for parm in $CMDPARMS
	do
		if [ "$parm" == "$1" ]; then
			LASTARGFOUND=$1
			found=0
			break
		fi
	    i=$((i + 1));
	done
	return $found
}


# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# installer variables
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#cmd with cleaned input
CMDPARMS=$(echo "$@"|tr -d "-" |tr '[:upper:]' '[:lower:]')
INSTVER="1.60"
INSTBACK="IHC Captain installer v$INSTVER"

#running a custom install not
CUSTOM_INSTALL=false
# automatic try and detect docker - can be forced by launching with docker as a argument
INSIDE_DOCKER=false
# run IHC Captain has this user
USERNAME=pi
NEWHOSTNAME="IHCCaptain"
DEFAULTPASS="IHCCaptain"

# quick lookup are we a raspberry pi or not - actually it checks the os for rasbian
IS_A_PI=false

# are we already existing for when traps are fired
EXITING=false
HEADERSHOWN=false
SECTIONOPEN=false

# dest dirs
DEST_DIR=/opt/ihccaptain
DEST_DIR_TMP=$DEST_DIR/tmp
DEST_DIR_TMPCAP=$DEST_DIR_TMP/ihccaptain
DEST_DIR_TUNOUT=/opt/tunnelout
TEMPDIR=/tmp/

#device info (file does not exist on all unix distros)
# shellcheck disable=SC2015
DEVICEMODEL=$([[ -f /proc/device-tree/model ]] && (tr '\0' '\n' < /proc/device-tree/model) || true)

#download base url for IHC Captain
DLURL=https://jemi.dk/ihc/files/

#defaults for services / addons
SERVICESTART=true
LOG2RAM=true
INSTALLTO=true

# What IHC Captain to download
DLFILE="ihccaptain.tar.gz?$(date +%s)"
if checkForArg "beta"; then
	DLFILE="ihccaptain-beta.tar.gz?$(date +%s)"
	INSTVER="$INSTVER BETA";
	INSTBACK="$INSTBACK BETA";
fi
# no output wanted when updating
BEQUIET=false
if checkForArg "quiet" || checkForArg "webupdate"; then
	BEQUIET=true
fi

DEBUGINST=false
if [[ "$*" == *"debug"* ]]; then
	INSTBACK="$INSTBACK !DEBUG!";
	DEBUGINST=true
fi


# Make sure
if $INGIT; then
	INSIDE_DOCKER=true
fi



# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# installer options/config
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# used for adding and removing stuff in files
CHECKMARK="ihccaptainadded"

# Add to cron info
CRONCMD="find ${DEST_DIR_TMPCAP}/logins/ -type f -mtime +2 -delete 2>&1"
CRONJOB="0 * * * * $CRONCMD"

#Skip APT-get install
INSTALLAPT=true

#Global error feedback
GERROR=false
TERROR=false

# nginx webserver settings
WEBPORT=80
SSLPORT=443
SSLINSTALL=true
WEBINSTALL=true
SHOWWEBUI=true
PHPFPM=null

SSLCERT1=/etc/ssl/certs/ssl-cert-snakeoil.pem
SSLCERT2=/etc/ssl/private/ssl-cert-snakeoil.key

BUILDIMG=false

APTPARM="-qqyf"

# force values when building the img file
if checkForArg "buildimg"; then
	BUILDIMG=true
	INSIDE_DOCKER=true
	USERNAME=pi
	IS_A_PI=true
	APTPARM="-yf"
fi

if checkForArg "noapt"; then
	INSTALLAPT=false
fi

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# basic output formatting functions
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
errorMsg()
{
	if $BEQUIET; then
		>&2 echo "$1"
		return 0
	fi
	echo -e "[ ${RTXT}FEJL${BTXT} ] $1" >&2
	TERROR=true
}

succesMsg()
{
	if $GERROR; then
		return
	fi
	if $BEQUIET; then
		return 0
	fi
	echo -e "[${GTXT}Â»${LGTXT}Â»OKÂ«${GTXT}Â«${BTXT}] $1"
}

installsechead(){
	# reset failure for this section
	GERROR=false
	if $BEQUIET; then
		return 0
	fi
	if $SECTIONOPEN; then
		sepline
		echo
	fi
	SECTIONOPEN=true
	sepline 0
	echo -ne "\râ”€â•¡ ${WTXT}$1${BTXT} â•ž"
	echo
}


ihccapheader(){
	if $HEADERSHOWN; then
		return 0
	fi
	HEADERSHOWN=true
	if $BEQUIET; then
		return 0
	fi
	if [ -z "${1-}" ]; then
		clear
	fi
	echo -e "$GTXTâ–â–‚$LGTXTâ–„â–†â–ˆ ${WTXT}$INSTBACK$BTXT $LGTXTâ–ˆâ–†â–„$GTXTâ–‚â–$BTXT"
	fatline
}

fatline(){
	if $BEQUIET; then
		return 0
	fi
	termLine "â•" 10
	echo -e "\r"
}

sepline(){
	if $BEQUIET; then
		return 0
	fi
	termLine "â”€" 10
	if [ -z "${1-}" ]; then
		echo -e "\r"
	fi
}

# $1 = char to print
# $2 = numbers of chars to use for calc
# $3 = if set then we will only print $2 numbers of $1 - if unset then we will asumme terminal width minus this
termLine(){
	if [ -n "${3-}" ]; then
		local tLen=$2
	else
		local tLen=$((WT_WIDTH-$2))
	fi
	printf  "%0.s$1" $(seq 1 "$tLen")
}


rootcheck(){
	if [[ $(id -u) != 0 ]]; then
		if $BEQUIET; then
			echo "Du skal vÃ¦re root/superuser for at benytte IHC Captain installer"
			exit 1
		fi
		whiptail --backtitle "$INSTBACK" --title "Du er ikke root/superuser" --msgbox "Du skal vÃ¦re root/superuser for at benytte IHC Captain installer.\n\nBenyt evt. \"sudo ${0} ${CMDPARMS}\"" "$WT_HEIGHT" "$WT_WIDTH"
		exit 1
	fi
}

getTermSize(){
	WT_HEIGHT=15

	# hardcoded
	if $INSIDE_DOCKER || $BUILDIMG; then
		WT_WIDTH=120
		return;
	fi

	WT_WIDTH=$(tput cols)
	if [ -z "$WT_WIDTH" ] || [ "$WT_WIDTH" -lt 60 ]; then
		WT_WIDTH=80
	fi
	if [ "$WT_WIDTH" -gt 120 ]; then
		WT_WIDTH=120
	fi
	WT_WIDTH=$((WT_WIDTH-4))
}

# when called it will check if should show debug and exit
# it normally called just before starting a task - and thereby it can also show the last parameter that was checked for
debugOut(){
	if ! $DEBUGINST; then
		return 0
	fi
	ihccapheader
	echo

	echo -e "${WTXT}-[Debug installer]------------------------------------${BTXT}"
	# Nothing passed then show the last command if possible
	if [ $# -eq 0 ]; then
		if [[ $LASTARGFOUND != "" ]]; then
			echo " last cmd argument      : $LASTARGFOUND"
		fi
	fi
	echo " ihccaptain inst. dir   : $DEST_DIR"
	echo " tunnelout inst. dir    : $DEST_DIR_TUNOUT"
	echo " temp. dir              : $TEMPDIR"
	echo " Run as user            : $USERNAME"
	echo " User homedir           : $HOMEDIR"
	echo " Download file          : $DLURL$DLFILE"
	echo " APT upgrade/install    : $INSTALLAPT"
	echo " Tunnelout install      : $INSTALLTO"
	echo " log2ram install        : $LOG2RAM"
	echo " ihccaptain service     : $SERVICESTART"
	echo " build image install    : $BUILDIMG"

	if $WEBINSTALL; then
		echo " nginx http             : $WEBPORT"
	else
		echo " nginx http             : disabled"
	fi
	if $SSLINSTALL; then
		echo " nginx https            : $SSLPORT"
	else
		echo " nginx https            : disabled"
	fi

	echo
	echo -e "${WTXT}-[Enviroment]-----------------------------------------${BTXT}"
	echo " Distro name            : $DIST_NAME"
	echo " Distro version         : $DIST_VERSION"
	echo " PHP fm                 : $PHPFPM"
	echo " HW info                : $DEVICEMODEL"
	echo " Raspberry Pi hardware  : $IS_A_PI"
	echo " Custom install         : $CUSTOM_INSTALL"
	echo " Quiet mode             : $BEQUIET"
	echo " Docker                 : $INSIDE_DOCKER"
	echo " GitHub                 : $INGIT"
	echo " Term size              : $WT_WIDTH * $WT_HEIGHT"
	echo
	exit 0
}

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#INSIDE DOCKER then we dont ask a lot of questions and make wrappers for the UI functions - run if inside docker or asked for docker in params
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
if [[ -f /.dockerenv ]] || grep -Eq '(lxc|docker)' /proc/1/cgroup > /dev/null 2>&1 || (checkForArg "docker") || [[ $BUILDIMG == true ]]; then
	# Wrapper functions for automatic installs
	function whiptail {
		local INPUTSTR="$*"
		# we only suppor the msg box in docker/build mode
		if ( grep --quiet "msgbox" <<< "$INPUTSTR" ); then
			echo
			# remove terminal sizes from the message
			INPUTSTR=${INPUTSTR/$WT_HEIGHT $WT_WIDTH/""}
			# trim the string
			INPUTSTR=${INPUTSTR##*( )}
			INPUTSTR=${INPUTSTR%%*( )}
			# find the title of the box
			local TITLE="${INPUTSTR##*--title }"
			TITLE="${TITLE%% --*}"
			TITLE=" $TITLE "

			# main msg
			local MSG="${INPUTSTR##*--msgbox }"
			MSG="\n${MSG}"

			# Wrap the text if possible
			if command -v fold &> /dev/null; then
				MSG=$(fold -sw $((WT_WIDTH-15)) <<< "$MSG")
			else
				if command -v fmt &> /dev/null; then
					MSG=$(fmt -w $((WT_WIDTH-15)) <<< "$MSG")
				fi
			fi

			MSG=$(echo -en "$MSG")
			local titeLen=${#TITLE}
			# header box
			echo -n  "  â”Œ"
			termLine "â”€" "$titeLen" true
			echo       "â”"
			echo -en "â”Œâ”€â•¡${RTXT}$TITLE${BTXT}â•žâ”€"
			termLine "â”€" $((titeLen+16))
			echo "â”"
			echo -n  "â”‚ â””"
			termLine "â”€" "$titeLen" true
			echo -n "â”˜"
			termLine " " $((titeLen+15))
			echo "â”‚"

			# content
			while IFS= read -r line; do
			    echo -n "â”‚ "
			    echo -n "${line}"
			    termLine " " $((${#line}+14))
			    echo " â”‚"
			done <<< "$MSG"

			# empty bottom
			echo -n "â”‚ "
		    termLine " " 14
		    echo " â”‚"

			# end box
			echo -n "â””"
			termLine "â”€" 12
			echo -n "â”˜"
			echo
			echo
		else
			echo "#########################################################################"
			echo "### ERROR: $*"
			echo "#########################################################################"
			echo
		fi
	}
	function clear {
		# avoid printing error 'Term'
		if $HEADERSHOWN; then
			echo -n
		else
			echo -e "\r\r\r"
		fi
	}
	function tput {
		# avoid error
		if command -v true &> /dev/null; then
			true
		else
			echo -n
		fi
	}

	# tell the world we are running dockerish
	INSIDE_DOCKER=true

	# Recalc size
	getTermSize

	echo
	ihccapheader
	if $BUILDIMG; then
		if $INGIT; then
			echo "IHC Captain custom installer | .img builder for RPIs [RPI IMG GITHUB]"
		else
			echo "IHC Captain custom installer | .img builder for RPIs [RPI IMG]"
		fi
	else
		USERNAME=root
		echo "IHC Captain custom installer for Docker"
	fi
	fatline
fi

# Recalc size
getTermSize


######################################################################################
# Help - its here because now we have the most basic stuff
######################################################################################
if checkForArg "help"; then
	echo
	ihccapheader noclear
	echo "Help..."
	echo
	echo " Options:"
	echo "  debug          : Show debug information - no real install"
	echo "  update         : Update IHC Captain"
	echo "  service        : Just update IHC Captain service"
	echo "  testinstaller  : test the installer options"
	echo "  styrdithus     : Just install the styrdithus.dk service"
	echo "  log2ram        : Just install log2ram"
	echo "  nginx          : Just install the NGINX IHC Captain config"
	echo "  cronjob        : Just install the cronjob"
	echo "  fixrights      : Fix user and file rights"
	echo "  remove         : uninstall IHC Captain and related programs"
	echo "  cleanup        : Remove all user data"
	echo "  quiet          : Less output"
	echo
	echo " Expert options:"
	echo "  custom         : custom installer"
	echo "  docker         : docker installer"
	echo "  beta           : beta installer"
	echo "  buildimg       : builds the SD card image"
	echo "  updatenginx    : Update NGINX config files"
	echo "  noapt          : Dont do apt update and install"
	echo "  forceapt       : Always install/update apt-get packages"
	echo "  user=USER      : install with USER as username - default pi"

	echo
	exit 0
fi

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# check for whiptail when running normally - this should never happen but hey...
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
if ! $INSIDE_DOCKER && ! $BUILDIMG; then
	if ( ! command -v "whiptail" > /dev/null 2>&1 ); then
		echo
		echo "IHC Captain installer"
		echo -ne "For at vise brugerfladen behÃ¸ves programmet \"whiptail\"\nTryk j for at forsÃ¦tte eller n for at afbryde: "
		read -r WHIPINSTALL
		if [[ "$WHIPINSTALL" != "j" ]] && [[ "$WHIPINSTALL" != "J" ]]; then
			echo "Farvel og tak..."
			exit 1
		fi
		if [[ $(id -u) != 0 ]]; then
			echo
			echo -e "Du skal vÃ¦re root/superuser for at benytte IHC Captain installer.\nBenyt evt. \"sudo ${0} ${CMDPARMS}\""
			exit 1
		fi
		echo
		echo "Henter whiptail programmet - vent venligst..."
		if (! apt-get $APTPARM install whiptail); then
			echo "whiptail programmet kunne ikke installeres - beklager..."
			exit 1
		fi
	fi
fi


# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# CUSTOM INSTALL OPTIONS if requested or running inside docker from the above
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
if checkForArg "custom"  || checkForArg "custominstall"; then
	CUSTOM_INSTALL=true
	if ! $INSIDE_DOCKER; then
		ihccapheader
		echo "IHC Captain custom installer"
	fi
fi

# Doe we have a username from the bash
if [[ "$*" =~ .*user=([[:alpha:]]*) ]]; then
	# strip bad chars to improve input
	USERNAME=$(tr -dc '[:alnum:]\n\r' <<< "${BASH_REMATCH[1]}")
# ask for the username on custom installs
elif ! $INSIDE_DOCKER && $CUSTOM_INSTALL; then
	FIRSTUSER=$(getent passwd 1000 2> /dev/null | cut -d: -f1)
	echo -e "Tast det brugernavn du vil have IHC Captain til at kÃ¸re under og tryk enter.\n"
	if [[ -n $FIRSTUSER ]]; then
		echo -e "Brugeren: \"$FIRSTUSER\" er en mulighed ;)\n"
	fi
	echo -n "Indtast brugernavn: "
	read -r USERNAME

	# strip bad chars to improve input
	USERNAME=$(tr -dc '[:alnum:]\n\r' <<< "$USERNAME")

	# validate username
	if [ -z "$USERNAME" ]; then
		errorMsg "Du skal angive et brugernavn - farvel!"
		echo
		exit 1
	fi
fi

# find homedir for the user and check it okay
HOMEDIR=$(bash -c "cd ~$(printf %q "$USERNAME") 2> /dev/null && pwd")
if [ ! -d "${HOMEDIR}" ];  then
	errorMsg "Kunne ikke finde homedir for brugeren \"$USERNAME\""
	echo
	exit 1
fi

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#Version check for OS etc
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
DIST_NAME="Ukendt"
DIST_VERSION=-1
# supported distros
KNOWNDISTROS=(
raspbian
debian
)

# Min distro version we support
MINDISTVER=10
# Format pretty
KNOWNDISTROSSTR=$(printf "/%s" "${KNOWNDISTROS[@]}")
KNOWNDISTROSSTR=${KNOWNDISTROSSTR:1}

# Build distro info or fail
if [[ -r /etc/os-release ]]; then
	DIST_NAME=$(grep "^ID=" /etc/os-release| cut -c 4-)
	DIST_VERSION=$(grep "^VERSION_ID=" /etc/os-release| cut -c 12-)
	DIST_VERSION="${DIST_VERSION%\"}"
	DIST_VERSION="${DIST_VERSION#\"}"
fi

# Did we find what we were looking for?
# shellcheck disable=SC2076
if ! $CUSTOM_INSTALL && { [[ ! " ${KNOWNDISTROS[*]} " =~ " ${DIST_NAME} " ]] || [[ $DIST_VERSION -lt $MINDISTVER ]] ;} then
	if $BEQUIET; then
		errorMsg "Failed to detect Linux distribution/OS for your system: $DIST_NAME / $DIST_VERSION"
		exit 1
	fi
	if $INSIDE_DOCKER; then
		whiptail --title "Advarsel: Ukendt distribution/OS" --msgbox "Din Linux distribution/OS er ikke en $KNOWNDISTROSSTR distribution og derfor ikke understÃ¸ttet.\n\nOS: $DIST_NAME\nVersion : $DIST_VERSION"
		exit 1
	fi

	if (! whiptail --backtitle "$INSTBACK" --title "Advarsel: Ukendt distribution/OS" --yesno "Din Linux distribution/OS er ikke en $KNOWNDISTROSSTR distribution og derfor ikke understÃ¸ttet.\n\nOS navn    : $DIST_NAME\nOS version : $DIST_VERSION\n\nÃ˜nsker du at forsÃ¦tte installationen?" --yes-button "Ja" --no-button "Nej" $WT_HEIGHT $WT_WIDTH ) then
		errorMsg "Installation afbrudt - kÃ¸r evt. med: ${0} ${CMDPARMS} custom"
		sepline
		echo
		exit 1
	fi
fi

# make lookups easier later on
if [[ "$DEVICEMODEL" == *"Raspberry Pi"* ]]; then
	IS_A_PI=true
fi

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# FUNCTIONS START
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------

installSystemD(){
	run_command "cp \"${DEST_DIR}/installer/$1.service\" \"/etc/systemd/system/$1.service\"" "Opretter $1 systemd service"
	sed -i -e "s|_INSTALLDIR_|$DEST_DIR|g" "/etc/systemd/system/$1.service"
	sed -i -e "s|_TUNOUTDIR_|$DEST_DIR_TUNOUT|g" "/etc/systemd/system/$1.service"
	sed -i -e "s|_UPDATED_|$(date +'%D %H:%M:%S')|g" "/etc/systemd/system/$1.service"
	chmod 644 "/etc/systemd/system/$1.service"

	if ! $BUILDIMG; then
		run_command "systemctl daemon-reload" "Systemctl daemon genindlÃ¦ses"
		run_command "systemctl enable $1.service" "$1 service systemd aktiveres"
		run_command "systemctl restart $1.service" "$1 service systemd (gen)startes"
	else
		run_command "systemctl enable $1.service" "$1 service systemd aktiveres"
	fi
	succesMsg "$1 systemd service er installeret"
}

######################################################################################
# install IHC Captain files
######################################################################################
install_ihccaptain() {
	if [ ! -d "$DEST_DIR" ]; then
		run_command "mkdir \"$DEST_DIR\"" "Opretter mappen $DEST_DIR"
	fi

	if $GERROR; then
		return 1
	fi

	if [ ! -d "$DEST_DIR_TMPCAP" ]; then
		run_command "mkdir -p \"$DEST_DIR_TMPCAP\"" "Opretter mappen $DEST_DIR_TMPCAP"
		run_command "chown -R www-data:www-data $DEST_DIR_TMP" "Skifter rettigheder pÃ¥ mappen $DEST_DIR_TMP"
	fi

	cd $DEST_DIR || exit 1
	rm -rf debugCap > /dev/null 2>&1
	run_command "wget --no-cache -q -O ihccaptain.tar.gz $DLURL$DLFILE" "Henter IHC Captain"
	run_command "tar -xpszf ihccaptain.tar.gz" "Udpakker IHC Captain"
	rm "ihccaptain.tar.gz" > /dev/null 2>&1
	succesMsg "IHC Captain softwaren er installeret"
}

######################################################################################
# service install function
######################################################################################
install_service() {
	rootcheck

	installSystemD ihccaptain
	installSystemD findmypi

	# check for ssl options
	if ! $BUILDIMG; then
		if ! command -v make-ssl-cert &> /dev/null; then
			errorMsg "make-ssl-cert blev ikke fundet. Kan ikke lave selfsigned SSL certifikater"
		else
			if [ ! -f $SSLCERT2 ] || [ ! -s $SSLCERT2 ] || [ ! -f $SSLCERT1 ] || [ ! -s $SSLCERT1 ]; then
				run_command "make-ssl-cert generate-default-snakeoil --force-overwrite" "Bygger selfsigned SSL certifikater"
			fi
		fi
	fi
}

######################################################################################
# tunnelout service install
######################################################################################
install_tunnelout(){
	rootcheck

	if uname -m | grep -Eq ^armv6; then
		whiptail --backtitle "$INSTBACK" --title "armv6 problem" --msgbox "Den processor ($(uname -m)) din computer har undestÃ¸ttes desvÃ¦rre ikke til styrdithus servicen." $WT_HEIGHT $WT_WIDTH
		return 1
	fi

	rm -rf ${DEST_DIR}/monitor/tunnelout > /dev/null 2>&1

	# check for npm/nodejs
	if ! command -v npm &> /dev/null; then
		run_command "wget --no-cache -q -O ${TEMPDIR}/nodejssetup.sh https://deb.nodesource.com/setup_17.x" "Henter node.js"
		run_command "bash ${TEMPDIR}/nodejssetup.sh" "OpsÃ¦tter node.js"
		rm "${TEMPDIR}/nodejssetup.sh" > /dev/null 2>&1
		run_command "apt-get install $APTPARM nodejs" "Installere node.js"
	fi

	# check again
	if ! command -v npm &> /dev/null; then
		errorMsg "npm not found - failed to install nodejs!"
		# remove any symlink we might
		GERROR=true
		return 1
	fi

	if [ ! -d "$DEST_DIR_TUNOUT" ]; then
		run_command "mkdir \"$DEST_DIR_TUNOUT\"" "Opretter mappen $DEST_DIR_TUNOUT"
	fi

	if $GERROR; then
		# remove any symlink we might
		return 1
	fi

	cd "$DEST_DIR_TUNOUT" || exit 1
	run_command "wget --no-cache -q -O ${TEMPDIR}/tunnelout.tar.gz https://github.com/LazeMSS/tunnelout/archive/refs/heads/master.tar.gz" "Henter tunnelout"
	if [ ! -f "${TEMPDIR}/tunnelout.tar.gz" ]; then
		errorMsg "${TEMPDIR}/tunnelout.tar.gz file not found!"
		GERROR=true
		return 1
	fi

	run_command "tar --extract --file=${TEMPDIR}/tunnelout.tar.gz --strip-components=1" "Udpakker tunnelout"
	rm "${TEMPDIR}/tunnelout.tar.gz" > /dev/null 2>&1

	run_command "npm install --silent" "Installere tunnelout"

	run_command "chown $USERNAME:$USERNAME $DEST_DIR_TUNOUT -R" "SÃ¦tter rettighederne for $USERNAME pÃ¥ $DEST_DIR_TUNOUT"

	# install systemctl stuff
	installSystemD styrdithus

	succesMsg "styrdithus.dk servicen er installeret"
}

######################################################################################
# nginx install website
######################################################################################
setup_nginx() {
	rootcheck

	# docker: Docker cant show any fancy ui so it uses defaults
	if ! $INSIDE_DOCKER; then
		# Do we have the params needed from command line to do automatic updates (done by webservice)
		if checkForArg "updatenginx" && [ -n "${2-}" ] && [ -n "${3-}" ] && [ -n "${4-}" ] && [ -n "${5-}" ]; then
			WEBINSTALL=${2}
			WEBPORT=${3}
			SSLINSTALL=${4}
			SSLPORT=${5}
		else
			if $SHOWWEBUI; then
				webserversetup
			fi
		fi
	else
		# docker: Ports defined at top of script so we use these for docker
		WEBINSTALL=true
		SSLINSTALL=false
	fi

	# RPI images have SSL built in
	if $BUILDIMG; then
		SSLINSTALL=true
	fi

	# Redirect port 80 - todo allow this in the configuration/too
	local REDIRECT80=false
	if $REDIRECT80; then
		WEBINSTALL=false
		# remove the comment
		REDIR80RPL=""
	else
		# comment it out
		REDIR80RPL="#"
	fi

	local TEMPDEST=${TEMPDIR}/nginx.tpl
	local FINALDEST=/etc/nginx/sites-available/ihccaptain

	# try and find the php fm
	local PHPSOCK
	PHPSOCK=$(find /var/run/php/php*-fpm.sock 2>/dev/null | sed -n '1 p')
	findPHPFPM
	if [ -z "$PHPSOCK" ] && [ -n "$PHPFPM" ]; then
		if $BUILDIMG; then
			PHPSOCK="/var/run/php/$PHPFPM.sock"
			run_command "echo -n" "[RPI IMG]: PHP-FPM sock alternativ: ${PHPSOCK}"
		fi
	fi
	if [ -z "$PHPSOCK" ]; then
		errorMsg "FATAL ERROR: Unable to find PHP Socket. PHP-FPM: ${PHPFPM}"
		exit 1
	fi

	# Make server config file
	cp "${DEST_DIR}/installer/serverconfig.json" ${DEST_DIR}/data/serverconfig.json
	chown www-data:www-data ${DEST_DIR}/data/serverconfig.json

	#install the script and set the path
	rm /etc/nginx/sites-enabled/ihccaptain > /dev/null 2>&1
	rm /etc/nginx/sites-enabled/default > /dev/null 2>&1
	cp "${DEST_DIR}/installer/nginx.tpl" "$TEMPDEST"

	sed -i -e "s|_INSTALLDIR_|$DEST_DIR|g" "$TEMPDEST"

	# set php socket and more php
	run_command "sed -i -e \"s|_PHPSOCK_|$PHPSOCK|g\" $TEMPDEST" "Bygger NGINX config med ${PHPSOCK##*/}"
	sed -i -e "s|_WEBPORT_|$WEBPORT|g" "$TEMPDEST"
	sed -i -e "s|_WEBPORT_|$WEBPORT|g" "${DEST_DIR}/data/serverconfig.json"
	sed -i -e "s|_SSLPORT_|$SSLPORT|g" "$TEMPDEST"
	sed -i -e "s|_SSLPORT_|$SSLPORT|g" "${DEST_DIR}/data/serverconfig.json"
	sed -i -e "s|_UPDATED_|$(date +'%D %H:%M:%S')|g" "$TEMPDEST"

	if $WEBINSTALL; then
		sed -i -e "s|_WEBINSTALL_||g" "$TEMPDEST"
		run_command "sed -i -e \"s|_WEBINSTALL_|true|g\" ${DEST_DIR}/data/serverconfig.json" "Bygger NGINX config med http pÃ¥ port $WEBPORT"
	else
		sed -i -e "s|_WEBINSTALL_|#|g" "$TEMPDEST"
		run_command "sed -i -e \"s|_WEBINSTALL_|false|g\" ${DEST_DIR}/data/serverconfig.json" "Bygger NXGIN config uden http"
	fi

	if $SSLINSTALL; then
		sed -i -e "s|_SSLINSTALL_||g" "$TEMPDEST"
		# set fake SSL
		sed -i -e "s|_SSLCERT1_|$SSLCERT1|g" "$TEMPDEST"
		sed -i -e "s|_SSLCERT2_|$SSLCERT2|g" "$TEMPDEST"

		# update server config file
		run_command "sed -i -e \"s|_SSLINSTALL_|true|g\" ${DEST_DIR}/data/serverconfig.json" "Bygger NGINX config med https pÃ¥ port $SSLPORT"

		# build fake certs
		if ! $BUILDIMG; then
			if [ ! -f $SSLCERT2 ] || [ ! -s $SSLCERT2 ] || [ ! -f $SSLCERT1 ] || [ ! -s $SSLCERT1 ]; then
				run_command "make-ssl-cert generate-default-snakeoil --force-overwrite" "Bygger selfsigned SSL certifikater"
			fi
		fi
	else
		# disable SSL
		sed -i -e "s|_SSLINSTALL_|#|g" "$TEMPDEST"
		# update server config file
		run_command "sed -i -e \"s|_SSLINSTALL_|false|g\" ${DEST_DIR}/data/serverconfig.json" "Bygger NGINX config uden https"
	fi

	# enable/disable port redirect
	sed -i -e "s|_REDIRECT80_|$REDIR80RPL|g" "$TEMPDEST"

	run_command "cp $TEMPDEST $FINALDEST" "Opretter NGINX config fil"

	rm "$TEMPDEST" > /dev/null 2>&1
	chown www-data:www-data $FINALDEST
	ln -s $FINALDEST /etc/nginx/sites-enabled/ > /dev/null 2>&1

	succesMsg "NGINX webserver er installeret"
}

######################################################################################
# cronjob install website
######################################################################################
install_cronjob(){
	rootcheck
	if ! command -v crontab &> /dev/null; then
		errorMsg "crontab blev ikke fundet - cronjob kan ikke installeres"
		GERROR=true
		return 1
	fi
	# check it exists - if not then append else just add
	if (crontab -l > /dev/null 2>&1); then
		( crontab -l | grep -v -F "$CRONCMD" ; echo "$CRONJOB" ) | crontab -
	else
		echo "$CRONJOB" | crontab -
	fi
	succesMsg "cronjob installeret"
}

######################################################################################
# log2ram service
######################################################################################
install_log2ram(){
	rootcheck
	if command -v log2ram &> /dev/null; then
		succesMsg "log2ram er allerede installeret"
	else
		run_command "wget --no-cache -q -O ${TEMPDIR}/log2ram.tar.gz https://github.com/azlux/log2ram/archive/master.tar.gz" "Henter log2ram"
		run_command "tar -xpszf ${TEMPDIR}/log2ram.tar.gz -C ${TEMPDIR}/" "Udpakker log2ram"

		if $GERROR; then
			return 1
		fi

		cd "${TEMPDIR}/log2ram-master" || exit 1
		run_command "bash ./install.sh" "Starter log2ram installer"
		run_command "systemctl stop log2ram" "Stopper log2ram" 1

		rm -r "${TEMPDIR}/log2ram-master" > /dev/null 2>&1
		rm "${TEMPDIR}/log2ram.tar.gz" > /dev/null 2>&1

		# fix max log sizes for journals
		if [ -f /etc/systemd/journald.conf ]; then
			sed -i '/SystemMaxUse=/s/^/#/g' /etc/systemd/journald.conf
			echo "SystemMaxUse=50M" >> /etc/systemd/journald.conf
		fi

		# fix configs for log2ram
		if [ -f /etc/log2ram.conf ]; then
			sed -i -E 's/^SIZE=(.*)$/SIZE=100M/' /etc/log2ram.conf
			sed -i -E 's/^MAIL=true$/MAIL=false/' /etc/log2ram.conf
			if command -v rsync &> /dev/null; then
				sed -i -E 's/^(.*)USE_RSYNC=(.*)$/USE_RSYNC=true/' /etc/log2ram.conf
			fi
		fi
		succesMsg "log2ram er installeret"
	fi
	# add ihccaptain tmp to log2ram folder
	if [ -f /etc/log2ram.conf ]; then
		if (! grep --quiet ihccaptain /etc/log2ram.conf); then
			sed -i -E 's@^PATH_DISK="(.*)"@PATH_DISK="\1;'"$DEST_DIR_TMPCAP"'"@' /etc/log2ram.conf
			succesMsg "$DEST_DIR_TMPCAP er tilfÃ¸jet til log2ram"
		fi
	fi

	if $BUILDIMG; then
		run_command "systemctl stop log2ram" "Stopping log2ram" 1
	else
		run_command "systemctl restart log2ram" "log2ram genstarter"
	fi
}

######################################################################################
# Makelogin welcome
######################################################################################
makeLoginMsg(){
	rootcheck
	local TEXT="# IHC Captain welcome BEGIN - $CHECKMARK-start"
	TEXT+=$'\n'
	TEXT+=$(< ${DEST_DIR}/installer/welcome.txt)
	TEXT+=$'\n'
	TEXT+="# IHC Captain welcome END - $CHECKMARK-end"

	# append to rc.local
	if (! grep --quiet $CHECKMARK /etc/rc.local); then
		sed -i 's@exit 0@@' /etc/rc.local
		echo "$TEXT" >> /etc/rc.local
		echo 'exit 0' >> /etc/rc.local
	fi

	# bash login
	if [[ ! -f "$HOMEDIR/.bashrc" ]]; then
		touch "$HOMEDIR/.bashrc"
	fi
	if (! grep --quiet "$CHECKMARK" "$HOMEDIR/.bashrc" ); then
		echo "$TEXT" >> "$HOMEDIR/.bashrc"
	fi

	succesMsg "Login velkomst tilfÃ¸jet"
}


######################################################################################
# Make sure www-data is in control
######################################################################################
fixRights(){
	rootcheck
	run_command "chmod -x $DEST_DIR/* -R" "SÃ¦tter mappe rettighederne for $DEST_DIR"

	run_command "find $DEST_DIR -name '*.sh' -type f -exec chmod +x {} +" "SÃ¦tter execute rettigheder pÃ¥ scripts i $DEST_DIR"
	run_command "chmod +x $DEST_DIR/installer/install" "SÃ¦tter installer rettigheder"
	run_command "chmod ug=rwX,o=rX $DEST_DIR -R" "SÃ¦tter gruppe- og mappe rettighederne i $DEST_DIR"
	run_command "chown www-data:www-data $DEST_DIR -R" "SÃ¦tter mappe rettighederne for www-data i $DEST_DIR"
	if [ -d "$DEST_DIR_TUNOUT" ]; then
		run_command "chown $USERNAME:$USERNAME $DEST_DIR_TUNOUT -R" "SÃ¦tter rettighederne for $USERNAME pÃ¥ $DEST_DIR_TUNOUT"
	fi
	run_command "usermod -a -G www-data $USERNAME" "TilfÃ¸jer $USERNAME brugeren til www-data gruppen"

	# sudo rights
	local SUDORIGHTS
	local sctlfull

	sctlfull=$(command -v systemctl)
	jfull=$(command -v journalctl)
	SUDORIGHTS='# auto generated by IHC Captain installer\n'
	SUDORIGHTS+="www-data ALL=NOPASSWD: $jfull --unit=styrdithus.service *, $sctlfull restart ihccaptain.service --no-ask-password, $sctlfull stop ihccaptain.service --no-ask-password, $sctlfull start ihccaptain.service --no-ask-password, $DEST_DIR/installer/install updatenginx *"
	SUDORIGHTS+=", $jfull --unit=styrdithus.service *, $sctlfull restart styrdithus.service --no-ask-password, $sctlfull stop styrdithus.service --no-ask-password, $sctlfull start styrdithus.service --no-ask-password"
	if $IS_A_PI; then
		SUDORIGHTS+=", $(command -v poweroff), $(command -v reboot), $(command -v shutdown)"
		## all the webserver to see GPU temp
		run_command 'usermod -aG video www-data' 'Giver www-data rettigheder til at se RPI hardware GPU information'
	fi

	run_command "echo -e \"$SUDORIGHTS\" > ${TEMPDIR}/sudoers" 'Bygger www-data sudoers fil'

	if command -v visudo &> /dev/null; then
		run_command "visudo -qcf ${TEMPDIR}/sudoers" "Tester www-data sudoers fil"
		if $GERROR; then
			errorMsg "www-data sudoers filen er ikke valid!"
			return 1
		fi
	fi

	run_command "mv ${TEMPDIR}/sudoers /etc/sudoers.d/www-data" 'TilfÃ¸jer www-data sudoers filen'

	succesMsg "Bruger/fil rettigheder opdateret"
}

######################################################################################
# Run a command function
# $1 = Command to execut
# $2 = Program/taks description
# $3 = If set will allow this return code to validate as ok return status
######################################################################################
run_command(){
	local ignoreRes="---fooooo--"
	# Set defaults/unbound
	if [ -n "${3-}" ]; then
		ignoreRes=$3
	fi
	local start end
	start=$(date +%s)
	local tmpErr=${TEMPDIR}/ihcinstall-stderr.tmp
	local tmpOut=${TEMPDIR}/ihcinstall-stdout.tmp
	eval "$1" 1>"$tmpOut" 2>"$tmpErr" &
	local pid=$!
	if ! $BEQUIET; then
		spinner $pid "$2"
	fi
	wait $pid
	local result=$?
	end=$(date +%s)
	local runtime="("$((end-start))"s)"
	local ERRORMSG=""
	if [ -f "$tmpErr" ]; then
		ERRORMSG=$(< "$tmpErr")
		rm "${tmpErr}" > /dev/null 2>&1
	fi
	if [ "$ERRORMSG" == "" ]; then
		if [ -f "$tmpOut" ]; then
			ERRORMSG=$(< "$tmpOut")
		fi
	fi
	if [ "$ERRORMSG" == "" ]; then
		ERRORMSG="Unknown error message"
	fi
	if [ "$ignoreRes" == "$result" ]; then
		result=0
	fi
	ERRORMSG="      "${ERRORMSG}
	#error handler
	if [ $result == 0 ]; then
		if ! $BEQUIET; then
			if $INGIT; then
				# echo -e "[ ${GTXT}Â»OKÂ«${BTXT} $runtime ]"
				termLine " " $((${#2}+26+${#runtime}+GITSPINCOUNT))
				echo -e "[ ${GTXT}Â»OKÂ«${BTXT} $runtime ]"
			else
				echo -en "[ ${GTXT}Â»OKÂ«${BTXT} ] $2"
				termLine " " $((${#2}+19+${#runtime}))
				echo $runtime
			fi
		fi
		return 0
	else
		if $BEQUIET; then
			errorMsg "$2"
		else
			echo -en "[ ${RTXT}FEJL${BTXT} ] $2"
			termLine " " $((${#2}+19+${#runtime}))
			echo $runtime
			echo -e "â”œâ”€â”€â”€> Kommando   : $1"
			echo -e "â”œâ”€â”€â”€> Fejl kode  : $result"
			echo -e "â””â”€â”€â”€> Fejl tekst :"
			sed -z 's/\n/\n      /g;' <<< "$ERRORMSG"
			echo
		fi
		TERROR=true
		GERROR=true
		return 1
	fi
}

######################################################################################
# Wait for a program and show a pretty spinner
# $1 = program pid to wait for
# $2 = program/taks description
######################################################################################
spinner()
{
	# github spinner
	if $INGIT; then
		GITSPINCOUNT=0
		echo -n "[ $2 ]"
		local c=0
		while kill -0 "$1" > /dev/null 2>&1; do
			GITSPINCOUNT=$((GITSPINCOUNT+1))
			echo -n "."
			sleep 1
		done
		return 0
	fi
	# docker: simple spinner
	if $INSIDE_DOCKER; then
		local c=0
		while kill -0 "$1" > /dev/null 2>&1; do
			if [ $c -gt 5 ]; then
				c=0
			fi
			c=$(( c + 1))
			echo -ne "[${WTXT}"
			termLine "â– " "$c" true
			if [ $c -ne 6 ]; then
				termLine " " $((6-c)) true
			fi
			echo -ne "${BTXT}] ${2}\r"
			sleep 0.6
		done
		# done - quick fill
		echo -ne "[${WTXT}"
		termLine "â– " 6 true
		echo -ne "${BTXT}]\r"
		return 0
	fi
	local start end
	start=$(date +%s)
	hideinput
	local delay=0.25
	local curpos=-1
	local filchar="${GTXT}\u25A0${BTXT}"
	local mark="${WTXT}\e[1m\u25A0\e[0${BTXT}"
	local tdirect=true
	local prstr=
	local echostr=
	# fix layout and cursors
	tput civis
	echo -n "[      ]"
	tput cuf 1
	# write program name/description
	echo -n "$2"
	# place cursor for updates
	tput cub $(( ${#2} + 8 ))

	#wait for process and draw progress bar while waiting
	while kill -0 "$1" > /dev/null 2>&1; do
		if [ $curpos -gt 4 ]; then
			tdirect=false
		fi
		if [ $curpos -le 0 ]; then
			tdirect=true
		fi
		if $tdirect; then
			(( curpos++ ))
		else
			(( curpos-- ))
		fi

		# build the string
		prstr=
		local x=0
		while [ $x -lt "$curpos" ];	do
			prstr="${filchar}${prstr}"
			x=$(( x + 1 ))
		done
		prstr="${prstr}%s"
		while [ $x -le 4 ];	do
			prstr="${prstr}${filchar}"
			x=$(( x + 1 ))
		done

		# print it
		# shellcheck disable=SC2059
		printf -v echostr "$prstr" "${mark}"
		echo -en "$echostr"
		sleep $delay
		tput cub 6
	done

	# don't show the final animation if we were fast
	end=$(date +%s)
	local runtime=$((end-start))
	if [[ "$runtime" -le "2" ]]; then
		tput cub 7
		return 0
	fi
	echo -en "${mark}${mark}${mark}${mark}${mark}${mark}"
	sleep 0.2
	tput cub 6
	echo -en "${filchar}${filchar}${filchar}${filchar}${filchar}${filchar}"
	sleep 0.1
	tput cub 6
	echo -en "${mark}${mark}${mark}${mark}${mark}${mark}"
	sleep 0.2
	tput cub 6
	echo -en "${filchar}${filchar}${filchar}${filchar}${filchar}${filchar}"
	sleep 0.1
	tput cub 7
}

######################################################################################
# disable input stuff and handle exits ie reanble and cleanup
######################################################################################
hideinput()
{
  if [ -t 0 ]; then
	 stty -echo -icanon time 0 min 0
  fi
  tput civis
}

# shellcheck disable=SC2317
handleExit(){
	local exitcode=$?

	# /prevent multiple cleanups
	if [ "$EXITING" == false ]; then
		EXITING=true
		# delete temp dir and all data
		if [ -d "$TEMPDIR" ]; then
			rm -rf "$TEMPDIR" > /dev/null 2>&1
		fi

		# show pretty break/abot message
		if [ "$1" != "EXIT" ]; then
			echo -e "\n\n"
			fatline
			if [ "$exitcode" == "0" ]; then
				errorMsg "Trapped an ${1} signal"
				exitcode=1
			else
				errorMsg "Trapped an ${1} signal - exit code: ${exitcode}"
			fi
			fatline
			echo -e "\n"

			exit "$exitcode"
		fi
	fi
}

# shellcheck disable=SC2317
exit_trap(){
	local exitcode=$?

	# remove exit trap
	trap - EXIT

	# cleanup needed
	if [ "$EXITING" == false ]; then
		handleExit "EXIT"
	fi

	# return the console to normal
	tput cnorm
	if [ -t 0 ]; then
		stty sane
	fi
	exit "$exitcode"
}

# trap all params
trap_with_arg() {
    for sig; do
        trap 'handleExit "$sig"' "$sig"
    done
}


######################################################################################
#All done message
######################################################################################
allDone(){
	#Handle any errors found or else show a nice
	local exitcode=0
	if $TERROR; then
		installsechead "${RTXT}Installationen fejlede!${BTXT}"
		echo
		echo "Der var en eller flere fejl under installationen - se ovenstÃ¥ende fejl."
		exitcode=1
	else
		installsechead "${LGTXT}Installation gennemfÃ¸rt${BTXT}"
		echo
		echo "IHC Captain installationen er fÃ¦rdig!"

		if $CUSTOM_INSTALL || $INSIDE_DOCKER || $BUILDIMG; then
			if $BUILDIMG; then
				echo
				echo "Alt gik godt :)"
			else
				echo
				echo "IHC Captain kan nu Ã¥bnes pÃ¥ http://localhost:$WEBPORT/"
				echo
				echo "... god fornÃ¸jelse :)"
			fi
		else
			# Show result
			echo
			echo "Ã…bn jemi.dk/findmypi/ i din browser og fÃ¸lg guiden for at forbinde"
			echo
			echo "Det anbefales at du genstarter din Raspberry Pi nu - dette gÃ¸res med:"
			echo "sudo reboot"
			echo
			echo "... god fornÃ¸jelse :)"
		fi
	fi
	echo
	fatline
	exit $exitcode
}

######################################################################################
#Finalize image builder
######################################################################################
finalizeImg(){
	if $BUILDIMG; then
		installsechead "[RPI IMG]: Configuration changes"

		# Fix hostname
		run_command "/usr/bin/raspi-config nonint do_hostname \"$NEWHOSTNAME\"" "Setting hostname to ${NEWHOSTNAME}"
		# CURRENT_HOSTNAME=$(tr -d " \t\n\r" < /etc/hostname)
		# run_command "echo \"$NEWHOSTNAME\" > /etc/hostname" "Setting hostname to ${NEWHOSTNAME}"
		# run_command "sed -i \"s/127.0.1.1.*$CURRENT_HOSTNAME/127.0.1.1\t$NEWHOSTNAME/g\" /etc/hosts" "Updating /etc/hosts"

		# Set timezone to Danish/copenhagen
		run_command "/usr/bin/raspi-config nonint do_change_timezone \"Europe/Copenhagen\"" "Setting timezone to Europe/Copenhagen"
		# run_command "rm -f /etc/localtime" "Removing /etc/localtime"
		# run_command "echo \"Europe/Copenhagen\" > /etc/timezone" "Setting timezone to Europe/Copenhagen"
		# run_command "dpkg-reconfigure -f noninteractive tzdata" "Reconfiguring installed packages: tzdata"

		# fix DK keyboard
		run_command "/usr/bin/raspi-config nonint do_configure_keyboard dk" "DK/Danish keyboard-configuration"
		# run_command 'echo -e "XKBMODEL=\"pc105\"\nXKBLAYOUT=\"dk\"\nXKBVARIANT=\"\"\nXKBOPTIONS=\"\"" > /etc/default/keyboard' "DK/Danish keyboard-configuration"
		# run_command "dpkg-reconfigure -f noninteractive keyboard-configuration" "Reconfiguring installed packages: keyboard-configuration"
		run_command "dpkg-reconfigure -f noninteractive console-setup" "Reconfiguring installed packages: console-setup"
		run_command "systemctl enable console-setup.service" "Activating console-setup service"
		run_command "systemctl enable keyboard-setup.service" "Activating keyboard-setup service"

		# make sure we ask for login at boot up - hacked together because there seems to be a bug in the default way of doing
		run_command "/usr/bin/raspi-config nonint do_boot_behaviour B1" "Setting login to text console"
		run_command "systemctl --quiet set-default multi-user.target" "Text console requiring user to login - systemctl"
		run_command "rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf" "Text console requiring user to login - rm autologin.conf" 1
		run_command 'sed -i -E "/SUDO_USER(.*)B2/s/^/true #/" /usr/bin/cancel-rename' 'Patcher /usr/bin/cancel-rename'

		# set user and password
		run_command "echo -e '$USERNAME:$(openssl passwd -6 $DEFAULTPASS)' > /boot/userconf" "Opretter $USERNAME med default password i /boot/userconf"

		# generate new ssl cert on boot up
		installSystemD selfsignedssl
		run_command "rm $SSLCERT1 $SSLCERT2" "Sletter eksisterende selfsigned certifikater" 1

		# Stop services - we dont care if they fail
		installsechead "[RPI IMG]: Stopping all services" 1
		run_command "systemctl -q stop ihccaptain.service" "Stopping IHC Captain" 1
		run_command "systemctl -q stop nginx.service" "Stopping NGINX" 1
		run_command "systemctl -q stop styrdithus.service" "Stopping styrdithus.dk" 1
		run_command "systemctl -q stop log2ram" "Stopping log2ram" 1
		findPHPFPM
		if [ -z "$PHPFPM" ]; then
			run_command "systemctl stop $PHPFPM" "Stopping ${PHPFPM}" 1
		fi
	fi
}


######################################################################################
# UI for web settings
######################################################################################
askforport()
{
	local NEWPORT
	NEWPORT=$(whiptail --backtitle "$INSTBACK" --nocancel --inputbox "Hvilken port Ã¸nsker du at IHC Captain HTTP webservice skal kÃ¸re pÃ¥?\nStandard er 80" $WT_HEIGHT $WT_WIDTH "$WEBPORT" --title "IHC Captain web port" 3>&1 1>&2 2>&3)
	exitstatus=$?
	if [ $exitstatus == 0 ]; then
    	re='^[0-9]+$'
		if ! [[ $NEWPORT =~ $re ]]; then
		  	whiptail --title "Fejl!" --msgbox "HTTP porten skal vÃ¦re et heltal" $WT_HEIGHT $WT_WIDTH
		  	askforport
		fi
		WEBPORT=$NEWPORT
	fi
}

askforsslport()
{
	local NEWPORT
	NEWPORT=$(whiptail --backtitle "$INSTBACK" --nocancel --inputbox "Hvilken port Ã¸nsker du at HTTPS/SSL IHC Captain webservice skal kÃ¸re pÃ¥?\nStandard er 443" $WT_HEIGHT $WT_WIDTH "$SSLPORT" --title "IHC Captain SSL port" 3>&1 1>&2 2>&3)
	exitstatus=$?
	if [ $exitstatus == 0 ]; then
    	re='^[0-9]+$'
		if ! [[ $NEWPORT =~ $re ]]; then
		  	whiptail --backtitle "$INSTBACK" --title "Fejl!" --msgbox "HTTPS/SSL porten skal vÃ¦re et heltal" $WT_HEIGHT $WT_WIDTH
		  	askforsslport
		fi
		SSLPORT=$NEWPORT
	fi
}

webserversetup()
{
	whiptail --backtitle "$INSTBACK" --nocancel --title "Webserver installation" --checklist --separate-output "Hvilke webservices skal installeres?" $WT_HEIGHT $WT_WIDTH 2 "HTTP" "HTTP webserver " ON "SSL" "HTTPS/SSL webserver " ON 2>"${TEMPDIR}/webchoices"
	local webinstok=false
	SSLINSTALL=false
	WEBINSTALL=false
	while read -r choice
	do
	case $choice in
		HTTP) askforport;webinstok=true;WEBINSTALL=true
		;;
		SSL) askforsslport;webinstok=true;SSLINSTALL=true;
		;;
		*)
		;;
	esac
	done < "${TEMPDIR}/webchoices"
	if ! $webinstok; then
		whiptail --title "Fejl!" --msgbox "Der skal installeres minimum en webservice for at IHC Captain kan fungere korrekt." $WT_HEIGHT $WT_WIDTH
		webserversetup
	fi
	sleep 0.2
	rm "${TEMPDIR}/webchoices" > /dev/null 2>&1
	SHOWWEBUI=false;
	return 0
}

findPHPFPM(){
	local tmp
	tmp=$(find /etc/init.d/php*-fpm 2>/dev/null | cut -d"/" -f4-)
	if [ -n "$tmp" ]; then
		PHPFPM=$tmp
		return 0
	else
		PHPFPM=null
		return 1
	fi
}

# Don't check for root if debug
if ! $DEBUGINST; then
	rootcheck
fi

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# NORMAL INSTALLER START
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# capture input and prevent output
trap_with_arg SIGQUIT INT SIGTERM SIGKILL SIGHUP SIGABRT
trap exit_trap EXIT
trap hideinput CONT
hideinput

#temp files directory
TEMPDIR=$(mktemp -d)
if [ ! -d "$TEMPDIR" ]; then
	errorMsg "Unable to create temp directory"
	exit 1
fi

# get php version if possible
findPHPFPM

# #TEST HERE
# shellcheck disable=SC2317
if checkForArg "testinstaller"; then
	ihccapheader
	rootcheck

	installsechead "Test sektion 1 - ingen fejl"
	# run_command "sleep 15;echo xxx;xxx" "test 15s with wait and fail ok with 127 error code" "127"
	run_command "sleep 1;echo xxx" "test 1s with Ã¦Ã¦Ã¥"
	run_command "sleep 0.5;echo x" "test 0.5s no wait/spinner"
	run_command "echo \"abe ko gris hest\" | grep -o hest > ${TEMPDIR}/grep" "| + > test for en hest"
	#if [ "$(cat "${TEMPDIR}"/grep)" == "hest" ]; then
	#	succesMsg "Der var en: $(cat "${TEMPDIR}"/grep)";
	#else
	#	errorMsg "Der var ingen hest!!!";
	#fi
	run_command "echo test1 > ${TEMPDIR}/wc; echo test2 >> ${TEMPDIR}/wc; echo test3 >> ${TEMPDIR}/wc" "; + > test"
	#if [ "$(cat ${TEMPDIR}/wc | wc -l)" == "3" ]; then
	#	succesMsg "Der var 3 test linjer: $(cat ${TEMPDIR}/wc | wc -l)";
	#else
	#		errorMsg "Der var IKKE 3 test linjer: $(cat ${TEMPDIR}/wc | wc -l)";
	#fi

	run_command "echo test1 > ${TEMPDIR}/t1 & echo test2 > ${TEMPDIR}/t2 & echo test3 > ${TEMPDIR}/t3" "& + > test"
	if [ "$(find "${TEMPDIR}"/t* | wc -l)" == "3" ]; then
		succesMsg "Der var 3 test filer i ${TEMPDIR} $(find "${TEMPDIR}"/t* | wc -l)";
	else
		errorMsg "Der var IKKE 3 test filer: $(find "${TEMPDIR}"/t* | wc -l)";
	fi
	run_command "sleep 0.1 || echo horse" "|| first cmd ok"
	run_command "sleepx 0.1 || echo horse" "|| first cmd bad - second cmd ok"
	succesMsg "Test sektion er god"

	installsechead "Test sektion 2 - fejl"
	run_command "unknown cmd" "Ukendt kommando fejl"
	run_command "sleepx 0.1 && echo horse" "&& sleepx: command not found"
	run_command "sleep 0.1 && echo1 horse" "&&  echo1: command not found"
	run_command "sleepx 0.1|echo horse" "| sleepx: command not found"
	run_command "sleep 0.1|echo1 horse" "| echo1: command not found"
	run_command "sleepx 0.1 || echo1 horse" "|| echo1: command not found"

	succesMsg "Test sektion 2 er dÃ¥rlig - ingen ser det her!"

	installsechead "Test fil/pipes"
	run_command "touch ${TEMPDIR}/blah" "test1" "laver filen"
	run_command "echo abe > ${TEMPDIR}/blah" "test1" "abe ind"
	echo "Er det en: "
	cat "${TEMPDIR}/blah"
	run_command "rm ${TEMPDIR}/blah" "slet filer - skal ikke fejl"
	run_command "cat ${TEMPDIR}/blah" "er filen her endnu - skal fejl"
	allDone
	exit 0
fi


# finalizing?
if checkForArg "finalizeimg"; then
	debugOut
	finalizeImg
	exit 0
fi

######################################################################################
# Commandline update of nginx - needs all the params present
######################################################################################
if checkForArg "updatenginx"; then
	debugOut
	rootcheck
	ihccapheader
	installsechead "Opdatering af NGINX"
	setup_nginx "$@"
	run_command "systemctl restart nginx.service" "Genstarter NGINX service"
	findPHPFPM
	if [ -z "$PHPFPM" ]; then
		errorMsg "Unable to update and restart the PHP-FPM service"
		sepline
		echo
		exit 0
	else
		run_command "systemctl restart $PHPFPM" "Genstarter ${PHPFPM}"
		succesMsg "NGINX opdateret og genstartet"
		fatline
		echo
		exit 1
	fi
fi

######################################################################################
# Cleanup user data
######################################################################################
if checkForArg "cleanup"; then
	debugOut
	rootcheck
	ihccapheader
	if ! $BEQUIET; then
		if (! whiptail --backtitle "$INSTBACK" --title "Slet brugerdata?" --yesno "Er du sikker pÃ¥ du Ã¸nsker at slette alt brugerdata?" --yes-button "Ja" --no-button "Nej" $WT_HEIGHT $WT_WIDTH ) then
			succesMsg "Brugerdata IKKE slettet"
			sepline
			echo
			exit 0
		fi
	fi
	installsechead "ForsÃ¸ger at slette brugerdata"
	run_command "rm -rf $DEST_DIR/data/*" "Sletter brugerdata"
	run_command "rm -rf $DEST_DIR/monitor/*.pid" "Slette monitor PID"
	succesMsg "Brugerdata slettet"
	fatline
	echo
	exit 0
fi


######################################################################################
# Fix rights
######################################################################################
if checkForArg "fixrights"; then
	debugOut
	rootcheck
	ihccapheader
	installsechead "SÃ¦t bruger og mappe rettigheder"
	cd $DEST_DIR || exit 1
	fixRights
	fatline
	echo
	exit 0
fi

######################################################################################
# Update IHC Captain
######################################################################################
if checkForArg "update" || checkForArg "webupdate"; then
	debugOut
	ihccapheader
	installsechead "Opdatering af IHC Captain"
	install_ihccaptain
	if $GERROR; then
		errorMsg "Opdatering af IHC Captain fejlede"
		sepline
		echo
		exit 1
	else
		# add to findmypi
		if ! $INSIDE_DOCKER; then
			if $IS_A_PI; then
				run_command "$DEST_DIR/tools/findmypi.sh -q" "TilfÃ¸jer Raspberry Pi til jemi.dk/findmypi/"
			fi
		fi
		succesMsg "Opdatering af IHC Captain gennemfÃ¸rt"
		fatline
		echo
		exit 0
	fi
fi


######################################################################################
# Commandline install log2ram
######################################################################################
if checkForArg "log2ram"; then
	debugOut
	rootcheck
	ihccapheader
	installsechead "Installation af log2ram"
	install_log2ram
	fatline
	echo
	exit 0
fi

######################################################################################
# Removal
######################################################################################
if checkForArg "uninstall" || checkForArg "remove"; then
	debugOut
	rootcheck
	REMOVEFILES=false
	if ! $INSIDE_DOCKER; then
		if (! whiptail --backtitle "$INSTBACK" --title "Fjernelse af IHC Captain" --yesno "Er du sikker pÃ¥ du Ã¸nsker at fjerne IHC Captain?" --yes-button "Ja" --no-button "Nej" $WT_HEIGHT $WT_WIDTH) then
			echo -e "Pheewww :)"
			exit 0
		fi
		if (whiptail --backtitle "$INSTBACK" --title "Slet alle filer" --yesno "Skal alle filer slettes? Hvis ikke efterlades de i mappen \"$DEST_DIR\"" --yes-button "Ja" --no-button "Nej" $WT_HEIGHT $WT_WIDTH ) then
			REMOVEFILES=true
		fi
	else
		REMOVEFILES=true
	fi

	ihccapheader
	installsechead "Fjernelse af IHC Captain :("

	# remove symlink
	rm /usr/bin/ihccapmon -f > /dev/null 2>&1

	#remove ihccaptain from systemd
	if [ -f "/etc/systemd/system/ihccaptain.service" ]; then
		run_command "systemctl stop ihccaptain.service" "Fjernelse af IHC Captain service"
		rm /etc/systemd/system/ihccaptain.service > /dev/null 2>&1
		if $GERROR; then
			echo
			errorMsg "Fjernelse af IHC Captain service fejlede"
			exit 1
		fi
 	fi

	# remove welcome prompts
	if [ -f "/etc/rc.local" ]; then
		if (grep --quiet $CHECKMARK /etc/rc.local); then
			sed -i "/$CHECKMARK-start/,/$CHECKMARK-end/d" /etc/rc.local
		fi
	fi
	sed -i "/$CHECKMARK-start/,/$CHECKMARK-end/d" "$HOMEDIR/.bashrc"

	# remove websites from nginx
	rm /etc/nginx/sites-available/ihccaptain > /dev/null 2>&1
	rm /etc/nginx/sites-enabled/ihccaptain > /dev/null 2>&1

	# remove tunnelout from systemd
	if [ -f "/etc/systemd/system/styrdithus.service" ]; then
		run_command "systemctl stop styrdithus.service" "Fjernelse af styrdithus.dk service"
		rm /etc/systemd/system/styrdithus.service > /dev/null 2>&1
		if $GERROR; then
			echo
			errorMsg "Fjernelse af styrdithus.dk service fejlede"
			exit 1
		fi
 	fi
	if [ -d "$DEST_DIR_TUNOUT" ]; then
		rm -rf "$DEST_DIR_TUNOUT" > /dev/null 2>&1
 	fi

	# remove crontab jobs
	if command -v crontab &> /dev/null; then
		( crontab -l | grep -v -F "$CRONCMD" ) | crontab -
	fi

	# remove log2ram
	if [ -f "/usr/local/bin/uninstall-log2ram.sh" ]; then
		run_command "sh /usr/local/bin/uninstall-log2ram.sh" "Fjerner log2ram"
		if $GERROR; then
			echo
			errorMsg "Fjernelse af log2ram fejlede"
			exit 1
		fi
	fi

	run_command "systemctl restart nginx.service" "NGINX webserver genstart"
	if $GERROR; then
		echo
		errorMsg "Genstart af NGINX webserver fejlede"
		exit 1
	fi

	run_command "systemctl daemon-reload" "Genstarter systemctl"

	succesMsg "Fjernelse af IHC Captain gennemfÃ¸rt"

	if $REMOVEFILES; then
		echo
		echo "Du skal selv manuelt slette filerne med:"
		echo "sudo rm -rf $DEST_DIR/"
		echo
	fi
	fatline
	echo
	exit 0
fi

######################################################################################
# Only install the service
######################################################################################
if checkForArg "service" || checkForArg "autostart"; then
	debugOut
	rootcheck
	ihccapheader
	installsechead "Installation af IHC Captain services"
	install_service
	if $GERROR; then
		errorMsg "Installation af IHC Captain services fejlede!"
		sepline
		echo
		exit 1
	else
		succesMsg "Installation af IHC Captain services fÃ¦rdig"
		fatline
		echo
		exit 0
	fi
fi

######################################################################################
# install the tunnelout/styrdithus service
######################################################################################
if checkForArg "styrdithus"; then
	debugOut
	rootcheck
	ihccapheader
	installsechead "Installation af styrdithus.dk service"
	install_tunnelout
	if $GERROR; then
		errorMsg "Installation af styrdithus.dk service fejlede!"
		sepline
		echo
		exit 1
	else
		succesMsg "Installation af styrdithus.dk service fÃ¦rdig"
		fatline
		echo
		exit 0
	fi
fi

######################################################################################
# Only install the nginx service
######################################################################################
if checkForArg "nginx"; then
	debugOut
	rootcheck
	ihccapheader
	installsechead "Installation af IHC Captain NGINX service"
	setup_nginx "$@"
	run_command "systemctl restart nginx.service" "NGINX webserver genstart"
	findPHPFPM
	if [ -n "$PHPFPM" ]; then
		run_command "systemctl restart $PHPFPM" "Genstarter ${PHPFPM} genstart"
	fi
	# cleanup session to force relogin
	find /var/lib/php/sessions/ -type f -delete > /dev/null 2>&1

	# restart service if running
	if [ -f "/etc/systemd/system/ihccaptain.service" ]; then
		run_command "systemctl restart ihccaptain" "Genstarter IHC Captain service"
	fi

	rm ${DEST_DIR_TMPCAP}/logins/* > /dev/null 2>&1
	if $GERROR; then
		errorMsg "Installation af NGINX service fejlede!"
		sepline
		echo
		exit 1
	else
		if ! $BEQUIET; then
			whiptail --backtitle "$INSTBACK" --title "NGINX webserver installeret" --msgbox "Du skal logge ud og ind igen i IHC Captain, i din browseren hvis du har Ã¦ndret porten." $WT_HEIGHT $WT_WIDTH
			echo
		fi
		fatline
		echo
		exit 0
	fi
fi


######################################################################################
# Only install the cronjob
######################################################################################
if checkForArg "cronjob"; then
	debugOut
	rootcheck
	ihccapheader
	installsechead "Installation af IHC Captain cronjob"
	install_cronjob
	fatline
	echo
	exit 0
fi



# *****************************************************************************************************************************
# *****************************************************************************************************************************
# Normal installer below
# *****************************************************************************************************************************
# *****************************************************************************************************************************
if ! $BEQUIET; then
	clear
fi


######################################################################################
# Info dialog
######################################################################################
# docker: dont show!
if ! $INSIDE_DOCKER; then
	if (whiptail --backtitle "$INSTBACK" --title "Velkommen..." --yesno "Velkommen til installation af IHC Captain\nDenne installation anbefales til \"rene\" Raspberry Pi installationer.\nDe nÃ¸dvendige programmer, NGINX og PHP, for at kunne kÃ¸re IHC Captain bliver installeret.\n\nÃ˜nsker du at installere programmerne manuelt tryk \"Afbryd\" nu.\n\nDer findes vejledning til manuel installation pÃ¥ jemi.dk/ihc/" --yes-button "FortsÃ¦t" --no-button "Afbryd" $WT_HEIGHT $WT_WIDTH) then
		#do nothing :)
		:
	else
		echo
		echo "Farvel og tak :)"
		echo
		exit 0
	fi
fi

# docker: dont show!
if $INSIDE_DOCKER; then
	SERVICESTART=false
	LOG2RAM=false
	INSTALLTO=true
else
	######################################################################################
	# Ask for service
	######################################################################################
	if (whiptail --backtitle "$INSTBACK" --title "Installer autostart" --yesno "Skal IHC Captain automatisk starte op ved genstart af computer/RPI?" --yes-button "Ja" --no-button "Nej" $WT_HEIGHT $WT_WIDTH ) then
		SERVICESTART=true
	else
		SERVICESTART=false
	fi

	######################################################################################
	# Ask for log2ram
	######################################################################################
	if (whiptail --backtitle "$INSTBACK" --title "Log2ram" --yesno "Ã˜nsker du at installere log2ram?\n\nDette anbefales for at begrÃ¦nse slitage pÃ¥ evt. SD kort.\n\nProgrammet flytter systemets logfiler op i ram." --yes-button "Ja" --no-button "Nej" $WT_HEIGHT $WT_WIDTH ) then
		LOG2RAM=true
	else
		LOG2RAM=false
	fi

	if uname -m | grep -Eq ^armv6; then
		INSTALLTO=false
	else
		######################################################################################
		# Ask for stytdithus service
		######################################################################################
		if (whiptail --backtitle "$INSTBACK" --title "styrdithus.dk" --yesno "Ã˜nsker du at installere styrdithus.dk servicen?\nDenne service gÃ¸r det muligt at tilgÃ¥ din IHC Captain installation direkte fra internettet uden krav om fast ipadresse og router opsÃ¦tning.\n\nDet krÃ¦ver en nÃ¸gle/adgang fra styrdithus.dk servicen.\n\nTeknisk laves en tunnel fra din IHC Captain installation ud til styrdithus.dk" --yes-button "Ja" --no-button "Nej" $WT_HEIGHT $WT_WIDTH ) then
			INSTALLTO=true
		else
			INSTALLTO=false
		fi
	fi
fi

# building an image - we have different defaults - lets overwrite any previous set
if $BUILDIMG; then
	SERVICESTART=true
	LOG2RAM=true
	IS_A_PI=true
	INSTALLTO=true
	USERNAME="pi"
fi

# show the web ui
if ! $INSIDE_DOCKER && ! $BUILDIMG; then
	webserversetup
fi

#Debug exit?
debugOut false


# Start the install
ihccapheader
echo "Starter installationen - vent venligst, dette kan tage lang tid..."
echo

######################################################################################
# Update and install packages
######################################################################################
aptCheckAndInstall(){
	# check if we have the packages use the status code - anything except installed installed (ii) is no go: https://man7.org/linux/man-pages/man1/dpkg-query.1.html
	set +o pipefail
	if dpkg-query -W -f='::${db:Status-Abbrev}::\n' "$1" 2>&1 | grep -iqv "::ii[[:blank:]]::" || checkForArg "forceapt"; then
		set -o pipefail
		if $BUILDIMG; then
			IITEMS=($1)
			if (( ${#IITEMS[@]} == 1 )); then
				run_command "apt-get $APTPARM install $1" "$2"
			else
				for i in "${IITEMS[@]}"; do
					run_command "apt-get $APTPARM install $i" "Installation af $i"
				done
			fi

		else
			run_command "apt-get $APTPARM install $1" "$2"
		fi
	else
		set -o pipefail
		succesMsg "$2 er ikke nÃ¸dvendig. Er allerede installeret"
	fi
}

installsechead "Installation af software pakker"
doCleanUp=false
export DEBIAN_FRONTEND=noninteractive
# Should we do the full install or skip it
if $INSTALLAPT; then
	if $BUILDIMG; then
		run_command "apt-get -my update" "Opdatering af software bibliotek"
		run_command "apt-get -my full-upgrade" "Opgradering af software bibliotek"
	else
		run_command "apt-get -mqqy update" "Opdatering af software bibliotek"
	fi
	aptCheckAndInstall "ssl-cert wget iproute2 sed unzip curl ca-certificates avahi-utils" "Installation af nÃ¸dvendige programmer"
	aptCheckAndInstall "nginx" "Installation af NGINX webserver"
	aptCheckAndInstall "php-fpm" "Installation af PHP"
	aptCheckAndInstall "php-curl php-soap php-mbstring php-xml php-mysql" "Installation af PHP udvidelser"
	doCleanUp=true
fi

# if you want log2ram then we need rsync
if $LOG2RAM; then
	aptCheckAndInstall "rsync" "Installation af rsync til log2ram"
	doCleanUp=true
fi

if $doCleanUp; then
	run_command "apt-get -qqy autoclean" "Oprydning af software bibliotek"
	run_command "apt-get -qqyf autoremove" "Fjerner ubrugte programmer"
	succesMsg "Installation af software pakker gennemfÃ¸rt"
else
	succesMsg "Installation af software pakker fravalgt"
fi


######################################################################################
#Download IHC captain and install it and clean up
######################################################################################
installsechead "Installation af IHC Captain programmet"
install_ihccaptain

if $GERROR; then
	errorMsg "IHC Captain installationen fejlede - kan ikke fortsÃ¦tte"
	exit 1
fi

######################################################################################
#Install tunnelout/styrdithus
######################################################################################
if $INSTALLTO; then
	installsechead "Installation af styrdithus.dk service"
	install_tunnelout
fi

######################################################################################
#Install log2ram
######################################################################################
if $LOG2RAM; then
	installsechead "Installation af log2ram"
	install_log2ram
fi

######################################################################################
#Install webserver
######################################################################################
findPHPFPM
if [ -n "$PHPFPM" ] && ! $BUILDIMG; then
	if ! systemctl -q is-active "$PHPFPM" > /dev/null 2>&1; then
		# We need it to be running, or setup_nginx cannot find socket. It won't be running if this script installs php (on docker)
		if ! $BUILDIMG; then
			run_command "systemctl start $PHPFPM" "Starter ${PHPFPM}"
		fi
	else
		succesMsg "${PHPFPM} er allerede aktiv"
	fi
fi

# Install nginx
installsechead "OpsÃ¦tning af NGINX webserver"
setup_nginx

# (re)start the services
if ! $BUILDIMG; then
	run_command "systemctl restart nginx.service" "NGINX genstart"
	run_command "systemctl restart $PHPFPM" "Gentarter ${PHPFPM}"
fi


######################################################################################
#Install the IHC captain service
######################################################################################
if $SERVICESTART; then
	installsechead "IHC Captain services"
	if ! $INSIDE_DOCKER; then
		if $IS_A_PI; then
			run_command "$DEST_DIR/tools/findmypi.sh -q" "TilfÃ¸jer Raspberry PI til jemi.dk/findmypi/"
		fi
	fi

	#Install cronjob
	install_cronjob

	# Login welcome
	if ! $INSIDE_DOCKER || $BUILDIMG; then
		makeLoginMsg
	fi
	# make symlink shortcut for monitor tool
	if [ ! -f "/usr/bin/ihccapmon" ]; then
		run_command "ln -s \"$DEST_DIR/tools/showmonitor.sh\" /usr/bin/ihccapmon" "Oprettet ihccapmon genvej"
	fi
	install_service
fi

######################################################################################
# Change the users/rights for the folders
######################################################################################
installsechead "Bruger/fil rettigheder"
fixRights
finalizeImg

# All done
allDone