package sp.aicoin_kline.core.indicator.config;

import app.aicoin.ui.main.data.NewsSearchTypeItemEntity;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: sp.aicoin_kline.core.indicator.config.d, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C10497d extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        AiFDIRemote aifdi = chartIndicatorSetting.getAifdi();
        if (aifdi == null) {
            return;
        }
        if (KLineManager.f142490O.a().H()) {
            AiFDIRemote.Output output = aifdi.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getFdiDisabled());
                return;
            }
            return;
        }
        AiFDIRemote.Output app_output = aifdi.getApp_output();
        if (app_output != null) {
            ek.v.l(this, 0, app_output.getFdiDisabled());
        }
        AiFDIRemote.Output output2 = aifdi.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getFdiDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new AiFDIRemote(new AiFDIRemote.Output(Boolean.valueOf(ek.v.j(this, 0, KLineManager.f142490O.a().H())), null, null, null, null, null, null, null, NewsSearchTypeItemEntity.Type.HISTORY_SECTION, null), new AiFDIRemote.Output(Boolean.valueOf(ek.v.g(this, 0)), null, null, null, null, null, null, null, NewsSearchTypeItemEntity.Type.HISTORY_SECTION, null)), null, null, null, null, null, null, null, null, null, -1, 33521663, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new AiFDIRemote(new AiFDIRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, null, null, null, null, null, NewsSearchTypeItemEntity.Type.HISTORY_SECTION, null), new AiFDIRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, null, null, null, null, null, NewsSearchTypeItemEntity.Type.HISTORY_SECTION, null)), null, null, null, null, null, null, null, null, null, -1, 33521663, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("ai-fdi");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 37;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("AI-FDI", -13643086, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[0];
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("AI-FDI", false, 2, null)};
    }
}
