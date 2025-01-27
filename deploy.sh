#!/usr/bin/env bash
set -euo pipefail

if ! command -v jq >/dev/null; then
  echo "Must have JQ installed"
  exit 1
fi

if [ -z "${ALLOWED_IPS+set}" ]; then
  echo "Must set ALLOWED_IPS environment variable to a comma separated list of IP addresses"
  exit 1
fi

if [ -z "${ROUTE_SERVICE_APP_NAME+set}" ]; then
  echo "Must set ROUTE_SERVICE_APP_NAME environment variable"
  exit 1
fi

if [ -z "${ROUTE_SERVICE_NAME+set}" ]; then
  echo "Must set ROUTE_SERVICE_NAME environment variable"
  exit 1
fi

if [ -z "${PROTECTED_APP_NAME+set}" ]; then
  echo "Must set PROTECTED_APP_NAME environment variable"
  exit 1
fi

IFS="," read -ra IPS <<< "$ALLOWED_IPS"

NGINX_ALLOW_STATEMENTS=""
for addr in "${IPS[@]}";
  do NGINX_ALLOW_STATEMENTS="${NGINX_ALLOW_STATEMENTS} allow $addr;"; true;
done;

APPS_DOMAIN=$(cf curl "/v3/domains" | jq -r '[.resources[] | select(.name|endswith("apps.digital"))][0].name')

cf push "${ROUTE_SERVICE_APP_NAME}" --no-start --var app-name="${ROUTE_SERVICE_APP_NAME}"
cf set-env "${ROUTE_SERVICE_APP_NAME}" ALLOWED_IPS "$(printf "%s" "${NGINX_ALLOW_STATEMENTS}")"
cf start "${ROUTE_SERVICE_APP_NAME}"

ROUTE_SERVICE_DOMAIN="$(cf curl "/v3/apps/$(cf app "${ROUTE_SERVICE_APP_NAME}" --guid)/routes" | jq -r --arg APPS_DOMAIN "${APPS_DOMAIN}" '[.resources[] | select(.url | endswith($APPS_DOMAIN))][0].url')"

if cf curl "/v3/service_instances?type=user-provided&names=${ROUTE_SERVICE_NAME}" | jq -e '.pagination.total_results == 0' > /dev/null; then
  cf create-user-provided-service \
    "${ROUTE_SERVICE_NAME}" \
    -r "https://${ROUTE_SERVICE_DOMAIN}";
else
  cf update-user-provided-service \
    "${ROUTE_SERVICE_NAME}" \
    -r "https://${ROUTE_SERVICE_DOMAIN}";
fi

PROTECTED_APP_HOSTNAME="$(cf curl "/v3/apps/$(cf app "${PROTECTED_APP_NAME}" --guid)/routes" | jq -r --arg APPS_DOMAIN "${APPS_DOMAIN}" '[.resources[] | select(.url | endswith($APPS_DOMAIN))][0].host')"

cf bind-route-service "${APPS_DOMAIN}" "${ROUTE_SERVICE_NAME}" --hostname "${PROTECTED_APP_HOSTNAME}";
