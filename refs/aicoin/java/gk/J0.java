package gk;

import Rj.AbstractC2755v;
import Rj.C2703d0;
import Rj.C2732n;
import Rj.C2741q;
import Rj.C2765z;
import Rj.y1;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.chart.data.ScriptDrawData;
import sp.aicoin_kline.chart.data.ScriptIndicAction;
import sp.aicoin_kline.chart.data.ScriptIndicConfig;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class J0 extends AbstractC2755v {

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final sp.aicoin_kline.core.indicator.config.F f96464n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public List f96465o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public y1 f96466p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public y1 f96467q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public Long f96468r;

    public J0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str);
        this.f96464n = f10;
        this.f96465o = new ArrayList();
        this.f96466p = c2732n.b().m("ds0");
    }

    /* JADX WARN: Code duplicated, block: B:171:0x0263  */
    /* JADX WARN: Code duplicated, block: B:174:0x026a  */
    /* JADX WARN: Code duplicated, block: B:177:0x0273  */
    /* JADX WARN: Code duplicated, block: B:181:0x027c  */
    /* JADX WARN: Code duplicated, block: B:184:0x0281  */
    /* JADX WARN: Failed to restore switch over string. Please report as a decompilation issue */
    @Override // Rj.AbstractC2755v
    public void l(int i10, double[] dArr) {
        y1 y1VarM;
        List<ScriptIndicAction> action;
        Double dN;
        Double dN2;
        Double dN3;
        Double dN4;
        Double dN5;
        Double dN6;
        Double dN7;
        String str;
        boolean z10;
        Double dN8;
        Double dN9;
        C2741q c2741qB = h().b();
        dArr[0] = Double.MAX_VALUE;
        dArr[1] = -1.7976931348623157E308d;
        C2765z c2765zH = c2741qB.h(c());
        if (c2765zH == null || (y1VarM = c2741qB.m(c())) == null) {
            return;
        }
        this.f96467q = y1VarM;
        int iD = c2765zH.D() - 1;
        Sj.a aVarC = c2765zH.C();
        if (aVarC.size() > 0) {
            Sj.b bVarD = (Sj.b) Sf.z.r0(aVarC, i10);
            if (bVarD == null) {
                return;
            }
            if (i10 == iD) {
                bVarD = nk.c.f134195a.d(bVarD);
            }
            dArr[0] = bVarD.c();
            dArr[1] = bVarD.b();
        }
        y1 y1Var = this.f96467q;
        this.f96468r = y1Var != null ? Long.valueOf(y1Var.H(i10)) : null;
        new LinkedHashMap();
        ArrayList<ScriptDrawData> arrayList = new ArrayList(this.f96465o);
        Map mapU = KLineManager.f142490O.a().u();
        for (ScriptDrawData scriptDrawData : arrayList) {
            C2703d0 c2703d0 = C2703d0.f19361a;
            ScriptIndicConfig config = scriptDrawData.getConfig();
            if (c2703d0.b(config != null ? config.getScriptRef() : null, mapU)) {
                Map mapZ = Sf.N.z(scriptDrawData.getCalculateHistoryData());
                if (mapZ == null || mapZ.isEmpty()) {
                    return;
                }
                Map linkedHashMap = (Map) mapZ.get(String.valueOf(this.f96468r));
                if (linkedHashMap == null) {
                    linkedHashMap = new LinkedHashMap();
                }
                ScriptIndicConfig config2 = scriptDrawData.getConfig();
                if (config2 != null && (action = config2.getAction()) != null) {
                    for (ScriptIndicAction scriptIndicAction : action) {
                        if (!AbstractC7609s.f(scriptIndicAction.getDisplay(), Boolean.FALSE)) {
                            Boolean excludeRange = scriptIndicAction.getExcludeRange();
                            if (!(excludeRange != null ? excludeRange.booleanValue() : false)) {
                                String action2 = scriptIndicAction.getAction();
                                double dDoubleValue = Double.NaN;
                                switch (action2.hashCode()) {
                                    case -2020374621:
                                        if (action2.equals("plotHist")) {
                                            String series = scriptIndicAction.getSeries();
                                            String str2 = (String) linkedHashMap.get(series != null ? series : "0");
                                            if (!(str2 == null || str2.length() == 0) && (dN = Ah.v.n(str2)) != null) {
                                                dDoubleValue = dN.doubleValue();
                                            }
                                        } else {
                                            dDoubleValue = 0.0d;
                                        }
                                        break;
                                    case -2020167279:
                                        if (action2.equals("plotOhlc")) {
                                            String high = scriptIndicAction.getHigh();
                                            if (high == null) {
                                                high = "";
                                            }
                                            String str3 = (String) linkedHashMap.get(high);
                                            double dDoubleValue2 = (str3 == null || (dN3 = Ah.v.n(str3)) == null) ? 0.0d : dN3.doubleValue();
                                            String low = scriptIndicAction.getLow();
                                            String str4 = (String) linkedHashMap.get(low != null ? low : "");
                                            double dDoubleValue3 = (str4 == null || (dN2 = Ah.v.n(str4)) == null) ? 0.0d : dN2.doubleValue();
                                            if (!(dDoubleValue2 == 0.0d)) {
                                                if (!(dDoubleValue3 == 0.0d)) {
                                                    if (dDoubleValue2 < dArr[0]) {
                                                        dArr[0] = dDoubleValue2;
                                                    }
                                                    if (dDoubleValue2 > dArr[1]) {
                                                        dArr[1] = dDoubleValue2;
                                                    }
                                                    if (dDoubleValue3 < dArr[0]) {
                                                        dArr[0] = dDoubleValue3;
                                                    }
                                                    if (dDoubleValue3 > dArr[1]) {
                                                        dArr[1] = dDoubleValue3;
                                                    }
                                                }
                                            }
                                        } else {
                                            dDoubleValue = 0.0d;
                                        }
                                        break;
                                    case -2020020818:
                                        if (action2.equals("plotText")) {
                                            String refSeries = scriptIndicAction.getRefSeries();
                                            str = (String) linkedHashMap.get(refSeries != null ? refSeries : "");
                                            if (str != null || str.length() == 0) {
                                                z10 = true;
                                            } else {
                                                z10 = false;
                                            }
                                            if (!z10 && (dN8 = Ah.v.n(str)) != null) {
                                                dDoubleValue = dN8.doubleValue();
                                            }
                                        } else {
                                            dDoubleValue = 0.0d;
                                        }
                                        break;
                                    case -608864346:
                                        if (action2.equals("label.new")) {
                                            String refSeries2 = scriptIndicAction.getRefSeries();
                                            str = (String) linkedHashMap.get(refSeries2 != null ? refSeries2 : "");
                                            if (str != null) {
                                                z10 = true;
                                            } else {
                                                z10 = true;
                                            }
                                            if (!z10) {
                                                dDoubleValue = dN8.doubleValue();
                                            }
                                        } else {
                                            dDoubleValue = 0.0d;
                                        }
                                        break;
                                    case -405487794:
                                        if (action2.equals("plotCandle")) {
                                            String high2 = scriptIndicAction.getHigh();
                                            if (high2 == null) {
                                                high2 = "";
                                            }
                                            String str5 = (String) linkedHashMap.get(high2);
                                            double dDoubleValue4 = (str5 == null || (dN5 = Ah.v.n(str5)) == null) ? 0.0d : dN5.doubleValue();
                                            String low2 = scriptIndicAction.getLow();
                                            String str6 = (String) linkedHashMap.get(low2 != null ? low2 : "");
                                            double dDoubleValue5 = (str6 == null || (dN4 = Ah.v.n(str6)) == null) ? 0.0d : dN4.doubleValue();
                                            if (!(dDoubleValue4 == 0.0d)) {
                                                if (!(dDoubleValue5 == 0.0d)) {
                                                    if (dDoubleValue4 < dArr[0]) {
                                                        dArr[0] = dDoubleValue4;
                                                    }
                                                    if (dDoubleValue4 > dArr[1]) {
                                                        dArr[1] = dDoubleValue4;
                                                    }
                                                    if (dDoubleValue5 < dArr[0]) {
                                                        dArr[0] = dDoubleValue5;
                                                    }
                                                    if (dDoubleValue5 > dArr[1]) {
                                                        dArr[1] = dDoubleValue5;
                                                    }
                                                }
                                            }
                                        } else {
                                            dDoubleValue = 0.0d;
                                        }
                                        break;
                                    case -392601705:
                                        if (action2.equals("plotColumn")) {
                                            String series2 = scriptIndicAction.getSeries();
                                            String str7 = (String) linkedHashMap.get(series2 != null ? series2 : "0");
                                            if (!(str7 == null || str7.length() == 0) && (dN6 = Ah.v.n(str7)) != null) {
                                                dDoubleValue = dN6.doubleValue();
                                            }
                                        } else {
                                            dDoubleValue = 0.0d;
                                        }
                                        break;
                                    case 3143043:
                                        if (!action2.equals("fill")) {
                                            dDoubleValue = 0.0d;
                                        }
                                        break;
                                    case 3443937:
                                        if (action2.equals("plot")) {
                                            String series3 = scriptIndicAction.getSeries();
                                            String str8 = (String) linkedHashMap.get(series3 != null ? series3 : "0");
                                            if (!(str8 == null || str8.length() == 0) && (dN7 = Ah.v.n(str8)) != null) {
                                                dDoubleValue = dN7.doubleValue();
                                            }
                                        } else {
                                            dDoubleValue = 0.0d;
                                        }
                                        break;
                                    case 71185149:
                                        if (action2.equals("box.new")) {
                                            String refSeries3 = scriptIndicAction.getRefSeries();
                                            str = (String) linkedHashMap.get(refSeries3 != null ? refSeries3 : "");
                                            if (str != null) {
                                                z10 = true;
                                            } else {
                                                z10 = true;
                                            }
                                            if (!z10) {
                                                dDoubleValue = dN8.doubleValue();
                                            }
                                        } else {
                                            dDoubleValue = 0.0d;
                                        }
                                        break;
                                    case 1187522726:
                                        if (action2.equals("line.new")) {
                                            String refSeries4 = scriptIndicAction.getRefSeries();
                                            str = (String) linkedHashMap.get(refSeries4 != null ? refSeries4 : "");
                                            if (str != null) {
                                                z10 = true;
                                            } else {
                                                z10 = true;
                                            }
                                            if (!z10) {
                                                dDoubleValue = dN8.doubleValue();
                                            }
                                        } else {
                                            dDoubleValue = 0.0d;
                                        }
                                        break;
                                    case 1803007808:
                                        if (action2.equals("plotShape")) {
                                            String refSeries5 = scriptIndicAction.getRefSeries();
                                            String str9 = (String) linkedHashMap.get(refSeries5 != null ? refSeries5 : "");
                                            if (!(str9 == null || str9.length() == 0) && (dN9 = Ah.v.n(str9)) != null) {
                                                dDoubleValue = dN9.doubleValue();
                                            }
                                        } else {
                                            dDoubleValue = 0.0d;
                                        }
                                        break;
                                    default:
                                        dDoubleValue = 0.0d;
                                        break;
                                }
                                if (!Double.isNaN(dDoubleValue)) {
                                    if (dDoubleValue < dArr[0]) {
                                        dArr[0] = KLineManager.f142490O.a().B() * dDoubleValue;
                                    }
                                    if (dDoubleValue > dArr[1]) {
                                        dArr[1] = KLineManager.f142490O.a().B() * dDoubleValue;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @Override // Rj.AbstractC2755v
    public void q(dk.s sVar) {
        this.f96465o.clear();
        this.f96465o = new ArrayList(sVar.q().R());
    }

    public final List s() {
        return this.f96465o;
    }

    public final sp.aicoin_kline.core.indicator.config.F t() {
        return this.f96464n;
    }
}
