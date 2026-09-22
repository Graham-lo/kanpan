/// 价格提醒共用的铃声。原始值用于同步；资源名同时是 APNs 的 aps.sound。
enum AlertSound: String, CaseIterable, Sendable {
  case `default`, crisp, electronic, glass

  var title: String {
    switch self {
    case .default: "默认"
    case .crisp: "清脆"
    case .electronic: "电子"
    case .glass: "玻璃"
    }
  }

  var fileName: String? {
    self == .default ? nil : "alert-\(rawValue).caf"
  }
}
