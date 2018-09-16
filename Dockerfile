FROM phusion/baseimage:0.10.2
MAINTAINER Denys Zhdanov <denis.zhdanov@gmail.com>

RUN apt-get -y update \
  && apt-get -y upgrade \
  && apt-get -y install vim \
  python-dev \
  python-flup \
  python-pip \
  python-ldap \
  expect \
  git \
  memcached \
  libffi-dev \
  libcairo2 \
  libcairo2-dev \
  python-cairo \
  python-rrdtool \
  pkg-config \
  nodejs \
  && rm -rf /var/lib/apt/lists/*

# choose a timezone at build-time
# use `--build-arg CONTAINER_TIMEZONE=Europe/Brussels` in `docker build`
ARG CONTAINER_TIMEZONE
ENV DEBIAN_FRONTEND noninteractive

RUN if [ ! -z "${CONTAINER_TIMEZONE}" ]; \
    then ln -sf /usr/share/zoneinfo/$CONTAINER_TIMEZONE /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata; \
    fi

ARG version=1.1.4
ARG whisper_version=${version}
ARG carbon_version=${version}
ARG graphite_api_version=1.1.2

ARG whisper_repo=https://github.com/graphite-project/whisper.git
ARG carbon_repo=https://github.com/graphite-project/carbon.git
ARG graphite_api_repo=https://github.com/brutasse/graphite-api.git

ARG statsd_version=v0.8.0

ARG statsd_repo=https://github.com/etsy/statsd.git

# install whisper
RUN git clone -b ${whisper_version} --depth 1 ${whisper_repo} /usr/local/src/whisper
WORKDIR /usr/local/src/whisper
RUN python ./setup.py install

# install carbon
RUN git clone -b ${carbon_version} --depth 1 ${carbon_repo} /usr/local/src/carbon
WORKDIR /usr/local/src/carbon
RUN pip install -r requirements.txt \
  && python ./setup.py install


# install graphite-api
# RUN git clone - ${graphite_api_version} --depth 1 ${graphite_api_repo} /usr/local/src/graphite-api
# WORKDIR /usr/local/src/graphite-api
# RUN pip install -r requirements.txt \
#   && python ./setup.py install

# install graphite-api
RUN apt-get install -y build-essential
RUN pip install gunicorn graphite-api[sentry,cyanite]
ONBUILD ADD graphite-api.yaml /etc/graphite-api.yaml
ONBUILD RUN chmod 0644 /etc/graphite-api.yaml
EXPOSE 8000
CMD exec gunicorn -b 0.0.0.0:8000 -w 2 --log-level debug graphite_api.app:app

# install statsd
RUN git clone -b ${statsd_version} ${statsd_repo} /opt/statsd

# config graphite
ADD conf/opt/graphite/conf/*.conf /opt/graphite/conf/

# config statsd
ADD conf/opt/statsd/config_*.js /opt/statsd/

# logging support
RUN mkdir -p /var/log/carbon /var/log/graphite /var/log/nginx
ADD conf/etc/logrotate.d/graphite-statsd /etc/logrotate.d/graphite-statsd

# daemons
ADD conf/etc/service/carbon/run /etc/service/carbon/run
ADD conf/etc/service/carbon-aggregator/run /etc/service/carbon-aggregator/run
ADD conf/etc/service/graphite/run /etc/service/graphite/run
ADD conf/etc/service/statsd/run /etc/service/statsd/run
ADD conf/etc/service/nginx/run /etc/service/nginx/run

# default conf setup
ADD conf /etc/graphite-statsd/conf
ADD conf/etc/my_init.d/01_conf_init.sh /etc/my_init.d/01_conf_init.sh

# cleanup
RUN apt-get clean\
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# defaults
EXPOSE 80 2003-2004 2023-2024 8080 8125 8125/udp 8126 8000
VOLUME ["/opt/graphite/conf", "/opt/graphite/storage", "/etc/graphite-api.yaml", "/opt/statsd", "/etc/logrotate.d", "/var/log"]
WORKDIR /
ENV HOME /root
ENV STATSD_INTERFACE udp

CMD ["/sbin/my_init"]
