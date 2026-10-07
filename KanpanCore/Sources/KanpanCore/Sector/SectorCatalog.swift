import Foundation

/// 板块页的**归类目录**：板块 id、中文名、以及它收录的 base 代号。
///
/// 口径来自 `docs/板块分类表-2026-09-18/`（2026-09-18 用户确认「分得很好，就按照这个来即可」），
/// 由 `scratchpad/gen-sector-catalog.py` 一次性生成成静态表——**运行时不解析任何 TSV/JSON**。
/// 归类是不会变的那一半，会变的那一半（涨跌幅、成交额）实时从行情流来。
///
/// 注意跟 `MarketSector` 分清楚：那个是交易所元数据（品种属于哪个市场），
/// 这里是板块页的目录（板块收了哪些品种），两者互不覆盖。
///
/// 几条不许破的规矩：
/// - 加密固定 24 个 id，照 `加密-板块定义.md`，**不得自创**。
/// - TSV 里标 `NONE` 的 48 个币不进任何板块；它们在运行时按交易所自带 tag 兜底，
///   由调用方传 `SectorFallbackBucket`，不是这张静态表的事。
/// - 美股头 10 个细分照 `美股-AI产业链.py` 的 `MEDIUM`，已过 `DEDUP` 归并与
///   `EXCLUDE_ETP` / `EXCLUDE_ETF` / `EXCLUDE_OTHER` / `NON_AI` 剔除；
///   「软件」「电力」是 2026-09-18 手工补的两个：软件把原先落在「其他」里的一批软件公司捞了
///   回来，电力则是把原「服务器与电力」里供电散热那半边单独立了一格。当天一度还分出过一格
///   「硬件」，同日按用户要求并回了「算力芯片」——ARM / AVGO / ALAB 仍在算力芯片里。
/// - 2026-10-08 起美股在 12 个 AI 细分之后再加 11 个手工归类的板块（加密概念、金融、消费、
///   媒体娱乐、医药、汽车与出行、航天、能源与资源、ETF 与基金、杠杆做多、反向与波动），把原来
///   一股脑落进「其他」兜底桶的那百来只捞回来，「其他」只剩读不出是什么的几只（≤ 15）。
///   ETF / 杠杆 / 反向产品**仍不许进 12 个 AI 细分**（混一只两倍做多就把中位数拽歪），
///   只进它们自己的那三格。
/// - 一个品种允许跨板块（SOL 同时在 `sol-eco` 与 `l1`，高通同时在 `gpu` 与 `edge`），
///   每个板块各自算各自的中位数。

public enum SectorMarket: String, Codable, Sendable, CaseIterable { case crypto, us }

/// 一个板块的静态定义。`members` 是去重后的 base 代号，全大写。
public struct SectorDef: Sendable, Equatable, Identifiable {
  public let id: String
  public let name: String
  public let market: SectorMarket
  public let members: [String]
  public init(id: String, name: String, market: SectorMarket, members: [String]) {
    self.id = id; self.name = name; self.market = market; self.members = members
  }
}

public enum SectorCatalog {
  /// 固定顺序：加密 24 个在前，美股 23 个在后（12 个 AI 细分 + 11 个手工归类）。
  public static let all: [SectorDef] = crypto + us

  public static func sectors(_ m: SectorMarket) -> [SectorDef] {
    switch m { case .crypto: return crypto; case .us: return us }
  }

  public static func sector(id: String) -> SectorDef? { byID[id] }

  /// 反查：这个代号进了哪几个板块。按 `all` 的顺序返回，可为空（兜底品种就是空）。
  public static func sectors(for base: String, market: SectorMarket) -> [SectorDef] {
    let key = base.uppercased()
    return (byBase[market]?[key] ?? []).compactMap { byID[$0] }
  }

  /// 美股标的的中文公司名（`美股-中文名.json`）。加密一律没有，返回 nil。
  public static func chineseName(base: String) -> String? { usChineseNames[base.uppercased()] }

  // MARK: - 加密 24 个细分板块

