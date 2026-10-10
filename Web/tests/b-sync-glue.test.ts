import { describe, it, expect, vi, beforeEach } from 'vitest'

// ─── 同步：自选与提醒同一轮变了，自选侧栏也要重画（B19） ───
const h = vi.hoisted(() => ({ adapter: null as null | { apply(s: unknown): unknown }, renderPanel: vi.fn(), notifyAlerts: vi.fn(), applied: {} as Record<string, unknown> }))
vi.mock('../src/app/store', () => ({ st: {}, save: vi.fn(), subscribe: vi.fn(), drawingsSuspect: () => false, clearDrawingsSuspect: vi.fn() }))
vi.mock('../src/app/shell', () => ({ hooks: { booted: [] }, applyTheme: vi.fn() }))
vi.mock('../src/market', () => ({ S: { symbols: new Map() } }))
vi.mock('../src/pages/chart', () => ({ allCells: () => [], cfg: vi.fn(), drawingsFor: vi.fn(), renderPanel: h.renderPanel, renderToolbar: vi.fn(), applyLayoutSet: vi.fn(), refreshWebPrefs: vi.fn() }))
vi.mock('../src/alerts/model', () => ({ announceRemoteFire: vi.fn(), notifyAlerts: h.notifyAlerts, onAlertFired: vi.fn() }))
vi.mock('../src/sync/bridge', () => ({ OWNED: [], applyInto: () => h.applied, captureInto: () => 0, fingerprint: () => ({}), corePrint: () => '', layoutsPrint: () => '', prefsPrint: () => '', mergeFirst: () => h.applied, restoreDrawings: () => h.applied }))
vi.mock('../src/sync/runtime', () => ({ transport: {}, createSyncRuntime: (a: { apply(s: unknown): unknown }) => { h.adapter = a; return { changed: vi.fn(), boot: vi.fn(), pushSoon: vi.fn() } } }))

describe('同步装回自选侧栏（B19）', () => {
  beforeEach(() => { h.renderPanel.mockClear(); h.notifyAlerts.mockClear() })
  it('一轮里自选和提醒都变了：提醒刷新，自选侧栏也重画', async () => {
    const { initSync } = await import('../src/sync/glue')
    initSync()
    h.applied = { settings: [], drawings: new Set(), alerts: true, favorites: true, fired: [] }
    h.adapter!.apply({})
    expect(h.notifyAlerts).toHaveBeenCalled()
    expect(h.renderPanel).toHaveBeenCalled()
  })
})
