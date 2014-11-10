#!/bin/bash
# -----------------------------------------------------------------------------
# Initial setup for Ubuntu 14.04 LTS on Amazon's Elastic Compute Cloud
#
# Note that after creating a new EC2 instance the username will be "ubuntu"
# with no password. This is a non-root account with access to sudo.
#
# References:
# http://c-nergy.be/blog/?p=5305
# http://scikit-learn.org/stable/install.html
# https://help.ubuntu.com/community/PostgreSQL
# https://launchpad.net/~webupd8team/+archive/ubuntu/java
# https://help.ubuntu.com/community/VNC/Servers
# -----------------------------------------------------------------------------
if [ $EUID -eq 0 ]; then
    echo "Please run this script as someone other than root."
    exit 1
fi

# -----------------------------------------------------------------------------
# OPTIONS
#
# The IB API link frequently changes. See http://interactivebrokers.github.io
# for the latest version.
# -----------------------------------------------------------------------------

IB_API_URL="http://interactivebrokers.github.io/downloads/twsapi_macunix.972.03.jar"
IB_CLIENT_URL="https://download2.interactivebrokers.com/download/unixmacosx_latest.jar"


# -----------------------------------------------------------------------------
# FUNCTIONS, HIGH-LEVEL
# -----------------------------------------------------------------------------

#
# Update the package database, upgrade the system, and create a user account.
#
setup_system ()
{
    if [ -z "$1" ]; then
        echo "You must specify a new user account name."
        exit 1
    fi
    # Update the packages
    sudo apt-get -y update
    sudo apt-get -y upgrade
    # Create a local user account
    echo "Creating an account for $1 ..."
    sudo useradd -m -g users -G sudo -s /bin/bash $1
    sudo passwd $1
    # Add the SSH key to the account. Note that as long as we are the default
    # "ubuntu" user in the AWS image, the keys will already be here.
    sudo mkdir /home/$1/.ssh
    sudo cp $HOME/.ssh/authorized_keys /home/$1/.ssh/authorized_keys
    sudo chmod 600 /home/$1/.ssh/authorized_keys
    sudo chown -R $1:users /home/$1/.ssh
    # Copy the setup script(s) to the new user directory
    sudo cp -a $HOME/setup-scripts /home/$1
    sudo chmod -R 700 /home/$1/setup-scripts
    sudo chown $1:users /home/$1/setup-scripts
}

#
# Install console applications.
#
install_console_apps ()
{
    # General development tools
    sudo apt-get -y install build-essential
    sudo apt-get -y install cmake
    sudo apt-get -y install git
    sudo apt-get -y install htop
    # Python development
    sudo apt-get -y install ipython3
    sudo apt-get -y install ipython3-notebook
    sudo apt-get -y install libatlas-dev
    sudo apt-get -y install libatlas3gf-base
    sudo apt-get -y install python3-cherrypy3
    sudo apt-get -y install python3-flake8
    sudo apt-get -y install python3-matplotlib
    sudo apt-get -y install python3-pip
    sudo apt-get -y install python3-scipy
    sudo apt-get -y install python3-ws4py
    # Database support 
    sudo apt-get -y install postgresql
    sudo apt-get -y install postgresql-client
    sudo apt-get -y install python3-psycopg2
    # Compiled/complex apps
    configure_postgresql
    install_java
    install_scikit_learn
    install_tmux_monitor
    sudo pip3 install deap
}

#
# Install graphical applications.
#
install_gui_apps ()
{
    sudo apt-get -y install openbox
    sudo apt-get -y install lxterminal
    sudo apt-get -y install tint2
    sudo apt-get -y install chromium-browser
    install_ib
    install_vnc
}


# -----------------------------------------------------------------------------
# FUNCTIONS, SPECIAL APPLICATIONS
# -----------------------------------------------------------------------------

#
# Configure PostgreSQL.
#
configure_postgresql ()
{
    # Create a PostgreSQL user account
    sudo -u postgres createuser --superuser $USER
    echo "Type \"\\password $USER\" to change your PostgreSQL password."
    echo "Then \"\\q\" to quit the Postgres shell."
    sudo -u postgres psql
    # Create a database for the user
    sudo -u postgres createdb $USER
}

