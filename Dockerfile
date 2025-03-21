ARG BUILD_FROM
FROM $BUILD_FROM

LABEL io.hass.version="1.0" io.hass.type="addon" io.hass.arch="aarch64|amd64"

# Setup base
# hadolint ignore=DL3018
RUN apk update \
  && apk add nano sane ruby \
  && rm -fr /var/cache/apk

# Copy root filesystem
COPY rootfs /

RUN cd /app && bundle install

RUN chmod a+x /run.sh

CMD ["/run.sh"]
