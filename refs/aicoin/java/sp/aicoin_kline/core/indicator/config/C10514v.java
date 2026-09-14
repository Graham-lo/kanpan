package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: sp.aicoin_kline.core.indicator.config.v, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C10514v extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        DmaRemote dma = chartIndicatorSetting.getDma();
        if (dma == null) {
            return;
        }
        DmaRemote.Output app_output = dma.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getDmaLineColor());
            Integer dmaLineWidth = app_output.getDmaLineWidth();
            if (numR != null && dmaLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(dmaLineWidth.intValue());
            }
            Integer numR2 = ek.v.r(app_output.getAmaLineColor());
            Integer amaLineWidth = app_output.getAmaLineWidth();
            if (numR2 != null && amaLineWidth != null) {
                k()[1].d(numR2.intValue());
                k()[1].e(amaLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            DmaRemote.Input input = dma.getInput();
            if (input != null) {
                ek.v.m(this, 0, input.getSc());
                ek.v.m(this, 1, input.getLc());
                ek.v.m(this, 2, input.getMac());
            }
            DmaRemote.Output output = dma.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getDmaDisabled());
                ek.v.l(this, 1, output.getAmaDisabled());
                return;
            }
            return;
        }
        DmaRemote.Input app_input = dma.getApp_input();
        if (app_input != null) {
            ek.v.m(this, 0, app_input.getSc());
            ek.v.m(this, 1, app_input.getLc());
            ek.v.m(this, 2, app_input.getMac());
        }
        DmaRemote.Output app_output2 = dma.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getDmaDisabled());
            ek.v.l(this, 1, app_output2.getAmaDisabled());
        }
        DmaRemote.Input input2 = dma.getInput();
        if (input2 != null) {
            ek.v.p(this, 0, input2.getSc());
            ek.v.p(this, 1, input2.getLc());
            ek.v.p(this, 2, input2.getMac());
        }
        DmaRemote.Output output2 = dma.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getDmaDisabled());
            ek.v.o(this, 1, output2.getAmaDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        int i10 = ek.v.i(this, 0, zH);
        DmaRemote.Input input = new DmaRemote.Input(Integer.valueOf(ek.v.i(this, 1, zH)), Integer.valueOf(ek.v.i(this, 2, zH)), Integer.valueOf(i10));
        DmaRemote.Output output = new DmaRemote.Output(Boolean.valueOf(ek.v.j(this, 1, zH)), null, null, Boolean.valueOf(ek.v.j(this, 0, zH)), null, null, 54, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        DmaRemote.Output output2 = new DmaRemote.Output(Boolean.valueOf(ek.v.g(this, 1)), ek.v.q(k()[1].a()), Integer.valueOf((int) k()[1].b()), Boolean.valueOf(ek.v.g(this, 0)), strQ, Integer.valueOf(iB));
        int iF = ek.v.f(this, 0);
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new DmaRemote(input, output, output2, new DmaRemote.Input(Integer.valueOf(ek.v.f(this, 1)), Integer.valueOf(ek.v.f(this, 2)), Integer.valueOf(iF))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -536870913, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("dma");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 19;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("DMA", -13643086, 0.0f, 4, null), new ek.m("AMA", -19456, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("SHORT", new p292ng.g(0, 60), 10, false, 0, 24, null), new ek.w("LONG", new p292ng.g(0, androidx.recyclerview.widget.l.e.DEFAULT_SWIPE_ANIMATION_DURATION), 50, false, 0, 24, null), new ek.w("MA", new p292ng.g(0, 100), 10, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("DMA", false, 2, null), new ek.I("AMA", false, 2, null)};
    }
}
