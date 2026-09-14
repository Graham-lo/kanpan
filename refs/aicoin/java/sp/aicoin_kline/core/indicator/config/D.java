package sp.aicoin_kline.core.indicator.config;

import android.content.Context;
import android.content.res.Resources;
import sp.aicoin_kline.R;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class D extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        LiqHeatmapRemote liqheatmap = chartIndicatorSetting.getLiqheatmap();
        if (liqheatmap == null) {
            return;
        }
        if (KLineManager.f142490O.a().H()) {
            LiqHeatmapRemote.Output output = liqheatmap.getOutput();
            if (output != null) {
                Boolean heatmapShowMagnifier = output.getHeatmapShowMagnifier();
                ek.v.l(this, 0, heatmapShowMagnifier != null ? Boolean.valueOf(!heatmapShowMagnifier.booleanValue()) : null);
                Boolean heatmapShowTurnover = output.getHeatmapShowTurnover();
                ek.v.l(this, 1, heatmapShowTurnover != null ? Boolean.valueOf(!heatmapShowTurnover.booleanValue()) : null);
                return;
            }
            return;
        }
        LiqHeatmapRemote.Output app_output = liqheatmap.getApp_output();
        if (app_output != null) {
            Boolean heatmapShowMagnifier2 = app_output.getHeatmapShowMagnifier();
            ek.v.l(this, 0, heatmapShowMagnifier2 != null ? Boolean.valueOf(!heatmapShowMagnifier2.booleanValue()) : null);
            Boolean heatmapShowTurnover2 = app_output.getHeatmapShowTurnover();
            ek.v.l(this, 1, heatmapShowTurnover2 != null ? Boolean.valueOf(!heatmapShowTurnover2.booleanValue()) : null);
        }
        LiqHeatmapRemote.Output output2 = liqheatmap.getOutput();
        if (output2 != null) {
            Boolean heatmapShowMagnifier3 = output2.getHeatmapShowMagnifier();
            ek.v.o(this, 0, heatmapShowMagnifier3 != null ? Boolean.valueOf(!heatmapShowMagnifier3.booleanValue()) : null);
            Boolean heatmapShowTurnover3 = output2.getHeatmapShowTurnover();
            ek.v.o(this, 1, heatmapShowTurnover3 != null ? Boolean.valueOf(!heatmapShowTurnover3.booleanValue()) : null);
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new LiqHeatmapRemote(new LiqHeatmapRemote.Output(Boolean.valueOf(!ek.v.j(this, 0, zH)), Boolean.valueOf(!ek.v.j(this, 1, zH))), new LiqHeatmapRemote.Output(Boolean.valueOf(!ek.v.g(this, 0)), Boolean.valueOf(!ek.v.g(this, 1)))), -1, 16777215, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new LiqHeatmapRemote(new LiqHeatmapRemote.Output(Boolean.valueOf(!ek.v.j(this, 0, z10)), Boolean.valueOf(!ek.v.j(this, 1, z10))), new LiqHeatmapRemote.Output(Boolean.valueOf(!ek.v.g(this, 0)), Boolean.valueOf(!ek.v.g(this, 1)))), -1, 16777215, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("liqheatmap");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 21;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return true;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[0];
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[0];
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        String string;
        String string2;
        Resources resources;
        Resources resources2;
        KLineManager.a aVar = KLineManager.f142490O;
        Context contextW = aVar.a().w();
        if (contextW == null || (resources2 = contextW.getResources()) == null || (string = resources2.getString(R.string.kline_het_map__dialog)) == null) {
            string = aVar.a().i().getResources().getString(R.string.kline_het_map__dialog);
        }
        Context contextW2 = aVar.a().w();
        if (contextW2 == null || (resources = contextW2.getResources()) == null || (string2 = resources.getString(R.string.kline_het_map__text)) == null) {
            string2 = aVar.a().i().getResources().getString(R.string.kline_het_map__text);
        }
        return new ek.I[]{new ek.I(string, true), new ek.I(string2, true)};
    }
}
