-- Public history identity and ANN lookup. Rows remain provenance-bound by source.
CREATE UNIQUE INDEX market_features_identity
ON market_features(market, symbol, timeframe, start_at, end_at, model_id, render_version, source);

CREATE INDEX market_features_embedding_ann
ON market_features USING hnsw (embedding vector_cosine_ops)
WHERE published
  AND model_id = 'candle-geometry-v2'
  AND render_version = 'ohlc-geometry-resample64-v2';
