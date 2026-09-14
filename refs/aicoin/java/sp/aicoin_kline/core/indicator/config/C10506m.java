package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: sp.aicoin_kline.core.indicator.config.m, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C10506m extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        BBIRemote bbi = chartIndicatorSetting.getBbi();
        if (bbi == null) {
            return;
        }
        BBIRemote.Output app_output = bbi.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getBbiLineColor());
            Integer bbiLineWidth = app_output.getBbiLineWidth();
            if (numR != null && bbiLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(bbiLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            BBIRemote.Input input = bbi.getInput();
            if (input != null) {
                ek.v.m(this, 0, input.getN1());
                ek.v.m(this, 1, input.getN2());
                ek.v.m(this, 2, input.getN3());
                ek.v.m(this, 3, input.getN4());
            }
            BBIRemote.Output output = bbi.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getBbiDisabled());
                return;
            }
            return;
        }
        BBIRemote.Input app_input = bbi.getApp_input();
        if (app_input != null) {
            ek.v.m(this, 0, app_input.getN1());
            ek.v.m(this, 1, app_input.getN2());
            ek.v.m(this, 2, app_input.getN3());
            ek.v.m(this, 3, app_input.getN4());
        }
        BBIRemote.Output app_output2 = bbi.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getBbiDisabled());
        }
        BBIRemote.Input input2 = bbi.getInput();
        if (input2 != null) {
            ek.v.p(this, 0, input2.getN1());
            ek.v.p(this, 1, input2.getN2());
            ek.v.p(this, 2, input2.getN3());
            ek.v.p(this, 3, input2.getN4());
        }
        BBIRemote.Output output2 = bbi.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getBbiDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, new BBIRemote(new BBIRemote.Input(Integer.valueOf(ek.v.i(this, 0, zH)), Integer.valueOf(ek.v.i(this, 1, zH)), Integer.valueOf(ek.v.i(this, 2, zH)), Integer.valueOf(ek.v.i(this, 3, zH))), new BBIRemote.Output(Boolean.valueOf(ek.v.j(this, 0, zH)), null, null, 6, null), new BBIRemote.Output(Boolean.valueOf(ek.v.g(this, 0)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b())), new BBIRemote.Input(Integer.valueOf(ek.v.f(this, 0)), Integer.valueOf(ek.v.f(this, 1)), Integer.valueOf(ek.v.f(this, 2)), Integer.valueOf(ek.v.f(this, 3)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1025, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, new BBIRemote(new BBIRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)), Integer.valueOf(ek.v.i(this, 1, z10)), Integer.valueOf(ek.v.i(this, 2, z10)), Integer.valueOf(ek.v.i(this, 3, z10))), new BBIRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, 6, null), new BBIRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b())), new BBIRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)), Integer.valueOf(ek.v.i(this, 1, z10)), Integer.valueOf(ek.v.i(this, 2, z10)), Integer.valueOf(ek.v.i(this, 3, z10)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1025, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("bbi");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 11;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return true;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("BBI", -13643086, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("MID1", new p292ng.g(0, 1000), 3, false, 0, 24, null), new ek.w("MID2", new p292ng.g(0, 1000), 6, false, 0, 24, null), new ek.w("MID3", new p292ng.g(0, 1000), 12, false, 0, 24, null), new ek.w("MID4", new p292ng.g(0, 1000), 24, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("BBI", false, 2, null)};
    }
}
