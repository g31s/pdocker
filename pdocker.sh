# The Bash script is to manage and maintain the pdocker enviroment with docker.
# Version 2.1.0

# Gloabl Variables
pdockerContainers=$(docker ps -a | grep pdocker | awk -F ' ' '{print ($NF ":" $1)}' | tr ',', '\n')
count=$(echo $pdockerContainers | wc -w)
image="pdocker"

# commit_container commit the existing container. Funcation requires 2 parameters.
# $1 containerid
# $2 image_name
commit_container(){
	docker commit $1 $2
}

# find_volume find the volumne path for the container. Funcation requires 1 parameter.
# $1 containerid
find_volume(){
	local volume=$(docker inspect --format="{{.Mounts}}" $1 | awk -F ' ' '{print ($2)}')
	echo "$volume"
}

# open_ports open ports for existing docker container by commiting it first.
open_ports(){
	local input containers containerid containername name
	check_container
	display_containers

	echo "[!] Pdocker will open the ports for the first entry. Make sure to write the fullname or ID."

	input=$(user_input)

	for containers in $pdockerContainers
	do 	
		if [[ "$containers" == *"$input"* ]]; then
			containerid=$(echo $containers | awk -F ':' '{print ($2)}')
			containername=$(echo $containers | awk -F ':' '{print ($1)}')

			name=$containername"_pdocker_op"
			commit_container $containerid $name

			volume=$(find_volume $containerid)
			portoptions=$(get_ports)

			delete_container $containerid

			docker run -it --name $containername --volume $volume:/home/$containername $portoptions $name
			exit
		fi
	done
}

# user_input ask user for input
user_input(){
	local input
	read -p "[*] Type the Container ID or Name:" input
	echo "$input"
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
	echo 'Options: [(n|new)|(d|delete)|(da|delete_all)|(op|open_ports)|(h|help)]'
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
	local input
	check_container
	display_containers
	input=$(user_input)

	echo "[*] Staring $input container..."
	docker start $input
	docker exec -it $input /bin/bash
}

# display_containers function display the list of existing containers in nice format.
display_containers(){
	local containers
	echo "[*] List of containers ids. Newer are first."
	echo "======================="
	echo "    ID 		 Name"
	echo "------------  --------"

	for containers in $pdockerContainers
	do 	
		echo $containers |  awk -F ':' '{print ($NF "\t" $1)}'
	done

	echo "======================="
}

# delete_containe_all delete all containers
delete_container_all(){
	local permission containers container_id
	check_container
	read -p "[!] Sure you want to delete all containers?[N/y]:" permission
	if [[ $permission == 'y' ]];
	then
		echo "[*] Deleteing All Container...."

		for containers in $pdockerContainers
		do 	
			container_id=$(echo $containers |  awk -F ':' '{print ($1)}')
			docker stop $container_id
			docker rm $container_id
		done

	fi
}

# delete_container delete basd on user input
delete_container(){
	local input
	input=$1
	if [[ "$#" -eq 0 ]]; then
		check_container
		display_containers
		input=$(user_input)
	fi
	echo $input
	echo "[*] Deleteing Container...."
	docker stop $input
	docker rm $input
}


# get_name funciton ask user for the name for the container.
get_name(){ 
	local name
	while true
	do
		read -p "[*] New Container Name:" name
		if [[ $name =~ ^.[a-z]* ]]; then
			break;
		else
			echo "[-] Invalid Input. Try again."
		fi
	done
	echo "$name"
}

# display_get_volume_options funcation displays options to get volumne
display_get_volume_options(){
	echo "[*] Select Options for adding Volume:"
	echo "=> Select current: y"
	echo "=> No volume: n"
	echo "=> Type the path for volume"
}

# get_volume function ask user for adding volumne to container. Requires 1 parameter
# $1 container_name
get_volume(){
	local volume
	read -p ">>" volume

	if [[ $volume == "y" ]]; then
		volume=$(pwd)
	fi

	if  [ $volume ] && [ $volume != n ]; then
		volumeoptions="--volume $volume:/home/$1"
	fi
	echo "$volumeoptions"
}

# get_ports open ports frorm container to host
get_ports(){
	local ports portoptions
	read -p "Open ports n/[80:81] >>" ports
	if  [ $ports ] && [ $ports != n ]; then
		portoptions="-p $ports"
	fi
	echo "$portoptions"
}

# create_new_container creates new docker container.
create_new_container(){
	local name volume portoptions
	name=$(get_name)
	display_get_volume_options
	volumeoptions=$(get_volume $name)
	portoptions=$(get_ports)
	docker run -it --name $name $volumeoptions $portoptions $image
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
	op|open_ports)
	  open_ports
	;;
	h|help)
	  help
	;;
	*)
	  start_container
	;;
esac