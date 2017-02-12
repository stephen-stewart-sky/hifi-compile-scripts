#!/bin/bash

# Home Directory for HifiUser
HIFIDIR="/usr/local/hifi"
# Last Compile Backup Directory
LASTCOMPILE="$HIFIDIR/last-compile"
# Runtime Directory Location
RUNDIR="$HIFIDIR/run"
# Log Directory
LOGSDIR="$HIFIDIR/logs"
# Source Storage Dir
SRCDIR="/usr/local/src"

## Functions ##
function checkroot {
  [ `whoami` = root ] || { echo "Please run as root"; exit 1; }
}

function writecommands {
# Always rewrite just incase something changed
cat <<EOF > /etc/profile.d/coal.sh
alias compilehifi='bash <(curl -Ls https://raw.githubusercontent.com/nbq/hifi-compile-scripts/master/centos7-compile-hifi.sh)'
alias recompilehifi='bash <(curl -Ls https://raw.githubusercontent.com/nbq/hifi-compile-scripts/master/centos7-recompile-hifi.sh)'
alias runhifi='bash <(curl -Ls https://raw.githubusercontent.com/nbq/hifi-compile-scripts/master/centos7-run-hifi.sh)'
alias killhifi='bash <(curl -Ls https://raw.githubusercontent.com/nbq/hifi-compile-scripts/master/centos7-kill-hifi.sh)'
EOF
}

function checkifrunning {
  # Not used now, but in the future will check if ds/ac is running then offer to restart if so
  # For now we just auto restart.
  [[ $(pidof domain-server) -gt 0 ]] && { HIFIRUNNING=1; }
}

function handlerunhifi {
  echo "Running your HiFi Stack as user hifi"
  echo "To update your install later, just type 'compilehifi' to begin this safe process again - NO DATA IS LOST"
  export -f runashifi
  su hifi -c "bash -c runashifi"
  exit 0
}

function runashifi {
  # Everything here is run as the user hifi
  TIMESTAMP=$(date '+%F')
  HIFIDIR=/usr/local/hifi
  HIFIRUNDIR=$HIFIDIR/run
  HIFILOGDIR=$HIFIDIR/logs
  cd $HIFIRUNDIR
  ./domain-server &>> $HIFILOGDIR/domain-$TIMESTAMP.log&
  ./assignment-client -n 3 &>> $HIFILOGDIR/assignment-$TIMESTAMP.log&
}

function doyum {
  echo "Updating Your OS - If you see Kernel listed you should restart when done and after type 'runhifi' to restart HighFidelity."
  yum update -y
  echo "Installing EPEL Repo."
  yum install epel-release -y > /dev/null 2>&1
  echo "Installing compile tools."
  yum groupinstall "development tools" -y > /dev/null 2>&1
  echo "Installing base needed tools."
  yum install openssl-devel glew-devel git wget sudo libXmu-* libXi-devel libXrandr libXrandr-devel qt5-qt* -y > /dev/null 2>&1
}

function killrunning {
  echo "Killing Running Processess"
  pkill -9 -f "[d]omain-server" > /dev/null 2>&1
  pkill -9 -f "[a]ssignment-client" > /dev/null 2>&1
}

function createuser {
  if [[ $(grep -c "^hifi:" /etc/passwd) = "0" ]]; then
    useradd -s /bin/bash -r -m -d $HIFIDIR hifi
  fi
}

function removeuser {
  userdel -r hifi > /dev/null 2>&1
}

function changeowner  {
  if [ -d "$HIFIDIR" ]; then
    chown -R hifi:hifi $HIFIDIR
  fi  
}

function setuphifidirs {

  if [[ ! -d $HIFIDIR ]]; then
    echo "Creating $HIFIDIR"
    mkdir $HIFIDIR
  fi

  pushd $HIFIDIR > /dev/null

  if [[ ! -d "$LASTCOMPILE" ]]; then
    echo "Creating Last-Compile Backup Directory"
    mkdir $LASTCOMPILE
  fi

  if [[ ! -d "$RUNDIR" ]]; then
    echo "Creating Runtime Directory"
    mkdir $RUNDIR
  fi

  if [[ -a "$RUNDIR/assignment-client" && -a "$RUNDIR/domain-server" && -d "$RUNDIR/resources" ]]; then
    echo "Removing Old Last-Compile Backup"
    rm -rf $LASTCOMPILE/*

    echo "Backing Up AC"
    mv "$RUNDIR/assignment-client" $LASTCOMPILE

    echo "Backing Up DS"
    mv "$RUNDIR/domain-server" $LASTCOMPILE

    echo "Making a Copy Of The Resources Folder"
    cp -R "$RUNDIR/resources" $LASTCOMPILE
  fi

  if [[ ! -d $LOGSDIR ]]; then
    mkdir $LOGSDIR
  fi

  popd > /dev/null
}

function handlecmake {
  if [[ ! -f "cmake-3.7.2.tar.gz" ]]; then
    wget https://cmake.org/files/v3.7/cmake-3.7.2.tar.gz
    tar -xzvf cmake-3.7.2.tar.gz
    cd cmake-3.7.2/
    ./configure --prefix=/usr
    gmake && gmake install
    cd ..
  fi
}

function compilehifi {
  # NOTE - This currently assumes /usr/local/src and does not move forward if the source dir does not exist - todo: fix
  if [[ -d "$SRCDIR" ]]; then
    pushd $SRCDIR > /dev/null

    # handle install and compile of cmake
    if [[ ! -f "/usr/bin/cmake"  ]]; then
      handlecmake
    fi

    if [[ ! -d "highfidelity" ]]; then
      mkdir highfidelity
    fi

    cd highfidelity

    if [[ ! -d "hifi" ]]; then
      git clone https://github.com/highfidelity/hifi.git
    fi
    
    # popd src
    popd > /dev/null
    pushd $SRCDIR/highfidelity/hifi > /dev/null 

    # update if needed
    git pull

    echo "Source needs compiling."
    killrunning
    # we are still assumed to be in hifi directory
    if [[ -d "build" ]]; then
      rm -rf build/*
    else
      mkdir build
    fi
    cd build
    cmake -DGET_LIBOVR=1 ..
    make domain-server && make assignment-client
    setwebperm

    # popd on hifi source dir
    popd > /dev/null
  fi
}

function setwebperm {
  chown -R hifi:hifi $SRCDIR/highfidelity/hifi/domain-server/resources/web
}

function movehifi {
  #killrunning
  setwebperm
  DSDIR="$SRCDIR/highfidelity/hifi/build/domain-server"
  ACDIR="$SRCDIR/highfidelity/hifi/build/assignment-client"
  cp $DSDIR/domain-server $RUNDIR
  cp -R $DSDIR/resources $RUNDIR
  cp $ACDIR/assignment-client $RUNDIR
  changeowner
}

## End Functions ##

# Make sure only root can run this
checkroot

# Make our HiFi user if needed
createuser

# Handle Yum Install Commands
doyum

# Deal with the source code and compile highfidelity
compilehifi

# setup hifi folders
setuphifidirs

# Copy new binaries then change owner
movehifi

# Copy commands to be run to .bashrc
writecommands

# Handle re-running the hifi stack as needed here
handlerunhifi
