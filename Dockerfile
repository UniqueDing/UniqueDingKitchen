FROM ghcr.io/cirruslabs/flutter:stable AS builder

WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
RUN flutter build web --wasm --no-source-maps --no-web-resources-cdn --no-wasm-dry-run

FROM python:3.12-slim

ARG SUPERCRONIC_VERSION=v0.2.29
ARG TARGETARCH
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV WEB_PORT=8080
ENV TZ=Asia/Shanghai

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl nginx \
    && rm -rf /var/lib/apt/lists/*

RUN ARCH="${TARGETARCH}" \
    && if [ -z "${ARCH}" ]; then ARCH="$(uname -m)"; fi \
    && case "${ARCH}" in \
      amd64|x86_64) SC_ARCH=amd64 ;; \
      arm64|aarch64) SC_ARCH=arm64 ;; \
      *) echo "Unsupported architecture: ${ARCH}"; exit 1 ;; \
    esac \
    && curl -fsSL "https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-${SC_ARCH}" -o /usr/local/bin/supercronic \
    && chmod +x /usr/local/bin/supercronic

WORKDIR /app

COPY --from=builder /app/build/web /app/site
COPY web/favicon.svg /app/site/favicon.svg
COPY web/manifest.json /app/site/manifest.json
COPY web/public/menu.md /app/defaults/menu.md
COPY scripts/generate_recommendation.py /app/scripts/generate_recommendation.py
COPY docker/entrypoint.sh /app/docker/entrypoint.sh

RUN chmod +x /app/docker/entrypoint.sh \
    && rm -f /etc/nginx/sites-enabled/default /etc/nginx/conf.d/default.conf

EXPOSE 8080

ENTRYPOINT ["/app/docker/entrypoint.sh"]
