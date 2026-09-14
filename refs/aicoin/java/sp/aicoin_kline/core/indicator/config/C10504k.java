package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: sp.aicoin_kline.core.indicator.config.k, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C10504k extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        AtrRemote atr = chartIndicatorSetting.getAtr();
        if (atr == null) {
            return;
        }
        AtrRemote.Output app_output = atr.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getAtrLineColor());
            Integer atrLineWidth = app_output.getAtrLineWidth();
            if (numR != null && atrLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(atrLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            AtrRemote.Input input = atr.getInput();
            if (input != null) {
                ek.v.m(this, 0, input.getCc());
            }
            AtrRemote.Output output = atr.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getAtrDisabled());
                return;
            }
            return;
        }
        AtrRemote.Input app_input = atr.getApp_input();
        if (app_input != null) {
            ek.v.m(this, 0, app_input.getCc());
        }
        AtrRemote.Output app_output2 = atr.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getAtrDisabled());
        }
        AtrRemote.Input input2 = atr.getInput();
        if (input2 != null) {
            ek.v.p(this, 0, input2.getCc());
        }
        AtrRemote.Output output2 = atr.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getAtrDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new AtrRemote(new AtrRemote.Input(Integer.valueOf(ek.v.i(this, 0, zH))), new AtrRemote.Output(Boolean.valueOf(ek.v.j(this, 0, zH)), null, null, 6, null), new AtrRemote.Output(Boolean.valueOf(ek.v.g(this, 0)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b())), new AtrRemote.Input(Integer.valueOf(ek.v.f(this, 0)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -4194305, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new AtrRemote(new AtrRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10))), new AtrRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, 6, null), new AtrRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b())), new AtrRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -4194305, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("atr");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 10;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("ATR", -13643086, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("ATR", new p292ng.g(0, 1000), 14, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("ATR", false, 2, null)};
    }
}
