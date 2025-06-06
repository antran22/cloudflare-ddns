#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
ENV_FILE="$SCRIPT_DIR/env.sh"

if [[ -f "$ENV_FILE" ]]; then
  source $ENV_FILE
else
  echo "DDNS Updater: Env file $ENV_FILE isn't found, hopefully the env variables already there"
fi

###########################################
## Check if we have a public IP
###########################################
ipv4_regex='([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])'
ip=$(curl -s -4 https://cloudflare.com/cdn-cgi/trace | grep -E '^ip')
ret=$?
if [[ ! $ret == 0 ]]; then # In the case that cloudflare failed to return an ip.
  # Attempt to get the ip from other websites.
  ip=$(curl -s https://api.ipify.org || curl -s https://ipv4.icanhazip.com)
else
  # Extract just the ip from the ip line from cloudflare.
  ip=$(echo $ip | sed -E "s/^ip=($ipv4_regex)$/\1/")
fi

# Use regex to check for proper IPv4 format.
if [[ ! $ip =~ ^$ipv4_regex$ ]]; then
  echo "DDNS Updater: Failed to find a valid IP."
  exit 2
fi

###########################################
## Check and set the proper auth header
###########################################
if [[ "${auth_method}" == "global" ]]; then
  auth_header="X-Auth-Key:"
else
  auth_header="Authorization: Bearer"
fi

###########################################
## Seek for the A record
###########################################

echo "DDNS Updater: Check Initiated"
record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=A&name=$record_name" \
  -H "X-Auth-Email: $auth_email" \
  -H "$auth_header $auth_key" \
  -H "Content-Type: application/json")

###########################################
## Check if the domain has an A record
###########################################
#
if [[ $record == *"\"count\":0"* ]]; then
  echo "DDNS Updater: Record does not exist, perhaps create one first? (${ip} for ${record_name})"
  exit 1
fi

###########################################
## Get existing IP
###########################################
old_ip=$(echo "$record" | sed -E 's/.*"content":"(([0-9]{1,3}\.){3}[0-9]{1,3})".*/\1/')
# Compare if they're the same
if [[ $ip == $old_ip ]]; then
  echo "DDNS Updater: IP ($ip) for ${record_name} has not changed."
  exit 0
fi

###########################################
## Set the record identifier from result
###########################################
echo $record
record_identifier=$(echo "$record" | sed -E 's/.*"id":"([A-Za-z0-9_]+)".*/\1/')

###########################################
## Change the IP@Cloudflare using the API
###########################################
update=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" \
  -H "X-Auth-Email: $auth_email" \
  -H "$auth_header $auth_key" \
  -H "Content-Type: application/json" \
  --data "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":${proxy}}")

###########################################
## Report the status
###########################################
case "$update" in
*"\"success\":false"*)
  echo "DDNS Updater: $ip $record_name DDNS failed for $record_identifier ($ip). DUMPING RESULTS:\n$update" | logger -s
  if [[ $shoutrrr_url != "" ]]; then
    apprise "$noti_url" -m "$sitename Failed to update $record_name's new IP Address. New address is '$ip'."
    apprise "$noti_url" -m "\`\`\`$update\`\`\`"
  fi
  exit 1
  ;;
*)
  echo "DDNS Updater: $ip $record_name DDNS updated."
  if [[ $shoutrrr_url != "" ]]; then
    shoutrrr send "$shoutrrr_url" -m "$sitename Updated: $record_name's new IP Address is '$ip'"
  fi
  exit 0
  ;;
esac
