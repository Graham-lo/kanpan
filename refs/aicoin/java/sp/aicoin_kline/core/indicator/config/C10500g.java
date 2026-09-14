package sp.aicoin_kline.core.indicator.config;

import app.aicoin.ui.main.data.NewsSearchTypeItemEntity;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: sp.aicoin_kline.core.indicator.config.g, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C10500g extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        AiPDRemote aipd = chartIndicatorSetting.getAipd();
        if (aipd == null) {
            return;
        }
        if (KLineManager.f142490O.a().H()) {
            AiPDRemote.Output output = aipd.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getPdDisabled());
                return;
            }
            return;
        }
        AiPDRemote.Output app_output = aipd.getApp_output();
        if (app_output != null) {
            ek.v.l(this, 0, app_output.getPdDisabled());
        }
        AiPDRemote.Output output2 = aipd.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getPdDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new AiPDRemote(new AiPDRemote.Output(Boolean.valueOf(ek.v.j(this, 0, KLineManager.f142490O.a().H())), null, null, null, null, null, null, null, NewsSearchTypeItemEntity.Type.HISTORY_SECTION, null), new AiPDRemote.Output(Boolean.valueOf(ek.v.g(this, 0)), null, null, null, null, null, null, null, NewsSearchTypeItemEntity.Type.HISTORY_SECTION, null)), null, null, null, null, null, null, null, null, -1, 33488895, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new AiPDRemote(new AiPDRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, null, null, null, null, null, NewsSearchTypeItemEntity.Type.HISTORY_SECTION, null), new AiPDRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, null, null, null, null, null, NewsSearchTypeItemEntity.Type.HISTORY_SECTION, null)), null, null, null, null, null, null, null, null, -1, 33488895, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("ai-pd");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 38;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("AI-PD", -13643086, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[0];
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("AI-PD", false, 2, null)};
    }
}
