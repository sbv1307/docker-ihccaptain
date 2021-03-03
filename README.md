# Docker container for [IHC® Captain](https://jemi.dk/ihc/)

#### Build on IHC Captain version 1.54, for Raspberry Pi model 3, controlling two IHC® Controllers.

The installationprocess will end up starting two docker containers (one for each IHC® Controller).
The containers will expose port 8100 respectively 8200, on which IHC® Captain can be reached.

## Usage

1. Open the web interface at 'http://[raspberry-pi-ip-address:8100](raspberry-pi-ip-address:8100)' and/or 'http://[raspberry-pi-ip-address:8200](raspberry-pi-ip-address:8200)'.
2. At first, a dialog box is opened, in which username, password and the IP address for the IHC® Controller is entered.
   'Use a specific IHC user, with administrator rights on the IHC® Controller for this purpose.'
3. After this is referred to [IHC® Captain's manual](https://jemi.dk/ihc/#mainmain).

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
    restart: always
    ports:
      - 8100:80
      - 9100:443
    volumes:
      - ihcA_data:/opt/ihccaptain/data
  
  ihccaptainB:
    image: sbv1307/docker-ihccaptain:latest
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

## Troubleshooting

Run an instance of `sbv1307/docker-ihccaptain:sh` instead of using the `:latest` image.
The `:sh` image, does not run the startup script `run_ihc_captain_in_docker.sh` automatically.

#### Usefull commands:

To start an instance (container):

```bash
docker run -it -p 8300:80 -p 9300:443 sbv1307/docker-ihccaptain:sh
```

When attached to the container, run and verify the sercices, started by `sbv1307/docker-ihccaptain:sh`

```bash
[ ! -f /opt/ihccaptain/data/serverconfig.json ] && cp /opt/ihccaptain/dataOrg/serverconfig.json /opt/ihccaptain/data
service php7.3-fpm start
service php7.3-fpm status
service nginx start
service nginx status
```

Chedk 'http://[raspberry-pi-ip-address:8300](raspberry-pi-ip-address:8300)' to verify is IHC Captain is available.

## Credits

- IHC® Captain by http://jemi.dk/ihc/
- arberg/docker-ihccaptain by https://github.com/arberg
