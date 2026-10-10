#!/usr/bin/env python3
"""加一个跟人走（.synced）的设置字段：一条命令把三端的样板全写好（2026-10-10「同步字段解耦」）。

用法（仓库根）：
  make new-sync-field name=chartHints rule=bool default=true note='图上提示条开不开'
  make new-sync-field name=fooMode rule='enum:a|b|c' default=a
  make new-sync-field name=fooRatio rule='number:0.5..2' default=1
  make new-sync-field name=fooCount rule='int:1..9' default=3
  make new-sync-field name=fooLabel rule='string:64' default=''
  （也可以直接 python3 Tools/new-sync-field.py name=… rule=… default=… [note=…] [contract=no]）

它做的事（每处都插在源码里 `↑ new-sync-field:<槽位>` 那一行上面）：
  1. iOS 母表：PrefsFieldPlan.table 记 .synced、PrefsFieldPlan.rules 记值规则；
  2. iOS Prefs：字段与出厂值（enum / number / int / string 另带一个 static 的词表 / 区间 / 字节上限，
     规则和解码都引用它，数只写一次）；PrefsCodec 的 CodingKey、编码、按规则的宽容解码；
  3. 服务端 sync.rs SETTINGS_FIELDS 加名字（值规则不用写：服务端按契约校验）；
  4. 手机网页 prefs.ts：类型、SYNCED_FIELDS、出厂值、normalizePrefs 里按契约清洗；
  5. 电脑网页 codec.ts PC_UNUSED_SYNCED_FIELDS 放一条 TODO——tests/pc-sync-fields-contract.test.ts 会一直红，
     直到有人决定电脑接不接（接：挪进 SETTINGS_FIELDS 写换算；不接：TODO 换成一句为什么）；
  6. 跑 make sync-contract 重新生成契约（contract=no 跳过）。

只管通用规则里简单的五种（bool / enum / number / int / string）。数组、计次表、嵌套对象这类照现有字段手写，
值规则装不下就在服务端 sync_validation::custom_setting 写一个函数、规则写 .custom("函数名")。
界面（设置页那一行、PrefsStore 的改法）它不碰。
"""
import datetime
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TODAY = datetime.date.today().isoformat()

FILES = {
    'plan': 'Kanpan/Kanpan/Settings/Model/PrefsFieldPlan.swift',
    'rule': 'Kanpan/Kanpan/Settings/Model/PrefsFieldRules.swift',
    'prefs-field': 'Kanpan/Kanpan/Settings/Model/Prefs.swift',
    'coding-key': 'Kanpan/Kanpan/Settings/Model/PrefsCodec.swift',
    'encode': 'Kanpan/Kanpan/Settings/Model/PrefsCodec.swift',
    'decode': 'Kanpan/Kanpan/Settings/Model/PrefsCodec.swift',
    'server-allowlist': 'Backend/kanpan-api/src/sync.rs',
    'm-interface': 'Web/src/m/app/prefs.ts',
    'm-synced': 'Web/src/m/app/prefs.ts',
    'm-default': 'Web/src/m/app/prefs.ts',
    'm-normalize': 'Web/src/m/app/prefs.ts',
    'pc-unused': 'Web/src/sync/codec.ts',
}


def die(msg):
    sys.stderr.write('new-sync-field: ' + msg + '\n')
    sys.exit(2)


def read(rel):
    with open(os.path.join(ROOT, rel), encoding='utf-8') as f:
        return f.read()


def parse_args(argv):
    args = {}
    for a in argv:
        if '=' not in a:
            die(f'参数要写成 key=value：{a!r}')
        k, v = a.split('=', 1)
        args[k.strip()] = v
    for k in ('name', 'rule', 'default'):
        if k not in args:
            die(f'缺 {k}=…（用法见 Tools/new-sync-field.py 开头）')
    return args


def num(text, what):
    try:
        v = float(text)
    except ValueError:
        die(f'{what} 不是数：{text!r}')
    if v != v or v in (float('inf'), float('-inf')):
        die(f'{what} 要是有限的数：{text!r}')
    return v


def fmt(v):
    """Swift / TS 都认的数字面量：整数不带 .0，其余照 repr。"""
    return str(int(v)) if float(v).is_integer() else repr(v)


