FROM ubuntu:22.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential cmake git python3 python3-pip \
    libopenmpi-dev openmpi-bin \
    && rm -rf /var/lib/apt/lists/*
RUN pip3 install reframe-hpc
WORKDIR /work
