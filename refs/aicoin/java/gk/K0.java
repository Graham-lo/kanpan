package gk;

import Rj.C2732n;
import Rj.C2741q;
import Rj.y1;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.chart.data.ScriptDrawData;
import sp.aicoin_kline.chart.data.ScriptIndicAction;
import sp.aicoin_kline.chart.data.ScriptIndicConfig;

/* JADX INFO: loaded from: classes7.dex */
public final class K0 extends AbstractC7467h0 {

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public List f96469t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public final String f96470u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public double[] f96471v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public Long f96472w;

    public K0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10, String str2) {
        super(c2732n, str, f10, false, 8, null);
        this.f96469t = new ArrayList();
        this.f96470u = str2;
    }

    public static Map D(Map map, long j10) {
        Object obj;
        Map map2;
        Map map3 = (Map) map.get(String.valueOf(j10));
        if (map3 != null && !map3.isEmpty()) {
            return map3;
        }
        Set setKeySet = map.keySet();
        ArrayList arrayList = new ArrayList();
        Iterator it = setKeySet.iterator();
        while (it.hasNext()) {
            Long lR = Ah.w.r((String) it.next());
            if (lR != null) {
                arrayList.add(lR);
            }
        }
        if (arrayList.isEmpty()) {
            return Sf.N.j();
        }
        Iterator it2 = arrayList.iterator();
        if (it2.hasNext()) {
            Object next = it2.next();
            if (it2.hasNext()) {
                long jAbs = Math.abs(((Number) next).longValue() - j10);
                do {
                    Object next2 = it2.next();
                    long jAbs2 = Math.abs(((Number) next2).longValue() - j10);
                    if (jAbs > jAbs2) {
                        next = next2;
                        jAbs = jAbs2;
                    }
                } while (it2.hasNext());
            }
            obj = next;
        } else {
            obj = null;
        }
        Long l10 = (Long) obj;
        return (l10 == null || (map2 = (Map) map.get(String.valueOf(l10.longValue()))) == null) ? Sf.N.j() : map2;
    }

    /* JADX WARN: Code duplicated, block: B:127:0x0181  */
    /* JADX WARN: Code duplicated, block: B:130:0x0188  */
    /* JADX WARN: Code duplicated, block: B:133:0x0191  */
    /* JADX WARN: Code duplicated, block: B:139:0x01a3  */
    /* JADX WARN: Code duplicated, block: B:36:0x007c A[PHI: r3
      0x007c: PHI (r3v40 double) = (r3v3 double), (r3v26 double), (r3v31 double), (r3v36 double), (r3v43 double) binds: [B:199:0x0242, B:78:0x00f8, B:59:0x00c0, B:140:0x01a4, B:34:0x0078] A[DONT_GENERATE, DONT_INLINE]] */
    public static void E(Map map, ScriptDrawData scriptDrawData, double[] dArr) {
        List<ScriptIndicAction> action;
        double dDoubleValue;
        Double dN;
        Double dN2;
        Double dN3;
        Double dN4;
        Double dN5;
        Double dN6;
        Double dN7;
        String str;
        Double dN8;
        Double dN9;
        ScriptIndicConfig config = scriptDrawData.getConfig();
        if (config == null || (action = config.getAction()) == null) {
            return;
        }
        for (ScriptIndicAction scriptIndicAction : action) {
            if (!AbstractC7609s.f(scriptIndicAction.getDisplay(), Boolean.FALSE)) {
                Boolean excludeRange = scriptIndicAction.getExcludeRange();
                boolean zBooleanValue = excludeRange != null ? excludeRange.booleanValue() : false;
                String action2 = scriptIndicAction.getAction();
                double d10 = Double.NaN;
                switch (action2.hashCode()) {
                    case -2020374621:
                        if (action2.equals("plotHist")) {
                            String series = scriptIndicAction.getSeries();
                            String str2 = (String) map.get(series != null ? series : "0");
                            dDoubleValue = (str2 == null || str2.length() == 0 || (dN = Ah.v.n(str2)) == null) ? Double.NaN : dN.doubleValue();
                            if (!zBooleanValue) {
                                d10 = dDoubleValue;
                            }
                        }
                        break;
                    case -2020167279:
                        if (action2.equals("plotOhlc") && !zBooleanValue) {
                            String high = scriptIndicAction.getHigh();
                            if (high == null) {
                                high = "";
                            }
                            String str3 = (String) map.get(high);
                            double dDoubleValue2 = (str3 == null || (dN3 = Ah.v.n(str3)) == null) ? 0.0d : dN3.doubleValue();
                            String low = scriptIndicAction.getLow();
                            String str4 = (String) map.get(low != null ? low : "");
                            double dDoubleValue3 = (str4 == null || (dN2 = Ah.v.n(str4)) == null) ? 0.0d : dN2.doubleValue();
                            if (dDoubleValue2 != 0.0d && dDoubleValue3 != 0.0d) {
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
                        break;
                    case -2020020818:
                        if (action2.equals("plotText")) {
                            String refSeries = scriptIndicAction.getRefSeries();
                            str = (String) map.get(refSeries != null ? refSeries : "0");
                            if (str != null || str.length() == 0 || (dN8 = Ah.v.n(str)) == null) {
                                dDoubleValue = Double.NaN;
                            } else {
                                dDoubleValue = dN8.doubleValue();
                            }
                            if (!zBooleanValue) {
                                d10 = dDoubleValue;
                            }
                        }
                        break;
                    case -608864346:
                        if (action2.equals("label.new")) {
                            String refSeries2 = scriptIndicAction.getRefSeries();
                            str = (String) map.get(refSeries2 != null ? refSeries2 : "0");
                            if (str != null) {
                                dDoubleValue = Double.NaN;
                            } else {
                                dDoubleValue = Double.NaN;
                            }
                            if (!zBooleanValue) {
                                d10 = dDoubleValue;
                            }
                        }
                        break;
                    case -405487794:
                        if (action2.equals("plotCandle") && !zBooleanValue) {
                            String high2 = scriptIndicAction.getHigh();
                            if (high2 == null) {
                                high2 = "";
                            }
                            String str5 = (String) map.get(high2);
                            double dDoubleValue4 = (str5 == null || (dN5 = Ah.v.n(str5)) == null) ? 0.0d : dN5.doubleValue();
                            String low2 = scriptIndicAction.getLow();
                            String str6 = (String) map.get(low2 != null ? low2 : "");
                            double dDoubleValue5 = (str6 == null || (dN4 = Ah.v.n(str6)) == null) ? 0.0d : dN4.doubleValue();
                            if (dDoubleValue4 != 0.0d && dDoubleValue5 != 0.0d) {
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
                        break;
                    case -392601705:
                        if (action2.equals("plotColumn")) {
                            String series2 = scriptIndicAction.getSeries();
                            String str7 = (String) map.get(series2 != null ? series2 : "0");
                            dDoubleValue = (str7 == null || str7.length() == 0 || (dN6 = Ah.v.n(str7)) == null) ? Double.NaN : dN6.doubleValue();
                            if (!zBooleanValue) {
                                d10 = dDoubleValue;
                            }
                        }
                        break;
                    case 3143043:
                        action2.equals("fill");
                        break;
                    case 3443937:
                        if (action2.equals("plot")) {
                            String series3 = scriptIndicAction.getSeries();
                            String str8 = (String) map.get(series3 != null ? series3 : "0");
                            dDoubleValue = (str8 == null || str8.length() == 0 || (dN7 = Ah.v.n(str8)) == null) ? Double.NaN : dN7.doubleValue();
                            if (!zBooleanValue) {
                                d10 = dDoubleValue;
                            }
                        }
                        break;
                    case 71185149:
                        if (action2.equals("box.new")) {
                            String refSeries3 = scriptIndicAction.getRefSeries();
                            str = (String) map.get(refSeries3 != null ? refSeries3 : "0");
                            if (str != null) {
                                dDoubleValue = Double.NaN;
                            } else {
                                dDoubleValue = Double.NaN;
                            }
                            if (!zBooleanValue) {
                                d10 = dDoubleValue;
                            }
                        }
                        break;
                    case 1187522726:
                        if (action2.equals("line.new")) {
                            String refSeries4 = scriptIndicAction.getRefSeries();
                            str = (String) map.get(refSeries4 != null ? refSeries4 : "0");
                            if (str != null) {
                                dDoubleValue = Double.NaN;
                            } else {
                                dDoubleValue = Double.NaN;
                            }
                            if (!zBooleanValue) {
                                d10 = dDoubleValue;
                            }
                        }
                        break;
                    case 1803007808:
                        if (action2.equals("plotShape")) {
                            String refSeries5 = scriptIndicAction.getRefSeries();
                            String str9 = (String) map.get(refSeries5 != null ? refSeries5 : "");
                            dDoubleValue = (str9 == null || str9.length() == 0 || (dN9 = Ah.v.n(str9)) == null) ? Double.NaN : dN9.doubleValue();
                            if (!zBooleanValue) {
                                d10 = dDoubleValue;
                            }
                        }
                        break;
                }
                if (!Double.isNaN(d10)) {
                    if (d10 < dArr[0]) {
                        dArr[0] = d10;
                    }
                    if (d10 > dArr[1]) {
                        dArr[1] = d10;
                    }
                }
            }
        }
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        this.f96471v = null;
        ArrayList arrayList = new ArrayList(sVar.q().S());
        this.f96469t = arrayList;
        nk.x.f134260a.f(arrayList);
    }

    public final List F() {
        return this.f96469t;
    }

    @Override // gk.AbstractC7467h0, Rj.AbstractC2755v
    public void l(int i10, double[] dArr) {
        Object obj;
        Map<String, Map<String, String>> calculateHistoryData;
        String id2;
        C2741q c2741qB = h().b();
        dArr[0] = Double.MAX_VALUE;
        dArr[1] = -1.7976931348623157E308d;
        y1 y1VarM = c2741qB.m(c());
        if (y1VarM == null) {
            return;
        }
        this.f96472w = Long.valueOf(y1VarM.H(i10));
        try {
            Iterator it = new ArrayList(this.f96469t).iterator();
            while (true) {
                obj = null;
                if (!it.hasNext()) {
                    break;
                }
                Object next = it.next();
                String str = this.f96470u;
                ScriptIndicConfig config = ((ScriptDrawData) next).getConfig();
                if (config == null || (id2 = config.getId()) == null) {
                    id2 = "";
                }
                if (Ah.y.T(str, id2, false, 2, null)) {
                    obj = next;
                    break;
                }
            }
            ScriptDrawData scriptDrawData = (ScriptDrawData) obj;
            if (scriptDrawData != null && (calculateHistoryData = scriptDrawData.getCalculateHistoryData()) != null && !calculateHistoryData.isEmpty()) {
                Long l10 = this.f96472w;
                E(D(calculateHistoryData, l10 != null ? l10.longValue() : 0L), scriptDrawData, dArr);
                double d10 = dArr[0];
                if ((d10 != Double.MAX_VALUE || dArr[1] != -1.7976931348623157E308d) && d10 <= dArr[1]) {
                    return;
                }
                double[] dArr2 = this.f96471v;
                if (dArr2 != null) {
                    dArr[0] = dArr2[0];
                    dArr[1] = dArr2[1];
                    return;
                }
                double[] dArr3 = {Double.MAX_VALUE, -1.7976931348623157E308d};
                Iterator<Map<String, String>> it2 = calculateHistoryData.values().iterator();
                while (it2.hasNext()) {
                    E(it2.next(), scriptDrawData, dArr3);
                }
                double d11 = dArr3[0];
                if ((d11 == Double.MAX_VALUE && dArr3[1] == -1.7976931348623157E308d) || d11 > dArr3[1]) {
                    dArr3[0] = 0.0d;
                    dArr3[1] = 1.0d;
                }
                double d12 = dArr3[0];
                double d13 = dArr3[1];
                this.f96471v = new double[]{d12, d13};
                dArr[0] = d12;
                dArr[1] = d13;
            }
        } catch (Exception unused) {
        }
    }
}
