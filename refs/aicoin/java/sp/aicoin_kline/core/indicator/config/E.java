package sp.aicoin_kline.core.indicator.config;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class E extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        IchimokuRemote ichimoku = chartIndicatorSetting.getIchimoku();
        if (ichimoku == null) {
            return;
        }
        IchimokuRemote.Output app_output = ichimoku.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getConversion_lineColor());
            Integer conversion_lineWidth = app_output.getConversion_lineWidth();
            if (numR != null && conversion_lineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(conversion_lineWidth.intValue());
            }
            Integer numR2 = ek.v.r(app_output.getBase_lineColor());
            Integer base_lineWidth = app_output.getBase_lineWidth();
            if (numR2 != null && base_lineWidth != null) {
                k()[1].d(numR2.intValue());
                k()[1].e(base_lineWidth.intValue());
            }
            Integer numR3 = ek.v.r(app_output.getLaggingSpan_lineColor());
            Integer laggingSpan_lineWidth = app_output.getLaggingSpan_lineWidth();
            if (numR3 != null && laggingSpan_lineWidth != null) {
                k()[2].d(numR3.intValue());
                k()[2].e(laggingSpan_lineWidth.intValue());
            }
            Integer numR4 = ek.v.r(app_output.getLead1_lineColor());
            Integer lead1_lineWidth = app_output.getLead1_lineWidth();
            if (numR4 != null && lead1_lineWidth != null) {
                k()[3].d(numR4.intValue());
                k()[3].e(lead1_lineWidth.intValue());
            }
            Integer numR5 = ek.v.r(app_output.getLead2_lineColor());
            Integer lead2_lineWidth = app_output.getLead2_lineWidth();
            if (numR5 != null && lead2_lineWidth != null) {
                k()[4].d(numR5.intValue());
                k()[4].e(lead2_lineWidth.intValue());
            }
            Integer numR6 = ek.v.r(app_output.getRising_background());
            if (numR6 != null) {
                k()[5].d(numR6.intValue());
            }
            Integer numR7 = ek.v.r(app_output.getFalling_background());
            if (numR7 != null) {
                k()[6].d(numR7.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            IchimokuRemote.Input input = ichimoku.getInput();
            if (input != null) {
                ek.v.m(this, 0, input.getConversionCycle());
                ek.v.m(this, 1, input.getBaseCycle());
                ek.v.m(this, 2, input.getLaggingSpan2Cycle());
                ek.v.m(this, 3, Integer.valueOf(input.getDisplacement()));
            }
            IchimokuRemote.Output output = ichimoku.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getConversionDisabled());
                ek.v.l(this, 1, output.getBaseDisabled());
                ek.v.l(this, 2, output.getLaggingSpanDisabled());
                ek.v.l(this, 3, output.getLead1Disabled());
                ek.v.l(this, 4, output.getLead2Disabled());
                return;
            }
            return;
        }
        IchimokuRemote.Input app_input = ichimoku.getApp_input();
        if (app_input != null) {
            ek.v.m(this, 0, app_input.getConversionCycle());
            ek.v.m(this, 1, app_input.getBaseCycle());
            ek.v.m(this, 2, app_input.getLaggingSpan2Cycle());
            ek.v.m(this, 3, Integer.valueOf(app_input.getDisplacement()));
        }
        IchimokuRemote.Output app_output2 = ichimoku.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getConversionDisabled());
            ek.v.l(this, 1, app_output2.getBaseDisabled());
            ek.v.l(this, 2, app_output2.getLaggingSpanDisabled());
            ek.v.l(this, 3, app_output2.getLead1Disabled());
            ek.v.l(this, 4, app_output2.getLead2Disabled());
        }
        IchimokuRemote.Input input2 = ichimoku.getInput();
        if (input2 != null) {
            ek.v.p(this, 0, input2.getConversionCycle());
            ek.v.p(this, 1, input2.getBaseCycle());
            ek.v.p(this, 2, input2.getLaggingSpan2Cycle());
            ek.v.p(this, 3, Integer.valueOf(input2.getDisplacement()));
        }
        IchimokuRemote.Output output2 = ichimoku.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getConversionDisabled());
            ek.v.o(this, 1, output2.getBaseDisabled());
            ek.v.o(this, 2, output2.getLaggingSpanDisabled());
            ek.v.o(this, 3, output2.getLead1Disabled());
            ek.v.o(this, 4, output2.getLead2Disabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        IchimokuRemote.Input input = new IchimokuRemote.Input(Integer.valueOf(ek.v.i(this, 0, zH)), Integer.valueOf(ek.v.i(this, 1, zH)), Integer.valueOf(ek.v.i(this, 2, zH)), ek.v.i(this, 3, zH));
        IchimokuRemote.Output output = new IchimokuRemote.Output(Boolean.valueOf(ek.v.j(this, 0, zH)), null, null, Boolean.valueOf(ek.v.j(this, 1, zH)), null, null, Boolean.valueOf(ek.v.j(this, 2, zH)), null, null, Boolean.valueOf(ek.v.j(this, 3, zH)), null, null, Boolean.valueOf(ek.v.j(this, 4, zH)), null, null, null, null, 126390, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        String strQ3 = ek.v.q(k()[2].a());
        int iB3 = (int) k()[2].b();
        String strQ4 = ek.v.q(k()[3].a());
        int iB4 = (int) k()[3].b();
        String strQ5 = ek.v.q(k()[4].a());
        int iB5 = (int) k()[4].b();
        boolean zG = ek.v.g(this, 0);
        boolean zG2 = ek.v.g(this, 1);
        boolean zG3 = ek.v.g(this, 2);
        boolean zG4 = ek.v.g(this, 3);
        boolean zG5 = ek.v.g(this, 4);
        return new ChartIndicatorSetting(null, null, null, null, new IchimokuRemote(input, output, new IchimokuRemote.Output(Boolean.valueOf(zG), Integer.valueOf(iB), strQ, Boolean.valueOf(zG2), Integer.valueOf(iB2), strQ2, Boolean.valueOf(zG3), Integer.valueOf(iB3), strQ3, Boolean.valueOf(zG4), Integer.valueOf(iB4), strQ4, Boolean.valueOf(zG5), Integer.valueOf(iB5), strQ5, ek.v.q(k()[5].a()), ek.v.q(k()[6].a())), new IchimokuRemote.Input(Integer.valueOf(ek.v.f(this, 0)), Integer.valueOf(ek.v.f(this, 1)), Integer.valueOf(ek.v.f(this, 2)), ek.v.f(this, 3))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -17, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        IchimokuRemote.Input input = new IchimokuRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)), Integer.valueOf(ek.v.i(this, 1, z10)), Integer.valueOf(ek.v.i(this, 2, z10)), ek.v.i(this, 3, z10));
        IchimokuRemote.Output output = new IchimokuRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, Boolean.valueOf(ek.v.j(this, 1, z10)), null, null, Boolean.valueOf(ek.v.j(this, 2, z10)), null, null, Boolean.valueOf(ek.v.j(this, 3, z10)), null, null, Boolean.valueOf(ek.v.j(this, 4, z10)), null, null, null, null, 126390, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        String strQ3 = ek.v.q(k()[2].a());
        int iB3 = (int) k()[2].b();
        String strQ4 = ek.v.q(k()[3].a());
        int iB4 = (int) k()[3].b();
        String strQ5 = ek.v.q(k()[4].a());
        int iB5 = (int) k()[4].b();
        boolean zJ = ek.v.j(this, 0, z10);
        boolean zJ2 = ek.v.j(this, 1, z10);
        boolean zJ3 = ek.v.j(this, 2, z10);
        boolean zJ4 = ek.v.j(this, 3, z10);
        boolean zJ5 = ek.v.j(this, 4, z10);
        return new ChartIndicatorSetting(null, null, null, null, new IchimokuRemote(input, output, new IchimokuRemote.Output(Boolean.valueOf(zJ), Integer.valueOf(iB), strQ, Boolean.valueOf(zJ2), Integer.valueOf(iB2), strQ2, Boolean.valueOf(zJ3), Integer.valueOf(iB3), strQ3, Boolean.valueOf(zJ4), Integer.valueOf(iB4), strQ4, Boolean.valueOf(zJ5), Integer.valueOf(iB5), strQ5, ek.v.q(k()[5].a()), ek.v.q(k()[6].a())), new IchimokuRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)), Integer.valueOf(ek.v.i(this, 1, z10)), Integer.valueOf(ek.v.i(this, 2, z10)), ek.v.i(this, 3, z10))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -17, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("ichimoku");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 8;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return true;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("Conversion", -9777229, 0.0f, 4, null), new ek.m("Base", -2861387, 0.0f, 4, null), new ek.m("Lagging Span", -805297, 0.0f, 4, null), new ek.m("Lead 1", -44124268, 0.0f, 4, null), new ek.m("Lead 2", -2468007, 0.0f, 4, null), new ek.m("Rising Background", 858772146, 0.0f, 4, null), new ek.m("Falling Background", 854940504, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("Conversion Line Periods", new p292ng.g(0, 1000), 9, false, 0, 24, null), new ek.w("Base Line Periods", new p292ng.g(0, 1000), 26, false, 0, 24, null), new ek.w("Lagging Span 2 Periods", new p292ng.g(0, 1000), 52, false, 0, 24, null), new ek.w("Displacement", new p292ng.g(0, 1000), 26, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("Conversion", false, 2, null), new ek.I("Base", false, 2, null), new ek.I("Lagging Span", false, 2, null), new ek.I("Lead 1", false, 2, null), new ek.I("Lead 2", false, 2, null), new ek.I("Rising Background", false, 2, null), new ek.I("Falling Background", false, 2, null)};
    }
}
