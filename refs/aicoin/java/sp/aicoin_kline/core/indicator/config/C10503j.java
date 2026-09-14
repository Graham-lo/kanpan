package sp.aicoin_kline.core.indicator.config;

import com.tencent.tpns.baseapi.base.util.ErrCode;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: sp.aicoin_kline.core.indicator.config.j, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C10503j extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        AlligatorRemote alligator = chartIndicatorSetting.getAlligator();
        if (alligator == null) {
            return;
        }
        AlligatorRemote.Output app_output = alligator.getApp_output();
        if (app_output != null) {
            Integer numR = ek.v.r(app_output.getJawLineColor());
            Integer jawLineWidth = app_output.getJawLineWidth();
            if (numR != null && jawLineWidth != null) {
                k()[0].d(numR.intValue());
                k()[0].e(jawLineWidth.intValue());
            }
            Integer numR2 = ek.v.r(app_output.getLipsLineColor());
            Integer lipsLineWidth = app_output.getLipsLineWidth();
            if (numR2 != null && lipsLineWidth != null) {
                k()[1].d(numR2.intValue());
                k()[1].e(lipsLineWidth.intValue());
            }
            Integer numR3 = ek.v.r(app_output.getTeethLineColor());
            Integer teethLineWidth = app_output.getTeethLineWidth();
            if (numR3 != null && teethLineWidth != null) {
                k()[2].d(numR3.intValue());
                k()[2].e(teethLineWidth.intValue());
            }
        }
        if (KLineManager.f142490O.a().H()) {
            AlligatorRemote.Input input = alligator.getInput();
            if (input != null) {
                ek.v.m(this, 0, input.getJawCycle());
                ek.v.m(this, 1, input.getTeethCycle());
                ek.v.m(this, 2, input.getLipsCycle());
                ek.v.m(this, 3, input.getJawOffset());
                ek.v.m(this, 4, input.getTeethOffset());
                ek.v.m(this, 5, input.getLipsOffset());
            }
            AlligatorRemote.Output output = alligator.getOutput();
            if (output != null) {
                ek.v.l(this, 0, output.getJawDisabled());
                ek.v.l(this, 1, output.getTeethDisabled());
                ek.v.l(this, 2, output.getLipsDisabled());
                return;
            }
            return;
        }
        AlligatorRemote.Input input2 = alligator.getInput();
        if (input2 != null) {
            ek.v.m(this, 0, input2.getJawCycle());
            ek.v.m(this, 1, input2.getTeethCycle());
            ek.v.m(this, 2, input2.getLipsCycle());
            ek.v.m(this, 3, input2.getJawOffset());
            ek.v.m(this, 4, input2.getTeethOffset());
            ek.v.m(this, 5, input2.getLipsOffset());
        }
        AlligatorRemote.Output output2 = alligator.getOutput();
        if (output2 != null) {
            ek.v.l(this, 0, output2.getJawDisabled());
            ek.v.l(this, 1, output2.getTeethDisabled());
            ek.v.l(this, 2, output2.getLipsDisabled());
        }
        AlligatorRemote.Input input3 = alligator.getInput();
        if (input3 != null) {
            ek.v.p(this, 0, input3.getJawCycle());
            ek.v.p(this, 1, input3.getTeethCycle());
            ek.v.p(this, 2, input3.getLipsCycle());
            ek.v.p(this, 3, input3.getJawOffset());
            ek.v.p(this, 4, input3.getTeethOffset());
            ek.v.p(this, 5, input3.getLipsOffset());
        }
        AlligatorRemote.Output output3 = alligator.getOutput();
        if (output3 != null) {
            ek.v.o(this, 0, output3.getJawDisabled());
            ek.v.o(this, 1, output3.getTeethDisabled());
            ek.v.o(this, 2, output3.getLipsDisabled());
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        int i10 = ek.v.i(this, 0, zH);
        int i11 = ek.v.i(this, 1, zH);
        int i12 = ek.v.i(this, 2, zH);
        int i13 = ek.v.i(this, 3, zH);
        int i14 = ek.v.i(this, 4, zH);
        AlligatorRemote.Input input = new AlligatorRemote.Input(Integer.valueOf(i10), Integer.valueOf(i13), Integer.valueOf(i12), Integer.valueOf(ek.v.i(this, 5, zH)), Integer.valueOf(i11), Integer.valueOf(i14));
        boolean zJ = ek.v.j(this, 0, zH);
        boolean zJ2 = ek.v.j(this, 1, zH);
        AlligatorRemote.Output output = new AlligatorRemote.Output(Boolean.valueOf(zJ), null, null, Boolean.valueOf(ek.v.j(this, 2, zH)), null, null, Boolean.valueOf(zJ2), null, null, 438, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        String strQ3 = ek.v.q(k()[2].a());
        int iB3 = (int) k()[2].b();
        boolean zG = ek.v.g(this, 0);
        boolean zG2 = ek.v.g(this, 1);
        AlligatorRemote.Output output2 = new AlligatorRemote.Output(Boolean.valueOf(zG), strQ, Integer.valueOf(iB), Boolean.valueOf(ek.v.g(this, 2)), strQ2, Integer.valueOf(iB2), Boolean.valueOf(zG2), strQ3, Integer.valueOf(iB3));
        int iF = ek.v.f(this, 0);
        int iF2 = ek.v.f(this, 1);
        int iF3 = ek.v.f(this, 2);
        int iF4 = ek.v.f(this, 3);
        int iF5 = ek.v.f(this, 4);
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, new AlligatorRemote(input, output, output2, new AlligatorRemote.Input(Integer.valueOf(iF), Integer.valueOf(iF4), Integer.valueOf(iF3), Integer.valueOf(ek.v.f(this, 5)), Integer.valueOf(iF2), Integer.valueOf(iF5))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, ErrCode.GUID_HTTP_REQ_ERROR_CONNECT, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        int i10 = ek.v.i(this, 0, z10);
        int i11 = ek.v.i(this, 1, z10);
        int i12 = ek.v.i(this, 2, z10);
        int i13 = ek.v.i(this, 3, z10);
        int i14 = ek.v.i(this, 4, z10);
        AlligatorRemote.Input input = new AlligatorRemote.Input(Integer.valueOf(i10), Integer.valueOf(i13), Integer.valueOf(i12), Integer.valueOf(ek.v.i(this, 5, z10)), Integer.valueOf(i11), Integer.valueOf(i14));
        boolean zJ = ek.v.j(this, 0, z10);
        boolean zJ2 = ek.v.j(this, 1, z10);
        AlligatorRemote.Output output = new AlligatorRemote.Output(Boolean.valueOf(zJ), null, null, Boolean.valueOf(ek.v.j(this, 2, z10)), null, null, Boolean.valueOf(zJ2), null, null, 438, null);
        String strQ = ek.v.q(k()[0].a());
        int iB = (int) k()[0].b();
        String strQ2 = ek.v.q(k()[1].a());
        int iB2 = (int) k()[1].b();
        String strQ3 = ek.v.q(k()[2].a());
        int iB3 = (int) k()[2].b();
        boolean zJ3 = ek.v.j(this, 0, z10);
        boolean zJ4 = ek.v.j(this, 1, z10);
        AlligatorRemote.Output output2 = new AlligatorRemote.Output(Boolean.valueOf(zJ3), strQ, Integer.valueOf(iB), Boolean.valueOf(ek.v.j(this, 2, z10)), strQ2, Integer.valueOf(iB2), Boolean.valueOf(zJ4), strQ3, Integer.valueOf(iB3));
        int i15 = ek.v.i(this, 0, z10);
        int i16 = ek.v.i(this, 1, z10);
        int i17 = ek.v.i(this, 2, z10);
        int i18 = ek.v.i(this, 3, z10);
        int i19 = ek.v.i(this, 4, z10);
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, new AlligatorRemote(input, output, output2, new AlligatorRemote.Input(Integer.valueOf(i15), Integer.valueOf(i18), Integer.valueOf(i17), Integer.valueOf(ek.v.i(this, 5, z10)), Integer.valueOf(i16), Integer.valueOf(i19))), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, ErrCode.GUID_HTTP_REQ_ERROR_CONNECT, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("alligator");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 7;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return true;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("JAW", -13643086, 0.0f, 4, null), new ek.m("TEETH", -19456, 0.0f, 4, null), new ek.m("LIPS", -1553991, 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        return new ek.w[]{new ek.w("Jaw Length", new p292ng.g(0, 100), 13, false, 0, 24, null), new ek.w("Teeth Length", new p292ng.g(0, 100), 8, false, 0, 24, null), new ek.w("Lips Length", new p292ng.g(0, 100), 5, false, 0, 24, null), new ek.w("Jaw Offset", new p292ng.g(0, 100), 8, false, 0, 24, null), new ek.w("Teeth Offset", new p292ng.g(0, 100), 5, false, 0, 24, null), new ek.w("Lips Offset", new p292ng.g(0, 100), 3, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        return new ek.I[]{new ek.I("JAW", false, 2, null), new ek.I("TEETH", false, 2, null), new ek.I("LIPS", false, 2, null)};
    }
}
