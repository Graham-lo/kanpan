#!/bin/bash
# 交易所隔离守卫（多交易所 阶段 2）。
#
# 某一家交易所的名字、域名、「以 USDT 结尾就是币安」这类判断，只许出现在：
#   - KanpanNetwork/Sources/KanpanNetwork/<交易所>/   （那一家的提供者）
#   - KanpanNetwork/Sources/KanpanNetwork/Provider/VenueRegistry.swift（唯一的交易所清单）
#   - Kanpan/Kanpan/Exchange/<交易所>/   （那一家的只读账户，自动复盘用）
#   - Kanpan/Kanpan/Exchange/ExchangeAccountRegistry.swift（只读账户的交易所清单）
# 其余源码一律只认 `MarketProvider` 与 `ProviderCapabilities`。测试不在此列。
# 接新交易所时把它的目录加进 VENUE_DIRS。见 docs/多交易所-接入指南.md。
set -euo pipefail
cd "$(dirname "$0")/.."

VENUE_DIRS='^(KanpanNetwork/Sources/KanpanNetwork/(Binance|Coinbase|Macro|OrderFlow)|Kanpan/Kanpan/Exchange/(Binance))/'
REGISTRY='^(KanpanNetwork/Sources/KanpanNetwork/Provider/VenueRegistry|Kanpan/Kanpan/Exchange/ExchangeAccountRegistry)\.swift$'
PATTERN='Binance\|Coinbase\|fapi\.binance\|coinbase\.com\|hasSuffix("USDT")'

files=$(git ls-files --cached --others --exclude-standard -- '*.swift' \
  | grep -Ev 'Tests/|Tests\.swift$' \
  | grep -Ev "$VENUE_DIRS" \
  | grep -Ev "$REGISTRY" || true)

# 只看代码，不看注释：行注释（`//` 前是行首或空白；`https://` 这种 `:` 后的 `//` 不算）里解释
# 「Coinbase 现货等由谁补价」不算点名。2026-10-04 深度审查 D / E 线补的十来处说明注释曾把守卫整条判红。
hits=$(printf '%s\n' "$files" | sed '/^$/d' | tr '\n' '\0' | xargs -0 grep -n "$PATTERN" 2>/dev/null \
  | awk -v pat="$PATTERN" '{
      line = $0; sub(/^[^:]+:[0-9]+:/, "", line)
      sub(/(^|[[:space:]])\/\/.*$/, "", line)
      re = pat; gsub(/\\\|/, "|", re)
      if (line ~ re) print $0
    }' || true)
if [ -n "$hits" ]; then
  echo "交易所隔离被破坏：下面这些地方直接点了某家交易所的名字或域名。"
  echo "请改用 MarketProvider / ProviderCapabilities / VenueRegistry。"
  echo "$hits"
  exit 1
fi
echo "交易所隔离：通过（$(printf '%s\n' "$files" | sed '/^$/d' | wc -l | tr -d ' ') 个源文件）"
