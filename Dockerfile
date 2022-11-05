FROM python:3.10-slim

ARG IBG_VERSION=stable
ENV IBG_VERSION=${IBG_VERSION:-stable}
ENV IBC_VERSION=3.14.0
ENV IB_INSYNC_VERSION=0.9.71

RUN echo building IB GW ${IBG_VERSION}

# install dependencies
RUN  apt-get update \
  # && apt-get upgrade -y \
  && apt-get install -y \
  wget \
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
  xterm \
  x11vnc
RUN apt install -y openjdk-17-jre
RUN python -m pip install --upgrade pip
RUN pip install ib_insync==${IB_INSYNC_VERSION} google-cloud-secret-manager==2.11.1

# set environment variables
ENV TWS_INSTALL_LOG=/root/Jts/tws_install.log \
    ibcIni=/root/ibc/config.ini \
    ibcPath=/opt/ibc \
    javaPath=/opt/i4j_jres \
    twsPath=/root/Jts \
    twsSettingsPath=/root/Jts \
    ibAccMaxRetryCount=30

# make dirs
RUN mkdir -p /tmp && mkdir -p ${ibcPath} && mkdir -p ${twsPath}

# download & install IBC
RUN wget -q -O /tmp/IBC.zip https://github.com/IbcAlpha/IBC/releases/download/${IBC_VERSION}/IBCLinux-${IBC_VERSION}.zip
RUN unzip /tmp/IBC.zip -d ${ibcPath}
RUN chmod +x ${ibcPath}/*.sh ${ibcPath}/*/*.sh
# remove downloaded files
RUN rm /tmp/IBC.zip

# download IB GW
RUN wget -q -O /tmp/ibgw.sh https://download2.interactivebrokers.com/installers/ibgateway/${IBG_VERSION}-standalone/ibgateway-${IBG_VERSION}-standalone-linux-x64.sh
RUN chmod +x /tmp/ibgw.sh
# install IB Gateway, write output to file so that we can parse the version number later
COPY install_ibgw.exp /tmp/install_ibgw.exp
RUN chmod +x /tmp/install_ibgw.exp
RUN /tmp/install_ibgw.exp
# remove downloaded files
RUN rm /tmp/ibgw.sh

# copy IBC/Jts configs
COPY ibc/config.ini ${ibcIni}
COPY ibc/jts.ini ${twsPath}/jts.ini

# copy cmd script
WORKDIR /root
COPY cmd.sh /root/cmd.sh
RUN chmod +x /root/cmd.sh

# python script for /root directory
COPY src/*.py /root/
RUN chmod +x /root/*.py

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

HEALTHCHECK --interval=1m --timeout=30s --start-period=10s --retries=3 \
  CMD python healthcheck.py || exit 1

ENTRYPOINT [ "sh", "/root/cmd.sh" ] 