  public static let crypto: [SectorDef] = [
    SectorDef(id: "l1", name: "公链 Layer-1", market: .crypto, members: [
      "0G", "1000LUNC", "A", "ADA", "ALGO", "APT", "ARK", "ASTR",
      "ATOM", "AVAX", "BB", "BERA", "BNB", "CC", "CELO", "CFX",
      "CHR", "CKB", "CROSS", "CTK", "DATAIP", "DOT", "DUSK", "DYM",
      "EGLD", "ETC", "ETHW", "FLOW", "FOGO", "G", "GAS", "GRAM",
      "GUN", "HBAR", "HIVE", "HYPE", "ICP", "INIT", "INJ", "IOST",
      "IOTA", "IOTX", "KAIA", "KAS", "KAVA", "KITE", "KSM", "LUNA2",
      "M", "MANTRA", "MINA", "MITO", "MON", "MOVR", "NEAR", "NEO",
      "NIGHT", "ONE", "ONG", "ONT", "PHAROS", "PLUME", "POLYX", "QTUM",
      "RONIN", "ROSE", "RVN", "S", "SAGA", "SEI", "SOL", "SOMI",
      "STABLE", "STEEM", "SUI", "TAC", "TAO", "TIA", "TRX", "VET",
      "VTHO", "WAXP", "XLM", "XPL", "XRP", "XTZ", "ZETA", "ZIL"
    ]),  // 88 个
    SectorDef(id: "ai", name: "AI 代币", market: .crypto, members: [
      "0G", "ACT", "AGT", "AIA", "AIGENSYN", "AIN", "AIO", "AIOT",
      "AIXBT", "AKE", "AKT", "ALCH", "ALLO", "ARC", "ARIA", "ATH",
      "AVAAI", "AWE", "BLUAI", "C", "CARV", "CGPT", "CHIP", "CLANKER",
      "COAI", "COOKIE", "ELSA", "FET", "FLOCK", "GOAT", "GRASS", "GRIFFAIN",
      "GUA", "HOLO", "IDOL", "IN", "IO", "JCT", "KAITO", "KITE",
      "LA", "LPT", "LYN", "MIRA", "NEWT", "NIL", "NMR", "OPEN",
      "OPG", "PHA", "PIEVERSE", "PRL", "PROMPT", "Q", "RECALL", "RENDER",
      "RLC", "ROBO", "SAHARA", "SAPIEN", "SENT", "SHELL", "SKYAI", "SWARMS",
      "TA", "TAG", "TAO", "THETA", "UAI", "UB", "US", "VANA",
      "VELVET", "VIRTUAL", "VVV", "WLD", "XNY", "ZEREBRO"
    ]),  // 78 个
    SectorDef(id: "meme", name: "Meme", market: .crypto, members: [
      "1000000BOB", "1000000MOG", "1000BONK", "1000CAT", "1000CHEEMS", "1000FLOKI", "1000PEPE", "1000RATS",
      "1000SATS", "1000SHIB", "1MBABYDOGE", "4", "ACT", "B", "BAN", "BANANAS31",
      "BOME", "BRETT", "BROCCOLI714", "BROCCOLIF3B", "BULLA", "CHILLGUY", "DOGE", "DOGS",
      "FARTCOIN", "GIGGLE", "GOAT", "JELLYJELLY", "KOMA", "M", "MARSCOIN", "MELANIA",
      "MEME", "MEW", "MOODENG", "MUBARAK", "NEIRO", "NOT", "ORDI", "PENGU",
      "PEOPLE", "PIPPIN", "PNUT", "POPCAT", "PUMP", "SIREN", "SPX", "TOSHI",
      "TRUMP", "TST", "TURBO", "TUT", "USELESS", "WIF", "ZEREBRO"
    ]),  // 55 个
    SectorDef(id: "sol-eco", name: "Solana 生态", market: .crypto, members: [
      "1000BONK", "ALCH", "ARC", "ARX", "AVAAI", "BAN", "BIRB", "BOME",
      "CHILLGUY", "DRIFT", "FARTCOIN", "FIDA", "GOAT", "GRASS", "GRIFFAIN", "HOLO",
      "JELLYJELLY", "JTO", "JUP", "KMNO", "LAYER", "ME", "MELANIA", "MET",
      "MEW", "MOODENG", "ORCA", "PENGU", "PIPPIN", "PNUT", "POPCAT", "PRL",
      "PUMP", "RAYSOL", "SKR", "SLX", "SOL", "SONIC", "SWARMS", "TNSR",
      "TRUMP", "USELESS", "WET", "WIF", "ZEREBRO"
    ]),  // 45 个
    SectorDef(id: "defi-blue", name: "DeFi 蓝筹", market: .crypto, members: [
      "1INCH", "AAVE", "AERO", "BNT", "CAKE", "CETUS", "COMP", "COW",
      "CRV", "CVX", "DEEP", "DODOX", "DOLO", "EUL", "FLUID", "FRAX",
      "GMX", "JOE", "JST", "JUP", "KMNO", "KNC", "LISTA", "LQTY",
      "MAV", "MORPHO", "ORCA", "RAYSOL", "RUNE", "SKY", "SNX", "SPELL",
      "SPK", "SUN", "SUSHI", "THE", "UNI", "VELODROME", "WOO", "XVS",
      "YB", "YFI", "ZRX"
    ]),  // 43 个
    SectorDef(id: "gamefi", name: "链游 GameFi", market: .crypto, members: [
      "ACE", "AGLD", "AKE", "ALICE", "ARIA", "AXS", "BEAMX", "BEAT",
      "BIGTIME", "CARV", "CATI", "CHR", "CROSS", "ENJ", "ESPORTS", "FORM",
      "GALA", "GMT", "GUN", "HMSTR", "ILV", "IMX", "KGEN", "MAGIC",
      "MAVIA", "NOT", "NXPC", "PIXEL", "PLAY", "PORTAL", "POWER", "RONIN",
      "SAGA", "SAND", "SLP", "SOMI", "SONIC", "SUPER", "TAKE", "TLM",
      "WAXP", "XAI", "YGG"
    ]),  // 43 个
    SectorDef(id: "l2", name: "Layer-2 扩容", market: .crypto, members: [
      "ALT", "ARB", "AZTEC", "B2", "BTR", "CTR", "CTSI", "CYBER",
      "ERA", "ESP", "HEMI", "IMX", "KAT", "LINEA", "LSK", "LUMIA",
      "MANTA", "MEGA", "MERL", "METIS", "MOVE", "OP", "POL", "PROM",
      "SCR", "SKL", "SONIC", "SOON", "SOPH", "STRK", "STX", "TAIKO",
      "XAI", "ZK", "ZORA"
    ]),  // 35 个
    SectorDef(id: "depin", name: "DePIN 物理基建", market: .crypto, members: [
      "2Z", "ACU", "AIGENSYN", "AIOT", "AKT", "ATH", "BLESS", "CYS",
      "FIL", "FLUX", "GLM", "GRASS", "HOT", "ICNT", "IO", "IOTX",
      "JASMY", "JCT", "LPT", "NAORIS", "PHA", "POWR", "RENDER", "RLC",
      "ROBO", "SKR", "SPACE", "STAR", "THETA", "XPIN"
    ]),  // 30 个
    SectorDef(id: "nft-social", name: "NFT 与社交", market: .crypto, members: [
      "AGLD", "ANIME", "APE", "BIRB", "BLUR", "COLLECT", "CYBER", "DOOD",
      "ENJ", "EPIC", "FLOW", "HANA", "HIVE", "IMX", "MASK", "ME",
      "MEME", "MOCA", "PENGU", "RARE", "STEEM", "SUPER", "TNSR", "TOWNS",
      "WAXP", "ZORA"
    ]),  // 26 个
    SectorDef(id: "stable-yield", name: "稳定币与生息", market: .crypto, members: [
      "CAP", "CHIP", "EDEN", "ENA", "FF", "FRAX", "LISTA", "LQTY",
      "OGN", "PENDLE", "RESOLV", "RIVER", "RSR", "SKY", "SLX", "SPELL",
      "SPK", "STABLE", "STBL", "SYRUP", "TREE", "USDC", "USTC", "USUAL",
      "WLFI"
    ]),  // 25 个
    SectorDef(id: "btc-eco", name: "比特币生态", market: .crypto, members: [
      "1000RATS", "1000SATS", "B2", "BABY", "BANK", "BARD", "BB", "BR",
      "BTC", "BTR", "CTR", "HEMI", "LIGHT", "MERL", "ORDI", "PTB",
      "PUMPBTC", "RIF", "SOLV", "STX", "T", "ZEST"
    ]),  // 22 个
    SectorDef(id: "storage-data", name: "存储与数据", market: .crypto, members: [
      "0G", "AR", "ARKM", "BMT", "C", "CARV", "DATAIP", "FIL",
      "GRT", "ICNT", "IRYS", "JASMY", "SQD", "SXT", "TIA", "TRUST",
      "TRUTH", "UB", "VANA", "WAL", "XNY"
    ]),  // 21 个
    SectorDef(id: "zk", name: "零知识证明", market: .crypto, members: [
      "AZTEC", "BREV", "CTR", "CYS", "LA", "LINEA", "MANTA", "MINA",
      "ON", "PROM", "PROVE", "SCR", "SOPH", "STRK", "SXT", "TAIKO",
      "ZBT", "ZK", "ZKC", "ZKP"
    ]),  // 20 个
    SectorDef(id: "rwa", name: "RWA 现实资产", market: .crypto, members: [
      "CC", "CFG", "CHIP", "COLLECT", "DUSK", "EDEN", "EPIC", "HUMA",
      "LUMIA", "MANTRA", "ONDO", "PAXG", "PHAROS", "PLUME", "POLYX", "RE",
      "STBL", "SYRUP", "USUAL", "XAUT"
    ]),  // 20 个
    SectorDef(id: "oracle-bridge", name: "预言机与跨链", market: .crypto, members: [
      "API3", "AXL", "BAND", "CELR", "DIA", "HYPER", "LINK", "PTB",
      "PYTH", "QNT", "RED", "RUNE", "STG", "SYN", "TRB", "UMA",
      "W", "ZETA", "ZRO"
    ]),  // 19 个
    SectorDef(id: "payment", name: "支付", market: .crypto, members: [
      "1000XEC", "ACH", "BCH", "BSV", "CELO", "COTI", "DASH", "GRAM",
      "HUMA", "KITE", "LTC", "MTL", "PIEVERSE", "PUNDIX", "STABLE", "TRIA",
      "XLM", "XPL", "XRP"
    ]),  // 19 个
    SectorDef(id: "perp-dex", name: "链上永续 DEX", market: .crypto, members: [
      "AEVO", "ASTER", "AVNT", "BASED", "DRIFT", "DYDX", "EDGE", "F",
      "GMX", "GRVT", "HYPE", "INJ", "LIT", "MYX", "NOM", "ORDER",
      "SNX", "TRADOOR"
    ]),  // 18 个
    SectorDef(id: "pow", name: "PoW 挖矿", market: .crypto, members: [
      "1000XEC", "BCH", "BSV", "BTC", "CFX", "CKB", "DASH", "DOGE",
      "ETC", "ETHW", "FLUX", "KAS", "LTC", "RVN", "XMR", "XVG",
      "ZEC", "ZEN"
    ]),  // 18 个
    SectorDef(id: "privacy", name: "隐私", market: .crypto, members: [
      "ARX", "AZTEC", "CC", "COTI", "DASH", "DUSK", "FHE", "NIGHT",
      "NIL", "ROSE", "T", "XMR", "XVG", "ZAMA", "ZEC", "ZEN",
      "ZKP"
    ]),  // 17 个
    SectorDef(id: "eth-eco", name: "以太坊生态", market: .crypto, members: [
      "EIGEN", "ENS", "ETH", "ETHFI", "GWEI", "KERNEL", "LDO", "REZ",
      "RPL", "SAFE", "SSV", "STO"
    ]),  // 12 个
    SectorDef(id: "metaverse", name: "元宇宙", market: .crypto, members: [
      "ALICE", "APE", "AWE", "AXS", "IDOL", "ILV", "MANA", "MOCA",
      "SAND", "TLM"
    ]),  // 10 个
    SectorDef(id: "meme-cn", name: "华语 Meme", market: .crypto, members: [
      "哈基米", "币安人生", "我踏马来了", "牛来", "龙虾"
    ]),  // 5 个
    SectorDef(id: "fan-token", name: "粉丝代币", market: .crypto, members: [
      "ALPINE", "ASR", "CHZ", "OG", "SANTOS"
    ]),  // 5 个
    SectorDef(id: "desci", name: "DeSci 去中心化科学", market: .crypto, members: [
      "BIO"
    ]),  // 1 个
  ]

