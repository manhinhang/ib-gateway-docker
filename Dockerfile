FROM ubuntu:24.04 as dependencies

# install dependencies
RUN  apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y \
  xvfb \
  libxtst6 \
  libxrender1 \
  x11-utils \
  socat \
  procps \
  xterm


FROM eclipse-temurin:21 as ibgw
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
  build-essential \
  net-tools \
  expect

# set environment variables
ENV TWS_INSTALL_LOG=/root/Jts/tws_install.log \
    IBC_INI=/root/ibc/config.ini \
    IBC_PATH=/opt/ibc \
    TWS_PATH=/root/Jts \
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

# Create a custom Java runtime
RUN $JAVA_HOME/bin/jlink \
         --add-modules java.base \
         --strip-debug \
         --no-man-pages \
         --no-header-files \
         --compress=2 \
         --output /javaruntime

# copy IBC/Jts configs
COPY ibc/config.ini ${IBC_INI}

FROM ubuntu:24.04

ENV TWS_INSTALL_LOG=/root/Jts/tws_install.log
ENV IBC_INI=/root/ibc/config.ini
ENV IBC_PATH=/opt/ibc
ENV TWS_PATH=/root/Jts
ENV TWOFA_TIMEOUT_ACTION=restart
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH "${JAVA_HOME}/bin:${PATH}"
COPY --from=ibgw /javaruntime $JAVA_HOME

COPY --from=dependencies / /
COPY --from=ibgw /opt/ibc /opt/ibc
COPY --from=ibgw /root/Jts /root/Jts

# install healthcheck tool
ADD healthcheck/healthcheck/build/distributions/healthcheck.tar /
ENV PATH="${PATH}:/healthcheck/bin"

# copy cmd script
WORKDIR /root
COPY start.sh /root/start.sh
RUN chmod +x /root/start.sh

# set display environment variable (must be set after TWS installation)
ENV DISPLAY=:0

ENV IBGW_PORT 4002

EXPOSE $IBGW_PORT

ENTRYPOINT [ "sh", "/root/start.sh" ] 
