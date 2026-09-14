package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class W extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        Integer numR;
        SARRemote sar = chartIndicatorSetting.getSar();
        if (sar == null) {
            return;
        }
        SARRemote.Output app_output = sar.getApp_output();
        if (app_output != null && (numR = ek.v.r(app_output.getSarColor())) != null) {
            k()[0].d(numR.intValue());
        }
        if (KLineManager.f142490O.a().H()) {
            SARRemote.Input input = sar.getInput();
            if (input != null) {
                ek.v.k(this, 0, input.getAf(), 3);
                ek.v.k(this, 1, input.getEp(), 3);
            }
            SARRemote.Output output = sar.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getSarDisabled());
                return;
            }
            return;
        }
        SARRemote.Input app_input = sar.getApp_input();
        if (app_input != null) {
            ek.v.k(this, 0, app_input.getAf(), 3);
            ek.v.k(this, 1, app_input.getEp(), 3);
        }
        SARRemote.Output app_output2 = sar.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getSarDisabled());
        }
        SARRemote.Input input2 = sar.getInput();
        if (input2 != null) {
            ek.v.n(this, 0, input2.getAf(), 3);
            ek.v.n(this, 1, input2.getEp(), 3);
        }
        SARRemote.Output output2 = sar.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getSarDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        return new ChartIndicatorSetting(null, null, null, null, null, null, new SARRemote(new SARRemote.Input(ek.v.h(this, 0, zH), ek.v.h(this, 1, zH)), new SARRemote.Output(null, Boolean.valueOf(ek.v.j(this, 0, zH)), null, 5, null), new SARRemote.Output(ek.v.q(k()[0].a()), Boolean.valueOf(ek.v.g(this, 0)), null, 4, null), new SARRemote.Input(ek.v.d(this, 0), ek.v.d(this, 1))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -65, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        return new ChartIndicatorSetting(null, null, null, null, null, null, new SARRemote(new SARRemote.Input(ek.v.a(this, 0, z10), ek.v.a(this, 1, z10)), new SARRemote.Output(null, Boolean.valueOf(ek.v.c(this, 0, z10)), null, 5, null), new SARRemote.Output(ek.v.q(k()[0].a()), Boolean.valueOf(ek.v.c(this, 0, z10)), null, 4, null), new SARRemote.Input(ek.v.a(this, 0, z10), ek.v.a(this, 1, z10))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -65, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("sar");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 4;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return true;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("SAR", -13643086, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("ACC", new p292ng.g(0, 100), 2, false, 3, 8, null), new ek.w("MAX", new p292ng.g(0, 100), 20, false, 3, 8, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("SAR", false, 2, null)};
    }
}
