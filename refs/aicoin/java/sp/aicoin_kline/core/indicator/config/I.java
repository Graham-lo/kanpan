package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class I extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        LSURRemote lsur = chartIndicatorSetting.getLsur();
        if (lsur == null) {
            return;
        }
        LSURRemote.Output app_output = lsur.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getLsurLineColor());
            Integer lsurLineWidth = app_output.getLsurLineWidth();
            if (numR != null && lsurLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(lsurLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            LSURRemote.Output output = lsur.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getLsurDisabled());
                return;
            }
            return;
        }
        LSURRemote.Output app_output2 = lsur.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getLsurDisabled());
        }
        LSURRemote.Output output2 = lsur.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getLsurDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new LSURRemote(new LSURRemote.Output(Boolean.valueOf(ek.v.j(this, 0, KLineManager.f142490O.a().H())), null, null, 6, null), new LSURRemote.Output(Boolean.valueOf(ek.v.g(this, 0)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b()))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1, 33553919, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new LSURRemote(new LSURRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, 6, null), new LSURRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b()))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1, 33553919, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("lsur");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 31;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("L/S", -13643086, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[0];
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("L/S", false, 2, null)};
    }
}
