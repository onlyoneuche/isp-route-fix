#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${1:-}"
PATH_TO_TEST="${2:-/}"
APPLY="${3:-}"

if [ -z "$DOMAIN" ]; then
  echo "Usage:"
  echo "  $0 <domain> [path] [--apply]"
  echo
  echo "Example:"
  echo "  $0 dashboard.doppler.com /login --apply"
  exit 1
fi

# Remove scheme and path if user passes a full URL.
DOMAIN="$(echo "$DOMAIN" | sed -E 's#^https?://##' | cut -d/ -f1)"

if ! command -v dig >/dev/null 2>&1; then
  echo "Error: dig is required."
  echo "Install bind-utils/dnsutils, or use a system with dig available."
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl is required."
  exit 1
fi

echo "Resolving $DOMAIN..."
IPS="$(dig +short A "$DOMAIN" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u || true)"

if [ -z "$IPS" ]; then
  echo "No IPv4 A records found for $DOMAIN"
  exit 1
fi

echo
echo "Testing HTTPS reachability..."
echo

WORKING_IP=""

for IP in $IPS; do
  echo "===== $IP ====="

  RESULT="$(
    curl -sS -o /dev/null \
      --connect-timeout 10 \
      --max-time 20 \
      --resolve "$DOMAIN:443:$IP" \
      -w "http=%{http_code} connect=%{time_connect}s tls=%{time_appconnect}s" \
      "https://$DOMAIN$PATH_TO_TEST" 2>&1
  )" && STATUS=0 || STATUS=$?

  echo "$RESULT"

  if [ "$STATUS" -eq 0 ]; then
    WORKING_IP="$IP"
    echo "OK: $IP works for $DOMAIN"
    break
  else
    echo "FAILED: $IP did not complete HTTPS"
  fi

  echo
done

if [ -z "$WORKING_IP" ]; then
  echo
  echo "No working IP found."
  echo "Do not update /etc/hosts for this domain."
  echo "This may be a full ISP block, DNS issue, MTU issue, or service-side block."
  exit 2
fi

echo
echo "Selected IP: $WORKING_IP"
echo "Hosts entry:"
echo "$WORKING_IP $DOMAIN # isp-route-fix:$DOMAIN"

if [ "$APPLY" != "--apply" ]; then
  echo
  echo "Dry run only. To apply:"
  echo "  $0 $DOMAIN $PATH_TO_TEST --apply"
  exit 0
fi

echo
echo "Updating /etc/hosts..."

BACKUP="/etc/hosts.backup.$(date +%Y%m%d%H%M%S)"
TMP_FILE="$(mktemp)"

sudo cp /etc/hosts "$BACKUP"

# Remove old entry managed by this script for the same domain.
grep -v "# isp-route-fix:$DOMAIN" /etc/hosts > "$TMP_FILE" || true

# Add new pinned IP.
echo "$WORKING_IP $DOMAIN # isp-route-fix:$DOMAIN" >> "$TMP_FILE"

sudo cp "$TMP_FILE" /etc/hosts
rm -f "$TMP_FILE"

echo "Backup saved to: $BACKUP"

echo
echo "Flushing DNS cache..."

if command -v dscacheutil >/dev/null 2>&1; then
  sudo dscacheutil -flushcache || true
  sudo killall -HUP mDNSResponder || true
elif command -v resolvectl >/dev/null 2>&1; then
  sudo resolvectl flush-caches || true
elif command -v systemd-resolve >/dev/null 2>&1; then
  sudo systemd-resolve --flush-caches || true
else
  echo "Could not auto-flush DNS cache. Restart your browser or network service."
fi

echo
echo "Done."
echo "Test with:"
echo "  curl -Iv https://$DOMAIN$PATH_TO_TEST"