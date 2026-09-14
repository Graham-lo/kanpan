package fk;

import Rj.AbstractC2693a;
import Rj.AbstractC2735o;
import Rj.AbstractC2755v;
import Rj.C2702d;
import Rj.C2732n;
import Rj.C2741q;
import Rj.C2765z;
import Rj.y1;
import android.content.res.Resources;
import android.graphics.Canvas;
import android.graphics.Paint;
import gk.J0;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.R;
import sp.aicoin_kline.chart.data.ActionOutput;
import sp.aicoin_kline.chart.data.ScriptDrawData;
import sp.aicoin_kline.chart.data.ScriptIndicAction;
import sp.aicoin_kline.chart.data.ScriptIndicConfig;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class S extends AbstractC2693a {

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public Paint f95128A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public y1 f95129B;

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public J0 f95130C;

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public int f95131D;

    /* JADX INFO: renamed from: E, reason: collision with root package name */
    public int f95132E;

    /* JADX INFO: renamed from: F, reason: collision with root package name */
    public int f95133F;

    /* JADX INFO: renamed from: G, reason: collision with root package name */
    public final ArrayList f95134G;

    /* JADX INFO: renamed from: H, reason: collision with root package name */
    public String f95135H;

    /* JADX INFO: renamed from: I, reason: collision with root package name */
    public String f95136I;

    /* JADX INFO: renamed from: J, reason: collision with root package name */
    public String f95137J;

    /* JADX INFO: renamed from: K, reason: collision with root package name */
    public String f95138K;

    public S(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f95131D = KLineManager.f142490O.a().j();
        new ArrayList();
        this.f95134G = new ArrayList();
        this.f95135H = "";
        this.f95136I = "";
        this.f95137J = "";
        this.f95138K = "";
    }

    public static final List H(S s10, int i10) {
        return (List) s10.f95134G.get(i10);
    }

    /* JADX WARN: Can't fix incorrect switch cases order, some code will duplicate */
    /* JADX WARN: Code duplicated, block: B:166:0x035f  */
    /* JADX WARN: Code duplicated, block: B:246:0x04dd A[PHI: r15 r32
      0x04dd: PHI (r15v12 sp.aicoin_kline.chart.data.ScriptDrawData) = 
      (r15v8 sp.aicoin_kline.chart.data.ScriptDrawData)
      (r15v9 sp.aicoin_kline.chart.data.ScriptDrawData)
      (r15v9 sp.aicoin_kline.chart.data.ScriptDrawData)
      (r15v9 sp.aicoin_kline.chart.data.ScriptDrawData)
      (r15v9 sp.aicoin_kline.chart.data.ScriptDrawData)
      (r15v10 sp.aicoin_kline.chart.data.ScriptDrawData)
      (r15v10 sp.aicoin_kline.chart.data.ScriptDrawData)
      (r15v11 sp.aicoin_kline.chart.data.ScriptDrawData)
      (r15v11 sp.aicoin_kline.chart.data.ScriptDrawData)
      (r15v11 sp.aicoin_kline.chart.data.ScriptDrawData)
      (r15v11 sp.aicoin_kline.chart.data.ScriptDrawData)
      (r15v11 sp.aicoin_kline.chart.data.ScriptDrawData)
      (r8v9 sp.aicoin_kline.chart.data.ScriptDrawData)
     binds: [B:166:0x035f, B:319:0x0645, B:325:0x0656, B:327:0x065c, B:330:0x0664, B:273:0x0538, B:317:0x0626, B:248:0x04ea, B:260:0x050b, B:265:0x051a, B:267:0x0520, B:270:0x0527, B:245:0x04c9] A[DONT_GENERATE, DONT_INLINE]
      0x04dd: PHI (r32v4 java.util.Map) = 
      (r32v0 java.util.Map)
      (r32v1 java.util.Map)
      (r32v1 java.util.Map)
      (r32v1 java.util.Map)
      (r32v1 java.util.Map)
      (r32v2 java.util.Map)
      (r32v2 java.util.Map)
      (r32v3 java.util.Map)
      (r32v3 java.util.Map)
      (r32v3 java.util.Map)
      (r32v3 java.util.Map)
      (r32v3 java.util.Map)
      (r32v5 java.util.Map)
     binds: [B:166:0x035f, B:319:0x0645, B:325:0x0656, B:327:0x065c, B:330:0x0664, B:273:0x0538, B:317:0x0626, B:248:0x04ea, B:260:0x050b, B:265:0x051a, B:267:0x0520, B:270:0x0527, B:245:0x04c9] A[DONT_GENERATE, DONT_INLINE]] */
    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        C2702d c2702dD;
        y1 y1Var;
        C2765z c2765zH;
        Rj.G gH;
        String strValueOf;
        Map mapZ;
        y1 y1Var2;
        Iterator it;
        sp.aicoin_kline.core.indicator.config.F f10;
        Map map;
        Double dN;
        double dDoubleValue;
        String scriptRef;
        Double dN2;
        Double dN3;
        Double dN4;
        Double dN5;
        Double dN6;
        Double dN7;
        String scriptRef2;
        Double dN8;
        Double dN9;
        Double dN10;
        Double dN11;
        Double dN12;
        Double dN13;
        boolean z10;
        String scriptRef3;
        Double dN14;
        Double dN15;
        Ah.j.b bVarA;
        Paint paint;
        String str;
        Integer numP;
        Integer numP2;
        String scriptRef4;
        boolean z11 = true;
        J0 j10 = this.f95130C;
        if (j10 == null || (c2702dD = j().d()) == null || (y1Var = this.f95129B) == null || (c2765zH = j().i().h(c())) == null || (gH = j().h()) == null) {
            return;
        }
        sp.aicoin_kline.core.indicator.config.F fT = j10.t();
        int iD = c2765zH.D() - 1;
        boolean zF = nk.n.f(13);
        this.f95132E = 0;
        int iIntValue = ((Number) p162hb.e.c(zF, Integer.valueOf(gH.t()), Integer.valueOf(y1Var.D()))).intValue();
        if (gH.B() || y1Var.E()) {
            iD = iIntValue;
        }
        long jH = y1Var.H(iD);
        List listR1 = Sf.z.r1(j10.s());
        this.f95134G.clear();
        canvas.save();
        Iterator it2 = listR1.iterator();
        while (it2.hasNext()) {
            ScriptDrawData scriptDrawData = (ScriptDrawData) it2.next();
            ArrayList arrayList = new ArrayList();
            ScriptIndicConfig config = scriptDrawData.getConfig();
            String errorMsg = config != null ? config.getErrorMsg() : null;
            if (errorMsg == null || errorMsg.length() == 0) {
                ScriptIndicConfig config2 = scriptDrawData.getConfig();
                strValueOf = String.valueOf(config2 != null ? config2.getTitle() : null);
            } else {
                StringBuilder sb2 = new StringBuilder();
                ScriptIndicConfig config3 = scriptDrawData.getConfig();
                sb2.append(config3 != null ? config3.getTitle() : null);
                sb2.append(' ');
                ScriptIndicConfig config4 = scriptDrawData.getConfig();
                sb2.append(config4 != null ? config4.getErrorMsg() : null);
                strValueOf = sb2.toString();
            }
            Paint paint2 = this.f95128A;
            if (paint2 != null) {
                paint2.setColor(this.f95133F);
                Qf.H h10 = Qf.H.f17640a;
            }
            ScriptIndicConfig config5 = scriptDrawData.getConfig();
            arrayList.add(new AbstractC2693a.b(strValueOf + ' ', this.f95128A, true, true, (config5 == null || (scriptRef4 = config5.getScriptRef()) == null) ? "" : scriptRef4, true));
            ScriptIndicConfig config6 = scriptDrawData.getConfig();
            if ((config6 != null ? config6.getAction() : null) != null && (mapZ = Sf.N.z(scriptDrawData.getCalculateHistoryData())) != null && !mapZ.isEmpty()) {
                int i10 = 0;
                for (Object obj : Sf.z.u1(scriptDrawData.getConfig().getAction())) {
                    int i11 = i10 + 1;
                    if (i10 < 0) {
                        Sf.r.x();
                    }
                    ScriptIndicAction scriptIndicAction = (ScriptIndicAction) obj;
                    String title = scriptIndicAction.getTitle();
                    String str2 = (title == null || title.length() == 0) ? "k" + i10 + ": " : scriptIndicAction.getTitle() + ": ";
                    String offset = scriptIndicAction.getOffset();
                    int iIntValue2 = (offset == null || (numP2 = Ah.w.p(offset)) == null) ? 0 : numP2.intValue();
                    Map linkedHashMap = (Map) mapZ.get(String.valueOf(iIntValue2 != 0 ? iIntValue2 > 0 ? y1Var.H(iD - iIntValue2) : y1Var.H(iD + iIntValue2) : jH));
                    if (linkedHashMap == null) {
                        linkedHashMap = new LinkedHashMap();
                    }
                    if (linkedHashMap.isEmpty()) {
                        y1Var2 = y1Var;
                        it = it2;
                        f10 = fT;
                        scriptDrawData = scriptDrawData;
                        map = mapZ;
                    } else {
                        StringBuilder sb3 = new StringBuilder();
                        ActionOutput output = scriptIndicAction.getOutput();
                        sb3.append(output != null ? output.getColor() : null);
                        sb3.append("Value");
                        String string = sb3.toString();
                        y1Var2 = y1Var;
                        Paint paint3 = new Paint(1);
                        paint3.setTextSize(Xj.a.d(9));
                        paint3.setAntiAlias(true);
                        this.f95128A = paint3;
                        int iA = (string == null || string.length() == 0 || AbstractC7609s.f(string, "nullValue") || (str = (String) linkedHashMap.get(string)) == null || (numP = Ah.w.p(str)) == null) ? fT.u()[this.f95132E].a() : numP.intValue();
                        paint3.setColor(iA);
                        Qf.H h11 = Qf.H.f17640a;
                        StringBuilder sb4 = new StringBuilder();
                        ActionOutput output2 = scriptIndicAction.getOutput();
                        sb4.append(output2 != null ? output2.getColor() : null);
                        sb4.append("originValue");
                        String str3 = (String) linkedHashMap.get(sb4.toString());
                        double dDoubleValue2 = 0.0d;
                        if (str3 == null || str3.length() == 0) {
                            it = it2;
                            f10 = fT;
                        } else {
                            it = it2;
                            f10 = fT;
                            Ah.j jVarC = Ah.l.c(new Ah.l("rgba\\((\\d+),(\\d+),(\\d+),((?:\\d+(?:\\.\\d*)?|\\.\\d+))\\)"), str3, 0, 2, null);
                            if (jVarC != null && (bVarA = jVarC.a()) != null) {
                                Double dN16 = Ah.v.n((String) kk.j.a(bVarA, 4));
                                if (((float) ((dN16 != null ? dN16.doubleValue() : 0.0d) * ((double) 255))) == 0.0f && (paint = this.f95128A) != null) {
                                    paint.setColor(f10.u()[this.f95132E].a());
                                }
                            }
                        }
                        String action = scriptIndicAction.getAction();
                        switch (action.hashCode()) {
                            case -2020374621:
                                scriptDrawData = scriptDrawData;
                                map = mapZ;
                                if (action.equals("plotHist")) {
                                    Object series = scriptIndicAction.getSeries();
                                    if (series == null) {
                                        series = "";
                                    }
                                    String str4 = (String) linkedHashMap.get(series);
                                    if (str4 == null || str4.length() == 0 || (dN = Ah.v.n(str4)) == null) {
                                        dDoubleValue = Double.NaN;
                                    } else {
                                        dDoubleValue = dN.doubleValue();
                                    }
                                } else {
                                    dDoubleValue = Double.NaN;
                                }
                                break;
                            case -2020167279:
                                scriptDrawData = scriptDrawData;
                                map = mapZ;
                                if (action.equals("plotOhlc")) {
                                    nk.h hVar = nk.h.f134211a;
                                    Object high = scriptIndicAction.getHigh();
                                    if (high == null) {
                                        high = "";
                                    }
                                    String str5 = (String) linkedHashMap.get(high);
                                    String strG = hVar.g((str5 == null || (dN5 = Ah.v.n(str5)) == null) ? 0.0d : dN5.doubleValue(), AbstractC2735o.a(i()));
                                    Object open = scriptIndicAction.getOpen();
                                    if (open == null) {
                                        open = "";
                                    }
                                    String str6 = (String) linkedHashMap.get(open);
                                    String strG2 = hVar.g((str6 == null || (dN4 = Ah.v.n(str6)) == null) ? 0.0d : dN4.doubleValue(), AbstractC2735o.a(i()));
                                    Object low = scriptIndicAction.getLow();
                                    if (low == null) {
                                        low = "";
                                    }
                                    String str7 = (String) linkedHashMap.get(low);
                                    String strG3 = hVar.g((str7 == null || (dN3 = Ah.v.n(str7)) == null) ? 0.0d : dN3.doubleValue(), AbstractC2735o.a(i()));
                                    Object close = scriptIndicAction.getClose();
                                    if (close == null) {
                                        close = "";
                                    }
                                    String str8 = (String) linkedHashMap.get(close);
                                    if (str8 != null && (dN2 = Ah.v.n(str8)) != null) {
                                        dDoubleValue2 = dN2.doubleValue();
                                    }
                                    String str9 = this.f95136I + strG + ' ' + this.f95135H + strG2 + ' ' + this.f95137J + strG3 + ' ' + this.f95138K + hVar.g(dDoubleValue2, AbstractC2735o.a(i()));
                                    Paint paint4 = this.f95128A;
                                    ScriptIndicConfig config7 = scriptDrawData.getConfig();
                                    arrayList.add(new AbstractC2693a.b(str9, paint4, true, false, (config7 == null || (scriptRef = config7.getScriptRef()) == null) ? "" : scriptRef, true, 8, null));
                                }
                                dDoubleValue = Double.NaN;
                                break;
                            case -2020020818:
                                scriptDrawData = scriptDrawData;
                                map = mapZ;
                                if (action.equals("plotText")) {
                                    Object series2 = scriptIndicAction.getSeries();
                                    if (series2 == null) {
                                        series2 = "";
                                    }
                                    String str10 = (String) linkedHashMap.get(series2);
                                    if (((str10 == null || (dN7 = Ah.v.n(str10)) == null) ? 0.0d : dN7.doubleValue()) <= 0.0d) {
                                        dDoubleValue = Double.NaN;
                                    } else {
                                        Object refSeries = scriptIndicAction.getRefSeries();
                                        if (refSeries == null) {
                                            refSeries = "";
                                        }
                                        String str11 = (String) linkedHashMap.get(refSeries);
                                        if (str11 == null || str11.length() == 0 || (dN6 = Ah.v.n(str11)) == null) {
                                            dDoubleValue = Double.NaN;
                                        } else {
                                            dDoubleValue = dN6.doubleValue();
                                        }
                                    }
                                } else {
                                    dDoubleValue = Double.NaN;
                                }
                                break;
                            case -405487794:
                                if (action.equals("plotCandle")) {
                                    nk.h hVar2 = nk.h.f134211a;
                                    Object high2 = scriptIndicAction.getHigh();
                                    if (high2 == null) {
                                        high2 = "";
                                    }
                                    String str12 = (String) linkedHashMap.get(high2);
                                    String strG4 = hVar2.g((str12 == null || (dN11 = Ah.v.n(str12)) == null) ? 0.0d : dN11.doubleValue(), AbstractC2735o.a(i()));
                                    Object open2 = scriptIndicAction.getOpen();
                                    if (open2 == null) {
                                        open2 = "";
                                    }
                                    String str13 = (String) linkedHashMap.get(open2);
                                    String strG5 = hVar2.g((str13 == null || (dN10 = Ah.v.n(str13)) == null) ? 0.0d : dN10.doubleValue(), AbstractC2735o.a(i()));
                                    Object low2 = scriptIndicAction.getLow();
                                    if (low2 == null) {
                                        low2 = "";
                                    }
                                    String str14 = (String) linkedHashMap.get(low2);
                                    map = mapZ;
                                    String strG6 = hVar2.g((str14 == null || (dN9 = Ah.v.n(str14)) == null) ? 0.0d : dN9.doubleValue(), AbstractC2735o.a(i()));
                                    Object close2 = scriptIndicAction.getClose();
                                    if (close2 == null) {
                                        close2 = "";
                                    }
                                    String str15 = (String) linkedHashMap.get(close2);
                                    if (str15 != null && (dN8 = Ah.v.n(str15)) != null) {
                                        dDoubleValue2 = dN8.doubleValue();
                                    }
                                    String str16 = this.f95136I + strG4 + ' ' + this.f95135H + strG5 + ' ' + this.f95137J + strG6 + ' ' + this.f95138K + hVar2.g(dDoubleValue2, AbstractC2735o.a(i()));
                                    Paint paint5 = this.f95128A;
                                    ScriptIndicConfig config8 = scriptDrawData.getConfig();
                                    arrayList.add(new AbstractC2693a.b(str16, paint5, true, false, (config8 == null || (scriptRef2 = config8.getScriptRef()) == null) ? "" : scriptRef2, true, 8, null));
                                } else {
                                    scriptDrawData = scriptDrawData;
                                    map = mapZ;
                                }
                                dDoubleValue = Double.NaN;
                                break;
                            case -392601705:
                                if (action.equals("plotColumn")) {
                                    Object series3 = scriptIndicAction.getSeries();
                                    if (series3 == null) {
                                        series3 = "";
                                    }
                                    String str17 = (String) linkedHashMap.get(series3);
                                    if (str17 != null && str17.length() != 0 && (dN12 = Ah.v.n(str17)) != null) {
                                        dDoubleValue = dN12.doubleValue();
                                        scriptDrawData = scriptDrawData;
                                        map = mapZ;
                                    }
                                }
                                scriptDrawData = scriptDrawData;
                                map = mapZ;
                                dDoubleValue = Double.NaN;
                                break;
                            case 3143043:
                                action.equals("fill");
                                scriptDrawData = scriptDrawData;
                                map = mapZ;
                                dDoubleValue = Double.NaN;
                                break;
                            case 3443937:
                                if (action.equals("plot")) {
                                    Object series4 = scriptIndicAction.getSeries();
                                    if (series4 == null) {
                                        series4 = "";
                                    }
                                    String str18 = (String) linkedHashMap.get(series4);
                                    if (str18 != null && str18.length() != 0 && (dN13 = Ah.v.n(str18)) != null) {
                                        dDoubleValue = dN13.doubleValue();
                                        scriptDrawData = scriptDrawData;
                                        map = mapZ;
                                    }
                                }
                                scriptDrawData = scriptDrawData;
                                map = mapZ;
                                dDoubleValue = Double.NaN;
                                break;
                            case 1803007808:
                                if (action.equals("plotShape")) {
                                    Object series5 = scriptIndicAction.getSeries();
                                    if (series5 == null) {
                                        series5 = "";
                                    }
                                    String str19 = (String) linkedHashMap.get(series5);
                                    if (((str19 == null || (dN15 = Ah.v.n(str19)) == null) ? 0.0d : dN15.doubleValue()) > 0.0d) {
                                        Object refSeries2 = scriptIndicAction.getRefSeries();
                                        if (refSeries2 == null) {
                                            refSeries2 = "";
                                        }
                                        String str20 = (String) linkedHashMap.get(refSeries2);
                                        if (str20 != null && str20.length() != 0 && (dN14 = Ah.v.n(str20)) != null) {
                                            dDoubleValue = dN14.doubleValue();
                                            scriptDrawData = scriptDrawData;
                                            map = mapZ;
                                        }
                                    }
                                }
                                scriptDrawData = scriptDrawData;
                                map = mapZ;
                                dDoubleValue = Double.NaN;
                                break;
                            default:
                                scriptDrawData = scriptDrawData;
                                map = mapZ;
                                dDoubleValue = Double.NaN;
                                break;
                        }
                        if (!Double.isNaN(dDoubleValue)) {
                            String str21 = str2 + nk.h.f134211a.g(dDoubleValue, AbstractC2735o.a(i())) + ' ';
                            Paint paint6 = this.f95128A;
                            ScriptIndicConfig config9 = scriptDrawData.getConfig();
                            arrayList.add(new AbstractC2693a.b(str21, paint6, true, false, (config9 == null || (scriptRef3 = config9.getScriptRef()) == null) ? "" : scriptRef3, true, 8, null));
                        }
                        String color = scriptIndicAction.getOutput().getColor();
                        if (color == null || color.length() == 0) {
                            z10 = true;
                            int i12 = this.f95132E + 1;
                            this.f95132E = i12;
                            if (i12 >= 9) {
                                this.f95132E = 8;
                            }
                        }
                        scriptDrawData = scriptDrawData;
                        fT = f10;
                        i10 = i11;
                        listR1 = listR1;
                        z11 = z10;
                        iD = iD;
                        y1Var = y1Var2;
                        it2 = it;
                        mapZ = map;
                    }
                    z10 = true;
                    scriptDrawData = scriptDrawData;
                    fT = f10;
                    i10 = i11;
                    listR1 = listR1;
                    z11 = z10;
                    iD = iD;
                    y1Var = y1Var2;
                    it2 = it;
                    mapZ = map;
                }
            }
            boolean z12 = z11;
            List list = listR1;
            y1 y1Var3 = y1Var;
            int i13 = iD;
            Iterator it3 = it2;
            sp.aicoin_kline.core.indicator.config.F f11 = fT;
            this.f95134G.add(arrayList);
            fT = f11;
            listR1 = list;
            z11 = z12;
            iD = i13;
            y1Var = y1Var3;
            it2 = it3;
        }
        y(canvas, c2702dD, listR1.size(), new Q(this));
        canvas.restore();
    }

    @Override // Rj.AbstractC2693a, Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        super.u(aVar);
        if (aVar == null) {
            return;
        }
        E();
        C2741q c2741qB = i().b();
        c2741qB.e(b());
        this.f95129B = c2741qB.m(c());
        c2741qB.l(b());
        AbstractC2755v abstractC2755vQ = q();
        J0 j10 = abstractC2755vQ instanceof J0 ? (J0) abstractC2755vQ : null;
        if (j10 == null) {
            return;
        }
        this.f95130C = j10;
        Paint paint = new Paint(1);
        paint.setColor(aVar.d(".price_info.unit_value"));
        paint.setTextSize(Xj.a.d(9));
        paint.setAntiAlias(true);
        this.f95128A = paint;
        this.f95133F = aVar.d(".price_info.unit_value");
        Resources resources = i().c().getResources();
        this.f95135H = resources.getString(R.string.kline_titles_open);
        this.f95136I = resources.getString(R.string.kline_titles_high);
        this.f95137J = resources.getString(R.string.kline_titles_low);
        this.f95138K = resources.getString(R.string.kline_titles_close);
    }
}
