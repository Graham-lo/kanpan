#!/usr/bin/env python3
"""从 Kanpan/Kanpan/Main/CoinBadgeBrands.swift 的八张静态表生成 CoinBadgeBrands.json。

一次性的搬家脚本（审查第 18 项）：Swift 表删掉之后 JSON 就是唯一真值，这个脚本不再有用。
只认这份文件里实际出现的那几种写法：
  "KEY": CoinSpec(from: "#…", to: "#…", mark: <MARK>[, inset: <NUM>]),
  <MARK> := .text("…") | fill([<STRS>]) | stroke([<STRS>], <NUM>) | .parts([Part(d: [<STRS>], stroke: <NUM>|nil), …])
  <STRS> := <STR> (+ <STR>)* , …
每条前面（上一条结束之后）的 // 注释和条目内部的 // 注释合成 note。
"""
import json, re, sys
from collections import OrderedDict

SRC, OUT = sys.argv[1], sys.argv[2]
src = open(SRC, encoding="utf-8").read()

# brand(_:) 的查表顺序，从源码里读，不手写。
order_m = re.search(r"static func brand\(_ key: String\) -> CoinSpec\? \{(.*?)\n  \}", src, re.S)
ORDER = re.findall(r"(\w+)\[key\]", order_m.group(1))
assert len(ORDER) == 8, ORDER

# 每张表前面那行分隔注释里的标题（「半导体与硬件」…），作 group。
GROUP_TITLE = {}
for m in re.finditer(r"// -{10,} (\S[^\n]*)\n(?:\s*//[^\n]*\n)*\s*\n?\s*private static let (\w+): \[String: CoinSpec\] = \[", src):
    GROUP_TITLE[m.group(2)] = m.group(1).strip()

class Tok:
    def __init__(self, kind, val, line):
        self.kind, self.val, self.line = kind, val, line
    def __repr__(self): return f"{self.kind}:{self.val!r}@{self.line}"

def tokenize(text, line0):
    toks, i, line = [], 0, line0
    n = len(text)
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1; i += 1; continue
        if c in " \t\r":
            i += 1; continue
        if text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            toks.append(Tok("comment", text[i + 2:j].strip(), line)); i = j; continue
        if c == '"':
            j = i + 1; buf = []
            while text[j] != '"':
                if text[j] == "\\":
                    nxt = text[j + 1]
                    buf.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}[nxt]); j += 2
                else:
                    buf.append(text[j]); j += 1
            toks.append(Tok("str", "".join(buf), line)); i = j + 1; continue
        m = re.match(r"-?\d+(?:\.\d+)?", text[i:])
        if m:
            toks.append(Tok("num", float(m.group(0)), line)); i += len(m.group(0)); continue
        m = re.match(r"\.?[A-Za-z_]\w*", text[i:])
        if m:
            toks.append(Tok("id", m.group(0), line)); i += len(m.group(0)); continue
        if c in "[](),:+":
            toks.append(Tok("p", c, line)); i += 1; continue
        raise SystemExit(f"认不出的字符 {c!r} 在第 {line} 行")
    return toks

