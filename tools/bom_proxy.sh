#!/bin/sh
set -eu

USER_AGENT='Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15'
RAW_QUERY="${QUERY_STRING:-}"
PATH_INFO_VALUE="${RAW_QUERY%%&*}"
QUERY=""
if [ "${RAW_QUERY#*&}" != "$RAW_QUERY" ]; then
  QUERY="${RAW_QUERY#*&}"
fi

case "$PATH_INFO_VALUE" in
  /fwo/*|/radar/*) ;;
  *)
    printf 'Status: 404 Not Found\r\n'
    printf 'Content-Type: text/plain; charset=utf-8\r\n'
    printf 'Access-Control-Allow-Origin: *\r\n'
    printf '\r\n'
    printf 'unsupported path\n'
    exit 0
    ;;
esac

UPSTREAM="https://www.bom.gov.au${PATH_INFO_VALUE}"
if [ -n "$QUERY" ]; then
  UPSTREAM="${UPSTREAM}?${QUERY}"
fi

BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT HUP INT TERM

CURL_OUTPUT="$(curl -L -sS -A "$USER_AGENT" -o "$BODY_FILE" -w '%{http_code}\n%{content_type}' "$UPSTREAM" 2>&1 || true)"
HTTP_CODE="$(printf '%s\n' "$CURL_OUTPUT" | tail -n 2 | sed -n '1p')"
CONTENT_TYPE="$(printf '%s\n' "$CURL_OUTPUT" | tail -n 1)"

case "$HTTP_CODE" in
  2*|3*|4*|5*) ;;
  *)
    ERROR_TEXT="$CURL_OUTPUT"
    printf 'Status: 502 Bad Gateway\r\n'
    printf 'Content-Type: text/plain; charset=utf-8\r\n'
    printf 'Access-Control-Allow-Origin: *\r\n'
    printf '\r\n'
    printf '%s\n' "$ERROR_TEXT"
    exit 0
    ;;
esac

[ -n "$CONTENT_TYPE" ] || CONTENT_TYPE='application/octet-stream'

printf 'Status: %s\r\n' "$HTTP_CODE"
printf 'Content-Type: %s\r\n' "$CONTENT_TYPE"
printf 'Access-Control-Allow-Origin: *\r\n'
printf 'Cache-Control: no-store\r\n'
printf '\r\n'
cat "$BODY_FILE"
