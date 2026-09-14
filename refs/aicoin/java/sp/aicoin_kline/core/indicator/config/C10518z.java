package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: sp.aicoin_kline.core.indicator.config.z, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C10518z extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        ENERemote ene = chartIndicatorSetting.getEne();
        if (ene == null) {
            return;
        }
        ENERemote.Output app_output = ene.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getMidLineColor());
            Integer midLineWidth = app_output.getMidLineWidth();
            if (numR != null && midLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(midLineWidth.intValue());
            }
            Integer numR2 = ek.v.r(app_output.getUpperLineColor());
            Integer upperLineWidth = app_output.getUpperLineWidth();
            if (numR2 != null && upperLineWidth != null) {
                k()[1].d(numR2.intValue());
                k()[1].e(upperLineWidth.intValue());
            }
            Integer numR3 = ek.v.r(app_output.getLowerLineColor());
            Integer lowerLineWidth = app_output.getLowerLineWidth();
            if (numR3 != null && lowerLineWidth != null) {
                k()[2].d(numR3.intValue());
                k()[2].e(lowerLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            ENERemote.Input input = ene.getInput();
            if (input != null) {
                ek.v.m(this, 0, input.getCc1());
                ek.v.m(this, 1, input.getCc2());
                ek.v.m(this, 2, input.getCc3());
            }
            ENERemote.Output output = ene.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getMidDisabled());
                ek.v.l(this, 1, output.getUpperDisabled());
                ek.v.l(this, 2, output.getLowerDisabled());
                return;
            }
            return;
        }
        ENERemote.Input app_input = ene.getApp_input();
        if (app_input != null) {
            ek.v.m(this, 0, app_input.getCc1());
            ek.v.m(this, 1, app_input.getCc2());
            ek.v.m(this, 2, app_input.getCc3());
        }
        ENERemote.Output app_output2 = ene.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getMidDisabled());
            ek.v.l(this, 1, app_output2.getUpperDisabled());
            ek.v.l(this, 2, app_output2.getLowerDisabled());
        }
        ENERemote.Input input2 = ene.getInput();
        if (input2 != null) {
            ek.v.p(this, 0, input2.getCc1());
            ek.v.p(this, 1, input2.getCc2());
            ek.v.p(this, 2, input2.getCc3());
        }
        ENERemote.Output output2 = ene.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getMidDisabled());
            ek.v.o(this, 1, output2.getUpperDisabled());
            ek.v.o(this, 2, output2.getLowerDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        ENERemote.Input input = new ENERemote.Input(Integer.valueOf(ek.v.i(this, 0, zH)), Integer.valueOf(ek.v.i(this, 1, zH)), Integer.valueOf(ek.v.i(this, 2, zH)));
        ENERemote.Output output = new ENERemote.Output(Boolean.valueOf(ek.v.j(this, 0, zH)), null, null, Boolean.valueOf(ek.v.j(this, 1, zH)), null, null, Boolean.valueOf(ek.v.j(this, 2, zH)), null, null, 438, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        String strQ3 = ek.v.q(k()[2].a());
        int iB3 = (int) k()[2].b();
        return new ChartIndicatorSetting(null, null, null, new ENERemote(input, output, new ENERemote.Output(Boolean.valueOf(ek.v.g(this, 0)), Integer.valueOf(iB), strQ, Boolean.valueOf(ek.v.g(this, 1)), Integer.valueOf(iB2), strQ2, Boolean.valueOf(ek.v.g(this, 2)), Integer.valueOf(iB3), strQ3), new ENERemote.Input(Integer.valueOf(ek.v.f(this, 0)), Integer.valueOf(ek.v.f(this, 1)), Integer.valueOf(ek.v.f(this, 2)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -9, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        ENERemote.Input input = new ENERemote.Input(Integer.valueOf(ek.v.b(this, 0, z10)), Integer.valueOf(ek.v.b(this, 1, z10)), Integer.valueOf(ek.v.b(this, 2, z10)));
        ENERemote.Output output = new ENERemote.Output(Boolean.valueOf(ek.v.c(this, 0, z10)), null, null, Boolean.valueOf(ek.v.c(this, 1, z10)), null, null, Boolean.valueOf(ek.v.c(this, 2, z10)), null, null, 438, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        String strQ3 = ek.v.q(k()[2].a());
        int iB3 = (int) k()[2].b();
        return new ChartIndicatorSetting(null, null, null, new ENERemote(input, output, new ENERemote.Output(Boolean.valueOf(ek.v.c(this, 0, z10)), Integer.valueOf(iB), strQ, Boolean.valueOf(ek.v.c(this, 1, z10)), Integer.valueOf(iB2), strQ2, Boolean.valueOf(ek.v.c(this, 2, z10)), Integer.valueOf(iB3), strQ3), new ENERemote.Input(Integer.valueOf(ek.v.b(this, 0, z10)), Integer.valueOf(ek.v.b(this, 1, z10)), Integer.valueOf(ek.v.b(this, 2, z10)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -9, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("ene");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 5;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return true;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("MID", -13643086, 0.0f, 4, null), new ek.m("UP", -19456, 0.0f, 4, null), new ek.m("LOW", -1553991, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("N", new p292ng.g(0, 1000), 10, false, 0, 24, null), new ek.w("M1", new p292ng.g(0, 1000), 11, false, 0, 24, null), new ek.w("M2", new p292ng.g(0, 1000), 9, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("MID", false, 2, null), new ek.I("UP", false, 2, null), new ek.I("LOW", false, 2, null)};
    }
}
