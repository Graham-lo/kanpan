package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class Y extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        SmiRemote smi = chartIndicatorSetting.getSmi();
        if (smi == null) {
            return;
        }
        SmiRemote.Output app_output = smi.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getSmiLineColor());
            Integer smiLineWidth = app_output.getSmiLineWidth();
            if (numR != null && smiLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(smiLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            SmiRemote.Input input = smi.getInput();
            if (input != null) {
                ek.v.m(this, 0, input.getMac());
            }
            SmiRemote.Output output = smi.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getSmiDisabled());
                return;
            }
            return;
        }
        SmiRemote.Input app_input = smi.getApp_input();
        if (app_input != null) {
            ek.v.m(this, 0, app_input.getMac());
        }
        SmiRemote.Output app_output2 = smi.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getSmiDisabled());
        }
        SmiRemote.Input input2 = smi.getInput();
        if (input2 != null) {
            ek.v.p(this, 0, input2.getMac());
        }
        SmiRemote.Output output2 = smi.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getSmiDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new SmiRemote(new SmiRemote.Input(Integer.valueOf(ek.v.i(this, 0, zH))), new SmiRemote.Output(Boolean.valueOf(ek.v.j(this, 0, zH)), null, null, 6, null), new SmiRemote.Output(Boolean.valueOf(ek.v.g(this, 0)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b())), new SmiRemote.Input(Integer.valueOf(ek.v.f(this, 0)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -134217729, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new SmiRemote(new SmiRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10))), new SmiRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, 6, null), new SmiRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b())), new SmiRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -134217729, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("smi");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 17;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("SMI", -13643086, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("SMI", new p292ng.g(0, 1000), 20, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("SMI", false, 2, null)};
    }
}
