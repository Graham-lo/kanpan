package sp.aicoin_kline.core.indicator.config;

import app.aicoin.ui.main.data.NewsSearchTypeItemEntity;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class C extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        FundFlowRemote fundflow = chartIndicatorSetting.getFundflow();
        if (fundflow == null) {
            return;
        }
        if (KLineManager.f142490O.a().H()) {
            FundFlowRemote.Output output = fundflow.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getFundflowDisabled());
                return;
            }
            return;
        }
        FundFlowRemote.Output app_output = fundflow.getApp_output();
        if (app_output != null) {
            ek.v.l(this, 0, app_output.getFundflowDisabled());
        }
        FundFlowRemote.Output output2 = fundflow.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getFundflowDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new FundFlowRemote(new FundFlowRemote.Output(Boolean.valueOf(ek.v.j(this, 0, KLineManager.f142490O.a().H())), null, null, null, null, null, null, null, NewsSearchTypeItemEntity.Type.HISTORY_SECTION, null), new FundFlowRemote.Output(Boolean.valueOf(ek.v.g(this, 0)), null, null, null, null, null, null, null, NewsSearchTypeItemEntity.Type.HISTORY_SECTION, null)), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1, 33554430, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new FundFlowRemote(new FundFlowRemote.Output(Boolean.valueOf(ek.v.j(this, 0, KLineManager.f142490O.a().H())), null, null, null, null, null, null, null, NewsSearchTypeItemEntity.Type.HISTORY_SECTION, null), new FundFlowRemote.Output(Boolean.valueOf(ek.v.g(this, 0)), null, null, null, null, null, null, null, NewsSearchTypeItemEntity.Type.HISTORY_SECTION, null)), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1, 33554430, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("fundflow");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 12;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("Fund flow", -13643086, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[0];
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("Fund flow", false, 2, null)};
    }
}
