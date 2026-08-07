# pfSense-pkg-SipRegistar

Universal SIP registrar based on Kamailio 6.1.1 for pfSense 2.7.2.

Turns pfSense into a lightweight, vendor-independent SIP registrar
suitable for small offices, workshops, warehouses, and home deployments.
Any RFC 3261-compatible SIP IP phones, softphones, and gateways can
register with it and place calls using short extensions (2–5 digits),
with optional routing to external SIP gateways based on number prefixes.

---

## Features

- **SIP registrar** for any RFC 3261 phone, softphone, or gateway; short
  extensions (2–5 digits) and free-form SIP IDs.
- **Outbound routing** to external SIP gateways by number prefix.
- **SIP trunks** — register to a provider to receive and place external calls;
  incoming filtering, work-hours / DID routing, ring groups, call pickup.
- **Call History (CDR)** and a pfSense **dashboard widget**.
- **Brute-force / flood protection** and RFC 4028 session timers.
- **External call transfer (B2BUA)** — *optional, off by default:* lets a
  dispatcher blind-transfer an external trunk caller to another extension and
  drop off, even when the provider does not support `REFER`. Transfers appear in
  the call History and dashboard. Requires `python311` (bundled here); enable it
  on the Trunks tab.

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
| Kamailio         | 6.1.1 (minimal build, in this bundle) |
| PHP              | 8.2.x (pfSense base)                  |
| python311        | 3.11.6 (for optional B2BUA; in bundle)|

> **Offline install — no base changes.** Everything ships in `packages/` and is
> installed **from the local catalog only** — the installer does **not** reach the
> Internet and does **not** upgrade or remove any pfSense base package. The bundled
> `kamailio` is a minimal build linked against base FreeBSD libraries only (no
> `icu`/`libxml2`/`mysql`). See `INSTALL.md` for the step-by-step guide.

> **ASLR is left enabled.** The minimal Kamailio build has no KEMI and runs fine
> with ASLR on; `install.sh` also clears any legacy global ASLR-disable.

---

## Numbering Scheme

- **Number (Extension)**: 2–5 digits, no leading zero, range 10..99999.
  Examples: `42`, `101`, `8500`, `10001`. Used for dialing.
- **SIP ID**: any text containing Latin letters, digits, underscores,
  periods, and hyphens (length 1..64). Examples: `alice`, `101`,
  `director`, `gw_ta800`. Used as the SIP registration username on phones.
- The HA1 hash `md5(SIP ID + Realm + Password)` is what Kamailio actually
  authenticates against; it is written to the `subscriber` table (file mode
  `0600`).
- **The password itself is kept in pfSense `config.xml` in clear text.** It has
  to be: HA1 depends on the realm, so changing the SIP Realm (for example when
  the LAN address changes) requires recomputing every hash, which is impossible
  from the hash alone. The GUI never displays a stored password — it only shows
  whether one is set — and `config.xml` is readable by pfSense administrators
  only. Treat a `config.xml` backup as a secret: it carries both the extension
  passwords and the SIP trunk credentials.

The **Number → SIP ID** mapping is stored in the Kamailio `dbaliases`
table. When someone dials a Number, Kamailio looks up the alias and
forwards the INVITE to the current registration associated with that SIP ID.

---

## Quick Start

1. Download the package and copy it to your pfSense in the /tmp directory
   Connect via SSH to your pfSense and run the installation script with 
   the sh command in the /tmp/offline directory install.sh

2. **Open the firewall port**:
   *Firewall → Rules → LAN → Add* → UDP, destination port 5060
   (or your chosen port), source `LAN net`.

3. **Configure the registrar**:
   *Services → SIP Registrar*.
   - **Settings tab**: verify SIP Port and SIP Realm (the LAN IP
     is filled in automatically). Select the language (English / Russian).
   - **Gateways tab**: add on-premises FXS/FXO gateways (e.g. Yeastar TA810)
     with optional number prefixes. Analog gateways whose FXS lines register
     directly to Kamailio are also auto-detected and shown read-only (model and
     live status read from their registrations — no SNMP).
   - **Trunks tab**: add external SIP provider lines (e.g. Rostelecom, Zadarma).
     Kamailio registers as a UAC client. Status badges show registration state.
   - **Devices tab**: add phones and softphones.
     Set Number, SIP ID, and SIP Password.
   - **Incoming tab**: configure DID routing from trunks/gateways to extensions
     with business hours / after hours schedule.
   - **Outbound tab**: configure which extensions can make outbound calls
     via each trunk or gateway.
   - **Groups tab**: ring/hunt groups — parallel ring-all or sequential hunt
     with per-member timeout and a fallback extension.
   - **Status / History tabs**: live registrations and active calls; call
     history (CDR) with a number filter and click-sortable columns.
   - Click **Save** — settings/device changes apply without dropping
     registrations. Routing changes (Trunks/Incoming/Outbound/Gateways) restart
     Kamailio (route blocks are parsed only at startup), but registrations are
     persisted (db_text usrloc) and reloaded, so phones are **not** dropped and
     do not re-register.

4. **Configure each phone**:
   - SIP Server: pfSense LAN IP
   - SIP Port: as configured in Settings (default 5060)
   - Username: SIP ID from the Devices table
   - Password: SIP Password from the Devices table

5. **Verify** in *Services → SIP Registrar → Status* —
   registered phones should appear within 30–60 seconds.

Detailed instructions are available in `INSTALL.ru.md`.

---


See `SECURITY.ru.md` for the full security model.

---

## Author

Sergey Saidov <40user40@gmail.com>

## License

BSD 2-Clause License — see `LICENSE`.

## Repository

https://github.com/humaxoid/SipRegistar
