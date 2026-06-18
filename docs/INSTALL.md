# Installation Guide — pfSense-pkg-SipRegistrar v2.4.0

This guide covers the **offline installation** of the SIP registrar
(**Kamailio 6.1.1** + **rtpproxy**) on pfSense 2.7.2 — no Internet access required
on the pfSense box, and **without upgrading or breaking the base system**.

> **Requirements**:
> - pfSense **2.7.2-RELEASE**, **amd64** architecture (FreeBSD 14)
> - SSH/console access to pfSense (root / the `admin` account)
> - A way to copy a folder to pfSense (WinSCP/SFTP/USB)
> - Internet on pfSense is **NOT** required (everything is in the bundle)

> Russian version: [INSTALL.ru.md](INSTALL.ru.md)

---

## 1. Install the package — offline via `install.sh` (recommended)

The bundle (the `offline/` folder, ≈13 MB) contains the package and all
dependencies:

```
offline/
├── install.sh          # installer
└── packages/
    ├── pfSense-pkg-SipRegistrar-2.4.0.pkg   # the package
    ├── kamailio-6.1.1.pkg                   # minimal build (no icu/libxml2)
    ├── rtpproxy-2.1.1_1.pkg                 # media proxy (RTP)
    └── gsm-1.0.23.pkg                       # codec (rtpproxy dependency)
```

> The minimal `kamailio` is built to link against **base FreeBSD libraries only**
> and does NOT pull `icu`/`libxml2`/`mysql`. So the install changes nothing in the
> pfSense base and removes nothing from it.

### Step 1. Copy the `offline/` folder to pfSense

From Windows (PowerShell, via SCP):
```powershell
scp -r "C:\path\to\pfSense-pkg-SipRegistrar\offline" admin@LAN_IP:/root/offline
```
Or upload the whole `offline` folder into `/root/` with WinSCP/FileZilla.

You should end up with `/root/offline/install.sh` and `/root/offline/packages/*.pkg`.

### Step 2. Connect over SSH and run

Host: pfSense IP, Port: 22. In the pfSense menu pick **8) Shell** (or
Diagnostics → Command Prompt), then:

```sh
cd /root/offline
sh install.sh
```

The script automatically:
1. leaves system ASLR **enabled** (the minimal kamailio build has no KEMI and runs
   fine with ASLR) and removes any legacy global ASLR disable left by old versions;
2. builds a local repository **named `pfSense`** — important, otherwise the package
   is not visible in Package Manager (see "Notes" below);
3. installs the 4 packages **from the local catalog only** (no network, no base
   upgrade);
4. generates a working `kamailio.cfg` and **starts** `kamailio` + `rtpproxy` right away.

Success looks like:
```
[4/4] Installing pfSense-pkg-SipRegistrar-2.4.0...
apply ok
  SIP Registrar installed successfully.
```

> ⚠ Back up your pfSense config first (*Diagnostics → Backup & Restore → Download
> configuration*).

The post-install also: creates the `kamailio` user/group, sets `dbtext/`
permissions, enables autostart, initialises the `<sipregistrar>` section in
`config.xml`, and registers the package in Package Manager and the Services menu.

---

## 1a. After install: verification and GUI access

**Verify over SSH:**
```sh
pkg info pfSense-pkg-SipRegistrar | head -3      # package installed
pkg query '%R' pfSense-pkg-SipRegistrar          # must print: pfSense (quote '%R' for tcsh)
ps ax | grep -E '[k]amailio|[r]tpproxy'          # services running
/usr/local/sbin/kamailio -f /usr/local/etc/kamailio/kamailio.cfg -c; echo "exit=$?"  # exit=0
```

**In the web UI** (refresh — **Ctrl+F5**, re-login if needed):
- **System → Package Manager → Installed Packages** — shows `SIP Registrar 2.4.0`.
- **Services → SIP Registrar** — the configuration page.
- **Dashboard widget:** on the Dashboard click **"+"** (Available Widgets) and add
  **SIP Registrar**. *(Widgets are added manually in pfSense.)*

### Notes
- **Repository name `pfSense`.** The "Installed Packages" page only lists packages
  whose `pkg query %R` equals `pfSense`. The installer deliberately creates a local
  repository with that name (via `-o REPOS_DIR`). The Netgate repository is not used,
  so there is no conflict and `pkg upgrade` leaves this package alone.
- **The pfSense base is unchanged.** `pfSense`, `php82`, `kea` stay in place — only
  `kamailio`, `rtpproxy`, `gsm` and the package itself are added.
- **ASLR is NOT disabled** — system protection stays intact. The minimal kamailio
  build (no KEMI) runs with ASLR enabled; if an older version disabled it globally
  (`kern.elf64.aslr.*`), the installer cleans that up.
