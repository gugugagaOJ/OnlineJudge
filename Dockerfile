FROM alpine:3.19 AS downloader

WORKDIR /app

RUN <<EOS
set -ex
apk add unzip
wget https://github.com/gugugagaOJ/ojFE/releases/download/v2.5.2/dist.zip
unzip dist.zip
rm -f dist.zip
EOS

FROM python:3.12-alpine
ARG TARGETARCH
ARG TARGETVARIANT

ENV OJ_ENV production
WORKDIR /app

COPY ./deploy/requirements.txt /app/deploy/
# psycopg2: libpq-dev
# pillow: libjpeg-turbo-dev zlib-dev freetype-dev
RUN --mount=type=cache,target=/etc/apk/cache,id=apk-cahce-$TARGETARCH$TARGETVARIANT-final \
    --mount=type=cache,target=/root/.cache/pip,id=pip-cahce-$TARGETARCH$TARGETVARIANT-final \
    <<EOS
set -ex
apk update
apk add --no-cache gcc libc-dev python3-dev libpq libpq-dev libjpeg-turbo libjpeg-turbo-dev zlib zlib-dev freetype freetype-dev supervisor openssl curl unzip
pip install -r /app/deploy/requirements.txt
apk del gcc libc-dev python3-dev libpq-dev libjpeg-turbo-dev zlib-dev freetype-dev
EOS

# 1. Manually create the user/group (as discussed)
RUN set -x \
    && addgroup -g 101 -S nginx \
    && adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx

# 2. Install nginx but SKIP the crashing scripts
RUN apk add --no-cache --no-scripts nginx

# 3. Manually perform the work the post-install script usually does
#    (Create log/cache dirs and set permissions)
RUN mkdir -p /var/log/nginx /var/lib/nginx /var/tmp/nginx \
    && chown -R nginx:nginx /var/log/nginx /var/lib/nginx /var/tmp/nginx \
    && chmod 755 /var/log/nginx /var/lib/nginx /var/tmp/nginx

COPY ./ /app/
COPY --from=downloader --link /app/dist/ /app/dist/
RUN chmod -R u=rwX,go=rX ./ && chmod +x ./deploy/entrypoint.sh

HEALTHCHECK --interval=5s CMD [ "/usr/local/bin/python3", "/app/deploy/health_check.py" ]
EXPOSE 8000
ENTRYPOINT [ "/app/deploy/entrypoint.sh" ]
