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
  - Later debugging showed even ANY responses carried **no A records at
    all**: the fork only populates addr-auto service addresses in
    `add_new_interface()`, which the daemon-startup interfaces never
    pass through — so the registered service had no addresses to answer
    with, whatever the question.

## The fix (four small patches, in `qs-mdns-patches/`)

1. `0001-mdns-sd-*.patch` — mdns-sd (`Martichou/mdns-sd`, branch
   `unsolicited`): (a) answer A/AAAA/ANY queries case-insensitively,
   trailing-dot-insensitively, and also when the question name is the
   instance fullname — parsed question names keep their trailing dot
   while `ServiceInfo`'s hostname does not, so naive comparisons never
   match; (b) seed the addresses of addr-auto services at registration —
   in this fork only `add_new_interface()` populates them, and the
   interfaces that existed at daemon startup never pass through it, so
   the service stayed address-less and even ANY responses carried no A
   records.
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

A phone connects **directly over Wi-Fi TCP to the mDNS-advertised SRV
port** — that is the standard Nearby Connections client behaviour. On a
default-deny host firewall (ufw with its stock input policy `DROP`) that
connect is silently dropped: discovery still works because ufw's stock
`before.rules` allows multicast UDP 5353 (mDNS), and Bluetooth is not IP,
so the phone falls back to the BLE connect-back path and the file crawls
at ≈150 KB/s — or the send fails outright.

Evidence on this machine: `[UFW BLOCK]` kernel log lines with the phone's
SYNs to the ports qs had advertised, e.g.
`SRC=<phone-ip> DST=<this-host> PROTO=TCP DPT=<port> SYN`.

The advertised port is random per start, so omaShare's helper runs
`qs receive --port 35353` and the host allows that one port:

```sh
sudo ufw allow in 35353/tcp comment 'omaShare Quick Share'
```

With the port reachable the phone transfers over Wi-Fi from the start.
For BLE-originated sessions rquickshare's bandwidth upgrade (patch 0004)
also binds 35353 first — while the main listener holds it, it falls back
to an ephemeral port, which the firewall then blocks (transfer stays on
BLE: slow but working). The receiver logs the protocol into the shell
journal (`RUST_LOG=info,rqs_lib=debug,mdns_sd=warn`), including
`BWU: phone connected over TCP from …` when an upgrade does complete.

## Installing qs

The fixes live in published forks, so one command installs a working
receiver. The `--rev` pins the exact reviewed commit (the marketplace
security baseline requires it); when the fork is intentionally
updated, bump the SHA here, in `install.sh`, `Service.qml`, and the
helper's hint in the same plugin commit:

```sh
cargo install --git https://github.com/sorenmat/qs --rev 7a5409bce9ea74140b688598ccc0ddf1730e5c54 --bin qs
```

That repo pins `rqs_lib` to [sorenmat/rquickshare `omashare`](https://github.com/sorenmat/rquickshare/tree/omashare)
and patches `mdns-sd` to [sorenmat/mdns-sd `omashare`](https://github.com/sorenmat/mdns-sd/tree/omashare);
the commit messages there describe each fix.

## Rebuilding by applying the patches yourself

The patch files in this directory are the same changes, kept for
reviewing and upstreaming:

```sh
mkdir -p ~/code && cd ~/code
git clone https://github.com/martinalderson/qs
git clone -b feat/ble-receiver-connect-back https://github.com/martinalderson/rquickshare
git clone -b unsolicited https://github.com/Martichou/mdns-sd
cd omashare/notes/qs-mdns-patches
patch -p1 -d ../mdns-sd      < 0001-mdns-sd-*.patch
patch -p1 -d ../rquickshare  < 0002-rquickshare-*.patch
patch -p1 -d ../rquickshare  < 0004-rquickshare-*.patch
patch -p1 -d ../qs           < 0003-qs-*.patch
cd ../qs
cargo install --path . --bin qs --root "$HOME/.local"
omarchy restart shell   # let the omaShare service respawn the receiver
```

Verify the mDNS advertisement after restarting the shell (run on the
machine hosting the receiver; stdlib only):

```sh
python3 notes/qs-mdns-patches/verify-mdns.py   # expect PASS
```

Expected end-to-end: the phone completes transfers;
`omarchy-shell smo.omashare status` shows `transferring:true` briefly and
`recent` increments.

## Upstreaming

The fixes are proposed upstream:

- Martichou/mdns-sd#1 (branch `unsolicited`) — A-query matching +
  addr-auto seeding.
- martinalderson/rquickshare#3 (branch
  `feat/ble-receiver-connect-back`) — resolvable mDNS hostname +
  pinned BWU port.

## Caveats

- The 0004 BWU port (35353/tcp) is a local choice; if something else on
  the host claims it, qs falls back to an ephemeral port and the firewall
  exception no longer matches (transfer then stays on BLE — slow but
  working). Pick another port in the patch and the `ufw allow` rule if
  35353 ever collides.
- When upstream lands the fixes, switch back to
  `cargo install --git https://github.com/martinalderson/qs --bin qs`
  and retire the forks.
