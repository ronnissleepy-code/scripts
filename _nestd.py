#!/usr/bin/env python3
# ============================================================================
# nestd - the callback receiver for nested scanners.
#
# Victims cannot be trusted to give us a readable stream: measured on a real
# daemon (Docker 29.8.0), GET /containers/<id>/logs and POST /exec/<id>/start both
# return EMPTY while the plain JSON routes work fine. So a nested scanner reports
# by HTTP instead - one wget per hit, straight into the queue box1 already reads.
#
#   GET /hit?ip=X&f=Y   -> append "X\tnest" to .hunt/mass.found (deduped)
#   GET /alive?ip=Y     -> liveness breadcrumb for the victim
#   GET /stat           -> counters, for humans
#
# Box1 only reads mass.found; this just fills it, so a hit from a victim is
# indistinguishable downstream from a hit from the sweep - which is the point.
# ============================================================================
import http.server
import os
import socketserver
import threading
import time
import urllib.parse

HUNT = os.environ.get("HUNT_WORK", "/tmp/.sysd/.hunt")
PORT = int(os.environ.get("NEST_PORT", "8080"))
MASS = os.path.join(HUNT, "mass.found")
ALIVE = os.path.join(HUNT, "nest.alive")
HITLOG = "/tmp/_nestd.hits"

lock = threading.Lock()
known = set()
TALLY = {"hits": 0, "fresh": 0}


def load_known():
    try:
        with open(MASS, "r", errors="ignore") as fh:
            for line in fh:
                ip = line.split("\t")[0].strip()
                if ip:
                    known.add(ip)
    except FileNotFoundError:
        pass


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        ip = (q.get("ip") or [""])[0].strip()
        who = (q.get("f") or [""])[0].strip()
        if u.path == "/hit" and ip:
            with lock:
                fresh = ip not in known
                TALLY["hits"] += 1
                if fresh:
                    known.add(ip)
                    TALLY["fresh"] += 1
                    with open(MASS, "a") as fh:
                        fh.write("%s\tnest\n" % ip)
                # Log EVERY hit, not just fresh ones. The cursor spends its first
                # passes inside already-swept space, so a healthy scanner mostly
                # reports addresses we already know - and when only fresh hits were
                # logged, "1 hit" was indistinguishable from "the scanner is dead".
                with open(HITLOG, "a") as fh:
                    fh.write("%s\t%s\t%s\t%s\n" % (time.strftime("%H:%M:%S"), ip, "fresh" if fresh else "dup", who))
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok" if fresh else b"dup")
            return
        if u.path == "/alive" and ip:
            with open(ALIVE, "a") as fh:
                fh.write("%s\t%s\n" % (time.strftime("%H:%M:%S"), ip))
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")
            return
        if u.path == "/stat":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(("known=%d hits=%d fresh=%d\n" % (len(known), TALLY["hits"], TALLY["fresh"])).encode())
            return
        self.send_response(404)
        self.end_headers()


socketserver.ThreadingTCPServer.allow_reuse_address = True
with socketserver.ThreadingTCPServer(("0.0.0.0", PORT), Handler) as srv:
    load_known()
    srv.serve_forever()
