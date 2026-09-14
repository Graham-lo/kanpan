package sp.aicoin_kline.core.indicator.config;

import com.tencent.wcdb.FileUtils;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: sp.aicoin_kline.core.indicator.config.t, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C10512t extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        DPORemote dpo = chartIndicatorSetting.getDpo();
        if (dpo == null) {
            return;
        }
        DPORemote.Output app_output = dpo.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getDpoLineColor());
            Integer dpoLineWidth = app_output.getDpoLineWidth();
            if (numR != null && dpoLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(dpoLineWidth.intValue());
            }
            Integer numR2 = ek.v.r(app_output.getMaDpoLineColor());
            Integer maDpoLineWidth = app_output.getMaDpoLineWidth();
            if (numR2 != null && maDpoLineWidth != null) {
                k()[1].d(numR2.intValue());
                k()[1].e(maDpoLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            DPORemote.Input input = dpo.getInput();
            if (input != null) {
                ek.v.m(this, 0, input.getCc());
                ek.v.m(this, 1, input.getMac());
            }
            DPORemote.Output output = dpo.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getDpoDisabled());
                ek.v.l(this, 1, output.getMaDpoDisabled());
                return;
            }
            return;
        }
        DPORemote.Input app_input = dpo.getApp_input();
        if (app_input != null) {
            ek.v.m(this, 0, app_input.getCc());
            ek.v.m(this, 1, app_input.getMac());
        }
        DPORemote.Output app_output2 = dpo.getApp_output();
        if (app_output2 != null) {
            ek.v.l(this, 0, app_output2.getDpoDisabled());
            ek.v.l(this, 1, app_output2.getMaDpoDisabled());
        }
        DPORemote.Input input2 = dpo.getInput();
        if (input2 != null) {
            ek.v.p(this, 0, input2.getCc());
            ek.v.p(this, 1, input2.getMac());
        }
        DPORemote.Output output2 = dpo.getOutput();
        if (output2 != null) {
            ek.v.o(this, 0, output2.getDpoDisabled());
            ek.v.o(this, 1, output2.getMaDpoDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        DPORemote.Input input = new DPORemote.Input(Integer.valueOf(ek.v.i(this, 0, zH)), Integer.valueOf(ek.v.i(this, 1, zH)));
        DPORemote.Output output = new DPORemote.Output(Boolean.valueOf(ek.v.j(this, 0, zH)), null, null, Boolean.valueOf(ek.v.j(this, 1, zH)), null, null, null, null, null, 502, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new DPORemote(input, output, new DPORemote.Output(Boolean.valueOf(ek.v.g(this, 0)), strQ, Integer.valueOf(iB), Boolean.valueOf(ek.v.g(this, 1)), strQ2, Integer.valueOf(iB2), null, null, null, FileUtils.S_IRWXU, null), new DPORemote.Input(Integer.valueOf(ek.v.f(this, 0)), Integer.valueOf(ek.v.f(this, 1)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1, 33554303, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        DPORemote.Input input = new DPORemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)), Integer.valueOf(ek.v.i(this, 1, z10)));
        DPORemote.Output output = new DPORemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), null, null, Boolean.valueOf(ek.v.j(this, 1, z10)), null, null, null, null, null, 502, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new DPORemote(input, output, new DPORemote.Output(Boolean.valueOf(ek.v.j(this, 0, z10)), strQ, Integer.valueOf(iB), Boolean.valueOf(ek.v.j(this, 1, z10)), strQ2, Integer.valueOf(iB2), null, null, null, FileUtils.S_IRWXU, null), new DPORemote.Input(Integer.valueOf(ek.v.i(this, 0, z10)), Integer.valueOf(ek.v.i(this, 1, z10)))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -1, 33554303, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("dpo");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 29;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("DPO", -13643086, 0.0f, 4, null), new ek.m("MADPO", -19456, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("N", new p292ng.g(0, 1000), 21, false, 0, 24, null), new ek.w("MA", new p292ng.g(0, 1000), 6, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("DPO", false, 2, null), new ek.I("MADPO", false, 2, null)};
    }
}
