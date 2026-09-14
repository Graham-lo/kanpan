package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class M extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        MACDRemote macd = chartIndicatorSetting.getMacd();
        if (macd == null) {
            return;
        }
        MACDRemote.Output app_output = macd.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getDifLineColor());
            Integer difLineWidth = app_output.getDifLineWidth();
            if (numR != null && difLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(difLineWidth.intValue());
            }
            Integer numR2 = ek.v.r(app_output.getDeaLineColor());
            Integer deaLineWidth = app_output.getDeaLineWidth();
            if (numR2 != null && deaLineWidth != null) {
                k()[1].d(numR2.intValue());
                k()[1].e(deaLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            MACDRemote.Input input = macd.getInput();
            if (input != null) {
                ek.v.m(this, 0, input.getSc());
                ek.v.m(this, 1, input.getLc());
                ek.v.m(this, 2, input.getMac());
            }
            MACDRemote.Output output = macd.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getDifDisabled());
                ek.v.l(this, 1, output.getDeaDisabled());
                ek.v.l(this, 2, output.getMacdDisabled());
                return;
            }
            return;
        }
        MACDRemote.Input app_input = macd.getApp_input();
        if (app_input != null) {
            ek.v.m(this, 0, app_input.getSc());
            ek.v.m(this, 1, app_input.getLc());
            ek.v.m(this, 2, app_input.getMac());
        }
        MACDRemote.Output app_output2 = macd.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getDifDisabled());
            ek.v.l(this, 1, app_output2.getDeaDisabled());
            ek.v.l(this, 2, app_output2.getMacdDisabled());
        }
        MACDRemote.Input input2 = macd.getInput();
        if (input2 != null) {
            ek.v.p(this, 0, input2.getSc());
            ek.v.p(this, 1, input2.getLc());
            ek.v.p(this, 2, input2.getMac());
        }
        MACDRemote.Output output2 = macd.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getDifDisabled());
            ek.v.o(this, 1, output2.getDeaDisabled());
            ek.v.o(this, 2, output2.getMacdDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        int i10 = ek.v.i(this, 0, zH);
        MACDRemote.Input input = new MACDRemote.Input(Integer.valueOf(ek.v.i(this, 1, zH)), Integer.valueOf(ek.v.i(this, 2, zH)), Integer.valueOf(i10));
        boolean zJ = ek.v.j(this, 0, zH);
        MACDRemote.Output output = new MACDRemote.Output(Boolean.valueOf(ek.v.j(this, 1, zH)), null, null, Boolean.valueOf(zJ), null, null, Boolean.valueOf(ek.v.j(this, 2, zH)), null, null, null, null, null, null, null, null, 32694, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        boolean zG = ek.v.g(this, 0);
        MACDRemote.Output output2 = new MACDRemote.Output(Boolean.valueOf(ek.v.g(this, 1)), strQ2, Integer.valueOf(iB2), Boolean.valueOf(zG), strQ, Integer.valueOf(iB), Boolean.valueOf(ek.v.g(this, 2)), null, null, null, null, null, null, null, null, 32640, null);
        int iF = ek.v.f(this, 0);
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, new MACDRemote(input, output, output2, new MACDRemote.Input(Integer.valueOf(ek.v.f(this, 1)), Integer.valueOf(ek.v.f(this, 2)), Integer.valueOf(iF))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -8193, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        int i10 = ek.v.i(this, 0, z10);
        MACDRemote.Input input = new MACDRemote.Input(Integer.valueOf(ek.v.i(this, 1, z10)), Integer.valueOf(ek.v.i(this, 2, z10)), Integer.valueOf(i10));
        boolean zJ = ek.v.j(this, 0, z10);
        MACDRemote.Output output = new MACDRemote.Output(Boolean.valueOf(ek.v.j(this, 1, z10)), null, null, Boolean.valueOf(zJ), null, null, Boolean.valueOf(ek.v.j(this, 2, z10)), null, null, null, null, null, null, null, null, 32694, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        boolean zJ2 = ek.v.j(this, 0, z10);
        MACDRemote.Output output2 = new MACDRemote.Output(Boolean.valueOf(ek.v.j(this, 1, z10)), strQ2, Integer.valueOf(iB2), Boolean.valueOf(zJ2), strQ, Integer.valueOf(iB), Boolean.valueOf(ek.v.j(this, 2, z10)), null, null, null, null, null, null, null, null, 32640, null);
        int i11 = ek.v.i(this, 0, z10);
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, new MACDRemote(input, output, output2, new MACDRemote.Input(Integer.valueOf(ek.v.i(this, 1, z10)), Integer.valueOf(ek.v.i(this, 2, z10)), Integer.valueOf(i11))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -8193, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("macd");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 1;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("DIF", -13643086, 0.0f, 4, null), new ek.m("DEA", -19456, 0.0f, 4, null), new ek.m("MACD", -1553991, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("SHORT", new p292ng.g(0, 200), 12, false, 0, 24, null), new ek.w("LONG", new p292ng.g(0, 200), 26, false, 0, 24, null), new ek.w("MA", new p292ng.g(0, 200), 9, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("DIF", false, 2, null), new ek.I("DEA", false, 2, null), new ek.I("MACD", false, 2, null)};
    }
}
