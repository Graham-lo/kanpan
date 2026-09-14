package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: sp.aicoin_kline.core.indicator.config.i, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C10502i extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        AORemote ao = chartIndicatorSetting.getAo();
        if (ao == null) {
            return;
        }
        if (KLineManager.f142490O.a().H()) {
            AORemote.Output output = ao.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getAoDisabled());
                return;
            }
            return;
        }
        AORemote.Output app_output = ao.getApp_output();
        if (app_output != null) {
            ek.v.l(this, 0, app_output.getAoDisabled());
        }
        AORemote.Output output2 = ao.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getAoDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new AORemote(new AORemote.Output(Boolean.valueOf(ek.v.j(this, 0, KLineManager.f142490O.a().H())), null, null, null, null, 30, null), new AORemote.Output(Boolean.valueOf(ek.v.g(this, 0)), null, null, null, null, 30, null)), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1, 33554175, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new AORemote(new AORemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, null, null, 30, null), new AORemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, null, null, 30, null)), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1, 33554175, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("ao");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 30;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("AO", -13643086, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[0];
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("AO", false, 2, null)};
    }
}
