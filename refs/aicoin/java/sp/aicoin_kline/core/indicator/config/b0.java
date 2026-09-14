package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class b0 extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        TTMURemote ttmu = chartIndicatorSetting.getTtmu();
        if (ttmu == null) {
            return;
        }
        TTMURemote.Output app_output = ttmu.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getLongLineColor());
            Integer longLineWidth = app_output.getLongLineWidth();
            if (numR != null && longLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(longLineWidth.intValue());
            }
            Integer numR2 = ek.v.r(app_output.getShortLineColor());
            Integer shortLineWidth = app_output.getShortLineWidth();
            if (numR2 != null && shortLineWidth != null) {
                k()[1].d(numR2.intValue());
                k()[1].e(shortLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            TTMURemote.Output output = ttmu.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getLongDisabled());
                ek.v.l(this, 1, output.getShortDisabled());
                return;
            }
            return;
        }
        TTMURemote.Output app_output2 = ttmu.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getLongDisabled());
            ek.v.l(this, 1, app_output2.getShortDisabled());
        }
        TTMURemote.Output output2 = ttmu.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getLongDisabled());
            ek.v.o(this, 1, output2.getShortDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        TTMURemote.Output output = new TTMURemote.Output(Boolean.valueOf(ek.v.j(this, 0, zH)), null, null, Boolean.valueOf(ek.v.j(this, 1, zH)), null, null, 54, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new TTMURemote(output, new TTMURemote.Output(Boolean.valueOf(ek.v.g(this, 0)), strQ, Integer.valueOf(iB), Boolean.valueOf(ek.v.g(this, 1)), strQ2, Integer.valueOf(iB2))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1, 33554423, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        TTMURemote.Output output = new TTMURemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, Boolean.valueOf(ek.v.j(this, 1, z10)), null, null, 54, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new TTMURemote(output, new TTMURemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), strQ, Integer.valueOf(iB), Boolean.valueOf(ek.v.j(this, 1, z10)), strQ2, Integer.valueOf(iB2))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1, 33554423, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("ttmu");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 24;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("Long", -13643086, 0.0f, 4, null), new ek.m("Short", -19456, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[0];
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("Long", false, 2, null), new ek.I("Short", false, 2, null)};
    }
}
