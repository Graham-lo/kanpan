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
import gk.K0;
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
public final class T extends AbstractC2693a {

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public Paint f95139A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public y1 f95140B;

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public K0 f95141C;

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public int f95142D;

    /* JADX INFO: renamed from: E, reason: collision with root package name */
    public List f95143E;

    /* JADX INFO: renamed from: F, reason: collision with root package name */
    public int f95144F;

    /* JADX INFO: renamed from: G, reason: collision with root package name */
    public int f95145G;

    /* JADX INFO: renamed from: H, reason: collision with root package name */
    public final String f95146H;

    /* JADX INFO: renamed from: I, reason: collision with root package name */
    public String f95147I;

    /* JADX INFO: renamed from: J, reason: collision with root package name */
    public String f95148J;

    /* JADX INFO: renamed from: K, reason: collision with root package name */
    public String f95149K;

    /* JADX INFO: renamed from: L, reason: collision with root package name */
    public String f95150L;

    public T(C2732n c2732n, String str, String str2, boolean z10) {
        super(c2732n, str);
        this.f95142D = KLineManager.f142490O.a().j();
        this.f95143E = new ArrayList();
        this.f95146H = str2;
        this.f95147I = "";
        this.f95148J = "";
        this.f95149K = "";
        this.f95150L = "";
    }

