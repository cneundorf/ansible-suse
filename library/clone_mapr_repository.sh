#!/bin/bash
#
#	Simple script to clone MapR repository
#
#	usage: clone_mapr_repository.sh <http_src>  <<version or 'ecosystem'> [ <dst_path> ]
#
#		The default destination path is the HTTP Server data directory
#		(even if the HTTP service is not installed)
#
#	examples:
#		clone_mapr_repository.sh http://package.mapr.com/releases 3.1.1
#		clone_mapr_repository.sh http://apt.qa.lab 4.0.2
#
# Very limited error checking done.  
#
# Assumes that the necessary repository
# tools are in place
#	Debian
#		apt-get install -y apache2		# leaves service configured
#
#		service apache2 status
#
#	CentOS
#		yum install -y httpd
#		yum install -y createrepo
#
#		service httpd status
#

PROGNAME=${0}
#	Ansbile Integration: if $1 is passed in, we assume it is the 
#	ansible argument passing logic (a dump of key-value pairs).  
#	This sed expression parses it out.
#		No, I'm not that good a sed programmer; found this example
#		on the Ansible web site.	DBT  30-Oct-2013

if [ -n "${1}"  -a  -f "${1}" ] ; then
	eval $(sed -e "s/\s?\([^=]+\)\s?=\s?\(\x22\([^\x22]+\)\x22|\x27\([^\x27]+\)\x27|\(\S+\)\)\s?/\1='\2'/p" $1)
	ANSIBLE_PARENT=1
else
  REPO_URL=${1}
	REPO_ARG=${2}
	LOCAL_REPO_PATH=${3}
	echo ""
fi


# Helper functions for exiting properly for Ansible
#	exitSucess <msg>   # eg ansible_exit "OK"
#	ansible_fail <msg>   # eg ansible_exit "Unable to create <foo>"
#
function exitSuccess() {
	if [ -n ${ANSIBLE_PARENT} ] ; then
		echo "{\"changed\":true, \"msg\":\"$1\"}"
	else
		echo "$1"
	fi
	exit 0
}

function exitFailure() {
	if [ -n ${ANSIBLE_PARENT} ] ; then
		echo "{\"failed\":true, \"msg\":\"$1\"}"
		exit 0
	else
		echo "$1"
		exit 1
	fi
}


function usage() {
	echo "usage: $PROGNAME <MapR_Package_TOP>  < MapR_version | \"ecosystem\" >"
	echo "  example: $PROGNAME  http://package.mapr.com/releases  3.1.0"
	echo "           $PROGNAME  http://package.mapr.com/releases  ecosystem"
}

createDebianRepository()
{
    DIR=$1
    
    mkdir -p $DIR/binary
    mkdir -p $DIR/dists/binary/binary-all

    cat > $DIR/apt-binary-release.conf <<EOM
APT::FTPArchive::Release::Origin "MapR Techonologies, Inc.";
APT::FTPArchive::Release::Label "MapR Techonologies, Inc.";
APT::FTPArchive::Release::Suite "stable";
APT::FTPArchive::Release::Codename "binary";
APT::FTPArchive::Release::Architectures "all";
APT::FTPArchive::Release::Components "binary";
APT::FTPArchive::Release::Description "MapR Techonologies, Inc.";
EOM

    cat > $DIR/apt-ftparchive.conf <<EOM
Dir {
  ArchiveDir ".";
  CacheDir ".";
};

Default {
  Packages::Compress ". gzip bzip2";
  Contents::Compress "gzip bzip2";
};

BinDirectory "dists" {
  Packages "binary/Packages";
  Contents "binary/Contents-all";
};

Tree "dists" {
  Sections "binary";
  Architectures "all";
};

Default {
  Packages {
    Extensions ".deb";
  };
};
EOM

    cat > $DIR/dists/Release <<EOM
Architectures: all
Codename: binary
Components: binary
Date: $(date)
Description: MapR Techonologies, Inc.
Label: MapR Techonologies, Inc.
Origin: MapR Techonologies, Inc.
Suite: stable
EOM
}


#
# At the top-level of the Debian repository
# create the indexing script 
#
# $1 - the pathname of where the Debian 
#      repository was to be created.
createDebianArchiveScript()
{
    DIR=$1/$REPO

    cd $DIR

    cat > $DIR/update-archive.sh <<EOM
#!/bin/bash -x

cd $DIR

apt-ftparchive generate apt-ftparchive.conf
apt-ftparchive -c apt-binary-release.conf release dists/binary >dists/Release

EOM
    chmod 755 update-archive.sh
}



# Set up for different distribution.  We'll use "package.mapr.com",
# since that is guaranteed to have the tarballs with all the packages.
#
echo "${REPO_ARG}" | grep -q "^[1-9]"
if [ $? -eq 0 ] ; then
	REPO_TOP="${REPO_URL}/v${REPO_ARG}"
elif [ $REPO_ARG = "ecosystem" ] ; then
	REPO_TOP="${REPO_URL}/ecosystem"
else
	usage
	echo ""
	exitFailure "Error: unrecognized repo specification ($REPO_ARG)"
fi

