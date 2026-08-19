# isp-route-fix

A small CLI tool that tests a domain’s resolved IPs, finds a working HTTPS route, and temporarily pins it in `/etc/hosts`.

It helps when your ISP can reach one CDN edge IP but fails on another.

## Why this exists

Some sites resolve to multiple IP addresses. For example, a service behind Cloudflare can return two or more edge IPs.

Sometimes, your ISP may have a bad route to one of those IPs. The result can look like this:

```text
IP A -> TCP connects, but TLS times out
IP B -> TLS succeeds, HTTP 200
```

`isp-route-fix` tests the IPs for a domain and finds one that works. It can then add a temporary `/etc/hosts` entry so your machine uses the working IP.

## When to use it

Use this when:

* a website does not open on one ISP;
* the same website works on another ISP or VPN;
* DNS resolves correctly;
* one IP for the domain works, but another IP fails.

Do not use this when:

* all resolved IPs fail;
* the domain has no IPv4 records;
* the website blocks your account or session;
* you need a permanent fix.

This is a temporary workaround. The real fix should come from the ISP or network provider.

## Installation

Clone the repo:

```bash
git clone https://github.com/<your-username>/isp-route-fix.git
cd isp-route-fix
```

Make the script executable:

```bash
chmod +x isp-route-fix.sh
```

## Usage

Run a dry test first:

```bash
./isp-route-fix.sh dashboard.doppler.com /login
```

If the tool finds a working IP, apply the fix:

```bash
./isp-route-fix.sh dashboard.doppler.com /login --apply
```

For a normal website root path:

```bash
./isp-route-fix.sh example.com /
```

## What it does

The script:

1. resolves the domain’s IPv4 records;
2. tests HTTPS against each IP directly;
3. finds an IP that completes HTTPS successfully;
4. prints the recommended `/etc/hosts` entry;
5. optionally writes the entry to `/etc/hosts`;
6. creates a backup before changing `/etc/hosts`;
7. flushes the local DNS cache where possible.

## Example

```bash
./isp-route-fix.sh dashboard.doppler.com /login
```

Example output:

```text
Resolving dashboard.doppler.com...

Testing HTTPS reachability...

===== 172.66.43.202 =====
curl: (28) SSL connection timeout
FAILED: 172.66.43.202 did not complete HTTPS

===== 172.66.40.54 =====
http=200 connect=0.038s tls=0.084s
OK: 172.66.40.54 works for dashboard.doppler.com

Selected IP: 172.66.40.54
Hosts entry:
172.66.40.54 dashboard.doppler.com # isp-route-fix:dashboard.doppler.com
```

## Apply the fix

```bash
./isp-route-fix.sh dashboard.doppler.com /login --apply
```

This adds a managed line to `/etc/hosts`:

```text
172.66.40.54 dashboard.doppler.com # isp-route-fix:dashboard.doppler.com
```

## Remove the fix

Open `/etc/hosts`:

```bash
sudo nano /etc/hosts
```

Delete the line that contains:

```text
# isp-route-fix:domain.com
```

Then flush DNS.

On macOS:

```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

On Linux:

```bash
sudo resolvectl flush-caches
```

## Requirements

* Bash
* `curl`
* `dig`
* `sudo` access to update `/etc/hosts`

On Ubuntu/Debian, install `dig` with:

```bash
sudo apt install dnsutils
```

On Fedora:

```bash
sudo dnf install bind-utils
```

On macOS, `dig` and `curl` are usually available by default.

## Important warning

This tool changes local name resolution.

That means your computer will ignore DNS for the pinned domain and use the selected IP instead.

This can break later because CDN IPs can change. Remove the `/etc/hosts` entry after your ISP fixes the routing issue.

## License

MIT
