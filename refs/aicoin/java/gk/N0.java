package gk;

import Qf.InterfaceC2632j;
import Rj.C2732n;
import Rj.C2741q;
import Rj.y1;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.chart.data.ScriptDrawData;
import sp.aicoin_kline.chart.data.ScriptIndicAction;
import sp.aicoin_kline.chart.data.ScriptIndicConfig;

/* JADX INFO: loaded from: classes7.dex */
public abstract class N0 extends AbstractC7467h0 {

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public Map f96478t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public Long f96479u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public final InterfaceC2632j f96480v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public ScriptDrawData f96481w;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public Map f96482x;

    public N0(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10, false, 8, null);
        this.f96478t = new LinkedHashMap();
        this.f96480v = Qf.k.b(new M0(c2732n));
        new LinkedHashMap();
        this.f96482x = new LinkedHashMap();
    }

    public static final C2741q D(C2732n c2732n) {
        return c2732n.b();
    }

    @Override // gk.AbstractC7467h0
    public void A(dk.s sVar) {
        B();
        this.f96478t = sVar.q().W();
    }

    public abstract String E();

    public final Map F() {
        return this.f96478t;
    }

    /* JADX WARN: Can't fix incorrect switch cases order, some code will duplicate */
    /* JADX WARN: Code duplicated, block: B:101:0x019d A[PHI: r0
      0x019d: PHI (r0v29 java.lang.String) = (r0v24 java.lang.String), (r0v30 java.lang.String) binds: [B:99:0x019a, B:103:0x01a3] A[DONT_GENERATE, DONT_INLINE]] */
    /* JADX WARN: Code duplicated, block: B:106:0x01ad  */
    /* JADX WARN: Code duplicated, block: B:109:0x01b8  */
    /* JADX WARN: Code duplicated, block: B:55:0x00ef  */
    /* JADX WARN: Code duplicated, block: B:58:0x00ff  */
    /* JADX WARN: Code duplicated, block: B:60:0x0107  */
    /* JADX WARN: Code duplicated, block: B:66:0x011d  */
    /* JADX WARN: Code duplicated, block: B:70:0x0125  */
    /* JADX WARN: Code duplicated, block: B:80:0x0159  */
    /* JADX WARN: Code duplicated, block: B:83:0x0168  */
    /* JADX WARN: Code duplicated, block: B:85:0x0177  */
    /* JADX WARN: Code duplicated, block: B:96:0x0190  */
    /* JADX WARN: Instruction removed from duplicated block: B:58:0x00ff, please report this as an issue */
    @Override // gk.AbstractC7467h0, Rj.AbstractC2755v
    public void l(int i10, double[] dArr) {
        Map<String, String> map;
        ScriptIndicConfig config;
        List<ScriptIndicAction> action;
        double dDoubleValue;
        double dDoubleValue2;
        Double dN;
        Double dN2;
        String refSeries;
        Double dN3;
        dArr[0] = Double.MAX_VALUE;
        dArr[1] = -1.7976931348623157E308d;
        y1 y1VarM = ((C2741q) this.f96480v.getValue()).m(c());
        if (y1VarM == null) {
            return;
        }
        this.f96479u = Long.valueOf(y1VarM.H(i10));
        ScriptDrawData scriptDrawData = (ScriptDrawData) this.f96478t.get(E());
        if (scriptDrawData == null) {
            return;
        }
        this.f96481w = scriptDrawData;
        Map<String, Map<String, String>> calculateHistoryData = scriptDrawData.getCalculateHistoryData();
        if (calculateHistoryData == null || (map = calculateHistoryData.get(String.valueOf(this.f96479u))) == null) {
            return;
        }
        this.f96482x = map;
        ScriptDrawData scriptDrawData2 = this.f96481w;
        if (scriptDrawData2 == null || (config = scriptDrawData2.getConfig()) == null || (action = config.getAction()) == null) {
            return;
        }
        for (ScriptIndicAction scriptIndicAction : action) {
            if (!AbstractC7609s.f(scriptIndicAction.getDisplay(), Boolean.FALSE)) {
                switch (scriptIndicAction.getAction()) {
                    case "plotHist":
                        Map map2 = this.f96482x;
                        if (!AbstractC7609s.f(scriptIndicAction.getExcludeRange(), Boolean.TRUE)) {
                            dDoubleValue = Double.NaN;
                        } else {
                            String action2 = scriptIndicAction.getAction();
                            int iHashCode = action2.hashCode();
                            String str = "0";
                            if (iHashCode == -2020374621 ? action2.equals("plotHist") : iHashCode == -392601705 ? action2.equals("plotColumn") : iHashCode == 3443937 && action2.equals("plot")) {
                                refSeries = scriptIndicAction.getSeries();
                                if (refSeries != null) {
                                    str = refSeries;
                                }
                            } else {
                                refSeries = scriptIndicAction.getRefSeries();
                                if (refSeries != null) {
                                    str = refSeries;
                                }
                            }
                            String str2 = (String) map2.get(str);
                            if (str2 != null || (dN3 = Ah.v.n(str2)) == null) {
                                dDoubleValue = Double.NaN;
                            } else {
                                dDoubleValue = dN3.doubleValue();
                            }
                        }
                        break;
                    case "plotOhlc":
                        Map map3 = this.f96482x;
                        if (!AbstractC7609s.f(scriptIndicAction.getExcludeRange(), Boolean.TRUE)) {
                            String high = scriptIndicAction.getHigh();
                            if (high == null) {
                                high = "";
                            }
                            String str3 = (String) map3.get(high);
                            double dDoubleValue3 = 0.0d;
                            if (str3 != null || (dN2 = Ah.v.n(str3)) == null) {
                                dDoubleValue2 = 0.0d;
                            } else {
                                dDoubleValue2 = dN2.doubleValue();
                            }
                            String low = scriptIndicAction.getLow();
                            String str4 = (String) map3.get(low != null ? low : "");
                            if (str4 != null && (dN = Ah.v.n(str4)) != null) {
                                dDoubleValue3 = dN.doubleValue();
                            }
                            dArr[0] = Math.min(dArr[0], Math.min(dDoubleValue2, dDoubleValue3));
                            dArr[1] = Math.max(dArr[1], Math.max(dDoubleValue2, dDoubleValue3));
                        }
                    case "plotText":
                    case "label.new":
                        Map map4 = this.f96482x;
                        if (!AbstractC7609s.f(scriptIndicAction.getExcludeRange(), Boolean.TRUE)) {
                            dDoubleValue = Double.NaN;
                        } else {
                            String action3 = scriptIndicAction.getAction();
                            int iHashCode2 = action3.hashCode();
                            String str5 = "0";
                            if (iHashCode2 == -2020374621 ? action3.equals("plotHist") : iHashCode2 == -392601705 ? action3.equals("plotColumn") : iHashCode2 == 3443937 && action3.equals("plot")) {
                                refSeries = scriptIndicAction.getSeries();
                                if (refSeries != null) {
                                    str5 = refSeries;
                                }
                            } else {
                                refSeries = scriptIndicAction.getRefSeries();
                                if (refSeries != null) {
                                    str5 = refSeries;
                                }
                            }
                            String str6 = (String) map4.get(str5);
                            if (str6 != null || (dN3 = Ah.v.n(str6)) == null) {
                                dDoubleValue = Double.NaN;
                            } else {
                                dDoubleValue = dN3.doubleValue();
                            }
                        }
                        break;
                    case "plotCandle":
                        Map map5 = this.f96482x;
                        if (!AbstractC7609s.f(scriptIndicAction.getExcludeRange(), Boolean.TRUE)) {
                            String high2 = scriptIndicAction.getHigh();
                            if (high2 == null) {
                                high2 = "";
                            }
                            String str7 = (String) map5.get(high2);
                            double dDoubleValue4 = 0.0d;
                            if (str7 != null || (dN2 = Ah.v.n(str7)) == null) {
                                dDoubleValue2 = 0.0d;
                            } else {
                                dDoubleValue2 = dN2.doubleValue();
                            }
                            String low2 = scriptIndicAction.getLow();
                            String str8 = (String) map5.get(low2 != null ? low2 : "");
                            if (str8 != null && (dN = Ah.v.n(str8)) != null) {
                                dDoubleValue4 = dN.doubleValue();
                            }
                            dArr[0] = Math.min(dArr[0], Math.min(dDoubleValue2, dDoubleValue4));
                            dArr[1] = Math.max(dArr[1], Math.max(dDoubleValue2, dDoubleValue4));
                        }
                    case "plotColumn":
                    case "plot":
                    case "box.new":
                    case "line.new":
                    case "plotShape":
                        Map map6 = this.f96482x;
                        if (!AbstractC7609s.f(scriptIndicAction.getExcludeRange(), Boolean.TRUE)) {
                            dDoubleValue = Double.NaN;
                        } else {
                            String action4 = scriptIndicAction.getAction();
                            int iHashCode3 = action4.hashCode();
                            String str9 = "0";
                            if (iHashCode3 == -2020374621 ? action4.equals("plotHist") : iHashCode3 == -392601705 ? action4.equals("plotColumn") : iHashCode3 == 3443937 && action4.equals("plot")) {
                                refSeries = scriptIndicAction.getSeries();
                                if (refSeries != null) {
                                    str9 = refSeries;
                                }
                            } else {
                                refSeries = scriptIndicAction.getRefSeries();
                                if (refSeries != null) {
                                    str9 = refSeries;
                                }
                            }
                            String str10 = (String) map6.get(str9);
                            if (str10 != null || (dN3 = Ah.v.n(str10)) == null) {
                                dDoubleValue = Double.NaN;
                            } else {
                                dDoubleValue = dN3.doubleValue();
                            }
                        }
                        break;
                    default:
                        dDoubleValue = Double.NaN;
                        break;
                }
                if (!Double.isNaN(dDoubleValue)) {
                    dArr[0] = Math.min(dArr[0], dDoubleValue);
                    dArr[1] = Math.max(dArr[1], dDoubleValue);
                }
            }
        }
    }
}