class Parser:
    def __init__(self, toks):
        self.t = toks; self.i = 0; self.inner_comments = []
    def peek(self):
        while self.t[self.i].kind == "comment":
            self.inner_comments.append(self.t[self.i].val); self.i += 1
        return self.t[self.i]
    def take(self, kind=None, val=None):
        tok = self.peek()
        if (kind and tok.kind != kind) or (val is not None and tok.val != val):
            raise SystemExit(f"期望 {kind} {val!r}，得到 {tok}")
        self.i += 1
        return tok
    def string(self):
        s = self.take("str").val
        while self.peek().kind == "p" and self.peek().val == "+":
            self.take("p", "+"); s += self.take("str").val
        return s
    def strings(self):
        self.take("p", "["); out = []
        while not (self.peek().kind == "p" and self.peek().val == "]"):
            out.append(self.string())
            if self.peek().val == ",": self.take("p", ",")
        self.take("p", "]")
        return out
    def num_or_nil(self):
        tok = self.take()
        if tok.kind == "num": return tok.val
        if tok.kind == "id" and tok.val == "nil": return None
        raise SystemExit(f"期望数字或 nil，得到 {tok}")
    def part(self):
        self.take("id", "Part"); self.take("p", "(")
        self.take("id", "d"); self.take("p", ":"); d = self.strings()
        self.take("p", ","); self.take("id", "stroke"); self.take("p", ":"); w = self.num_or_nil()
        self.take("p", ")")
        return {"d": d, "stroke": w}
    def mark(self):
        head = self.take("id").val
        self.take("p", "(")
        if head == ".text":
            s = self.string(); self.take("p", ")"); return {"text": s}
        if head == "fill":
            d = self.strings(); self.take("p", ")"); return {"parts": [{"d": d, "stroke": None}]}
        if head == "stroke":
            d = self.strings(); self.take("p", ","); w = self.take("num").val; self.take("p", ")")
            return {"parts": [{"d": d, "stroke": w}]}
        if head == ".parts":
            self.take("p", "["); parts = []
            while not (self.peek().kind == "p" and self.peek().val == "]"):
                parts.append(self.part())
                if self.peek().val == ",": self.take("p", ",")
            self.take("p", "]"); self.take("p", ")")
            return {"parts": parts}
        raise SystemExit(f"认不出的记号写法 {head}")
    def spec(self):
        self.take("id", "CoinSpec"); self.take("p", "(")
        self.take("id", "from"); self.take("p", ":"); frm = self.string(); self.take("p", ",")
        self.take("id", "to"); self.take("p", ":"); to = self.string(); self.take("p", ",")
        self.take("id", "mark"); self.take("p", ":"); mark = self.mark()
        inset = 0.62
        if self.peek().val == ",":
            self.take("p", ","); self.take("id", "inset"); self.take("p", ":"); inset = self.take("num").val
        self.take("p", ")")
        return frm, to, mark, inset

def table_body(name):
    m = re.search(rf"private static let {name}: \[String: CoinSpec\] = \[\n", src)
    start = m.end()
    end = src.index("\n  ]\n", start)
    line0 = src.count("\n", 0, start) + 1
    return src[start:end], line0

def canon_part(p):
    out = OrderedDict([("d", p["d"])])
    if p["stroke"] is not None: out["stroke"] = p["stroke"]
    return out

def join_comments(lines):
    out = ""
    for ln in lines:
        if out and re.match(r"[A-Za-z0-9`(]", ln) and re.search(r"[A-Za-z0-9`),.;:]$", out):
            out += " "
        out += ln
    return out.strip()

# 原表里只有这两条前面没写依据（自 2968fed0 起就没有）。长期测试要求 note 非空，
# 这里按画法补记，并注明是搬家时补的。
MISSING_NOTES = {
    "PAYP": "PAYP：一只钱包——描边的外框，右侧一格填实的卡扣；配色与 PYPL 同一对。"
            "（原表这一条没写依据，搬成资源时按画法补记。）",
    "CSOPSKHYNIX2L": "南方 SK 海力士两倍做多：一块描边的方片压在一道底杠上，"
                     "和上面南方三星两倍做多「底下垫杠」同一个做法。（原表这一条没写依据，搬成资源时按画法补记。）",
}