def plan_for(name, rule, default, note):
    """按规则算出每个槽位要插的那几行。"""
    kind, _, spec = rule.partition(':')
    doc = f'{note}（{TODAY}，跟账号同步；make new-sync-field 生成）'
    swift_static = []
    if kind == 'bool':
        if default not in ('true', 'false'):
            die('bool 的 default 只能是 true / false')
        swift_type, swift_default, ts_type, ts_default = 'Bool', default, 'boolean', default
        rule_expr = '.bool'
        decode = f'if let v = bool(.{name}) {{ {name} = v }}'
    elif kind == 'enum':
        values = [v for v in spec.split('|')]
        if not values or any(not v for v in values) or len(set(values)) != len(values):
            die("enum 写成 enum:a|b|c（不能有空值、不能重复）")
        if any(not re.fullmatch(r'[A-Za-z0-9_.\-]+', v) for v in values):
            die('enum 的值只用字母、数字、_ . -')
        if default not in values:
            die(f'default {default!r} 不在 {values} 里')
        lst = ', '.join(f'"{v}"' for v in values)
        swift_static.append(f'  /// `{name}` 的取值（值规则与解码都认这一张）。')
        swift_static.append(f'  static let {name}Values: [String] = [{lst}]')
        swift_type, swift_default = 'String', f'"{default}"'
        ts_type = ' | '.join(f"'{v}'" for v in values)
        ts_default = f"'{default}'"
        rule_expr = f'.enumeration(Prefs.{name}Values)'
        decode = f'if let raw = str(.{name}), Prefs.{name}Values.contains(raw) {{ {name} = raw }}'
    elif kind in ('number', 'int'):
        m = re.fullmatch(r'\s*(-?[0-9.eE+-]+)\s*\.\.\s*(-?[0-9.eE+-]+)\s*', spec)
        if not m:
            die(f'{kind} 写成 {kind}:最小..最大，比如 {kind}:1..9')
        lo, hi, d = num(m.group(1), '最小'), num(m.group(2), '最大'), num(default, 'default')
        if lo > hi:
            die('最小比最大还大')
        if not lo <= d <= hi:
            die(f'default {default} 不在 {fmt(lo)}…{fmt(hi)} 里')
        if kind == 'int':
            if not all(float(x).is_integer() for x in (lo, hi, d)):
                die('int 的上下限与 default 都要是整数')
            swift_type, ts_type = 'Int', 'number'
            swift_static.append(f'  /// `{name}` 的取值范围（值规则与解码都认这一段）。')
            swift_static.append(f'  static let {name}Range: ClosedRange<Int> = {fmt(lo)}...{fmt(hi)}')
            rule_expr = f'.int(min: Prefs.{name}Range.lowerBound, max: Prefs.{name}Range.upperBound)'
            decode = (f'if let v = try? c.decode(Int.self, forKey: .{name}) '
                      f'{{ {name} = min(max(v, Prefs.{name}Range.lowerBound), Prefs.{name}Range.upperBound) }}')
        else:
            swift_type, ts_type = 'Double', 'number'
            swift_static.append(f'  /// `{name}` 的取值范围（值规则与解码都认这一段）。')
            swift_static.append(f'  static let {name}Range: ClosedRange<Double> = {fmt(lo)}...{fmt(hi)}')
            rule_expr = f'.number(min: Prefs.{name}Range.lowerBound, max: Prefs.{name}Range.upperBound)'
            decode = (f'if let v = try? c.decode(Double.self, forKey: .{name}), v.isFinite '
                      f'{{ {name} = min(max(v, Prefs.{name}Range.lowerBound), Prefs.{name}Range.upperBound) }}')
        swift_default = ts_default = fmt(d)
    elif kind == 'string':
        if not spec.isdigit() or int(spec) <= 0:
            die('string 写成 string:最多几个 UTF-8 字节，比如 string:64')
        n = int(spec)
        if len(default.encode('utf-8')) > n:
            die(f'default 超过 {n} 字节')
        if '"' in default or '\\' in default or "'" in default:
            die('default 里别带引号和反斜杠')
        swift_static.append(f'  /// `{name}` 最多几个 UTF-8 字节（服务端数字节，不数字符）。')
        swift_static.append(f'  static let {name}MaxBytes = {n}')
        swift_type, swift_default, ts_type, ts_default = 'String', f'"{default}"', 'string', f"'{default}'"
        rule_expr = f'.string(maxBytes: Prefs.{name}MaxBytes)'
        decode = f'if let raw = str(.{name}), raw.utf8.count <= Prefs.{name}MaxBytes {{ {name} = raw }}'
    else:
        die(f'不认识的规则 {rule!r}：脚手架只管 bool / enum:a|b / number:lo..hi / int:lo..hi / string:N，'
            '别的照现有字段手写（见 AGENTS.md「加 / 删一个同步字段」）')
    return {
        'plan': [f'    // {TODAY} {note}', f'    "{name}": .synced,'],
        'rule': [f'      "{name}": {rule_expr},'],
        'prefs-field': [f'  /// {doc}', f'  var {name}: {swift_type} = {swift_default}', *swift_static, ''],
        'coding-key': [f'    case {name}'],
        'encode': [f'    try c.encode({name}, forKey: .{name})'],
        'decode': [f'    {decode}'],
        'server-allowlist': [f' // {TODAY} {note}', f' "{name}",'],
        'm-interface': [f'  /** {note}（与 iOS `Prefs.{name}` 同义，{TODAY}；make new-sync-field 生成） */', f'  {name}: {ts_type}'],
        'm-synced': [f"  '{name}',"],
        'm-default': [f'    {name}: {ts_default},'],
        'm-normalize': [f"    {name}: g('{name}'),"],
        'pc-unused': [f"  {name}: 'TODO：电脑网页要不要接？接就挪进 SETTINGS_FIELDS 写换算，不接把这句换成为什么不用',"],
    }