- **Logs.** Kamailio writes to **`/var/log/SipRegistrar.log`** (directly, bypassing
  pfSense syslog — its default `local0.none` drops the logs). Rotation is handled by
  `newsyslog` (daily / 5 MB / keep 14 / gzip), rule in
  `/var/etc/newsyslog.conf.d/SipRegistrar.log.conf`. Verbosity: *Services → SIP
  Registrar → Settings → Log Level* (0–3; use 1 in production, 3 for debugging).

---

## 2. Open the SIP port in the firewall

The package does NOT modify firewall rules automatically. You must add
a rule to allow SIP traffic from the LAN.

1. Navigate to *Firewall → Rules → LAN → Add* (top arrow icon).
2. Configure the rule:
   - **Action**: Pass
   - **Interface**: LAN
   - **Protocol**: UDP
   - **Source**: LAN net
   - **Destination**: This Firewall (or LAN address)
   - **Destination Port Range**: SIP port from your Settings
     (default 5060)
   - **Description**: `Allow SIP to Kamailio Registrar`
3. Save and apply changes.

> **Do not open SIP from WAN.** This package has no protection against
> brute-force or DDoS attacks from the Internet.

---

## 3. Configure the registrar

Open *Services → SIP Registrar*.

### Settings tab

| Field      | Default              | Notes                                              |
|------------|----------------------|----------------------------------------------------|
| SIP Port   | 5060                 | UDP port (1024..65535)                             |
| SIP Realm  | auto LAN IP          | SIP authentication realm                           |
| Log Level  | 1 (Warnings)         | 0..3, only use 3 for troubleshooting               |
| Language   | English              | Interface language (also stored in your browser)   |

> **Warning**: changing SIP Realm invalidates all existing HA1 hashes.
> You will need to re-enter every device password after changing it.

### Gateways tab

Add each external SIP gateway as a row:

| Field          | Notes                                                |
|----------------|------------------------------------------------------|
| Gateway IP     | IPv4 address of the gateway                          |
| Port           | SIP port on the gateway (default 5060)               |
| Prefix         | Leading digits that match dialed numbers, or empty   |
| Description    | Free-form text (e.g. "Yeastar TA800 PSTN")           |
| Priority       | 1 (highest) .. 3 (lowest)                            |

Routing logic:
- For each new INVITE the SIP ID is first looked up in the alias
  table. If a phone is registered, the call goes peer-to-peer.
- If not registered, the gateways with a matching prefix are tried
  in priority order; longer prefixes match first.
- The gateway with an **empty prefix** is the default route, used
  when nothing else matches.

### Devices tab

Add each phone or softphone:

| Field         | Notes                                                |
|---------------|------------------------------------------------------|
| Number        | Extension (2..5 digits, e.g. 101)                    |
| IP Address    | Optional — informational only                        |
| SIP ID        | Registration username (letters/digits/`_.-`, 1..64)  |
| SIP Password  | Required for new devices                             |
| Type          | Auto-detected: Phone (IP) or Gateway (SIP)           |
| Description   | Free-form text (e.g. "alice (sales department)")     |

After adding/editing all entries, click **Save**. Kamailio
reloads the configuration without dropping active calls.

### Trunks tab

Add external SIP provider lines. Kamailio registers as a UAC client.

| Field       | Notes                                                    |
|-------------|----------------------------------------------------------|
| Phone / DID | Provider phone number (e.g. +7XXXXXXXXXX)                |
| SIP Domain  | Provider's SIP domain (e.g. sip.provider.ru)             |
| Proxy IP    | Provider's SIP proxy IP address                          |
| Port        | SIP proxy port (default 5060)                            |
| Username    | Registration username                                    |
| Password    | Registration password                                    |
| On          | Enable/disable this trunk                                |
| Description | Free-form text (e.g. "Main Line")                        |

Advanced settings (click a trunk row → Advanced panel): Expires, Interval, Keep-Alive timers.

Status badges update automatically every 5 seconds: Registered (green), Offline (grey), Failed (red).

### Incoming tab

Configure how calls from external trunks/gateways are routed to internal extensions.
Each DID can have separate day and night extensions, with configurable work hours and days.

### Outbound tab

Configure which internal extensions are allowed to make outbound calls via each trunk or gateway.
Extensions not listed receive 403 Forbidden.

---

## 4. Configure SIP phones

The exact menu names vary by vendor, but the parameters are the same:

| Parameter        | Value                                                   |
|------------------|---------------------------------------------------------|
| SIP Server       | LAN IP of pfSense                                       |
| SIP Port         | As set in Settings (default 5060)                       |
| Authentication / Username  | SIP ID from Devices table                     |
| Authentication / Password  | SIP Password from Devices table               |
| Display name     | Any text                                                |
| Transport        | UDP                                                     |
| Registration period (Re-REGISTER) | 60..3600 seconds (default OK)          |

