#!/usr/bin/env bash

if [[ $# -lt 1 ]]
then
  echo 'Need to specify ip'
  exit 1
fi

RPI_IP=$1
RPI_DEFAULT_PASS="raspberry"
PI_EEPROM_DATE="2020-07-31"
PI_EEPROM_VERSION="pieeprom-${PI_EEPROM_DATE}"
PI_EEPROM_FILE="${PI_EEPROM_VERSION}.bin"
PI_EEPROM_NETBOOT_FILE="${PI_EEPROM_VERSION}-netboot.bin"
PI_EEPROM_LINK="https://github.com/raspberrypi/rpi-eeprom/raw/master/firmware/stable/${PI_EEPROM_FILE}"
ENV_FILE="rpi-$(echo $RPI_IP | tr . -).env"

ssh-keygen -R ${RPI_IP}
ssh-keyscan -H ${RPI_IP} >> ~/.ssh/known_hosts
sshpass -p "${RPI_DEFAULT_PASS}" ssh pi@${RPI_IP} << EOF
order=\$(vcgencmd bootloader_config | grep BOOT_ORDER | cut -d '=' -f 2)
echo "Order is \${order}"
if [[ \${order} = "0xf21" ]]
then
  echo 'Netboot is already enabled'
  exit 0
else
  echo 'Netboot is not enabled. Continue.'
fi 

if [[ -f ${PI_EEPROM_FILE} ]]
then
  rm ${PI_EEPROM_FILE}
fi
if [[ -f ${PI_EEPROM_NETBOOT_FILE} ]]
then
  rm ${PI_EEPROM_NETBOOT_FILE}
fi

rm *.rpi.env
rm bootconf.txt
if [[ ! -f ${PI_EEPROM_FILE} ]]
then
  echo "Get EEPROM from ${PI_EEPROM_LINK}"
  wget ${PI_EEPROM_LINK}
fi

echo 'Extract bootconf.txt'
sudo rpi-eeprom-config ${PI_EEPROM_FILE} > bootconf.txt

echo 'Updating bootconf'
sed -i 's/BOOT_ORDER=.*/BOOT_ORDER=0xf21/g' bootconf.txt
sed -i 's/ENABLE_SELF_UPDATE=.*/ENABLE_SELF_UPDATE=0/g' bootconf.txt
sed -i 's/POWER_OFF_ON_HALT=.*/POWER_OFF_ON_HALT=1/g' bootconf.txt

echo 'New bootconf'
cat bootconf.txt

echo 'Update EEPROM'
sudo rpi-eeprom-config --out ${PI_EEPROM_NETBOOT_FILE} --config bootconf.txt ${PI_EEPROM_FILE}
sudo rpi-eeprom-update -d -f ${PI_EEPROM_NETBOOT_FILE}

echo 'Get serial and MAC'
cat /proc/cpuinfo | grep Serial | tail -c 9 > ${ENV_FILE}
ip addr show eth0 | grep ether | awk '{print \$2}' >> ${ENV_FILE}
EOF

sshpass -p "${RPI_DEFAULT_PASS}" scp -r pi@${RPI_IP}:~/${ENV_FILE} ~/${ENV_FILE}

sshpass -p "${RPI_DEFAULT_PASS}" ssh pi@${RPI_IP} << EOF
sudo shutdown -r now
EOF
cat ~/${ENV_FILE}