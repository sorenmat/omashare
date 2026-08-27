# qs mDNS receiver-record fix

Upstream `qs` (martinalderson/qs + its `rquickshare` and `mdns-sd` git
dependencies, commits `a63bc7b` / `66e8b6b` / `c3d6ec2`, August 2026)
advertises its Quick Share receiver with an **unresolvable mDNS service
record**, so phones find the device by name but then cannot resolve its
IP:port: the phone shows *waiting…* and the transfer fails.

## Symptoms (before the fix)

- Phone's Quick Share picker lists the machine (PTR + TXT are answered).
- Choosing the device and sending a file: *waiting…* → *failed*.
- A/SRV follow-up behaviour observed with a raw mDNS probe:
  - PTR answer included an SRV additional (port, target = bare instance
    label like `I3gyQnP8n14AAA`) and A additionals **named after that bare
    label**.
  - A standalone `A` query for the instance FQDN got no answer (no record
    exists under the FQDN).
  - A standalone `A` query for the bare label also got no answer, because
    mdns-sd's answer path lowercases the question name but compares it to
    the un-lowercased, mixed-case base64 hostname — a case-sensitivity
    bug that can never match.

## The fix (three small patches, in `qs-mdns-patches/`)

1. `0001-mdns-sd-*.patch` — mdns-sd (`Martichou/mdns-sd`, branch
   `unsolicited`): answer A/AAAA/ANY queries case-insensitively and also
   when the question name is the instance fullname.
2. `0002-rquickshare-*.patch` — rquickshare
   (`martinalderson/rquickshare`, branch
   `feat/ble-receiver-connect-back`): use the instance fullname
   (`<instance>._FC9F5ED42C8A._tcp.local`) as the service hostname, so the
   SRV target and the A records live under the name clients actually
   query.
3. `0003-qs-*.patch` — qs: point `rqs_lib` at the local rquickshare and
   add a `[patch]` entry for the local mdns-sd.
4. `0004-rquickshare-*.patch` — rquickshare: bind the Wi-Fi bandwidth
   upgrade (BWU) listener to a **fixed TCP port 35353** (ephemeral
   fallback), so a host firewall can allow the phone's inbound upgrade
   connection with a single rule. See the next section for why that is
   needed.

## Wi-Fi speed needs one firewall rule

A phone→machine transfer starts over the BLE connect-back channel and then
upgrades to Wi-Fi: `qs` binds a TCP listener, offers the port to the phone
over the encrypted BLE channel (`UpgradePathAvailable`), and the phone
connects to that port for the payload. On a default-deny host firewall
(e.g. ufw with its stock input policy `DROP`) that TCP connect is silently
dropped — discovery still works because ufw's stock `before.rules` allows
multicast UDP 5353 (mDNS), and BLE is not IP — so `do_bwu()` times out
after 15 s and the whole file crawls over BLE at ≈150 KB/s.

Evidence on this machine: `[UFW BLOCK]` kernel log lines with the phone's
SYNs to the exact ephemeral ports qs had offered, e.g.
`SRC=192.168.50.208 DST=192.168.50.2 PROTO=TCP DPT=44715 SYN`.

With patch 0004 the listener is always on 35353/tcp, so allow it once:

```sh
sudo ufw allow in 35353/tcp comment 'omaShare Quick Share Wi-Fi upgrade'
```

After the upgrade completes, transfers run at Wi-Fi speed. The receiver
logs the handoff (`BWU: phone connected over TCP from …`) into the shell
journal — omaShare runs `qs receive` with
`RUST_LOG=info,rqs_lib=debug,mdns_sd=warn`.

## Rebuilding qs from a clean machine

```sh
mkdir -p ~/code && cd ~/code
git clone https://github.com/martinalderson/qs
git clone -b feat/ble-receiver-connect-back https://github.com/martinalderson/rquickshare
git clone -b unsolicited https://github.com/Martichou/mdns-sd
cd qs-mdns-patches
patch -p1 -d ../mdns-sd      < 0001-mdns-sd-*.patch
patch -p1 -d ../rquickshare  < 0002-rquickshare-*.patch
patch -p1 -d ../rquickshare  < 0004-rquickshare-*.patch
patch -p1 -d ../qs           < 0003-qs-*.patch
cd ../qs
cargo install --path . --bin qs --root "$HOME/.local"
omarchy restart shell   # let the omaShare service respawn the receiver
```

On this host the patched working copies already live at
`/home/smo/code/{qs,rquickshare,mdns-sd}`; the installed
`~/.local/bin/qs` was built from them (2026-08-27).

Verify the mDNS advertisement after restarting the shell (run on the
machine hosting the receiver; stdlib only):

```sh
python3 notes/qs-mdns-patches/verify-mdns.py   # expect PASS
```

Expected end-to-end: the phone completes transfers;
`omarchy-shell smo.omashare status` shows `transferring:true` briefly and
`recent` increments.

## Caveats

- The 0004 BWU port (35353/tcp) is a local choice; if something else on
  the host claims it, qs falls back to an ephemeral port and the firewall
  exception no longer matches (transfer then stays on BLE — slow but
  working). Pick another port in the patch and the `ufw allow` rule if
  35353 ever collides.
- When upstream lands the fixes, drop the local patches and
  `cargo install --git https://github.com/martinalderson/qs --bin qs
  --root ~/.local` again.
