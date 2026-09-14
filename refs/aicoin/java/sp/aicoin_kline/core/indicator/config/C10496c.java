package sp.aicoin_kline.core.indicator.config;

import android.content.Context;
import android.content.res.Resources;
import android.graphics.Color;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.R;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: sp.aicoin_kline.core.indicator.config.c, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C10496c extends F {
    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        char c10;
        VPVRRemote vpvr = chartIndicatorSetting.getVpvr();
        if (vpvr == null) {
            return;
        }
        VPVRRemote.Output app_output = vpvr.getApp_output();
        if (app_output != null) {
            ek.v.l(this, 0, app_output.getPocDisabled());
            ek.v.l(this, 1, app_output.getRange1Disabled());
            ek.v.l(this, 2, app_output.getRange2Disabled());
            Integer numR = ek.v.r(app_output.getRange1NegFill());
            Integer numR2 = ek.v.r(app_output.getRange1PosFill());
            Integer numR3 = ek.v.r(app_output.getRange2NegFill());
            Integer numR4 = ek.v.r(app_output.getRange2PosFill());
            Integer numR5 = ek.v.r(app_output.getVpNegFill());
            Integer numR6 = ek.v.r(app_output.getVpPosFill());
            Integer numR7 = ek.v.r(app_output.getPocColor());
            if (numR7 != null) {
                c10 = 6;
                k()[0].d(numR7.intValue());
            } else {
                c10 = 6;
            }
            if (numR6 != null) {
                k()[1].d(numR6.intValue());
            }
            if (numR5 != null) {
                k()[2].d(numR5.intValue());
            }
            if (numR2 != null) {
                k()[3].d(numR2.intValue());
            }
            if (numR != null) {
                k()[4].d(numR.intValue());
            }
            if (numR4 != null) {
                k()[5].d(numR4.intValue());
            }
            if (numR3 != null) {
                k()[c10].d(numR3.intValue());
            }
        } else {
            c10 = 6;
        }
        if (!KLineManager.f142490O.a().H()) {
            VPVRRemote.Input app_input = vpvr.getApp_input();
            if (app_input != null) {
                ek.v.m(this, 0, app_input.getRows());
                ek.v.m(this, 1, app_input.getRange1());
                ek.v.m(this, 2, app_input.getRange2());
            }
            VPVRRemote.Output app_output2 = vpvr.getApp_output();
            if (app_output2 != null) {
                ek.v.l(this, 0, app_output2.getPocDisabled());
                ek.v.l(this, 1, app_output2.getRange1Disabled());
                ek.v.l(this, 2, app_output2.getRange2Disabled());
            }
            VPVRRemote.Input input = vpvr.getInput();
            if (input != null) {
                ek.v.p(this, 0, input.getRows());
                ek.v.p(this, 1, input.getRange1());
                ek.v.p(this, 2, input.getRange2());
            }
            VPVRRemote.Output output = vpvr.getOutput();
            if (output != null) {
                ek.v.o(this, 0, output.getPocDisabled());
                ek.v.o(this, 1, output.getRange1Disabled());
                ek.v.o(this, 2, output.getRange2Disabled());
                return;
            }
            return;
        }
        VPVRRemote.Input input2 = vpvr.getInput();
        if (input2 != null) {
            ek.v.m(this, 0, input2.getRows());
            ek.v.m(this, 1, input2.getRange1());
            ek.v.m(this, 2, input2.getRange2());
        }
        VPVRRemote.Output output2 = vpvr.getOutput();
        if (output2 != null) {
            r()[0].d(AbstractC7609s.f(output2.getPocDisabled(), Boolean.TRUE));
            ek.v.l(this, 1, output2.getRange1Disabled());
            ek.v.l(this, 2, output2.getRange2Disabled());
            Integer numR8 = ek.v.r(output2.getRange1NegFill());
            Integer numR9 = ek.v.r(output2.getRange1PosFill());
            Integer numR10 = ek.v.r(output2.getRange2NegFill());
            Integer numR11 = ek.v.r(output2.getRange2PosFill());
            Integer numR12 = ek.v.r(output2.getVpNegFill());
            Integer numR13 = ek.v.r(output2.getVpPosFill());
            Integer numR14 = ek.v.r(output2.getPocColor());
            if (numR14 != null) {
                k()[0].d(numR14.intValue());
            }
            if (numR13 != null) {
                k()[1].d(numR13.intValue());
            }
            if (numR12 != null) {
                k()[2].d(numR12.intValue());
            }
            if (numR9 != null) {
                k()[3].d(numR9.intValue());
            }
            if (numR8 != null) {
                k()[4].d(numR8.intValue());
            }
            if (numR11 != null) {
                k()[5].d(numR11.intValue());
            }
            if (numR10 != null) {
                k()[c10].d(numR10.intValue());
            }
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        boolean zH = KLineManager.f142490O.a().H();
        VPVRRemote.Input input = new VPVRRemote.Input(Integer.valueOf(ek.v.i(this, 1, zH)), Integer.valueOf(ek.v.i(this, 2, zH)), Integer.valueOf(ek.v.i(this, 0, zH)));
        boolean zB = (zH ? r()[0] : p()[0]).b();
        boolean zJ = ek.v.j(this, 1, zH);
        boolean zJ2 = ek.v.j(this, 2, zH);
        String strQ = ek.v.q(k()[4].a());
        String strQ2 = ek.v.q(k()[3].a());
        VPVRRemote.Output output = new VPVRRemote.Output(null, Boolean.valueOf(zJ2), ek.v.q(k()[6].a()), ek.v.q(k()[5].a()), strQ, strQ2, Boolean.valueOf(zJ), null, null, Boolean.valueOf(zB), null, null, 3457, null);
        boolean zB2 = (zH ? r()[0] : p()[0]).b();
        boolean zJ3 = ek.v.j(this, 1, zH);
        boolean zJ4 = ek.v.j(this, 2, zH);
        String strQ3 = ek.v.q(k()[4].a());
        String strQ4 = ek.v.q(k()[3].a());
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new VPVRRemote(input, output, new VPVRRemote.Output(null, Boolean.valueOf(zJ4), ek.v.q(k()[6].a()), ek.v.q(k()[5].a()), strQ3, strQ4, Boolean.valueOf(zJ3), null, null, Boolean.valueOf(zB2), null, null, 3457, null), new VPVRRemote.Input(Integer.valueOf(ek.v.f(this, 1)), Integer.valueOf(ek.v.f(this, 2)), Integer.valueOf(ek.v.f(this, 0)))), null, -1, 25165823, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        VPVRRemote.Input input = new VPVRRemote.Input(Integer.valueOf(ek.v.i(this, 1, z10)), Integer.valueOf(ek.v.i(this, 2, z10)), Integer.valueOf(ek.v.i(this, 0, z10)));
        boolean zB = (z10 ? r()[0] : p()[0]).b();
        boolean zJ = ek.v.j(this, 1, z10);
        boolean zJ2 = ek.v.j(this, 2, z10);
        String strQ = ek.v.q(k()[4].a());
        String strQ2 = ek.v.q(k()[3].a());
        VPVRRemote.Output output = new VPVRRemote.Output(null, Boolean.valueOf(zJ2), ek.v.q(k()[6].a()), ek.v.q(k()[5].a()), strQ, strQ2, Boolean.valueOf(zJ), null, null, Boolean.valueOf(zB), null, null, 3457, null);
        boolean zB2 = (z10 ? r()[0] : p()[0]).b();
        boolean zJ3 = ek.v.j(this, 1, z10);
        boolean zJ4 = ek.v.j(this, 2, z10);
        String strQ3 = ek.v.q(k()[4].a());
        String strQ4 = ek.v.q(k()[3].a());
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new VPVRRemote(input, output, new VPVRRemote.Output(null, Boolean.valueOf(zJ4), ek.v.q(k()[6].a()), ek.v.q(k()[5].a()), strQ3, strQ4, Boolean.valueOf(zJ3), null, null, Boolean.valueOf(zB2), null, null, 3457, null), new VPVRRemote.Input(Integer.valueOf(ek.v.f(this, 1)), Integer.valueOf(ek.v.f(this, 2)), Integer.valueOf(ek.v.f(this, 0)))), null, -1, 25165823, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("vpvr");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 16;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return true;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.m[] u() {
        return new ek.m[]{new ek.m("控制点", Color.parseColor("#FFF7F8FA"), 0.0f, 4, null), new ek.m("筹码区域0", Color.parseColor("#331478FA"), 0.0f, 4, null), new ek.m("筹码区域0", Color.parseColor("#33FAAD14"), 0.0f, 4, null), new ek.m("筹码区域1", Color.parseColor("#7F1478FA"), 0.0f, 4, null), new ek.m("筹码区域1", Color.parseColor("#7FFAAD14"), 0.0f, 4, null), new ek.m("筹码区域2", Color.parseColor("#B34A6EFF"), 0.0f, 4, null), new ek.m("筹码区域2", Color.parseColor("#B3FFA442"), 0.0f, 4, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.w[] v() {
        String string;
        String string2;
        String string3;
        Resources resources;
        Resources resources2;
        Resources resources3;
        KLineManager.a aVar = KLineManager.f142490O;
        Context contextW = aVar.a().w();
        if (contextW == null || (resources3 = contextW.getResources()) == null || (string = resources3.getString(R.string.kline_vpvr_line)) == null) {
            string = aVar.a().i().getResources().getString(R.string.kline_vpvr_line);
        }
        String str = string;
        Context contextW2 = aVar.a().w();
        if (contextW2 == null || (resources2 = contextW2.getResources()) == null || (string2 = resources2.getString(R.string.kline_vpvr_range1)) == null) {
            string2 = aVar.a().i().getResources().getString(R.string.kline_vpvr_range1);
        }
        Context contextW3 = aVar.a().w();
        if (contextW3 == null || (resources = contextW3.getResources()) == null || (string3 = resources.getString(R.string.kline_vpvr_range2)) == null) {
            string3 = aVar.a().i().getResources().getString(R.string.kline_vpvr_range2);
        }
        return new ek.w[]{new ek.w(str, new p292ng.g(0, 100), 50, false, 0, 24, null), new ek.w(string2, new p292ng.g(0, 100), 90, false, 0, 24, null), new ek.w(string3, new p292ng.g(0, 100), 70, false, 0, 24, null)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ek.I[] w() {
        String string;
        String string2;
        String string3;
        Resources resources;
        Resources resources2;
        Resources resources3;
        KLineManager.a aVar = KLineManager.f142490O;
        Context contextW = aVar.a().w();
        if (contextW == null || (resources3 = contextW.getResources()) == null || (string = resources3.getString(R.string.kline_vpvr_point)) == null) {
            string = aVar.a().i().getResources().getString(R.string.kline_vpvr_point);
        }
        Context contextW2 = aVar.a().w();
        if (contextW2 == null || (resources2 = contextW2.getResources()) == null || (string2 = resources2.getString(R.string.kline_vpvr_range1)) == null) {
            string2 = aVar.a().i().getResources().getString(R.string.kline_vpvr_range1);
        }
        Context contextW3 = aVar.a().w();
        if (contextW3 == null || (resources = contextW3.getResources()) == null || (string3 = resources.getString(R.string.kline_vpvr_range2)) == null) {
            string3 = aVar.a().i().getResources().getString(R.string.kline_vpvr_range2);
        }
        return new ek.I[]{new ek.I(string, false), new ek.I(string2, true), new ek.I(string3, true)};
    }
}
