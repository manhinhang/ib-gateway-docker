FROM python:3.11-slim
# IBC Version : https://github.com/IbcAlpha/IBC/releases
ARG IBC_VER="3.18.0"
# ib_insync : https://pypi.org/project/ib-insync/#history
ARG IB_INSYNC_VER="0.9.86"

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
RUN pip install ib_insync==$IB_INSYNC_VER

# set environment variables
ENV TWS_INSTALL_LOG=/root/Jts/tws_install.log \
    ibcIni=/root/ibc/config.ini \
    ibcPath=/opt/ibc \
    javaPath=/opt/i4j_jres \
    twsPath=/root/Jts \
    twsSettingsPath=/root/Jts \
    IB_GATEWAY_PING_CLIENT_ID=1 \
    ibAccMaxRetryCount=30

# make dirs
RUN mkdir -p /tmp && mkdir -p ${ibcPath} && mkdir -p ${twsPath}

# download IB TWS
RUN wget -q -O /tmp/ibgw.sh https://download2.interactivebrokers.com/installers/ibgateway/stable-standalone/ibgateway-stable-standalone-linux-x64.sh
RUN chmod +x /tmp/ibgw.sh

# download IBC
RUN wget -q -O /tmp/IBC.zip https://github.com/IbcAlpha/IBC/releases/download/$IBC_VER-Update.1/IBCLinux-$IBC_VER.zip
RUN unzip /tmp/IBC.zip -d ${ibcPath}
RUN chmod +x ${ibcPath}/*.sh ${ibcPath}/*/*.sh

# install TWS, write output to file so that we can parse the TWS version number later
RUN touch $TWS_INSTALL_LOG
COPY install_ibgw.exp /tmp/install_ibgw.exp
RUN chmod +x /tmp/install_ibgw.exp
RUN /tmp/install_ibgw.exp

# remove downloaded files
RUN rm /tmp/ibgw.sh /tmp/IBC.zip

# copy IBC/Jts configs
COPY ibc/config.ini ${ibcIni}
COPY ibc/jts.ini ${twsPath}/jts.ini

# copy cmd script
WORKDIR /root
COPY cmd.sh /root/cmd.sh
RUN chmod +x /root/cmd.sh

# python script for /root directory
COPY src/bootstrap.py /root/bootstrap.py
RUN chmod +x /root/bootstrap.py
COPY src/ib_account.py /root/ib_account.py
RUN chmod +x /root/ib_account.py

# set display environment variable (must be set after TWS installation)
ENV DISPLAY=:0
ENV GCP_SECRET=False

ENV IBGW_PORT 4002
ENV IBGW_WATCHDOG_CONNECT_TIMEOUT 30
ENV IBGW_WATCHDOG_APP_STARTUP_TIME 30
ENV IBGW_WATCHDOG_APP_TIMEOUT 30
ENV IBGW_WATCHDOG_RETRY_DELAY 2
ENV IBGW_WATCHDOG_PROBE_TIMEOUT 4

EXPOSE $IBGW_PORT

ENTRYPOINT [ "sh", "/root/cmd.sh" ] 
