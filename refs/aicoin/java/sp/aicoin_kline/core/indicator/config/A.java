package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class A extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        FRRemote fr = chartIndicatorSetting.getFr();
        if (fr == null) {
            return;
        }
        FRRemote.Output app_output = fr.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getFrLineColor());
            Integer frLineWidth = app_output.getFrLineWidth();
            if (numR != null && frLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(frLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            FRRemote.Output output = fr.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getFrDisabled());
                return;
            }
            return;
        }
        FRRemote.Output app_output2 = fr.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getFrDisabled());
        }
        FRRemote.Output output2 = fr.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getFrDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new FRRemote(new FRRemote.Output(Boolean.valueOf(ek.v.j(this, 0, KLineManager.f142490O.a().H())), null, null, null, null, null, 62, null), new FRRemote.Output(Boolean.valueOf(ek.v.g(this, 0)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b()), null, null, null, 56, null)), null, null, null, -1, 31457279, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new FRRemote(new FRRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, null, null, null, 62, null), new FRRemote.Output(Boolean.valueOf(ek.v.g(this, 0)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b()), null, null, null, 56, null)), null, null, null, -1, 31457279, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("fr");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 43;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("FR", -13643086, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[0];
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("FR", false, 2, null)};
    }
}