result = OrderedDict()
seen_in = {}
dups = []
counts = OrderedDict()
for name in ORDER:
    body, line0 = table_body(name)
    toks = tokenize(body, line0)
    p = Parser(toks)
    pending = []  # 本条之前的注释
    subgroup = None  # 表内「// ── ETF：…」这种小节标题：它之后的条目 group 加上小节名
    counts[name] = 0
    while p.i < len(toks):
        tok = toks[p.i]
        if tok.kind == "comment":
            m = re.match(r"── ([^：]+)：", tok.val)
            if m: subgroup = m.group(1)
            pending.append(tok.val); p.i += 1; continue
        key = p.take("str").val
        p.take("p", ":")
        p.inner_comments = []
        frm, to, mark, inset = p.spec()
        inner = p.inner_comments
        # 条目后面的逗号；逗号之前若混进注释也算条目内部
        if p.i < len(toks) and toks[p.i].kind == "p" and toks[p.i].val == ",":
            p.i += 1
        note = join_comments(pending + inner) or MISSING_NOTES.get(key, "")
        pending = []
        counts[name] += 1
        if key in result:
            dups.append((key, seen_in[key], name))
            continue  # brand(_:) 先查到的那张为准
        entry = OrderedDict()
        entry["group"] = GROUP_TITLE.get(name, name) + (f" · {subgroup}" if subgroup else "")
        entry["note"] = note
        entry["from"] = frm
        entry["to"] = to
        entry["inset"] = inset
        if "text" in mark:
            entry["mark"] = OrderedDict([("text", mark["text"])])
        else:
            entry["mark"] = OrderedDict([("parts", [canon_part(x) for x in mark["parts"]])])
        result[key] = entry
        seen_in[key] = name
    if pending:
        raise SystemExit(f"{name} 表末尾有挂空的注释：{pending}")

empty = [k for k, v in result.items() if not v["note"]]
ABOUT = ("品种徽章的品牌标，一支一个记号（`CoinSpec.brand(_:)` 从 app 包里懒加载这一份）。"
         "由审查第 18 项从原 Main/CoinBadgeBrands.swift 的八张静态表（按原 brand(_:) 的查表顺序 "
         + " → ".join(ORDER) + "）用脚本逐条生成，此后这份文件就是唯一真值。"
         "note 是每一条的设计依据（用户纠正过两次：不能拿代号当图标，也不能整类共用一个图形），必填、不许删；"
         "group 只是原来那张小表的标题，查表不用它。坐标系是 24×24 的 viewBox；part 缺 stroke 表示填充，"
         "有 stroke 表示按这个宽度描边；inset 是记号占徽章边长的比例。"
         "加一支：照样子加一条，跑 make main-ios-test（CoinBadgeBrandsTests 会查条数、hex、路径、note）。")

def j(v): return json.dumps(v, ensure_ascii=False)

lines = ["{", f'  "about": {j(ABOUT)},', '  "brands": {']
keys = list(result)
for idx, key in enumerate(keys):
    e = result[key]
    lines.append(f"    {j(key)}: {{")
    lines.append(f'      "group": {j(e["group"])},')
    lines.append(f'      "note": {j(e["note"])},')
    lines.append(f'      "from": {j(e["from"])}, "to": {j(e["to"])}, "inset": {j(e["inset"])},')
    mark = e["mark"]
    if "text" in mark:
        lines.append(f'      "mark": {{"text": {j(mark["text"])}}}')
    else:
        lines.append('      "mark": {"parts": [')
        parts = mark["parts"]
        for pi, part in enumerate(parts):
            tail = "," if pi < len(parts) - 1 else ""
            if len(part["d"]) <= 1:
                body = f'{{"d": {j(part["d"])}' + (f', "stroke": {j(part["stroke"])}' if "stroke" in part else "") + "}"
                lines.append(f"        {body}{tail}")
            else:
                lines.append('        {"d": [')
                for di, dd in enumerate(part["d"]):
                    lines.append(f"          {j(dd)}" + ("," if di < len(part["d"]) - 1 else ""))
                lines.append("        ]" + (f', "stroke": {j(part["stroke"])}' if "stroke" in part else "") + f"}}{tail}")
        lines.append("      ]}")
    lines.append("    }" + ("," if idx < len(keys) - 1 else ""))
lines += ["  }", "}", ""]
text = "\n".join(lines)
assert json.loads(text)["brands"] == json.loads(json.dumps(result)), "手排版和数据不一致"
open(OUT, "w", encoding="utf-8").write(text)
print("order:", ORDER)
print("groups:", GROUP_TITLE)
print("per-table:", dict(counts), "sum", sum(counts.values()))
print("unique:", len(result))
print("dups:", dups)
print("empty notes:", empty)
