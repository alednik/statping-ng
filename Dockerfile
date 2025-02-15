# Stage 1: Frontend build
FROM node:16.14.0-alpine AS frontend
LABEL maintainer="Statping-ng (https://github.com/statping-ng)"
ARG BUILDPLATFORM
WORKDIR /statping
COPY ./frontend/package.json .
COPY ./frontend/yarn.lock .
RUN yarn install --pure-lockfile --network-timeout 1000000
COPY ./frontend .
RUN yarn build && yarn cache clean

# Stage 2: Backend build
FROM --platform=linux/amd64 golang:1.20.0 AS backend
LABEL maintainer="Statping-NG (https://github.com/statping-ng)"
ARG VERSION
ARG COMMIT
ARG BUILDPLATFORM
ARG TARGETARCH=amd64  # Убедимся, что архитектура задана явно

# Устанавливаем окружение для сборки под amd64
ENV GOOS=linux GOARCH=amd64 CGO_ENABLED=1

RUN dpkg --add-architecture amd64
RUN apt-get update && apt-get install -y \
    gcc g++ make git autoconf \
    libtool wget curl jq && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /root
RUN git clone --depth 1 --branch 3.6.2 https://github.com/sass/sassc.git
RUN . sassc/script/bootstrap && make -C sassc -j4

WORKDIR /go/src/github.com/statping-ng/statping-ng
ADD go.mod go.sum ./
RUN go mod download

COPY cmd ./cmd
COPY database ./database
COPY handlers ./handlers
COPY notifiers ./notifiers
COPY source ./source
COPY types ./types
COPY utils ./utils
COPY --from=frontend /statping/dist/ ./source/dist/

# RUN go install github.com/GeertJohan/go.rice/rice@latest && \
#     echo $(go env GOPATH)/bin && ls $(go env GOPATH)/bin
# RUN cd source && rice embed-go
RUN go install github.com/GeertJohan/go.rice/rice@latest && \
    export PATH=/go/bin/linux_amd64:$PATH && \
    cd source && rice embed-go
RUN go build -a -ldflags "-s -w -extldflags -static -X main.VERSION=$VERSION -X main.COMMIT=$COMMIT" -o statping --tags "musl netgo linux" ./cmd
RUN chmod a+x statping && mv statping /go/bin/statping

# Stage 3: Final image based on Amazon Linux 2
FROM amazonlinux:2
LABEL maintainer="Statping-NG (https://github.com/statping-ng)"

RUN yum install -y libgcc libstdc++ ca-certificates curl jq && \
    yum clean all && \
    update-ca-trust

COPY --from=backend /go/bin/statping /usr/local/bin/
COPY --from=backend /root/sassc/bin/sassc /usr/local/bin/
COPY --from=backend /usr/local/share/ca-certificates /usr/local/share/

WORKDIR /app
VOLUME /app

ENV IS_DOCKER=true
ENV SASS=/usr/local/bin/sassc
ENV STATPING_DIR=/app
ENV PORT=8080
ENV BASE_PATH=""

EXPOSE $PORT

HEALTHCHECK --interval=60s --timeout=10s --retries=3 CMD if [ -z "$BASE_PATH" ]; then HEALTHPATH="/health"; else HEALTHPATH="/$BASE_PATH/health" ; fi && curl -s "http://localhost:${PORT}$HEALTHPATH" | jq -r -e ".online==true"

CMD statping --port $PORT
