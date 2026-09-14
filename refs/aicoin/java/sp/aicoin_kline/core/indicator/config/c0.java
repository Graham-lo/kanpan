package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class c0 extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        TTSIRemote ttsi = chartIndicatorSetting.getTtsi();
        if (ttsi == null) {
            return;
        }
        TTSIRemote.Output app_output = ttsi.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getLongLineColor());
            Integer longLineWidth = app_output.getLongLineWidth();
            if (numR != null && longLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(longLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            TTSIRemote.Output output = ttsi.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getLongDisabled());
                return;
            }
            return;
        }
        TTSIRemote.Output app_output2 = ttsi.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getLongDisabled());
        }
        TTSIRemote.Output output2 = ttsi.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getLongDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new TTSIRemote(new TTSIRemote.Output(Boolean.valueOf(ek.v.j(this, 0, KLineManager.f142490O.a().H())), null, null, 6, null), new TTSIRemote.Output(Boolean.valueOf(ek.v.g(this, 0)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b()))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1, 33554427, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new TTSIRemote(new TTSIRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, 6, null), new TTSIRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b()))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1, 33554427, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("ttsi");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 23;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("Long", -13643086, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[0];
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("Long", false, 2, null)};
    }
}
