package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class T extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        PsyRemote psy = chartIndicatorSetting.getPsy();
        if (psy == null) {
            return;
        }
        PsyRemote.Output app_output = psy.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getPsyLineColor());
            Integer psyLineWidth = app_output.getPsyLineWidth();
            if (numR != null && psyLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(psyLineWidth.intValue());
            }
            Integer numR2 = ek.v.r(app_output.getMaPsyLineColor());
            Integer maPsyLineWidth = app_output.getMaPsyLineWidth();
            if (numR2 != null && maPsyLineWidth != null) {
                k()[1].d(numR2.intValue());
                k()[1].e(maPsyLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            PsyRemote.Input input = psy.getInput();
            if (input != null) {
                ek.v.m(this, 0, input.getCc());
                ek.v.m(this, 1, input.getMac());
            }
            PsyRemote.Output output = psy.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getPsyDisabled());
                ek.v.l(this, 1, output.getMaPsyDisabled());
                return;
            }
            return;
        }
        PsyRemote.Input app_input = psy.getApp_input();
        if (app_input != null) {
            ek.v.m(this, 0, app_input.getCc());
            ek.v.m(this, 1, app_input.getMac());
        }
        PsyRemote.Output app_output2 = psy.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getPsyDisabled());
            ek.v.l(this, 1, app_output2.getMaPsyDisabled());
        }
        PsyRemote.Input input2 = psy.getInput();
        if (input2 != null) {
            ek.v.p(this, 0, input2.getCc());
            ek.v.p(this, 1, input2.getMac());
        }
        PsyRemote.Output output2 = psy.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getPsyDisabled());
            ek.v.o(this, 1, output2.getMaPsyDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        PsyRemote.Input input = new PsyRemote.Input(Integer.valueOf(ek.v.i(this, 0, zH)), Integer.valueOf(ek.v.i(this, 1, zH)));
        PsyRemote.Output output = new PsyRemote.Output(Boolean.valueOf(ek.v.j(this, 1, zH)), null, null, Boolean.valueOf(ek.v.j(this, 0, zH)), null, null, 54, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new PsyRemote(input, output, new PsyRemote.Output(Boolean.valueOf(ek.v.g(this, 1)), ek.v.q(k()[1].a()), Integer.valueOf((int) k()[1].b()), Boolean.valueOf(ek.v.g(this, 0)), strQ, Integer.valueOf(iB)), new PsyRemote.Input(Integer.valueOf(ek.v.f(this, 0)), Integer.valueOf(ek.v.f(this, 1)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -33554433, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        PsyRemote.Input input = new PsyRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)), Integer.valueOf(ek.v.i(this, 1, z10)));
        PsyRemote.Output output = new PsyRemote.Output(Boolean.valueOf(ek.v.j(this, 1, z10)), null, null, Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, 54, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new PsyRemote(input, output, new PsyRemote.Output(Boolean.valueOf(ek.v.j(this, 1, z10)), ek.v.q(k()[1].a()), Integer.valueOf((int) k()[1].b()), Boolean.valueOf(ek.v.j(this, 0, z10)), strQ, Integer.valueOf(iB)), new PsyRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)), Integer.valueOf(ek.v.i(this, 1, z10)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -33554433, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("psy");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 15;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("PSY", -13643086, 0.0f, 4, null), new ek.m("MAPSY", -19456, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("PSY", new p292ng.g(1, 100), 12, false, 0, 24, null), new ek.w("MAPSY", new p292ng.g(0, 100), 6, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("PSY", false, 2, null), new ek.I("MAPSY", false, 2, null)};
    }
}
