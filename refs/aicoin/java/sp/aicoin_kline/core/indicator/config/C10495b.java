package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: sp.aicoin_kline.core.indicator.config.b, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C10495b extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        AiBstRemote aibst = chartIndicatorSetting.getAibst();
        if (aibst == null) {
            return;
        }
        if (KLineManager.f142490O.a().H()) {
            AiBstRemote.Output output = aibst.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getPosDisabled());
                ek.v.l(this, 1, output.getNegDisabled());
                return;
            }
            return;
        }
        AiBstRemote.Output app_output = aibst.getApp_output();
        if (app_output != null) {
            ek.v.l(this, 0, app_output.getPosDisabled());
            ek.v.l(this, 1, app_output.getNegDisabled());
        }
        AiBstRemote.Output output2 = aibst.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getPosDisabled());
            ek.v.o(this, 1, output2.getNegDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new AiBstRemote(new AiBstRemote.Output(null, Boolean.valueOf(ek.v.j(this, 1, zH)), null, null, Boolean.valueOf(ek.v.j(this, 0, zH)), null, 45, null), new AiBstRemote.Output(null, Boolean.valueOf(ek.v.g(this, 1)), null, null, Boolean.valueOf(ek.v.g(this, 0)), null, 45, null)), null, null, null, null, -1, 32505855, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new AiBstRemote(new AiBstRemote.Output(null, Boolean.valueOf(ek.v.j(this, 1, z10)), null, null, Boolean.valueOf(ek.v.j(this, 0, z10)), null, 45, null), new AiBstRemote.Output(null, Boolean.valueOf(ek.v.j(this, 1, z10)), null, null, Boolean.valueOf(ek.v.j(this, 0, z10)), null, 45, null)), null, null, null, null, -1, 32505855, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("ai-bst");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 42;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("Buy", -13643086, 0.0f, 4, null), new ek.m("Sell", -19456, 0.0f, 4, null), new ek.m("Total", -1553991, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[0];
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("Buy", false, 2, null), new ek.I("Sell", false, 2, null), new ek.I("Total", false, 2, null)};
    }
}
