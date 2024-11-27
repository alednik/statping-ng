# Instruction to build binary for linux(amd64)
1. Build docker image by command `docker build -t statping-builder`
2. Create docker container from built images by command `docker create --name temp-container statping-builder`
3. Copy built binary from container to local host by command `docker cp temp-container:/usr/local/bin/statping ./statping-build/`