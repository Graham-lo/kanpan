package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: sp.aicoin_kline.core.indicator.config.l, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C10505l extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        BasisRemote basis = chartIndicatorSetting.getBasis();
        if (basis == null) {
            return;
        }
        BasisRemote.Output app_output = basis.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getBasisLineColor());
            Integer basisLineWidth = app_output.getBasisLineWidth();
            if (numR != null && basisLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(basisLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            BasisRemote.Output output = basis.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getBasisDisabled());
                return;
            }
            return;
        }
        BasisRemote.Output app_output2 = basis.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getBasisDisabled());
        }
        BasisRemote.Output output2 = basis.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getBasisDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new BasisRemote(new BasisRemote.Output(Boolean.valueOf(ek.v.j(this, 0, KLineManager.f142490O.a().H())), null, null, null, null, null, 62, null), new BasisRemote.Output(Boolean.valueOf(ek.v.g(this, 0)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b()), null, null, null, 56, null)), null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1, 33553407, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new BasisRemote(new BasisRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, null, null, null, 62, null), new BasisRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b()), null, null, null, 56, null)), null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1, 33553407, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("basis");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 32;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("BASIS", -13643086, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[0];
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("BASIS", false, 2, null)};
    }
}
