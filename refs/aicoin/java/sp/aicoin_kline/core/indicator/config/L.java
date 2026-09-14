package sp.aicoin_kline.core.indicator.config;

import android.graphics.Color;
import java.util.ArrayList;
import java.util.List;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class L extends N {
    @Override // sp.aicoin_kline.core.indicator.config.N
    public N.a[] B() {
        return new N.a[]{new N.a("MA1", new p292ng.g(0, 1000), 7, true, -13643086, 2.0f), new N.a("MA2", new p292ng.g(0, 1000), 30, true, -19456, 2.0f), new N.a("MA3", new p292ng.g(0, 1000), 0, false, -1553991, 2.0f), new N.a("MA4", new p292ng.g(0, 1000), 0, false, -15435576, 2.0f), new N.a("MA5", new p292ng.g(0, 1000), 0, false, -5054582, 2.0f), new N.a("MA6", new p292ng.g(0, 1000), 0, false, -288103, 2.0f), new N.a("MA7", new p292ng.g(0, 1000), 0, false, -16726565, 2.0f), new N.a("MA8", new p292ng.g(0, 1000), 0, false, -683264, 2.0f), new N.a("MA9", new p292ng.g(0, 1000), 0, false, -7334914, 2.0f), new N.a("MA10", new p292ng.g(0, 1000), 0, false, -8355712, 2.0f), new N.a("MA11", new p292ng.g(0, 1000), 0, false, Color.parseColor("#FFE36E1B"), 2.0f), new N.a("MA12", new p292ng.g(0, 1000), 0, false, Color.parseColor("#FFA939BF"), 2.0f), new N.a("MA13", new p292ng.g(0, 1000), 0, false, Color.parseColor("#FFE65D45"), 2.0f), new N.a("MA14", new p292ng.g(0, 1000), 0, false, Color.parseColor("#FF16AB81"), 2.0f), new N.a("MA15", new p292ng.g(0, 1000), 0, false, Color.parseColor("#FF4BBF89"), 2.0f), new N.a("MA16", new p292ng.g(0, 1000), 0, false, Color.parseColor("#FFE8DE1C"), 2.0f), new N.a("MA17", new p292ng.g(0, 1000), 0, false, Color.parseColor("#FF2F8FDE"), 2.0f), new N.a("MA18", new p292ng.g(0, 1000), 0, false, Color.parseColor("#FFD64542"), 2.0f), new N.a("MA19", new p292ng.g(0, 1000), 0, false, Color.parseColor("#FFBD244F"), 2.0f), new N.a("MA20", new p292ng.g(0, 1000), 0, false, Color.parseColor("#FF545454"), 2.0f)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        List<MARemote.Output.Ma> ma2;
        Boolean maDisabled;
        List<Integer> ma3;
        List<MARemote.Output.Ma> ma4;
        Boolean maDisabled2;
        List<Integer> ma5;
        List<MARemote.Output.Ma> ma6;
        Boolean maDisabled3;
        List<Integer> ma7;
        List<MARemote.Output.Ma> ma8;
        String maLineColor;
        Integer numR;
        Integer maLineWidth;
        MARemote ma9 = chartIndicatorSetting.getMa();
        if (ma9 == null) {
            return;
        }
        MARemote.Output app_output = ma9.getApp_output();
        int i10 = 0;
        if (app_output != null && (ma8 = app_output.getMa()) != null) {
            ek.m[] mVarArrK = k();
            int length = mVarArrK.length;
            int i11 = 0;
            int i12 = 0;
            while (i11 < length) {
                ek.m mVar = mVarArrK[i11];
                int i13 = i12 + 1;
                MARemote.Output.Ma ma10 = (MARemote.Output.Ma) Sf.z.r0(ma8, i12);
                if (ma10 != null && (maLineColor = ma10.getMaLineColor()) != null && (numR = ek.v.r(maLineColor)) != null) {
                    int iIntValue = numR.intValue();
                    MARemote.Output.Ma ma11 = (MARemote.Output.Ma) Sf.z.r0(ma8, i12);
                    if (ma11 != null && (maLineWidth = ma11.getMaLineWidth()) != null) {
                        int iIntValue2 = maLineWidth.intValue();
                        mVar.d(iIntValue);
                        mVar.e(iIntValue2);
                    }
                }
                i11++;
                i12 = i13;
            }
        }
        if (KLineManager.f142490O.a().H()) {
            MARemote.Input input = ma9.getInput();
            if (input != null && (ma7 = input.getMa()) != null) {
                ek.w[] wVarArrL = l();
                int length2 = wVarArrL.length;
                int i14 = 0;
                int i15 = 0;
                while (i14 < length2) {
                    ek.w wVar = wVarArrL[i14];
                    int i16 = i15 + 1;
                    Integer num = (Integer) Sf.z.r0(ma7, i15);
                    if (num != null) {
                        wVar.j(num.intValue());
                    }
                    i14++;
                    i15 = i16;
                }
            }
            MARemote.Output output = ma9.getOutput();
            if (output == null || (ma6 = output.getMa()) == null) {
                return;
            }
            ek.I[] iArrR = r();
            int length3 = iArrR.length;
            int i17 = 0;
            while (i10 < length3) {
                ek.I i18 = iArrR[i10];
                int i19 = i17 + 1;
                MARemote.Output.Ma ma12 = (MARemote.Output.Ma) Sf.z.r0(ma6, i17);
                if (ma12 != null && (maDisabled3 = ma12.getMaDisabled()) != null) {
                    i18.d(!maDisabled3.booleanValue());
                }
                i10++;
                i17 = i19;
            }
            return;
        }
        MARemote.Input app_input = ma9.getApp_input();
        if (app_input != null && (ma5 = app_input.getMa()) != null) {
            ek.w[] wVarArrL2 = l();
            int length4 = wVarArrL2.length;
            int i20 = 0;
            int i21 = 0;
            while (i20 < length4) {
                ek.w wVar2 = wVarArrL2[i20];
                int i22 = i21 + 1;
                Integer num2 = (Integer) Sf.z.r0(ma5, i21);
                if (num2 != null) {
                    wVar2.j(num2.intValue());
                }
                i20++;
                i21 = i22;
            }
        }
        MARemote.Output app_output2 = ma9.getApp_output();
        if (app_output2 != null && (ma4 = app_output2.getMa()) != null) {
            ek.I[] iArrR2 = r();
            int length5 = iArrR2.length;
            int i23 = 0;
            int i24 = 0;
            while (i23 < length5) {
                ek.I i25 = iArrR2[i23];
                int i26 = i24 + 1;
                MARemote.Output.Ma ma13 = (MARemote.Output.Ma) Sf.z.r0(ma4, i24);
                if (ma13 != null && (maDisabled2 = ma13.getMaDisabled()) != null) {
                    i25.d(!maDisabled2.booleanValue());
                }
                i23++;
                i24 = i26;
            }
        }
        MARemote.Input input2 = ma9.getInput();
        if (input2 != null && (ma3 = input2.getMa()) != null) {
            ek.w[] wVarArrO = o();
            int length6 = wVarArrO.length;
            int i27 = 0;
            int i28 = 0;
            while (i27 < length6) {
                ek.w wVar3 = wVarArrO[i27];
                int i29 = i28 + 1;
                Integer num3 = (Integer) Sf.z.r0(ma3, i28);
                if (num3 != null) {
                    wVar3.j(num3.intValue());
                }
                i27++;
                i28 = i29;
            }
        }
        MARemote.Output output2 = ma9.getOutput();
        if (output2 == null || (ma2 = output2.getMa()) == null) {
            return;
        }
        ek.I[] iArrP = p();
        int length7 = iArrP.length;
        int i30 = 0;
        while (i10 < length7) {
            ek.I i31 = iArrP[i10];
            int i32 = i30 + 1;
            MARemote.Output.Ma ma14 = (MARemote.Output.Ma) Sf.z.r0(ma2, i30);
            if (ma14 != null && (maDisabled = ma14.getMaDisabled()) != null) {
                i31.d(!maDisabled.booleanValue());
            }
            i10++;
            i30 = i32;
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        ArrayList arrayList;
        Boolean maDisabled;
        boolean zH = KLineManager.f142490O.a().H();
        ek.w[] wVarArrL = l();
        ArrayList arrayList2 = new ArrayList(wVarArrL.length);
        for (int iA = 0; iA < wVarArrL.length; iA = kk.e.a(wVarArrL[iA], arrayList2, iA, 1)) {
        }
        ek.I[] iArrR = r();
        ArrayList arrayList3 = new ArrayList(iArrR.length);
        for (ek.I i10 : iArrR) {
            arrayList3.add(new MARemote.Output.Ma(Boolean.valueOf(!i10.b()), null, null, 6, null));
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
            MARemote.Output.Ma ma2 = (MARemote.Output.Ma) Sf.z.r0(arrayList3, i12);
            arrayList4.add(new MARemote.Output.Ma(Boolean.valueOf((ma2 == null || (maDisabled = ma2.getMaDisabled()) == null) ? true : maDisabled.booleanValue()), strQ, Integer.valueOf(iB)));
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
        MARemote.Input input = new MARemote.Input(arrayList);
        if (!zH) {
            ek.I[] iArrP = p();
            arrayList3 = new ArrayList(iArrP.length);
            for (ek.I i14 : iArrP) {
                arrayList3.add(new MARemote.Output.Ma(Boolean.valueOf(!i14.b()), null, null, 6, null));
            }
        }
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, new MARemote(input, new MARemote.Output(arrayList3), new MARemote.Output(arrayList4), new MARemote.Input(arrayList2)), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -129, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        ArrayList arrayList;
        ArrayList arrayList2;
        ArrayList arrayList3;
        ArrayList arrayList4;
        Boolean maDisabled;
        int iA = 0;
        if (z10) {
            ek.I[] iArrR = r();
            arrayList = new ArrayList(iArrR.length);
            for (ek.I i10 : iArrR) {
                arrayList.add(new MARemote.Output.Ma(Boolean.valueOf(!i10.b()), null, null, 6, null));
            }
        } else {
            ek.I[] iArrP = p();
            arrayList = new ArrayList(iArrP.length);
            for (ek.I i11 : iArrP) {
                arrayList.add(new MARemote.Output.Ma(Boolean.valueOf(!i11.b()), null, null, 6, null));
            }
        }
        ek.m[] mVarArrK = k();
        ArrayList arrayList5 = new ArrayList(mVarArrK.length);
        int length = mVarArrK.length;
        int i12 = 0;
        int i13 = 0;
        while (i12 < length) {
            ek.m mVar = mVarArrK[i12];
            int i14 = i13 + 1;
            String strQ = ek.v.q(mVar.a());
            int iB = (int) mVar.b();
            MARemote.Output.Ma ma2 = (MARemote.Output.Ma) Sf.z.r0(arrayList, i13);
            arrayList5.add(new MARemote.Output.Ma(Boolean.valueOf((ma2 == null || (maDisabled = ma2.getMaDisabled()) == null) ? true : maDisabled.booleanValue()), strQ, Integer.valueOf(iB)));
            i12++;
            i13 = i14;
        }
        if (z10) {
            ek.w[] wVarArrL = l();
            arrayList2 = new ArrayList(wVarArrL.length);
            for (int iA2 = 0; iA2 < wVarArrL.length; iA2 = kk.e.a(wVarArrL[iA2], arrayList2, iA2, 1)) {
            }
        } else {
            ek.w[] wVarArrO = o();
            arrayList2 = new ArrayList(wVarArrO.length);
            for (int iA3 = 0; iA3 < wVarArrO.length; iA3 = kk.e.a(wVarArrO[iA3], arrayList2, iA3, 1)) {
            }
        }
        MARemote.Input input = new MARemote.Input(arrayList2);
        if (z10) {
            ek.I[] iArrR2 = r();
            arrayList3 = new ArrayList(iArrR2.length);
            for (ek.I i15 : iArrR2) {
                arrayList3.add(new MARemote.Output.Ma(Boolean.valueOf(!i15.b()), null, null, 6, null));
            }
        } else {
            ek.I[] iArrP2 = p();
            arrayList3 = new ArrayList(iArrP2.length);
            for (ek.I i16 : iArrP2) {
                arrayList3.add(new MARemote.Output.Ma(Boolean.valueOf(!i16.b()), null, null, 6, null));
            }
        }
        MARemote.Output output = new MARemote.Output(arrayList3);
        MARemote.Output output2 = new MARemote.Output(arrayList5);
        if (z10) {
            ek.w[] wVarArrL2 = l();
            arrayList4 = new ArrayList(wVarArrL2.length);
            int length2 = wVarArrL2.length;
            while (iA < length2) {
                iA = kk.e.a(wVarArrL2[iA], arrayList4, iA, 1);
            }
        } else {
            ek.w[] wVarArrO2 = o();
            arrayList4 = new ArrayList(wVarArrO2.length);
            int length3 = wVarArrO2.length;
            while (iA < length3) {
                iA = kk.e.a(wVarArrO2[iA], arrayList4, iA, 1);
            }
        }
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, new MARemote(input, output, output2, new MARemote.Input(arrayList4)), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -129, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("ma");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 1;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return true;
    }
}
