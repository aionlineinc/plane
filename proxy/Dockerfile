FROM nginx:alpine
RUN apk add --no-cache gettext
COPY nginx.conf.template /etc/nginx/conf.d/default.conf.template
RUN rm -f /etc/nginx/conf.d/default.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
