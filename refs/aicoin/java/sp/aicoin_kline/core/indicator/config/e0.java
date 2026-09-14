package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class e0 extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        TrixRemote trix = chartIndicatorSetting.getTrix();
        if (trix == null) {
            return;
        }
        TrixRemote.Output app_output = trix.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getTrixLineColor());
            Integer trixLineWidth = app_output.getTrixLineWidth();
            if (numR != null && trixLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(trixLineWidth.intValue());
            }
            Integer numR2 = ek.v.r(app_output.getMaTrixLineColor());
            Integer maTrixLineWidth = app_output.getMaTrixLineWidth();
            if (numR2 != null && maTrixLineWidth != null) {
                k()[1].d(numR2.intValue());
                k()[1].e(maTrixLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            TrixRemote.Input input = trix.getInput();
            if (input != null) {
                ek.v.m(this, 0, input.getMac1());
                ek.v.m(this, 1, input.getMac2());
            }
            TrixRemote.Output output = trix.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getTrixDisabled());
                ek.v.l(this, 1, output.getMaTrixDisabled());
                return;
            }
            return;
        }
        TrixRemote.Input app_input = trix.getApp_input();
        if (app_input != null) {
            ek.v.m(this, 0, app_input.getMac1());
            ek.v.m(this, 1, app_input.getMac2());
        }
        TrixRemote.Output app_output2 = trix.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getTrixDisabled());
            ek.v.l(this, 1, app_output2.getMaTrixDisabled());
        }
        TrixRemote.Input input2 = trix.getInput();
        if (input2 != null) {
            ek.v.p(this, 0, input2.getMac1());
            ek.v.p(this, 1, input2.getMac2());
        }
        TrixRemote.Output output2 = trix.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getTrixDisabled());
            ek.v.o(this, 1, output2.getMaTrixDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        TrixRemote.Input input = new TrixRemote.Input(Integer.valueOf(ek.v.i(this, 0, zH)), Integer.valueOf(ek.v.i(this, 1, zH)));
        TrixRemote.Output output = new TrixRemote.Output(Boolean.valueOf(ek.v.j(this, 1, zH)), null, null, Boolean.valueOf(ek.v.j(this, 0, zH)), null, null, 54, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new TrixRemote(input, output, new TrixRemote.Output(Boolean.valueOf(ek.v.g(this, 1)), ek.v.q(k()[1].a()), Integer.valueOf((int) k()[1].b()), Boolean.valueOf(ek.v.g(this, 0)), strQ, Integer.valueOf(iB)), new TrixRemote.Input(Integer.valueOf(ek.v.f(this, 0)), Integer.valueOf(ek.v.f(this, 1)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -262145, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        TrixRemote.Input input = new TrixRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)), Integer.valueOf(ek.v.i(this, 1, z10)));
        TrixRemote.Output output = new TrixRemote.Output(Boolean.valueOf(ek.v.j(this, 1, z10)), null, null, Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, 54, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new TrixRemote(input, output, new TrixRemote.Output(Boolean.valueOf(ek.v.j(this, 1, z10)), ek.v.q(k()[1].a()), Integer.valueOf((int) k()[1].b()), Boolean.valueOf(ek.v.j(this, 0, z10)), strQ, Integer.valueOf(iB)), new TrixRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)), Integer.valueOf(ek.v.i(this, 1, z10)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -262145, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("trix");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 6;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("TRIX", -13643086, 0.0f, 4, null), new ek.m("MATRIX", -19456, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("TRIX", new p292ng.g(0, 100), 12, false, 0, 24, null), new ek.w("MATRIX", new p292ng.g(0, 100), 9, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("TRIX", false, 2, null), new ek.I("MATRIX", false, 2, null)};
    }
}
