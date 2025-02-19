#!/bin/sh

## @file
## @brief Download, compile, and install Geeqie on Debian-based systems.
##
## If run from a folder that already contains the Geeqie sources, the source
## code will be updated from the repository.
## Dialogs allow the user to install additional features.
##

version="2022-04-09"
description='
Geeqie is an image viewer.
This script will download, compile, and install Geeqie on Debian-based systems.
If run from a folder that already contains the Geeqie sources, the source
code will be updated from the repository.
Dialogs allow the user to install additional features.

Command line options are:
-v --version The version of this file
-h --help Output this text
-c --commit=ID Checkout and compile commit ID
-t --tag=TAG Checkout and compile TAG (e.g. v1.4 or v1.3)
-b --back=N Checkout commit -N (e.g. "-b 1" for last-but-one commit)
-l --list List required dependencies
-d --debug=yes Compile with debug output
'

# Essential for compiling
essential_array="git
build-essential
autoconf
libglib2.0-0
intltool
libtool
yelp-tools"

# Optional for both GTK2 and GTK3
optional_array="LCMS (for color management)
liblcms2-dev
exiv2 (for exif handling)
libgexiv2-dev
lua (for --remote commands)
liblua5.1-0-dev
libffmpegthumbnailer (for mpeg thumbnails)
libffmpegthumbnailer-dev
libtiff (for tiff support)
libtiff-dev
libjpeg (for jpeg support)
libjpeg-dev
librsvg2 (for viewing .svg images)
librsvg2-common
libwmf (for viewing .wmf images)
libwmf0.2-7-gtk
exiftran (for image rotation)
exiftran
imagemagick (for image rotation)
imagemagick
exiv2 command line (for jpeg export)
exiv2
jpgicc (for jpeg export color correction)
liblcms2-utils
pandoc (for generating README help file)
pandoc
gphoto2 (for tethered photography and camera download plugins)
gphoto2
libimage-exiftool-perl (for jpeg extraction plugin)
libimage-exiftool-perl
libheif (for HEIF support)
libheif-dev
libwebp (for WebP images)
libwebp-dev
libdjvulibre (for DjVu images)
libdjvulibre-dev
libopenjp2 (for JP2 images)
libopenjp2-7-dev
libraw (for CR3 images)
libraw-dev
libomp (required by libraw)
libomp-dev
libarchive (for compressed files e.g. zip, including timezone)
libarchive-dev"

# Optional for GTK3 only
optional_gtk3_array="libchamplain gtk (for GPS maps)
libchamplain-gtk-0.12-dev
libchamplain (for GPS maps)
libchamplain-0.12-dev
libpoppler (for pdf file preview)
libpoppler-glib-dev
libgspell (for spelling checks)
libgspell-1-dev"

####################################################################
# Get System Info
# Derived from: https://github.com/coto/server-easy-install (GPL)
####################################################################
lowercase()
{
	printf '%b\n' "$1" | sed "y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/"
}

