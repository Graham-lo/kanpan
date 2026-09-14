package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class H extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        KDJRemote kdj = chartIndicatorSetting.getKdj();
        if (kdj == null) {
            return;
        }
        KDJRemote.Output app_output = kdj.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getKLineColor());
            Integer kLineWidth = app_output.getKLineWidth();
            if (numR != null && kLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(kLineWidth.intValue());
            }
            Integer numR2 = ek.v.r(app_output.getDLineColor());
            Integer dLineWidth = app_output.getDLineWidth();
            if (numR2 != null && dLineWidth != null) {
                k()[1].d(numR2.intValue());
                k()[1].e(dLineWidth.intValue());
            }
            Integer numR3 = ek.v.r(app_output.getJLineColor());
            Integer jLineWidth = app_output.getJLineWidth();
            if (numR3 != null && jLineWidth != null) {
                k()[2].d(numR3.intValue());
                k()[2].e(jLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            KDJRemote.Input input = kdj.getInput();
            if (input != null) {
                ek.v.m(this, 0, input.getCc());
                ek.v.m(this, 1, input.getMac1());
                ek.v.m(this, 2, input.getMac2());
            }
            KDJRemote.Output output = kdj.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getKDisabled());
                ek.v.l(this, 1, output.getDDisabled());
                ek.v.l(this, 2, output.getJDisabled());
                return;
            }
            return;
        }
        KDJRemote.Input app_input = kdj.getApp_input();
        if (app_input != null) {
            ek.v.m(this, 0, app_input.getCc());
            ek.v.m(this, 1, app_input.getMac1());
            ek.v.m(this, 2, app_input.getMac2());
        }
        KDJRemote.Output app_output2 = kdj.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getKDisabled());
            ek.v.l(this, 1, app_output2.getDDisabled());
            ek.v.l(this, 2, app_output2.getJDisabled());
        }
        KDJRemote.Input input2 = kdj.getInput();
        if (input2 != null) {
            ek.v.p(this, 0, input2.getCc());
            ek.v.p(this, 1, input2.getMac1());
            ek.v.p(this, 2, input2.getMac2());
        }
        KDJRemote.Output output2 = kdj.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getKDisabled());
            ek.v.o(this, 1, output2.getDDisabled());
            ek.v.o(this, 2, output2.getJDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        KDJRemote.Input input = new KDJRemote.Input(Integer.valueOf(ek.v.i(this, 0, zH)), Integer.valueOf(ek.v.i(this, 1, zH)), Integer.valueOf(ek.v.i(this, 2, zH)));
        boolean zJ = ek.v.j(this, 0, zH);
        KDJRemote.Output output = new KDJRemote.Output(Boolean.valueOf(ek.v.j(this, 1, zH)), null, null, Boolean.valueOf(ek.v.j(this, 2, zH)), null, null, Boolean.valueOf(zJ), null, null, 438, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        String strQ3 = ek.v.q(k()[2].a());
        int iB3 = (int) k()[2].b();
        boolean zG = ek.v.g(this, 0);
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, new KDJRemote(input, output, new KDJRemote.Output(Boolean.valueOf(ek.v.g(this, 1)), strQ2, Integer.valueOf(iB2), Boolean.valueOf(ek.v.g(this, 2)), strQ3, Integer.valueOf(iB3), Boolean.valueOf(zG), strQ, Integer.valueOf(iB)), new KDJRemote.Input(Integer.valueOf(ek.v.f(this, 0)), Integer.valueOf(ek.v.f(this, 1)), Integer.valueOf(ek.v.f(this, 2)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -16385, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        KDJRemote.Input input = new KDJRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)), Integer.valueOf(ek.v.i(this, 1, z10)), Integer.valueOf(ek.v.i(this, 2, z10)));
        boolean zJ = ek.v.j(this, 0, z10);
        KDJRemote.Output output = new KDJRemote.Output(Boolean.valueOf(ek.v.j(this, 1, z10)), null, null, Boolean.valueOf(ek.v.j(this, 2, z10)), null, null, Boolean.valueOf(zJ), null, null, 438, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        String strQ3 = ek.v.q(k()[2].a());
        int iB3 = (int) k()[2].b();
        boolean zJ2 = ek.v.j(this, 0, z10);
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, new KDJRemote(input, output, new KDJRemote.Output(Boolean.valueOf(ek.v.j(this, 1, z10)), strQ2, Integer.valueOf(iB2), Boolean.valueOf(ek.v.j(this, 2, z10)), strQ3, Integer.valueOf(iB3), Boolean.valueOf(zJ2), strQ, Integer.valueOf(iB)), new KDJRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)), Integer.valueOf(ek.v.i(this, 1, z10)), Integer.valueOf(ek.v.i(this, 2, z10)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -16385, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("kdj");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 2;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("K", -13643086, 0.0f, 4, null), new ek.m("D", -19456, 0.0f, 4, null), new ek.m("J", -1553991, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("N", new p292ng.g(1, 90), 9, false, 0, 24, null), new ek.w("MID1", new p292ng.g(1, 30), 3, false, 0, 24, null), new ek.w("MID2", new p292ng.g(1, 30), 3, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("K", false, 2, null), new ek.I("D", false, 2, null), new ek.I("J", false, 2, null)};
    }
}
