#!/bin/bash
# 交易所隔离守卫（多交易所 阶段 2）。
#
# 某一家交易所的名字、域名、「以 USDT 结尾就是币安」这类判断，只许出现在：
#   - KanpanNetwork/Sources/KanpanNetwork/<交易所>/   （那一家的提供者）
#   - KanpanNetwork/Sources/KanpanNetwork/Provider/VenueRegistry.swift（唯一的交易所清单）
# 其余源码一律只认 `MarketProvider` 与 `ProviderCapabilities`。测试不在此列。
# 接新交易所时把它的目录加进 VENUE_DIRS。见 docs/多交易所-接入指南.md。
set -euo pipefail
cd "$(dirname "$0")/.."

VENUE_DIRS='^KanpanNetwork/Sources/KanpanNetwork/(Binance|Coinbase|OrderFlow)/'
REGISTRY='^KanpanNetwork/Sources/KanpanNetwork/Provider/VenueRegistry\.swift$'
PATTERN='Binance\|Coinbase\|fapi\.binance\|coinbase\.com\|hasSuffix("USDT")'

files=$(git ls-files --cached --others --exclude-standard -- '*.swift' \
  | grep -Ev 'Tests/|Tests\.swift$' \
  | grep -Ev "$VENUE_DIRS" \
  | grep -Ev "$REGISTRY" || true)

hits=$(printf '%s\n' "$files" | sed '/^$/d' | tr '\n' '\0' | xargs -0 grep -n "$PATTERN" 2>/dev/null || true)
if [ -n "$hits" ]; then
  echo "交易所隔离被破坏：下面这些地方直接点了某家交易所的名字或域名。"
  echo "请改用 MarketProvider / ProviderCapabilities / VenueRegistry。"
  echo "$hits"
  exit 1
fi
echo "交易所隔离：通过（$(printf '%s\n' "$files" | sed '/^$/d' | wc -l | tr -d ' ') 个源文件）"
