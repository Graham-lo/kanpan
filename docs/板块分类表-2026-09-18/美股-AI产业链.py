# -*- coding: utf-8 -*-
"""美股 AI 产业链板块表。代号用币安合约 baseAsset。
   歧义项与重复挂牌已用 /fapi/v1/constituents 反查真实交易所代码坐实。
   允许一只股跨段（高通既在算力芯片也在端侧），每段独立取中位数。"""

MEDIUM = {
 "gpu":    ("算力芯片", "AI 加速器、CPU、定制 ASIC、互连芯片、量子算力",
   "NVDA AMD AVGO MRVL INTC ARM QCOM CBRS ALAB CRDO TSM IONQ QNTX"),
 "mem":    ("存储", "HBM、DRAM、NAND、企业级硬盘",
   "MU SNDK WDC STXX SKHYNIX SAMSUNG GIGADEV CXMT"),
 "equip":  ("设备与材料", "光刻、刻蚀、量测、键合、衬底",
   "ASML AMAT LRCX KLAC TER HANMI AXTI"),
 "optic":  ("光通信与网络", "光模块、光器件、数据中心网络",
   "LITE COHR AAOI CIEN ZHONGJI CSCO GLW NOK"),
 "hyper":  ("云厂商", "超大规模云厂，AI 资本开支的出钱方，产业链需求的源头",
   "MSFT GOOGL AMZN META ORCL IBM BABA TENCENT"),
 "neo":    ("算力租赁", "neocloud、GPU 云、边缘推理，靠出租算力吃 capex 的一方",
   "CRWV NBIS IREN SHAZ NET"),
 "server": ("服务器与电力", "AI 整机、基板、液冷供电、数据中心发电储能",
   "DELL SMCI HPE PENG VRT FLEX SAMSUNGEM HK0992 GEV VST BE FLNC"),
 "edge":   ("端侧 AI", "手机与 PC 端 NPU、边缘推理芯片、传感与终端",
   "QCOM ARM AAPL HK1810 SONY TXN LGELECTRONICS HK0992 SAMSUNG"),
 "robot":  ("机器人与具身", "人形机器人、协作机器人、自动驾驶与自主系统",
   "UNITREE TSLA TER HYUNDAI ONDS RIVN"),
 "app":    ("模型与应用", "大模型、AI 软件与数据平台",
   "OPENAI ANTHROPIC ZHIPU MINIMAX PLTR CRM NOW ADBE SNOW APP TEM KUAISHOU NAVER"),
}
COARSE_MAP = {
 "silicon": ("硅与制造", ["gpu", "mem", "equip"]),
 "iron":    ("机房与互连", ["optic", "server"]),
 "compute": ("云与算力",   ["hyper", "neo"]),
 "intel":   ("终端与模型", ["edge", "robot", "app"]),
}
DEDUP = {"SKHY": "SKHYNIX", "HK0700": "TENCENT", "PAYP": "PYPL"}
EXCLUDE_ETP = """SOXL SOXS SNXX MUU MVLL INTW TQQQ SQQQ TSLL NVDL TMF TZA TBT UVXY
KORU SKUU SKDD RAM CSOPSAMSUNG2L CSOPSKHYNIX2L""".split()
EXCLUDE_ETF = """QQQ SPY SMH IWM EWY EWJ EWT EWZ XLE XBI GDX URNM KSTR BITO KODEX200
DRAM LYTE BOT""".split()
EXCLUDE_OTHER = ["STRC"]
NON_AI = """SPCX RKLB ASTS USAR CRCL MSTR COIN HOOD BMNR GME DJT MARA SOFI
BNC FWDI BSP BBX GS BX BRKB JPM V PYPL SHOP EBAY PDD MEITUAN POPMART HK0625 BYD
SONY_X DIS NFLX TTWO DKNG ZM TEAM WEN KO HD WMT COST CAT UBER
MRNA LLY NVO MRK HIMS RDDT GPRO CRWD PANW ZS DDOG MDB GTLB""".split()
