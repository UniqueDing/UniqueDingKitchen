#!/bin/sh
set -eu

SITE_NAME_VALUE=${SITE_NAME:-"UniqueDing's Kitchen"}
CRON_SCHEDULE_VALUE=${RECOMMEND_CRON_SCHEDULE:-${CRON_SCHEDULE:-"0 0 * * *"}}
WEB_PORT_VALUE=${WEB_PORT:-8080}
TZ_VALUE=${TZ:-Asia/Shanghai}
BASE_HREF_VALUE=${WEB_BASE_HREF:-${BASE_HREF:-"/"}}
MENU_SOURCE_VALUE=${MENU_SOURCE:-"local"}
TRILLIUM_URL_VALUE=${TRILLIUM_URL:-""}
TRILLIUM_TITLE_VALUE=${TRILLIUM_TITLE:-"cooklist"}

case "${BASE_HREF_VALUE}" in
  /*) ;;
  *) BASE_HREF_VALUE="/${BASE_HREF_VALUE}" ;;
esac
case "${BASE_HREF_VALUE}" in
  */) ;;
  *) BASE_HREF_VALUE="${BASE_HREF_VALUE}/" ;;
esac

PUBLIC_DIR_VALUE=${PUBLIC_DIR:-""}
if [ -z "${PUBLIC_DIR_VALUE}" ]; then
  if [ -d /app/public ] && [ "$(ls -A /app/public 2>/dev/null)" ]; then
    PUBLIC_DIR_VALUE=/app/public
  else
    PUBLIC_DIR_VALUE=/app/site/public
  fi
fi

MENU_FILE_VALUE=${MENU_FILE:-"${PUBLIC_DIR_VALUE}/menu.md"}
RECOMMEND_FILE_VALUE=${RECOMMEND_FILE:-"${PUBLIC_DIR_VALUE}/recommend.md"}

SCRIPT_PUBLIC_DIR_VALUE="${PUBLIC_DIR_VALUE}"
case "${SCRIPT_PUBLIC_DIR_VALUE}" in
  /app/*) SCRIPT_PUBLIC_DIR_VALUE=".${SCRIPT_PUBLIC_DIR_VALUE#/app}" ;;
esac

link_public_dir() {
  mkdir -p "${PUBLIC_DIR_VALUE}"

  if [ "${PUBLIC_DIR_VALUE}" != "/app/site/public" ]; then
    rm -rf /app/site/public
    ln -s "${PUBLIC_DIR_VALUE}" /app/site/public
  fi
}

write_runtime_config_and_patch_index() {
  SITE_NAME="${SITE_NAME_VALUE}" \
  PUBLIC_DIR_VALUE="${PUBLIC_DIR_VALUE}" \
  MENU_SOURCE_VALUE="${MENU_SOURCE_VALUE}" \
  TRILLIUM_URL_VALUE="${TRILLIUM_URL_VALUE}" \
  TRILLIUM_TITLE_VALUE="${TRILLIUM_TITLE_VALUE}" \
  BASE_HREF_VALUE="${BASE_HREF_VALUE}" \
  python - <<'PY'
import json
import os
import re
from pathlib import Path

public_dir = Path(os.environ.get('PUBLIC_DIR_VALUE', '/app/site/public'))
public_dir.mkdir(parents=True, exist_ok=True)
Path(public_dir / 'runtime_config.json').write_text(
    json.dumps(
        {
            'site_name': os.environ['SITE_NAME'],
            'MENU_SOURCE': os.environ.get('MENU_SOURCE_VALUE', 'local'),
            'TRILLIUM_URL': os.environ.get('TRILLIUM_URL_VALUE', ''),
            'TRILLIUM_TITLE': os.environ.get('TRILLIUM_TITLE_VALUE', 'cooklist'),
        },
        ensure_ascii=False,
    ),
    encoding='utf-8',
)

index_path = Path('/app/site/index.html')
if index_path.exists():
    source = index_path.read_text(encoding='utf-8')
    base_href = os.environ.get('BASE_HREF_VALUE', '/').strip() or '/'
    icon_href = f'{base_href}favicon.svg'
    manifest_href = f'{base_href}manifest.json'
    apple_icon_href = f'{base_href}icons/Icon-192.png'
    has_apple_icon = Path('/app/site/icons/Icon-192.png').exists()
    source = re.sub(
        r'<base href="[^"]*">',
        f'<base href="{base_href}">',
        source,
        count=1,
    )
    source = source.replace(
        '<title>unique_ding_kitchen</title>',
        f'<title>{os.environ["SITE_NAME"]}</title>',
    )
    source = source.replace(
        '<meta name="apple-mobile-web-app-title" content="unique_ding_kitchen">',
        f'<meta name="apple-mobile-web-app-title" content="{os.environ["SITE_NAME"]}">',
    )
    if has_apple_icon:
        source = re.sub(
            r'<link rel="apple-touch-icon" href="[^"]*">',
            f'<link rel="apple-touch-icon" href="{apple_icon_href}">',
            source,
            count=1,
        )
    else:
        source = re.sub(
            r'\s*<link rel="apple-touch-icon" href="[^"]*">\s*',
            '\n',
            source,
            count=1,
        )
    source = re.sub(
        r'<link rel="icon"[^>]*href="[^"]*"[^>]*/?>',
        f'<link rel="icon" type="image/svg+xml" href="{icon_href}"/>',
        source,
        count=1,
    )
    source = re.sub(
        r'<link rel="manifest" href="[^"]*">',
        f'<link rel="manifest" href="{manifest_href}">',
        source,
        count=1,
    )
    index_path.write_text(source, encoding='utf-8')
