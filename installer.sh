#!/bin/bash

#v-beta_testing

# Define argument names
ARG1_NAME="--install"
ARG2_NAME="--enable"
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
status_conf_file=status.conf

if [[ -f /etc/debian_version ]] ; then
    status_conf_path=$debian_path
elif [[ -f /etc/redhat-release ]] ; then
    status_conf_path=$centos_path
fi

endpoint="/server-status"
content="\n\t<Location /server-status>\n\t\tSetHandler server-status\n\t</Location>"


#trap Function To reset terminal colours 

func_exit() {
    tput sgr0 # Reset Terminal Colors
    exit 0 # Cleanly exit script
}

#Trap for ctr+c(SIGINT) and ctrl+z(SIGTSTP)

trap func_exit SIGINT SIGTSTP

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

    echo "The Default url with the endpoint found is: http://localhost:80$endpoint?auto"
    read -p "Do you wish to change the url?? (y or n):" change_url
    echo
    
    if [ $change_url = "n" -o $change_url = "N" ] ; then
        url="http://localhost:80$endpoint?auto"
    elif [ $change_url = "y" -o $change_url = "Y" ] ; then
        tput setaf 4
        read -p "  Enter the URL: " url
    else
        tput setaf 4
        read -p "  Enter the URL: " url
    fi

    tput setaf 4
    echo
    echo "  Hit enter if you dont have any credentials set for the endpoint"
    echo

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

    elif ! echo "$output" | grep -qE "\"busy_workers\":|\"idle_workers\":"; then
        tput setaf 3
        echo "The Metrics is not present in the output.Please check if the entered url has the status module endpoint."
        echo "The url example: http://localhost:80$endpoint?auto"
        error_handler 1 "$output"

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

    if [[ -d $status_conf_path ]] ; then  
        echo "$status_conf_path Directory Exists"
        return 0
    else
        echo "Either $debian_path nor $centos_path directory does not exists"
        error_handler 1  
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


    status_conf=$status_conf_path/$status_conf_file
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

        read -p "$status_conf_file file does not exist. Do you wish to Create File and enable mod_status??(y or n):" create_file
        if $create_file = "n" -o $create_file = "N" ; then
            echo "Bye"
            exit
        elif create_file = "y" -o create_file = "Y" ; then
            echo "Creating $status_conf_file file"
            output=$(touch $status_conf)
            error_handler $? $output
            echo
            echo "Adding Content to enable mod_status"
            output=$(echo -e $content >> $status_conf)
            error_handler $? $output
            restart_apache
            return 1
        fi
    fi


}

enabled_or_not() {

    output=$(grep -E "^[^#]*\<SetHandler server-status\>"  $status_conf )
    exit_status=$?
    if [ $exit_status != 1 ] ; then
        error_handler $exit_status $output
    fi


    if [ -n "$output" ] ; then
        echo "status mod already enabled"
        get_endpoint
        
    else
        echo "Mod Status Not enabled"
        echo
        tput setaf 3
        echo "------------Enabling Mod Status------------" 
        echo
        tput sgr0

        echo "The installer will check if there is status.conf file in $staus_conf_path directory."
        echo "If the file does not exist, it will create the file and add the content to enable mod_status."
        echo "If the file exists, it will check if the mod_status is already enabled."
        echo "If the mod_status is not enabled, it will add the content to enable mod_status."
        echo
        echo "Content to be added in $status_conf_file file"
        echo -e $content
        echo
        read -p "Do you wish to continue??(y or n):" continue

        if [ $continue = "n" -o $continue = "N" ] ; then
            echo "bye"
            exit
        elif [ $continue = "y" -o $continue = "Y" ] ; then
            echo "Taking Backup of $status_conf_file file"
            output=$(cp $status_conf $status_conf_path/$status_conf_file.bak.$(date +%Y_%m_%d_%H_%M_%S))
            error_handler $? $output
            echo
            echo "Adding Content..."
            add_content 
            echo "Done"
            restart_apache

        else 
            echo "Invalid Input"
            exit
        fi

    fi

}

get_endpoint(){
    line=$(grep -nE "^[^#]*\<SetHandler server-status\>" $status_conf | awk -F: '{print $1}')
    l_no=$(( $line-1 ))


    while [ $l_no -gt 0 ] ; do
    
    text=$(sed -n $l_no"p" $status_conf)
    
    if echo $text | grep -qE "^[^#]*\<Location\>" ; then
        endpoint=$(echo $text | grep  "^[^#]*\<Location\>" | sed -n 's/^.*<Location \([^>]*\)>.*/\1/p') 
        echo "The endpoint of Mod Status: $endpoint"
        echo "Proceding to install the plugin"
        break
        
        
    else
        l_no=$(( $l_no-1 ))
    fi

    done


}

add_content() {

    output=$(sed -i "/^<IfModule mod_status.c>/a\ $content"  $status_conf)
    error_handler $? $output

}

restart_apache(){

     echo "The changes will only be reflected after restarting or reloading the apache webserver"
     read -p "Do you wish to restart apache webserver??(y or n):" restart
        if [ $restart = "y" -o $restart = "Y" ] ; then
            echo "Restarting Apache Webserver..."
            if [[ -f /etc/debian_version ]] ; then
                output=$(systemctl restart apache2)
                error_handler $? $output
                echo "Done"
            elif [[ -f /etc/redhat-release ]] ; then
                output=$(systemctl restart httpd)
                error_handler $? $output
                echo "Done"
            fi
            
        elif [ $restart = "n" -o $restart = "N" ] ; then
            echo "Done"
            
        fi


}


install_plugin() {

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
}


tput setaf 3
echo
echo "------------Checking if $status_conf_file exists------------"
tput sgr0


echo
check_if_dir_exists     
check_if_file_exists

install_plugin
