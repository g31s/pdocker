# Building the Docker Image for Pdocker project.
# Version 1.1.0

echo "[*] Start Building..."
# Build the image
sudo docker build \
    --rm \
    -t pdocker .

# Add the alias to bashrc
echo "# Pdocker alias" >> ~/.profile
# Add  -v ~/hostpath/Projects:/Projects to share volume
echo "alias pdocker=`pwd`/pdocker.sh" >> ~/.profile
source ~/.profile 

echo "[*] Image Building Complete."
echo "[*] Use pdocker to start the enviroment. Enjoy."