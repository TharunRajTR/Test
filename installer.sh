#!/bin/bash

# Define argument names
ARG1_NAME="--install"
ARG2_NAME="--enable"
ARG3_NAME="--add_instance"
install=false
enable=false
add_instance=false

# Install
plugin=apache_monitoring
agent_dir=/opt/site24x7/monagent
temp_dir=$agent_dir/temp/plugins/$plugin
plugin_dir=$agent_dir/plugins/
py_file="$temp_dir/$plugin.py"
cfg_file="$temp_dir/$plugin.cfg"



# Enable
debian_path=/etc/apache2/mods-available
centos_path=/etc/httpd/conf.d
status_conf_path=/etc/apache2/mods-available
status_conf_file=status.conf

content="\n\t<Location /server-status>\n\t\tSetHandler server-status\n\t</Location>"

#trap Function To reset terminal colours 

func_exit() {
    tput sgr0 # Reset Terminal Colors
    exit 0 # Cleanly exit script
}

#Trap for ctr+c(SIGINT) and ctrl+z(SIGTSTP)

trap func_exit SIGINT SIGTSTP

# Start processing command line arguments
while [[ $# -gt  0 ]]; do
    key="$1"

    case "$key" in
        $ARG1_NAME)
            install=true
            shift # past argument
            shift # past value
            ;;
        $ARG2_NAME)
            enable=true
            shift # past argument
            shift # past value
            ;;
        $ARG3_NAME)
            add_instance=true
            shift # past argument
            shift # past value
            ;;
        *)
            echo "Unknown option: $key"
            exit   1
            ;;
        esac
done

download_files() {

    file_name=$1 
    echo "Downloading: $file_name"
    echo
    
    output=$(wget -P $temp_dir $file_name  2>&1 )

    if [ $? -ne 0 ]; then
        tput setaf 1
        error=$(grep -E 'HTTP' <<< "$output" )
        echo $error
        if echo "$error" | grep -q "200"; then
            echo $output
        fi
        tput sgr0
        exit
    else
        tput setaf 2
        echo $(grep -E 'HTTP' <<< "$output" )
        echo $(grep -E 'saved' <<< "$output" )
        tput sgr0
        
    fi
    echo

}


install (){
    
    if [[ -d $temp_dir ]] ; then

        if ( [[ -f $py_file ]] ) ; then 
            rm $py_file
        fi
        if ( [[ -f $cfg_file ]] ) ; then 
            rm $cfg_file
        fi

        download_files https://raw.githubusercontent.com/site24x7/plugins/master/apache_monitoring/apache_monitoring.py
        download_files https://raw.githubusercontent.com/site24x7/plugins/master/apache_monitoring/apache_monitoring.cfg

    else
        output=$(mkdir $temp_dir)
         if [ $? -ne 0 ]; then
            tput setaf 1
            echo "------------Error Occured------------"
            echo $output
            tput sgr0
            exit
        fi

        download_files https://raw.githubusercontent.com/site24x7/plugins/master/apache_monitoring/apache_monitoring.py
        download_files https://raw.githubusercontent.com/site24x7/plugins/master/apache_monitoring/apache_monitoring.cfg
        
    fi

}

get_plugin_data() {
    tput setaf 3
    echo
    echo "------------Connection Details------------"
    echo 

    tput setaf 4
    read -p "  Enter the URL: " url
    read -p "  Enter the User Name: " username
    read -sp "  Enter the Password: " password
    echo
    tput sgr0
}


python_path_update() {
    echo "Checking for python3"
    output=$(which python3)
    if [ $? -ne 0 ]; then

        echo $(python3 --version)
        echo
        echo "Checking for python2"
        output=$(which python)
        if [ $? -ne 0 ]; then
            tput setaf 1
            echo "------------Could Not Update Python Path------------"
            echo 
            tput sgr0
            echo $(python --version)
            exit
        else
            python=python
            output=$(sed -i "1s|^.*|#! $output|" $py_file)
            if [ $? -ne 0 ]; then
                tput setaf 1
                echo "------------Could Not Update Python Path------------"
                echo 
                tput sgr0
            
            else
                echo "Python Path Updated with $(python --version 2>&1)"
            fi
        fi

    else
        python=python3
         output=$(sed -i "1s|^.*|#! $output|" $py_file)
         if [ $? -ne 0 ]; then
            tput setaf 1
            echo "------------Could Not Update Python Path------------"
            echo 
            tput sgr0
        else
            echo "Python Path Updated with $(python3 --version)"
        fi
    

    fi

}

check_plugin_execution() {

    output=$($python $py_file --url "$url" --username "$username" --password "$password")
    if  [ $? -ne 0 ]; then
        tput setaf 1
        echo "------------Error Occured------------"
        echo $output
        echo
        echo $(grep -E '"status": 0' <<< "$output" )
        echo $(grep -E '"msg": *' <<< "$output" )
        tput sgr0
        exit
    fi
    if grep -qE '"status": 0' <<< "$output"  ; then
        tput setaf 1
        echo "------------Error Occured------------"
        echo $output
        echo
        echo "Status And Error Message:"
        echo $(grep -E '"status": 0' <<< "$output" )
        echo $(grep -E '"msg": *' <<< "$output" )
        tput sgr0
        exit
    else
        tput setaf 3
        echo "------------Successfull Test Execution------------"
        tput setaf 2
        echo $output
        tput sgr0

    fi


}

