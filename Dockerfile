# syntax=docker.io/docker/dockerfile:1.4
ARG SUNODO_SDK_VERSION=0.2.0

FROM sunodo/sdk:${SUNODO_SDK_VERSION} as sunodo-workspace

RUN <<EOF
apt-get update
apt-get install -y --no-install-recommends e2tools xxd jq wget
rm -rf /var/lib/apt/lists/*
EOF

RUN curl http://dkolf.de/src/dkjson-lua.fsl/raw/dkjson.lua?name=6c6486a4a589ed9ae70654a2821e956650299228 -o /usr/share/lua/5.4/dkjson.lua

WORKDIR /opt/workspace

RUN chmod 777 .

COPY video_processor.sh .

RUN <<EOF
echo '#!/usr/bin/env lua5.4

local json = require("dkjson")

function string.fromhex(str)
    return (str:gsub('"'"'..'"'"', function (cc)
        return string.char(tonumber(cc, 16))
    end))
end

local function write_be256(value)
    io.stdout:write(string.rep("\\0", 32 - 8))
    io.stdout:write(string.pack(">I8", value))
end

local function encode_input()
    local j, _, e = json.decode(io.read("*a"))
    if not j then error(e) end
    local payload = assert(j.payload, "missing payload")
    local payload_bin = payload:fromhex()
    write_be256(32)
    write_be256(#payload_bin)
    io.stdout:write(payload_bin)
end

encode_input()
' > encode_input.lua
chmod +x encode_input.lua
EOF

FROM sunodo-workspace as celestia-wo-builder

WORKDIR /opt/build

ARG GOVERSION=1.21.2

RUN wget https://go.dev/dl/go${GOVERSION}.linux-$(dpkg --print-architecture).tar.gz && \
    tar -C /usr/local -xzf go${GOVERSION}.linux-$(dpkg --print-architecture).tar.gz

ENV PATH=/usr/local/go/bin:${PATH}

COPY utils .

RUN go build celestia_blob_wo.go

FROM --platform=linux/riscv64 cartesi/python:3.10-slim-jammy as base

ARG SUNODO_SDK_VERSION

LABEL io.sunodo.sdk_version=${SUNODO_SDK_VERSION}
LABEL io.cartesi.rollups.ram_size=512Mi
LABEL io.cartesi.rollups.data_size=32Mb

ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=Etc/UTC

ARG MACHINE_EMULATOR_TOOLS_VERSION=0.12.0
RUN <<EOF
apt-get update
apt-get install -y --no-install-recommends busybox-static=1:1.30.1-7ubuntu3 ca-certificates=20230311ubuntu0.22.04.1 curl=7.81.0-1ubuntu1.14 \
    build-essential=12.9ubuntu3 python3-numpy=1:1.21.5-1ubuntu22.04.1 python3-opencv=4.5.4+dfsg-9ubuntu4 libopenblas-dev=0.3.20+ds-1
curl -fsSL https://github.com/cartesi/machine-emulator-tools/releases/download/v${MACHINE_EMULATOR_TOOLS_VERSION}/machine-emulator-tools-v${MACHINE_EMULATOR_TOOLS_VERSION}.tar.gz \
  | tar -C / --overwrite -xvzf -
rm -rf /var/lib/apt/lists/*
EOF

# libavcodec-dev libavformat-dev libswscale-dev libopencv-dev x264 libx264-dev  ffmpeg

ENV PATH="/opt/cartesi/bin:${PATH}"
ENV PYTHONPATH="/opt/venv/lib/python3.10/site-packages:/usr/lib/python3/dist-packages"

WORKDIR /opt/cartesi/dapp

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .
RUN pip3 install -r requirements.txt --no-cache

# RUN apt remove -y build-essential curl git && apt -y autoremove

# RUN rm requirements.txt \
#     && find /usr/local/lib -type d -name __pycache__ -exec rm -r {} + \
#     && find /var/log \( -name '*.log' -o -name '*.log.*' \) -exec truncate -s 0 {} \;

COPY ./video_processor.py .
COPY ./model model
COPY ./data/glasses.png data/glasses.png

FROM base as standalone

COPY ./process_video.py .

FROM base as dapp

COPY ./dapp.py .

ENV ROLLUP_HTTP_SERVER_URL="http://127.0.0.1:5004"

RUN <<EOF
echo '#!/bin/sh

set -e

export PYTHONPATH=/opt/venv/lib/python3.10/site-packages:/usr/lib/python3/dist-packages
python3 dapp.py
' > entrypoint.sh
chmod +x entrypoint.sh
EOF

ENTRYPOINT ["rollup-init"]
CMD ["/opt/cartesi/dapp/entrypoint.sh"]
