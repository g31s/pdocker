# The Bash script is to manage and maintain the pdocker enviroment with docker.
# Version 1.1.1

# Gloabl Variables
pdockercontainers=$(docker ps -a | grep pdocker | awk -F ' ' '{print ($NF ":" $1)}' | tr ',', '\n')
count=$(echo $pdockercontainers | wc -w)

# start_container function start the older containers base on name or id. If no container exists it creates new one.
manage_container(){
	echo "[*] Select Following Option:"
	echo "=> New Container: new"
	echo "=> Delete Container: delete"
	echo "=> Type the Container ID to start."
	read -p ">>" option

	if [[ $option == "new" ]]; then
		echo "[*] Staring new container..."
		create_new_container
	elif [[ $option == "delete" ]]; then
		read -p "Container ID >>" container_id
		docker stop $container_id
		docker rm $container_id
		echo "[*] Container Deleted."
	elif [[ $option == "exit" ]]; then
		exit;
	else
		echo "[*] Staring $option container..."
		docker start $option
		docker exec -it $option /bin/bash
	fi
}

# display_containers function display the list of existing containers in nice format.
display_containers(){
	echo "[*] List of containers ids. Newer are first."
	echo "======================="
	echo "    ID 		 Name"
	echo "------------  --------"

	for containerid in $pdockercontainers
	do 	
		echo $containerid |  awk -F ':' '{print ($NF "\t" $1)}'
	done

	echo "======================="
}

# more_than_one function display nice error message if there are more than 1 existing containers
more_than_one(){
	echo "[!] Pdocker containers already exists."
	display_containers
}

# get_name funciton ask user for the name for the container.
get_name(){ 
	while true
	do
		read -p "[*] New Container Name:" name
		if [[ $name =~ ^.[a-z]* ]]; then
			break;
		else
			echo "[-] Invalid Input. Try again."
		fi
	done
}

# get_volume function ask user for adding volumne to container
get_volume(){
	echo "[*] Select Options for adding Volume:"
	echo "=> Select current: y"
	echo "=> No volume: n"
	echo "=> Type the path for volume"

	read -p ">>" volumepath

}

# create_new_container creates new docker container
create_new_container(){
	get_name
	get_volume

	#move to here as pwd passed form string dosn't work.
	if [[ $volumepath == "y" ]]; then
		docker run --name $name --volume "$(pwd)":/home/$name -t -i pdocker /bin/bash
	elif [[ $volumepath != "n" ]]; then
		volume="--volume $volumepath:/home/$name"
		docker run --name $name $volume -t -i pdocker /bin/bash
	else
		docker run --name $name -t -i pdocker /bin/bash
	fi

}

# check_containers check if there is existing containers.
check_containers(){
	if [ $count -eq 0 ]; then
		create_new_container
	else
		more_than_one
		manage_container
	fi
}

main(){
	# Check if container already exists
	check_containers
	echo "[*] Bye."
}

# Everything starts here.
main