  // MARK: - 美股 23 个板块（12 个 AI 产业链细分 + 11 个手工归类）

  public static let us: [SectorDef] = [
    SectorDef(id: "gpu", name: "算力芯片", market: .us, members: [
      "NVDA", "AMD", "AVGO", "INTC", "QCOM", "ARM", "ALAB", "CBRS", "IONQ", "QNTX"
    ]),  // 10 个。算力这颗芯片本身怎么来的都算这一格：按片卖的商用加速卡、给云厂商做的定制
    // ASIC、授权出去的 IP，以及把它们插在一块板上的互连（ALAB 做 PCIe / CXL 板级互连，不走光）。
    // 代工和封装不在这儿，在「设备与材料」。ARM 在「端侧 AI」里还有一份，那是它另一条腿，不冲突。
    SectorDef(id: "mem", name: "存储", market: .us, members: [
      "MU", "SNDK", "WDC", "STXX", "SKHY", "SKHYNIX", "SAMSUNG", "GIGADEV", "CXMT"
    ]),  // 9 个。SKHY 是 SK 海力士的 ADR，和 SKHYNIX 在币安上是两个独立合约，两档都要在。
    // TSM 2026-09-18 从「算力芯片」挪过来：台积电是代工厂，吃的是制造与先进封装这个环节，
    // 和 ASML、AMAT、HANMI（韩美半导体做封装设备）是同一条线，不跟着芯片设计公司的定价权走。
    SectorDef(id: "equip", name: "设备与材料", market: .us, members: [
      "ASML", "AMAT", "LRCX", "KLAC", "TER", "HANMI", "AXTI", "TSM"
    ]),  // 8 个
    // MRVL 与 CRDO 2026-09-18 从「算力芯片」挪过来：Marvell 的主业是光模块 DSP 和定制互连，
    // Credo 的主力是 AEC 有源电缆和光 DSP，两家吃的都是光模块那条出货节奏，不是卖商用算力芯片的。
    SectorDef(id: "optic", name: "光通信与网络", market: .us, members: [
      "LITE", "COHR", "AAOI", "CIEN", "ZHONGJI", "CSCO", "GLW", "NOK", "MRVL", "CRDO",
      "ANET"
    ]),  // 11 个。ANET（Arista，数据中心交换机）2026-10-08 补。
    SectorDef(id: "hyper", name: "云厂商", market: .us, members: [
      "MSFT", "GOOGL", "AMZN", "META", "ORCL", "IBM", "BABA", "TENCENT"
    ]),  // 8 个
    SectorDef(id: "neo", name: "算力租赁", market: .us, members: [
      "CRWV", "NBIS", "IREN", "SHAZ", "NET", "APLD", "AGPU"
    ]),  // 7 个。APLD（Applied Digital，AI 数据中心托管）、AGPU（Axe Compute，GPU 算力）2026-10-08 补。
    SectorDef(id: "server", name: "服务器", market: .us, members: [
      "DELL", "SMCI", "HPE", "PENG", "FLEX", "SAMSUNGEM", "HK0992"
    ]),  // 7 个。整机与代工这一层，只跟着服务器出货走。
    // 2026-09-18 从「服务器与电力」里拆出来：机柜供电、散热、发电和储能是另一门生意，
    // 跟的是数据中心开工与电价，不是服务器出货。VRT（Vertiv）做的是数据中心的供电与散热
    // 基础设施，不是服务器本身，所以归电力不归服务器。
    SectorDef(id: "power", name: "电力", market: .us, members: [
      "VRT", "GEV", "VST", "BE", "FLNC", "OKLO", "CAT"
    ]),  // 7 个。OKLO（小型核电）、CAT（数据中心备用发电机组）2026-10-08 补。
    SectorDef(id: "edge", name: "端侧 AI", market: .us, members: [
      "QCOM", "ARM", "AAPL", "HK1810", "SONY", "TXN", "LGELECTRONICS", "HK0992",
      "SAMSUNG"
    ]),  // 9 个
    SectorDef(id: "robot", name: "机器人与具身", market: .us, members: [
      "UNITREE", "TSLA", "TER", "HYUNDAI", "ONDS", "RIVN"
    ]),  // 6 个
    // 卖软件的那一层：安全、可观测、数据库、开发协作、自动化。它们的强弱跟着 IT 预算走，
    // 和「模型与应用」里那批靠模型讲故事的公司不是一回事，混在一起两边的中位数都读不准。
    SectorDef(id: "software", name: "软件", market: .us, members: [
      "CRM", "NOW", "ADBE", "SNOW", "CRWD", "PANW", "ZS", "DDOG",
      "MDB", "GTLB", "TEAM", "PATH", "ZM", "ACN", "AKAM", "BSP"
    ]),  // 16 个。ACN（埃森哲）、AKAM（Akamai）、BSP（Bending Spoons）2026-10-08 补。
    SectorDef(id: "app", name: "模型与应用", market: .us, members: [
      "OPENAI", "ANTHROPIC", "ZHIPU", "MINIMAX", "PLTR", "APP", "TEM", "KUAISHOU",
      "NAVER"
    ]),  // 9 个。PLTR / APP / TEM 的故事是模型驱动的，所以留在这儿，不跟 CRM 那批走。

    // —— 以下 11 个是 2026-10-08 手工归类的，不属于 AI 产业链 ——
    SectorDef(id: "cryptoeq", name: "加密概念", market: .us, members: [
      "COIN", "MSTR", "HOOD", "CRCL", "MARA", "HUT", "BMNR", "BNC",
      "FWDI", "STRC", "CYPH", "SECZ"
    ]),  // 12 个。交易所、稳定币、矿企与囤币公司（BMNR 囤 ETH、BNC 囤 BNB、FWDI 囤 SOL）。
    SectorDef(id: "bank", name: "金融", market: .us, members: [
      "JPM", "GS", "V", "BX", "BRKB", "SOFI", "PYPL"
    ]),  // 7 个。PAYP 是 PayPal 的旧代号（DEDUP），不重复收。
    SectorDef(id: "consumer", name: "消费", market: .us, members: [
      "KO", "MCD", "WMT", "COST", "HD", "NKE", "EBAY", "SHOP", "PDD", "WEN", "GPRO",
      "MEITUAN", "POPMART"
    ]),  // 13 个
    SectorDef(id: "media", name: "媒体娱乐", market: .us, members: [
      "DIS", "NFLX", "TTWO", "RDDT", "RUM", "GME", "AMC", "DKNG", "DJT"
    ]),  // 9 个
    SectorDef(id: "pharma", name: "医药", market: .us, members: [
      "LLY", "MRK", "MRNA", "NVO", "UNH", "HIMS", "VKTX", "TWST"
    ]),  // 8 个
    SectorDef(id: "auto", name: "汽车与出行", market: .us, members: [
      "TSLA", "RIVN", "BYD", "HYUNDAI", "UBER", "CVNA"
    ]),  // 6 个。TSLA / RIVN / HYUNDAI 在「机器人与具身」里还有一份，跨板块不冲突。
    SectorDef(id: "space", name: "航天", market: .us, members: [
      "SPCX", "RKLB", "ASTS"
    ]),  // 3 个。SPCX 是币安的 SpaceX 永续。
    SectorDef(id: "resource", name: "能源与资源", market: .us, members: [
      "XOM", "MP", "USAR", "CRML"
    ]),  // 4 个。石油与稀土 / 关键金属。
    SectorDef(id: "etf", name: "ETF 与基金", market: .us, members: [
      "SPY", "QQQ", "IWM", "SMH", "XBI", "XLE", "GDX", "URNM", "DRAM", "LYTE",
      "EWJ", "EWT", "EWY", "EWZ", "KSTR", "KODEX200", "BWET", "BITO", "BOT"
    ]),  // 19 个。宽基、行业、国家 ETF，加上 BITO（比特币期货 ETF）、BOT（机器人封闭式基金）。
    SectorDef(id: "lev", name: "杠杆做多", market: .us, members: [
      "SOXL", "TQQQ", "TMF", "KORU", "TSLL", "NVDL", "INTW", "MUU", "MVLL",
      "SNXX", "SKUU", "RAM", "CSOPSAMSUNG2L", "CSOPSKHYNIX2L"
    ]),  // 14 个
    SectorDef(id: "inverse", name: "反向与波动", market: .us, members: [
      "SOXS", "SQQQ", "TZA", "TBT", "SKDD", "UVXY"
    ]),  // 6 个。反向和波动率产品单列，不和做多那格互相抵消。
  ]

