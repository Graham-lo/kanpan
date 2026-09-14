package sp.aicoin_kline.core.indicator.config;

import com.davemorrissey.labs.subscaleview.SubsamplingScaleImageView;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: sp.aicoin_kline.core.indicator.config.o, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C10508o extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        BbwRemote bbw = chartIndicatorSetting.getBbw();
        if (bbw == null) {
            return;
        }
        BbwRemote.Output app_output = bbw.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getBbwLineColor());
            Integer bbwLineWidth = app_output.getBbwLineWidth();
            if (numR != null && bbwLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(bbwLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            BbwRemote.Input input = bbw.getInput();
            if (input != null) {
                ek.v.m(this, 0, input.getCc());
                ek.v.m(this, 1, input.getSd());
            }
            BbwRemote.Output output = bbw.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getBbwDisabled());
                return;
            }
            return;
        }
        BbwRemote.Input app_input = bbw.getApp_input();
        if (app_input != null) {
            ek.v.m(this, 0, app_input.getCc());
            ek.v.m(this, 1, app_input.getSd());
        }
        BbwRemote.Output app_output2 = bbw.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getBbwDisabled());
        }
        BbwRemote.Input input2 = bbw.getInput();
        if (input2 != null) {
            ek.v.p(this, 0, input2.getCc());
            ek.v.p(this, 1, input2.getSd());
        }
        BbwRemote.Output output2 = bbw.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getBbwDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new BbwRemote(new BbwRemote.Input(Integer.valueOf(ek.v.i(this, 0, zH)), Integer.valueOf(ek.v.i(this, 1, zH))), new BbwRemote.Output(Boolean.valueOf(ek.v.j(this, 0, zH)), null, null, 6, null), new BbwRemote.Output(Boolean.valueOf(ek.v.g(this, 0)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b())), new BbwRemote.Input(Integer.valueOf(ek.v.f(this, 0)), Integer.valueOf(ek.v.f(this, 1)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, SubsamplingScaleImageView.TILE_SIZE_AUTO, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new BbwRemote(new BbwRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)), Integer.valueOf(ek.v.i(this, 1, z10))), new BbwRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, 6, null), new BbwRemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), ek.v.q(k()[0].a()), Integer.valueOf((int) k()[0].b())), new BbwRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)), Integer.valueOf(ek.v.i(this, 1, z10)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, SubsamplingScaleImageView.TILE_SIZE_AUTO, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("bbw");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 21;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("BBW", -13643086, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("MID", new p292ng.g(0, 120), 20, false, 0, 24, null), new ek.w("BOLL_BAND_WIDTH", new p292ng.g(0, 50), 2, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("BBW", false, 2, null)};
    }
}
