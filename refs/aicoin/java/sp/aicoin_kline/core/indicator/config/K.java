package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class K extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        MLRRemote mlr = chartIndicatorSetting.getMlr();
        if (mlr == null) {
            return;
        }
        MLRRemote.Output app_output = mlr.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getMlrLineColor());
            Integer mlrLineWidth = app_output.getMlrLineWidth();
            if (numR != null && mlrLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(mlrLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            MLRRemote.Output output = mlr.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getMlrDisabled());
                return;
            }
            return;
        }
        MLRRemote.Output app_output2 = mlr.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getMlrDisabled());
        }
        MLRRemote.Output output2 = mlr.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getMlrDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new MLRRemote(new MLRRemote.Output(Boolean.valueOf(ek.v.j(this, 0, KLineManager.f142490O.a().H())), null, null, 6, null), new MLRRemote.Output(Boolean.valueOf(ek.v.g(this, 0)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b()))), null, null, null, null, null, null, null, null, null, null, null, -1, 33546239, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new MLRRemote(new MLRRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, 6, null), new MLRRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b()))), null, null, null, null, null, null, null, null, null, null, null, -1, 33546239, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("mlr");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 35;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("MLR", -13643086, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[0];
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("MLR", false, 2, null)};
    }
}
