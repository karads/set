sudo apt update -y
apt-get update -y
sudo apt install git python3-pip make build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev -y
sudo apt update -y && sudo apt upgrade -y && sudo apt install -y screen rand unzip nano curl libsodium-dev cmake g++ git build-essential libgmp-dev libnuma-dev net-tools bc python3 python3-pip dos2unix
sudo apt-get install inotify-tools -y
sudo add-apt-repository ppa:deadsnakes/ppa -y
sudo apt update -y
sudo apt install python3.10 -y
apt install unzip -y
apt install unzip nano screen ifstat rand fuse3 nload -y
sudo -v ; curl https://rclone.org/install.sh | sudo bash
sudo apt update -y
mv rclone.log /root/
mkdir /mnt/{temp,pw,up1,up2,up3,up4,up5,up6,up7,up8,up9,up10}
for i in {1..10}; do mkdir -p /root/check$i; done
mkdir /root/.config/
mkdir /root/.config/rclone/
mv rclone.conf /root/.config/rclone/
mv accounts.zip /root/
unzip /root/accounts.zip
chmod 777 client
screen -dmS bas bash start.sh
screen -dmS move bash move.sh
bash 10ups.sh
chmod +x /root/set/yeniup*.sh
for i in {1..10}; do screen -dmS up$i bash /root/set/yeniup$i.sh; done
