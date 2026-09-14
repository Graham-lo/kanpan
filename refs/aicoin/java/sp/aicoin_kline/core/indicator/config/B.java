package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class B extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        FTBSRemote ftbs = chartIndicatorSetting.getFtbs();
        if (ftbs == null) {
            return;
        }
        FTBSRemote.Output app_output = ftbs.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getBuyLineColor());
            Integer buyLineWidth = app_output.getBuyLineWidth();
            if (numR != null && buyLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(buyLineWidth.intValue());
            }
            Integer numR2 = ek.v.r(app_output.getSellLineColor());
            Integer sellLineWidth = app_output.getSellLineWidth();
            if (numR2 != null && sellLineWidth != null) {
                k()[1].d(numR2.intValue());
                k()[1].e(sellLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            FTBSRemote.Output output = ftbs.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getBuyDisabled());
                ek.v.l(this, 1, output.getSellDisabled());
                return;
            }
            return;
        }
        FTBSRemote.Output app_output2 = ftbs.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getBuyDisabled());
            ek.v.l(this, 1, app_output2.getSellDisabled());
        }
        FTBSRemote.Output output2 = ftbs.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getBuyDisabled());
            ek.v.o(this, 1, output2.getSellDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        FTBSRemote.Output output = new FTBSRemote.Output(Boolean.valueOf(ek.v.j(this, 0, zH)), null, null, Boolean.valueOf(ek.v.j(this, 1, zH)), null, null, 54, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new FTBSRemote(output, new FTBSRemote.Output(Boolean.valueOf(ek.v.g(this, 0)), strQ, Integer.valueOf(iB), Boolean.valueOf(ek.v.g(this, 1)), strQ2, Integer.valueOf(iB2))), null, null, null, null, null, null, null, null, null, null, null, null, -1, 33550335, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        FTBSRemote.Output output = new FTBSRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, Boolean.valueOf(ek.v.j(this, 1, z10)), null, null, 54, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new FTBSRemote(output, new FTBSRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), strQ, Integer.valueOf(iB), Boolean.valueOf(ek.v.j(this, 1, z10)), strQ2, Integer.valueOf(iB2))), null, null, null, null, null, null, null, null, null, null, null, null, -1, 33550335, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("ftbs");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 34;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("Buy", -13643086, 0.0f, 4, null), new ek.m("Sell", -19456, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[0];
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("Buy", false, 2, null), new ek.I("Sell", false, 2, null)};
    }
}
