# Docker container for [IHC® Captain](https://jemi.dk/ihc/)

#### Build on IHC Captain [v2.0.26](VERSION) written in [Go](https://go.dev/), for Raspberry Pi ARM64, controlling two IHC® Controllers.

The installationprocess will end up starting two docker containers (one for each IHC® Controller) using docker compose.
The containers will expose port 8100 respectively 8200, on which IHC® Captain can be reached.

## Usage

* Open the web interface at 'http://[raspberry-pi-ip-address:8100](raspberry-pi-ip-address:8100)' and/or 'http://[raspberry-pi-ip-address:8200](raspberry-pi-ip-address:8200)'.
* After this is referred to [IHC® Captain's manual](https://jemi.dk/ihc/#mainmain).

## Requirements
- Raspberry Pi 3 Model B Plus Rev 1.3. Linux 6.12.47+rpt-rpi-v8installed with Debian GNU/Linux 13 (trixie) - 64 bit
- Internet access and attached to the same local network as the two IHC® Controllers.
- Docker (if you are new to Docker, see [Docker Engine installation guide for Debian](https://docs.docker.com/engine/install/debian/)).
- User credentials for a specific user, with administrator rights on the IHC® Controller for this purpose.

## Building IHC Docker image for docker compose.

##### This is only required when the Docker image has not been pushed to Docker hub.

- Download binary from download section [Download IHC Captain](https://jemi.dk/ihc/#download) >- **Standalone Binaries & Docker / Proxmox**. 
- Change the dropdown fields [**Windown**] to [**Raspberry pi (DietPi/Linux)**] and [**x64 (AMD64)**] to [**Alle arkitekturer**].
- Download [Image **Raspberry Pi arm64**] image.
- Unback the **.zip** image and rename the unpacked file to **goihccap**

PS: Image for this build is **IHCCaptain_2.0.26_rpi-arm64_20261028-2308**

### Crete the **Dockerfile** for building the image

The **[Dockerfile](host\jemiDickerfile)** provided at [IHC® Captain](https://jemi.dk/ihc/#installation) -> Installationsguide -> Docker has a couple of issues when started.

-  level=WARN msg="Running as root is not recommended. Please run as a non-privileged user (e.g., dietpi)." component=MAIN
- level=INFO msg="Loading definitions from embedded storage" component=SYSTEM
That’s an informational startup message: the app is loading its definitions from storage embedded in the program. By itself, it doesn’t indicate an error 
-  A non-root Linux process generally can’t bind directly to ports below 1024, such as 80 or 443.

To overcome the warning a user is added in the image. The user ID (UID) is choosen to 10000 in order to prevent the use of a host users priviliges, when a host directory (docker run ... -v ${PWD}/data:/app/data ...) is mounted.

The app **goihccap** selected 8080 for HTTP and 8443 for HTTPS, so these ports are exposed instead of 80 and 443.

The **[Dockerfile](Dockerfile)**, locaed in the same directory as the **goihccap** file, should contain:

```yaml
FROM alpine:latest

RUN apk --no-cache add ca-certificates tzdata libc6-compat \
 && adduser -D -u 10000 appuser \
 && mkdir -p /app/data \
 && chown -R appuser:appuser /app

WORKDIR /app
COPY VERSION .
COPY --chown=appuser:appuser goihccap .
RUN chmod +x goihccap

EXPOSE 8080 8443
USER appuser
ENTRYPOINT ["./goihccap"]
```

### Build the image

Building the image in Docker Desktop for windows, creates an image fro linux/amd64. When run on linux/arm64/v8, the following warning will apear:

###### WARNING: The requested image's platform (linux/amd64) does not match the detected host platform (linux/arm64/v8) and no specific platform was requested**

Build the image using **docker buildx build --platform linux/amd64,linux/arm64 ...** instead, but the current Buildx builder might use a docker driver, which doesn’t support multi-platform builds. If so! Create and select a docker-container builder:

```Bash
docker buildx create --name multiarch --driver docker-container --use
docker buildx inspect --bootstrap
```

Create and select a docker-container builder:

```yaml
docker buildx build --platform linux/amd64,linux/arm64 \  
  -t sbv1307/docker-ihccaptain:v2.0.26 \
  -t sbv1307/docker-ihccaptain:latest \
  --push .
```

### To verify the image

On a Raspberry PI (CPU model arm64 ) run the following command:
PS: Running it none-detached (obmit the -d option) will show messages!

```Bash
mkdir -p ${PWD}/data
chmod -R a+rwX data   # Because UID 10000 in the image will read and write to /app/data, this user needs rw access to the host directory. This command adds rw for all.

docker run --name ihc-server --network host -v ${PWD}/data:/app/data sbv1307/docker-ihccaptain:latest
```

After verification - cleanup the environment.
```Bash
# remove all Docker resources on the machine despite having no running containers
docker system prune --all --volumes --force

# Remove Exited containers
docker rm $(docker ps --filter STATUS=exited -q)

# Remove images related to sbv1307/docker-ihccaptain
docker rmi $(docker image ls sbv1307/docker-ihccaptain -q)

# Remove all unused volumes including unused named volumes - Might not be necessary in this context
docker volume prune -a
```


## Installation instructions


1. Create Environment file for docker compose.

```Bash
vi .env
```
Then add:

```basb
# IHC A 
IHC_A_IP=nnn.nnn.nnn.nnn
IHC_A_USERNAME="username"
IHC_A_PASSWORD="password"

# IHC B 
IHC_B_IP=nnn.nnn.nnn.nnn
IHC_B_USERNAME="username"
IHC_B_PASSWORD="password"
```

2. Create a file called [`compose.yaml`](compose.yaml) with the following content:

```bash
services:
  ihc-server-A:
    image: sbv1307/docker-ihccaptain:latest
    container_name: ihc-server-A
    restart: always
    #  Compose uses a separate bridge network by default, where ports 80 and 443 are free inside the container.
    # The app auto-selects those ports, which is why 80 and 443 is mapped.
    ports:
      - 8100:80
      - 9100:443
    volumes:
      - ihcA_data:/app/data
    environment:
      IHC_IP: ${IHC_A_IP}
      IHC_USERNAME: "${IHC_A_USERNAME}"
      IHC_PASSWORD: "${IHC_A_PASSWORD}"

  ihc-server-B:
    image: sbv1307/docker-ihccaptain:latest
    container_name: ihc-server-B
    restart: always
   #  Compose uses a separate bridge network by default, where ports 80 and 443 are free inside the container.
    # The app auto-selects those ports, which is why 80 and 443 is mapped.
    ports:
      - 8200:80
      - 9200:443
    volumes:
      - ihcB_data:/app/data
    environment:
      IHC_IP: ${IHC_B_IP}
      IHC_USERNAME: "${IHC_B_USERNAME}"
      IHC_PASSWORD: "${IHC_B_PASSWORD}"

volumes:
  ihcA_data:
  ihcB_data:
```

3. Validate the **docker-compose.yml** file an check that substitutions for IP address, user name and password is correct.

```Bash
docker compose config
``


4. Start the docker containers with `docker-compose up -d`.

```bash
docker-compose up -d
```

