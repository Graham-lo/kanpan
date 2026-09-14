package sp.aicoin_kline.core.indicator.config;

import java.util.ArrayList;
import java.util.List;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class f0 extends N {
    @Override // sp.aicoin_kline.core.indicator.config.N
    public N.a[] B() {
        return new N.a[]{new N.a("MAVOL1", new p292ng.g(0, 1000), 5, true, -13643086, 2.0f), new N.a("MAVOL2", new p292ng.g(0, 1000), 10, true, -19456, 2.0f), new N.a("MAVOL3", new p292ng.g(0, 1000), 0, false, -1553991, 2.0f), new N.a("MAVOL4", new p292ng.g(0, 1000), 0, false, -15435576, 2.0f), new N.a("MAVOL5", new p292ng.g(0, 1000), 0, false, -5054582, 2.0f), new N.a("MAVOL6", new p292ng.g(0, 1000), 0, false, -288103, 2.0f)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        List<VolumeRemote.Output.Ma> ma2;
        Boolean maDisabled;
        List<Integer> ma3;
        List<VolumeRemote.Output.Ma> ma4;
        Boolean maDisabled2;
        List<Integer> ma5;
        List<VolumeRemote.Output.Ma> ma6;
        Boolean maDisabled3;
        List<Integer> ma7;
        List<VolumeRemote.Output.Ma> ma8;
        String maLineColor;
        Integer maLineWidth;
        VolumeRemote volume = chartIndicatorSetting.getVolume();
        if (volume == null) {
            return;
        }
        VolumeRemote.Output app_output = volume.getApp_output();
        int i10 = 0;
        if (app_output != null && (ma8 = app_output.getMa()) != null) {
            ek.m[] mVarArrK = k();
            int length = mVarArrK.length;
            int i11 = 0;
            int i12 = 0;
            while (i11 < length) {
                ek.m mVar = mVarArrK[i11];
                int i13 = i12 + 1;
                VolumeRemote.Output.Ma ma9 = (VolumeRemote.Output.Ma) Sf.z.r0(ma8, i12);
                if (ma9 != null && (maLineColor = ma9.getMaLineColor()) != null) {
                    Integer numR = ek.v.r(maLineColor);
                    VolumeRemote.Output.Ma ma10 = (VolumeRemote.Output.Ma) Sf.z.r0(ma8, i12);
                    if (ma10 != null && (maLineWidth = ma10.getMaLineWidth()) != null) {
                        int iIntValue = maLineWidth.intValue();
                        if (numR != null) {
                            mVar.d(numR.intValue());
                        }
                        mVar.e(iIntValue);
                    }
                }
                i11++;
                i12 = i13;
            }
        }
        if (KLineManager.f142490O.a().H()) {
            VolumeRemote.Input input = volume.getInput();
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
            VolumeRemote.Output output = volume.getOutput();
            if (output == null || (ma6 = output.getMa()) == null) {
                return;
            }
            ek.I[] iArrR = r();
            int length3 = iArrR.length;
            int i17 = 0;
            while (i10 < length3) {
                ek.I i18 = iArrR[i10];
                int i19 = i17 + 1;
                VolumeRemote.Output.Ma ma11 = (VolumeRemote.Output.Ma) Sf.z.r0(ma6, i17);
                if (ma11 != null && (maDisabled3 = ma11.getMaDisabled()) != null) {
                    i18.d(!maDisabled3.booleanValue());
                }
                i10++;
                i17 = i19;
            }
            return;
        }
        VolumeRemote.Input app_input = volume.getApp_input();
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
        VolumeRemote.Output app_output2 = volume.getApp_output();
        if (app_output2 != null && (ma4 = app_output2.getMa()) != null) {
            ek.I[] iArrR2 = r();
            int length5 = iArrR2.length;
            int i23 = 0;
            int i24 = 0;
            while (i23 < length5) {
                ek.I i25 = iArrR2[i23];
                int i26 = i24 + 1;
                VolumeRemote.Output.Ma ma12 = (VolumeRemote.Output.Ma) Sf.z.r0(ma4, i24);
                if (ma12 != null && (maDisabled2 = ma12.getMaDisabled()) != null) {
                    i25.d(!maDisabled2.booleanValue());
                }
                i23++;
                i24 = i26;
            }
        }
        VolumeRemote.Input input2 = volume.getInput();
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
        VolumeRemote.Output output2 = volume.getOutput();
        if (output2 == null || (ma2 = output2.getMa()) == null) {
            return;
        }
        ek.I[] iArrP = p();
        int length7 = iArrP.length;
        int i30 = 0;
        while (i10 < length7) {
            ek.I i31 = iArrP[i10];
            int i32 = i30 + 1;
            VolumeRemote.Output.Ma ma13 = (VolumeRemote.Output.Ma) Sf.z.r0(ma2, i30);
            if (ma13 != null && (maDisabled = ma13.getMaDisabled()) != null) {
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
            arrayList3.add(new VolumeRemote.Output.Ma(Boolean.valueOf(!i10.b()), null, null, 6, null));
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
            VolumeRemote.Output.Ma ma2 = (VolumeRemote.Output.Ma) Sf.z.r0(arrayList3, i12);
            arrayList4.add(new VolumeRemote.Output.Ma(Boolean.valueOf((ma2 == null || (maDisabled = ma2.getMaDisabled()) == null) ? true : maDisabled.booleanValue()), strQ, Integer.valueOf(iB)));
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
        VolumeRemote.Input input = new VolumeRemote.Input(arrayList);
        if (!zH) {
            ek.I[] iArrP = p();
            arrayList3 = new ArrayList(iArrP.length);
            for (ek.I i14 : iArrP) {
                arrayList3.add(new VolumeRemote.Output.Ma(Boolean.valueOf(!i14.b()), null, null, 6, null));
            }
        }
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, new VolumeRemote(input, new VolumeRemote.Output(null, null, arrayList3, null, null, null, null, null, 251, null), new VolumeRemote.Output(null, null, arrayList4, null, null, null, null, null, 251, null), new VolumeRemote.Input(arrayList2)), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -4097, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        ArrayList arrayList;
        ArrayList arrayList2;
        ArrayList arrayList3;
        Boolean maDisabled;
        ek.w[] wVarArrL = l();
        ArrayList arrayList4 = new ArrayList(wVarArrL.length);
        for (int iA = 0; iA < wVarArrL.length; iA = kk.e.a(wVarArrL[iA], arrayList4, iA, 1)) {
        }
        if (z10) {
            ek.I[] iArrR = r();
            arrayList = new ArrayList(iArrR.length);
            for (ek.I i10 : iArrR) {
                arrayList.add(new VolumeRemote.Output.Ma(Boolean.valueOf(!i10.b()), null, null, 6, null));
            }
        } else {
            ek.I[] iArrP = p();
            arrayList = new ArrayList(iArrP.length);
            for (ek.I i11 : iArrP) {
                arrayList.add(new VolumeRemote.Output.Ma(Boolean.valueOf(!i11.b()), null, null, 6, null));
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
            VolumeRemote.Output.Ma ma2 = (VolumeRemote.Output.Ma) Sf.z.r0(arrayList, i13);
            arrayList5.add(new VolumeRemote.Output.Ma(Boolean.valueOf((ma2 == null || (maDisabled = ma2.getMaDisabled()) == null) ? true : maDisabled.booleanValue()), strQ, Integer.valueOf(iB)));
            i12++;
            i13 = i14;
        }
        if (z10) {
            arrayList2 = arrayList4;
        } else {
            ek.w[] wVarArrO = o();
            arrayList2 = new ArrayList(wVarArrO.length);
            for (int iA2 = 0; iA2 < wVarArrO.length; iA2 = kk.e.a(wVarArrO[iA2], arrayList2, iA2, 1)) {
            }
        }
        VolumeRemote.Input input = new VolumeRemote.Input(arrayList2);
        if (z10) {
            arrayList3 = arrayList;
        } else {
            ek.I[] iArrP2 = p();
            ArrayList arrayList6 = new ArrayList(iArrP2.length);
            for (ek.I i15 : iArrP2) {
                arrayList6.add(new VolumeRemote.Output.Ma(Boolean.valueOf(!i15.b()), null, null, 6, null));
            }
            arrayList3 = arrayList6;
        }
        VolumeRemote.Output output = new VolumeRemote.Output(null, null, arrayList3, null, null, null, null, null, 251, null);
        VolumeRemote.Output output2 = new VolumeRemote.Output(null, null, arrayList5, null, null, null, null, null, 251, null);
        if (!z10) {
            ek.w[] wVarArrO2 = o();
            ArrayList arrayList7 = new ArrayList(wVarArrO2.length);
            int length2 = wVarArrO2.length;
            for (int iA3 = 0; iA3 < length2; iA3 = kk.e.a(wVarArrO2[iA3], arrayList7, iA3, 1)) {
            }
            arrayList4 = arrayList7;
        }
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, new VolumeRemote(input, output, output2, new VolumeRemote.Input(arrayList4)), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -4097, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("volume");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 11;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }
}
