# Cloudflare Poor man DDNS

## Usage:
- Clone this repository
- `cp env.example.sh env.sh`
- Fill in `env.sh`
- Add Cronjob entry

```cron
*/5 * * * * root /bin/bash /etc/ddns/ipv4.sh
```

