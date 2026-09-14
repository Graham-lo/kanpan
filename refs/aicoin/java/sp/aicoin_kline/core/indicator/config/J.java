package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class J extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        MFIRemote mfi = chartIndicatorSetting.getMfi();
        if (mfi == null) {
            return;
        }
        MFIRemote.Output app_output = mfi.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getMfiLineColor());
            Integer mfiLineWidth = app_output.getMfiLineWidth();
            if (numR != null && mfiLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(mfiLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            MFIRemote.Input input = mfi.getInput();
            if (input != null) {
                ek.v.m(this, 0, input.getCc());
                ek.v.m(this, 1, input.getUpperBand());
                ek.v.m(this, 2, input.getLowerBand());
            }
            MFIRemote.Output output = mfi.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getMfiDisabled());
                return;
            }
            return;
        }
        MFIRemote.Input app_input = mfi.getApp_input();
        if (app_input != null) {
            ek.v.m(this, 0, app_input.getCc());
            ek.v.m(this, 1, app_input.getUpperBand());
            ek.v.m(this, 2, app_input.getLowerBand());
        }
        MFIRemote.Output app_output2 = mfi.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getMfiDisabled());
        }
        MFIRemote.Input input2 = mfi.getInput();
        if (input2 != null) {
            ek.v.p(this, 0, input2.getCc());
            ek.v.p(this, 1, input2.getUpperBand());
            ek.v.p(this, 2, input2.getLowerBand());
        }
        MFIRemote.Output output2 = mfi.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getMfiDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        int i10 = ek.v.i(this, 0, zH);
        int i11 = ek.v.i(this, 1, zH);
        MFIRemote.Input input = new MFIRemote.Input(Integer.valueOf(i10), Integer.valueOf(ek.v.i(this, 2, zH)), Integer.valueOf(i11));
        MFIRemote.Output output = new MFIRemote.Output(null, null, null, null, null, Boolean.valueOf(ek.v.j(this, 0, zH)), null, null, null, null, null, 2015, null);
        MFIRemote.Output output2 = new MFIRemote.Output(null, null, null, null, null, Boolean.valueOf(ek.v.g(this, 0)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b()), null, null, null, 1823, null);
        int iF = ek.v.f(this, 0);
        int iF2 = ek.v.f(this, 1);
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new MFIRemote(input, output, output2, new MFIRemote.Input(Integer.valueOf(iF), Integer.valueOf(ek.v.f(this, 2)), Integer.valueOf(iF2))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1, 33554367, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        int i10 = ek.v.i(this, 0, z10);
        int i11 = ek.v.i(this, 1, z10);
        MFIRemote.Input input = new MFIRemote.Input(Integer.valueOf(i10), Integer.valueOf(ek.v.i(this, 2, z10)), Integer.valueOf(i11));
        MFIRemote.Output output = new MFIRemote.Output(null, null, null, null, null, Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, null, null, null, 2015, null);
        MFIRemote.Output output2 = new MFIRemote.Output(null, null, null, null, null, Boolean.valueOf(ek.v.j(this, 0, z10)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b()), null, null, null, 1823, null);
        int i12 = ek.v.i(this, 0, z10);
        int i13 = ek.v.i(this, 1, z10);
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new MFIRemote(input, output, output2, new MFIRemote.Input(Integer.valueOf(i12), Integer.valueOf(ek.v.i(this, 2, z10)), Integer.valueOf(i13))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1, 33554367, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("mfi");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 27;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("MFI", -13643086, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("N", new p292ng.g(0, 1000), 14, false, 0, 24, null), new ek.w("OVER_BOUGHT", new p292ng.g(0, 100), 80, false, 0, 24, null), new ek.w("OVER_SOLD", new p292ng.g(0, 100), 20, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("MFI", false, 2, null)};
    }
}
