package sp.aicoin_kline.core.indicator.config;

import java.util.ArrayList;
import java.util.List;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: sp.aicoin_kline.core.indicator.config.p, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C10509p extends N {
    @Override // sp.aicoin_kline.core.indicator.config.N
    public N.a[] B() {
        return new N.a[]{new N.a("BIAS1", new p292ng.g(0, 1000), 6, true, -13643086, 2.0f), new N.a("BIAS2", new p292ng.g(0, 1000), 12, true, -19456, 2.0f), new N.a("BIAS3", new p292ng.g(0, 1000), 24, true, -1553991, 2.0f)};
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public void c(ChartIndicatorSetting chartIndicatorSetting) {
        List<BiasRemote.Output.Bia> bias;
        Boolean biasDisabled;
        List<Integer> bias2;
        List<BiasRemote.Output.Bia> bias3;
        Boolean biasDisabled2;
        List<Integer> bias4;
        List<BiasRemote.Output.Bia> bias5;
        Boolean biasDisabled3;
        List<Integer> bias6;
        List<BiasRemote.Output.Bia> bias7;
        String biasLineColor;
        BiasRemote.Output.Bia bia;
        Integer biasLineWidth;
        BiasRemote bias8 = chartIndicatorSetting.getBias();
        if (bias8 == null) {
            return;
        }
        BiasRemote.Output app_output = bias8.getApp_output();
        int i10 = 0;
        if (app_output != null && (bias7 = app_output.getBias()) != null) {
            ek.m[] mVarArrK = k();
            int length = mVarArrK.length;
            int i11 = 0;
            int i12 = 0;
            while (i11 < length) {
                ek.m mVar = mVarArrK[i11];
                int i13 = i12 + 1;
                BiasRemote.Output.Bia bia2 = (BiasRemote.Output.Bia) Sf.z.r0(bias7, i12);
                if (bia2 != null && (biasLineColor = bia2.getBiasLineColor()) != null && (bia = (BiasRemote.Output.Bia) Sf.z.r0(bias7, i12)) != null && (biasLineWidth = bia.getBiasLineWidth()) != null) {
                    int iIntValue = biasLineWidth.intValue();
                    Integer numR = ek.v.r(biasLineColor);
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
            BiasRemote.Input input = bias8.getInput();
            if (input != null && (bias6 = input.getBias()) != null) {
                ek.w[] wVarArrL = l();
                int length2 = wVarArrL.length;
                int i14 = 0;
                int i15 = 0;
                while (i14 < length2) {
                    ek.w wVar = wVarArrL[i14];
                    int i16 = i15 + 1;
                    Integer num = (Integer) Sf.z.r0(bias6, i15);
                    if (num != null) {
                        wVar.j(num.intValue());
                    }
                    i14++;
                    i15 = i16;
                }
            }
            BiasRemote.Output output = bias8.getOutput();
            if (output == null || (bias5 = output.getBias()) == null) {
                return;
            }
            ek.I[] iArrR = r();
            int length3 = iArrR.length;
            int i17 = 0;
            while (i10 < length3) {
                ek.I i18 = iArrR[i10];
                int i19 = i17 + 1;
                BiasRemote.Output.Bia bia3 = (BiasRemote.Output.Bia) Sf.z.r0(bias5, i17);
                if (bia3 != null && (biasDisabled3 = bia3.getBiasDisabled()) != null) {
                    i18.d(!biasDisabled3.booleanValue());
                }
                i10++;
                i17 = i19;
            }
            return;
        }
        BiasRemote.Input app_input = bias8.getApp_input();
        if (app_input != null && (bias4 = app_input.getBias()) != null) {
            ek.w[] wVarArrL2 = l();
            int length4 = wVarArrL2.length;
            int i20 = 0;
            int i21 = 0;
            while (i20 < length4) {
                ek.w wVar2 = wVarArrL2[i20];
                int i22 = i21 + 1;
                Integer num2 = (Integer) Sf.z.r0(bias4, i21);
                if (num2 != null) {
                    wVar2.j(num2.intValue());
                }
                i20++;
                i21 = i22;
            }
        }
        BiasRemote.Output app_output2 = bias8.getApp_output();
        if (app_output2 != null && (bias3 = app_output2.getBias()) != null) {
            ek.I[] iArrR2 = r();
            int length5 = iArrR2.length;
            int i23 = 0;
            int i24 = 0;
            while (i23 < length5) {
                ek.I i25 = iArrR2[i23];
                int i26 = i24 + 1;
                BiasRemote.Output.Bia bia4 = (BiasRemote.Output.Bia) Sf.z.r0(bias3, i24);
                if (bia4 != null && (biasDisabled2 = bia4.getBiasDisabled()) != null) {
                    i25.d(!biasDisabled2.booleanValue());
                }
                i23++;
                i24 = i26;
            }
        }
        BiasRemote.Input input2 = bias8.getInput();
        if (input2 != null && (bias2 = input2.getBias()) != null) {
            ek.w[] wVarArrO = o();
            int length6 = wVarArrO.length;
            int i27 = 0;
            int i28 = 0;
            while (i27 < length6) {
                ek.w wVar3 = wVarArrO[i27];
                int i29 = i28 + 1;
                Integer num3 = (Integer) Sf.z.r0(bias2, i28);
                if (num3 != null) {
                    wVar3.j(num3.intValue());
                }
                i27++;
                i28 = i29;
            }
        }
        BiasRemote.Output output2 = bias8.getOutput();
        if (output2 == null || (bias = output2.getBias()) == null) {
            return;
        }
        ek.I[] iArrP = p();
        int length7 = iArrP.length;
        int i30 = 0;
        while (i10 < length7) {
            ek.I i31 = iArrP[i10];
            int i32 = i30 + 1;
            BiasRemote.Output.Bia bia5 = (BiasRemote.Output.Bia) Sf.z.r0(bias, i30);
            if (bia5 != null && (biasDisabled = bia5.getBiasDisabled()) != null) {
                i31.d(!biasDisabled.booleanValue());
            }
            i10++;
            i30 = i32;
        }
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting i() {
        ArrayList arrayList;
        Boolean biasDisabled;
        boolean zH = KLineManager.f142490O.a().H();
        ek.w[] wVarArrL = l();
        ArrayList arrayList2 = new ArrayList(wVarArrL.length);
        for (int iA = 0; iA < wVarArrL.length; iA = kk.e.a(wVarArrL[iA], arrayList2, iA, 1)) {
        }
        ek.I[] iArrR = r();
        ArrayList arrayList3 = new ArrayList(iArrR.length);
        for (ek.I i10 : iArrR) {
            arrayList3.add(new BiasRemote.Output.Bia(Boolean.valueOf(!i10.b()), null, null, 6, null));
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
            BiasRemote.Output.Bia bia = (BiasRemote.Output.Bia) Sf.z.r0(arrayList3, i12);
            arrayList4.add(new BiasRemote.Output.Bia(Boolean.valueOf((bia == null || (biasDisabled = bia.getBiasDisabled()) == null) ? true : biasDisabled.booleanValue()), strQ, Integer.valueOf(iB)));
            i11++;
            i12 = i13;
        }
        if (zH) {
            ek.w[] wVarArrL2 = l();
            arrayList = new ArrayList(wVarArrL2.length);
            for (int iA2 = 0; iA2 < wVarArrL2.length; iA2 = kk.e.a(wVarArrL2[iA2], arrayList, iA2, 1)) {
            }
        } else {
            ek.w[] wVarArrO = o();
            arrayList = new ArrayList(wVarArrO.length);
            for (int iA3 = 0; iA3 < wVarArrO.length; iA3 = kk.e.a(wVarArrO[iA3], arrayList, iA3, 1)) {
            }
        }
        BiasRemote.Input input = new BiasRemote.Input(arrayList);
        if (!zH) {
            ek.I[] iArrP = p();
            arrayList3 = new ArrayList(iArrP.length);
            for (ek.I i14 : iArrP) {
                arrayList3.add(new BiasRemote.Output.Bia(Boolean.valueOf(!i14.b()), null, null, 6, null));
            }
        }
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new BiasRemote(input, new BiasRemote.Output(arrayList3, null, null, null, 14, null), new BiasRemote.Output(arrayList4, null, null, null, 14, null), new BiasRemote.Input(arrayList2)), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -67108865, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public ChartIndicatorSetting j(boolean z10) {
        ArrayList arrayList;
        ArrayList arrayList2;
        ArrayList arrayList3;
        ArrayList arrayList4;
        Boolean biasDisabled;
        int iA = 0;
        if (z10) {
            ek.I[] iArrR = r();
            arrayList = new ArrayList(iArrR.length);
            for (ek.I i10 : iArrR) {
                arrayList.add(new BiasRemote.Output.Bia(Boolean.valueOf(!i10.b()), null, null, 6, null));
            }
        } else {
            ek.I[] iArrP = p();
            arrayList = new ArrayList(iArrP.length);
            for (ek.I i11 : iArrP) {
                arrayList.add(new BiasRemote.Output.Bia(Boolean.valueOf(!i11.b()), null, null, 6, null));
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
            BiasRemote.Output.Bia bia = (BiasRemote.Output.Bia) Sf.z.r0(arrayList, i13);
            arrayList5.add(new BiasRemote.Output.Bia(Boolean.valueOf((bia == null || (biasDisabled = bia.getBiasDisabled()) == null) ? true : biasDisabled.booleanValue()), strQ, Integer.valueOf(iB)));
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
        BiasRemote.Input input = new BiasRemote.Input(arrayList2);
        if (z10) {
            arrayList3 = arrayList;
        } else {
            ek.I[] iArrP2 = p();
            ArrayList arrayList6 = new ArrayList(iArrP2.length);
            for (ek.I i15 : iArrP2) {
                arrayList6.add(new BiasRemote.Output.Bia(Boolean.valueOf(!i15.b()), null, null, 6, null));
            }
            arrayList3 = arrayList6;
        }
        BiasRemote.Output output = new BiasRemote.Output(arrayList3, null, null, null, 14, null);
        BiasRemote.Output output2 = new BiasRemote.Output(arrayList5, null, null, null, 14, null);
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
        return new ChartIndicatorSetting(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, new BiasRemote(input, output, output2, new BiasRemote.Input(arrayList4)), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, -67108865, 33554431, null);
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public String n() {
        return nk.o.f134231a.a("bias");
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public int q() {
        return 16;
    }

    @Override // sp.aicoin_kline.core.indicator.config.F
    public boolean s() {
        return false;
    }
}
