#!/bin/zsh
set -e
OUT=raw
mkdir -p $OUT
for sym in BTCUSDT ETHUSDT SOLUSDT; do
  for iv in 1m 5m 15m 1h 4h 1d; do
    curl -s --max-time 20 "https://fapi.binance.com/fapi/v1/klines?symbol=$sym&interval=$iv&limit=1000" -o "$OUT/k_${sym}_${iv}.json"
    printf "%s %s %s bytes\n" $sym $iv $(wc -c < "$OUT/k_${sym}_${iv}.json")
  done
  curl -s --max-time 20 "https://fapi.binance.com/futures/data/openInterestHist?symbol=$sym&period=1h&limit=500" -o "$OUT/oi_${sym}_1h.json"
  curl -s --max-time 20 "https://fapi.binance.com/futures/data/openInterestHist?symbol=$sym&period=5m&limit=500" -o "$OUT/oi_${sym}_5m.json"
done
curl -s --max-time 25 "https://fapi.binance.com/fapi/v1/exchangeInfo" -o "$OUT/exchangeInfo.json"
curl -s --max-time 25 "https://fapi.binance.com/fapi/v1/ticker/24hr" -o "$OUT/ticker24.json"
echo "exchangeInfo $(wc -c < $OUT/exchangeInfo.json) ticker $(wc -c < $OUT/ticker24.json)"
