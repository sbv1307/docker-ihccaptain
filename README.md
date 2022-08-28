# Docker container for [IHC® Captain](https://jemi.dk/ihc/)

#### Build on IHC Captain version 1.54, for Raspberry Pi model 3, controlling two IHC® Controllers.

The installationprocess will end up starting two docker containers (one for each IHC® Controller).
The containers will expose port 8100 respectively 8200, on which IHC® Captain can be reached.

## Usage

* Open the web interface at 'http://[raspberry-pi-ip-address:8100](raspberry-pi-ip-address:8100)' and/or 'http://[raspberry-pi-ip-address:8200](raspberry-pi-ip-address:8200)'.
* At first, a dialog box is opened, in which username, password and the IP address for the IHC® Controller is entered.[](https://)
  'Use a specific IHC user, with administrator rights on the IHC® Controller for this purpose.'
* After this is referred to [IHC® Captain's manual](https://jemi.dk/ihc/#mainmain).

## Requirements

- Raspberry Pi model B v1.2. Installed with Raspberry Pi OS Lite (32-bit).
- Internet access and attached to the same local network as the two IHC® Controllers.
- Docker (if you are new to Docker, see [Installing Docker and Docker Compose](https://dev.to/rohansawant/installing-docker-and-docker-compose-on-the-raspberry-pi-in-5-simple-steps-3mgl)).
- User credentials for a specific user, with administrator rights on the IHC® Controller for this purpose.

## Installation instructions

1. Create a file called `docker-compose.yml` with the following content:

```bash
version: "3.9"

services:
  ihccaptainA:
    image: sbv1307/docker-ihccaptain:latest
    container_name: ihccaptainA
    restart: always
    ports:
      - 8100:80
      - 9100:443
    volumes:
      - ihcA_data:/opt/ihccaptain/data
  
  ihccaptainB:
    image: sbv1307/docker-ihccaptain:latest
    container_name: ihccaptainB
    restart: always
    ports:
      - 8200:80
      - 9200:443
    volumes:
      - ihcB_data:/opt/ihccaptain/data

volumes:
  ihcA_data:
  ihcB_data:
```

2. Start the docker containers with `docker-compose up -d`.

```bash
docker-compose up -d
```

## Detailed installation

Detailed installation instructions for this "Profe of Concept" (PoC) project can be found in the file `detailedInstall.xlsx`.

## Backup / Restore IHC Captain data (Manual process)

**The Backup process:**

- Log on to Raspberry pi
- Create two backup directories `mkdir ihcA_data` and `mkdir ihcB_data`
- Verify Docker container names pi_ihccaptainA_1 and pi_ihccaptainB_1 `docker ps`
- Copy IHC Captain data from the docker containers to local host
- - `docker cp pi_ihccaptainA_1:/opt/ihccaptain/data ./ihcA_data`
- - `docker cp pi_ihccaptainB_1:/opt/ihccaptain/data ./ihcB_data`
- Create backupfile. 
- - `tar cvf IHC_Captain.tar ./ihcA_data ./ihcB_data`
- Move IHC_Captain.tar to a secure location.

**The Restore process:**

- Log on to Raspberry pi.
- Get IHC_Captain.tar to current dir.
- Extract backup: `tar xvf IHC_Captain.tar .`
- Stop running containers: `docker-compose stop`
- Copy IHC Captain data into containers:
```bash
docker cp ./ihcA_data/data pi_ihccaptainA_1:/opt/ihccaptain/data
docker cp ./ihcB_data/data pi_ihccaptainB_1:/opt/ihccaptain/data
```
- Start IHC Captain containers: `docker-compose up -d`

## Backup IHC Captain data ("Semi" Automataed process)


**Preparations for automatisation.**

Create backup destination directory:
```bash
sudo mkdir -pm 1777 /mnt/remote/IHC_Captain-Docker-backup
```
Install ftp server
```bash
sudo apt update
sudo apt full-upgrade
sudo apt install vsftpd
```

Configure FTP server
```bash
sudo vi /etc/vsftpd.conf
```
Uncomment the following lines
```bash
write_enable=YES
local_umask=022
chroot_local_user=YES
```
Change the follwing lines:
```bash
anonymous_enable=NO
```
Add the follosing lines
```bash
user_sub_token=$USER
local_root=/mnt/remote
allow_writeable_chroot=YES
```
Restart FTP service
```bash
sudo service vsftpd restart
```

Add FTP user 
```bash
sudo useradd ftpuser
sudo passwd ftpuser
```

Verify FTP setup - From windows CMD do: ftp 192.168.10.117

**The Backup script**
Create a file called ´IHC_Captain-Docker-backupp.sh´ with the following content (OBS! Remember to chmod -x):


```bash
vi IHC_Captain-Docker-backup.sh
```
```bash
#!/bin/bash
# Set variables to give a flxiable environemnt
# Working directory is where the docker-compose.yml file is located

WORKING_DIR='/home/pi/IHC_Captain'

# Distenation directory is the directory in which the backup and logfiles are located
BACKUP_DIR='/mnt/remote/IHC_Captain-Docker-backup'
LOGFILE_DIR='/mnt/remote'
BACKUP_FILE="IHC_Captain-Docker_$(date +"%F_%H.%M.%S").bak"
ERROR_LOG="IHC_Captain-Docker-backup.log"

# When run from Cropn: Un-comment nest line to redirect ALL output to ERROR_LOG in LOGFILE_DIR
# exec &>> $LOGFILE_DIR/$ERROR_LOG

# Change directory to where docker-compose.yml file is located

cd $WORKING_DIR

# Prepare DEST_PATH's

if [[ -d "ihcA_data" ]]
then
    rm -r ihcA_data/*
else
  mkdir ihcA_data
fi

if [[ -d "ihcB_data" ]]
then
    rm -r ihcB_data/*
else
  mkdir ihcB_data
fi

# Run IHC backup commands.

/usr/bin/docker cp pi_ihccaptainA_1:/opt/ihccaptain/data ./ihcA_data
/usr/bin/docker cp pi_ihccaptainB_1:/opt/ihccaptain/data ./ihcB_data

# Compress backupfile
tar cvf $BACKUP_DIR/$BACKUP_FILE ./ihcA_data ./ihcB_data
/bin/gzip $BACKUP_DIR/$BACKUP_FILE

# Delete files more than 8 days old
/usr/bin/find $BACKUP_DIR/IHC_Captain-Docker* -mtime +2 -delete
```
```bash
chmod +x IHC_Captain-Docker-backup.sh
```

## Configure Hybrid Backup Sync on QNAP NAS2 to offload teslamate backup file

1. Login as admin to qnap-nas-2 and run Hybrid Bakcup Sync
2. Create job "Sync" -> Active Sync -> Sync Remote to Local
3. Choose "FTP" as Network Protocol
4. Sync Job Name: **IHC_Captain-Docker-backup->RaspberryPi>Docker-IHC-Captain>Backup**
```bash
 Settings: 
   TeslaMate-FTP
   IP address: 192.168.10.117
   Username: pi
   Password: 
```
5. Local destination: /RASPBERRY_PI_VOLUME/Docker-IHC-Captain/backup
6. Remopte Souce Folder: /IHC_Captain-Docker-backup
7. [Add] locations and go to 'Advanced settings'
```
Schedule:
  Periodically: Daily -> 02
Policy:
  Delete extra files
Filter:
  Include file types: Other -> *.gz
Events:
  Send alert emails when...: A job finishes
```


## **The Backup process**

1. Login to IHC Docker (192.168.10.117) and Run /home/IHC_Captain/IHC_Captain-Docker-backup.sh

Hybrid Backup Sync on QNAP NAS2 will pickup the generated backup file at the next periodically run at 02:00.

## Troubleshooting

Run an instance of `sbv1307/docker-ihccaptain:sh` instead of using the `:latest` image.
The `:sh` image, does not automatically run the startup script `run_ihc_captain_in_docker.sh`.

#### Usefull commands:

To stop the containers started by `docker-compose up -d`use the command:

````bash
docker-compose stop
````

To start an instance (container)e.g. for investigations purposes:
The containers tagged with "sh", does not start the IHC Captain services automatically.

```bash
docker run -it -p 8300:80 -p 9300:443 sbv1307/docker-ihccaptain:sh
```

Starting the instance (container) with the Docker Volume for IHC Captain mounted

```bash

docker run -it -p 8300:80 -p 9300:443 --mount source=ihc_captain_ihcA_data,target=/app  sbv1307/docker-ihccaptain:sh
```

When attached to the container, run and verify the services, started by
`sbv1307/docker-ihccaptain:sh`

```bash
[ ! -f /opt/ihccaptain/data/serverconfig.json ] && cp /opt/ihccaptain/dataOrg/serverconfig.json 
service php7.3-fpm start
service php7.3-fpm status
service nginx start
service nginx status
```

Other userfull commands:

````bash
docker ps -a
docker rm -f $(docker ps -aq)
docker volume ls
docker volume rm <Volume Name>
````

Command used to build sbv1307/docker-ihccaptain docker container.
Before building the container, modify the Docker file:

* Deside if the container will start IHC Captain services (wether or not to run the command
  `CMD /app/run_ihc_captain_in_docker.s` e.g. comment out the line.
* Deside which IHC Captain installer to use. P.t. the one at `http://jemi.dk/ihc/files/install` Fails to build the container.

```bash
docker build --pull --rm -f "Dockerfile" -t docker-ihccaptain:<TAG>
```


## Credits

- IHC® Captain by http://jemi.dk/ihc/
- arberg/docker-ihccaptain by https://github.com/arberg

## **Version History**
Issue: Restore process didn't work<br>
* Docker copy command incorrect as container has changed name after restart in a new working directory.<br>
Solved by: Defining fixed container names in docker-compose file<br>

* The Docker cp command in the Restore process has errors.<br>
`docker cp ./ihcA_data/data pi_ihccaptainA_1:/opt/ihccaptain/`<br>
changed to<br>
`docker cp ./ihcA_data/data pi_ihccaptainA_1:/opt/ihccaptain/data`<br>
And<br>
`docker cp ./ihcB_data/data pi_ihccaptainB_1:/opt/ihccaptain/`<br>
changed to<br>
`docker cp ./ihcB_data/data pi_ihccaptainB_1:/opt/ihccaptain/data`
