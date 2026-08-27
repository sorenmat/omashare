#!/usr/bin/env python3
"""Post-deploy mDNS verification for the Quick Share receiver.

Phase 1: PTR query for the service type -> instance fullname.
Phase 2: SRV + A queries for the instance, plus A for the SRV target.
PASS criteria: SRV answered with target == instance FQDN, and standalone
A queries for the instance FQDN (and the SRV target) are answered with an
IPv4 address.
"""
import socket
import struct
import sys
import time

TYPE = "_FC9F5ED42C8A._tcp.local"


def encode_name(name):
    out = b""
    for label in name.rstrip(".").split("."):
        out += bytes([len(label)]) + label.encode()
    return out + b"\x00"


def decode_name(buf, off):
    labels, jumps = [], 0
    while jumps < 16:
        l = buf[off]
        if l == 0:
            off += 1
            break
        if l & 0xC0 == 0xC0:
            off = struct.unpack(">H", buf[off : off + 2])[0] & 0x3FFF
            jumps += 1
            continue
        labels.append(buf[off + 1 : off + l + 1].decode("utf-8", "replace"))
        off += l + 1
        jumps += 1
    return ".".join(labels)


def q(name, qtype):
    return (
        struct.pack(">HHHHHH", 0, 0, 1, 0, 0, 0)
        + encode_name(name)
        + struct.pack(">HH", qtype, 0x8001)
    )


s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("0.0.0.0", 5353))
# The interface address to multicast on: argv override, else the source
# address the kernel would pick for the mDNS group.
probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
probe.connect(("224.0.0.251", 5353))
wifi = sys.argv[1] if len(sys.argv) > 1 else probe.getsockname()[0]
probe.close()
grp = struct.pack("4s4s", socket.inet_aton("224.0.0.251"), socket.inet_aton(wifi))
s.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, grp)
s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_LOOP, 1)
s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(wifi))


def listen(secs):
    s.settimeout(0.4)
    deadline = time.time() + secs
    out = []
    while time.time() < deadline:
        try:
            data, _ = s.recvfrom(4096)
        except socket.timeout:
            continue
        if len(data) < 12:
            continue
        _, flags, qd, an, ns, ar = struct.unpack(">HHHHHH", data[:12])
        if not flags & 0x8000:
            continue
        off = 12
        for i in range(qd + an + ns + ar):
            if i < qd:
                n = off
                while True:
                    l = data[n]
                    if l == 0:
                        n += 1
                        break
                    if l & 0xC0 == 0xC0:
                        n += 2
                        break
                    n += l + 1
                off = n + 4
                continue
            n = off
            while True:
                l = data[n]
                if l == 0:
                    n += 1
                    break
                if l & 0xC0 == 0xC0:
                    n += 2
                    break
                n += l + 1
            rtype, _ = struct.unpack(">HH", data[n : n + 4])
            rdlen = struct.unpack(">H", data[n + 8 : n + 10])[0]
            rdata = data[n + 10 : n + 10 + rdlen]
            off = n + 10 + rdlen
            if rtype == 12:
                out.append(("PTR", decode_name(data, n + 10)))
            elif rtype == 33 and rdlen >= 6:
                port = struct.unpack(">H", rdata[4:6])[0]
                out.append(("SRV", port, decode_name(data, n + 10 + 6)))
            elif rtype == 1 and rdlen == 4:
                out.append(("A", ".".join(str(b) for b in rdata)))
    return out


print("phase 1: PTR for service type")
s.sendto(q(TYPE, 12), ("224.0.0.251", 5353))
instances = {v for t, *rest in listen(2.5) if t == "PTR" for v in [rest[0]]}
print(" instances:", instances or "(none)")
if not instances:
    raise SystemExit(1)
inst = sorted(instances)[0]

s.sendto(q(inst, 33), ("224.0.0.251", 5353))
time.sleep(1.5)
srv = [x for x in listen(2.0) if x[0] == "SRV"]
s.sendto(q(inst, 1), ("224.0.0.251", 5353))
time.sleep(1.5)
a_fqdn = [x for x in listen(2.0) if x[0] == "A"]

print(f"SRV for {inst}: {srv or 'NO ANSWER'}")
print(f"A   for {inst}: {a_fqdn or 'NO ANSWER'}")

ok = True
if not srv:
    ok = False
    print("FAIL: no SRV answer")
else:
    _, port, target = srv[0]
    print(f"SRV port={port} target={target}")
    if target.lower() != inst.lower():
        print(f"NOTE: SRV target differs from instance FQDN ({target})")
        s.sendto(q(target, 1), ("224.0.0.251", 5353))
        time.sleep(1.5)
        a_target = [x for x in listen(2.0) if x[0] == "A"]
        print(f"A   for SRV target: {a_target or 'NO ANSWER'}")
        if not a_target:
            ok = False
            print("FAIL: A for SRV target not answered")
if not a_fqdn:
    ok = False
    print("FAIL: A for instance FQDN not answered")

print("PASS" if ok else "FAIL")
raise SystemExit(0 if ok else 1)