#
# Get the configuration files (dotfiles) from github.
#
install_dotfiles ()
{
    # Clone the repository
    cd $HOME
    git clone https://github.com/larmer01/dotfiles
    # Create symbolic links
    rm -f .bash_logout
    rm -f .bashrc
    rm -f .profile
    ln -s dotfiles/bash_logout .bash_logout
    ln -s dotfiles/bashrc .bashrc
    ln -s dotfiles/dircolors .dircolors
    ln -s dotfiles/gitconfig .gitconfig
    ln -s dotfiles/ipython .ipython
    ln -s dotfiles/profile .profile
    ln -s dotfiles/tmux.conf .tmux.conf
    ln -s dotfiles/vim .vim
    ln -s dotfiles/vimrc .vimrc
    ln -s dotfiles/xsession .xsession
}

#
# Install the Interactive Brokers client, gateway and API.
#
install_ib ()
{
    mkdir $HOME/.tmp-ib-install
    cd $HOME/.tmp-ib-install

    # TWS will crash without this
    sudo apt-get -y install gsettings-desktop-schemas

    # Install the client
    wget -O unixmacosx.jar $IB_CLIENT_URL
    jar xf unixmacosx.jar
    rm -rf META-INF
    rm unixmacosx.jar
    mv IBJts client

    # Install the API
    wget -O twsapi.jar $IB_API_URL
    jar xf twsapi.jar
    rm twsapi.jar
    mv IBJts api

    # Copy to the /usr/local/share directory
    sudo rm -rf /usr/local/share/tws
    sudo mkdir -p /usr/local/share/tws
    sudo mv $HOME/.tmp-ib-install/* /usr/local/share/tws
    sudo chown -R $USER:users /usr/local/share/tws

    rm -rf $HOME/.tmp-ib-install
}

#
# Install Oracle's JDK via a PPA.
#
install_java ()
{
    sudo add-apt-repository ppa:webupd8team/java
    sudo apt-get update
    sudo apt-get -y install oracle-java7-installer
}

#
# Build scikit-learn.
#
install_scikit_learn ()
{
    # Make sure ATLAS is used to provide the implementation of the BLAS
    # and LAPACK linear algebra routines
    sudo update-alternatives --set libblas.so.3 \
        /usr/lib/atlas-base/atlas/libblas.so.3
    sudo update-alternatives --set liblapack.so.3 \
        /usr/lib/atlas-base/atlas/liblapack.so.3
    # Build/install
    sudo pip3 install -U scikit-learn
}

#
# Build the tmux cpu load plugin.
#
install_tmux_monitor ()
{
    mkdir $HOME/.tmp-build
    cd $HOME/.tmp-build
    git clone https://github.com/thewtex/tmux-mem-cpu-load.git
    cd tmux-mem-cpu-load
    cmake .
    make
    sudo make install
    cd ../..
    rm -rf $HOME/.tmp-build
}

#
# Install a VNC server.
#
install_vnc ()
{
    sudo apt-get -y install vnc4server

    # Initial run to setup the vnc folder and password
    vncserver :1
    vncserver -kill :1

    # Edit the xstartup file
    FILE=$HOME/.vnc/xstartup
    rm -f $FILE
    echo "#!/bin/sh
# Avoid keyboard mis-mapping
export XKL_XMODMAP_DISABLE=1
# Switch to our home directory
cd $HOME
# Start our session
lxterminal &
tint2 &
exec openbox-session" > $FILE
    chmod 755 $FILE
    chmod 700 $HOME/.vnc
}


# -----------------------------------------------------------------------------
# COMMAND-LINE
# -----------------------------------------------------------------------------

case "$1" in
    system)
        if [ $EUID -ne 1000 ]; then
            echo "Please run this script as the default 'ubuntu' user."
            exit 1
        fi
        setup_system $2
        ;;
    apps)
        if [ $EUID -eq 1000 ]; then
            echo "Please run this script as someone other than the default 'ubuntu' user."
            exit 1
        fi
        install_console_apps
        install_dotfiles
        install_gui_apps
        ;;
    ib)
        if [ $EUID -eq 1000 ]; then
            echo "Please run this script as someone other than the default 'ubuntu' user."
            exit 1
        fi
        install_ib
        ;;
    *)
        echo "Usage: $0 [system <username> | apps | ib]"
        ;;
esac

exit 0
