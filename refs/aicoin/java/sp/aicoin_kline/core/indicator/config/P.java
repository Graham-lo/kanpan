package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class P extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        ObvRemote obv = chartIndicatorSetting.getObv();
        if (obv == null) {
            return;
        }
        ObvRemote.Output app_output = obv.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getMaObvLineColor());
            Integer maObvLineWidth = app_output.getMaObvLineWidth();
            if (numR != null && maObvLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(maObvLineWidth.intValue());
            }
            Integer numR2 = ek.v.r(app_output.getObvLineColor());
            Integer obvLineWidth = app_output.getObvLineWidth();
            if (numR2 != null && obvLineWidth != null) {
                k()[1].d(numR2.intValue());
                k()[1].e(obvLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            ObvRemote.Input input = obv.getInput();
            if (input != null) {
                ek.v.m(this, 0, input.getMac());
            }
            ObvRemote.Output output = obv.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getObvDisabled());
                ek.v.l(this, 1, output.getMaObvDisabled());
                return;
            }
            return;
        }
        ObvRemote.Input app_input = obv.getApp_input();
        if (app_input != null) {
            ek.v.m(this, 0, app_input.getMac());
        }
        ObvRemote.Output app_output2 = obv.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getObvDisabled());
            ek.v.l(this, 1, app_output2.getMaObvDisabled());
        }
        ObvRemote.Input input2 = obv.getInput();
        if (input2 != null) {
            ek.v.p(this, 0, input2.getMac());
        }
        ObvRemote.Output output2 = obv.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getObvDisabled());
            ek.v.o(this, 1, output2.getMaObvDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        ObvRemote.Input input = new ObvRemote.Input(Integer.valueOf(ek.v.i(this, 0, zH)));
        ObvRemote.Output output = new ObvRemote.Output(Boolean.valueOf(ek.v.j(this, 1, zH)), null, null, Boolean.valueOf(ek.v.j(this, 0, zH)), null, null, 54, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new ObvRemote(input, output, new ObvRemote.Output(Boolean.valueOf(ek.v.g(this, 1)), strQ, Integer.valueOf(iB), Boolean.valueOf(ek.v.g(this, 0)), strQ2, Integer.valueOf(iB2)), new ObvRemote.Input(Integer.valueOf(ek.v.f(this, 0)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -65537, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        ObvRemote.Input input = new ObvRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)));
        ObvRemote.Output output = new ObvRemote.Output(Boolean.valueOf(ek.v.j(this, 1, z10)), null, null, Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, 54, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new ObvRemote(input, output, new ObvRemote.Output(Boolean.valueOf(ek.v.j(this, 1, z10)), strQ, Integer.valueOf(iB), Boolean.valueOf(ek.v.j(this, 0, z10)), strQ2, Integer.valueOf(iB2)), new ObvRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -65537, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("obv");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 5;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("OBV", -13643086, 0.0f, 4, null), new ek.m("MAOBV", -19456, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("N", new p292ng.g(0, 100), 30, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("OBV", false, 2, null), new ek.I("MAOBV", false, 2, null)};
    }
}
