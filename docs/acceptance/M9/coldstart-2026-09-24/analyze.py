# 冷启动逐帧：每段录像里「图区出现 K 线红绿」的第一帧。
# 两个口径：① 从 simctl launch 发出算（录像 t=0 对齐到「Recording started」那一刻，误差约一帧）；
# ② 从录像里画面第一次变化（系统开始画启动画面）算，不依赖两边时钟对齐。
import subprocess, sys, re, statistics, os
OUT = sys.argv[1] if len(sys.argv) > 1 else '/tmp/kanpan-pchain-m9/run'
REGION = ['0.02', '0.25', '0.85', '0.55']
times = {}
for line in open(os.path.join(OUT, 'times.txt')):
    m = re.match(r'(\d+) launch_cmd_start=([\d.]+) launch_cmd_end=([\d.]+) rec_started=([\d.]*)', line)
    if m: times[m.group(1)] = tuple(float(x) if x else None for x in m.groups()[1:])
rows = []
for i in sorted(times):
    v = os.path.join(OUT, f'cold-{i}.mp4')
    if not os.path.exists(v): continue
    fr = [tuple(map(float, l.split())) for l in subprocess.run(['/tmp/kanpan-pchain-m9/frames', v] + REGION, capture_output=True, text=True).stdout.split('\n') if l.strip()]
    if not fr: continue
    final = fr[-1][1]
    base_sum = fr[0][2]
    first_change = next((t for t, c, s in fr if abs(s - base_sum) > base_sum * 0.02), None)
    # 录像开头是主屏幕（图标同样是高彩度），要先等画面切进 app（彩像素掉到接近 0 的启动画面），
    # 之后第一次到末帧彩像素 30% 的那一帧才算出图。
    dark = next((k for k, (t, c, s) in enumerate(fr) if c < 50), None)
    chart = next((t for t, c, s in fr[dark:] if final > 0 and c >= 0.3 * final), None) if dark is not None else None
    ls, le, rs = times[i]
    wall = rs + chart - ls if (chart is not None and rs) else None
    rel = chart - first_change if (chart is not None and first_change is not None) else None
    rows.append((i, chart, first_change, wall, rel, int(final)))
    print(f"{i} 录像内出图 {chart} 画面首变 {first_change} 自launch起 {wall and round(wall*1000)}ms 自画面首变 {rel and round(rel*1000)}ms 末帧彩像素 {int(final)}")
for k, name in [(3, '自 launch 起'), (4, '自画面首变起')]:
    xs = [r[k] for r in rows if r[k] is not None and r[0] != '00']
    if xs: print(f"{name}（去掉 00 共 {len(xs)} 次）中位数 {round(statistics.median(xs)*1000)}ms 最小 {round(min(xs)*1000)} 最大 {round(max(xs)*1000)}")
