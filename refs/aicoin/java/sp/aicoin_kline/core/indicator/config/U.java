package sp.aicoin_kline.core.indicator.config;

import com.tencent.wcdb.FileUtils;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class U extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        ROCRemote roc = chartIndicatorSetting.getRoc();
        if (roc == null) {
            return;
        }
        ROCRemote.Output app_output = roc.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getRocLineColor());
            Integer rocLineWidth = app_output.getRocLineWidth();
            if (numR != null && rocLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(rocLineWidth.intValue());
            }
            Integer numR2 = ek.v.r(app_output.getMaRocLineColor());
            Integer maRocLineWidth = app_output.getMaRocLineWidth();
            if (numR2 != null && maRocLineWidth != null) {
                k()[1].d(numR2.intValue());
                k()[1].e(maRocLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            ROCRemote.Input input = roc.getInput();
            if (input != null) {
                ek.v.m(this, 0, input.getCc());
                ek.v.m(this, 1, input.getMac());
            }
            ROCRemote.Output output = roc.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getRocDisabled());
                ek.v.l(this, 1, output.getMaRocDisabled());
                return;
            }
            return;
        }
        ROCRemote.Input app_input = roc.getApp_input();
        if (app_input != null) {
            ek.v.m(this, 0, app_input.getCc());
            ek.v.m(this, 1, app_input.getMac());
        }
        ROCRemote.Output app_output2 = roc.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getRocDisabled());
            ek.v.l(this, 1, app_output2.getMaRocDisabled());
        }
        ROCRemote.Input input2 = roc.getInput();
        if (input2 != null) {
            ek.v.p(this, 0, input2.getCc());
            ek.v.p(this, 1, input2.getMac());
        }
        ROCRemote.Output output2 = roc.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getRocDisabled());
            ek.v.o(this, 1, output2.getMaRocDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        ROCRemote.Input input = new ROCRemote.Input(Integer.valueOf(ek.v.i(this, 0, zH)), Integer.valueOf(ek.v.i(this, 1, zH)));
        ROCRemote.Output output = new ROCRemote.Output(Boolean.valueOf(ek.v.j(this, 1, zH)), null, null, Boolean.valueOf(ek.v.j(this, 0, zH)), null, null, null, null, null, 502, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new ROCRemote(input, output, new ROCRemote.Output(Boolean.valueOf(ek.v.g(this, 1)), ek.v.q(k()[1].a()), Integer.valueOf((int) k()[1].b()), Boolean.valueOf(ek.v.g(this, 0)), strQ, Integer.valueOf(iB), null, null, null, FileUtils.S_IRWXU, null), new ROCRemote.Input(Integer.valueOf(ek.v.f(this, 0)), Integer.valueOf(ek.v.f(this, 1)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -2097153, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        ROCRemote.Input input = new ROCRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)), Integer.valueOf(ek.v.i(this, 1, z10)));
        ROCRemote.Output output = new ROCRemote.Output(Boolean.valueOf(ek.v.j(this, 1, z10)), null, null, Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, null, null, null, 502, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new ROCRemote(input, output, new ROCRemote.Output(Boolean.valueOf(ek.v.j(this, 1, z10)), ek.v.q(k()[1].a()), Integer.valueOf((int) k()[1].b()), Boolean.valueOf(ek.v.j(this, 0, z10)), strQ, Integer.valueOf(iB), null, null, null, FileUtils.S_IRWXU, null), new ROCRemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)), Integer.valueOf(ek.v.i(this, 1, z10)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -2097153, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("roc");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 9;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("ROC", -13643086, 0.0f, 4, null), new ek.m("MAROC", -19456, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("ROC", new p292ng.g(0, 120), 12, false, 0, 24, null), new ek.w("MAROC", new p292ng.g(0, 60), 6, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("ROC", false, 2, null), new ek.I("MAROC", false, 2, null)};
    }
}