    /* JADX WARN: Can't fix incorrect switch cases order, some code will duplicate */
    /* JADX WARN: Code duplicated, block: B:188:0x037f A[PHI: r27
      0x037f: PHI (r27v1 double) = 
      (r27v0 double)
      (r27v0 double)
      (r27v0 double)
      (r27v0 double)
      (r27v0 double)
      (r27v0 double)
      (r27v5 double)
      (r27v0 double)
      (r27v0 double)
      (r27v0 double)
      (r27v0 double)
      (r27v0 double)
      (r27v6 double)
      (r27v0 double)
      (r27v0 double)
      (r27v0 double)
      (r27v0 double)
      (r27v0 double)
      (r27v7 double)
     binds: [B:161:0x0332, B:220:0x03e7, B:206:0x03bd, B:212:0x03cd, B:214:0x03d3, B:217:0x03da, B:218:0x03dc, B:204:0x03b1, B:191:0x038d, B:197:0x039d, B:199:0x03a3, B:202:0x03aa, B:203:0x03ac, B:164:0x033c, B:176:0x035d, B:181:0x036c, B:183:0x0372, B:186:0x0379, B:187:0x037b] A[DONT_GENERATE, DONT_INLINE]] */
    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        C2702d c2702dD;
        y1 y1Var;
        C2765z c2765zH;
        Rj.G gH;
        Object next;
        String title;
        Map mapZ;
        List arrayList;
        y1 y1Var2;
        ScriptDrawData scriptDrawData;
        sp.aicoin_kline.core.indicator.config.F f10;
        long j10;
        Double dN;
        String id2;
        Double dN2;
        Double dN3;
        Double dN4;
        Double dN5;
        Double dN6;
        Double dN7;
        boolean z10;
        String id3;
        String id4;
        Double dN8;
        Double dN9;
        Double dN10;
        Double dN11;
        Double dN12;
        Double dN13;
        Double dN14;
        Double dN15;
        Ah.j.b bVarA;
        Paint paint;
        String str;
        Integer numP;
        Integer numP2;
        List<ScriptIndicAction> action;
        String id5;
        String title2;
        String str2;
        String id6;
        K0 k10 = this.f95141C;
        if (k10 == null || (c2702dD = j().d()) == null || (y1Var = this.f95140B) == null || (c2765zH = j().i().h(c())) == null || (gH = j().h()) == null) {
            return;
        }
        sp.aicoin_kline.core.indicator.config.F fX = k10.x();
        int iD = c2765zH.D() - 1;
        boolean zF = nk.n.f(13);
        this.f95144F = 0;
        int iIntValue = ((Number) p162hb.e.c(zF, Integer.valueOf(gH.t()), Integer.valueOf(y1Var.D()))).intValue();
        if (gH.B() || y1Var.E()) {
            iD = iIntValue;
        }
        long jH = y1Var.H(iD);
        canvas.save();
        Iterator it = Sf.z.r1(k10.F()).iterator();
        do {
            if (!it.hasNext()) {
                next = null;
                break;
            }
            next = it.next();
            str2 = this.f95146H;
            ScriptIndicConfig config = ((ScriptDrawData) next).getConfig();
            if (config == null || (id6 = config.getId()) == null) {
                id6 = "";
            }
        } while (!Ah.y.T(str2, id6, false, 2, null));
        ScriptDrawData scriptDrawData2 = (ScriptDrawData) next;
        if (scriptDrawData2 == null) {
            return;
        }
        ArrayList arrayList2 = new ArrayList();
        ScriptIndicConfig config2 = scriptDrawData2.getConfig();
        String errorMsg = config2 != null ? config2.getErrorMsg() : null;
        String string = "脚本暂不支持";
        if (errorMsg == null || errorMsg.length() == 0) {
            ScriptIndicConfig config3 = scriptDrawData2.getConfig();
            if (config3 != null && (title = config3.getTitle()) != null) {
                string = title;
            }
        } else {
            StringBuilder sb2 = new StringBuilder();
            ScriptIndicConfig config4 = scriptDrawData2.getConfig();
            if (config4 != null && (title2 = config4.getTitle()) != null) {
                string = title2;
            }
            sb2.append(string);
            sb2.append(' ');
            ScriptIndicConfig config5 = scriptDrawData2.getConfig();
            sb2.append(config5 != null ? config5.getErrorMsg() : null);
            string = sb2.toString();
        }
        String str3 = string + ' ';
        Paint paint2 = this.f95139A;
        ScriptIndicConfig config6 = scriptDrawData2.getConfig();
        arrayList2.add(new AbstractC2693a.b(str3, paint2, true, true, (config6 == null || (id5 = config6.getId()) == null) ? "" : id5, true));
        ScriptIndicConfig config7 = scriptDrawData2.getConfig();
        if ((config7 != null ? config7.getAction() : null) != null && (mapZ = Sf.N.z(scriptDrawData2.getCalculateHistoryData())) != null && !mapZ.isEmpty()) {
            ScriptIndicConfig config8 = scriptDrawData2.getConfig();
            if (config8 == null || (action = config8.getAction()) == null || (arrayList = Sf.z.u1(action)) == null) {
                arrayList = new ArrayList();
            }
            this.f95143E = arrayList;
            Paint paint3 = this.f95139A;
            if (paint3 != null) {
                paint3.setColor(this.f95145G);
                Qf.H h10 = Qf.H.f17640a;
            }
            Iterator it2 = this.f95143E.iterator();
            int i10 = 0;
            while (it2.hasNext()) {
                Object next2 = it2.next();
                int i11 = i10 + 1;
                if (i10 < 0) {
                    Sf.r.x();
                }
                ScriptIndicAction scriptIndicAction = (ScriptIndicAction) next2;
                String title3 = scriptIndicAction.getTitle();
                String str4 = (title3 == null || title3.length() == 0) ? "k" + i10 + ": " : scriptIndicAction.getTitle() + ": ";
                String offset = scriptIndicAction.getOffset();
                int iIntValue2 = (offset == null || (numP2 = Ah.w.p(offset)) == null) ? 0 : numP2.intValue();
                Map linkedHashMap = (Map) mapZ.get(String.valueOf(iIntValue2 != 0 ? iIntValue2 > 0 ? y1Var.H(iD - iIntValue2) : y1Var.H(iD + iIntValue2) : jH));
                if (linkedHashMap == null) {
                    linkedHashMap = new LinkedHashMap();
                }
                if (linkedHashMap.isEmpty()) {
                    y1Var2 = y1Var;
                    scriptDrawData = scriptDrawData2;
                    f10 = fX;
                    it2 = it2;
                    j10 = jH;
                } else {
                    String strA = kk.f.a(scriptIndicAction, new StringBuilder(), "Value");
                    y1Var2 = y1Var;
                    Paint paint4 = new Paint(1);
                    paint4.setTextSize(Xj.a.d(9));
                    paint4.setAntiAlias(true);
                    this.f95139A = paint4;
                    int iA = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str = (String) linkedHashMap.get(strA)) == null || (numP = Ah.w.p(str)) == null) ? fX.u()[this.f95144F].a() : numP.intValue();
                    paint4.setColor(iA);
                    Qf.H h11 = Qf.H.f17640a;
                    StringBuilder sb3 = new StringBuilder();
                    ActionOutput output = scriptIndicAction.getOutput();
                    sb3.append(output != null ? output.getColor() : null);
                    sb3.append("originValue");
                    String str5 = (String) linkedHashMap.get(sb3.toString());
                    double dDoubleValue = 0.0d;
                    if (str5 == null || str5.length() == 0) {
                        scriptDrawData = scriptDrawData2;
                        f10 = fX;
                    } else {
                        scriptDrawData = scriptDrawData2;
                        f10 = fX;
                        Ah.j jVarC = Ah.l.c(new Ah.l("rgba\\((\\d+),(\\d+),(\\d+),((?:\\d+(?:\\.\\d*)?|\\.\\d+))\\)"), str5, 0, 2, null);
                        if (jVarC != null && (bVarA = jVarC.a()) != null) {
                            Double dN16 = Ah.v.n((String) kk.j.a(bVarA, 4));
                            if (((float) (((double) 255) * (dN16 != null ? dN16.doubleValue() : 0.0d))) == 0.0f && (paint = this.f95139A) != null) {
                                paint.setColor(f10.u()[this.f95144F].a());
                            }
                        }
                    }
                    String action2 = scriptIndicAction.getAction();
                    double dDoubleValue2 = Double.NaN;
                    switch (action2.hashCode()) {
                        case -2020374621:
                            it2 = it2;
                            scriptIndicAction = scriptIndicAction;
                            j10 = jH;
                            if (action2.equals("plotHist")) {
                                Object series = scriptIndicAction.getSeries();
                                if (series == null) {
                                    series = "";
                                }
                                String str6 = (String) linkedHashMap.get(series);
                                if (str6 != null && str6.length() != 0 && (dN = Ah.v.n(str6)) != null) {
                                    dDoubleValue2 = dN.doubleValue();
                                }
                            }
                            break;
                        case -2020167279:
                            it2 = it2;
                            scriptIndicAction = scriptIndicAction;
                            j10 = jH;
                            if (action2.equals("plotOhlc")) {
                                nk.h hVar = nk.h.f134211a;
                                Object high = scriptIndicAction.getHigh();
                                if (high == null) {
                                    high = "";
                                }
                                String str7 = (String) linkedHashMap.get(high);
                                String strG = hVar.g((str7 == null || (dN5 = Ah.v.n(str7)) == null) ? 0.0d : dN5.doubleValue(), AbstractC2735o.a(i()));
                                Object open = scriptIndicAction.getOpen();
                                if (open == null) {
                                    open = "";
                                }
                                String str8 = (String) linkedHashMap.get(open);
                                String strG2 = hVar.g((str8 == null || (dN4 = Ah.v.n(str8)) == null) ? 0.0d : dN4.doubleValue(), AbstractC2735o.a(i()));
                                Object low = scriptIndicAction.getLow();
                                if (low == null) {
                                    low = "";
                                }
                                String str9 = (String) linkedHashMap.get(low);
                                String strG3 = hVar.g((str9 == null || (dN3 = Ah.v.n(str9)) == null) ? 0.0d : dN3.doubleValue(), AbstractC2735o.a(i()));
                                Object close = scriptIndicAction.getClose();
                                if (close == null) {
                                    close = "";
                                }
                                String str10 = (String) linkedHashMap.get(close);
                                if (str10 != null && (dN2 = Ah.v.n(str10)) != null) {
                                    dDoubleValue = dN2.doubleValue();
                                }
                                String str11 = this.f95148J + strG + ' ' + this.f95147I + strG2 + ' ' + this.f95149K + strG3 + ' ' + this.f95150L + hVar.g(dDoubleValue, AbstractC2735o.a(i()));
                                Paint paint5 = this.f95139A;
                                ScriptIndicConfig config9 = scriptDrawData.getConfig();
                                arrayList2.add(new AbstractC2693a.b(str11, paint5, true, false, (config9 == null || (id2 = config9.getId()) == null) ? "" : id2, true, 8, null));
                            }
                            break;
                        case -2020020818:
                            it2 = it2;
                            scriptIndicAction = scriptIndicAction;
                            j10 = jH;
                            if (action2.equals("plotText")) {
                                Object series2 = scriptIndicAction.getSeries();
                                if (series2 == null) {
                                    series2 = "";
                                }
                                String str12 = (String) linkedHashMap.get(series2);
                                if (((str12 == null || (dN7 = Ah.v.n(str12)) == null) ? 0.0d : dN7.doubleValue()) > 0.0d) {
                                    Object refSeries = scriptIndicAction.getRefSeries();
                                    if (refSeries == null) {
                                        refSeries = "";
                                    }
                                    String str13 = (String) linkedHashMap.get(refSeries);
                                    if (str13 != null && str13.length() != 0 && (dN6 = Ah.v.n(str13)) != null) {
                                        dDoubleValue2 = dN6.doubleValue();
                                    }
                                }
                            }
                            break;
                        case -405487794:
                            if (!action2.equals("plotCandle")) {
                                it2 = it2;
                                scriptIndicAction = scriptIndicAction;
                                j10 = jH;
                            } else {
                                nk.h hVar2 = nk.h.f134211a;
                                Object high2 = scriptIndicAction.getHigh();
                                if (high2 == null) {
                                    high2 = "";
                                }
                                String str14 = (String) linkedHashMap.get(high2);
                                String strG4 = hVar2.g((str14 == null || (dN11 = Ah.v.n(str14)) == null) ? 0.0d : dN11.doubleValue(), AbstractC2735o.a(i()));
                                Object open2 = scriptIndicAction.getOpen();
                                if (open2 == null) {
                                    open2 = "";
                                }
                                String str15 = (String) linkedHashMap.get(open2);
                                String strG5 = hVar2.g((str15 == null || (dN10 = Ah.v.n(str15)) == null) ? 0.0d : dN10.doubleValue(), AbstractC2735o.a(i()));
                                Object low2 = scriptIndicAction.getLow();
                                if (low2 == null) {
                                    low2 = "";
                                }
                                String str16 = (String) linkedHashMap.get(low2);
                                j10 = jH;
                                String strG6 = hVar2.g((str16 == null || (dN9 = Ah.v.n(str16)) == null) ? 0.0d : dN9.doubleValue(), AbstractC2735o.a(i()));
                                Object close2 = scriptIndicAction.getClose();
                                if (close2 == null) {
                                    close2 = "";
                                }
                                String str17 = (String) linkedHashMap.get(close2);
                                if (str17 != null && (dN8 = Ah.v.n(str17)) != null) {
                                    dDoubleValue = dN8.doubleValue();
                                }
                                String str18 = this.f95148J + strG4 + ' ' + this.f95147I + strG5 + ' ' + this.f95149K + strG6 + ' ' + this.f95150L + hVar2.g(dDoubleValue, AbstractC2735o.a(i()));
                                Paint paint6 = this.f95139A;
                                ScriptIndicConfig config10 = scriptDrawData.getConfig();
                                arrayList2.add(new AbstractC2693a.b(str18, paint6, true, false, (config10 == null || (id4 = config10.getId()) == null) ? "" : id4, true, 8, null));
                            }
                            break;
                        case -392601705:
                            if (action2.equals("plotColumn")) {
                                Object series3 = scriptIndicAction.getSeries();
                                if (series3 == null) {
                                    series3 = "";
                                }
                                String str19 = (String) linkedHashMap.get(series3);
                                if (str19 != null && str19.length() != 0 && (dN12 = Ah.v.n(str19)) != null) {
                                    dDoubleValue2 = dN12.doubleValue();
                                }
                            }
                            it2 = it2;
                            scriptIndicAction = scriptIndicAction;
                            j10 = jH;
                            break;
                        case 3143043:
                            action2.equals("fill");
                            it2 = it2;
                            scriptIndicAction = scriptIndicAction;
                            j10 = jH;
                            break;
                        case 3443937:
                            if (action2.equals("plot")) {
                                Object series4 = scriptIndicAction.getSeries();
                                if (series4 == null) {
                                    series4 = "";
                                }
                                String str20 = (String) linkedHashMap.get(series4);
                                if (str20 != null && str20.length() != 0 && (dN13 = Ah.v.n(str20)) != null) {
                                    dDoubleValue2 = dN13.doubleValue();
                                }
                            }
                            it2 = it2;
                            scriptIndicAction = scriptIndicAction;
                            j10 = jH;
                            break;
                        case 1803007808:
                            if (action2.equals("plotShape")) {
                                Object series5 = scriptIndicAction.getSeries();
                                if (series5 == null) {
                                    series5 = "";
                                }
                                String str21 = (String) linkedHashMap.get(series5);
                                if (((str21 == null || (dN15 = Ah.v.n(str21)) == null) ? 0.0d : dN15.doubleValue()) > 0.0d) {
                                    Object refSeries2 = scriptIndicAction.getRefSeries();
                                    if (refSeries2 == null) {
                                        refSeries2 = "";
                                    }
                                    String str22 = (String) linkedHashMap.get(refSeries2);
                                    if (str22 != null && str22.length() != 0 && (dN14 = Ah.v.n(str22)) != null) {
                                        dDoubleValue2 = dN14.doubleValue();
                                    }
                                }
                            }
                            it2 = it2;
                            scriptIndicAction = scriptIndicAction;
                            j10 = jH;
                            break;
                        default:
                            it2 = it2;
                            scriptIndicAction = scriptIndicAction;
                            j10 = jH;
                            break;
                    }
                    double d10 = dDoubleValue2;
                    if (!Double.isNaN(d10)) {
                        String str23 = str4 + nk.h.f134211a.g(d10, AbstractC2735o.a(i())) + ' ';
                        Paint paint7 = this.f95139A;
                        ScriptIndicConfig config11 = scriptDrawData.getConfig();
                        arrayList2.add(new AbstractC2693a.b(str23, paint7, true, false, (config11 == null || (id3 = config11.getId()) == null) ? "" : id3, true, 8, null));
                    }
                    String color = scriptIndicAction.getOutput().getColor();
                    if (color == null || color.length() == 0) {
                        z10 = true;
                        int i12 = this.f95144F + 1;
                        this.f95144F = i12;
                        if (i12 >= 9) {
                            this.f95144F = 8;
                        }
                    }
                    it2 = it2;
                    scriptDrawData2 = scriptDrawData;
                    i10 = i11;
                    fX = f10;
                    iD = iD;
                    y1Var = y1Var2;
                    jH = j10;
                }
                z10 = true;
                it2 = it2;
                scriptDrawData2 = scriptDrawData;
                i10 = i11;
                fX = f10;
                iD = iD;
                y1Var = y1Var2;
                jH = j10;
            }
        }
        z(canvas, c2702dD, arrayList2);
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
        this.f95140B = c2741qB.m(c());
        c2741qB.l(b());
        AbstractC2755v abstractC2755vQ = q();
        K0 k10 = abstractC2755vQ instanceof K0 ? (K0) abstractC2755vQ : null;
        if (k10 == null) {
            return;
        }
        this.f95141C = k10;
        Paint paint = new Paint(1);
        paint.setColor(aVar.d(".price_info.unit_value"));
        paint.setTextSize(Xj.a.d(9));
        paint.setAntiAlias(true);
        this.f95139A = paint;
        this.f95145G = aVar.d(".price_info.unit_value");
        Resources resources = i().c().getResources();
        this.f95147I = resources.getString(R.string.kline_titles_open);
        this.f95148J = resources.getString(R.string.kline_titles_high);
        this.f95149K = resources.getString(R.string.kline_titles_low);
        this.f95150L = resources.getString(R.string.kline_titles_close);
    }
}
