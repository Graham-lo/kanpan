package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class O extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        MtmRemote mtm = chartIndicatorSetting.getMtm();
        if (mtm == null) {
            return;
        }
        MtmRemote.Output app_output = mtm.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getMtmLineColor());
            Integer mtmLineWidth = app_output.getMtmLineWidth();
            if (numR != null && mtmLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(mtmLineWidth.intValue());
            }
            Integer numR2 = ek.v.r(app_output.getMaMtmLineColor());
            Integer maMtmLineWidth = app_output.getMaMtmLineWidth();
            if (numR2 != null && maMtmLineWidth != null) {
                k()[1].d(numR2.intValue());
                k()[1].e(maMtmLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            MtmRemote.Input input = mtm.getInput();
            if (input != null) {
                ek.v.m(this, 0, input.getCc());
                ek.v.m(this, 1, input.getMac());
            }
            MtmRemote.Output output = mtm.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getMtmDisabled());
                ek.v.l(this, 1, output.getMaMtmDisabled());
                return;
            }
            return;
        }
        MtmRemote.Input app_input = mtm.getApp_input();
        if (app_input != null) {
            ek.v.m(this, 0, app_input.getCc());
            ek.v.m(this, 1, app_input.getMac());
        }
        MtmRemote.Output app_output2 = mtm.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getMtmDisabled());
            ek.v.l(this, 1, app_output2.getMaMtmDisabled());
        }
        MtmRemote.Input input2 = mtm.getInput();
        if (input2 != null) {
            ek.v.p(this, 0, input2.getCc());
            ek.v.p(this, 1, input2.getMac());
        }
        MtmRemote.Output output2 = mtm.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getMtmDisabled());
            ek.v.o(this, 1, output2.getMaMtmDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        MtmRemote.Input input = new MtmRemote.Input(Integer.valueOf(ek.v.i(this, 0, zH)), Integer.valueOf(ek.v.i(this, 1, zH)));
        MtmRemote.Output output = new MtmRemote.Output(Boolean.valueOf(ek.v.j(this, 1, zH)), null, null, Boolean.valueOf(ek.v.j(this, 0, zH)), null, null, 54, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new MtmRemote(input, output, new MtmRemote.Output(Boolean.valueOf(ek.v.g(this, 1)), ek.v.q(k()[1].a()), Integer.valueOf((int) k()[1].b()), Boolean.valueOf(ek.v.g(this, 0)), strQ, Integer.valueOf(iB)), new MtmRemote.Input(Integer.valueOf(ek.v.f(this, 0)), Integer.valueOf(ek.v.f(this, 1)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1073741825, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("mtm");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 20;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("MTM", -13643086, 0.0f, 4, null), new ek.m("MAMTM", -19456, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("MTM", new p292ng.g(0, 120), 12, false, 0, 24, null), new ek.w("MAMTM", new p292ng.g(0, 60), 6, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("MTM", false, 2, null), new ek.I("MAMTM", false, 2, null)};
    }
}
