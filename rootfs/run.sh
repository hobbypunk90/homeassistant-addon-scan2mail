#!/usr/bin/with-contenv bashio

ulimit -n 1048576

#bashio::log.info "Preparing directories"
bashio::log.info "Starting scan2mail"

ruby /app/start.rb
