# pfSense-pkg-SipRegistrar

Universal SIP registrar based on Kamailio 6.1.1 for pfSense 2.7.2

Turns pfSense into a lightweight, vendor-independent SIP registrar
suitable for small offices, workshops, warehouses, and home deployments.
Any RFC 3261-compatible SIP IP phones, softphones, and gateways can
register with it and place calls using short extensions (2–5 digits),
with optional routing to external SIP gateways based on number prefixes.

---

## Compatibility

### IP Phones and Softphones (any RFC 3261 SIP UA)
- Grandstream GRP / GXP series
- Yealink T2x, T4x, T5x series
- Cisco CP-78xx, CP-88xx series
- Fanvil X, H series
- Snom 3xx, 7xx series
- Softphones: Zoiper, MicroSIP, Linphone, Bria, etc.

### SIP Gateways (any SIP-compatible device)
- Yeastar TA series (FXO/FXS gateways)
- Grandstream GXW series
- Cisco VG series
- Audiocodes Mediant series
- Asterisk / FreePBX / 3CX
- Any other SIP gateway or IP PBX

---

## Network Diagram (Typical Deployment)

```text

  Analog phones (any quantity)
        │
        └── SIP gateway (Yeastar TA800 / Grandstream GXW / Cisco VG)
                │   IP: configured in package settings
                │
                └── Local network (any subnet)
                        │
                        ├── IP phones / softphones
                        │   Extensions: 2–5 digits (10..99999)
                        │   SIP ID: any text (alice, 101, director, ...)
                        │
                        ├── Additional SIP gateways (optional)
                        │   Routing by number prefix
                        │
                        └── pfSense (Kamailio SIP registrar)
                            LAN IP = SIP realm (detected automatically)
                            SIP port: configurable (default 5060/UDP)

```

---

## Requirements

| Component        | Version                              |
|------------------|--------------------------------------|
| pfSense          | 2.7.2-RELEASE (amd64)                |
| FreeBSD          | 14.0-RELEASE (base system)           |
| Kamailio         | 6.1.1 (FreeBSD quarterly repository) |
| PHP              | 8.2.x                                |

> **Important**: Kamailio is not available in the pfSense repository.
> The installer downloads it from the standard FreeBSD quarterly repository
> using a workaround mechanism (`pfSense-Extra.conf`).
> This process updates pfSense system packages
> (php82, perl5, kea, rrdtool, libxml2, and others). For risk details,
> see `SECURITY.ru.md`; installation instructions are available in
> `INSTALL.ru.md`.

> **ASLR must be disabled** on the pfSense host before running Kamailio 6.x.
> The installer (`install.sh`) does this automatically.

---

## Numbering Scheme

- **Number (Extension)**: 2–5 digits, no leading zero, range 10..99999.
  Examples: `42`, `101`, `8500`, `10001`. Used for dialing.
- **SIP ID**: any text containing Latin letters, digits, underscores,
  periods, and hyphens (length 1..64). Examples: `alice`, `101`,
  `director`, `gw_ta800`. Used as the SIP registration username on phones.
- The HA1 password hash is calculated as
  `md5(SIP ID + Realm + Password)` and stored in pfSense `config.xml`.
  The plain-text password is never stored.

The **Number → SIP ID** mapping is stored in the Kamailio `dbaliases`
table. When someone dials a Number, Kamailio looks up the alias and
forwards the INVITE to the current registration associated with that SIP ID.

---

## Quick Start

1. **Install the package** via *System → Package Manager → Available
   Packages → Search "SipRegistrar"* and click *Install*.

2. **Open the firewall port**:
   *Firewall → Rules → LAN → Add* → UDP, destination port 5060
   (or your chosen port), source `LAN net`.

3. **Configure the registrar**:
   *Services → SIP Registrar*.
   - **Settings tab**: verify SIP Port and SIP Realm (the LAN IP
     is filled in automatically). Select the language (English / Russian).
   - **Gateways tab**: add on-premises FXS/FXO gateways (e.g. Yeastar TA810)
     with optional number prefixes.
   - **Trunks tab**: add external SIP provider lines (e.g. Rostelecom, Zadarma).
     Kamailio registers as a UAC client. Status badges show registration state.
   - **Devices tab**: add phones and softphones.
     Set Number, SIP ID, and SIP Password.
   - **Incoming tab**: configure DID routing from trunks/gateways to extensions
     with business hours / after hours schedule.
   - **Outbound tab**: configure which extensions can make outbound calls
     via each trunk or gateway.
   - Click **Save** — Kamailio reloads without interrupting active calls.

4. **Configure each phone**:
   - SIP Server: pfSense LAN IP
   - SIP Port: as configured in Settings (default 5060)
   - Username: SIP ID from the Devices table
   - Password: SIP Password from the Devices table

5. **Verify** in *Services → SIP Registrar → Status* —
   registered phones should appear within 30–60 seconds.

Detailed instructions are available in `INSTALL.ru.md`.

---

## Limitations

- **LAN only**: the package is designed for SIP traffic within a single
  local network. RTP is transmitted peer-to-peer between phones without
  a media proxy. With NAT or VPN, audio may work only one-way.
- **No TLS / SRTP**: signaling and media are not encrypted.
  Do not expose the SIP port to the Internet.
- **No gateway monitoring**: the Kamailio `dispatcher` module is not loaded.
  All configured gateways are assumed to be available.

See `SECURITY.ru.md` for the full security model.

---

## Author

Sergey Saidov <40user40@gmail.com>

## License

BSD 2-Clause License — see `LICENSE`.

## Repository

https://github.com/humaxoid/SipRegistrar
