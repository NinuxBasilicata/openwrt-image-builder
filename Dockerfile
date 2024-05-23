FROM debian:stable-slim AS build-stage
ARG DEVICE=X86_64
ARG OPENWRT_VERSION=v23.05.3
ARG SHOULD_ADD_HAASMESH=0
ARG CPUS

## Install dependencies
RUN apt-get update
RUN apt-get install -y sudo build-essential clang flex g++ gawk gettext \
      git libncurses5-dev libssl-dev python3-distutils rsync unzip zlib1g-dev \
      file wget
RUN apt-get clean

# Add openwrt user
RUN useradd -m openwrt && \
    echo 'openwrt ALL=NOPASSWD: ALL' > /etc/sudoers.d/openwrt

## Clone and prepare OpenWRT
USER openwrt
WORKDIR /home/openwrt

RUN git clone -b $OPENWRT_VERSION git://git.openwrt.org/openwrt/openwrt.git

## Custom Files
RUN rm -rf openwrt/files
COPY root_files /home/openwrt/openwrt/files

## Configure feeds
RUN echo "src-git chilli https://github.com/openwisp/coova-chilli-openwrt.git" > /home/openwrt/openwrt/feeds.conf
RUN echo "src-git openwisp_config https://github.com/openwisp/openwisp-config.git^1.0.1" >> /home/openwrt/openwrt/feeds.conf
RUN echo "src-git openwisp_monitoring https://github.com/openwisp/openwrt-openwisp-monitoring.git" >> /home/openwrt/openwrt/feeds.conf
RUN echo "src-git zerotier https://github.com/mwarning/zerotier-openwrt.git" >> /home/openwrt/openwrt/feeds.conf
RUN sed '/telephony/d' /home/openwrt/openwrt/feeds.conf.default >> /home/openwrt/openwrt/feeds.conf
RUN openwrt/scripts/feeds update -a
RUN openwrt/scripts/feeds install -a

RUN rm -rf openwrt/package/feeds/luci/luci-app-apinger
RUN rm -rf openwrt/.config*


WORKDIR /home/openwrt/openwrt
COPY devices/$DEVICE.config /home/openwrt/openwrt/.config
COPY devices/base-config /home/openwrt/base-config
USER root
RUN chmod 777 /home/openwrt/openwrt/.config
RUN cat /home/openwrt/base-config >> /home/openwrt/openwrt/.config
USER openwrt
RUN export TERM=xterm

# Apply config changes
RUN make defconfig
RUN make download
# Build OpenWRT
RUN if [ -z $CPUS ]; then \
    make -j $(($(nproc)+1)) V=sc download world \
    ; else \
    make -j$CPUS V=sc download world \
    ; fi

FROM scratch AS export-stage
COPY --from=build-stage /home/openwrt/openwrt/bin/targets/ /