  /// 12 个 AI 产业链细分（`us` 的前 12 个）。ETF / 杠杆 / 反向产品不许进这几格。
  public static let usAIIDs: [String] = ["gpu", "mem", "equip", "optic", "hyper", "neo", "server",
                                         "power", "edge", "robot", "software", "app"]

  // MARK: - 索引

  private static let byID: [String: SectorDef] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

  private static let byBase: [SectorMarket: [String: [String]]] = {
    var out: [SectorMarket: [String: [String]]] = [:]
    for d in all {
      for b in d.members { out[d.market, default: [:]][b, default: []].append(d.id) }
    }
    return out
  }()

  private static let usChineseNames: [String: String] = [
    "NVDA": "英伟达", "AMD": "AMD", "AVGO": "博通",
    "MRVL": "Marvell", "INTC": "英特尔", "ARM": "ARM",
    "QCOM": "高通", "CBRS": "Cerebras", "ALAB": "Astera Labs",
    "CRDO": "Credo", "TSM": "台积电", "IONQ": "IonQ",
    "QNTX": "Quantinuum", "MU": "美光", "SNDK": "闪迪",
    "WDC": "西部数据", "STXX": "希捷", "SKHYNIX": "SK 海力士",
    "SKHY": "SK 海力士 ADR", "SAMSUNG": "三星电子", "GIGADEV": "兆易创新",
    "CXMT": "长鑫存储",
    "ASML": "ASML", "AMAT": "应用材料", "LRCX": "泛林",
    "KLAC": "科天", "TER": "泰瑞达", "HANMI": "韩美半导体",
    "AXTI": "AXT", "LITE": "Lumentum", "COHR": "Coherent",
    "AAOI": "AOI", "CIEN": "Ciena", "ZHONGJI": "中际旭创",
    "CSCO": "思科", "GLW": "康宁", "NOK": "诺基亚",
    "MSFT": "微软", "GOOGL": "谷歌", "AMZN": "亚马逊",
    "META": "Meta", "ORCL": "甲骨文", "IBM": "IBM",
    "BABA": "阿里巴巴", "TENCENT": "腾讯", "CRWV": "CoreWeave",
    "NBIS": "Nebius", "IREN": "IREN", "SHAZ": "SharonAI",
    "NET": "Cloudflare", "DELL": "戴尔", "SMCI": "超微",
    "HPE": "慧与", "PENG": "Penguin Solutions", "VRT": "Vertiv",
    "FLEX": "伟创力", "SAMSUNGEM": "三星电机", "HK0992": "联想",
    "GEV": "GE Vernova", "VST": "Vistra", "BE": "Bloom Energy",
    "FLNC": "Fluence", "AAPL": "苹果", "HK1810": "小米",
    "SONY": "索尼", "TXN": "德州仪器", "LGELECTRONICS": "LG 电子",
    "UNITREE": "宇树科技", "TSLA": "特斯拉", "HYUNDAI": "现代汽车",
    "ONDS": "Ondas", "RIVN": "Rivian", "OPENAI": "OpenAI",
    "ANTHROPIC": "Anthropic", "ZHIPU": "智谱", "MINIMAX": "MiniMax",
    "PLTR": "Palantir", "CRM": "Salesforce", "NOW": "ServiceNow",
    "ADBE": "Adobe", "SNOW": "Snowflake", "APP": "AppLovin",
    "TEM": "Tempus AI", "KUAISHOU": "快手", "NAVER": "Naver",
    "CRWD": "CrowdStrike", "PANW": "Palo Alto", "ZS": "Zscaler",
    "DDOG": "Datadog", "MDB": "MongoDB", "GTLB": "GitLab",
    "TEAM": "Atlassian", "PATH": "UiPath", "ZM": "Zoom",
    // 2026-10-08 补进 AI 细分的
    "APLD": "Applied Digital", "AGPU": "Axe Compute", "ANET": "Arista",
    "OKLO": "Oklo", "CAT": "卡特彼勒", "ACN": "埃森哲", "AKAM": "Akamai",
    "BSP": "Bending Spoons",
    // 加密概念
    "COIN": "Coinbase", "MSTR": "Strategy", "HOOD": "Robinhood", "CRCL": "Circle", // venue-name-ok：上市公司名，不是交易所
    "MARA": "MARA", "HUT": "Hut 8", "BMNR": "BitMine", "BNC": "CEA Industries",
    "FWDI": "Forward Industries", "STRC": "Strategy 优先股", "CYPH": "Cypherpunk",
    "SECZ": "Securitize",
    // 金融
    "JPM": "摩根大通", "GS": "高盛", "V": "Visa", "BX": "黑石", "BRKB": "伯克希尔 B",
    "SOFI": "SoFi", "PYPL": "PayPal",
    // 消费
    "KO": "可口可乐", "MCD": "麦当劳", "WMT": "沃尔玛", "COST": "好市多", "HD": "家得宝",
    "NKE": "耐克", "EBAY": "eBay", "SHOP": "Shopify", "PDD": "拼多多", "WEN": "温蒂汉堡",
    "GPRO": "GoPro", "MEITUAN": "美团", "POPMART": "泡泡玛特",
    // 媒体娱乐
    "DIS": "迪士尼", "NFLX": "奈飞", "TTWO": "Take-Two", "RDDT": "Reddit", "RUM": "Rumble",
    "GME": "游戏驿站", "AMC": "AMC 院线", "DKNG": "DraftKings", "DJT": "特朗普媒体",
    // 医药
    "LLY": "礼来", "MRK": "默沙东", "MRNA": "Moderna", "NVO": "诺和诺德", "UNH": "联合健康",
    "HIMS": "Hims & Hers", "VKTX": "Viking", "TWST": "Twist",
    // 汽车与出行、航天、能源与资源
    "BYD": "比亚迪", "UBER": "优步", "CVNA": "Carvana",
    "SPCX": "SpaceX", "RKLB": "Rocket Lab", "ASTS": "AST SpaceMobile",
    "XOM": "埃克森美孚", "MP": "MP Materials", "USAR": "USA Rare Earth", "CRML": "Critical Metals",
    // ETF 与基金
    "SPY": "标普 500 ETF", "QQQ": "纳指 100 ETF", "IWM": "罗素 2000 ETF", "SMH": "半导体 ETF",
    "XBI": "生物科技 ETF", "XLE": "能源 ETF", "GDX": "金矿 ETF", "URNM": "铀矿 ETF",
    "DRAM": "存储 ETF", "LYTE": "光子 ETF", "EWJ": "日本 ETF", "EWT": "台湾 ETF",
    "EWY": "韩国 ETF", "EWZ": "巴西 ETF", "KSTR": "科创 50 ETF", "KODEX200": "KODEX 200",
    "BWET": "油轮运价 ETF", "BITO": "比特币期货 ETF", "BOT": "RoboStrategy",
    // 杠杆做多
    "SOXL": "三倍做多半导体", "TQQQ": "三倍做多纳指", "TMF": "三倍做多美债",
    "KORU": "三倍做多韩国", "TSLL": "两倍做多特斯拉", "NVDL": "两倍做多英伟达",
    "INTW": "两倍做多英特尔", "MUU": "两倍做多美光", "MVLL": "两倍做多 Marvell",
    "SNXX": "两倍做多闪迪", "SKUU": "两倍做多 SK 海力士", "RAM": "两倍做多存储",
    "CSOPSAMSUNG2L": "两倍做多三星", "CSOPSKHYNIX2L": "两倍做多 SK 海力士（港）",
    // 反向与波动
    "SOXS": "三倍做空半导体", "SQQQ": "三倍做空纳指", "TZA": "三倍做空罗素 2000",
    "TBT": "两倍做空美债", "SKDD": "做空 SK 海力士", "UVXY": "VIX 波动率",
  ]
}
