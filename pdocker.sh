# The Bash script is to manage and maintain the pdocker enviroment with docker.
# Version 1.0.0

# Gloabl Variables
pdockercontainers=$(docker ps -a | grep pdocker | awk -F ' ' '{print ($NF ":" $1)}' | tr ',', '\n')
count=$(echo $pdockercontainers | wc -w)

# start_container function start the older containers base on name or id. If no container exists it creates new one.
start_container(){
	echo "[*] Type the container ID or type new to create new container."
	read -p ">>" option

	if [[ $option == "new" ]];
	then
		echo "[*] Staring new container..."
		create_new_container
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
	echo "==============================="
	echo "  ID 		Name"

	for containerid in $pdockercontainers
	do 	
		echo $containerid |  awk -F ':' '{print ($NF "\t" $1)}'
	done

	echo "==============================="
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
		if [[ $name =~ ^.[a-z]* ]]
		then
			break;
		else
			echo "[-] Invalid Input. Try again."
		fi
	done
}

# create_new_container creates new docker container
create_new_container(){
	get_name
	docker run --name $name -t -i pdocker /bin/bash
}

# check_containers check if there is existing containers.
check_containers(){
	#
	if [ $count -eq 0 ] 
	then
		create_new_container
	else
		more_than_one
		start_container
	fi
}

main(){
	# Check if container already exists
	check_containers
	echo "[*] Bye."
}

# Everything starts here.
main