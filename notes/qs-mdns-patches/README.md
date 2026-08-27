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

## Rebuilding qs from a clean machine

```sh
mkdir -p ~/code && cd ~/code
git clone https://github.com/martinalderson/qs
git clone -b feat/ble-receiver-connect-back https://github.com/martinalderson/rquickshare
git clone -b unsolicited https://github.com/Martichou/mdns-sd
cd qs-mdns-patches
patch -p1 -d ../mdns-sd      < 0001-mdns-sd-*.patch
patch -p1 -d ../rquickshare  < 0002-rquickshare-*.patch
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

- Transfers on this build are slow (≈150 KB/s observed). The current
  rquickshare branch receives over the BLE "connect-back" path first and
  is supposed to upgrade to Wi-Fi bandwidth afterwards; that upgrade does
  not seem to complete on this machine, so data stays on BLE. Upstream may
  fix this — re-check the branch before keeping these patches long-term.
- When upstream lands the fixes, drop the local patches and
  `cargo install --git https://github.com/martinalderson/qs --bin qs
  --root ~/.local` again.
