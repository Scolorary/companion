#!/bin/bash

cd /home/pi/companion/br-webui

if ! npm list nodegit | grep -q nodegit@0.18.3; then
    echo 'Fetching nodegit packages for raspberry pi...'
    wget --timeout=15 --tries=2 https://s3.amazonaws.com/downloads.bluerobotics.com/Pi/dependencies/nodegit/nodegit_required_modules.zip -O /tmp/nodegit_required_modules.zip
    if [ $? -ne 0 ] # If "wget" failed:
    then
        echo 'Failed to retrieve nodegit packages; Aborting update'
        echo 'Rebooting'
        sleep 0.1
        sudo reboot
    fi

    echo 'Extracting prebuilt packages...'
    unzip -q /tmp/nodegit_required_modules.zip -d ~/companion/br-webui/node_modules/
fi

# TODO prune unused npm modules here

echo 'run npm install'
npm install
if [ $? -ne 0 ] # If "npm install" failed:
then
    echo 'Failed to install required npm modules; Aborting update'
    echo 'Rebooting'
    sleep 0.1
    sudo reboot
fi

cd /home/pi/companion

echo 'Updating submodules...'
git submodule init && git submodule sync
if [ $? -ne 0 ] # If either "git submodule" failed:
then
    echo 'Failed to update submodules; Aborting update'
    echo 'Rebooting'
    sleep 0.1
    sudo reboot
fi

# https://git-scm.com/docs/git-submodule#git-submodule-status--cached--recursive--ltpathgt82308203

echo 'Checking mavlink status...'
MAVLINK_STATUS=$(git submodule status | grep mavlink | head -c 1)
if [[ ! -z $MAVLINK_STATUS && ($MAVLINK_STATUS == '+' || $MAVLINK_STATUS == '-') ]]; then
    # Remove old mavlink directory if it exists
    [ -d ~/mavlink ] && sudo rm -rf ~/mavlink

    echo 'mavlink needs update.'
    git submodule update --recursive --init -f submodules/mavlink
    echo 'Installing mavlink...'
    cd /home/pi/companion/submodules/mavlink/pymavlink
    sudo python setup.py build install || { echo 'mavlink installation failed!'; }
else
    echo 'mavlink is up to date.'
fi

cd /home/pi/companion

echo 'Checking MAVProxy status...'
MAVPROXY_STATUS=$(git submodule status | grep MAVProxy | head -c 1)
if [[ ! -z $MAVPROXY_STATUS && ($MAVPROXY_STATUS == '+' || $MAVPROXY_STATUS == '-') ]]; then
    echo 'MAVProxy needs update.'
    git submodule update --recursive -f submodules/MAVProxy
    echo 'Installing MAVProxy...'
    cd /home/pi/companion/submodules/MAVProxy
    sudo python setup.py build install || { echo 'MAVProxy installation failed!'; }
else
    echo 'MAVProxy is up to date.'
fi

echo 'checking for github in known_hosts'

# Check for github key in known_hosts
if ! ssh-keygen -H -F github.com; then
    mkdir ~/.ssh

    # Get gihub public key
    ssh-keyscan -t rsa -H github.com > /tmp/githost

    # Verify fingerprint
    if ssh-keygen -lf /tmp/githost | grep -q 16:27:ac:a5:76:28:2d:36:63:1b:56:4d:eb:df:a6:48; then
        # Add to known_hosts
        cat /tmp/githost >> ~/.ssh/known_hosts
    fi
fi

# install pynmea2 if neccessary
if pip list | grep pynmea2; then
    echo 'pynmea2 already installed'
else
    echo 'installing pynmea2...'
    sudo pip install pynmea2
    if [ $? -ne 0 ] # If "pip install pynmea2" failed:
    then
        echo 'Failed to install pynmea2; Aborting update'
        echo 'Rebooting'
        sleep 0.1
        sudo reboot
    fi
fi

# install grequests if neccessary
if pip list | grep grequests; then
    echo 'grequests already installed'
else
    echo 'Fetching grequests packages for raspberry pi...'
    wget --timeout=15 --tries=2 https://s3.amazonaws.com/downloads.bluerobotics.com/Pi/dependencies/grequests/grequests.zip -O /tmp/grequests.zip
    if [ $? -ne 0 ] # If "wget" failed:
    then
        echo 'Failed to retrieve grequests packages; Aborting update'
        echo 'Rebooting'
        sleep 0.1
        sudo reboot
    fi
    echo 'Extracting prebuilt packages...'
    sudo unzip -q -o /tmp/grequests.zip -d /
    echo 'installing grequests...'
    sudo pip install grequests
    if [ $? -ne 0 ] # If "pip install grequests" failed:
    then
        echo 'Failed to install grequests; Aborting update'
        echo 'Rebooting'
        sleep 0.1
        sudo reboot
    fi
fi

# copy default parameters if neccessary
cd /home/pi/companion/params

for default_param_file in *; do
    if [[ $default_param_file == *".param.default" ]]; then
        param_file="/home/pi/"$(echo $default_param_file | sed "s/.default//")
        if [ ! -e "$param_file" ]; then
            cp $default_param_file $param_file
        fi
    fi
done

# change the pi user password to 'bluerobotics' instead of the default 'raspberry'
PRE_0_0_8=$(( git rev-list --count --left-right 0.0.8...revert-point || echo 0 ) | cut -f1)
if (( $PRE_0_0_8 > 0 )); then
    echo "changing default password to 'companion'..."
    echo "pi:companion" | sudo chpasswd
fi

echo 'Update Complete, refresh your browser'

sleep 0.1

echo 'quit webui' >> /home/pi/.update_log
screen -X -S webui quit

echo 'restart webui' >> /home/pi/.update_log
sudo -H -u pi screen -dm -S webui /home/pi/companion/scripts/start_webui.sh

echo 'removing lock' >> /home/pi/.update_log
rm -f /home/pi/.updating
