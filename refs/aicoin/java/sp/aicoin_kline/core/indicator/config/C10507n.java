package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: sp.aicoin_kline.core.indicator.config.n, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C10507n extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        BRARRemote brar = chartIndicatorSetting.getBrar();
        if (brar == null) {
            return;
        }
        BRARRemote.Output app_output = brar.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getBrLineColor());
            Integer brLineWidth = app_output.getBrLineWidth();
            if (numR != null && brLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(brLineWidth.intValue());
            }
            Integer numR2 = ek.v.r(app_output.getArLineColor());
            Integer arLineWidth = app_output.getArLineWidth();
            if (numR2 != null && arLineWidth != null) {
                k()[1].d(numR2.intValue());
                k()[1].e(arLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            BRARRemote.Input input = brar.getInput();
            if (input != null) {
                ek.v.m(this, 0, input.getCc());
            }
            BRARRemote.Output output = brar.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getBrDisabled());
                ek.v.l(this, 1, output.getArDisabled());
                return;
            }
            return;
        }
        BRARRemote.Input app_input = brar.getApp_input();
        if (app_input != null) {
            ek.v.m(this, 0, app_input.getCc());
        }
        BRARRemote.Output app_output2 = brar.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getBrDisabled());
            ek.v.l(this, 1, app_output2.getArDisabled());
        }
        BRARRemote.Input input2 = brar.getInput();
        if (input2 != null) {
            ek.v.p(this, 0, input2.getCc());
        }
        BRARRemote.Output output2 = brar.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getBrDisabled());
            ek.v.o(this, 1, output2.getArDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        BRARRemote.Input input = new BRARRemote.Input(Integer.valueOf(ek.v.i(this, 0, zH)));
        BRARRemote.Output output = new BRARRemote.Output(Boolean.valueOf(ek.v.j(this, 1, zH)), null, null, Boolean.valueOf(ek.v.j(this, 0, zH)), null, null, 54, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new BRARRemote(input, output, new BRARRemote.Output(Boolean.valueOf(ek.v.g(this, 1)), ek.v.q(k()[1].a()), Integer.valueOf((int) k()[1].b()), Boolean.valueOf(ek.v.g(this, 0)), strQ, Integer.valueOf(iB)), new BRARRemote.Input(Integer.valueOf(ek.v.f(this, 0)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1, 33554415, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        BRARRemote.Input input = new BRARRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)));
        BRARRemote.Output output = new BRARRemote.Output(Boolean.valueOf(ek.v.j(this, 1, z10)), null, null, Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, 54, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new BRARRemote(input, output, new BRARRemote.Output(Boolean.valueOf(ek.v.j(this, 1, z10)), ek.v.q(k()[1].a()), Integer.valueOf((int) k()[1].b()), Boolean.valueOf(ek.v.j(this, 0, z10)), strQ, Integer.valueOf(iB)), new BRARRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1, 33554415, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("brar");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 25;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("BR", -13643086, 0.0f, 4, null), new ek.m("AR", -19456, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("N", new p292ng.g(0, 120), 26, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("BR", false, 2, null), new ek.I("AR", false, 2, null)};
    }
}
