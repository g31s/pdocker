# The Bash script is to manage and maintain the pdocker enviroment with docker.
# Version 2.0.1

# Gloabl Variables
pdockerContainers=$(docker ps -a | grep pdocker | awk -F ' ' '{print ($NF ":" $1)}' | tr ',', '\n')
count=$(echo $pdockerContainers | wc -w)

# user_input ask user for input
user_input(){
	echo "[*] Type the Container ID or Name:"
	read -p ">>" input
}

# docker_running? check if docker is running 
docker_running?(){
	if [[ $(pgrep -f docker | wc -l) -eq 1 ]];
	then
		echo '[!] Unable to find docker.'
		echo '[!] Verify if docker is installed and running.'
		exit
	fi
}

# help display program usage
help(){
	echo 'Usage: pdocker options'
	echo 'Options: [(n|new)|(d|delete)|(da|delete_all)|(h|help)]'
}

# check_container check for existing containers
check_container(){
	# Check if containers already exists
	if [ $count -eq 0 ]; then
		echo "[-] No pdocker containers found."
		help
		exit
	fi
}

# start_container function start the older containers base on name or id. If no container exists it creates new one.
start_container(){
	check_container
	display_containers
	user_input

	echo "[*] Staring $input container..."
	docker start $input
	docker exec -it $input /bin/bash
}

# display_containers function display the list of existing containers in nice format.
display_containers(){
	echo "[*] List of containers ids. Newer are first."
	echo "======================="
	echo "    ID 		 Name"
	echo "------------  --------"

	for containerid in $pdockerContainers
	do 	
		echo $containerid |  awk -F ':' '{print ($NF "\t" $1)}'
	done

	echo "======================="
}

# delete_containe_all delete all containers
delete_container_all(){
	check_container
	read -p "[!] Sure you want to delete all containers?[N/y]:" permission
	if [[ $permission == 'y' ]];
	then
		echo "[*] Deleteing All Container...."

		for containerid in $pdockerContainers
		do 	
			container_id=$(echo $containerid |  awk -F ':' '{print ($1)}')
			docker stop $container_id
			docker rm $container_id
		done

	fi
}

# delete_container delete basd on user input
delete_container(){
	check_container
	display_containers
	user_input
	echo "[*] Deleteing Container...."
	docker stop $input
	docker rm $input
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

	read -p ">>" volume

	if [[ $volume == "y" ]]; then
		volume=$(pwd)
	fi
}

# create_new_container creates new docker container
create_new_container(){
	get_name
	get_volume
	docker run --name $name --volume "$volume:/home/$name" -t -i pdocker /bin/bash
}

#Everything starts here..
docker_running?

# Check for command line arugments
case $1 in
	n|new)
	  create_new_container
	  ;;
	d|delete)
	  delete_container
	;;
	da|delete_all)
	  delete_container_all
	;;
	h|help)
	  help
	;;
	*)
	  start_container
	;;
esac