PY
}

ensure_menu_seed() {
  if [ -f "${MENU_FILE_VALUE}" ]; then
    return
  fi

  cp /app/defaults/menu.md "${MENU_FILE_VALUE}"
}

write_recommend_cron() {
  cat >/tmp/recommend.cron <<EOF
CRON_TZ=${TZ_VALUE}
${CRON_SCHEDULE_VALUE} PUBLIC_DIR="${SCRIPT_PUBLIC_DIR_VALUE}" MENU_SOURCE="${MENU_SOURCE_VALUE}" TRILLIUM_URL="${TRILLIUM_URL_VALUE}" TRILLIUM_TITLE="${TRILLIUM_TITLE_VALUE}" /usr/local/bin/python /app/scripts/generate_recommendation.py >> /proc/1/fd/1 2>> /proc/1/fd/2
EOF
}

run_recommend_on_start() {
  if [ "${RUN_RECOMMEND_ON_START:-true}" != "true" ]; then
    return
  fi

  PUBLIC_DIR="${SCRIPT_PUBLIC_DIR_VALUE}" MENU_SOURCE="${MENU_SOURCE_VALUE}" TRILLIUM_URL="${TRILLIUM_URL_VALUE}" TRILLIUM_TITLE="${TRILLIUM_TITLE_VALUE}" /usr/local/bin/python /app/scripts/generate_recommendation.py || true
}

log_startup_state() {
  echo "[startup] PUBLIC_DIR=${PUBLIC_DIR_VALUE}"
  echo "[startup] SCRIPT_PUBLIC_DIR=${SCRIPT_PUBLIC_DIR_VALUE}"
  echo "[startup] MENU_FILE=${MENU_FILE_VALUE}"
  echo "[startup] RECOMMEND_FILE=${RECOMMEND_FILE_VALUE}"
  echo "[startup] WEB_BASE_HREF=${BASE_HREF_VALUE}"
  echo "[startup] MENU_SOURCE=${MENU_SOURCE_VALUE}"
  echo "[startup] TRILLIUM_URL=${TRILLIUM_URL_VALUE}"
  echo "[startup] TRILLIUM_TITLE=${TRILLIUM_TITLE_VALUE}"
  if [ -f "${MENU_FILE_VALUE}" ]; then
    echo "[startup] menu.md sha256=$(sha256sum "${MENU_FILE_VALUE}" | awk '{print $1}')"
    echo "[startup] menu.md first-line=$(head -n 1 "${MENU_FILE_VALUE}")"
  fi
  if [ -f "${RECOMMEND_FILE_VALUE}" ]; then
    echo "[startup] recommend.md sha256=$(sha256sum "${RECOMMEND_FILE_VALUE}" | awk '{print $1}')"
    echo "[startup] recommend.md first-line=$(head -n 1 "${RECOMMEND_FILE_VALUE}")"
  fi
}

write_nginx_config() {
  mkdir -p /var/cache/nginx /var/log/nginx /etc/nginx/conf.d
  cat >/etc/nginx/conf.d/default.conf <<EOF
server {
  listen ${WEB_PORT_VALUE};
  listen [::]:${WEB_PORT_VALUE};
  server_name _;
  root /app/site;
  index index.html;

  gzip on;
  gzip_min_length 1024;
  gzip_vary on;
  gzip_proxied any;
  gzip_types application/javascript application/json application/wasm image/svg+xml text/css text/javascript text/plain;

  location = /index.html {
    add_header Cache-Control "no-cache" always;
  }

  location ~* \.mjs$ {
    default_type application/javascript;
    add_header Cache-Control "public, max-age=31536000, immutable" always;
    try_files \$uri =404;
  }

  location ~* \.wasm$ {
    default_type application/wasm;
    add_header Cache-Control "public, max-age=31536000, immutable" always;
    try_files \$uri =404;
  }

  location ~* \.js$ {
    add_header Cache-Control "public, max-age=31536000, immutable" always;
    try_files \$uri =404;
  }

  location ~* \.(?:css|json|svg|txt|map|otf)$ {
    add_header Cache-Control "public, max-age=3600" always;
    try_files \$uri =404;
  }

  location / {
    try_files \$uri \$uri/ /index.html;
  }
}
EOF
}

start_services() {
  /usr/local/bin/supercronic /tmp/recommend.cron &
  exec nginx -g 'daemon off;'
}

link_public_dir
write_runtime_config_and_patch_index
ensure_menu_seed
write_recommend_cron
run_recommend_on_start
log_startup_state
write_nginx_config
start_services
