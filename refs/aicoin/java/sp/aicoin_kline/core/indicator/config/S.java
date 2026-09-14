package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class S extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        PositionRemote position = chartIndicatorSetting.getPosition();
        if (position == null) {
            return;
        }
        PositionRemote.Output app_output = position.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getPositionLineColor());
            Integer positionLineWidth = app_output.getPositionLineWidth();
            if (numR != null && positionLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(positionLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            PositionRemote.Output output = position.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getPositionDisabled());
                return;
            }
            return;
        }
        PositionRemote.Output app_output2 = position.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getPositionDisabled());
        }
        PositionRemote.Output output2 = position.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getPositionDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new PositionRemote(new PositionRemote.Output(Boolean.valueOf(ek.v.j(this, 0, KLineManager.f142490O.a().H())), null, null, 6, null), new PositionRemote.Output(Boolean.valueOf(ek.v.g(this, 0)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b()))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1, 33554429, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new PositionRemote(new PositionRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, 6, null), new PositionRemote.Output(Boolean.valueOf(ek.v.g(this, 0)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b()))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1, 33554429, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("position");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 22;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("OI", -13643086, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[0];
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("OI", false, 2, null)};
    }
}
