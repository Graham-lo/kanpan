package sp.aicoin_kline.core.indicator.config;

import com.tencent.android.tpush.XGPushManager;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: sp.aicoin_kline.core.indicator.config.s, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C10511s extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        CCIRemote cci = chartIndicatorSetting.getCci();
        if (cci == null) {
            return;
        }
        CCIRemote.Output app_output = cci.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getCciLineColor());
            Integer cciLineWidth = app_output.getCciLineWidth();
            if (numR != null && cciLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(cciLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            CCIRemote.Input input = cci.getInput();
            if (input != null) {
                ek.v.m(this, 0, input.getCc());
                ek.v.m(this, 1, input.getUpperBand());
                ek.v.m(this, 2, input.getLowerBand());
            }
            CCIRemote.Output output = cci.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getCciDisabled());
                return;
            }
            return;
        }
        CCIRemote.Input app_input = cci.getApp_input();
        if (app_input != null) {
            ek.v.m(this, 0, app_input.getCc());
            ek.v.m(this, 1, app_input.getUpperBand());
            ek.v.m(this, 2, app_input.getLowerBand());
        }
        CCIRemote.Output app_output2 = cci.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getCciDisabled());
        }
        CCIRemote.Input input2 = cci.getInput();
        if (input2 != null) {
            ek.v.p(this, 0, input2.getCc());
            ek.v.p(this, 1, input2.getUpperBand());
            ek.v.p(this, 2, input2.getLowerBand());
        }
        CCIRemote.Output output2 = cci.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getCciDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        int i10 = ek.v.i(this, 0, zH);
        int i11 = ek.v.i(this, 1, zH);
        CCIRemote.Input input = new CCIRemote.Input(Integer.valueOf(i10), Integer.valueOf(ek.v.i(this, 2, zH)), Integer.valueOf(i11));
        CCIRemote.Output output = new CCIRemote.Output(null, null, Boolean.valueOf(ek.v.j(this, 0, zH)), null, null, null, null, null, null, null, null, 2043, null);
        CCIRemote.Output output2 = new CCIRemote.Output(null, null, Boolean.valueOf(ek.v.g(this, 0)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b()), null, null, null, null, null, null, 2019, null);
        int iF = ek.v.f(this, 0);
        int iF2 = ek.v.f(this, 1);
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new CCIRemote(input, output, output2, new CCIRemote.Input(Integer.valueOf(iF), Integer.valueOf(ek.v.f(this, 2)), Integer.valueOf(iF2))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1048577, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        int i10 = ek.v.i(this, 0, z10);
        int i11 = ek.v.i(this, 1, z10);
        CCIRemote.Input input = new CCIRemote.Input(Integer.valueOf(i10), Integer.valueOf(ek.v.i(this, 2, z10)), Integer.valueOf(i11));
        CCIRemote.Output output = new CCIRemote.Output(null, null, Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, null, null, null, null, null, null, 2043, null);
        CCIRemote.Output output2 = new CCIRemote.Output(null, null, Boolean.valueOf(ek.v.j(this, 0, z10)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b()), null, null, null, null, null, null, 2019, null);
        int i12 = ek.v.i(this, 0, z10);
        int i13 = ek.v.i(this, 1, z10);
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new CCIRemote(input, output, output2, new CCIRemote.Input(Integer.valueOf(i12), Integer.valueOf(ek.v.i(this, 2, z10)), Integer.valueOf(i13))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1048577, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("cci");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 8;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("CCI", -13643086, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("CCI", new p292ng.g(0, 1000), 20, false, 0, 24, null), new ek.w("CEILING", new p292ng.g(-500, XGPushManager.MAX_TAG_SIZE), 100, false, 0, 24, null), new ek.w("FLOOR", new p292ng.g(-500, XGPushManager.MAX_TAG_SIZE), -100, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("CCI", false, 2, null)};
    }
}
