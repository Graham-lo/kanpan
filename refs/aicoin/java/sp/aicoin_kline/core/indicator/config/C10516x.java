package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: sp.aicoin_kline.core.indicator.config.x, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C10516x extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        EMVRemote emv = chartIndicatorSetting.getEmv();
        if (emv == null) {
            return;
        }
        EMVRemote.Output app_output = emv.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getEmvLineColor());
            Integer emvLineWidth = app_output.getEmvLineWidth();
            if (numR != null && emvLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(emvLineWidth.intValue());
            }
            Integer numR2 = ek.v.r(app_output.getMaEmvLineColor());
            Integer maEmvLineWidth = app_output.getMaEmvLineWidth();
            if (numR2 != null && maEmvLineWidth != null) {
                k()[1].d(numR2.intValue());
                k()[1].e(maEmvLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            EMVRemote.Input input = emv.getInput();
            if (input != null) {
                ek.v.m(this, 0, input.getMac1());
                ek.v.m(this, 1, input.getMac2());
            }
            EMVRemote.Output output = emv.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getEmvDisabled());
                ek.v.l(this, 1, output.getMaEmvDisabled());
                return;
            }
            return;
        }
        EMVRemote.Input app_input = emv.getApp_input();
        if (app_input != null) {
            ek.v.m(this, 0, app_input.getMac1());
            ek.v.m(this, 1, app_input.getMac2());
        }
        EMVRemote.Output app_output2 = emv.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getEmvDisabled());
            ek.v.l(this, 1, app_output2.getMaEmvDisabled());
        }
        EMVRemote.Input input2 = emv.getInput();
        if (input2 != null) {
            ek.v.p(this, 0, input2.getMac1());
            ek.v.p(this, 1, input2.getMac2());
        }
        EMVRemote.Output output2 = emv.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getEmvDisabled());
            ek.v.o(this, 1, output2.getMaEmvDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        EMVRemote.Input input = new EMVRemote.Input(Integer.valueOf(ek.v.i(this, 0, zH)), Integer.valueOf(ek.v.i(this, 1, zH)));
        EMVRemote.Output output = new EMVRemote.Output(Boolean.valueOf(ek.v.j(this, 0, zH)), null, null, Boolean.valueOf(ek.v.j(this, 1, zH)), null, null, 54, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new EMVRemote(input, output, new EMVRemote.Output(Boolean.valueOf(ek.v.g(this, 0)), strQ, Integer.valueOf(iB), Boolean.valueOf(ek.v.g(this, 1)), strQ2, Integer.valueOf(iB2)), new EMVRemote.Input(Integer.valueOf(ek.v.f(this, 0)), Integer.valueOf(ek.v.f(this, 1)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1, 33554399, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        EMVRemote.Input input = new EMVRemote.Input(Integer.valueOf(ek.v.b(this, 0, z10)), Integer.valueOf(ek.v.b(this, 1, z10)));
        EMVRemote.Output output = new EMVRemote.Output(Boolean.valueOf(ek.v.c(this, 0, z10)), null, null, Boolean.valueOf(ek.v.c(this, 1, z10)), null, null, 54, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new EMVRemote(input, output, new EMVRemote.Output(Boolean.valueOf(ek.v.c(this, 0, z10)), strQ, Integer.valueOf(iB), Boolean.valueOf(ek.v.c(this, 1, z10)), strQ2, Integer.valueOf(iB2)), new EMVRemote.Input(Integer.valueOf(ek.v.b(this, 0, z10)), Integer.valueOf(ek.v.b(this, 1, z10)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1, 33554399, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("emv");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 26;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("EMV", -13643086, 0.0f, 4, null), new ek.m("MAEMV", -19456, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("EMV", new p292ng.g(0, 90), 14, false, 0, 24, null), new ek.w("MAEMV", new p292ng.g(0, 60), 9, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("EMV", false, 2, null), new ek.I("MAEMV", false, 2, null)};
    }
}
