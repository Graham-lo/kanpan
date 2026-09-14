package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class Z extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        StochRSIRemote stochrsi = chartIndicatorSetting.getStochrsi();
        if (stochrsi == null) {
            return;
        }
        StochRSIRemote.Output app_output = stochrsi.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getStochRsiLineColor());
            Integer stochRsiLineWidth = app_output.getStochRsiLineWidth();
            if (numR != null && stochRsiLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(stochRsiLineWidth.intValue());
            }
            Integer numR2 = ek.v.r(app_output.getMaStochRsiLineColor());
            Integer maStochRsiLineWidth = app_output.getMaStochRsiLineWidth();
            if (numR2 != null && maStochRsiLineWidth != null) {
                k()[1].d(numR2.intValue());
                k()[1].e(maStochRsiLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            StochRSIRemote.Input input = stochrsi.getInput();
            if (input != null) {
                ek.v.m(this, 0, input.getRsiLength());
                ek.v.m(this, 1, input.getStochLength());
                ek.v.m(this, 2, input.getK());
                ek.v.m(this, 3, input.getD());
                ek.v.m(this, 4, input.getUpperBand());
                ek.v.m(this, 5, input.getLowerBand());
            }
            StochRSIRemote.Output output = stochrsi.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getStochRsiDisabled());
                ek.v.l(this, 1, output.getMaStochRsiDisabled());
                return;
            }
            return;
        }
        StochRSIRemote.Input app_input = stochrsi.getApp_input();
        if (app_input != null) {
            ek.v.m(this, 0, app_input.getRsiLength());
            ek.v.m(this, 1, app_input.getStochLength());
            ek.v.m(this, 2, app_input.getK());
            ek.v.m(this, 3, app_input.getD());
            ek.v.m(this, 4, app_input.getUpperBand());
            ek.v.m(this, 5, app_input.getLowerBand());
        }
        StochRSIRemote.Output app_output2 = stochrsi.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getStochRsiDisabled());
            ek.v.l(this, 1, app_output2.getMaStochRsiDisabled());
        }
        StochRSIRemote.Input input2 = stochrsi.getInput();
        if (input2 != null) {
            ek.v.p(this, 0, input2.getRsiLength());
            ek.v.p(this, 1, input2.getStochLength());
            ek.v.p(this, 2, input2.getK());
            ek.v.p(this, 3, input2.getD());
            ek.v.p(this, 4, input2.getUpperBand());
            ek.v.p(this, 5, input2.getLowerBand());
        }
        StochRSIRemote.Output output2 = stochrsi.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getStochRsiDisabled());
            ek.v.o(this, 1, output2.getMaStochRsiDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        int i10 = ek.v.i(this, 0, zH);
        int i11 = ek.v.i(this, 1, zH);
        int i12 = ek.v.i(this, 2, zH);
        int i13 = ek.v.i(this, 3, zH);
        int i14 = ek.v.i(this, 4, zH);
        StochRSIRemote.Input input = new StochRSIRemote.Input(Integer.valueOf(i13), Integer.valueOf(i12), Integer.valueOf(ek.v.i(this, 5, zH)), Integer.valueOf(i10), Integer.valueOf(i11), Integer.valueOf(i14));
        StochRSIRemote.Output output = new StochRSIRemote.Output(null, null, null, null, null, Boolean.valueOf(ek.v.j(this, 1, zH)), null, null, Boolean.valueOf(ek.v.j(this, 0, zH)), null, null, null, null, null, 16095, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        StochRSIRemote.Output output2 = new StochRSIRemote.Output(null, null, null, null, null, Boolean.valueOf(ek.v.g(this, 1)), ek.v.q(k()[1].a()), Integer.valueOf((int) k()[1].b()), Boolean.valueOf(ek.v.g(this, 0)), strQ, Integer.valueOf(iB), null, null, null, 14367, null);
        int iF = ek.v.f(this, 0);
        int iF2 = ek.v.f(this, 1);
        int iF3 = ek.v.f(this, 2);
        int iF4 = ek.v.f(this, 3);
        int iF5 = ek.v.f(this, 4);
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new StochRSIRemote(input, output, output2, new StochRSIRemote.Input(Integer.valueOf(iF4), Integer.valueOf(iF3), Integer.valueOf(ek.v.f(this, 5)), Integer.valueOf(iF), Integer.valueOf(iF2), Integer.valueOf(iF5))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -131073, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        int i10 = ek.v.i(this, 0, z10);
        int i11 = ek.v.i(this, 1, z10);
        int i12 = ek.v.i(this, 2, z10);
        int i13 = ek.v.i(this, 3, z10);
        int i14 = ek.v.i(this, 4, z10);
        StochRSIRemote.Input input = new StochRSIRemote.Input(Integer.valueOf(i13), Integer.valueOf(i12), Integer.valueOf(ek.v.i(this, 5, z10)), Integer.valueOf(i10), Integer.valueOf(i11), Integer.valueOf(i14));
        StochRSIRemote.Output output = new StochRSIRemote.Output(null, null, null, null, null, Boolean.valueOf(ek.v.j(this, 1, z10)), null, null, Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, null, null, null, 16095, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        StochRSIRemote.Output output2 = new StochRSIRemote.Output(null, null, null, null, null, Boolean.valueOf(ek.v.j(this, 1, z10)), ek.v.q(k()[1].a()), Integer.valueOf((int) k()[1].b()), Boolean.valueOf(ek.v.j(this, 0, z10)), strQ, Integer.valueOf(iB), null, null, null, 14367, null);
        int i15 = ek.v.i(this, 0, z10);
        int i16 = ek.v.i(this, 1, z10);
        int i17 = ek.v.i(this, 2, z10);
        int i18 = ek.v.i(this, 3, z10);
        int i19 = ek.v.i(this, 4, z10);
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new StochRSIRemote(input, output, output2, new StochRSIRemote.Input(Integer.valueOf(i18), Integer.valueOf(i17), Integer.valueOf(ek.v.i(this, 5, z10)), Integer.valueOf(i15), Integer.valueOf(i16), Integer.valueOf(i19))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -131073, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("stochrsi");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 4;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("StochRSI", -13643086, 0.0f, 4, null), new ek.m("MAStochRSI", -19456, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("RSI_P", new p292ng.g(0, 100), 14, false, 0, 24, null), new ek.w("RD_P", new p292ng.g(0, 100), 14, false, 0, 24, null), new ek.w("K", new p292ng.g(0, 50), 3, false, 0, 24, null), new ek.w("D", new p292ng.g(0, 50), 3, false, 0, 24, null), new ek.w("CEILING", new p292ng.g(0, 100), 80, false, 0, 16, null), new ek.w("FLOOR", new p292ng.g(0, 100), 20, false, 0, 16, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("StochRSI", false, 2, null), new ek.I("MAStochRSI", false, 2, null)};
    }
}