add_conf() {
    echo
    #echo "before"
    #cat $cfg_file
    output=$(sed -i "/url*/c\url = \"$url\""  "$cfg_file")
    error_handler $? $output
    output=$(sed -i "/username*/c\username = \"$username\""  $cfg_file)
    error_handler $? $output
    output=$(sed -i "/password*/c\password = \"$password\""  $cfg_file)
    error_handler $? $output
    #echo "after"
    #cat $cfg_file
    
}

check_plugin_exists() {
    if  [[ -d "$plugin_dir/$plugin" ]]  ; then 
        echo "The plugin already Exists in the plugins directory"
        read -p "Do you wish to reinstall??(y or n):" reinstall
        if [ $reinstall = "y" -o $reinstall = "Y" ] ; then
            rm -rf "$plugin_dir/$plugin"
        elif [ $reinstall = "n" -o $reinstall = "N" ] ; then
            echo "Bye"
            exit
        fi
        
    fi
}

move_plugin() {
    output=$(mv $temp_dir $plugin_dir )
    if  [ $? -ne 0 ]; then
        tput setaf 1
        echo "------------Error Occured------------"
        tput sgr0
    else
        echo "Done"
    fi

}

check_if_dir_exists() {

    if [[ -d $debian_path ]] ; then 
        status_conf_path=$debian_path     
        return 0
    elif [[ -d $centos_path ]] ; then
        status_conf_path=$centos_path
        return 0
    else
        echo "$status_conf_path directory does not exist"
        exit
        return 1
    fi
}

error_handler() {
    if  [ $1 -ne 0 ]; then
        tput setaf 1
        echo  "------------Error Occured------------"
        echo $2
        tput sgr0
        exit
    fi
}
check_if_file_exists() {

    
    if [[ -f $status_conf ]] ; then
        echo "$status_conf_file file exists"
        echo
        tput setaf 3
        echo
        echo "------------Checking if Mod Status is already Enabled------------"
        echo
        tput sgr0
        enabled_or_not
        
        return 0
    else
        echo "$status_conf_file file does not exist. Creating File"
        echo "Adding Content to enable mod_status"
        output=$(touch $status_conf)
        error_handler $? $output
        echo -e $content >> $status_conf
        return 1check_if_file_exists
    fi


}

enabled_or_not() {

     if grep -qE "^[^#]*\<SetHandler server-status\>"   $status_conf ; then
        echo "status mod already enabled"
        get_endpoint
        exit
     else

        echo "Mod Status Not enabled"
        echo
        tput setaf 3
        echo
        echo "------------Enabling Mod Status------------"
        echo
        tput sgr0
        echo "Taking Backup of $status_conf_file file"
        output=$(cp $status_conf $status_conf_path/$status_conf_file.bak.$(date +%Y_%m_%d_%H_%M_%S))
        error_handler $? $output
        echo
        echo "Adding Content..."
        echo "Done"
        add_content 
    fi

}

get_endpoint(){
    line=$(grep -nE "^[^#]*\<SetHandler server-status\>" $status_conf | awk -F: '{print $1}')
    l_no=$(( $line-1 ))


    while [ $l_no -gt 0 ] ; do
    
    text=$(sed -n $l_no"p" $status_conf)
    
    if echo $text | grep -qE "^[^#]*\<Location\>" ; then
        endpoint=$(echo $text | grep  "^[^#]*\<Location\>" | sed -n 's/^.*<Location \([^>]*\)>.*/\1/p')
        echo "The enpoint of Mod Status: $endpoint"
        echo 
        echo "If you want to monitor localhost on port 80 with HTTP, use the following endpoint"
        echo "http://localhost:80$endpoint?auto"
        echo
        echo "And for HTTPS use the following endpoint"
        echo "https://localhost:80$endpoint?auto"
        echo
        echo "Change the endpoint in the plugin configuration, if the host and port are differ according to your server."
        exit
    else
        l_no=$(( $l_no-1 ))
    fi

    done


}

add_content() {

    output=$(sed -i "/^<IfModule mod_status.c>/a\ $content"  $status_conf)
    error_handler $? $output

}


if $install ; then

    check_plugin_exists
    tput setaf 3
    echo
    echo "------------Downloading the plugin files------------"
    echo    
    tput sgr0

    install

    echo
    echo 

    get_plugin_data

    add_conf

    python_path_update

    check_plugin_execution

    tput setaf 3
    echo
    echo "------------Moving Files To Add Plugin------------"
    echo
    tput sgr0

    move_plugin
fi

if $enable ; then

    if ( check_if_dir_exists ); then
        tput setaf 3
        echo
        echo "------------Checking if $status_conf_file exists------------"
        tput sgr0
        echo
        echo "$status_conf_path Directory Exists"
        status_conf=$status_conf_path/$status_conf_file
        check_if_file_exists
    

    else
        exit
    fi
fi
