// 手机网页版搜品种的拼音表生成器：浏览器里没有汉字转拼音的字典，
// 所以在 Mac 上用 iOS 同一套 CFStringTransform（SymbolAliases.pinyin）把别名表算好、提交成 JSON。
// 别名表改了（market/searchText.ts 的 CRYPTO_NAMES、sectors.json 的 usNames）就重跑：
//   swift scripts/gen-pinyin.swift > src/m/model/pinyin.json
// tests/m-search.test.ts 会拦住漏跑的情况。
import Foundation

func isHan(_ c: Character) -> Bool {
  c.unicodeScalars.contains { (0x3400...0x4DBF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }
}

/// 照 SymbolAliases.pinyin：只取汉字、转拉丁、去声调、按音节切，连起来是全拼，各取首字母是缩写
func pinyin(_ text: String) -> [String]? {
  let han = String(text.filter(isHan))
  guard !han.isEmpty else { return nil }
  let buffer = NSMutableString(string: han) as CFMutableString
  guard CFStringTransform(buffer, nil, kCFStringTransformMandarinLatin, false),
        CFStringTransform(buffer, nil, kCFStringTransformStripDiacritics, false) else { return nil }
  let syllables = (buffer as String).split(whereSeparator: { $0 == " " || $0 == "'" }).map { $0.uppercased() }.filter { !$0.isEmpty }
  guard !syllables.isEmpty else { return nil }
  return [syllables.joined(), String(syllables.compactMap(\.first))]
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
var names = Set<String>()

let search = try String(contentsOf: root.appendingPathComponent("src/market/searchText.ts"), encoding: .utf8)
if let start = search.range(of: "export const CRYPTO_NAMES"), let end = search.range(of: "\n}\n", range: start.upperBound..<search.endIndex) {
  let block = String(search[start.upperBound..<end.lowerBound])
  let re = try NSRegularExpression(pattern: "'([^']*)'")
  for m in re.matches(in: block, range: NSRange(block.startIndex..., in: block)) {
    if let r = Range(m.range(at: 1), in: block) { names.insert(String(block[r])) }
  }
}
let sectors = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("src/data/sectors.json"))) as! [String: Any]
for v in (sectors["usNames"] as? [String: String] ?? [:]).values { names.insert(v) }

var out: [String: [String]] = [:]
for n in names { if let p = pinyin(n) { out[n] = p } }
let data = try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys, .prettyPrinted])
print(String(data: data, encoding: .utf8)!)
