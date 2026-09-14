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
import gk.N0;
import java.util.ArrayList;
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

/* JADX INFO: renamed from: fk.t, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7394t extends AbstractC2693a {

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public final String f95502A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public Paint f95503B;

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public y1 f95504C;

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public N0 f95505D;

    /* JADX INFO: renamed from: E, reason: collision with root package name */
    public int f95506E;

    /* JADX INFO: renamed from: F, reason: collision with root package name */
    public List f95507F;

    /* JADX INFO: renamed from: G, reason: collision with root package name */
    public int f95508G;

    /* JADX INFO: renamed from: H, reason: collision with root package name */
    public int f95509H;

    /* JADX INFO: renamed from: I, reason: collision with root package name */
    public String f95510I;

    /* JADX INFO: renamed from: J, reason: collision with root package name */
    public String f95511J;

    /* JADX INFO: renamed from: K, reason: collision with root package name */
    public String f95512K;

    /* JADX INFO: renamed from: L, reason: collision with root package name */
    public String f95513L;

    /* JADX INFO: renamed from: M, reason: collision with root package name */
    public String f95514M;

    /* JADX INFO: renamed from: N, reason: collision with root package name */
    public double f95515N;

    /* JADX INFO: renamed from: O, reason: collision with root package name */
    public String f95516O;

    /* JADX INFO: renamed from: P, reason: collision with root package name */
    public final List f95517P;

    public C7394t(C2732n c2732n, String str, String str2) {
        super(c2732n, str);
        this.f95502A = str2;
        this.f95506E = KLineManager.f142490O.a().j();
        this.f95507F = new ArrayList();
        this.f95510I = "";
        this.f95511J = "";
        this.f95512K = "";
        this.f95513L = "";
        this.f95514M = "";
        this.f95516O = "";
        this.f95517P = Sf.r.t("publicScript-fundingRate", "publicScript-activeTradeVolume");
    }

    public final String H(double d10) {
        double d11;
        String strI;
        if (this.f95517P.contains(this.f95502A)) {
            strI = nk.l.f134222a.g(Double.valueOf(d10), this.f95502A);
            d11 = d10;
        } else {
            d11 = d10;
            strI = nk.h.i(nk.h.f134211a, d11, false, 0, AbstractC2735o.a(i()), 6, null);
        }
        return nk.h.f(nk.h.f134211a, d11, strI, 0, 4, null);
    }

    /* JADX WARN: Can't fix incorrect switch cases order, some code will duplicate */
    /* JADX WARN: Code duplicated, block: B:171:0x032f  */
    /* JADX WARN: Code duplicated, block: B:174:0x0339  */
    /* JADX WARN: Code duplicated, block: B:176:0x033f  */
    /* JADX WARN: Code duplicated, block: B:182:0x0354  */
    /* JADX WARN: Code duplicated, block: B:185:0x035a  */
    /* JADX WARN: Code duplicated, block: B:187:0x0360  */
    /* JADX WARN: Code duplicated, block: B:197:0x0382  */
    /* JADX WARN: Code duplicated, block: B:198:0x0385  */
    /* JADX WARN: Code duplicated, block: B:200:0x038b  */
    /* JADX WARN: Code duplicated, block: B:203:0x0395  */
    /* JADX WARN: Code duplicated, block: B:205:0x039b  */
    /* JADX WARN: Code duplicated, block: B:215:0x03bd  */
    /* JADX WARN: Code duplicated, block: B:217:0x03c3  */
    /* JADX WARN: Code duplicated, block: B:220:0x03cd  */
    /* JADX WARN: Code duplicated, block: B:221:0x03d3  */
    /* JADX WARN: Code duplicated, block: B:224:0x03dd  */
    /* JADX WARN: Code duplicated, block: B:226:0x03e3  */
    /* JADX WARN: Code duplicated, block: B:236:0x0405  */
    /* JADX WARN: Code duplicated, block: B:238:0x040b  */
    /* JADX WARN: Code duplicated, block: B:241:0x0415  */
    /* JADX WARN: Code duplicated, block: B:243:0x041d  */
    /* JADX WARN: Code duplicated, block: B:249:0x0432  */
    /* JADX WARN: Code duplicated, block: B:252:0x043e  */
    /* JADX WARN: Code duplicated, block: B:258:0x0453  */
    /* JADX WARN: Code duplicated, block: B:261:0x045f  */
    /* JADX WARN: Code duplicated, block: B:267:0x0474  */
    /* JADX WARN: Code duplicated, block: B:270:0x0480  */
    /* JADX WARN: Code duplicated, block: B:282:0x04e2  */
    /* JADX WARN: Code duplicated, block: B:284:0x04fa  */
    /* JADX WARN: Code duplicated, block: B:287:0x0504  */
    /* JADX WARN: Code duplicated, block: B:289:0x050a  */
    /* JADX WARN: Code duplicated, block: B:295:0x051f  */
    /* JADX WARN: Code duplicated, block: B:298:0x0525  */
    /* JADX WARN: Code duplicated, block: B:300:0x052b  */
    /* JADX WARN: Code duplicated, block: B:310:0x054d  */
    /* JADX WARN: Code duplicated, block: B:311:0x0550  */
    /* JADX WARN: Code duplicated, block: B:313:0x0556  */
    /* JADX WARN: Code duplicated, block: B:316:0x0560  */
    /* JADX WARN: Code duplicated, block: B:318:0x0568  */
    /* JADX WARN: Code duplicated, block: B:324:0x057d  */
    /* JADX WARN: Code duplicated, block: B:327:0x0589  */
    /* JADX WARN: Code duplicated, block: B:333:0x059e  */
    /* JADX WARN: Code duplicated, block: B:336:0x05aa  */
    /* JADX WARN: Code duplicated, block: B:342:0x05bf  */
    /* JADX WARN: Code duplicated, block: B:345:0x05cb  */
    /* JADX WARN: Code duplicated, block: B:357:0x062d  */
    /* JADX WARN: Code duplicated, block: B:359:0x0644  */
    /* JADX WARN: Code duplicated, block: B:361:0x064c  */
    /* JADX WARN: Code duplicated, block: B:362:0x0651  */
    /* JADX WARN: Code duplicated, block: B:364:0x0657  */
    /* JADX WARN: Code duplicated, block: B:374:0x0679  */
    /* JADX WARN: Code duplicated, block: B:378:0x0685  */
    /* JADX WARN: Code duplicated, block: B:380:0x068f  */
    /* JADX WARN: Code duplicated, block: B:382:0x069a  */
    /* JADX WARN: Code duplicated, block: B:389:0x06cb  */
    /* JADX WARN: Code duplicated, block: B:391:0x06e2  */
    /* JADX WARN: Code duplicated, block: B:394:0x06ea  */
    /* JADX WARN: Code duplicated, block: B:395:0x06ef  */
    /* JADX WARN: Code duplicated, block: B:401:0x06fd  */
    /* JADX WARN: Code duplicated, block: B:404:0x070d  */
    /* JADX WARN: Code duplicated, block: B:409:0x071c  */
    /* JADX WARN: Code duplicated, block: B:421:0x071e A[SYNTHETIC] */
    /* JADX WARN: Multi-variable type inference failed */
    /* JADX WARN: Type inference failed for: r14v8, types: [android.graphics.Paint] */
    /* JADX WARN: Type inference failed for: r1v0 */
    /* JADX WARN: Type inference failed for: r1v152 */
    /* JADX WARN: Type inference failed for: r1v3, types: [boolean, int] */
    /* JADX WARN: Type inference failed for: r21v1 */
    /* JADX WARN: Type inference failed for: r21v10 */
    /* JADX WARN: Type inference failed for: r21v11 */
    /* JADX WARN: Type inference failed for: r21v2 */
    /* JADX WARN: Type inference failed for: r21v3 */
    /* JADX WARN: Type inference failed for: r21v4 */
    /* JADX WARN: Type inference failed for: r21v5 */
    /* JADX WARN: Type inference failed for: r21v6 */
    /* JADX WARN: Type inference failed for: r21v7 */
    /* JADX WARN: Type inference failed for: r21v8 */
    /* JADX WARN: Type inference failed for: r21v9 */
    /* JADX WARN: Type inference failed for: r2v48 */
    /* JADX WARN: Type inference failed for: r36v0, types: [Rj.a, Rj.j0, Rj.r0, fk.t] */
    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        C2702d c2702dD;
        y1 y1Var;
        C2765z c2765zH;
        Rj.G gH;
        String title;
        ArrayList arrayList;
        Map<String, Map<String, String>> calculateHistoryData;
        List arrayList2;
        long jH;
        int length;
        ?? r21;
        ?? r22;
        ScriptDrawData scriptDrawData;
        y1 y1Var2;
        int i10;
        ArrayList arrayList3;
        String series;
        String str;
        String high;
        String str2;
        double dDoubleValue;
        String open;
        String str3;
        double dDoubleValue2;
        String low;
        String str4;
        double dDoubleValue3;
        String close;
        String str5;
        ScriptIndicConfig config;
        String str6;
        String scriptRef;
        Double dN;
        Double dN2;
        Double dN3;
        Double dN4;
        String series2;
        String str7;
        double dDoubleValue4;
        String refSeries;
        String str8;
        Double dN5;
        String high2;
        String str9;
        double dDoubleValue5;
        String open2;
        String str10;
        double dDoubleValue6;
        String low2;
        String str11;
        double dDoubleValue7;
        String close2;
        String str12;
        ScriptIndicConfig config2;
        String str13;
        String scriptRef2;
        Double dN6;
        Double dN7;
        Double dN8;
        Double dN9;
        String series3;
        String str14;
        String series4;
        String str15;
        char c10;
        ActionOutput output;
        String color;
        ?? r23;
        ek.m[] mVarArrU;
        boolean z10;
        String string;
        ScriptIndicConfig config3;
        String str16;
        String scriptRef3;
        String series5;
        String str17;
        double dDoubleValue8;
        String refSeries2;
        String str18;
        Double dN10;
        Ah.j.b bVarA;
        Paint paint;
        int iA;
        Integer numP;
        List<ScriptIndicAction> action;
        String scriptRef4;
        String title2;
        ?? r10 = 1;
        N0 n10 = this.f95505D;
        if (n10 == null || (c2702dD = j().d()) == null || (y1Var = this.f95504C) == null || (c2765zH = j().i().h(c())) == null || (gH = j().h()) == null) {
            return;
        }
        sp.aicoin_kline.core.indicator.config.F fX = n10.x();
        int iD = c2765zH.D() - 1;
        boolean zF = nk.n.f(13);
        this.f95508G = 0;
        int iIntValue = ((Number) p162hb.e.c(zF, Integer.valueOf(gH.t()), Integer.valueOf(y1Var.D()))).intValue();
        if (gH.B() || y1Var.E()) {
            iD = iIntValue;
        }
        long jH2 = y1Var.H(iD);
        canvas.save();
        ScriptDrawData scriptDrawData2 = (ScriptDrawData) n10.F().get(this.f95502A);
        if (scriptDrawData2 == null) {
            return;
        }
        ArrayList arrayList4 = new ArrayList();
        ScriptIndicConfig config4 = scriptDrawData2.getConfig();
        String errorMsg = config4 != null ? config4.getErrorMsg() : null;
        String string2 = "脚本暂不支持";
        if (errorMsg == null || errorMsg.length() == 0) {
            ScriptIndicConfig config5 = scriptDrawData2.getConfig();
            if (config5 != null && (title = config5.getTitle()) != null) {
                string2 = title;
            }
        } else {
            StringBuilder sb2 = new StringBuilder();
            ScriptIndicConfig config6 = scriptDrawData2.getConfig();
            if (config6 != null && (title2 = config6.getTitle()) != null) {
                string2 = title2;
            }
            sb2.append(string2);
            sb2.append(' ');
            ScriptIndicConfig config7 = scriptDrawData2.getConfig();
            sb2.append(config7 != null ? config7.getErrorMsg() : null);
            string2 = sb2.toString();
        }
        String str19 = string2 + ' ';
        Paint paint2 = this.f95503B;
        ScriptIndicConfig config8 = scriptDrawData2.getConfig();
        arrayList4.add(new AbstractC2693a.b(str19, paint2, true, true, (config8 == null || (scriptRef4 = config8.getScriptRef()) == null) ? "" : scriptRef4, false, 32, null));
        ScriptIndicConfig config9 = scriptDrawData2.getConfig();
        if ((config9 != null ? config9.getAction() : null) == null || (calculateHistoryData = scriptDrawData2.getCalculateHistoryData()) == null) {
            arrayList = arrayList4;
        } else if (calculateHistoryData.isEmpty()) {
            arrayList = arrayList4;
        } else {
            ScriptIndicConfig config10 = scriptDrawData2.getConfig();
            if (config10 == null || (action = config10.getAction()) == null || (arrayList2 = Sf.z.u1(action)) == null) {
                arrayList2 = new ArrayList();
            }
            this.f95507F = arrayList2;
            Paint paint3 = this.f95503B;
            if (paint3 != null) {
                paint3.setColor(this.f95509H);
                Qf.H h10 = Qf.H.f17640a;
            }
            int i11 = 0;
            for (Object obj : this.f95507F) {
                int i12 = i11 + 1;
                if (i11 < 0) {
                    Sf.r.x();
                }
                ScriptIndicAction scriptIndicAction = (ScriptIndicAction) obj;
                String title3 = scriptIndicAction.getTitle();
                this.f95514M = (title3 == null || title3.length() == 0) ? "k" + i11 + ": " : scriptIndicAction.getTitle() + ": ";
                int intOffset = scriptIndicAction.getIntOffset();
                if (intOffset == 0) {
                    jH = jH2;
                } else if (intOffset > 0) {
                    try {
                        jH = y1Var.H(iD - intOffset);
                    } catch (Exception unused) {
                        jH = jH2;
                    }
                } else {
                    jH = y1Var.H(Math.abs(intOffset) + iD);
                }
                Map<String, String> linkedHashMap = calculateHistoryData.get(String.valueOf(jH));
                if (linkedHashMap == null) {
                    linkedHashMap = new LinkedHashMap<>();
                }
                if (linkedHashMap.isEmpty()) {
                    r23 = r10;
                    scriptDrawData = scriptDrawData2;
                    y1Var2 = y1Var;
                    i10 = iD;
                    arrayList3 = arrayList4;
                    c10 = ' ';
                    z10 = false;
                } else {
                    StringBuilder sb3 = new StringBuilder();
                    ActionOutput output2 = scriptIndicAction.getOutput();
                    sb3.append(output2 != null ? output2.getColor() : null);
                    sb3.append("Value");
                    String string3 = sb3.toString();
                    ?? paint4 = new Paint((int) r10);
                    paint4.setTextSize(Xj.a.d(9));
                    paint4.setAntiAlias(r10);
                    this.f95503B = paint4;
                    ek.m[] mVarArrU2 = fX.u();
                    if (mVarArrU2.length == 0) {
                        length = -1;
                        r22 = r10;
                    } else {
                        length = this.f95508G;
                        if (length < 0) {
                            r22 = r10;
                            length = 0;
                        } else {
                            r21 = r10;
                            if (length >= mVarArrU2.length) {
                                r22 = r21;
                                length = mVarArrU2.length - 1;
                                r22 = r21;
                            }
                        }
                    }
                    r22 = r21;
                    Paint paint5 = this.f95503B;
                    if (paint5 != null) {
                        if (string3 == null || string3.length() == 0) {
                            scriptDrawData = scriptDrawData2;
                        } else {
                            scriptDrawData = scriptDrawData2;
                            if (!AbstractC7609s.f(string3, "nullValue")) {
                                String str20 = linkedHashMap.get(string3);
                                iA = (str20 == null || (numP = Ah.w.p(str20)) == null) ? length >= 0 ? mVarArrU2[length].a() : this.f95509H : numP.intValue();
                            }
                            paint5.setColor(iA);
                            Qf.H h11 = Qf.H.f17640a;
                        }
                        iA = length >= 0 ? mVarArrU2[length].a() : this.f95509H;
                        paint5.setColor(iA);
                        Qf.H h12 = Qf.H.f17640a;
                    } else {
                        scriptDrawData = scriptDrawData2;
                    }
                    StringBuilder sb4 = new StringBuilder();
                    ActionOutput output3 = scriptIndicAction.getOutput();
                    sb4.append(output3 != null ? output3.getColor() : null);
                    sb4.append("originValue");
                    String str21 = linkedHashMap.get(sb4.toString());
                    double dDoubleValue9 = 0.0d;
                    if (str21 == null || str21.length() == 0) {
                        y1Var2 = y1Var;
                        i10 = iD;
                    } else {
                        y1Var2 = y1Var;
                        i10 = iD;
                        Ah.j jVarC = Ah.l.c(new Ah.l("rgba\\((\\d+),(\\d+),(\\d+),((?:\\d+(?:\\.\\d*)?|\\.\\d+))\\)"), str21, 0, 2, null);
                        if (jVarC != null && (bVarA = jVarC.a()) != null) {
                            Double dN11 = Ah.v.n((String) kk.j.a(bVarA, 4));
                            arrayList3 = arrayList4;
                            if (((float) ((dN11 != null ? dN11.doubleValue() : 0.0d) * ((double) 255))) == 0.0f && (paint = this.f95503B) != null) {
                                paint.setColor(length >= 0 ? mVarArrU2[length].a() : this.f95509H);
                                Qf.H h13 = Qf.H.f17640a;
                            }
                        }
                        switch (scriptIndicAction.getAction()) {
                            case "plotHist":
                                series = scriptIndicAction.getSeries();
                                if (series == null) {
                                    series = "";
                                }
                                str = linkedHashMap.get(series);
                                this.f95516O = str;
                                if (str != null || str.length() == 0) {
                                    this.f95515N = Double.NaN;
                                } else {
                                    Double dN12 = Ah.v.n(this.f95516O);
                                    this.f95515N = dN12 != null ? dN12.doubleValue() : Double.NaN;
                                }
                                Qf.H h14 = Qf.H.f17640a;
                                break;
                            case "plotOhlc":
                                this.f95515N = Double.NaN;
                                high = scriptIndicAction.getHigh();
                                if (high == null) {
                                    high = "";
                                }
                                str2 = linkedHashMap.get(high);
                                if (str2 != null || (dN4 = Ah.v.n(str2)) == null) {
                                    dDoubleValue = 0.0d;
                                } else {
                                    dDoubleValue = dN4.doubleValue();
                                }
                                String strH = H(dDoubleValue);
                                open = scriptIndicAction.getOpen();
                                if (open == null) {
                                    open = "";
                                }
                                str3 = linkedHashMap.get(open);
                                if (str3 != null || (dN3 = Ah.v.n(str3)) == null) {
                                    dDoubleValue2 = 0.0d;
                                } else {
                                    dDoubleValue2 = dN3.doubleValue();
                                }
                                String strH2 = H(dDoubleValue2);
                                low = scriptIndicAction.getLow();
                                if (low == null) {
                                    low = "";
                                }
                                str4 = linkedHashMap.get(low);
                                if (str4 != null || (dN2 = Ah.v.n(str4)) == null) {
                                    dDoubleValue3 = 0.0d;
                                } else {
                                    dDoubleValue3 = dN2.doubleValue();
                                }
                                String strH3 = H(dDoubleValue3);
                                close = scriptIndicAction.getClose();
                                if (close == null) {
                                    close = "";
                                }
                                str5 = linkedHashMap.get(close);
                                if (str5 != null && (dN = Ah.v.n(str5)) != null) {
                                    dDoubleValue9 = dN.doubleValue();
                                }
                                String str22 = this.f95511J + strH + ' ' + this.f95510I + strH2 + ' ' + this.f95512K + strH3 + ' ' + this.f95513L + H(dDoubleValue9);
                                Paint paint6 = this.f95503B;
                                config = scriptDrawData.getConfig();
                                if (config != null || (scriptRef = config.getScriptRef()) == null) {
                                    str6 = "";
                                } else {
                                    str6 = scriptRef;
                                }
                                arrayList3.add(new AbstractC2693a.b(str22, paint6, true, false, str6, false, 40, null));
                                break;
                            case "plotText":
                                series2 = scriptIndicAction.getSeries();
                                if (series2 == null) {
                                    series2 = "";
                                }
                                str7 = linkedHashMap.get(series2);
                                if (str7 != null || (dN5 = Ah.v.n(str7)) == null) {
                                    dDoubleValue4 = 0.0d;
                                } else {
                                    dDoubleValue4 = dN5.doubleValue();
                                }
                                if (dDoubleValue4 > 0.0d) {
                                    refSeries = scriptIndicAction.getRefSeries();
                                    if (refSeries == null) {
                                        refSeries = "";
                                    }
                                    str8 = linkedHashMap.get(refSeries);
                                    this.f95516O = str8;
                                    if (str8 != null || str8.length() == 0) {
                                        this.f95515N = Double.NaN;
                                    } else {
                                        Double dN13 = Ah.v.n(this.f95516O);
                                        this.f95515N = dN13 != null ? dN13.doubleValue() : Double.NaN;
                                    }
                                } else {
                                    this.f95515N = Double.NaN;
                                }
                                Qf.H h15 = Qf.H.f17640a;
                                break;
                            case "plotCandle":
                                this.f95515N = Double.NaN;
                                high2 = scriptIndicAction.getHigh();
                                if (high2 == null) {
                                    high2 = "";
                                }
                                str9 = linkedHashMap.get(high2);
                                if (str9 != null || (dN9 = Ah.v.n(str9)) == null) {
                                    dDoubleValue5 = 0.0d;
                                } else {
                                    dDoubleValue5 = dN9.doubleValue();
                                }
                                String strH4 = H(dDoubleValue5);
                                open2 = scriptIndicAction.getOpen();
                                if (open2 == null) {
                                    open2 = "";
                                }
                                str10 = linkedHashMap.get(open2);
                                if (str10 != null || (dN8 = Ah.v.n(str10)) == null) {
                                    dDoubleValue6 = 0.0d;
                                } else {
                                    dDoubleValue6 = dN8.doubleValue();
                                }
                                String strH5 = H(dDoubleValue6);
                                low2 = scriptIndicAction.getLow();
                                if (low2 == null) {
                                    low2 = "";
                                }
                                str11 = linkedHashMap.get(low2);
                                if (str11 != null || (dN7 = Ah.v.n(str11)) == null) {
                                    dDoubleValue7 = 0.0d;
                                } else {
                                    dDoubleValue7 = dN7.doubleValue();
                                }
                                String strH6 = H(dDoubleValue7);
                                close2 = scriptIndicAction.getClose();
                                if (close2 == null) {
                                    close2 = "";
                                }
                                str12 = linkedHashMap.get(close2);
                                if (str12 != null && (dN6 = Ah.v.n(str12)) != null) {
                                    dDoubleValue9 = dN6.doubleValue();
                                }
                                String str23 = this.f95511J + strH4 + ' ' + this.f95510I + strH5 + ' ' + this.f95512K + strH6 + ' ' + this.f95513L + H(dDoubleValue9);
                                Paint paint7 = this.f95503B;
                                config2 = scriptDrawData.getConfig();
                                if (config2 != null || (scriptRef2 = config2.getScriptRef()) == null) {
                                    str13 = "";
                                } else {
                                    str13 = scriptRef2;
                                }
                                arrayList3.add(new AbstractC2693a.b(str23, paint7, true, false, str13, false, 40, null));
                                break;
                            case "plotColumn":
                                series3 = scriptIndicAction.getSeries();
                                if (series3 == null) {
                                    series3 = "";
                                }
                                str14 = linkedHashMap.get(series3);
                                this.f95516O = str14;
                                if (str14 != null || str14.length() == 0) {
                                    this.f95515N = Double.NaN;
                                } else {
                                    Double dN14 = Ah.v.n(this.f95516O);
                                    this.f95515N = dN14 != null ? dN14.doubleValue() : Double.NaN;
                                }
                                Qf.H h16 = Qf.H.f17640a;
                                break;
                            case "fill":
                                this.f95515N = Double.NaN;
                                Qf.H h17 = Qf.H.f17640a;
                                break;
                            case "plot":
                                series4 = scriptIndicAction.getSeries();
                                if (series4 == null) {
                                    series4 = "";
                                }
                                str15 = linkedHashMap.get(series4);
                                this.f95516O = str15;
                                if (str15 != null || str15.length() == 0) {
                                    this.f95515N = Double.NaN;
                                } else {
                                    Double dN15 = Ah.v.n(this.f95516O);
                                    this.f95515N = dN15 != null ? dN15.doubleValue() : Double.NaN;
                                }
                                Qf.H h18 = Qf.H.f17640a;
                                break;
                            case "plotShape":
                                series5 = scriptIndicAction.getSeries();
                                if (series5 == null) {
                                    series5 = "";
                                }
                                str17 = linkedHashMap.get(series5);
                                if (str17 != null || (dN10 = Ah.v.n(str17)) == null) {
                                    dDoubleValue8 = 0.0d;
                                } else {
                                    dDoubleValue8 = dN10.doubleValue();
                                }
                                if (dDoubleValue8 > 0.0d) {
                                    refSeries2 = scriptIndicAction.getRefSeries();
                                    if (refSeries2 == null) {
                                        refSeries2 = "";
                                    }
                                    str18 = linkedHashMap.get(refSeries2);
                                    this.f95516O = str18;
                                    if (str18 != null || str18.length() == 0) {
                                        this.f95515N = Double.NaN;
                                    } else {
                                        Double dN16 = Ah.v.n(this.f95516O);
                                        this.f95515N = dN16 != null ? dN16.doubleValue() : Double.NaN;
                                    }
                                } else {
                                    this.f95515N = Double.NaN;
                                }
                                Qf.H h19 = Qf.H.f17640a;
                                break;
                            default:
                                this.f95515N = Double.NaN;
                                Qf.H h20 = Qf.H.f17640a;
                                break;
                        }
                        if (Double.isNaN(this.f95515N)) {
                            c10 = ' ';
                        } else {
                            if (this.f95517P.contains(this.f95502A)) {
                                string = H(this.f95515N);
                                c10 = ' ';
                            } else {
                                StringBuilder sb5 = new StringBuilder();
                                sb5.append(this.f95514M);
                                sb5.append(H(this.f95515N));
                                c10 = ' ';
                                sb5.append(' ');
                                string = sb5.toString();
                            }
                            String str24 = string;
                            Paint paint8 = this.f95503B;
                            config3 = scriptDrawData.getConfig();
                            if (config3 != null || (scriptRef3 = config3.getScriptRef()) == null) {
                                str16 = "";
                            } else {
                                str16 = scriptRef3;
                            }
                            arrayList3.add(new AbstractC2693a.b(str24, paint8, true, false, str16, false, 40, null));
                        }
                        output = scriptIndicAction.getOutput();
                        if (output != null) {
                            color = output.getColor();
                        } else {
                            color = null;
                        }
                        if (color != null || color.length() == 0) {
                            r23 = 1;
                            r23 = 1;
                            this.f95508G++;
                            mVarArrU = fX.u();
                            if (mVarArrU.length != 0 && this.f95508G >= mVarArrU.length) {
                                this.f95508G = mVarArrU.length - 1;
                            }
                            z10 = false;
                            if (this.f95508G < 0) {
                                this.f95508G = 0;
                            }
                        } else {
                            z10 = false;
                            r23 = 1;
                        }
                    }
                    arrayList3 = arrayList4;
                    switch (scriptIndicAction.getAction()) {
                        case -2020374621:
                            if (!r1.equals("plotHist")) {
                                this.f95515N = Double.NaN;
                                Qf.H h21 = Qf.H.f17640a;
                            } else {
                                series = scriptIndicAction.getSeries();
                                if (series == null) {
                                    series = "";
                                }
                                str = linkedHashMap.get(series);
                                this.f95516O = str;
                                if (str != null) {
                                    this.f95515N = Double.NaN;
                                } else {
                                    this.f95515N = Double.NaN;
                                }
                                Qf.H h110 = Qf.H.f17640a;
                            }
                            break;
                        case -2020167279:
                            if (!r1.equals("plotOhlc")) {
                                this.f95515N = Double.NaN;
                                Qf.H h22 = Qf.H.f17640a;
                            } else {
                                this.f95515N = Double.NaN;
                                high = scriptIndicAction.getHigh();
                                if (high == null) {
                                    high = "";
                                }
                                str2 = linkedHashMap.get(high);
                                if (str2 != null) {
                                    dDoubleValue = 0.0d;
                                } else {
                                    dDoubleValue = 0.0d;
                                }
                                String strH7 = H(dDoubleValue);
                                open = scriptIndicAction.getOpen();
                                if (open == null) {
                                    open = "";
                                }
                                str3 = linkedHashMap.get(open);
                                if (str3 != null) {
                                    dDoubleValue2 = 0.0d;
                                } else {
                                    dDoubleValue2 = 0.0d;
                                }
                                String strH8 = H(dDoubleValue2);
                                low = scriptIndicAction.getLow();
                                if (low == null) {
                                    low = "";
                                }
                                str4 = linkedHashMap.get(low);
                                if (str4 != null) {
                                    dDoubleValue3 = 0.0d;
                                } else {
                                    dDoubleValue3 = 0.0d;
                                }
                                String strH9 = H(dDoubleValue3);
                                close = scriptIndicAction.getClose();
                                if (close == null) {
                                    close = "";
                                }
                                str5 = linkedHashMap.get(close);
                                if (str5 != null) {
                                    dDoubleValue9 = dN.doubleValue();
                                }
                                String str25 = this.f95511J + strH7 + ' ' + this.f95510I + strH8 + ' ' + this.f95512K + strH9 + ' ' + this.f95513L + H(dDoubleValue9);
                                Paint paint9 = this.f95503B;
                                config = scriptDrawData.getConfig();
                                if (config != null) {
                                    str6 = "";
                                } else {
                                    str6 = "";
                                }
                                arrayList3.add(new AbstractC2693a.b(str25, paint9, true, false, str6, false, 40, null));
                            }
                            break;
                        case -2020020818:
                            if (!r1.equals("plotText")) {
                                this.f95515N = Double.NaN;
                                Qf.H h23 = Qf.H.f17640a;
                            } else {
                                series2 = scriptIndicAction.getSeries();
                                if (series2 == null) {
                                    series2 = "";
                                }
                                str7 = linkedHashMap.get(series2);
                                if (str7 != null) {
                                    dDoubleValue4 = 0.0d;
                                } else {
                                    dDoubleValue4 = 0.0d;
                                }
                                if (dDoubleValue4 > 0.0d) {
                                    refSeries = scriptIndicAction.getRefSeries();
                                    if (refSeries == null) {
                                        refSeries = "";
                                    }
                                    str8 = linkedHashMap.get(refSeries);
                                    this.f95516O = str8;
                                    if (str8 != null) {
                                        this.f95515N = Double.NaN;
                                    } else {
                                        this.f95515N = Double.NaN;
                                    }
                                } else {
                                    this.f95515N = Double.NaN;
                                }
                                Qf.H h111 = Qf.H.f17640a;
                            }
                            break;
                        case -405487794:
                            if (!r1.equals("plotCandle")) {
                                this.f95515N = Double.NaN;
                                Qf.H h24 = Qf.H.f17640a;
                            } else {
                                this.f95515N = Double.NaN;
                                high2 = scriptIndicAction.getHigh();
                                if (high2 == null) {
                                    high2 = "";
                                }
                                str9 = linkedHashMap.get(high2);
                                if (str9 != null) {
                                    dDoubleValue5 = 0.0d;
                                } else {
                                    dDoubleValue5 = 0.0d;
                                }
                                String strH10 = H(dDoubleValue5);
                                open2 = scriptIndicAction.getOpen();
                                if (open2 == null) {
                                    open2 = "";
                                }
                                str10 = linkedHashMap.get(open2);
                                if (str10 != null) {
                                    dDoubleValue6 = 0.0d;
                                } else {
                                    dDoubleValue6 = 0.0d;
                                }
                                String strH11 = H(dDoubleValue6);
                                low2 = scriptIndicAction.getLow();
                                if (low2 == null) {
                                    low2 = "";
                                }
                                str11 = linkedHashMap.get(low2);
                                if (str11 != null) {
                                    dDoubleValue7 = 0.0d;
                                } else {
                                    dDoubleValue7 = 0.0d;
                                }
                                String strH12 = H(dDoubleValue7);
                                close2 = scriptIndicAction.getClose();
                                if (close2 == null) {
                                    close2 = "";
                                }
                                str12 = linkedHashMap.get(close2);
                                if (str12 != null) {
                                    dDoubleValue9 = dN6.doubleValue();
                                }
                                String str26 = this.f95511J + strH10 + ' ' + this.f95510I + strH11 + ' ' + this.f95512K + strH12 + ' ' + this.f95513L + H(dDoubleValue9);
                                Paint paint10 = this.f95503B;
                                config2 = scriptDrawData.getConfig();
                                if (config2 != null) {
                                    str13 = "";
                                } else {
                                    str13 = "";
                                }
                                arrayList3.add(new AbstractC2693a.b(str26, paint10, true, false, str13, false, 40, null));
                            }
                            break;
                        case -392601705:
                            if (!r1.equals("plotColumn")) {
                                this.f95515N = Double.NaN;
                                Qf.H h25 = Qf.H.f17640a;
                            } else {
                                series3 = scriptIndicAction.getSeries();
                                if (series3 == null) {
                                    series3 = "";
                                }
                                str14 = linkedHashMap.get(series3);
                                this.f95516O = str14;
                                if (str14 != null) {
                                    this.f95515N = Double.NaN;
                                } else {
                                    this.f95515N = Double.NaN;
                                }
                                Qf.H h112 = Qf.H.f17640a;
                            }
                            break;
                        case 3143043:
                            if (!r1.equals("fill")) {
                                this.f95515N = Double.NaN;
                                Qf.H h26 = Qf.H.f17640a;
                            } else {
                                this.f95515N = Double.NaN;
                                Qf.H h113 = Qf.H.f17640a;
                            }
                            break;
                        case 3443937:
                            if (!r1.equals("plot")) {
                                this.f95515N = Double.NaN;
                                Qf.H h27 = Qf.H.f17640a;
                            } else {
                                series4 = scriptIndicAction.getSeries();
                                if (series4 == null) {
                                    series4 = "";
                                }
                                str15 = linkedHashMap.get(series4);
                                this.f95516O = str15;
                                if (str15 != null) {
                                    this.f95515N = Double.NaN;
                                } else {
                                    this.f95515N = Double.NaN;
                                }
                                Qf.H h114 = Qf.H.f17640a;
                            }
                            break;
                        case 1803007808:
                            if (!r1.equals("plotShape")) {
                                this.f95515N = Double.NaN;
                                Qf.H h28 = Qf.H.f17640a;
                            } else {
                                series5 = scriptIndicAction.getSeries();
                                if (series5 == null) {
                                    series5 = "";
                                }
                                str17 = linkedHashMap.get(series5);
                                if (str17 != null) {
                                    dDoubleValue8 = 0.0d;
                                } else {
                                    dDoubleValue8 = 0.0d;
                                }
                                if (dDoubleValue8 > 0.0d) {
                                    refSeries2 = scriptIndicAction.getRefSeries();
                                    if (refSeries2 == null) {
                                        refSeries2 = "";
                                    }
                                    str18 = linkedHashMap.get(refSeries2);
                                    this.f95516O = str18;
                                    if (str18 != null) {
                                        this.f95515N = Double.NaN;
                                    } else {
                                        this.f95515N = Double.NaN;
                                    }
                                } else {
                                    this.f95515N = Double.NaN;
                                }
                                Qf.H h115 = Qf.H.f17640a;
                            }
                            break;
                        default:
                            this.f95515N = Double.NaN;
                            Qf.H h29 = Qf.H.f17640a;
                            break;
                    }
                    if (Double.isNaN(this.f95515N)) {
                        if (this.f95517P.contains(this.f95502A)) {
                            string = H(this.f95515N);
                            c10 = ' ';
                        } else {
                            StringBuilder sb6 = new StringBuilder();
                            sb6.append(this.f95514M);
                            sb6.append(H(this.f95515N));
                            c10 = ' ';
                            sb6.append(' ');
                            string = sb6.toString();
                        }
                        String str27 = string;
                        Paint paint11 = this.f95503B;
                        config3 = scriptDrawData.getConfig();
                        if (config3 != null) {
                            str16 = "";
                        } else {
                            str16 = "";
                        }
                        arrayList3.add(new AbstractC2693a.b(str27, paint11, true, false, str16, false, 40, null));
                    } else {
                        c10 = ' ';
                    }
                    output = scriptIndicAction.getOutput();
                    if (output != null) {
                        color = output.getColor();
                    } else {
                        color = null;
                    }
                    if (color != null) {
                        r23 = 1;
                        r23 = 1;
                        this.f95508G++;
                        mVarArrU = fX.u();
                        if (mVarArrU.length != 0) {
                            this.f95508G = mVarArrU.length - 1;
                        }
                        z10 = false;
                        if (this.f95508G < 0) {
                            this.f95508G = 0;
                        }
                    } else {
                        r23 = 1;
                        r23 = 1;
                        this.f95508G++;
                        mVarArrU = fX.u();
                        if (mVarArrU.length != 0) {
                            this.f95508G = mVarArrU.length - 1;
                        }
                        z10 = false;
                        if (this.f95508G < 0) {
                            this.f95508G = 0;
                        }
                    }
                }
                arrayList4 = arrayList3;
                i11 = i12;
                iD = i10;
                r10 = r23;
                scriptDrawData2 = scriptDrawData;
                y1Var = y1Var2;
            }
            arrayList = arrayList4;
        }
        z(canvas, c2702dD, arrayList);
        canvas.restore();
    }

    @Override // Rj.AbstractC2693a, Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        super.t();
        if (aVar == null) {
            return;
        }
        C2741q c2741qB = i().b();
        c2741qB.e(b());
        this.f95504C = c2741qB.m(c());
        c2741qB.l(b());
        AbstractC2755v abstractC2755vQ = q();
        N0 n10 = abstractC2755vQ instanceof N0 ? (N0) abstractC2755vQ : null;
        if (n10 == null) {
            return;
        }
        this.f95505D = n10;
        Paint paint = new Paint(1);
        paint.setColor(aVar.d(".price_info.unit_value"));
        paint.setTextSize(Xj.a.d(9));
        paint.setAntiAlias(true);
        this.f95503B = paint;
        this.f95509H = aVar.d(".price_info.unit_value");
        Resources resources = i().c().getResources();
        this.f95510I = resources.getString(R.string.kline_titles_open);
        this.f95511J = resources.getString(R.string.kline_titles_high);
        this.f95512K = resources.getString(R.string.kline_titles_low);
        this.f95513L = resources.getString(R.string.kline_titles_close);
    }
}
