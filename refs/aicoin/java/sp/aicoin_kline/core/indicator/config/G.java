package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class G extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        KCRemote kc2 = chartIndicatorSetting.getKc();
        if (kc2 == null) {
            return;
        }
        KCRemote.Output app_output = kc2.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getUpper_lineColor());
            Integer upper_lineWidth = app_output.getUpper_lineWidth();
            if (numR != null && upper_lineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(upper_lineWidth.intValue());
            }
            Integer numR2 = ek.v.r(app_output.getMid_lineColor());
            Integer mid_lineWidth = app_output.getMid_lineWidth();
            if (numR2 != null && mid_lineWidth != null) {
                k()[1].d(numR2.intValue());
                k()[1].e(mid_lineWidth.intValue());
            }
            Integer numR3 = ek.v.r(app_output.getLower_lineColor());
            Integer lower_lineWidth = app_output.getLower_lineWidth();
            if (numR3 != null && lower_lineWidth != null) {
                k()[2].d(numR3.intValue());
                k()[2].e(lower_lineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            KCRemote.Input input = kc2.getInput();
            if (input != null) {
                ek.v.m(this, 0, input.getCc());
                ek.v.m(this, 1, input.getFactor());
            }
            KCRemote.Output output = kc2.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getUpperDisabled());
                ek.v.l(this, 1, output.getMidDisabled());
                ek.v.l(this, 2, output.getLowerDisabled());
                return;
            }
            return;
        }
        KCRemote.Input app_input = kc2.getApp_input();
        if (app_input != null) {
            ek.v.m(this, 0, app_input.getCc());
            ek.v.m(this, 1, app_input.getFactor());
        }
        KCRemote.Output app_output2 = kc2.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getUpperDisabled());
            ek.v.l(this, 1, app_output2.getMidDisabled());
            ek.v.l(this, 2, app_output2.getLowerDisabled());
        }
        KCRemote.Input input2 = kc2.getInput();
        if (input2 != null) {
            ek.v.p(this, 0, input2.getCc());
            ek.v.p(this, 1, input2.getFactor());
        }
        KCRemote.Output output2 = kc2.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getUpperDisabled());
            ek.v.o(this, 1, output2.getMidDisabled());
            ek.v.o(this, 2, output2.getLowerDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        KCRemote.Input input = new KCRemote.Input(Integer.valueOf(ek.v.i(this, 0, zH)), Integer.valueOf(ek.v.i(this, 1, zH)));
        boolean zJ = ek.v.j(this, 0, zH);
        KCRemote.Output output = new KCRemote.Output(Boolean.valueOf(ek.v.j(this, 2, zH)), null, null, null, null, Boolean.valueOf(ek.v.j(this, 1, zH)), Boolean.valueOf(zJ), null, null, 414, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        String strQ3 = ek.v.q(k()[2].a());
        int iB3 = (int) k()[2].b();
        boolean zG = ek.v.g(this, 0);
        return new ChartIndicatorSetting(null, null, null, null, null, new KCRemote(input, output, new KCRemote.Output(Boolean.valueOf(ek.v.g(this, 2)), Integer.valueOf(iB3), strQ3, Integer.valueOf(iB2), strQ2, Boolean.valueOf(ek.v.g(this, 1)), Boolean.valueOf(zG), Integer.valueOf(iB), strQ), new KCRemote.Input(Integer.valueOf(ek.v.f(this, 0)), Integer.valueOf(ek.v.f(this, 1)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -33, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        KCRemote.Input input = new KCRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)), Integer.valueOf(ek.v.i(this, 1, z10)));
        boolean zJ = ek.v.j(this, 0, z10);
        KCRemote.Output output = new KCRemote.Output(Boolean.valueOf(ek.v.j(this, 2, z10)), null, null, null, null, Boolean.valueOf(ek.v.j(this, 1, z10)), Boolean.valueOf(zJ), null, null, 414, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        String strQ3 = ek.v.q(k()[2].a());
        int iB3 = (int) k()[2].b();
        boolean zJ2 = ek.v.j(this, 0, z10);
        return new ChartIndicatorSetting(null, null, null, null, null, new KCRemote(input, output, new KCRemote.Output(Boolean.valueOf(ek.v.j(this, 2, z10)), Integer.valueOf(iB3), strQ3, Integer.valueOf(iB2), strQ2, Boolean.valueOf(ek.v.j(this, 1, z10)), Boolean.valueOf(zJ2), Integer.valueOf(iB), strQ), new KCRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)), Integer.valueOf(ek.v.i(this, 1, z10)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -33, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("kc");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 9;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return true;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("UPPER", -13643086, 0.0f, 4, null), new ek.m("MID", -19456, 0.0f, 4, null), new ek.m("LOWER", -1553991, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("N", new p292ng.g(0, 1000), 20, false, 0, 24, null), new ek.w("Factor", new p292ng.g(0, 100), 1, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("UPPER", false, 2, null), new ek.I("MID", false, 2, null), new ek.I("LOWER", false, 2, null)};
    }
}
