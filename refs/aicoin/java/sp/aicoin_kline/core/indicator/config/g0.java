package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class g0 extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        VrRemote vr = chartIndicatorSetting.getVr();
        if (vr == null) {
            return;
        }
        VrRemote.Output app_output = vr.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getVrLineColor());
            Integer vrLineWidth = app_output.getVrLineWidth();
            if (numR != null && vrLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(vrLineWidth.intValue());
            }
            Integer numR2 = ek.v.r(app_output.getMaVrLineColor());
            Integer maVrLineWidth = app_output.getMaVrLineWidth();
            if (numR2 != null && maVrLineWidth != null) {
                k()[1].d(numR2.intValue());
                k()[1].e(maVrLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            VrRemote.Input input = vr.getInput();
            if (input != null) {
                ek.v.m(this, 0, input.getCc());
                ek.v.m(this, 1, input.getMac());
            }
            VrRemote.Output output = vr.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getVrDisabled());
                ek.v.l(this, 1, output.getMaVrDisabled());
                return;
            }
            return;
        }
        VrRemote.Input app_input = vr.getApp_input();
        if (app_input != null) {
            ek.v.m(this, 0, app_input.getCc());
            ek.v.m(this, 1, app_input.getMac());
        }
        VrRemote.Output app_output2 = vr.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getVrDisabled());
            ek.v.l(this, 1, app_output2.getMaVrDisabled());
        }
        VrRemote.Input input2 = vr.getInput();
        if (input2 != null) {
            ek.v.p(this, 0, input2.getCc());
            ek.v.p(this, 1, input2.getMac());
        }
        VrRemote.Output output2 = vr.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getVrDisabled());
            ek.v.o(this, 1, output2.getMaVrDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        VrRemote.Input input = new VrRemote.Input(Integer.valueOf(ek.v.i(this, 0, zH)), Integer.valueOf(ek.v.i(this, 1, zH)));
        VrRemote.Output output = new VrRemote.Output(Boolean.valueOf(ek.v.j(this, 1, zH)), null, null, Boolean.valueOf(ek.v.j(this, 0, zH)), null, null, 54, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new VrRemote(input, output, new VrRemote.Output(Boolean.valueOf(ek.v.g(this, 1)), ek.v.q(k()[1].a()), Integer.valueOf((int) k()[1].b()), Boolean.valueOf(ek.v.g(this, 0)), strQ, Integer.valueOf(iB)), new VrRemote.Input(Integer.valueOf(ek.v.f(this, 0)), Integer.valueOf(ek.v.f(this, 1)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -16777217, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        VrRemote.Input input = new VrRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)), Integer.valueOf(ek.v.i(this, 1, z10)));
        VrRemote.Output output = new VrRemote.Output(Boolean.valueOf(ek.v.j(this, 1, z10)), null, null, Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, 54, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new VrRemote(input, output, new VrRemote.Output(Boolean.valueOf(ek.v.j(this, 1, z10)), ek.v.q(k()[1].a()), Integer.valueOf((int) k()[1].b()), Boolean.valueOf(ek.v.j(this, 0, z10)), strQ, Integer.valueOf(iB)), new VrRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)), Integer.valueOf(ek.v.i(this, 1, z10)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -16777217, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("vr");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 14;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("VR", -13643086, 0.0f, 4, null), new ek.m("MAVR", -19456, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("VR", new p292ng.g(0, 100), 26, false, 0, 24, null), new ek.w("MAVR", new p292ng.g(0, 100), 6, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("VR", false, 2, null), new ek.I("MAVR", false, 2, null)};
    }
}
