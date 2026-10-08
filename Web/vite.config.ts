import { defineConfig } from 'vitest/config'

// 线上挂在 https://kanpan.43-160-232-253.sslip.io/web/ 下（Caddy file_server），路由走 hash，不需要改 Caddy。
// 手机网页版是第二个入口 m/index.html → /web/m/（本机 http://localhost:5178/web/m/）。
// 本机开发时 /v1（市值元数据，没有 CORS 头）、/market（网关行情 WS）与 /oi（持仓量归档）转发到线上同一个域名，和线上同源行为一致。
const ORIGIN = 'https://kanpan.43-160-232-253.sslip.io'
export default defineConfig({
  base: '/web/',
  build: {
    outDir: 'dist', target: 'es2022', sourcemap: false, chunkSizeWarningLimit: 900,
    // 两个入口：PC（/web/，入口键仍叫 index，产物名 assets/index-*.js 不变）与手机网页版（/web/m/，入口脚本名 assets/m-*.js）
    rollupOptions: { input: { index: 'index.html', m: 'm/index.html' } },
  },
  server: {
    port: 5178, strictPort: false,
    proxy: {
      '/v1': { target: ORIGIN, changeOrigin: true, secure: true },
      '/market': { target: ORIGIN, changeOrigin: true, secure: true, ws: true },
      '/oi': { target: ORIGIN, changeOrigin: true, secure: true },
    },
  },
  test: { environment: 'node', include: ['tests/**/*.test.ts'] },
})
