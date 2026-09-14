package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class X extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        SkdjRemote skdj = chartIndicatorSetting.getSkdj();
        if (skdj == null) {
            return;
        }
        SkdjRemote.Output app_output = skdj.getApp_output();
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
        }
        if (KLineManager.f142490O.a().H()) {
            SkdjRemote.Input input = skdj.getInput();
            if (input != null) {
                ek.v.m(this, 0, input.getCc());
                ek.v.m(this, 1, input.getMac1());
                ek.v.m(this, 2, input.getMac2());
            }
            SkdjRemote.Output output = skdj.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getKDisabled());
                ek.v.l(this, 1, output.getDDisabled());
                return;
            }
            return;
        }
        SkdjRemote.Input app_input = skdj.getApp_input();
        if (app_input != null) {
            ek.v.m(this, 0, app_input.getCc());
            ek.v.m(this, 1, app_input.getMac1());
            ek.v.m(this, 2, app_input.getMac2());
        }
        SkdjRemote.Output app_output2 = skdj.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getKDisabled());
            ek.v.l(this, 1, app_output2.getDDisabled());
        }
        SkdjRemote.Input input2 = skdj.getInput();
        if (input2 != null) {
            ek.v.p(this, 0, input2.getCc());
            ek.v.p(this, 1, input2.getMac1());
            ek.v.p(this, 2, input2.getMac2());
        }
        SkdjRemote.Output output2 = skdj.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getKDisabled());
            ek.v.o(this, 1, output2.getDDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        SkdjRemote.Input input = new SkdjRemote.Input(Integer.valueOf(ek.v.i(this, 0, zH)), Integer.valueOf(ek.v.i(this, 1, zH)), Integer.valueOf(ek.v.i(this, 2, zH)));
        SkdjRemote.Output output = new SkdjRemote.Output(Boolean.valueOf(ek.v.j(this, 1, zH)), null, null, Boolean.valueOf(ek.v.j(this, 0, zH)), null, null, 54, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new SkdjRemote(input, output, new SkdjRemote.Output(Boolean.valueOf(ek.v.g(this, 1)), ek.v.q(k()[1].a()), Integer.valueOf((int) k()[1].b()), Boolean.valueOf(ek.v.g(this, 0)), strQ, Integer.valueOf(iB)), new SkdjRemote.Input(Integer.valueOf(ek.v.f(this, 0)), Integer.valueOf(ek.v.f(this, 1)), Integer.valueOf(ek.v.f(this, 2)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -268435457, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("skdj");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 18;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("K", -13643086, 0.0f, 4, null), new ek.m("D", -19456, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("N", new p292ng.g(1, 1000), 9, false, 0, 24, null), new ek.w("MID1", new p292ng.g(1, 1000), 3, false, 0, 24, null), new ek.w("MID2", new p292ng.g(1, 1000), 3, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("K", false, 2, null), new ek.I("D", false, 2, null)};
    }
}
