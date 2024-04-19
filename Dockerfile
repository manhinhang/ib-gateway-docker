FROM python:3.11-slim
# IBC Version : https://github.com/IbcAlpha/IBC/releases
ARG IBC_VER="3.18.0"
ARG IBC_ASSET_URL="https://github.com/IbcAlpha/IBC/releases/download/3.18.0-Update.1/IBCLinux-3.18.0.zip"
ARG IB_GATEWAY_MAJOR="10"
ARG IB_GATEWAY_MINOR="19"

# install dependencies
RUN  apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y wget \
  unzip \
  xvfb \
  libxtst6 \
  libxrender1 \
  build-essential \
  net-tools \
  x11-utils \
  socat \
  expect \
  procps \
  xterm
RUN apt install -y openjdk-17-jre

# set environment variables
ENV TWS_INSTALL_LOG=/root/Jts/tws_install.log \
    IBC_INI=/root/ibc/config.ini \
    IBC_PATH=/opt/ibc \
    javaPath=/opt/i4j_jres \
    TWS_PATH=/root/Jts \
    twsSettingsPath=/root/Jts \
    TWOFA_TIMEOUT_ACTION=restart \
    IB_GATEWAY_MAJOR=${IB_GATEWAY_MAJOR} \
    IB_GATEWAY_MINOR=${IB_GATEWAY_MINOR} 

# make dirs
RUN mkdir -p /tmp && mkdir -p ${IBC_PATH} && mkdir -p ${TWS_PATH}

# download IB TWS
RUN wget -q -O /tmp/ibgw.sh https://download2.interactivebrokers.com/installers/ibgateway/stable-standalone/ibgateway-stable-standalone-linux-x64.sh
RUN chmod +x /tmp/ibgw.sh

# download IBC
RUN wget -q -O /tmp/IBC.zip ${IBC_ASSET_URL}
RUN unzip /tmp/IBC.zip -d ${IBC_PATH}
RUN chmod +x ${IBC_PATH}/*.sh ${IBC_PATH}/*/*.sh

# install TWS, write output to file so that we can parse the TWS version number later
RUN touch $TWS_INSTALL_LOG
COPY install_ibgw.exp /tmp/install_ibgw.exp
RUN chmod +x /tmp/install_ibgw.exp
RUN /tmp/install_ibgw.exp

# remove downloaded files
RUN rm /tmp/ibgw.sh /tmp/IBC.zip

# copy IBC/Jts configs
COPY ibc/config.ini ${IBC_INI}

# install healthcheck tool
ADD healthcheck/healthcheck/build/distributions/healthcheck.tar /
ENV PATH="${PATH}:/healthcheck/healthcheck/bin"

# copy cmd script
WORKDIR /root
COPY cmd.sh /root/cmd.sh
RUN chmod +x /root/cmd.sh

# set display environment variable (must be set after TWS installation)
ENV DISPLAY=:0

ENV IBGW_PORT 4002

EXPOSE $IBGW_PORT

ENTRYPOINT [ "sh", "/root/cmd.sh" ] 
