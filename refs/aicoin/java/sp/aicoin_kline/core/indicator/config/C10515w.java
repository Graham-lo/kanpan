package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: sp.aicoin_kline.core.indicator.config.w, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C10515w extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        DmiRemote dmi = chartIndicatorSetting.getDmi();
        if (dmi == null) {
            return;
        }
        DmiRemote.Output app_output = dmi.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getPdiLineColor());
            Integer pdiLineWidth = app_output.getPdiLineWidth();
            if (numR != null && pdiLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(pdiLineWidth.intValue());
            }
            Integer numR2 = ek.v.r(app_output.getMdiLineColor());
            Integer mdiLineWidth = app_output.getMdiLineWidth();
            if (numR2 != null && mdiLineWidth != null) {
                k()[1].d(numR2.intValue());
                k()[1].e(mdiLineWidth.intValue());
            }
            Integer numR3 = ek.v.r(app_output.getAdxLineColor());
            Integer adxLineWidth = app_output.getAdxLineWidth();
            if (numR3 != null && adxLineWidth != null) {
                k()[2].d(numR3.intValue());
                k()[2].e(adxLineWidth.intValue());
            }
            Integer numR4 = ek.v.r(app_output.getAdxrLineColor());
            Integer adxrLineWidth = app_output.getAdxrLineWidth();
            if (numR4 != null && adxrLineWidth != null) {
                k()[3].d(numR4.intValue());
                k()[3].e(adxrLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            DmiRemote.Input input = dmi.getInput();
            if (input != null) {
                ek.v.m(this, 0, input.getMac1());
                ek.v.m(this, 1, input.getMac2());
            }
            DmiRemote.Output output = dmi.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getPdiDisabled());
                ek.v.l(this, 1, output.getMdiDisabled());
                ek.v.l(this, 2, output.getAdxDisabled());
                ek.v.l(this, 3, output.getAdxrDisabled());
                return;
            }
            return;
        }
        DmiRemote.Input app_input = dmi.getApp_input();
        if (app_input != null) {
            ek.v.m(this, 0, app_input.getMac1());
            ek.v.m(this, 1, app_input.getMac2());
        }
        DmiRemote.Output app_output2 = dmi.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getPdiDisabled());
            ek.v.l(this, 1, app_output2.getMdiDisabled());
            ek.v.l(this, 2, app_output2.getAdxDisabled());
            ek.v.l(this, 3, app_output2.getAdxrDisabled());
        }
        DmiRemote.Input input2 = dmi.getInput();
        if (input2 != null) {
            ek.v.p(this, 0, input2.getMac1());
            ek.v.p(this, 1, input2.getMac2());
        }
        DmiRemote.Output output2 = dmi.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getPdiDisabled());
            ek.v.o(this, 1, output2.getMdiDisabled());
            ek.v.o(this, 2, output2.getAdxDisabled());
            ek.v.o(this, 3, output2.getAdxrDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        DmiRemote.Input input = new DmiRemote.Input(Integer.valueOf(ek.v.i(this, 0, zH)), Integer.valueOf(ek.v.i(this, 1, zH)));
        boolean zJ = ek.v.j(this, 0, zH);
        boolean zJ2 = ek.v.j(this, 1, zH);
        DmiRemote.Output output = new DmiRemote.Output(Boolean.valueOf(ek.v.j(this, 2, zH)), null, null, Boolean.valueOf(ek.v.j(this, 3, zH)), null, null, Boolean.valueOf(zJ2), null, null, Boolean.valueOf(zJ), null, null, 3510, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        String strQ3 = ek.v.q(k()[2].a());
        int iB3 = (int) k()[2].b();
        String strQ4 = ek.v.q(k()[3].a());
        int iB4 = (int) k()[3].b();
        boolean zG = ek.v.g(this, 0);
        boolean zG2 = ek.v.g(this, 1);
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new DmiRemote(input, output, new DmiRemote.Output(Boolean.valueOf(ek.v.g(this, 2)), strQ3, Integer.valueOf(iB3), Boolean.valueOf(ek.v.g(this, 3)), strQ4, Integer.valueOf(iB4), Boolean.valueOf(zG2), strQ2, Integer.valueOf(iB2), Boolean.valueOf(zG), strQ, Integer.valueOf(iB)), new DmiRemote.Input(Integer.valueOf(ek.v.f(this, 0)), Integer.valueOf(ek.v.f(this, 1)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -8388609, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        DmiRemote.Input input = new DmiRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)), Integer.valueOf(ek.v.i(this, 1, z10)));
        boolean zJ = ek.v.j(this, 0, z10);
        boolean zJ2 = ek.v.j(this, 1, z10);
        DmiRemote.Output output = new DmiRemote.Output(Boolean.valueOf(ek.v.j(this, 2, z10)), null, null, Boolean.valueOf(ek.v.j(this, 3, z10)), null, null, Boolean.valueOf(zJ2), null, null, Boolean.valueOf(zJ), null, null, 3510, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        String strQ3 = ek.v.q(k()[2].a());
        int iB3 = (int) k()[2].b();
        String strQ4 = ek.v.q(k()[3].a());
        int iB4 = (int) k()[3].b();
        boolean zJ3 = ek.v.j(this, 0, z10);
        boolean zJ4 = ek.v.j(this, 1, z10);
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new DmiRemote(input, output, new DmiRemote.Output(Boolean.valueOf(ek.v.j(this, 2, z10)), strQ3, Integer.valueOf(iB3), Boolean.valueOf(ek.v.j(this, 3, z10)), strQ4, Integer.valueOf(iB4), Boolean.valueOf(zJ4), strQ2, Integer.valueOf(iB2), Boolean.valueOf(zJ3), strQ, Integer.valueOf(iB)), new DmiRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)), Integer.valueOf(ek.v.i(this, 1, z10)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -8388609, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("dmi");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 13;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("PDI", -13643086, 0.0f, 4, null), new ek.m("MDI", -19456, 0.0f, 4, null), new ek.m("ADX", -1553991, 0.0f, 4, null), new ek.m("ADXR", -15435576, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("DI", new p292ng.g(0, 90), 14, false, 0, 24, null), new ek.w("ADX", new p292ng.g(0, 60), 6, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("PDI", false, 2, null), new ek.I("MDI", false, 2, null), new ek.I("ADX", false, 2, null), new ek.I("ADXR", false, 2, null)};
    }
}
