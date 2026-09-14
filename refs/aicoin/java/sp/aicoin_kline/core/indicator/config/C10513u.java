package sp.aicoin_kline.core.indicator.config;

import org.apache.tika.metadata.DublinCore;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: sp.aicoin_kline.core.indicator.config.u, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C10513u extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        DCRemote dc2 = chartIndicatorSetting.getDc();
        if (dc2 == null) {
            return;
        }
        DCRemote.Output app_output = dc2.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getMidLineColor());
            Integer midLineWidth = app_output.getMidLineWidth();
            if (numR != null && midLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(midLineWidth.intValue());
            }
            Integer numR2 = ek.v.r(app_output.getUpperLineColor());
            Integer upperLineWidth = app_output.getUpperLineWidth();
            if (numR2 != null && upperLineWidth != null) {
                k()[1].d(numR2.intValue());
                k()[1].e(upperLineWidth.intValue());
            }
            Integer numR3 = ek.v.r(app_output.getLowerLineColor());
            Integer lowerLineWidth = app_output.getLowerLineWidth();
            if (numR3 != null && lowerLineWidth != null) {
                k()[2].d(numR3.intValue());
                k()[2].e(lowerLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            DCRemote.Input input = dc2.getInput();
            if (input != null) {
                ek.v.m(this, 0, input.getCc());
            }
            DCRemote.Output output = dc2.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getMidDisabled());
                ek.v.l(this, 1, output.getUpperDisabled());
                ek.v.l(this, 2, output.getLowerDisabled());
                return;
            }
            return;
        }
        DCRemote.Input app_input = dc2.getApp_input();
        if (app_input != null) {
            ek.v.m(this, 0, app_input.getCc());
        }
        DCRemote.Output app_output2 = dc2.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getMidDisabled());
            ek.v.l(this, 1, app_output2.getUpperDisabled());
            ek.v.l(this, 2, app_output2.getLowerDisabled());
        }
        DCRemote.Input input2 = dc2.getInput();
        if (input2 != null) {
            ek.v.p(this, 0, input2.getCc());
        }
        DCRemote.Output output2 = dc2.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getMidDisabled());
            ek.v.o(this, 1, output2.getUpperDisabled());
            ek.v.o(this, 2, output2.getLowerDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        DCRemote.Input input = new DCRemote.Input(Integer.valueOf(ek.v.i(this, 0, zH)));
        DCRemote.Output output = new DCRemote.Output(Boolean.valueOf(ek.v.j(this, 0, zH)), null, null, Boolean.valueOf(ek.v.j(this, 1, zH)), null, null, Boolean.valueOf(ek.v.j(this, 2, zH)), null, null, null, 950, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        String strQ3 = ek.v.q(k()[2].a());
        int iB3 = (int) k()[2].b();
        return new ChartIndicatorSetting(null, null, new DCRemote(input, output, new DCRemote.Output(Boolean.valueOf(ek.v.g(this, 0)), strQ, Integer.valueOf(iB), Boolean.valueOf(ek.v.g(this, 1)), strQ2, Integer.valueOf(iB2), Boolean.valueOf(ek.v.g(this, 2)), strQ3, Integer.valueOf(iB3), null, 512, null), new DCRemote.Input(Integer.valueOf(ek.v.f(this, 0)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -5, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        DCRemote.Input input = new DCRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)));
        DCRemote.Output output = new DCRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, Boolean.valueOf(ek.v.j(this, 1, z10)), null, null, Boolean.valueOf(ek.v.j(this, 2, z10)), null, null, null, 950, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        String strQ3 = ek.v.q(k()[2].a());
        int iB3 = (int) k()[2].b();
        return new ChartIndicatorSetting(null, null, new DCRemote(input, output, new DCRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), strQ, Integer.valueOf(iB), Boolean.valueOf(ek.v.j(this, 1, z10)), strQ2, Integer.valueOf(iB2), Boolean.valueOf(ek.v.j(this, 2, z10)), strQ3, Integer.valueOf(iB3), null, 512, null), new DCRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -5, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a(DublinCore.PREFIX_DC);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 6;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return true;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("MID", -13643086, 0.0f, 4, null), new ek.m("UP", -19456, 0.0f, 4, null), new ek.m("LOW", -1553991, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("N", new p292ng.g(0, 1000), 20, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("MID", false, 2, null), new ek.I("UP", false, 2, null), new ek.I("LOW", false, 2, null)};
    }
}
