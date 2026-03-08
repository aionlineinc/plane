#!/bin/sh
set -e
export UPSTREAM_API="${UPSTREAM_API:-plane-api}"
export UPSTREAM_WEB="${UPSTREAM_WEB:-plane-web}"
envsubst '${UPSTREAM_API} ${UPSTREAM_WEB}' < /etc/nginx/conf.d/default.conf.template > /etc/nginx/conf.d/default.conf
exec nginx -g 'daemon off;'