def insert(text, slot, lines, rel):
    marker = f'new-sync-field:{slot} '
    hits = [i for i, l in enumerate(text.split('\n')) if marker in l]
    if len(hits) != 1:
        die(f'{rel} 里 `↑ new-sync-field:{slot}` 那一行找到 {len(hits)} 处（应该正好一处），没法插')
    rows = text.split('\n')
    at = hits[0]
    return '\n'.join(rows[:at] + lines + rows[at:])


def main():
    a = parse_args(sys.argv[1:])
    name, rule, default = a['name'].strip(), a['rule'].strip(), a['default']
    note = a.get('note', '').strip() or 'TODO：一句话说这是什么、为什么跟人走'
    if not re.fullmatch(r'[a-z][A-Za-z0-9]{1,47}', name):
        die('name 用小驼峰（字母开头、只含字母数字），和 iOS 字段名、线上键名同一个')
    plan = read(FILES['plan'])
    if re.search(rf'"{re.escape(name)}"\s*:', plan):
        die(f'`{name}` 已经在 PrefsFieldPlan.table 里了')
    sync_rs = read(FILES['server-allowlist'])
    retired = re.search(r'pub const RETIRED_SETTINGS_FIELDS:&\[&str\]=&\[([\s\S]*?)\];', sync_rs)
    if retired and f'"{name}"' in re.sub(r'//.*', '', retired.group(1)):
        die(f'`{name}` 是退役的键（sync.rs RETIRED_SETTINGS_FIELDS）：老客户端写的是另一种语义，换个名字')
    if re.search(rf'\b{re.escape(name)}\b', read(FILES['m-interface'])):
        die(f'`{name}` 已经出现在 Web/src/m/app/prefs.ts 里了')

    edits = plan_for(name, rule, default, note)
    texts = {}
    for slot, lines in edits.items():
        rel = FILES[slot]
        texts[rel] = insert(texts.get(rel) or read(rel), slot, lines, rel)
    for rel, text in texts.items():
        with open(os.path.join(ROOT, rel), 'w', encoding='utf-8') as f:
            f.write(text)
        print(f'  改了 {rel}')

    if a.get('contract', 'yes') != 'no':
        print('  跑 make sync-contract 重新生成契约 …')
        r = subprocess.run(['make', 'sync-contract'], cwd=ROOT)
        if r.returncode != 0:
            die('make sync-contract 没跑通（上面的输出说了原因）；样板已经写进去了，修好再跑一次 make sync-contract')

    print(f"""
`{name}` 的样板写好了。还剩下要人做的：
  - 电脑网页：Web/src/sync/codec.ts 的 PC_UNUSED_SYNCED_FIELDS 里那条 TODO——接就挪进 SETTINGS_FIELDS 写换算，
    不接就写一句为什么（不改 tests/pc-sync-fields-contract.test.ts 一直红）；
  - note 还是 TODO 的话，把 Prefs.swift / PrefsFieldPlan.swift / sync.rs / prefs.ts 里那几句补成人话；
  - 界面：设置页那一行、PrefsStore 的改法、手机网页的入口；
  - 跑测试：make settings-test account-codec-test、make backend-test、cd Web && npx tsc --noEmit && npx vitest run。
""")


if __name__ == '__main__':
    main()
