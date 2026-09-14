package sp.aicoin_kline.core.indicator.config;

import java.util.ArrayList;
import java.util.List;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class h0 extends N {
    @Override // sp.aicoin_kline.core.indicator.config.N
    public N.a[] B() {
        return new N.a[]{new N.a("WR1", new p292ng.g(0, 100), 10, true, -13643086, 2.0f), new N.a("WR2", new p292ng.g(0, 100), 6, true, -19456, 2.0f)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        List<WRRemote.Output.Wr> wr;
        Boolean wrDisabled;
        List<Integer> wr2;
        List<WRRemote.Output.Wr> wr3;
        Boolean wrDisabled2;
        List<Integer> wr4;
        List<WRRemote.Output.Wr> wr5;
        Boolean wrDisabled3;
        List<Integer> wr6;
        List<WRRemote.Output.Wr> wr7;
        String wrLineColor;
        WRRemote.Output.Wr wr8;
        Integer wrLineWidth;
        WRRemote wr9 = chartIndicatorSetting.getWr();
        if (wr9 == null) {
            return;
        }
        WRRemote.Output app_output = wr9.getApp_output();
        int i10 = 0;
        if (app_output != null && (wr7 = app_output.getWr()) != null) {
            ek.m[] mVarArrK = k();
            int length = mVarArrK.length;
            int i11 = 0;
            int i12 = 0;
            while (i11 < length) {
                ek.m mVar = mVarArrK[i11];
                int i13 = i12 + 1;
                WRRemote.Output.Wr wr10 = (WRRemote.Output.Wr) Sf.z.r0(wr7, i12);
                if (wr10 != null && (wrLineColor = wr10.getWrLineColor()) != null && (wr8 = (WRRemote.Output.Wr) Sf.z.r0(wr7, i12)) != null && (wrLineWidth = wr8.getWrLineWidth()) != null) {
                    int iIntValue = wrLineWidth.intValue();
                    Integer numR = ek.v.r(wrLineColor);
                    if (numR != null) {
                        mVar.d(numR.intValue());
                    }
                    mVar.e(iIntValue);
                }
                i11++;
                i12 = i13;
            }
        }
        if (KLineManager.f142490O.a().H()) {
            WRRemote.Input input = wr9.getInput();
            if (input != null && (wr6 = input.getWr()) != null) {
                ek.w[] wVarArrL = l();
                int length2 = wVarArrL.length;
                int i14 = 0;
                int i15 = 0;
                while (i14 < length2) {
                    ek.w wVar = wVarArrL[i14];
                    int i16 = i15 + 1;
                    Integer num = (Integer) Sf.z.r0(wr6, i15);
                    if (num != null) {
                        wVar.j(num.intValue());
                    }
                    i14++;
                    i15 = i16;
                }
            }
            WRRemote.Output output = wr9.getOutput();
            if (output == null || (wr5 = output.getWr()) == null) {
                return;
            }
            ek.I[] iArrR = r();
            int length3 = iArrR.length;
            int i17 = 0;
            while (i10 < length3) {
                ek.I i18 = iArrR[i10];
                int i19 = i17 + 1;
                WRRemote.Output.Wr wr11 = (WRRemote.Output.Wr) Sf.z.r0(wr5, i17);
                if (wr11 != null && (wrDisabled3 = wr11.getWrDisabled()) != null) {
                    i18.d(!wrDisabled3.booleanValue());
                }
                i10++;
                i17 = i19;
            }
            return;
        }
        WRRemote.Input app_input = wr9.getApp_input();
        if (app_input != null && (wr4 = app_input.getWr()) != null) {
            ek.w[] wVarArrL2 = l();
            int length4 = wVarArrL2.length;
            int i20 = 0;
            int i21 = 0;
            while (i20 < length4) {
                ek.w wVar2 = wVarArrL2[i20];
                int i22 = i21 + 1;
                Integer num2 = (Integer) Sf.z.r0(wr4, i21);
                if (num2 != null) {
                    wVar2.j(num2.intValue());
                }
                i20++;
                i21 = i22;
            }
        }
        WRRemote.Output app_output2 = wr9.getApp_output();
        if (app_output2 != null && (wr3 = app_output2.getWr()) != null) {
            ek.I[] iArrR2 = r();
            int length5 = iArrR2.length;
            int i23 = 0;
            int i24 = 0;
            while (i23 < length5) {
                ek.I i25 = iArrR2[i23];
                int i26 = i24 + 1;
                WRRemote.Output.Wr wr12 = (WRRemote.Output.Wr) Sf.z.r0(wr3, i24);
                if (wr12 != null && (wrDisabled2 = wr12.getWrDisabled()) != null) {
                    i25.d(!wrDisabled2.booleanValue());
                }
                i23++;
                i24 = i26;
            }
        }
        WRRemote.Input input2 = wr9.getInput();
        if (input2 != null && (wr2 = input2.getWr()) != null) {
            ek.w[] wVarArrO = o();
            int length6 = wVarArrO.length;
            int i27 = 0;
            int i28 = 0;
            while (i27 < length6) {
                ek.w wVar3 = wVarArrO[i27];
                int i29 = i28 + 1;
                Integer num3 = (Integer) Sf.z.r0(wr2, i28);
                if (num3 != null) {
                    wVar3.j(num3.intValue());
                }
                i27++;
                i28 = i29;
            }
        }
        WRRemote.Output output2 = wr9.getOutput();
        if (output2 == null || (wr = output2.getWr()) == null) {
            return;
        }
        ek.I[] iArrP = p();
        int length7 = iArrP.length;
        int i30 = 0;
        while (i10 < length7) {
            ek.I i31 = iArrP[i10];
            int i32 = i30 + 1;
            WRRemote.Output.Wr wr13 = (WRRemote.Output.Wr) Sf.z.r0(wr, i30);
            if (wr13 != null && (wrDisabled = wr13.getWrDisabled()) != null) {
                i31.d(!wrDisabled.booleanValue());
            }
            i10++;
            i30 = i32;
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        ArrayList arrayList;
        Boolean wrDisabled;
        boolean zH = KLineManager.f142490O.a().H();
        ek.w[] wVarArrL = l();
        ArrayList arrayList2 = new ArrayList(wVarArrL.length);
        for (int iA = 0; iA < wVarArrL.length; iA = kk.e.a(wVarArrL[iA], arrayList2, iA, 1)) {
        }
        ek.I[] iArrR = r();
        ArrayList arrayList3 = new ArrayList(iArrR.length);
        for (ek.I i10 : iArrR) {
            arrayList3.add(new WRRemote.Output.Wr(Boolean.valueOf(!i10.b()), null, null, 6, null));
        }
        ek.m[] mVarArrK = k();
        ArrayList arrayList4 = new ArrayList(mVarArrK.length);
        int length = mVarArrK.length;
        int i11 = 0;
        int i12 = 0;
        while (i11 < length) {
            ek.m mVar = mVarArrK[i11];
            int i13 = i12 + 1;
            String strQ = ek.v.q(mVar.a());
            int iB = (int) mVar.b();
            WRRemote.Output.Wr wr = (WRRemote.Output.Wr) Sf.z.r0(arrayList3, i12);
            arrayList4.add(new WRRemote.Output.Wr(Boolean.valueOf((wr == null || (wrDisabled = wr.getWrDisabled()) == null) ? true : wrDisabled.booleanValue()), strQ, Integer.valueOf(iB)));
            i11++;
            i12 = i13;
        }
        if (zH) {
            arrayList = arrayList2;
        } else {
            ek.w[] wVarArrO = o();
            arrayList = new ArrayList(wVarArrO.length);
            for (int iA2 = 0; iA2 < wVarArrO.length; iA2 = kk.e.a(wVarArrO[iA2], arrayList, iA2, 1)) {
            }
        }
        WRRemote.Input input = new WRRemote.Input(arrayList);
        if (!zH) {
            ek.I[] iArrP = p();
            arrayList3 = new ArrayList(iArrP.length);
            for (ek.I i14 : iArrP) {
                arrayList3.add(new WRRemote.Output.Wr(Boolean.valueOf(!i14.b()), null, null, 6, null));
            }
        }
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new WRRemote(input, new WRRemote.Output(arrayList3), new WRRemote.Output(arrayList4), new WRRemote.Input(arrayList2)), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -524289, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        ArrayList arrayList;
        ArrayList arrayList2;
        Boolean wrDisabled;
        ek.w[] wVarArrL = l();
        ArrayList arrayList3 = new ArrayList(wVarArrL.length);
        for (int iA = 0; iA < wVarArrL.length; iA = kk.e.a(wVarArrL[iA], arrayList3, iA, 1)) {
        }
        if (z10) {
            ek.I[] iArrR = r();
            arrayList = new ArrayList(iArrR.length);
            for (ek.I i10 : iArrR) {
                arrayList.add(new WRRemote.Output.Wr(Boolean.valueOf(!i10.b()), null, null, 6, null));
            }
        } else {
            ek.I[] iArrP = p();
            arrayList = new ArrayList(iArrP.length);
            for (ek.I i11 : iArrP) {
                arrayList.add(new WRRemote.Output.Wr(Boolean.valueOf(!i11.b()), null, null, 6, null));
            }
        }
        ek.m[] mVarArrK = k();
        ArrayList arrayList4 = new ArrayList(mVarArrK.length);
        int length = mVarArrK.length;
        int i12 = 0;
        int i13 = 0;
        while (i12 < length) {
            ek.m mVar = mVarArrK[i12];
            int i14 = i13 + 1;
            String strQ = ek.v.q(mVar.a());
            int iB = (int) mVar.b();
            WRRemote.Output.Wr wr = (WRRemote.Output.Wr) Sf.z.r0(arrayList, i13);
            arrayList4.add(new WRRemote.Output.Wr(Boolean.valueOf((wr == null || (wrDisabled = wr.getWrDisabled()) == null) ? true : wrDisabled.booleanValue()), strQ, Integer.valueOf(iB)));
            i12++;
            i13 = i14;
        }
        if (z10) {
            arrayList2 = arrayList3;
        } else {
            ek.w[] wVarArrO = o();
            arrayList2 = new ArrayList(wVarArrO.length);
            for (int iA2 = 0; iA2 < wVarArrO.length; iA2 = kk.e.a(wVarArrO[iA2], arrayList2, iA2, 1)) {
            }
        }
        WRRemote.Input input = new WRRemote.Input(arrayList2);
        if (!z10) {
            ek.I[] iArrP2 = p();
            ArrayList arrayList5 = new ArrayList(iArrP2.length);
            for (ek.I i15 : iArrP2) {
                arrayList5.add(new WRRemote.Output.Wr(Boolean.valueOf(!i15.b()), null, null, 6, null));
            }
            arrayList = arrayList5;
        }
        WRRemote.Output output = new WRRemote.Output(arrayList);
        WRRemote.Output output2 = new WRRemote.Output(arrayList4);
        if (!z10) {
            ek.w[] wVarArrO2 = o();
            ArrayList arrayList6 = new ArrayList(wVarArrO2.length);
            int length2 = wVarArrO2.length;
            for (int iA3 = 0; iA3 < length2; iA3 = kk.e.a(wVarArrO2[iA3], arrayList6, iA3, 1)) {
            }
            arrayList3 = arrayList6;
        }
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new WRRemote(input, output, output2, new WRRemote.Input(arrayList3)), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -524289, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("wr");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 7;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }
}
