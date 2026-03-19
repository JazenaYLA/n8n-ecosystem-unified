# Caddy Routes for Unified Stack

Add these blocks in **CaddyManager** (or directly in `/etc/caddy/Caddyfile`
on the Caddy LXC). Caddy runs in its own dedicated LXC — not inside Docker.

**Last updated:** 2026-03-19

---

## Router DNS Records (UniFi Local DNS)

Only **one A record** points to an actual IP. All services use CNAMEs:

```
# A record — only this needs updating if Caddy's IP changes
caddy.lab.local        A       <CADDY_LXC_IP>

# Existing CTI service CNAMEs (from threatlabs-cti-stack)
misp.lab.local         CNAME   caddy.lab.local
opencti.lab.local      CNAME   caddy.lab.local
thehive.lab.local      CNAME   caddy.lab.local
cortex.lab.local       CNAME   caddy.lab.local
dfir-iris.lab.local    CNAME   caddy.lab.local
flowintel.lab.local    CNAME   caddy.lab.local
forgejo.lab.local      CNAME   caddy.lab.local
kuma.lab.local         CNAME   caddy.lab.local

# New CNAMEs for unified stack
n8n.lab.local          CNAME   caddy.lab.local
flowise.lab.local      CNAME   caddy.lab.local
searxng.lab.local      CNAME   caddy.lab.local
postgrest.lab.local    CNAME   caddy.lab.local
pgadmin.lab.local      CNAME   caddy.lab.local
```

---

## Caddyfile Blocks

Add these to your Caddyfile on the Caddy LXC.

### n8n (n8n LXC — external, reverse proxy by IP)

```caddy
n8n.lab.local {
    reverse_proxy <N8N_LXC_IP>:5678
    encode gzip
    header {
        Strict-Transport-Security "max-age=31536000"
        X-Content-Type-Options nosniff
    }
}
```

### Flowise (Flowise LXC — native install, port 3000)

```caddy
flowise.lab.local {
    reverse_proxy <FLOWISE_LXC_IP>:3000
    encode gzip
}
```

### SearXNG (SearXNG LXC — Docker port mapped)

```caddy
searxng.lab.local {
    reverse_proxy <SEARXNG_LXC_IP>:8888
}
```

### PostgREST (CTI LXC — Docker container on cti-net)

> Note: Caddy must be on the same network as the CTI LXC, or use the
> CTI LXC IP directly. If Caddy is in its own LXC, use the IP:

```caddy
postgrest.lab.local {
    reverse_proxy <CTI_LXC_IP>:3000
}
```

### pgAdmin (CTI LXC — Docker port 5050 mapped to LXC host)

```caddy
pgadmin.lab.local {
    reverse_proxy <CTI_LXC_IP>:5050
}
```

---

## Notes

- Caddy handles TLS automatically for any domain with a valid public cert
  (Let's Encrypt). For `*.lab.local` internal domains, Caddy serves plain
  HTTP unless you configure a self-signed CA.
- For internal-only `lab.local` domains, configure your browser/devices
  to trust your Proxmox internal CA, or use `tls internal` in Caddy.
- See [threatlabs-cti-stack Reverse Proxy Guide](https://github.com/JazenaYLA/threatlabs-cti-stack/blob/enterprise/docs/Reverse-Proxy-Guide.md)
  for the full Caddy + DNS architecture.
