# 从 Instruments「Activity Monitor」录像（xctrace）里取 Kanpan 进程的 CPU 与内存（physical footprint）。
# 用法：python3 am.py am-start.trace am-end.trace
import subprocess, sys, statistics, xml.etree.ElementTree as ET
for tr in sys.argv[1:]:
    x = subprocess.run(['xcrun', 'xctrace', 'export', '--input', tr, '--xpath',
                        '/trace-toc/run[1]/data/table[@schema="activity-monitor-process-live"]'], capture_output=True, text=True).stdout
    root = ET.fromstring(x)
    ids = {e.attrib['id']: e for e in root.iter() if 'id' in e.attrib}
    val = lambda e: ids[e.attrib['ref']] if 'ref' in e.attrib else e
    cols = [c.find('mnemonic').text for c in root.iter('col')]
    rows = []
    for r in root.iter('row'):
        d = dict(zip(cols, [val(c) for c in r]))
        if 'Kanpan (' in d['process'].attrib.get('fmt', ''):
            rows.append((int(d['start'].text), int(d['cpu-total'].text), int(d['memory-physical-footprint'].text) / 1048576))
    (t0, c0, _), (t1, c1, _) = rows[0], rows[-1]
    ms = [r[2] for r in rows]
    print(f'{tr}: {(t1 - t0) / 1e9:.1f} 秒内 CPU 时间 {(c1 - c0) / 1e9:.2f} 秒，平均 {(c1 - c0) / (t1 - t0) * 100:.1f}%；'
          f'footprint 中位 {statistics.median(ms):.1f} MB（{min(ms):.1f}～{max(ms):.1f}）')
