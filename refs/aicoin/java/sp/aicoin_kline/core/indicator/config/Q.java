package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class Q extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        PFRRemote pfr = chartIndicatorSetting.getPfr();
        if (pfr == null) {
            return;
        }
        PFRRemote.Output app_output = pfr.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getLineLineColor());
            Integer lineLineWidth = app_output.getLineLineWidth();
            if (numR != null && lineLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(lineLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            PFRRemote.Output output = pfr.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getLineDisabled());
                return;
            }
            return;
        }
        PFRRemote.Output app_output2 = pfr.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getLineDisabled());
        }
        PFRRemote.Output output2 = pfr.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getLineDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new PFRRemote(new PFRRemote.Output(Boolean.valueOf(ek.v.j(this, 0, KLineManager.f142490O.a().H())), null, null, null, null, null, 62, null), new PFRRemote.Output(Boolean.valueOf(ek.v.g(this, 0)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b()), null, null, null, 56, null)), null, null, -1, 29360127, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new PFRRemote(new PFRRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, null, null, null, 62, null), new PFRRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b()), null, null, null, 56, null)), null, null, -1, 29360127, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("pfr");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 44;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("PFR", -13643086, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[0];
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("PFR", false, 2, null)};
    }
}