systemProfile()
{
	OS="$(lowercase "$(uname)")"
	KERNEL=$(uname -r)
	MACH=$(uname -m)

	if [ "${OS}" = "windowsnt" ]
	then
		OS=windows
	elif [ "${OS}" = "darwin" ]
	then
		OS=mac
	else
		OS=$(uname)
		if [ "${OS}" = "SunOS" ]
		then
			OS=Solaris
			ARCH=$(uname -p)
			OSSTR="${OS} ${REV}(${ARCH} $(uname -v))"
		elif [ "${OS}" = "AIX" ]
		then
			# shellcheck disable=SC2034
			OSSTR="${OS} $(oslevel) ($(oslevel -r))"
		elif [ "${OS}" = "Linux" ]
		then
			if [ -f /etc/redhat-release ]
			then
				DistroBasedOn='RedHat'
				DIST=$(sed s/\ release.*// /etc/redhat-release)
				PSUEDONAME=$(sed s/.*\(// /etc/redhat-release | sed s/\)//)
				REV=$(sed s/.*release\ // /etc/redhat-release | sed s/\ .*//)
			elif [ -f /etc/SuSE-release ]
			then
				DistroBasedOn='SuSe'
				PSUEDONAME=$(tr "\n" ' ' < /etc/SuSE-release | sed s/VERSION.*//)
				REV=$(tr "\n" ' ' < /etc/SuSE-release | sed s/.*=\ //)
			elif [ -f /etc/mandrake-release ]
			then
				DistroBasedOn='Mandrake'
				PSUEDONAME=$(sed s/.*\(// /etc/mandrake-release | sed s/\)//)
				REV=$(cat | sed s/.*release\ // /etc/mandrake-release | sed s/\ .*//)
			elif [ -f /etc/debian_version ]
			then
				DistroBasedOn='Debian'
				if [ -f /etc/lsb-release ]
				then
					DIST=$(grep '^DISTRIB_ID' /etc/lsb-release | awk -F= '{ print $2 }')
					PSUEDONAME=$(grep '^DISTRIB_CODENAME' /etc/lsb-release | awk -F= '{ print $2 }')
					REV=$(grep '^DISTRIB_RELEASE' /etc/lsb-release | awk -F= '{ print $2 }')
				fi
			fi
			if [ -f /etc/UnitedLinux-release ]
			then
				DIST="${DIST}[$(tr "\n" ' ' < /etc/UnitedLinux-release | sed s/VERSION.*//)]"
			fi
			OS=$(lowercase $OS)
			DistroBasedOn=$(lowercase $DistroBasedOn)
			readonly OS
			readonly DIST
			readonly DistroBasedOn
			readonly PSUEDONAME
			readonly REV
			readonly KERNEL
			readonly MACH
		fi
	fi
}

install_essential()
{
	i=0

	for file in $essential_array
	do
		if [ $((i % 2)) -ne 0 ]
		then
			if package_query "$file"
			then
				package_install "$file"
			fi
		fi

		i=$((i + 1))
	done

	if [ "$1" = "GTK3" ]
	then
		if package_query "libgtk-3-dev"
		then
			package_install libgtk-3-dev
		fi
	else
		if package_query "libgtk2.0-dev"
		then
			package_install libgtk2.0-dev
		fi
	fi
}

install_options()
{
	if [ -n "$options" ]
	then
		OLDIFS=$IFS
		IFS='|'
		set "$options"
		while [ $# -gt 0 ]
		do
			package_install "$1"
			shift
		done
		IFS=$OLDIFS
	fi
}

uninstall()
{
	current_dir="$(basename "$PWD")"
	if [ "$current_dir" = "geeqie" ]
	then

		sudo --askpass make uninstall

		if ! zenity --title="Uninstall Geeqie" --width=370 --text="WARNING.\nThis will delete folder:\n\n$PWD\n\nand all sub-folders!" --question --ok-label="Cancel" --cancel-label="OK" 2> /dev/null
		then
			cd ..
			sudo --askpass rm -rf geeqie
		fi
	else
		zenity --title="Uninstall Geeqie" --width=370 --text="This is not a geeqie installation folder!\n\n$PWD" --warning 2> /dev/null
	fi

	exit_install
}

package_query()
{
	if [ "$DistroBasedOn" = "debian" ]
	then

		# shellcheck disable=SC2086
		res=$(dpkg-query --show --showformat='${Status}' "$1" 2>> $install_log)
		if [ "${res}" = "install ok installed" ]
		then
			status=1
		else
			status=0
		fi
	fi
	return $status
}

package_install()
{
	if [ "$DistroBasedOn" = "debian" ]
	then
		# shellcheck disable=SC2024
		sudo --askpass apt-get --assume-yes install "$@" >> "$install_log" 2>&1
	fi
}

exit_install()
{
	rm "$install_pass_script" > /dev/null 2>&1

	if [ -p "$zen_pipe" ]
	then
		printf '%b\n' "100" > "$zen_pipe"
		printf '%b\n' "#End" > "$zen_pipe"
	fi

	zenity --title="$title" --width=370 --text="Geeqie is not installed\nLog file: $install_log" --info 2> /dev/null

	rm "$zen_pipe" > /dev/null 2>&1

	exit 1
}

# Entry point

IFS='
'

# If uninstall has been run, maybe the current directory no longer exists
if [ ! -d "$PWD" ]
then
	zenity --error --title="Install Geeqie and dependencies" --width=370 --text="Folder $PWD does not exist!" 2> /dev/null

	exit
fi

# Check system type
systemProfile
if [ "$DistroBasedOn" != "debian" ]
then
	zenity --error --title="Install Geeqie and dependencies" --width=370 --text="Unknown operating system:\n
Operating System: $OS
Distribution: $DIST
Psuedoname: $PSUEDONAME
Revision: $REV
DistroBasedOn: $DistroBasedOn
Kernel: $KERNEL
Machine: $MACH" 2> /dev/null

	exit
fi

# Parse the command line
OPTS=$(getopt -o vhc:t:b:ld: --long version,help,commit:,tag:,back:,list,debug: -- "$@")
eval set -- "$OPTS"

while true
do
	case "$1" in
		-v | --version)
			printf '%b\n' "$version"
			exit
			;;
		-h | --help)
			printf '%b\n' "$description"
			exit
			;;
		-c | --commit)
			COMMIT="$2"
			shift
			shift
			;;
		-t | --tag)
			TAG="$2"
			shift
			shift
			;;
		-b | --back)
			BACK="$2"
			shift
			shift
			;;
		-l | --list)
			LIST="$2"
			shift
			shift
			;;
		-d | --debug)
			DEBUG="$2"
			shift
			shift
			;;
		*)
			break
			;;
	esac
done

if [ "$LIST" ]
then
	printf '%b\n' "Essential libraries:"
	for file in $essential_array
	do
		printf '%b\n' "$file"
	done

	printf '\n'
	printf '%b\n' "Optional libraries:"
	for file in $optional_array
	do
		printf '%b\n' "$file"
	done

	printf '\n'
	printf '%b\n' "Optional for GTK3:"
	for file in $optional_gtk3_array
	do
		printf '%b\n' "$file"
	done

	exit
fi

# If a Geeqie folder already exists here, warn the user
if [ -d "geeqie" ]
then
	zenity --info --title="Install Geeqie and dependencies" --width=370 --text="This script is for use on Ubuntu and other\nDebian-based installations.\nIt will download, compile, and install Geeqie source\ncode and its dependencies.\n\nA sub-folder named \"geeqie\" will be created in the\nfolder this script is run from, and the source code\nwill be downloaded to that sub-folder.\n\nA sub-folder of that name already exists.\nPlease try another folder." 2> /dev/null

	exit
fi

# If it looks like a Geeqie download folder, assume an update
if [ -d ".git" ] && [ -d "src" ] && [ -f "geeqie.1" ]
then
	mode="update"
else
	# If it looks like something else is already installed here, warn the user
	if [ -d ".git" ] || [ -d "src" ]
	then
		zenity --info --title="Install Geeqie and dependencies" --width=370 --text="This script is for use on Ubuntu and other\nDebian-based installations.\nIt will download, compile, and install Geeqie source\ncode and its dependencies.\n\nIt looks like you are running this script from a folder which already has software installed.\n\nPlease try another folder." 2> /dev/null

		exit
	else
		mode="install"
	fi
fi

# Use GTK3 as default
gtk2_installed=FALSE
gtk3_installed=TRUE

if [ "$mode" = "install" ]
then
	message="This script is for use on Ubuntu and other\nDebian-based installations.\nIt will download, compile, and install Geeqie source\ncode and its dependencies.\n\nA sub-folder named \"geeqie\" will be created in the\nfolder this script is run from, and the source code\nwill be downloaded to that sub-folder.\n\nIn this dialog you must select whether to compile\nfor GTK2 or GTK3.\nIf you want to use GPS maps or pdf preview,\nyou must choose GTK3.\nThe GTK2 version has a slightly different\nlook-and-feel compared to the GTK3 version,\nbut otherwise has the same features.\nYou may easily switch between the two after\ninstallation.\n\nIn subsequent dialogs you may choose which\noptional features to install."

	title="Install Geeqie and dependencies"
	install_option=TRUE
else
	message="This script is for use on Ubuntu and other\nDebian-based installations.\nIt will update the Geeqie source code and its\ndependencies, and will compile and install Geeqie.\n\nYou may also switch the installed version from\nGTK2 to GTK3 and vice versa.\n\nIn this dialog you must select whether to compile\nfor GTK2 or GTK3.\nIf you want to use GPS maps or pdf preview,\nyou must choose GTK3.\nThe GTK2 version has a slightly different\nlook-and-feel compared to the GTK3 version,\nbut otherwise has the same features.\n\nIn subsequent dialogs you may choose which\noptional features to install."

	title="Update Geeqie and re-install"
	install_option=FALSE

	# When updating, use previous installation as default
	if [ -f config.log ]
	then
		if grep gtk-2.0 config.log > /dev/null
		then
			gtk2_installed=TRUE
			gtk3_installed=FALSE
		else
			gtk2_installed=FALSE
			gtk3_installed=TRUE
		fi
	fi
fi

# Ask whether to install GTK2 or GTK3 or uninstall

if ! gtk_version=$(zenity --title="$title" --width=370 --text="$message" --list --radiolist --column "" --column "" "$gtk3_installed" "GTK3 (required for GPS maps and pdf preview)" "$gtk2_installed" "GTK2" FALSE "Uninstall" --cancel-label="Cancel" --ok-label="OK" --hide-header 2> /dev/null)
then
	exit
fi

# Environment variable SUDO_ASKPASS cannot be "zenity --password",
# so create a temporary script containing the command
install_pass_script=$(mktemp "${TMPDIR:-/tmp}/geeqie.XXXXXXXXXX")
printf '%b\n' "#!/bin/sh
if zenity --password --title=\"$title\" --width=370 2>/dev/null
then
	exit 1
fi" > "$install_pass_script"
chmod +x "$install_pass_script"
export SUDO_ASKPASS=$install_pass_script

if [ "$gtk_version" = "Uninstall" ]
then
	uninstall
	exit
fi

# Put the install log in tmp, to avoid writing to PWD during a new install
rm install.log 2> /dev/null
install_log=$(mktemp "${TMPDIR:-/tmp}/geeqie.XXXXXXXXXX")

sleep 100 | zenity --title="$title" --text="Checking for installed files" --width=370 --progress --pulsate 2> /dev/null &
zen_pid=$!

# Get the standard options that are not yet installed
i=0
for file in $optional_array
do
	if [ $((i % 2)) -eq 0 ]
	then
		package_title="$file"
	else
		if package_query "$file"
		then
			if [ -z "$option_string" ]
			then
				option_string="${install_option:+${install_option}}\n${file}\n${file}"
			else
				option_string="${option_string:+${option_string}}\n$install_option\n${package_title}\n${file}"
			fi
		fi
	fi
	i=$((i + 1))
done

# If GTK3 required, get the GTK3 options not yet installed
if [ -z "${gtk_version%%GTK3*}" ]
then
	i=0
	for file in $optional_gtk3_array
	do
		if [ $((i % 2)) -eq 0 ]
		then
			package_title="$file"
		else
			if package_query "$file"
			then
				if [ -z "$option_string" ]
				then
					option_string="${install_option:+${install_option}}\n${file}\n${file}"
				else
					option_string="${option_string:+${option_string}}\n$install_option\n${package_title}\n${file}"
				fi
			fi
		fi
		i=$((i + 1))
	done
fi

kill $zen_pid 2> /dev/null

# Ask the user which options to install
if [ -n "$option_string" ]
then
	if ! options=$(printf '%b\n' "$option_string" | zenity --title="$title" --width=400 --height=500 --list --checklist --text 'Select which library files to install:' --column='Select' --column='Library files' --column='Library' --hide-column=3 --print-column=3 2> /dev/null)
	then
		exit_install
	fi
fi

# Start of Zenity progress section
zen_pipe=$(mktemp -u "${TMPDIR:-/tmp}/geeqie.XXXXXXXXXX")
mkfifo "$zen_pipe"
(tail -f "$zen_pipe" 2> /dev/null) | zenity --progress --title="$title" --width=370 --text="Installing options..." --auto-close --auto-kill --percentage=0 2> /dev/null &

printf '%b\n' "2" > "$zen_pipe"
printf '%b\n' "#Installing essential libraries..." > "$zen_pipe"

install_essential "$gtk_version"

printf '%b\n' "4" > "$zen_pipe"
printf '%b\n' "#Installing options..." > "$zen_pipe"

install_options

printf '%b\n' "6" > "$zen_pipe"
printf '%b\n' "#Installing extra loaders..." > "$zen_pipe"

printf '%b\n' "10" > "$zen_pipe"
printf '%b\n' "#Getting new sources from server..." > "$zen_pipe"

if [ "$mode" = "install" ]
then
	if ! git clone git://geeqie.org/geeqie.git >> "$install_log" 2>&1
	then
		git_error=$(tail -n5 "$install_log" 2>&1)
		zenity --title="$title" --width=370 --height=400 --error --text="Git error:\n\n$git_error" 2> /dev/null
		exit_install
	fi
else
	if ! git checkout master >> "$install_log" 2>&1
	then
		git_error="$(tail -n25 "$install_log" 2>&1)"
		zenity --title="$title" --width=370 --height=400 --error --text="Git error:\n\n$git_error" 2> /dev/null
		exit_install
	fi
	if ! git pull >> "$install_log" 2>&1
	then
		git_error=$(tail -n5 "$install_log" 2>&1)
		zenity --title="$title" --width=370 --height=400 --error --text="Git error:\n\n$git_error" 2> /dev/null
		exit_install
	fi
fi

printf '%b\n' "20" > "$zen_pipe"
printf '%b\n' "#Cleaning installed version..." > "$zen_pipe"

if [ $mode = "install" ]
then
	cd geeqie || exit 1
else
	# shellcheck disable=SC2024
	sudo --askpass make uninstall >> "$install_log" 2>&1
	# shellcheck disable=SC2024
	sudo --askpass make maintainer-clean >> "$install_log" 2>&1
fi

printf '%b\n' "30" > "$zen_pipe"
printf '%b\n' "#Checkout required version..." > "$zen_pipe"

if [ "$BACK" ]
then
	if ! git checkout master~"$BACK" >> "$install_log" 2>&1
	then
		git_error=$(tail -n5 "$install_log" 2>&1)
		zenity --title="$title" --width=370 --height=400 --error --text="Git error:\n\n$git_error" 2> /dev/null
		exit_install
	fi
elif [ "$COMMIT" ]
then

	if ! git checkout "$COMMIT" >> "$install_log" 2>&1
	then
		git_error=$(tail -n5 "$install_log" 2>&1)
		zenity --title="$title" --width=370 --height=400 --error --text="Git error:\n\n$git_error" 2> /dev/null
		exit_install
	fi
elif [ "$TAG" ]
then
	if ! git checkout "$TAG" >> "$install_log" 2>&1
	then
		git_error=$(tail -n5 "$install_log" 2>&1)
		zenity --title="$title" --width=370 --height=400 --error --text="Git error:\n\n$git_error" 2> /dev/null
		exit_install
		exit
	fi
fi
if [ "$DEBUG" = "yes" ]
then
	debug_opt=""
else
	debug_opt="--disable-debug-log"
fi

printf '%b\n' "40" > "$zen_pipe"
printf '%b\n' "#Creating configuration files..." > "$zen_pipe"

if [ -z "${gtk_version%%GTK3*}" ]
then
	./autogen.sh "$debug_opt" >> "$install_log" 2>&1
else
	./autogen.sh "$debug_opt" --disable-gtk3 >> "$install_log" 2>&1
fi

printf '%b\n' "60" > "$zen_pipe"
printf '%b\n' "#Compiling..." > "$zen_pipe"

export CFLAGS=$CFLAGS" -Wno-deprecated-declarations"
export CXXFLAGS=$CXXFLAGS" -Wno-deprecated-declarations"

if ! make -j >> "$install_log" 2>&1
then
	zenity --title="$title" --width=370 --height=400 --error --text="Compile error" 2> /dev/null
	exit_install
	exit
fi

printf '%b\n' "90 " > "$zen_pipe"
printf '%b\n' "#Installing Geeqie..." > "$zen_pipe"

# shellcheck disable=SC2024
sudo --askpass make install >> "$install_log" 2>&1

rm "$install_pass_script"
mv -f "$install_log" install.log

printf '%b\n' "100 " > "$zen_pipe"
rm "$zen_pipe"

(for i in $(seq 0 4 100)
do
	printf '%b\n' "$i"
	sleep 0.1
done) | zenity --progress --title="$title" --width=370 --text="Geeqie installation complete...\n" --auto-close --percentage=0 2> /dev/null

exit
