package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: sp.aicoin_kline.core.indicator.config.f, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C10499f extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        AiNetVolRemote ainetvol = chartIndicatorSetting.getAinetvol();
        if (ainetvol == null) {
            return;
        }
        AiNetVolRemote.Output app_output = ainetvol.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getVolLineColor());
            Integer volLineWidth = app_output.getVolLineWidth();
            if (numR != null && volLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(volLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            AiNetVolRemote.Output output = ainetvol.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getVolDisabled());
                return;
            }
            return;
        }
        AiNetVolRemote.Output app_output2 = ainetvol.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getVolDisabled());
        }
        AiNetVolRemote.Output output2 = ainetvol.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getVolDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new AiNetVolRemote(new AiNetVolRemote.Output(Boolean.valueOf(ek.v.j(this, 0, KLineManager.f142490O.a().H())), null, null, 6, null), new AiNetVolRemote.Output(Boolean.valueOf(ek.v.g(this, 0)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b()))), null, null, null, null, null, -1, 33030143, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new AiNetVolRemote(new AiNetVolRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, 6, null), new AiNetVolRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b()))), null, null, null, null, null, -1, 33030143, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("ai-netvol");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 41;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("AI-NetVOL", -13643086, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[0];
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("AI-NetVOL", false, 2, null)};
    }
}