### Example: Grandstream GRP2601P

1. Web GUI → *Accounts → Account 1 → General Settings*
2. Account Name = `alice`
3. SIP Server = `lan_ip` (LAN IP of pfSense)
4. SIP User ID = `alice` (SIP ID from Devices)
5. Authenticate ID = `alice`
6. Authenticate Password = the password you typed in pfSense
7. Save and apply

### Example: Zoiper

1. Settings → Accounts → Add Account → SIP
2. Domain = `lan_ip`
3. Username = `alice`
4. Password = the password from pfSense

---

## 5. Configure SIP gateways

External gateways (Yeastar TA800, Grandstream GXW, Asterisk etc.) can
register on the pfSense registrar like any other SIP device. Or you
can leave them unregistered if they are reachable by static IP — in
that case pfSense reaches them by the IP configured on the Gateways
tab.

If your gateway should be registered:
- Create a Device entry with a SIP ID containing one of the keywords
  `gw`, `gateway`, `trunk`, `pstn`, `ta800`, `yeastar`, etc. — the type
  is auto-detected as Gateway (SIP).
- Configure the gateway with `SIP Server = LAN IP of pfSense`,
  `Username = SIP ID`, `Password = SIP Password`.

---

## 6. Verify operation

```sh
# Active registrations
kamcmd ul.dump

# Number-to-SIP-ID aliases
kamcmd alias.dump

# Transaction statistics
kamcmd tm.stats

# Kamailio version
kamcmd core.version

# Service status
service kamailio status

# Listening sockets
sockstat -4 -l | grep 5060
```

The Status tab in the web UI shows the same information graphically.

---

## 7. Updating

The **Update** button in Package Manager does not work for this package (it is not
in the Netgate repository). To update, re-run the installer with a newer bundle:
```sh
cd /root/offline        # folder with the new .pkg files
sh install.sh
```
The `<sipregistrar>` settings in `config.xml` are **preserved**.

---

## 8. Uninstalling

Via the GUI: *System → Package Manager → Installed Packages → Remove* next to
`pfSense-pkg-SipRegistrar`.

Via SSH:
```sh
# Package only (dependencies stay)
pkg delete -y pfSense-pkg-SipRegistrar

# Fully, together with kamailio/rtpproxy/gsm
pkg delete -y pfSense-pkg-SipRegistrar kamailio rtpproxy gsm
pkg autoremove -y
```

On removal: the Kamailio and rtpproxy services are stopped, autostart is removed,
cron/log-rotation entries are cleaned. Verified: the pfSense base (`php82`, `kea`,
the `pfSense` metapackage) stays **intact**.

---

## 9. Monitoring & debugging

### Monitoring (over SSH)
```sh
kamcmd ul.dump                 # active registrations (phones/trunks)
kamcmd tm.stats                # transaction stats (incl. active)
kamcmd dlg.list                # active dialogs (calls); count: dlg.stats_active
kamcmd core.uptime             # engine uptime/version
sockstat -4 -l | grep 5060     # listening SIP sockets
top -b 10 | grep -i kamailio   # kamailio process load (or interactive: top)
```

### Logs
- File: **`/var/log/SipRegistrar.log`** (newsyslog rotation — see §1a).
- Level: *Services → SIP Registrar → Settings → Log Level* (1 = production, 3 = debug).

### Capturing SIP traffic (tcpdump)
On FreeBSD/pfSense: use a **specific interface** (the `any` pseudo-iface does NOT
work), pass **`-U`** (unbuffered — small captures otherwise "don't write"), and
filter **by port, not host** (filtering by host loses RTP from other addresses):
```sh
ifconfig | grep -E "^[a-z]|inet "                 # find interface names (LAN/WAN)
# signaling + media on LAN (e.g. re0):
tcpdump -n -s0 -U -i re0 -w /tmp/sip.pcap port 5060 or portrange 10000-40000
# trunk exchange on WAN (e.g. bge0):
tcpdump -n -s0 -U -i bge0 -w /tmp/trunk.pcap host <provider-ip>
```
Easier via GUI: *Diagnostics → Packet Capture*. Open the `.pcap` in Wireshark.

### Security/compatibility FAQ
- **ASLR** is not disabled (see §1a) — the system stays protected.
- **MAC/SELinux**: SELinux does not exist on FreeBSD; the MAC framework
  (`mac_bsdextended`) is **off by default** in pfSense 2.7.2 — it does not block Kamailio.
- **Package integrity**: `install.sh` verifies `packages/SHA256SUMS` before installing.

See `TROUBLESHOOTING.md` if something goes wrong.
