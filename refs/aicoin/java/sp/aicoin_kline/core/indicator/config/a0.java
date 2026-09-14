package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class a0 extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        Boolean tdHide;
        Boolean tdHide2;
        Boolean tdHide3;
        TDRemote td2 = chartIndicatorSetting.getTd();
        if (td2 == null) {
            return;
        }
        if (KLineManager.f142490O.a().H()) {
            TDRemote.Output output = td2.getOutput();
            if (output == null || (tdHide3 = output.getTdHide()) == null) {
                return;
            }
            r()[0].d(tdHide3.booleanValue());
            return;
        }
        TDRemote.Output app_output = td2.getApp_output();
        if (app_output != null && (tdHide2 = app_output.getTdHide()) != null) {
            r()[0].d(tdHide2.booleanValue());
        }
        TDRemote.Output output2 = td2.getOutput();
        if (output2 == null || (tdHide = output2.getTdHide()) == null) {
            return;
        }
        p()[0].d(tdHide.booleanValue());
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, new TDRemote(new TDRemote.Output(Boolean.valueOf((KLineManager.f142490O.a().H() ? r()[0] : p()[0]).b()), null, null, 6, null), new TDRemote.Output(Boolean.valueOf(r()[0].b()), null, null, 6, null)), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -2049, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, new TDRemote(new TDRemote.Output(Boolean.valueOf((z10 ? r()[0] : p()[0]).b()), null, null, 6, null), new TDRemote.Output(Boolean.valueOf((z10 ? r()[0] : p()[0]).b()), null, null, 6, null)), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -2049, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("td");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 10;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return true;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("TD_ONLY_913", -13643086, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[0];
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("TD_ONLY_913", false)};
    }
}
