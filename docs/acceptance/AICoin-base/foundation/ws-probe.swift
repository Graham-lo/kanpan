import Foundation
let prefix = CommandLine.arguments.dropFirst().first ?? "market"
let url = URL(string: "wss://fstream.binance.com/\(prefix == "legacy" ? "" : prefix + "/")stream?streams=btcusdt@kline_1m/btcusdt@ticker/btcusdt@markPrice@1s")!
let task = URLSession.shared.webSocketTask(with: url)
task.resume()
let timeout = Task { try? await Task.sleep(for: .seconds(16)); task.cancel(with: .goingAway, reason: nil) }
var counts: [String:Int] = [:], first: [String:Double] = [:], last: [String:Double] = [:]
let start = Date()
do {
  while true {
    let msg = try await task.receive()
    let data: Data
    switch msg { case .data(let d): data=d; case .string(let s): data=Data(s.utf8); @unknown default: continue }
    guard let obj=try JSONSerialization.jsonObject(with:data) as? [String:Any], let payload=obj["data"] as? [String:Any], let e=payload["e"] as? String else { continue }
    let elapsed=Date().timeIntervalSince(start)
    counts[e,default:0]+=1
    if first[e] == nil { first[e]=elapsed }
    last[e]=elapsed
  }
} catch { print("end:",error.localizedDescription) }
print("endpoint:",url.absoluteString)
print("counts:",counts,"firstSeconds:",first,"lastSeconds:",last)
timeout.cancel()