# TO BE DONE: check for SUSE zypper as well
if which dpkg &> /dev/null ; then
	REPO_TOP=${REPO_TOP}/ubuntu
	HTTPD_TOP=/var/www
	THIS_DISTRO=Debian
elif which rpm &> /dev/null ; then
	REPO_TOP=${REPO_TOP}/redhat
	HTTPD_TOP=/var/www/html
	THIS_DISTRO=RedHat
else
	exitFailure "Error: unrecognized Linux system; unable to create local repository"
fi

# Make sure we have a location for the repository 
#	Default: the HTTPD_TOP directory for the distribution
#
if [ -z "${LOCAL_REPO_PATH}" ] ; then
	LOCAL_REPO_PATH=$HTTPD_TOP/mapr/`basename ${REPO_TOP%/*}`
	if [ ! -d $HTTPD_TOP ] ; then
		echo "!!! Warning !!!  Defaulting to HTTPD data directory for repository location,"
		echo "!!! Warning !!!  but $HTTPD_TOP directory does not yet exist."
		echo "!!! Warning !!!  Please install the HTTP service on this node."
	fi
fi
if [ ! -d $LOCAL_REPO_PATH ] ; then
	mkdir -p $LOCAL_REPO_PATH
	if [ $? -ne 0 ] ; then
		echo "Error: Could not create local repository path ($LOCAL_REPO_PATH)"
		echo "Verify permissions and try again"
		exit 1
	fi
fi
if [ ! -d $LOCAL_REPO_PATH ] ; then
	exitFailure "Error: Could not locate local repository path ($LOCAL_REPO_PATH)"
fi


pkg=`curl $REPO_TOP/ 2> /dev/null | grep -e "\.tgz" | cut -d\" -f8`
if [ -z "${pkg}" ] ; then
	exitFailure "Error: No packages found in $REPO_TOP/"
fi

REPO_TARBALL=${REPO_TOP}/$pkg
echo "Info: Downloading $REPO_TARBALL to /tmp"
echo "Info: 	(will display curl status-bar)"
echo ""

#	For debug, only download if it's not already there
if [ ! -r /tmp/$pkg ] ; then
	curl $REPO_TARBALL -o /tmp/$pkg
	if [ $? -ne 0 ] ; then
		exitFailure "Error: Failed to download $REPO_TARBALL to /tmp/$pkg"
	fi
fi

#	TO BE DONE: be smarter here about overwriting files

if [ $THIS_DISTRO = "RedHat" ] ; then
	echo "Info: Extracting packages to $LOCAL_REPO_PATH"
	echo ""
	tar x -C $LOCAL_REPO_PATH -f /tmp/$pkg
	if [ $? -ne 0 ] ; then
		exitFailure "Error: Extraction of $pkg to $LOCAL_REPO_PATH failed"
	fi

	echo "Info: Generating repository artifacts"
	echo ""
	createrepo $LOCAL_REPO_PATH
	echo ""
elif [ $THIS_DISTRO = "Debian" ] ; then
	createDebianRepository     "$LOCAL_REPO_PATH"
	createDebianArchiveScript  "$LOCAL_REPO_PATH"

	echo "Info: Extracting packages to $LOCAL_REPO_PATH/dists/binary"
	echo ""
	tar x -C $LOCAL_REPO_PATH/dists/binary -f /tmp/$pkg
	if [ $? -ne 0 ] ; then
		exitFailure "Error: Extraction of $pkg to $LOCAL_REPO_PATH failed"
	fi

	echo "Info: Generating repository artifacts"
	echo ""
	$LOCAL_REPO_PATH/update-archive.sh
	echo ""
fi


if [ -d $LOCAL_REPO_PATH ]; then
  if [ ! -d $LOCAL_REPO_PATH/pub ]; then
    mkdir $LOCAL_REPO_PATH/pub
  fi

  if [ ! -f $LOCAL_REPO_PATH/pub/gnugpg.key ]; then
    curl -o $LOCAL_REPO_PATH/pub/gnugpg.key $REPO_URL/pub/gnugpg.key 2> /dev/null
  fi

  if [ ! -f $LOCAL_REPO_PATH/pub/maprgpg.key ]; then
    curl -o $LOCAL_REPO_PATH/pub/maprgpg.key $REPO_URL/pub/maprgpg.key 2> /dev/null
  fi
fi

# Test that the repo is accessible vi http://
if [ ${LOCAL_REPO_PATH#$HTTPD_TOP} != ${LOCAL_REPO_PATH} ] ; then
	echo "Info: Verifying access to newly generated repository"
	echo ""

	curl http://localhost/${LOCAL_REPO_PATH#$HTTPD_TOP}/ 2> /dev/null |  grep -e "mapr" | cut -d\" -f8
fi

# ??? Should we add details regarding how to use the repo here ???

if [ ${LOCAL_REPO_PATH#$HTTPD_TOP} != ${LOCAL_REPO_PATH} ] ; then
	local_repo="http://"
	local_repo=${local_repo}`/bin/hostname -s`
	local_repo=${local_repo}"/${LOCAL_REPO_PATH#$HTTPD_TOP}"
else
	local_repo="file://${LOCAL_REPO_PATH}"
fi

exitSuccess "SUCCESS; Repository is available at $local_repo"

