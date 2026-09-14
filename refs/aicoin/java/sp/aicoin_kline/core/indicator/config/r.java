package sp.aicoin_kline.core.indicator.config;

import com.tencent.android.tpns.mqtt.DisconnectedBufferOptions;
import java.math.BigDecimal;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class r extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        BigDecimal bigDecimalM;
        BigDecimal bigDecimalM2;
        BigDecimal bigDecimalM3;
        BollRemote boll = chartIndicatorSetting.getBoll();
        if (boll == null) {
            return;
        }
        BollRemote.Output app_output = boll.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getBollLineColor());
            Integer bollLineWidth = app_output.getBollLineWidth();
            if (numR != null && bollLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(bollLineWidth.intValue());
            }
            Integer numR2 = ek.v.r(app_output.getUbLineColor());
            Integer ubLineWidth = app_output.getUbLineWidth();
            if (numR2 != null && ubLineWidth != null) {
                k()[1].d(numR2.intValue());
                k()[1].e(ubLineWidth.intValue());
            }
            Integer numR3 = ek.v.r(app_output.getLbLineColor());
            Integer lbLineWidth = app_output.getLbLineWidth();
            if (numR3 != null && lbLineWidth != null) {
                k()[2].d(numR3.intValue());
                k()[2].e(lbLineWidth.intValue());
            }
        }
        Integer numValueOf = null;
        if (KLineManager.f142490O.a().H()) {
            BollRemote.Input input = boll.getInput();
            if (input != null) {
                String cc2 = input.getCc();
                if (cc2 != null && (bigDecimalM3 = Ah.v.m(cc2)) != null) {
                    numValueOf = Integer.valueOf(bigDecimalM3.intValue());
                }
                ek.v.m(this, 0, numValueOf);
                ek.v.k(this, 1, input.getSd(), 2);
            }
            BollRemote.Output output = boll.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getBollDisabled());
                ek.v.l(this, 1, output.getUbDisabled());
                ek.v.l(this, 2, output.getLbDisabled());
                return;
            }
            return;
        }
        BollRemote.Input app_input = boll.getApp_input();
        if (app_input != null) {
            String cc3 = app_input.getCc();
            ek.v.m(this, 0, (cc3 == null || (bigDecimalM2 = Ah.v.m(cc3)) == null) ? null : Integer.valueOf(bigDecimalM2.intValue()));
            ek.v.k(this, 1, app_input.getSd(), 2);
        }
        BollRemote.Output app_output2 = boll.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getBollDisabled());
            ek.v.l(this, 1, app_output2.getUbDisabled());
            ek.v.l(this, 2, app_output2.getLbDisabled());
        }
        BollRemote.Input input2 = boll.getInput();
        if (input2 != null) {
            String cc4 = input2.getCc();
            if (cc4 != null && (bigDecimalM = Ah.v.m(cc4)) != null) {
                numValueOf = Integer.valueOf(bigDecimalM.intValue());
            }
            ek.v.p(this, 0, numValueOf);
            ek.v.n(this, 1, input2.getSd(), 2);
        }
        BollRemote.Output output2 = boll.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getBollDisabled());
            ek.v.o(this, 1, output2.getUbDisabled());
            ek.v.o(this, 2, output2.getLbDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        BollRemote.Input input = new BollRemote.Input(String.valueOf(ek.v.i(this, 0, zH)), ek.v.h(this, 1, zH));
        BollRemote.Output output = new BollRemote.Output(null, null, null, Boolean.valueOf(ek.v.j(this, 0, zH)), null, Boolean.valueOf(ek.v.j(this, 1, zH)), null, null, Boolean.valueOf(ek.v.j(this, 2, zH)), null, null, 1751, null);
        String strQ = ek.v.q(k()[0].a());
        String strQ2 = ek.v.q(k()[1].a());
        String strQ3 = ek.v.q(k()[2].a());
        int iB = (int) k()[0].b();
        int iB2 = (int) k()[1].b();
        int iB3 = (int) k()[2].b();
        return new ChartIndicatorSetting(new BollRemote(input, output, new BollRemote.Output(null, null, strQ, Boolean.valueOf(ek.v.g(this, 0)), strQ2, Boolean.valueOf(ek.v.g(this, 1)), strQ3, Integer.valueOf(iB), Boolean.valueOf(ek.v.g(this, 2)), Integer.valueOf(iB2), Integer.valueOf(iB3), 3, null), new BollRemote.Input(String.valueOf(ek.v.f(this, 0)), String.valueOf(ek.v.f(this, 1)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -2, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        BollRemote.Input input = new BollRemote.Input(String.valueOf(ek.v.i(this, 0, z10)), ek.v.h(this, 1, z10));
        BollRemote.Output output = new BollRemote.Output(null, null, null, Boolean.valueOf(ek.v.j(this, 0, z10)), null, Boolean.valueOf(ek.v.j(this, 1, z10)), null, null, Boolean.valueOf(ek.v.j(this, 2, z10)), null, null, 1751, null);
        String strQ = ek.v.q(k()[0].a());
        String strQ2 = ek.v.q(k()[1].a());
        String strQ3 = ek.v.q(k()[2].a());
        int iB = (int) k()[0].b();
        int iB2 = (int) k()[1].b();
        int iB3 = (int) k()[2].b();
        return new ChartIndicatorSetting(new BollRemote(input, output, new BollRemote.Output(null, null, strQ, Boolean.valueOf(ek.v.j(this, 0, z10)), strQ2, Boolean.valueOf(ek.v.j(this, 1, z10)), strQ3, Integer.valueOf(iB), Boolean.valueOf(ek.v.j(this, 2, z10)), Integer.valueOf(iB2), Integer.valueOf(iB3), 3, null), new BollRemote.Input(String.valueOf(ek.v.i(this, 0, z10)), ek.v.h(this, 1, z10))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -2, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("boll");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 28;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("MID", -13643086, 0.0f, 4, null), new ek.m("UP", -19456, 0.0f, 4, null), new ek.m("LOW", -1553991, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("MID_CYCLE", new p292ng.g(0, DisconnectedBufferOptions.DISCONNECTED_BUFFER_SIZE_DEFAULT), 20, false, 0, 24, null), new ek.w("BOLL_BAND_WIDTH", new p292ng.g(0, 50), 2, false, 2, 8, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("MID", false, 2, null), new ek.I("UP", false, 2, null), new ek.I("LOW", false, 2, null)};
    }
}
