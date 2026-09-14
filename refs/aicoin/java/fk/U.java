package fk;

import Rj.AbstractC2744r0;
import Rj.AbstractC2755v;
import Rj.AbstractC2759w0;
import Rj.C2702d;
import Rj.C2732n;
import Rj.C2741q;
import Rj.C2765z;
import Rj.y1;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.DashPathEffect;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PointF;
import android.graphics.Rect;
import com.tencent.android.tpush.XGPushManager;
import gk.J0;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.chart.data.ActionOutput;
import sp.aicoin_kline.chart.data.ScriptDrawData;
import sp.aicoin_kline.chart.data.ScriptIndicAction;
import sp.aicoin_kline.chart.data.ScriptIndicConfig;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class U extends AbstractC2744r0 {

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public int f95151A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public Paint f95152B;

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public final Path f95153C;

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public final Path f95154D;

    /* JADX INFO: renamed from: E, reason: collision with root package name */
    public float f95155E;

    /* JADX INFO: renamed from: F, reason: collision with root package name */
    public float f95156F;

    /* JADX INFO: renamed from: G, reason: collision with root package name */
    public float f95157G;

    /* JADX INFO: renamed from: H, reason: collision with root package name */
    public float f95158H;

    /* JADX INFO: renamed from: I, reason: collision with root package name */
    public float f95159I;

    /* JADX INFO: renamed from: J, reason: collision with root package name */
    public int f95160J;

    /* JADX INFO: renamed from: K, reason: collision with root package name */
    public int f95161K;

    /* JADX INFO: renamed from: L, reason: collision with root package name */
    public int f95162L;

    /* JADX INFO: renamed from: M, reason: collision with root package name */
    public float f95163M;

    /* JADX INFO: renamed from: N, reason: collision with root package name */
    public float f95164N;

    /* JADX INFO: renamed from: O, reason: collision with root package name */
    public float f95165O;

    /* JADX INFO: renamed from: P, reason: collision with root package name */
    public float f95166P;

    /* JADX INFO: renamed from: Q, reason: collision with root package name */
    public double f95167Q;

    /* JADX INFO: renamed from: R, reason: collision with root package name */
    public double f95168R;

    /* JADX INFO: renamed from: S, reason: collision with root package name */
    public double f95169S;

    /* JADX INFO: renamed from: T, reason: collision with root package name */
    public double f95170T;

    /* JADX INFO: renamed from: U, reason: collision with root package name */
    public final Paint f95171U;

    /* JADX INFO: renamed from: V, reason: collision with root package name */
    public final Paint f95172V;

    /* JADX INFO: renamed from: W, reason: collision with root package name */
    public final Paint f95173W;

    /* JADX INFO: renamed from: X, reason: collision with root package name */
    public final Paint f95174X;

    /* JADX INFO: renamed from: Y, reason: collision with root package name */
    public final Paint f95175Y;

    /* JADX INFO: renamed from: Z, reason: collision with root package name */
    public final Paint f95176Z;

    /* JADX INFO: renamed from: a0, reason: collision with root package name */
    public final Path f95177a0;

    /* JADX INFO: renamed from: b0, reason: collision with root package name */
    public final Path f95178b0;

    /* JADX INFO: renamed from: c0, reason: collision with root package name */
    public final Paint f95179c0;

    /* JADX INFO: renamed from: d0, reason: collision with root package name */
    public final PointF f95180d0;

    /* JADX INFO: renamed from: e0, reason: collision with root package name */
    public final PointF f95181e0;

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public C2741q f95182l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public C2702d f95183m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public y1 f95184n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public AbstractC2759w0 f95185o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public J0 f95186p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public Path f95187q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public Paint f95188r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public Path f95189s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public Paint f95190t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public Paint f95191u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public final Rect f95192v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public Paint f95193w;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public Path f95194x;

    /* JADX INFO: renamed from: y, reason: collision with root package name */
    public Paint f95195y;

    /* JADX INFO: renamed from: z, reason: collision with root package name */
    public Paint f95196z;

    public static final class a {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public final float f95197a;

        /* JADX INFO: renamed from: b, reason: collision with root package name */
        public final float f95198b;

        /* JADX INFO: renamed from: c, reason: collision with root package name */
        public final float f95199c;

        /* JADX INFO: renamed from: d, reason: collision with root package name */
        public final float f95200d;

        /* JADX INFO: renamed from: e, reason: collision with root package name */
        public final float f95201e;

        /* JADX INFO: renamed from: f, reason: collision with root package name */
        public final float f95202f;

        /* JADX INFO: renamed from: g, reason: collision with root package name */
        public final boolean f95203g;

        /* JADX INFO: renamed from: h, reason: collision with root package name */
        public final int f95204h;

        public a(float f10, float f11, float f12, float f13, float f14, float f15, boolean z10, int i10) {
            this.f95197a = f10;
            this.f95198b = f11;
            this.f95199c = f12;
            this.f95200d = f13;
            this.f95201e = f14;
            this.f95202f = f15;
            this.f95203g = z10;
            this.f95204h = i10;
        }

        public final float a() {
            return this.f95197a;
        }

        public final float b() {
            return this.f95198b;
        }

        public final float c() {
            return this.f95199c;
        }

        public final float d() {
            return this.f95200d;
        }

        public final float e() {
            return this.f95201e;
        }

        public boolean equals(Object obj) {
            if (this == obj) {
                return true;
            }
            if (!(obj instanceof a)) {
                return false;
            }
            a aVar = (a) obj;
            return Float.compare(this.f95197a, aVar.f95197a) == 0 && Float.compare(this.f95198b, aVar.f95198b) == 0 && Float.compare(this.f95199c, aVar.f95199c) == 0 && Float.compare(this.f95200d, aVar.f95200d) == 0 && Float.compare(this.f95201e, aVar.f95201e) == 0 && Float.compare(this.f95202f, aVar.f95202f) == 0 && this.f95203g == aVar.f95203g && this.f95204h == aVar.f95204h;
        }

        public final float f() {
            return this.f95202f;
        }

        public final boolean g() {
            return this.f95203g;
        }

        public final int h() {
            return this.f95204h;
        }

        public int hashCode() {
            return Integer.hashCode(this.f95204h) + ((Boolean.hashCode(this.f95203g) + kk.a.a(this.f95202f, kk.a.a(this.f95201e, kk.a.a(this.f95200d, kk.a.a(this.f95199c, kk.a.a(this.f95198b, Float.hashCode(this.f95197a) * 31, 31), 31), 31), 31), 31)) * 31);
        }

        public String toString() {
            return "FillSegment(startX=" + this.f95197a + ", startY1=" + this.f95198b + ", startY2=" + this.f95199c + ", endX=" + this.f95200d + ", endY1=" + this.f95201e + ", endY2=" + this.f95202f + ", isFirstLineOnTop=" + this.f95203g + ", color=" + this.f95204h + ')';
        }
    }

    public U(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f95192v = new Rect();
        this.f95193w = new Paint();
        this.f95196z = new Paint();
        this.f95151A = XGPushManager.MAX_TAG_SIZE;
        this.f95152B = new Paint();
        new Paint();
        this.f95153C = new Path();
        this.f95154D = new Path();
        this.f95155E = 15.0f;
        this.f95156F = 16.0f;
        this.f95157G = 15.0f;
        this.f95158H = 8.0f;
        this.f95159I = 8.0f;
        this.f95161K = -16711936;
        this.f95162L = -65536;
        this.f95171U = new Paint();
        this.f95172V = new Paint();
        this.f95173W = new Paint();
        this.f95174X = new Paint();
        this.f95175Y = new Paint();
        this.f95176Z = new Paint();
        this.f95177a0 = new Path();
        this.f95178b0 = new Path();
        this.f95179c0 = new Paint();
        this.f95180d0 = new PointF();
        this.f95181e0 = new PointF();
    }

    public final void A(Canvas canvas, ScriptIndicAction scriptIndicAction, Map map, float f10, float f11, int i10, sp.aicoin_kline.core.indicator.config.F f12) {
        String str;
        Integer numP;
        String text = scriptIndicAction.getOutput().getText();
        if (text == null) {
            text = "";
        }
        if (text.length() == 0 || this.f95191u == null) {
            return;
        }
        String bgColor = scriptIndicAction.getOutput().getBgColor();
        if (bgColor != null && bgColor.length() != 0) {
            String str2 = scriptIndicAction.getOutput().getBgColor() + "BGValue";
            Paint paint = this.f95191u;
            if (paint != null) {
                int iA = (str2 == null || str2.length() == 0 || (str = (String) map.get(str2)) == null || (numP = Ah.w.p(str)) == null) ? f12.u()[this.f95160J].a() : numP.intValue();
                paint.setColor(iA);
            }
            this.f95191u.getTextBounds(text, 0, text.length(), this.f95192v);
            float fWidth = this.f95192v.width() / 2;
            canvas.drawRoundRect((f10 - Xj.a.a(4.0f)) - fWidth, f11 - (this.f95192v.height() + 10), (Xj.a.a(6.0f) + (f10 + this.f95192v.width())) - fWidth, (this.f95192v.height() / 3) + f11 + 4.0f, 6.0f, 6.0f, this.f95191u);
        }
        int iWidth = this.f95192v.width() / 2;
        Paint paint2 = this.f95191u;
        if (paint2 != null) {
            paint2.setColor(i10);
        }
        canvas.drawText(text, f10 - iWidth, f11, this.f95191u);
    }

    /* JADX WARN: Code duplicated, block: B:45:0x00a5  */
    public final void B(Canvas canvas, float f10, float f11, float f12, ScriptIndicAction scriptIndicAction, AbstractC2759w0 abstractC2759w0, int i10, int i11, Map map) {
        int iAbs;
        long jH;
        float f13;
        float f14;
        String str;
        Integer numP;
        String str2;
        Integer numP2;
        String str3;
        Integer numP3;
        Double dN;
        Double dN2;
        Double dN3;
        Double dN4;
        Long lR;
        int i12;
        float f15 = (f11 / 6) - f12;
        float f16 = f15 + f10;
        float f17 = 2;
        int intOffset = scriptIndicAction.getIntOffset();
        if (intOffset < 0) {
            iAbs = Math.abs(intOffset) + i11;
            float f18 = intOffset * f11;
            f15 += f18;
            f16 += f18;
        } else {
            iAbs = i11;
        }
        int i13 = intOffset > 0 ? i10 - intOffset : i10;
        int intShowLast = scriptIndicAction.getIntShowLast();
        int i14 = (1 > intShowLast || intShowLast >= (i12 = this.f95151A)) ? -1 : i12 - intShowLast;
        try {
            y1 y1Var = this.f95184n;
            jH = y1Var != null ? y1Var.H(i14) : 0L;
        } catch (Exception unused) {
        }
        while (i13 < iAbs) {
            y1 y1Var2 = this.f95184n;
            Map map2 = (Map) map.get(String.valueOf(y1Var2 != null ? Long.valueOf(y1Var2.H(i13)) : null));
            if (map2 == null) {
                f13 = f17;
            } else {
                String str4 = (String) map2.get("time");
                long jLongValue = (str4 == null || (lR = Ah.w.r(str4)) == null) ? 0L : lR.longValue();
                String open = scriptIndicAction.getOpen();
                if (open == null) {
                    open = "0";
                }
                String str5 = (String) map2.get(open);
                double dDoubleValue = 0.0d;
                double dDoubleValue2 = (str5 == null || (dN4 = Ah.v.n(str5)) == null) ? 0.0d : dN4.doubleValue();
                this.f95168R = dDoubleValue2;
                if (dDoubleValue2 == 0.0d) {
                    f14 = f16;
                    f13 = f17;
                } else {
                    KLineManager.a aVar = KLineManager.f142490O;
                    this.f95164N = kk.k.a(aVar, dDoubleValue2, abstractC2759w0);
                    String high = scriptIndicAction.getHigh();
                    if (high == null) {
                        high = "0";
                    }
                    String str6 = (String) map2.get(high);
                    double dDoubleValue3 = (str6 == null || (dN3 = Ah.v.n(str6)) == null) ? 0.0d : dN3.doubleValue();
                    this.f95167Q = dDoubleValue3;
                    this.f95163M = kk.k.a(aVar, dDoubleValue3, abstractC2759w0);
                    String low = scriptIndicAction.getLow();
                    if (low == null) {
                        low = "0";
                    }
                    String str7 = (String) map2.get(low);
                    double dDoubleValue4 = (str7 == null || (dN2 = Ah.v.n(str7)) == null) ? 0.0d : dN2.doubleValue();
                    this.f95169S = dDoubleValue4;
                    this.f95165O = kk.k.a(aVar, dDoubleValue4, abstractC2759w0);
                    String close = scriptIndicAction.getClose();
                    if (close == null) {
                        close = "0";
                    }
                    String str8 = (String) map2.get(close);
                    if (str8 != null && (dN = Ah.v.n(str8)) != null) {
                        dDoubleValue = dN.doubleValue();
                    }
                    double d10 = dDoubleValue;
                    this.f95170T = d10;
                    this.f95166P = kk.k.a(aVar, d10, abstractC2759w0);
                    String strA = kk.f.a(scriptIndicAction, new StringBuilder(), "Value");
                    float fAbs = (Math.abs(f16 - f15) / f17) + f15;
                    if (i14 <= 0 || jLongValue >= jH) {
                        float f19 = f16;
                        f13 = f17;
                        double d11 = this.f95170T;
                        double d12 = this.f95168R;
                        if (d11 > d12) {
                            this.f95173W.setStrokeWidth(3.0f);
                            Paint paint = this.f95173W;
                            int iIntValue = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str3 = (String) map2.get(strA)) == null || (numP3 = Ah.w.p(str3)) == null) ? this.f95161K : numP3.intValue();
                            paint.setColor(iIntValue);
                            canvas.drawLine(fAbs, this.f95163M, fAbs, this.f95165O, this.f95173W);
                            float f20 = this.f95164N;
                            canvas.drawLine(f15, f20, fAbs, f20, this.f95173W);
                            float f21 = this.f95166P;
                            f14 = f19;
                            canvas.drawLine(fAbs, f21, f14, f21, this.f95173W);
                        } else if (d11 == d12) {
                            this.f95176Z.setStrokeWidth(2.0f);
                            Paint paint2 = this.f95176Z;
                            int iIntValue2 = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str2 = (String) map2.get(strA)) == null || (numP2 = Ah.w.p(str2)) == null) ? this.f95161K : numP2.intValue();
                            paint2.setColor(iIntValue2);
                            canvas.drawLine(fAbs, this.f95163M, fAbs, this.f95165O, this.f95176Z);
                            float f22 = this.f95164N;
                            canvas.drawLine(f15, f22, fAbs, f22, this.f95176Z);
                            float f23 = this.f95166P;
                            f14 = f19;
                            canvas.drawLine(fAbs, f23, f14, f23, this.f95176Z);
                        } else {
                            this.f95175Y.setStrokeWidth(3.0f);
                            Paint paint3 = this.f95175Y;
                            int iIntValue3 = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str = (String) map2.get(strA)) == null || (numP = Ah.w.p(str)) == null) ? this.f95162L : numP.intValue();
                            paint3.setColor(iIntValue3);
                            canvas.drawLine(fAbs, this.f95163M, fAbs, this.f95165O, this.f95175Y);
                            float f24 = this.f95164N;
                            canvas.drawLine(f15, f24, fAbs, f24, this.f95175Y);
                            float f25 = this.f95166P;
                            f14 = f19;
                            canvas.drawLine(fAbs, f25, f14, f25, this.f95175Y);
                        }
                    } else {
                        f14 = f16;
                        f13 = f17;
                    }
                }
                f15 += f11;
                f16 = f14 + f11;
            }
            i13++;
            f17 = f13;
        }
    }

    public final void C(Canvas canvas, float f10, float f11, ScriptIndicAction scriptIndicAction, AbstractC2759w0 abstractC2759w0, int i10, int i11, sp.aicoin_kline.core.indicator.config.F f12, Map map) {
        float f13;
        int iAbs;
        String str;
        String str2;
        int i12;
        long jH;
        boolean z10;
        Paint paint;
        Path path;
        int i13;
        boolean z11;
        int i14;
        int iA;
        float f14;
        Path path2;
        String str3;
        Integer numP;
        Long lR;
        int i15;
        Path path3 = this.f95187q;
        if (path3 != null) {
            path3.reset();
        }
        Path path4 = this.f95189s;
        if (path4 != null) {
            path4.reset();
        }
        int intOffset = scriptIndicAction.getIntOffset();
        float fFloatValue = ((Number) p162hb.e.c(o(), Float.valueOf(abstractC2759w0.P(abstractC2759w0.v())), Float.valueOf(abstractC2759w0.P(abstractC2759w0.u())))).floatValue();
        if (intOffset < 0) {
            iAbs = Math.abs(intOffset) + i11;
            f13 = (intOffset * f11) + f10;
        } else {
            f13 = f10;
            iAbs = i11;
        }
        int i16 = intOffset > 0 ? i10 - intOffset : i10;
        String strA = kk.f.a(scriptIndicAction, new StringBuilder(), "Value");
        if (scriptIndicAction.getOutput().getLineWidth() != null) {
            Paint paint2 = this.f95188r;
            if (paint2 != null) {
                paint2.setStrokeWidth(scriptIndicAction.getOutput().getFloatLineWidth());
            }
            Paint paint3 = this.f95190t;
            if (paint3 != null) {
                paint3.setStrokeWidth(scriptIndicAction.getOutput().getFloatLineWidth());
            }
        }
        if (scriptIndicAction.getOutput().getLineDash() == null || (str = (String) Sf.z.q0(scriptIndicAction.getOutput().getLineDash())) == null) {
            str = "0";
        }
        if (scriptIndicAction.getOutput().getLineDash() == null || (str2 = (String) Sf.z.D0(scriptIndicAction.getOutput().getLineDash())) == null) {
            str2 = "0";
        }
        Float fO = Ah.v.o(str);
        float f15 = 0.0f;
        float fFloatValue2 = fO != null ? fO.floatValue() : 0.0f;
        Float fO2 = Ah.v.o(str2);
        float fFloatValue3 = fO2 != null ? fO2.floatValue() : 0.0f;
        Paint paint4 = this.f95188r;
        if (paint4 != null) {
            i12 = 1;
            paint4.setPathEffect(new DashPathEffect(new float[]{fFloatValue2, fFloatValue3}, 0.0f));
        } else {
            i12 = 1;
        }
        Paint paint5 = this.f95190t;
        if (paint5 != null) {
            float[] fArr = new float[2];
            fArr[0] = fFloatValue2;
            fArr[i12] = fFloatValue3;
            paint5.setPathEffect(new DashPathEffect(fArr, 0.0f));
        }
        int intShowLast = scriptIndicAction.getIntShowLast();
        int i17 = (i12 > intShowLast || intShowLast >= (i15 = this.f95151A)) ? -1 : i15 - intShowLast;
        int i18 = -16777216;
        try {
            y1 y1Var = this.f95184n;
            if (y1Var != null) {
                jH = y1Var.H(i17);
                z10 = true;
            } else {
                jH = 0;
                z10 = true;
            }
        } catch (Exception unused) {
        }
        while (i16 < iAbs) {
            y1 y1Var2 = this.f95184n;
            Map map2 = (Map) map.get(String.valueOf(y1Var2 != null ? Long.valueOf(y1Var2.H(i16)) : null));
            if (map2 == null) {
                i13 = i17;
                z11 = z10;
                i14 = i16;
                iA = i18;
                strA = strA;
            } else {
                i13 = i17;
                String str4 = (String) map2.get("time");
                long jLongValue = (str4 == null || (lR = Ah.w.r(str4)) == null) ? 0L : lR.longValue();
                String series = scriptIndicAction.getSeries();
                if (series == null) {
                    series = "0";
                }
                String str5 = (String) map2.get(series);
                if (str5 == null) {
                    str5 = "0.0";
                }
                Double dN = Ah.v.n(str5);
                double dDoubleValue = dN != null ? dN.doubleValue() : 0.0d;
                z11 = dDoubleValue == 0.0d ? true : z10;
                if (dDoubleValue == 0.0d) {
                    iA = i18;
                    i14 = i16;
                } else {
                    i14 = i16;
                    float fA = kk.k.a(KLineManager.f142490O, dDoubleValue, abstractC2759w0);
                    iA = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str3 = (String) map2.get(strA)) == null || (numP = Ah.w.p(str3)) == null) ? f12.u()[this.f95160J].a() : numP.intValue();
                    if (i13 <= 0 || jLongValue >= jH) {
                        if (z11) {
                            Paint paint6 = this.f95188r;
                            if (paint6 != null) {
                                paint6.setColor(iA);
                            }
                            Path path5 = this.f95187q;
                            if (path5 != null) {
                                path5.moveTo(f13, fA);
                            }
                            if (f15 + f11 != f13 && (path2 = this.f95187q) != null) {
                                path2.lineTo(f13, Xj.a.b(1) + fA);
                            }
                            f15 = fA;
                            strA = strA;
                            f15 = f13;
                            z11 = false;
                        } else {
                            if (iA != i18) {
                                Paint paint7 = this.f95190t;
                                if (paint7 != null) {
                                    paint7.setColor(iA);
                                }
                                Path path6 = this.f95189s;
                                if (path6 != null && this.f95190t != null) {
                                    path6.moveTo(f15, f15);
                                    Path path7 = this.f95189s;
                                    if (path7 != null) {
                                        path7.lineTo(f13, fA);
                                    }
                                }
                                iA = i18;
                            } else {
                                Paint paint8 = this.f95188r;
                                if (paint8 != null) {
                                    paint8.setColor(iA);
                                }
                                Path path8 = this.f95187q;
                                if (path8 != null) {
                                    float f16 = f15;
                                    f14 = fA;
                                    hk.a.f98027a.d(f16, f15, f13, f14, fFloatValue, path8);
                                }
                                f15 = f14;
                                f15 = f13;
                            }
                            f14 = fA;
                            f15 = f14;
                            f15 = f13;
                        }
                    }
                    f13 += f11;
                }
                strA = strA;
                f13 += f11;
            }
            i16 = i14 + 1;
            strA = strA;
            i18 = iA;
            i17 = i13;
            z10 = z11;
        }
        Paint paint9 = this.f95188r;
        if (paint9 != null && (path = this.f95187q) != null) {
            canvas.drawPath(path, paint9);
        }
        Path path9 = this.f95189s;
        if (path9 == null || (paint = this.f95190t) == null) {
            return;
        }
        canvas.drawPath(path9, paint);
    }

    public final void D(Canvas canvas, ScriptIndicAction scriptIndicAction, AbstractC2759w0 abstractC2759w0, sp.aicoin_kline.core.indicator.config.F f10, Map map) {
        Map linkedHashMap;
        Double dN;
        Long lR;
        String str;
        Integer numP;
        y1 y1Var = this.f95184n;
        long j10 = 0;
        long jM = y1Var != null ? y1Var.m() : 0L;
        new LinkedHashMap();
        if (jM > 0) {
            linkedHashMap = (Map) map.get(String.valueOf(jM / ((long) 1000)));
            if (linkedHashMap == null) {
                linkedHashMap = new LinkedHashMap();
            }
        } else {
            Map.Entry entry = (Map.Entry) Sf.z.p0(map.entrySet());
            if (entry == null || (linkedHashMap = (Map) entry.getValue()) == null) {
                linkedHashMap = new LinkedHashMap();
            }
        }
        Map map2 = linkedHashMap;
        String strA = kk.f.a(scriptIndicAction, new StringBuilder(), "Value");
        int iA = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str = (String) map2.get(strA)) == null || (numP = Ah.w.p(str)) == null) ? f10.u()[this.f95160J].a() : numP.intValue();
        int i10 = iA;
        String fontSize = scriptIndicAction.getOutput().getFontSize();
        if (fontSize != null && fontSize.length() != 0) {
            float floatFontSize = scriptIndicAction.getOutput().getFloatFontSize();
            Paint paint = this.f95191u;
            if (paint != null) {
                paint.setTextSize(Xj.a.c(floatFontSize));
            }
        }
        C2702d c2702d = this.f95183m;
        int i11 = 0;
        int iU = c2702d != null ? c2702d.u() : 0;
        y1 y1Var2 = this.f95184n;
        float fW = iU + (y1Var2 != null ? y1Var2.w() : 0.0f);
        String str2 = (String) kk.g.a(scriptIndicAction, new StringBuilder(), "AllLabels", map2);
        if (str2 == null || str2.length() == 0) {
            String str3 = (String) kk.g.a(scriptIndicAction, new StringBuilder(), "AfterTransTime1", map2);
            long jLongValue = (str3 == null || (lR = Ah.w.r(str3)) == null) ? 0L : lR.longValue();
            String str4 = (String) kk.g.a(scriptIndicAction, new StringBuilder(), "AfterTransValue1", map2);
            double dDoubleValue = (str4 == null || (dN = Ah.v.n(str4)) == null) ? 0.0d : dN.doubleValue();
            if (jLongValue <= 0 || dDoubleValue == 0.0d) {
                return;
            }
            y1 y1Var3 = this.f95184n;
            A(canvas, scriptIndicAction, map2, (y1Var3 != null ? y1Var3.j(jLongValue * ((long) 1000)) : 0.0f) - fW, kk.k.a(KLineManager.f142490O, dDoubleValue, abstractC2759w0), i10, f10);
            return;
        }
        Iterator it = Ah.y.M0(str2, new String[]{"|"}, false, 0, 6, null).iterator();
        while (it.hasNext()) {
            List listM0 = Ah.y.M0((String) it.next(), new String[]{","}, false, 0, 6, null);
            if (listM0.size() >= 2) {
                Long lR2 = Ah.w.r((String) listM0.get(i11));
                long jLongValue2 = lR2 != null ? lR2.longValue() : j10;
                Double dN2 = Ah.v.n((String) listM0.get(1));
                double dDoubleValue2 = dN2 != null ? dN2.doubleValue() : 0.0d;
                if (jLongValue2 <= j10 || dDoubleValue2 == 0.0d) {
                    j10 = j10;
                } else {
                    y1 y1Var4 = this.f95184n;
                    A(canvas, scriptIndicAction, map2, (y1Var4 != null ? y1Var4.j(jLongValue2 * ((long) 1000)) : 0.0f) - fW, kk.k.a(KLineManager.f142490O, dDoubleValue2, abstractC2759w0), i10, f10);
                    j10 = j10;
                    i11 = 0;
                }
            }
        }
    }

    /* JADX WARN: Code duplicated, block: B:59:0x00ec  */
    public final void E(Canvas canvas, float f10, float f11, ScriptIndicAction scriptIndicAction, AbstractC2759w0 abstractC2759w0, int i10, int i11, sp.aicoin_kline.core.indicator.config.F f12, Map map) {
        boolean z10;
        int i12;
        int i13;
        String str;
        Integer numP;
        float f13;
        float f14;
        String str2;
        Integer numP2;
        float f15;
        Canvas canvas2;
        int i14;
        String str3;
        Integer numP3;
        String str4;
        Integer numP4;
        Double dN;
        Double dN2;
        Double dN3;
        int intOffset = scriptIndicAction.getIntOffset();
        ScriptIndicAction scriptIndicAction2 = scriptIndicAction;
        String strA = kk.f.a(scriptIndicAction2, new StringBuilder(), "Value");
        int intShowLast = scriptIndicAction2.getIntShowLast();
        ArrayList arrayList = new ArrayList();
        double d10 = 0.0d;
        if (intOffset != 0) {
            List listB = Sf.P.B(map);
            int i15 = 0;
            for (Object obj : listB) {
                int i16 = i15 + 1;
                if (i15 < 0) {
                    Sf.r.x();
                }
                int i17 = (intOffset * (-1)) + i15;
                Map map2 = (Map) ((Qf.p) obj).d();
                String series = scriptIndicAction2.getSeries();
                String str5 = (String) map2.get(series == null ? "0" : series);
                boolean z11 = ((str5 == null || (dN3 = Ah.v.n(str5)) == null) ? 0.0d : dN3.doubleValue()) > 0.0d;
                if (i17 >= 0 && i17 < listB.size() && z11) {
                    arrayList.add(listB.get(i17));
                }
                i15 = i16;
            }
        }
        Map mapZ = intOffset != 0 ? Sf.N.z(Sf.N.v(arrayList)) : map;
        int i18 = (intShowLast <= 0 || intShowLast >= mapZ.size()) ? 0 : (this.f95151A - intShowLast) + intOffset;
        while (i10 < i11) {
            y1 y1Var = this.f95184n;
            Map linkedHashMap = (Map) mapZ.get(String.valueOf(y1Var != null ? Long.valueOf(y1Var.H(i10)) : null));
            if (linkedHashMap == null) {
                linkedHashMap = new LinkedHashMap();
            }
            if (intOffset == 0) {
                Object series2 = scriptIndicAction2.getSeries();
                if (series2 == null) {
                    series2 = "0";
                }
                String str6 = (String) linkedHashMap.get(series2);
                if (((str6 == null || (dN2 = Ah.v.n(str6)) == null) ? d10 : dN2.doubleValue()) > d10) {
                    z10 = true;
                } else {
                    z10 = false;
                }
            } else {
                z10 = true;
            }
            Object refSeries = scriptIndicAction2.getRefSeries();
            if (refSeries == null) {
                refSeries = "";
            }
            String str7 = (String) linkedHashMap.get(refSeries);
            double dDoubleValue = (str7 == null || (dN = Ah.v.n(str7)) == null) ? d10 : dN.doubleValue();
            if (dDoubleValue != d10 && z10 && i10 >= i18) {
                float fA = kk.k.a(KLineManager.f142490O, dDoubleValue, abstractC2759w0);
                int iA = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str4 = (String) linkedHashMap.get(strA)) == null || (numP4 = Ah.w.p(str4)) == null) ? f12.u()[this.f95160J].a() : numP4.intValue();
                String fontSize = scriptIndicAction2.getOutput().getFontSize();
                if (fontSize != null && fontSize.length() != 0) {
                    float floatFontSize = scriptIndicAction2.getOutput().getFloatFontSize();
                    Paint paint = this.f95191u;
                    if (paint != null) {
                        paint.setTextSize(Xj.a.c(floatFontSize));
                    }
                }
                if (!AbstractC7609s.f(scriptIndicAction2.getOutput().getPlacement(), "bottom")) {
                    i12 = i10;
                    i13 = i18;
                    intOffset = intOffset;
                    int i19 = iA;
                    if (AbstractC7609s.f(scriptIndicAction.getOutput().getPlacement(), "center")) {
                        if (this.f95191u != null) {
                            float fA2 = f10 - Xj.a.a(10.0f);
                            String bgColor = scriptIndicAction.getOutput().getBgColor();
                            if (bgColor == null || bgColor.length() == 0) {
                                f13 = fA2;
                                f14 = 2.0f;
                            } else {
                                String str8 = scriptIndicAction.getOutput().getBgColor() + "BGValue";
                                Paint paint2 = this.f95191u;
                                if (paint2 != null) {
                                    int iA2 = (str8 == null || str8.length() == 0 || (str2 = (String) linkedHashMap.get(str8)) == null || (numP2 = Ah.w.p(str2)) == null) ? f12.u()[this.f95160J].a() : numP2.intValue();
                                    paint2.setColor(iA2);
                                }
                                this.f95191u.getTextBounds(scriptIndicAction.getOutput().getText(), 0, scriptIndicAction.getOutput().getText().length(), this.f95192v);
                                f13 = fA2;
                                f14 = 2.0f;
                                canvas.drawRoundRect(fA2 - Xj.a.a(3.0f), fA - this.f95192v.height(), Xj.a.a(3.0f) + this.f95192v.width() + fA2, (this.f95192v.height() / 2) + fA + Xj.a.a(1.0f), Xj.a.a(3.0f), Xj.a.a(3.0f), this.f95191u);
                            }
                            Paint paint3 = this.f95191u;
                            if (paint3 != null) {
                                paint3.setColor(i19);
                            }
                            canvas.drawText(scriptIndicAction.getOutput().getText(), f13, Xj.a.a(f14) + fA, this.f95191u);
                        }
                    } else if (this.f95191u != null) {
                        float fA3 = f10 - Xj.a.a(10.0f);
                        float f16 = fA - 10.0f;
                        String bgColor2 = scriptIndicAction.getOutput().getBgColor();
                        if (bgColor2 != null && bgColor2.length() != 0) {
                            String str9 = scriptIndicAction.getOutput().getBgColor() + "BGValue";
                            Paint paint4 = this.f95191u;
                            if (paint4 != null) {
                                int iA3 = (str9 == null || str9.length() == 0 || (str = (String) linkedHashMap.get(str9)) == null || (numP = Ah.w.p(str)) == null) ? f12.u()[this.f95160J].a() : numP.intValue();
                                paint4.setColor(iA3);
                            }
                            this.f95191u.getTextBounds(scriptIndicAction.getOutput().getText(), 0, scriptIndicAction.getOutput().getText().length(), this.f95192v);
                            canvas.drawRoundRect(fA3 - Xj.a.a(3.0f), (f16 - this.f95192v.height()) - Xj.a.a(2.0f), this.f95192v.width() + fA3 + Xj.a.a(3.0f), (this.f95192v.height() / 2) + f16, Xj.a.a(3.0f), Xj.a.a(3.0f), this.f95191u);
                        }
                        Paint paint5 = this.f95191u;
                        if (paint5 != null) {
                            paint5.setColor(i19);
                        }
                        canvas.drawText(scriptIndicAction.getOutput().getText(), fA3, f16, this.f95191u);
                    }
                } else if (this.f95191u != null) {
                    float fA4 = f10 - Xj.a.a(10.0f);
                    float f17 = fA + 50.0f;
                    String bgColor3 = scriptIndicAction2.getOutput().getBgColor();
                    if (bgColor3 == null || bgColor3.length() == 0) {
                        i12 = i10;
                        i13 = i18;
                        f15 = fA4;
                        canvas2 = canvas;
                        i14 = iA;
                    } else {
                        StringBuilder sb2 = new StringBuilder();
                        int i20 = i10;
                        sb2.append(scriptIndicAction2.getOutput().getBgColor());
                        sb2.append("BGValue");
                        String string = sb2.toString();
                        Paint paint6 = this.f95191u;
                        if (paint6 != null) {
                            int iA4 = (string == null || string.length() == 0 || (str3 = (String) linkedHashMap.get(string)) == null || (numP3 = Ah.w.p(str3)) == null) ? f12.u()[this.f95160J].a() : numP3.intValue();
                            paint6.setColor(iA4);
                        }
                        this.f95191u.getTextBounds(scriptIndicAction2.getOutput().getText(), 0, scriptIndicAction2.getOutput().getText().length(), this.f95192v);
                        i12 = i20;
                        i14 = iA;
                        f15 = fA4;
                        canvas2 = canvas;
                        i13 = i18;
                        canvas2.drawRoundRect(fA4 - Xj.a.a(3.0f), f17 - (this.f95192v.height() + 6), Xj.a.a(3.0f) + this.f95192v.width() + fA4, (this.f95192v.height() / 3) + f17, Xj.a.a(3.0f), Xj.a.a(3.0f), this.f95191u);
                    }
                    Paint paint7 = this.f95191u;
                    if (paint7 != null) {
                        paint7.setColor(i14);
                    }
                    canvas2.drawText(scriptIndicAction.getOutput().getText(), f15, f17, this.f95191u);
                } else {
                    i12 = i10;
                    i13 = i18;
                    intOffset = intOffset;
                }
            } else {
                i12 = i10;
                i13 = i18;
                intOffset = intOffset;
            }
            f10 += f11;
            scriptIndicAction2 = scriptIndicAction;
            i11 = i11;
            i10 = i12 + 1;
            i18 = i13;
            intOffset = intOffset;
            d10 = 0.0d;
        }
    }

    public final void F(Canvas canvas, ScriptIndicAction scriptIndicAction, AbstractC2759w0 abstractC2759w0, sp.aicoin_kline.core.indicator.config.F f10, Map map) {
        String str;
        long j10;
        Map linkedHashMap;
        Double dN;
        Double dN2;
        Long lR;
        Long lR2;
        Path path;
        String str2;
        Integer numP;
        String str3;
        int i10 = 1;
        int i11 = 0;
        Path path2 = this.f95187q;
        if (path2 != null) {
            path2.reset();
        }
        Path path3 = this.f95189s;
        if (path3 != null) {
            path3.reset();
        }
        float fFloatValue = ((Number) p162hb.e.c(o(), Float.valueOf(abstractC2759w0.P(abstractC2759w0.v())), Float.valueOf(abstractC2759w0.P(abstractC2759w0.u())))).floatValue();
        float fFloatValue2 = ((Number) p162hb.e.c(o(), Float.valueOf(abstractC2759w0.P(abstractC2759w0.u())), Float.valueOf(abstractC2759w0.P(abstractC2759w0.v())))).floatValue();
        String strA = kk.f.a(scriptIndicAction, new StringBuilder(), "Value");
        if (scriptIndicAction.getOutput().getLineWidth() != null) {
            Paint paint = this.f95188r;
            if (paint != null) {
                paint.setStrokeWidth(scriptIndicAction.getOutput().getFloatLineWidth());
            }
            Paint paint2 = this.f95190t;
            if (paint2 != null) {
                paint2.setStrokeWidth(scriptIndicAction.getOutput().getFloatLineWidth());
            }
        }
        String str4 = "0";
        if (scriptIndicAction.getOutput().getLineDash() == null || (str = (String) Sf.z.q0(scriptIndicAction.getOutput().getLineDash())) == null) {
            str = "0";
        }
        if (scriptIndicAction.getOutput().getLineDash() != null && (str3 = (String) Sf.z.D0(scriptIndicAction.getOutput().getLineDash())) != null) {
            str4 = str3;
        }
        Float fO = Ah.v.o(str);
        float fFloatValue3 = fO != null ? fO.floatValue() : 0.0f;
        Float fO2 = Ah.v.o(str4);
        float fFloatValue4 = fO2 != null ? fO2.floatValue() : 0.0f;
        Paint paint3 = this.f95188r;
        if (paint3 != null) {
            paint3.setPathEffect(new DashPathEffect(new float[]{fFloatValue3, fFloatValue4}, 0.0f));
        }
        Paint paint4 = this.f95190t;
        if (paint4 != null) {
            paint4.setPathEffect(new DashPathEffect(new float[]{fFloatValue3, fFloatValue4}, 0.0f));
        }
        y1 y1Var = this.f95184n;
        long jM = y1Var != null ? y1Var.m() : 0L;
        new LinkedHashMap();
        if (jM > 0) {
            j10 = 0;
            linkedHashMap = (Map) map.get(String.valueOf(jM / ((long) 1000)));
            if (linkedHashMap == null) {
                linkedHashMap = new LinkedHashMap();
            }
        } else {
            j10 = 0;
            Map.Entry entry = (Map.Entry) Sf.z.p0(map.entrySet());
            if (entry == null || (linkedHashMap = (Map) entry.getValue()) == null) {
                linkedHashMap = new LinkedHashMap();
            }
        }
        int iA = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str2 = (String) linkedHashMap.get(strA)) == null || (numP = Ah.w.p(str2)) == null) ? f10.u()[this.f95160J].a() : numP.intValue();
        Paint paint5 = this.f95188r;
        if (paint5 != null) {
            paint5.setColor(iA);
        }
        C2702d c2702d = this.f95183m;
        int iU = c2702d != null ? c2702d.u() : 0;
        y1 y1Var2 = this.f95184n;
        float fW = iU + (y1Var2 != null ? y1Var2.w() : 0.0f);
        String str5 = (String) kk.g.a(scriptIndicAction, new StringBuilder(), "AllSegments", linkedHashMap);
        double d10 = 0.0d;
        if (str5 == null || str5.length() == 0) {
            String str6 = (String) kk.g.a(scriptIndicAction, new StringBuilder(), "AfterTransTime1", linkedHashMap);
            long jLongValue = (str6 == null || (lR2 = Ah.w.r(str6)) == null) ? j10 : lR2.longValue();
            String str7 = (String) kk.g.a(scriptIndicAction, new StringBuilder(), "AfterTransTime2", linkedHashMap);
            long jLongValue2 = (str7 == null || (lR = Ah.w.r(str7)) == null) ? j10 : lR.longValue();
            String str8 = (String) kk.g.a(scriptIndicAction, new StringBuilder(), "AfterTransValue1", linkedHashMap);
            double dDoubleValue = (str8 == null || (dN2 = Ah.v.n(str8)) == null) ? 0.0d : dN2.doubleValue();
            String str9 = (String) kk.g.a(scriptIndicAction, new StringBuilder(), "AfterTransValue2", linkedHashMap);
            double dDoubleValue2 = (str9 == null || (dN = Ah.v.n(str9)) == null) ? 0.0d : dN.doubleValue();
            if (jLongValue > j10 && jLongValue2 > j10 && dDoubleValue != 0.0d && dDoubleValue2 != 0.0d) {
                KLineManager.a aVar = KLineManager.f142490O;
                float fA = kk.k.a(aVar, dDoubleValue, abstractC2759w0);
                float fA2 = kk.k.a(aVar, dDoubleValue2, abstractC2759w0);
                PointF pointF = this.f95180d0;
                y1 y1Var3 = this.f95184n;
                pointF.x = y1Var3 != null ? y1Var3.j(((long) 1000) * jLongValue) : 0.0f;
                this.f95180d0.y = fA;
                PointF pointF2 = this.f95181e0;
                y1 y1Var4 = this.f95184n;
                pointF2.x = y1Var4 != null ? y1Var4.j(jLongValue2 * ((long) 1000)) : 0.0f;
                PointF pointF3 = this.f95181e0;
                pointF3.y = fA2;
                hk.a aVar2 = hk.a.f98027a;
                PointF pointF4 = this.f95180d0;
                aVar2.c(pointF4.x, pointF3.x, pointF4.y, fA2);
                aVar2.a(this.f95180d0, fFloatValue2, fFloatValue);
                PointF pointF5 = this.f95180d0;
                float f11 = pointF5.x - fW;
                float f12 = pointF5.y;
                PointF pointF6 = this.f95181e0;
                float f13 = pointF6.x - fW;
                float f14 = pointF6.y;
                Path path4 = this.f95187q;
                if (path4 != null) {
                    path4.moveTo(f11, f12);
                }
                Path path5 = this.f95187q;
                if (path5 != null) {
                    path5.lineTo(f13, f14);
                }
            }
        } else {
            Iterator it = Ah.y.M0(str5, new String[]{"|"}, false, 0, 6, null).iterator();
            while (it.hasNext()) {
                List listM0 = Ah.y.M0((String) it.next(), new String[]{","}, false, 0, 6, null);
                if (listM0.size() >= 4) {
                    Long lR3 = Ah.w.r((String) listM0.get(i11));
                    long jLongValue3 = lR3 != null ? lR3.longValue() : j10;
                    Double dN3 = Ah.v.n((String) listM0.get(i10));
                    double dDoubleValue3 = dN3 != null ? dN3.doubleValue() : d10;
                    Long lR4 = Ah.w.r((String) listM0.get(2));
                    long jLongValue4 = lR4 != null ? lR4.longValue() : j10;
                    Double dN4 = Ah.v.n((String) listM0.get(3));
                    double dDoubleValue4 = dN4 != null ? dN4.doubleValue() : d10;
                    if (jLongValue3 > j10 && jLongValue4 > j10 && dDoubleValue3 != d10 && dDoubleValue4 != d10) {
                        y1 y1Var5 = this.f95184n;
                        double d11 = d10;
                        float fJ = (y1Var5 != null ? y1Var5.j(jLongValue3 * ((long) 1000)) : 0.0f) - fW;
                        KLineManager.a aVar3 = KLineManager.f142490O;
                        float fA3 = kk.k.a(aVar3, dDoubleValue3, abstractC2759w0);
                        y1 y1Var6 = this.f95184n;
                        float fJ2 = (y1Var6 != null ? y1Var6.j(((long) 1000) * jLongValue4) : 0.0f) - fW;
                        float fA4 = kk.k.a(aVar3, dDoubleValue4, abstractC2759w0);
                        Path path6 = this.f95187q;
                        if (path6 != null) {
                            path6.moveTo(fJ, fA3);
                        }
                        Path path7 = this.f95187q;
                        if (path7 != null) {
                            path7.lineTo(fJ2, fA4);
                        }
                        d10 = d11;
                    }
                    i10 = 1;
                    i11 = 0;
                }
            }
        }
        Paint paint6 = this.f95188r;
        if (paint6 == null || (path = this.f95187q) == null) {
            return;
        }
        canvas.drawPath(path, paint6);
    }

    /* JADX WARN: Code duplicated, block: B:108:0x0241  */
    /* JADX WARN: Code duplicated, block: B:122:0x0272  */
    /* JADX WARN: Code duplicated, block: B:85:0x01f1  */
    /* JADX WARN: Failed to restore switch over string. Please report as a decompilation issue */
    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        J0 j10;
        y1 y1Var;
        List<ScriptIndicAction> action;
        ScriptIndicAction scriptIndicAction;
        sp.aicoin_kline.core.indicator.config.F f10;
        float f11;
        float f12;
        int i10;
        Map map;
        float f13;
        Double dN;
        Double dN2;
        int iAbs;
        long jH;
        int i11;
        String str;
        float f14;
        float f15;
        float f16;
        Double dN3;
        float f17;
        String str2;
        Integer numP;
        Double dN4;
        Long lR;
        int i12;
        Double dN5;
        Map map2;
        AbstractC2759w0 abstractC2759w0;
        sp.aicoin_kline.core.indicator.config.F f18;
        Map mapZ;
        int i13;
        boolean z10;
        AbstractC2759w0 abstractC2759w1;
        int i14;
        String str3;
        Integer numP2;
        Double dN6;
        Double dN7;
        Double dN8;
        U u10 = this;
        Canvas canvas2 = canvas;
        AbstractC2759w0 abstractC2759w2 = u10.f95185o;
        if (abstractC2759w2 == null || (j10 = u10.f95186p) == null || (y1Var = u10.f95184n) == null) {
            return;
        }
        sp.aicoin_kline.core.indicator.config.F fT = j10.t();
        List<ScriptDrawData> listR1 = Sf.z.r1(j10.s());
        if (listR1 == null || listR1.isEmpty()) {
            return;
        }
        nk.x.f134260a.e(listR1);
        C2765z c2765zH = u10.i().b().h(u10.c());
        if (c2765zH == null) {
            return;
        }
        u10.f95151A = c2765zH.D();
        int iR = y1Var.r();
        int iQ = y1Var.q();
        float fU = y1Var.u();
        float fJ = y1Var.J();
        float f19 = 2;
        float f20 = (fU / f19) - fJ;
        float f21 = (f19 * fU) / 3;
        int iY = y1Var.y();
        canvas2.save();
        for (ScriptDrawData scriptDrawData : listR1) {
            Map mapZ2 = Sf.N.z(scriptDrawData.getCalculateHistoryData());
            ScriptIndicConfig config = scriptDrawData.getConfig();
            u10.f95160J = 0;
            Map.Entry entry = (Map.Entry) Sf.z.p0(mapZ2.entrySet());
            Map map3 = entry != null ? (Map) entry.getValue() : null;
            if (!AbstractC7609s.f(KLineManager.f142490O.a().u().get(config != null ? config.getScriptRef() : null), Boolean.FALSE) && config != 0 && (action = config.getAction()) != null) {
                int i15 = 0;
                for (Object obj : action) {
                    int i16 = i15 + 1;
                    if (i15 < 0) {
                        Sf.r.x();
                    }
                    ScriptIndicAction scriptIndicAction2 = (ScriptIndicAction) obj;
                    Map map4 = map3;
                    String action2 = scriptIndicAction2.getAction();
                    int i17 = iR;
                    Map map5 = mapZ2;
                    float f22 = fJ;
                    float f23 = f20;
                    switch (action2.hashCode()) {
                        case -2020374621:
                            scriptIndicAction = scriptIndicAction2;
                            f10 = fT;
                            f11 = fU;
                            f12 = f21;
                            i10 = iY;
                            map = map4;
                            iR = i17;
                            iQ = iQ;
                            if (action2.equals("plotHist") && !AbstractC7609s.f(scriptIndicAction.getDisplay(), Boolean.FALSE)) {
                                u10 = this;
                                f22 = f22;
                                f13 = f11;
                                AbstractC2759w0 abstractC2759w3 = abstractC2759w2;
                                u10.w(canvas, f12, f13, f22, scriptIndicAction, abstractC2759w3, iR, i10, f10, Sf.N.z(map5));
                                abstractC2759w2 = abstractC2759w3;
                                iR = iR;
                                iY = i10;
                                fT = f10;
                            } else {
                                iR = iR;
                                u10 = this;
                                iY = i10;
                                f13 = f11;
                                fT = f10;
                            }
                            break;
                        case -2020167279:
                            scriptIndicAction = scriptIndicAction2;
                            f10 = fT;
                            f13 = fU;
                            f12 = f21;
                            map = map4;
                            iR = i17;
                            iQ = iQ;
                            if (action2.equals("plotOhlc") && !AbstractC7609s.f(scriptIndicAction.getDisplay(), Boolean.FALSE)) {
                                i10 = iY;
                                AbstractC2759w0 abstractC2759w4 = abstractC2759w2;
                                B(canvas, f12, f13, f22, scriptIndicAction, abstractC2759w4, iR, i10, Sf.N.z(map5));
                                f11 = f13;
                                abstractC2759w2 = abstractC2759w4;
                                if (AbstractC7609s.f(scriptIndicAction.getTrackPrice(), Boolean.TRUE) && map != null) {
                                    String close = scriptIndicAction.getClose();
                                    if (close == null) {
                                        close = "";
                                    }
                                    String str4 = (String) map.get(close);
                                    double dDoubleValue = (str4 == null || (dN = Ah.v.n(str4)) == null) ? 0.0d : dN.doubleValue();
                                    if (dDoubleValue != 0.0d) {
                                        StringBuilder sb2 = new StringBuilder();
                                        ActionOutput output = scriptIndicAction.getOutput();
                                        sb2.append(output != null ? output.getColor() : null);
                                        sb2.append("originValue");
                                        String str5 = (String) map.get(sb2.toString());
                                        y(canvas, abstractC2759w2, dDoubleValue, str5 == null ? "" : str5);
                                    }
                                }
                                iR = iR;
                                u10 = this;
                                iY = i10;
                                f13 = f11;
                            } else {
                                u10 = this;
                            }
                            fT = f10;
                            break;
                        case -2020020818:
                            scriptIndicAction = scriptIndicAction2;
                            f11 = fU;
                            f12 = f21;
                            map = map4;
                            iR = i17;
                            iQ = iQ;
                            if (action2.equals("plotText") && !AbstractC7609s.f(scriptIndicAction.getDisplay(), Boolean.FALSE)) {
                                u10 = this;
                                AbstractC2759w0 abstractC2759w5 = abstractC2759w2;
                                f13 = f11;
                                u10.E(canvas, f23, f13, scriptIndicAction, abstractC2759w5, iR, iQ, fT, Sf.N.z(map5));
                                abstractC2759w2 = abstractC2759w5;
                                f22 = f22;
                            } else {
                                u10 = this;
                                f22 = f22;
                                f13 = f11;
                            }
                            break;
                        case -608864346:
                            scriptIndicAction = scriptIndicAction2;
                            f10 = fT;
                            f11 = fU;
                            f12 = f21;
                            map = map4;
                            iR = i17;
                            iQ = iQ;
                            if (action2.equals("label.new") && !AbstractC7609s.f(scriptIndicAction.getDisplay(), Boolean.FALSE)) {
                                u10 = this;
                                AbstractC2759w0 abstractC2759w6 = abstractC2759w2;
                                u10.D(canvas, scriptIndicAction, abstractC2759w6, f10, map5);
                                abstractC2759w2 = abstractC2759w6;
                                fT = f10;
                                f22 = f22;
                                f13 = f11;
                            }
                            u10 = this;
                            f13 = f11;
                            fT = f10;
                            break;
                        case -405487794:
                            scriptIndicAction = scriptIndicAction2;
                            f10 = fT;
                            f11 = fU;
                            f12 = f21;
                            map = map4;
                            U u11 = u10;
                            AbstractC2759w0 abstractC2759w7 = abstractC2759w2;
                            iQ = iQ;
                            iR = i17;
                            if (!action2.equals("plotCandle")) {
                                u10 = u11;
                            } else if (!AbstractC7609s.f(scriptIndicAction.getDisplay(), Boolean.FALSE)) {
                                u11.v(canvas, f12, f11, f22, scriptIndicAction, abstractC2759w7, iR, iY, Sf.N.z(map5));
                                abstractC2759w2 = abstractC2759w7;
                                iR = iR;
                                if (AbstractC7609s.f(scriptIndicAction.getTrackPrice(), Boolean.TRUE) && map != null) {
                                    String close2 = scriptIndicAction.getClose();
                                    if (close2 == null) {
                                        close2 = "";
                                    }
                                    String str6 = (String) map.get(close2);
                                    double dDoubleValue2 = (str6 == null || (dN2 = Ah.v.n(str6)) == null) ? 0.0d : dN2.doubleValue();
                                    if (dDoubleValue2 != 0.0d) {
                                        StringBuilder sb3 = new StringBuilder();
                                        ActionOutput output2 = scriptIndicAction.getOutput();
                                        sb3.append(output2 != null ? output2.getColor() : null);
                                        sb3.append("originValue");
                                        String str7 = (String) map.get(sb3.toString());
                                        y(canvas, abstractC2759w2, dDoubleValue2, str7 == null ? "" : str7);
                                    }
                                }
                                u10 = this;
                                f13 = f11;
                                fT = f10;
                            } else {
                                u10 = this;
                            }
                            abstractC2759w2 = abstractC2759w7;
                            f13 = f11;
                            fT = f10;
                            break;
                        case -392601705:
                            f10 = fT;
                            f11 = fU;
                            f12 = f21;
                            map = map4;
                            U u12 = u10;
                            AbstractC2759w0 abstractC2759w8 = abstractC2759w2;
                            iQ = iQ;
                            if (action2.equals("plotColumn") && !AbstractC7609s.f(scriptIndicAction2.getDisplay(), Boolean.FALSE)) {
                                Map mapZ3 = Sf.N.z(map5);
                                float f24 = (f11 / 6) - f22;
                                float f25 = f24 + f12;
                                String histBase = scriptIndicAction2.getHistBase();
                                float f26 = f24;
                                float fA = kk.k.a(KLineManager.f142490O, (histBase == null || (dN5 = Ah.v.n(histBase)) == null) ? 0.0d : dN5.doubleValue(), abstractC2759w8);
                                int intOffset = scriptIndicAction2.getIntOffset();
                                if (intOffset < 0) {
                                    iAbs = Math.abs(intOffset) + iY;
                                    float f27 = intOffset * f11;
                                    f26 += f27;
                                    f25 += f27;
                                } else {
                                    iAbs = iY;
                                }
                                int i18 = intOffset > 0 ? i17 - intOffset : i17;
                                String strA = kk.f.a(scriptIndicAction2, new StringBuilder(), "Value");
                                if (scriptIndicAction2.getOutput().getFill()) {
                                    u12.f95193w.setStyle(Paint.Style.FILL);
                                } else {
                                    u12.f95193w.setStyle(Paint.Style.STROKE);
                                }
                                int intShowLast = scriptIndicAction2.getIntShowLast();
                                int i19 = (1 > intShowLast || intShowLast >= (i12 = u12.f95151A)) ? -1 : i12 - intShowLast;
                                try {
                                    y1 y1Var2 = u12.f95184n;
                                    jH = y1Var2 != null ? y1Var2.H(i19) : 0L;
                                } catch (Exception unused) {
                                }
                                while (i18 < iAbs) {
                                    int i20 = i19;
                                    y1 y1Var3 = u12.f95184n;
                                    Map map6 = (Map) mapZ3.get(String.valueOf(y1Var3 != null ? Long.valueOf(y1Var3.H(i18)) : null));
                                    if (map6 == null) {
                                        f17 = f26;
                                        i20 = i20;
                                        i11 = iAbs;
                                        str = strA;
                                        f16 = fA;
                                    } else {
                                        String str8 = (String) map6.get("time");
                                        long jLongValue = (str8 == null || (lR = Ah.w.r(str8)) == null) ? 0L : lR.longValue();
                                        String series = scriptIndicAction2.getSeries();
                                        if (series == null) {
                                            series = "0";
                                        }
                                        String str9 = (String) map6.get(series);
                                        double dDoubleValue3 = (str9 == null || (dN4 = Ah.v.n(str9)) == null) ? 0.0d : dN4.doubleValue();
                                        int iIntValue = dDoubleValue3 >= 0.0d ? u12.f95161K : u12.f95162L;
                                        if (strA != null && strA.length() != 0 && !AbstractC7609s.f(strA, "nullValue") && (str2 = (String) map6.get(strA)) != null && (numP = Ah.w.p(str2)) != null) {
                                            iIntValue = numP.intValue();
                                        }
                                        u12.f95193w.setColor(iIntValue);
                                        if (i20 <= 0 || jLongValue >= jH) {
                                            if (dDoubleValue3 == 0.0d) {
                                                float fQ = (abstractC2759w8.u() == 0.0d && abstractC2759w8.v() == 0.0d) ? fA + abstractC2759w8.q() : fA;
                                                int i21 = iAbs;
                                                f14 = f25;
                                                str = strA;
                                                f15 = f26;
                                                i11 = i21;
                                                canvas.drawLine(f15, fQ, f14, fQ, u12.f95193w);
                                            } else {
                                                float f28 = f26;
                                                i20 = i20;
                                                i11 = iAbs;
                                                str = strA;
                                                f14 = f25;
                                                String series2 = scriptIndicAction2.getSeries();
                                                if (series2 == null) {
                                                    series2 = "0";
                                                }
                                                String str10 = (String) map6.get(series2);
                                                float fA2 = kk.k.a(KLineManager.f142490O, (str10 == null || (dN3 = Ah.v.n(str10)) == null) ? 0.0d : dN3.doubleValue(), abstractC2759w8);
                                                if (Math.abs(fA - fA2) < 1.0f) {
                                                    f15 = f28;
                                                    float f29 = fA;
                                                    canvas.drawLine(f15, f29, f14, fA, u12.f95193w);
                                                    f16 = f29;
                                                } else {
                                                    f15 = f28;
                                                    f16 = fA;
                                                    nk.y.a(canvas, f15, fA2, f14, f16, u12.f95193w);
                                                }
                                            }
                                            f17 = f15 + f11;
                                            f25 = f14 + f11;
                                        } else {
                                            f15 = f26;
                                            i11 = iAbs;
                                            str = strA;
                                            f14 = f25;
                                        }
                                        f16 = fA;
                                        f17 = f15 + f11;
                                        f25 = f14 + f11;
                                    }
                                    i18++;
                                    fA = f16;
                                    iAbs = i11;
                                    strA = str;
                                    i19 = i20;
                                    f26 = f17;
                                    mapZ3 = mapZ3;
                                }
                            }
                            iR = i17;
                            u10 = u12;
                            abstractC2759w2 = abstractC2759w8;
                            scriptIndicAction = scriptIndicAction2;
                            f13 = f11;
                            fT = f10;
                            break;
                        case 3143043:
                            scriptIndicAction = scriptIndicAction2;
                            f11 = fU;
                            f12 = f21;
                            map = map4;
                            iR = i17;
                            if (action2.equals("fill") && !AbstractC7609s.f(scriptIndicAction.getDisplay(), Boolean.FALSE)) {
                                u10 = this;
                                AbstractC2759w0 abstractC2759w9 = abstractC2759w2;
                                f13 = f11;
                                u10.x(canvas, f23, f13, scriptIndicAction, abstractC2759w9, iR, iQ, fT, Sf.N.z(map5));
                                abstractC2759w2 = abstractC2759w9;
                                iQ = iQ;
                                f22 = f22;
                            }
                            u10 = this;
                            iQ = iQ;
                            f22 = f22;
                            f13 = f11;
                            break;
                        case 3443937:
                            scriptIndicAction = scriptIndicAction2;
                            f11 = fU;
                            f12 = f21;
                            map = map4;
                            map2 = map5;
                            if (action2.equals("plot") && !AbstractC7609s.f(scriptIndicAction.getDisplay(), Boolean.FALSE)) {
                                iR = i17;
                                AbstractC2759w0 abstractC2759w10 = abstractC2759w2;
                                C(canvas, f23, f11, scriptIndicAction, abstractC2759w10, iR, iQ, fT, map2);
                                abstractC2759w2 = abstractC2759w10;
                                map5 = map2;
                                if (AbstractC7609s.f(scriptIndicAction.getTrackPrice(), Boolean.TRUE) && map != null) {
                                    String series3 = scriptIndicAction.getSeries();
                                    if (series3 == null) {
                                        series3 = "0";
                                    }
                                    String str11 = (String) map.get(series3);
                                    if (str11 == null) {
                                        str11 = "0.0";
                                    }
                                    Double dN9 = Ah.v.n(str11);
                                    double dDoubleValue4 = dN9 != null ? dN9.doubleValue() : 0.0d;
                                    if (dDoubleValue4 != 0.0d) {
                                        StringBuilder sb4 = new StringBuilder();
                                        ActionOutput output3 = scriptIndicAction.getOutput();
                                        sb4.append(output3 != null ? output3.getColor() : null);
                                        sb4.append("originValue");
                                        String str12 = (String) map.get(sb4.toString());
                                        y(canvas, abstractC2759w2, dDoubleValue4, str12 == null ? "" : str12);
                                    }
                                }
                                u10 = this;
                                iQ = iQ;
                                f22 = f22;
                                f13 = f11;
                            }
                            u10 = this;
                            map5 = map2;
                            iQ = iQ;
                            iR = i17;
                            f22 = f22;
                            f13 = f11;
                            break;
                        case 71185149:
                            scriptIndicAction = scriptIndicAction2;
                            f11 = fU;
                            f12 = f21;
                            map = map4;
                            map2 = map5;
                            if (action2.equals("box.new") && !AbstractC7609s.f(scriptIndicAction.getDisplay(), Boolean.FALSE)) {
                                u10 = this;
                                AbstractC2759w0 abstractC2759w11 = abstractC2759w2;
                                u10.z(canvas, scriptIndicAction, abstractC2759w11, fT, map2);
                                abstractC2759w2 = abstractC2759w11;
                            } else {
                                u10 = this;
                            }
                            map5 = map2;
                            iQ = iQ;
                            iR = i17;
                            f22 = f22;
                            f13 = f11;
                            break;
                        case 1187522726:
                            abstractC2759w0 = abstractC2759w2;
                            scriptIndicAction = scriptIndicAction2;
                            f18 = fT;
                            f11 = fU;
                            f12 = f21;
                            if (action2.equals("line.new")) {
                                map = map4;
                                if (!AbstractC7609s.f(scriptIndicAction.getDisplay(), Boolean.FALSE)) {
                                    u10.F(canvas2, scriptIndicAction, abstractC2759w0, f18, map5);
                                    u10 = this;
                                    abstractC2759w2 = abstractC2759w0;
                                    fT = f18;
                                    iQ = iQ;
                                    iR = i17;
                                    f22 = f22;
                                    f13 = f11;
                                } else {
                                    u10 = this;
                                }
                            } else {
                                map = map4;
                            }
                            iR = i17;
                            f22 = f22;
                            f13 = f11;
                            fT = f18;
                            abstractC2759w2 = abstractC2759w0;
                            break;
                        case 1803007808:
                            if (action2.equals("plotShape") && !AbstractC7609s.f(scriptIndicAction2.getDisplay(), Boolean.FALSE)) {
                                Map mapZ4 = Sf.N.z(map5);
                                u10.f95153C.reset();
                                u10.f95154D.reset();
                                int intOffset2 = scriptIndicAction2.getIntOffset();
                                String strA2 = kk.f.a(scriptIndicAction2, new StringBuilder(), "Value");
                                scriptIndicAction2.getOutput().getBgColor();
                                int intShowLast2 = scriptIndicAction2.getIntShowLast();
                                scriptIndicAction = scriptIndicAction2;
                                ArrayList arrayList = new ArrayList();
                                if (intOffset2 != 0) {
                                    List listB = Sf.P.B(mapZ4);
                                    int i22 = 0;
                                    for (Object obj2 : listB) {
                                        int i23 = i22 + 1;
                                        if (i22 < 0) {
                                            Sf.r.x();
                                        }
                                        sp.aicoin_kline.core.indicator.config.F f30 = fT;
                                        int i24 = (intOffset2 * (-1)) + i22;
                                        Object objD = ((Qf.p) obj2).d();
                                        float f31 = fU;
                                        Map map7 = (Map) objD;
                                        String series4 = scriptIndicAction.getSeries();
                                        int i25 = intOffset2;
                                        String str13 = (String) map7.get(series4 == null ? "0" : series4);
                                        boolean z11 = ((str13 == null || (dN8 = Ah.v.n(str13)) == null) ? 0.0d : dN8.doubleValue()) > 0.0d;
                                        if (i24 >= 0 && i24 < listB.size() && z11) {
                                            arrayList.add(listB.get(i24));
                                        }
                                        fU = f31;
                                        i22 = i23;
                                        intOffset2 = i25;
                                        fT = f30;
                                    }
                                }
                                f18 = fT;
                                f11 = fU;
                                int i26 = intOffset2;
                                if (i26 != 0) {
                                    mapZ = Sf.N.z(Sf.N.v(arrayList));
                                }
                                if (intShowLast2 > 0) {
                                    mapZ = mapZ4;
                                    if (intShowLast2 < mapZ.size()) {
                                        i13 = (u10.f95151A - intShowLast2) + i26;
                                    } else {
                                        mapZ = mapZ4;
                                        i13 = 0;
                                    }
                                } else {
                                    mapZ = mapZ4;
                                    i13 = 0;
                                }
                                nk.x.f134260a.c(mapZ);
                                int i27 = i17;
                                float f32 = f23;
                                while (i27 < iQ) {
                                    y1 y1Var4 = u10.f95184n;
                                    Map linkedHashMap = (Map) mapZ.get(String.valueOf(y1Var4 != null ? Long.valueOf(y1Var4.H(i27)) : null));
                                    if (linkedHashMap == null) {
                                        linkedHashMap = new LinkedHashMap();
                                    }
                                    if (i26 == 0) {
                                        String series5 = scriptIndicAction.getSeries();
                                        if (series5 == null) {
                                            series5 = "0";
                                        }
                                        String str14 = (String) linkedHashMap.get(series5);
                                        if (((str14 == null || (dN7 = Ah.v.n(str14)) == null) ? 0.0d : dN7.doubleValue()) > 0.0d) {
                                            z10 = true;
                                        } else {
                                            z10 = false;
                                        }
                                    } else {
                                        z10 = true;
                                    }
                                    String refSeries = scriptIndicAction.getRefSeries();
                                    Map map8 = mapZ;
                                    String str15 = (String) linkedHashMap.get(refSeries == null ? "" : refSeries);
                                    double dDoubleValue5 = (str15 == null || (dN6 = Ah.v.n(str15)) == null) ? 0.0d : dN6.doubleValue();
                                    if (dDoubleValue5 != 0.0d && z10) {
                                        float fA3 = kk.k.a(KLineManager.f142490O, dDoubleValue5, abstractC2759w2);
                                        int iA = (strA2 == null || strA2.length() == 0 || AbstractC7609s.f(strA2, "nullValue") || (str3 = (String) linkedHashMap.get(strA2)) == null || (numP2 = Ah.w.p(str3)) == null) ? f18.u()[u10.f95160J].a() : numP2.intValue();
                                        if (scriptIndicAction.getOutput().getFill()) {
                                            u10.f95152B.setStyle(Paint.Style.FILL_AND_STROKE);
                                        } else {
                                            u10.f95152B.setStyle(Paint.Style.STROKE);
                                        }
                                        u10.f95152B.setColor(iA);
                                        String placement = scriptIndicAction.getOutput().getPlacement();
                                        String shape = scriptIndicAction.getOutput().getShape();
                                        if (i27 >= i13) {
                                            abstractC2759w1 = abstractC2759w2;
                                            i14 = i13;
                                            switch (shape.hashCode()) {
                                                case -1360216880:
                                                    if (shape.equals("circle")) {
                                                        u10.f95159I = Xj.a.a(10.0f);
                                                        if (AbstractC7609s.f(placement, "bottom")) {
                                                            canvas2.drawCircle(f32, fA3 + u10.f95159I, Xj.a.a(3.0f), u10.f95152B);
                                                        } else if (AbstractC7609s.f(placement, "center")) {
                                                            canvas2.drawCircle(f32, fA3, Xj.a.a(3.0f), u10.f95152B);
                                                        } else {
                                                            canvas2.drawCircle(f32, fA3 - u10.f95159I, Xj.a.a(3.0f), u10.f95152B);
                                                        }
                                                    }
                                                    break;
                                                case -1026432949:
                                                    if (shape.equals("arrowDown")) {
                                                        u10.f95155E = Xj.a.a(6.0f);
                                                        u10.f95156F = Xj.a.a(7.0f);
                                                        u10.f95157G = Xj.a.a(10.0f);
                                                        u10.f95158H = Xj.a.a(2.0f);
                                                        u10.f95159I = Xj.a.a(7.0f);
                                                        if (AbstractC7609s.f(placement, "bottom")) {
                                                            u10.f95153C.moveTo(f32, u10.f95159I + fA3);
                                                            u10.f95153C.lineTo(u10.f95158H + f32, u10.f95159I + fA3);
                                                            u10.f95153C.lineTo(u10.f95158H + f32, u10.f95157G + fA3 + u10.f95159I);
                                                            u10.f95153C.lineTo(u10.f95155E + f32, u10.f95157G + fA3 + u10.f95159I);
                                                            u10.f95153C.lineTo(f32, u10.f95157G + fA3 + u10.f95156F + u10.f95159I);
                                                            u10.f95153C.lineTo(f32 - u10.f95155E, u10.f95157G + fA3 + u10.f95159I);
                                                            u10.f95153C.lineTo(f32 - u10.f95158H, u10.f95157G + fA3 + u10.f95159I);
                                                            u10.f95153C.lineTo(f32 - u10.f95158H, fA3 + u10.f95159I);
                                                            u10.f95153C.close();
                                                        } else if (AbstractC7609s.f(placement, "center")) {
                                                            u10.f95153C.moveTo(f32, fA3 - u10.f95159I);
                                                            u10.f95153C.lineTo(u10.f95158H + f32, fA3 - u10.f95159I);
                                                            u10.f95153C.lineTo(u10.f95158H + f32, (u10.f95157G + fA3) - u10.f95159I);
                                                            u10.f95153C.lineTo(u10.f95155E + f32, (u10.f95157G + fA3) - u10.f95159I);
                                                            u10.f95153C.lineTo(f32, ((u10.f95157G + fA3) + u10.f95156F) - u10.f95159I);
                                                            u10.f95153C.lineTo(f32 - u10.f95155E, (u10.f95157G + fA3) - u10.f95159I);
                                                            u10.f95153C.lineTo(f32 - u10.f95158H, (u10.f95157G + fA3) - u10.f95159I);
                                                            u10.f95153C.lineTo(f32 - u10.f95158H, fA3 - u10.f95159I);
                                                            u10.f95153C.close();
                                                        } else {
                                                            u10.f95153C.moveTo(f32, fA3 - u10.f95159I);
                                                            u10.f95153C.lineTo(u10.f95155E + f32, (fA3 - u10.f95156F) - u10.f95159I);
                                                            u10.f95153C.lineTo(u10.f95158H + f32, (fA3 - u10.f95156F) - u10.f95159I);
                                                            u10.f95153C.lineTo(u10.f95158H + f32, (fA3 - u10.f95157G) - u10.f95159I);
                                                            u10.f95153C.lineTo(u10.f95158H + f32, ((fA3 - u10.f95157G) - u10.f95156F) - u10.f95159I);
                                                            u10.f95153C.lineTo(f32 - u10.f95158H, ((fA3 - u10.f95157G) - u10.f95156F) - u10.f95159I);
                                                            u10.f95153C.lineTo(f32 - u10.f95158H, (fA3 - u10.f95156F) - u10.f95159I);
                                                            u10.f95153C.lineTo(f32 - u10.f95155E, (fA3 - u10.f95156F) - u10.f95159I);
                                                            u10.f95153C.close();
                                                        }
                                                    }
                                                    break;
                                                case -742236470:
                                                    if (shape.equals("triangleDown")) {
                                                        u10.f95155E = Xj.a.a(7.0f);
                                                        u10.f95156F = Xj.a.a(9.0f);
                                                        u10.f95159I = Xj.a.a(5.0f);
                                                        if (AbstractC7609s.f(placement, "bottom")) {
                                                            u10.f95153C.moveTo(f32, u10.f95159I + fA3);
                                                            u10.f95153C.lineTo(u10.f95155E + f32, u10.f95159I + fA3);
                                                            u10.f95153C.lineTo(f32, u10.f95159I + fA3 + u10.f95156F);
                                                            u10.f95153C.lineTo(f32 - u10.f95155E, fA3 + u10.f95159I);
                                                            u10.f95153C.close();
                                                        } else if (AbstractC7609s.f(placement, "center")) {
                                                            u10.f95153C.moveTo(f32, fA3 - u10.f95159I);
                                                            u10.f95153C.lineTo(u10.f95155E + f32, fA3 - u10.f95159I);
                                                            u10.f95153C.lineTo(f32, (fA3 - u10.f95159I) + u10.f95156F);
                                                            u10.f95153C.lineTo(f32 - u10.f95155E, fA3 - u10.f95159I);
                                                            u10.f95153C.close();
                                                        } else {
                                                            u10.f95155E = Xj.a.a(7.0f);
                                                            u10.f95156F = Xj.a.a(9.0f);
                                                            float fA4 = Xj.a.a(5.0f);
                                                            u10.f95159I = fA4;
                                                            u10.f95153C.moveTo(f32, fA3 - fA4);
                                                            u10.f95153C.lineTo(u10.f95155E + f32, (fA3 - u10.f95159I) - u10.f95156F);
                                                            u10.f95153C.lineTo(f32 - u10.f95155E, (fA3 - u10.f95159I) - u10.f95156F);
                                                            u10.f95153C.close();
                                                        }
                                                    }
                                                    break;
                                                case -734027644:
                                                    if (shape.equals("arrowUp")) {
                                                        u10.f95155E = Xj.a.a(6.0f);
                                                        u10.f95156F = Xj.a.a(7.0f);
                                                        u10.f95157G = Xj.a.a(10.0f);
                                                        u10.f95158H = Xj.a.a(2.0f);
                                                        u10.f95159I = Xj.a.a(7.0f);
                                                        if (AbstractC7609s.f(placement, "bottom")) {
                                                            u10.f95153C.moveTo(f32, u10.f95159I + fA3);
                                                            u10.f95153C.lineTo(u10.f95155E + f32, u10.f95156F + fA3 + u10.f95159I);
                                                            u10.f95153C.lineTo(u10.f95158H + f32, u10.f95156F + fA3 + u10.f95159I);
                                                            u10.f95153C.lineTo(u10.f95158H + f32, u10.f95157G + fA3 + u10.f95159I);
                                                            u10.f95153C.lineTo(u10.f95158H + f32, u10.f95157G + fA3 + u10.f95156F + u10.f95159I);
                                                            u10.f95153C.lineTo(f32 - u10.f95158H, u10.f95157G + fA3 + u10.f95156F + u10.f95159I);
                                                            u10.f95153C.lineTo(f32 - u10.f95158H, u10.f95156F + fA3 + u10.f95159I);
                                                            u10.f95153C.lineTo(f32 - u10.f95155E, fA3 + u10.f95156F + u10.f95159I);
                                                            u10.f95153C.close();
                                                        } else if (AbstractC7609s.f(placement, "center")) {
                                                            u10.f95153C.moveTo(f32, fA3 - u10.f95159I);
                                                            u10.f95153C.lineTo(u10.f95155E + f32, (u10.f95156F + fA3) - u10.f95159I);
                                                            u10.f95153C.lineTo(u10.f95158H + f32, (u10.f95156F + fA3) - u10.f95159I);
                                                            u10.f95153C.lineTo(u10.f95158H + f32, (u10.f95157G + fA3) - u10.f95159I);
                                                            u10.f95153C.lineTo(u10.f95158H + f32, ((u10.f95157G + fA3) + u10.f95156F) - u10.f95159I);
                                                            u10.f95153C.lineTo(f32 - u10.f95158H, ((u10.f95157G + fA3) + u10.f95156F) - u10.f95159I);
                                                            u10.f95153C.lineTo(f32 - u10.f95158H, (u10.f95156F + fA3) - u10.f95159I);
                                                            u10.f95153C.lineTo(f32 - u10.f95155E, (fA3 + u10.f95156F) - u10.f95159I);
                                                            u10.f95153C.close();
                                                        } else {
                                                            u10.f95153C.moveTo(f32, fA3 - u10.f95159I);
                                                            u10.f95153C.lineTo(u10.f95158H + f32, fA3 - u10.f95159I);
                                                            u10.f95153C.lineTo(u10.f95158H + f32, (fA3 - u10.f95157G) - u10.f95159I);
                                                            u10.f95153C.lineTo(u10.f95155E + f32, (fA3 - u10.f95157G) - u10.f95159I);
                                                            u10.f95153C.lineTo(f32, ((fA3 - u10.f95157G) - u10.f95156F) - u10.f95159I);
                                                            u10.f95153C.lineTo(f32 - u10.f95155E, (fA3 - u10.f95157G) - u10.f95159I);
                                                            u10.f95153C.lineTo(f32 - u10.f95158H, (fA3 - u10.f95157G) - u10.f95159I);
                                                            u10.f95153C.lineTo(f32 - u10.f95158H, fA3 - u10.f95159I);
                                                            u10.f95153C.close();
                                                        }
                                                    }
                                                    break;
                                                case 535540419:
                                                    if (shape.equals("triangleUp")) {
                                                        if (AbstractC7609s.f(placement, "bottom")) {
                                                            u10.f95155E = Xj.a.a(7.0f);
                                                            u10.f95156F = Xj.a.a(9.0f);
                                                            float fA5 = Xj.a.a(5.0f);
                                                            u10.f95159I = fA5;
                                                            u10.f95153C.moveTo(f32, fA5 + fA3);
                                                            u10.f95153C.lineTo(u10.f95155E + f32, u10.f95159I + fA3 + u10.f95156F);
                                                            u10.f95153C.lineTo(f32 - u10.f95155E, fA3 + u10.f95159I + u10.f95156F);
                                                            u10.f95153C.close();
                                                        } else if (AbstractC7609s.f(placement, "center")) {
                                                            u10.f95155E = Xj.a.a(7.0f);
                                                            u10.f95156F = Xj.a.a(9.0f);
                                                            float fA6 = Xj.a.a(5.0f);
                                                            u10.f95159I = fA6;
                                                            u10.f95153C.moveTo(f32, fA3 - fA6);
                                                            u10.f95153C.lineTo(u10.f95155E + f32, (fA3 - u10.f95159I) + u10.f95156F);
                                                            u10.f95153C.lineTo(f32 - u10.f95155E, (fA3 - u10.f95159I) + u10.f95156F);
                                                            u10.f95153C.close();
                                                        } else {
                                                            u10.f95155E = Xj.a.a(7.0f);
                                                            u10.f95156F = Xj.a.a(9.0f);
                                                            float fA7 = Xj.a.a(5.0f);
                                                            u10.f95159I = fA7;
                                                            u10.f95153C.moveTo(f32, fA3 - fA7);
                                                            u10.f95153C.lineTo(u10.f95155E + f32, fA3 - u10.f95159I);
                                                            u10.f95153C.lineTo(f32, (fA3 - u10.f95159I) - u10.f95156F);
                                                            u10.f95153C.lineTo(f32 - u10.f95155E, fA3 - u10.f95159I);
                                                            u10.f95153C.close();
                                                        }
                                                    }
                                                    break;
                                            }
                                        } else {
                                            abstractC2759w1 = abstractC2759w2;
                                            i14 = i13;
                                        }
                                    } else {
                                        abstractC2759w1 = abstractC2759w2;
                                        i14 = i13;
                                    }
                                    f32 += f11;
                                    i27++;
                                    f21 = f21;
                                    mapZ = map8;
                                    abstractC2759w2 = abstractC2759w1;
                                    i13 = i14;
                                }
                                abstractC2759w0 = abstractC2759w2;
                                f12 = f21;
                                canvas2.drawPath(u10.f95153C, u10.f95152B);
                                map = map4;
                                iR = i17;
                                f22 = f22;
                                f13 = f11;
                                fT = f18;
                                abstractC2759w2 = abstractC2759w0;
                                break;
                            }
                        default:
                            scriptIndicAction = scriptIndicAction2;
                            f13 = fU;
                            f12 = f21;
                            map = map4;
                            iR = i17;
                            f22 = f22;
                            iQ = iQ;
                            break;
                    }
                    String color = scriptIndicAction.getOutput().getColor();
                    if (color == null || color.length() == 0) {
                        int i28 = u10.f95160J + 1;
                        u10.f95160J = i28;
                        if (i28 >= 9) {
                            u10.f95160J = 8;
                        }
                    }
                    canvas2 = canvas;
                    fU = f13;
                    fJ = f22;
                    map3 = map;
                    iQ = iQ;
                    i15 = i16;
                    mapZ2 = map5;
                    f20 = f23;
                    f21 = f12;
                }
            }
            canvas2 = canvas;
        }
        canvas.restore();
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        if (aVar == null) {
            return;
        }
        C2741q c2741qB = i().b();
        this.f95182l = c2741qB;
        this.f95183m = c2741qB.e(b());
        this.f95184n = this.f95182l.m(c());
        this.f95185o = this.f95182l.l(b());
        AbstractC2755v abstractC2755vQ = q();
        J0 j10 = abstractC2755vQ instanceof J0 ? (J0) abstractC2755vQ : null;
        if (j10 == null) {
            return;
        }
        this.f95161K = aVar.r();
        this.f95162L = aVar.m();
        this.f95186p = j10;
        this.f95187q = new Path();
        this.f95189s = new Path();
        Paint paint = new Paint();
        Paint.Style style = Paint.Style.STROKE;
        paint.setStyle(style);
        paint.setAntiAlias(true);
        paint.setStrokeWidth(2.0f);
        paint.setColor(-16777216);
        this.f95188r = paint;
        Paint paint2 = new Paint();
        paint2.setStyle(style);
        paint2.setAntiAlias(true);
        paint2.setStrokeWidth(2.0f);
        paint2.setColor(-16777216);
        this.f95190t = paint2;
        Paint paint3 = new Paint();
        paint3.setStyle(style);
        paint3.setAntiAlias(true);
        paint3.setStrokeWidth(2.0f);
        paint3.setColor(-16711936);
        this.f95196z = paint3;
        Paint paint4 = new Paint(1);
        paint4.setAntiAlias(true);
        paint4.setColor(-16777216);
        paint4.setTextSize(Xj.a.d(9));
        this.f95191u = paint4;
        Paint paint5 = new Paint();
        paint5.setStyle(style);
        paint5.setAntiAlias(true);
        paint5.setStrokeWidth(2.0f);
        paint5.setColor(-16711936);
        this.f95193w = paint5;
        this.f95194x = new Path();
        Paint paint6 = new Paint();
        Paint.Style style2 = Paint.Style.FILL_AND_STROKE;
        paint6.setStyle(style2);
        paint6.setAntiAlias(false);
        paint6.setStrokeWidth(0.0f);
        paint6.setColor(-16711936);
        this.f95195y = paint6;
        Paint paint7 = new Paint();
        paint7.setStyle(style);
        paint7.setAntiAlias(true);
        paint7.setStrokeWidth(Xj.a.a(1.0f));
        paint7.setColor(-16711936);
        this.f95152B = paint7;
        Paint paint8 = new Paint();
        paint8.setStyle(style2);
        paint8.setAntiAlias(true);
        paint8.setStrokeWidth(2.0f);
        paint8.setColor(-1);
        this.f95174X.setStyle(style2);
        if (KLineManager.f142490O.a().f0() == 1) {
            this.f95173W.setStrokeWidth(1.0f);
            this.f95175Y.setStrokeWidth(1.0f);
        }
        this.f95172V.setStyle(style);
        this.f95172V.setAntiAlias(true);
        this.f95171U.setStrokeWidth(2.0f);
        this.f95174X.setStrokeWidth(2.0f);
        this.f95172V.setStrokeWidth(1.0f);
        this.f95171U.setColor(aVar.r());
        this.f95172V.setColor(0);
        this.f95173W.setColor(aVar.r());
        this.f95174X.setColor(aVar.m());
        this.f95175Y.setColor(aVar.m());
        this.f95176Z.setColor(aVar.r());
        this.f95179c0.setStyle(style);
        this.f95179c0.setStrokeWidth(2.0f);
        this.f95179c0.setColor(aVar.t());
        this.f95179c0.setPathEffect(new DashPathEffect(new float[]{Xj.a.b(3), Xj.a.b(2)}, 0.0f));
    }

    /* JADX WARN: Code duplicated, block: B:108:0x01ec  */
    /* JADX WARN: Code duplicated, block: B:110:0x025f  */
    /* JADX WARN: Code duplicated, block: B:111:0x0261  */
    /* JADX WARN: Code duplicated, block: B:142:0x02bc  */
    /* JADX WARN: Code duplicated, block: B:144:0x02ce  */
    /* JADX WARN: Code duplicated, block: B:147:0x02fa  */
    /* JADX WARN: Code duplicated, block: B:150:0x0310  */
    /* JADX WARN: Code duplicated, block: B:152:0x0316  */
    /* JADX WARN: Code duplicated, block: B:153:0x0328  */
    /* JADX WARN: Code duplicated, block: B:155:0x033c  */
    /* JADX WARN: Code duplicated, block: B:158:0x034b  */
    /* JADX WARN: Code duplicated, block: B:160:0x0351  */
    /* JADX WARN: Code duplicated, block: B:161:0x035e  */
    /* JADX WARN: Code duplicated, block: B:162:0x036c  */
    /* JADX WARN: Code duplicated, block: B:164:0x0375  */
    /* JADX WARN: Code duplicated, block: B:180:0x03bd  */
    /* JADX WARN: Code duplicated, block: B:181:0x03d0  */
    /* JADX WARN: Code duplicated, block: B:184:0x03da  */
    /* JADX WARN: Code duplicated, block: B:185:0x03e8  */
    /* JADX WARN: Code duplicated, block: B:187:0x045d  */
    /* JADX WARN: Code duplicated, block: B:188:0x045f  */
    /* JADX WARN: Code duplicated, block: B:219:0x04ba  */
    /* JADX WARN: Code duplicated, block: B:221:0x04c9  */
    /* JADX WARN: Code duplicated, block: B:223:0x04f6  */
    /* JADX WARN: Code duplicated, block: B:226:0x050b  */
    /* JADX WARN: Code duplicated, block: B:228:0x0511  */
    /* JADX WARN: Code duplicated, block: B:229:0x0521  */
    /* JADX WARN: Code duplicated, block: B:230:0x0533  */
    /* JADX WARN: Code duplicated, block: B:233:0x0541  */
    /* JADX WARN: Code duplicated, block: B:235:0x0547  */
    /* JADX WARN: Code duplicated, block: B:236:0x0550  */
    public final void v(Canvas canvas, float f10, float f11, float f12, ScriptIndicAction scriptIndicAction, AbstractC2759w0 abstractC2759w0, int i10, int i11, Map map) {
        int iAbs;
        long jH;
        int i12;
        float f13;
        float f14;
        boolean z10;
        float fAbs;
        double d10;
        int i13;
        double d11;
        float fFloatValue;
        float fFloatValue2;
        float fFloatValue3;
        float fFloatValue4;
        boolean z11;
        float f15;
        float f16;
        float f17;
        float f18;
        float f19;
        float f20;
        float f21;
        double d12;
        float f22;
        double d13;
        double d14;
        float fFloatValue5;
        float fFloatValue6;
        float fFloatValue7;
        float fFloatValue8;
        boolean z12;
        float f23;
        float f24;
        float f25;
        float f26;
        float f27;
        float f28;
        float f29;
        Integer numP;
        Double dN;
        Double dN2;
        Double dN3;
        Double dN4;
        Long lR;
        int i14;
        float f30 = (f11 / 6) - f12;
        float f31 = f30 + f10;
        float f32 = 2;
        this.f95177a0.reset();
        int intOffset = scriptIndicAction.getIntOffset();
        if (intOffset < 0) {
            float f33 = intOffset * f11;
            f30 += f33;
            f31 += f33;
            iAbs = Math.abs(intOffset) + i11;
        } else {
            iAbs = i11;
        }
        int i15 = intOffset > 0 ? i10 - intOffset : i10;
        int intShowLast = scriptIndicAction.getIntShowLast();
        int i16 = (1 > intShowLast || intShowLast >= (i14 = this.f95151A)) ? -1 : i14 - intShowLast;
        try {
            y1 y1Var = this.f95184n;
            jH = y1Var != null ? y1Var.H(i16) : 0L;
        } catch (Exception unused) {
        }
        float f34 = f30;
        int i17 = i15;
        while (i17 < iAbs) {
            y1 y1Var2 = this.f95184n;
            Map map2 = (Map) map.get(String.valueOf(y1Var2 != null ? Long.valueOf(y1Var2.H(i17)) : null));
            if (map2 == null) {
                i12 = i17;
                f14 = f32;
                i13 = iAbs;
                i16 = i16;
            } else {
                String str = (String) map2.get("time");
                long jLongValue = (str == null || (lR = Ah.w.r(str)) == null) ? 0L : lR.longValue();
                String open = scriptIndicAction.getOpen();
                String str2 = (String) map2.get(open == null ? "0" : open);
                double dDoubleValue = (str2 == null || (dN4 = Ah.v.n(str2)) == null) ? 0.0d : dN4.doubleValue();
                this.f95168R = dDoubleValue;
                KLineManager.a aVar = KLineManager.f142490O;
                this.f95164N = kk.k.a(aVar, dDoubleValue, abstractC2759w0);
                String high = scriptIndicAction.getHigh();
                if (high == null) {
                    high = "0";
                }
                String str3 = (String) map2.get(high);
                double dDoubleValue2 = (str3 == null || (dN3 = Ah.v.n(str3)) == null) ? 0.0d : dN3.doubleValue();
                this.f95167Q = dDoubleValue2;
                this.f95163M = kk.k.a(aVar, dDoubleValue2, abstractC2759w0);
                String low = scriptIndicAction.getLow();
                if (low == null) {
                    low = "0";
                }
                String str4 = (String) map2.get(low);
                double dDoubleValue3 = (str4 == null || (dN2 = Ah.v.n(str4)) == null) ? 0.0d : dN2.doubleValue();
                this.f95169S = dDoubleValue3;
                this.f95165O = kk.k.a(aVar, dDoubleValue3, abstractC2759w0);
                String close = scriptIndicAction.getClose();
                if (close == null) {
                    close = "0";
                }
                String str5 = (String) map2.get(close);
                double dDoubleValue4 = (str5 == null || (dN = Ah.v.n(str5)) == null) ? 0.0d : dN.doubleValue();
                this.f95170T = dDoubleValue4;
                this.f95166P = kk.k.a(aVar, dDoubleValue4, abstractC2759w0);
                if (this.f95168R == 0.0d || this.f95167Q == 0.0d || this.f95169S == 0.0d || this.f95170T == 0.0d) {
                    i12 = i17;
                    f13 = f34;
                    f14 = f32;
                } else {
                    String strA = kk.f.a(scriptIndicAction, new StringBuilder(), "Value");
                    i12 = i17;
                    StringBuilder sb2 = new StringBuilder();
                    f13 = f34;
                    sb2.append(scriptIndicAction.getOutput().getBorderColor());
                    sb2.append("Value");
                    String string = sb2.toString();
                    String str6 = scriptIndicAction.getOutput().getWickColor() + "Value";
                    if (string == null || string.length() == 0 || AbstractC7609s.f(string, "nullValue")) {
                        f14 = f32;
                    } else {
                        String str7 = (String) map2.get(string);
                        int iIntValue = (str7 == null || (numP = Ah.w.p(str7)) == null) ? -1 : numP.intValue();
                        f14 = f32;
                        if (iIntValue != -1) {
                            this.f95172V.setColor(iIntValue);
                            z10 = true;
                        }
                        fAbs = (Math.abs(f31 - f13) / f14) + f13;
                        if (i16 > 0 || jLongValue >= jH) {
                            d10 = this.f95170T;
                            i13 = iAbs;
                            d11 = this.f95168R;
                            if (d10 > d11) {
                                this.f95173W.setStrokeWidth(3.0f);
                                fFloatValue5 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95164N), Float.valueOf(this.f95166P))).floatValue();
                                fFloatValue6 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95166P), Float.valueOf(this.f95164N))).floatValue();
                                fFloatValue7 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95165O), Float.valueOf(this.f95163M))).floatValue();
                                fFloatValue8 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95163M), Float.valueOf(this.f95165O))).floatValue();
                                if (fFloatValue6 - fFloatValue5 >= 2.0f) {
                                    z12 = true;
                                } else {
                                    z12 = false;
                                }
                                this.f95173W.setColor(strA != null ? this.f95161K : this.f95161K);
                                this.f95171U.setColor(str6 != null ? this.f95161K : this.f95161K);
                                if (z12) {
                                    f24 = fFloatValue5;
                                    canvas.drawRect(f13, f24, f31 - 1, fFloatValue6, this.f95173W);
                                    f23 = fFloatValue6;
                                    if (z10) {
                                        float f35 = f13 - f14;
                                        float f36 = f24 - f14;
                                        this.f95177a0.moveTo(f35, f36);
                                        float f37 = f31 + f14;
                                        this.f95177a0.lineTo(f37, f36);
                                        float f38 = f23 + f14;
                                        this.f95177a0.lineTo(f37, f38);
                                        this.f95177a0.lineTo(f35, f38);
                                        this.f95177a0.close();
                                        canvas.drawPath(this.f95177a0, this.f95172V);
                                    }
                                    f13 = f13;
                                } else {
                                    f23 = fFloatValue6;
                                    f24 = fFloatValue5;
                                    canvas.drawLine(f13, f24, f31, fFloatValue5, this.f95173W);
                                }
                                f25 = f24;
                                if (this.f95167Q > this.f95170T) {
                                    if (o()) {
                                        f28 = fAbs;
                                        canvas.drawLine(f28, fFloatValue8, fAbs, f23, this.f95173W);
                                        f26 = fFloatValue7;
                                        f27 = f25;
                                    } else {
                                        f28 = fAbs;
                                        canvas.drawLine(f28, fFloatValue7, f28, f25, this.f95173W);
                                        f26 = fFloatValue7;
                                        f27 = f25;
                                    }
                                    f29 = f28;
                                    if (this.f95169S < this.f95168R) {
                                        if (o()) {
                                            canvas.drawLine(f29, f27, f29, f26, this.f95173W);
                                        } else {
                                            canvas.drawLine(f29, f23, f29, fFloatValue8, this.f95173W);
                                        }
                                    }
                                } else {
                                    f26 = fFloatValue7;
                                    f27 = f25;
                                    f28 = fAbs;
                                }
                                f29 = f28;
                                if (this.f95169S < this.f95168R) {
                                    if (o()) {
                                        canvas.drawLine(f29, f27, f29, f26, this.f95173W);
                                    } else {
                                        canvas.drawLine(f29, f23, f29, fFloatValue8, this.f95173W);
                                    }
                                }
                            } else {
                                i16 = i16;
                                if (d10 == d11) {
                                    float f39 = this.f95164N;
                                    this.f95176Z.setColor(strA != null ? this.f95161K : this.f95161K);
                                    this.f95176Z.setStrokeWidth(2.0f);
                                    f21 = f39;
                                    canvas.drawLine(f13, f21, f31, f39, this.f95176Z);
                                    d12 = this.f95167Q;
                                    if (d12 > this.f95170T) {
                                        f22 = fAbs;
                                        canvas.drawLine(f22, kk.k.a(aVar, d12, abstractC2759w0), fAbs, f21, this.f95176Z);
                                        f21 = f21;
                                    } else {
                                        f22 = fAbs;
                                    }
                                    d13 = this.f95168R;
                                    d14 = this.f95169S;
                                    if (d13 > d14) {
                                        canvas.drawLine(f22, f21, f22, kk.k.a(aVar, d14, abstractC2759w0), this.f95176Z);
                                    }
                                } else {
                                    this.f95175Y.setStrokeWidth(3.0f);
                                    fFloatValue = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95166P), Float.valueOf(this.f95164N))).floatValue();
                                    fFloatValue2 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95164N), Float.valueOf(this.f95166P))).floatValue();
                                    fFloatValue3 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95165O), Float.valueOf(this.f95163M))).floatValue();
                                    fFloatValue4 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95163M), Float.valueOf(this.f95165O))).floatValue();
                                    if (fFloatValue2 - fFloatValue >= 1.0f) {
                                        z11 = true;
                                    } else {
                                        z11 = false;
                                    }
                                    this.f95175Y.setColor(strA != null ? this.f95162L : this.f95162L);
                                    this.f95174X.setColor(str6 != null ? this.f95162L : this.f95162L);
                                    if (z11) {
                                        f20 = f31;
                                        canvas.drawRect(f13, fFloatValue, f20, fFloatValue2, this.f95175Y);
                                        f15 = fFloatValue2;
                                        if (z10) {
                                            float f40 = f13 - f14;
                                            float f41 = fFloatValue - f14;
                                            this.f95177a0.moveTo(f40, f41);
                                            float f42 = f20 + f14;
                                            this.f95177a0.lineTo(f42, f41);
                                            float f43 = f15 + f14;
                                            this.f95177a0.lineTo(f42, f43);
                                            this.f95177a0.lineTo(f40, f43);
                                            this.f95177a0.close();
                                            canvas.drawPath(this.f95177a0, this.f95172V);
                                        }
                                        f13 = f13;
                                        f16 = fFloatValue;
                                        f31 = f20;
                                    } else {
                                        f15 = fFloatValue2;
                                        canvas.drawLine(f13, fFloatValue, f31, fFloatValue, this.f95175Y);
                                        f16 = fFloatValue;
                                    }
                                    if (this.f95167Q > this.f95168R) {
                                        f17 = fFloatValue3;
                                        f18 = f16;
                                        f19 = fAbs;
                                    } else if (o()) {
                                        f19 = fAbs;
                                        canvas.drawLine(f19, fFloatValue4, fAbs, f15, this.f95175Y);
                                        f17 = fFloatValue3;
                                        f18 = f16;
                                    } else {
                                        f19 = fAbs;
                                        float f44 = f16;
                                        canvas.drawLine(f19, fFloatValue3, f19, f44, this.f95175Y);
                                        f17 = fFloatValue3;
                                        f18 = f44;
                                    }
                                    if (this.f95169S < this.f95170T) {
                                        if (o()) {
                                            canvas.drawLine(f19, f18, f19, f17, this.f95175Y);
                                        } else {
                                            canvas.drawLine(f19, f15, f19, fFloatValue4, this.f95175Y);
                                        }
                                    }
                                }
                            }
                        }
                        f34 = f13 + f11;
                        f31 += f11;
                    }
                    z10 = false;
                    fAbs = (Math.abs(f31 - f13) / f14) + f13;
                    if (i16 > 0) {
                    }
                    d10 = this.f95170T;
                    i13 = iAbs;
                    d11 = this.f95168R;
                    if (d10 > d11) {
                        this.f95173W.setStrokeWidth(3.0f);
                        fFloatValue5 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95164N), Float.valueOf(this.f95166P))).floatValue();
                        fFloatValue6 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95166P), Float.valueOf(this.f95164N))).floatValue();
                        fFloatValue7 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95165O), Float.valueOf(this.f95163M))).floatValue();
                        fFloatValue8 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95163M), Float.valueOf(this.f95165O))).floatValue();
                        if (fFloatValue6 - fFloatValue5 >= 2.0f) {
                            z12 = true;
                        } else {
                            z12 = false;
                        }
                        this.f95173W.setColor(strA != null ? this.f95161K : this.f95161K);
                        this.f95171U.setColor(str6 != null ? this.f95161K : this.f95161K);
                        if (z12) {
                            f24 = fFloatValue5;
                            canvas.drawRect(f13, f24, f31 - 1, fFloatValue6, this.f95173W);
                            f23 = fFloatValue6;
                            if (z10) {
                                float f310 = f13 - f14;
                                float f311 = f24 - f14;
                                this.f95177a0.moveTo(f310, f311);
                                float f312 = f31 + f14;
                                this.f95177a0.lineTo(f312, f311);
                                float f313 = f23 + f14;
                                this.f95177a0.lineTo(f312, f313);
                                this.f95177a0.lineTo(f310, f313);
                                this.f95177a0.close();
                                canvas.drawPath(this.f95177a0, this.f95172V);
                            }
                            f13 = f13;
                        } else {
                            f23 = fFloatValue6;
                            f24 = fFloatValue5;
                            canvas.drawLine(f13, f24, f31, fFloatValue5, this.f95173W);
                        }
                        f25 = f24;
                        if (this.f95167Q > this.f95170T) {
                            if (o()) {
                                f28 = fAbs;
                                canvas.drawLine(f28, fFloatValue8, fAbs, f23, this.f95173W);
                                f26 = fFloatValue7;
                                f27 = f25;
                            } else {
                                f28 = fAbs;
                                canvas.drawLine(f28, fFloatValue7, f28, f25, this.f95173W);
                                f26 = fFloatValue7;
                                f27 = f25;
                            }
                            f29 = f28;
                            if (this.f95169S < this.f95168R) {
                                if (o()) {
                                    canvas.drawLine(f29, f27, f29, f26, this.f95173W);
                                } else {
                                    canvas.drawLine(f29, f23, f29, fFloatValue8, this.f95173W);
                                }
                            }
                        } else {
                            f26 = fFloatValue7;
                            f27 = f25;
                            f28 = fAbs;
                        }
                        f29 = f28;
                        if (this.f95169S < this.f95168R) {
                            if (o()) {
                                canvas.drawLine(f29, f27, f29, f26, this.f95173W);
                            } else {
                                canvas.drawLine(f29, f23, f29, fFloatValue8, this.f95173W);
                            }
                        }
                    } else {
                        i16 = i16;
                        if (d10 == d11) {
                            float f314 = this.f95164N;
                            this.f95176Z.setColor(strA != null ? this.f95161K : this.f95161K);
                            this.f95176Z.setStrokeWidth(2.0f);
                            f21 = f314;
                            canvas.drawLine(f13, f21, f31, f314, this.f95176Z);
                            d12 = this.f95167Q;
                            if (d12 > this.f95170T) {
                                f22 = fAbs;
                                canvas.drawLine(f22, kk.k.a(aVar, d12, abstractC2759w0), fAbs, f21, this.f95176Z);
                                f21 = f21;
                            } else {
                                f22 = fAbs;
                            }
                            d13 = this.f95168R;
                            d14 = this.f95169S;
                            if (d13 > d14) {
                                canvas.drawLine(f22, f21, f22, kk.k.a(aVar, d14, abstractC2759w0), this.f95176Z);
                            }
                        } else {
                            this.f95175Y.setStrokeWidth(3.0f);
                            fFloatValue = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95166P), Float.valueOf(this.f95164N))).floatValue();
                            fFloatValue2 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95164N), Float.valueOf(this.f95166P))).floatValue();
                            fFloatValue3 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95165O), Float.valueOf(this.f95163M))).floatValue();
                            fFloatValue4 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95163M), Float.valueOf(this.f95165O))).floatValue();
                            if (fFloatValue2 - fFloatValue >= 1.0f) {
                                z11 = true;
                            } else {
                                z11 = false;
                            }
                            this.f95175Y.setColor(strA != null ? this.f95162L : this.f95162L);
                            this.f95174X.setColor(str6 != null ? this.f95162L : this.f95162L);
                            if (z11) {
                                f20 = f31;
                                canvas.drawRect(f13, fFloatValue, f20, fFloatValue2, this.f95175Y);
                                f15 = fFloatValue2;
                                if (z10) {
                                    float f45 = f13 - f14;
                                    float f46 = fFloatValue - f14;
                                    this.f95177a0.moveTo(f45, f46);
                                    float f47 = f20 + f14;
                                    this.f95177a0.lineTo(f47, f46);
                                    float f48 = f15 + f14;
                                    this.f95177a0.lineTo(f47, f48);
                                    this.f95177a0.lineTo(f45, f48);
                                    this.f95177a0.close();
                                    canvas.drawPath(this.f95177a0, this.f95172V);
                                }
                                f13 = f13;
                                f16 = fFloatValue;
                                f31 = f20;
                            } else {
                                f15 = fFloatValue2;
                                canvas.drawLine(f13, fFloatValue, f31, fFloatValue, this.f95175Y);
                                f16 = fFloatValue;
                            }
                            if (this.f95167Q > this.f95168R) {
                                f17 = fFloatValue3;
                                f18 = f16;
                                f19 = fAbs;
                            } else if (o()) {
                                f19 = fAbs;
                                canvas.drawLine(f19, fFloatValue4, fAbs, f15, this.f95175Y);
                                f17 = fFloatValue3;
                                f18 = f16;
                            } else {
                                f19 = fAbs;
                                float f49 = f16;
                                canvas.drawLine(f19, fFloatValue3, f19, f49, this.f95175Y);
                                f17 = fFloatValue3;
                                f18 = f49;
                            }
                            if (this.f95169S < this.f95170T) {
                                if (o()) {
                                    canvas.drawLine(f19, f18, f19, f17, this.f95175Y);
                                } else {
                                    canvas.drawLine(f19, f15, f19, fFloatValue4, this.f95175Y);
                                }
                            }
                        }
                    }
                    f34 = f13 + f11;
                    f31 += f11;
                }
                i13 = iAbs;
                i16 = i16;
                f34 = f13 + f11;
                f31 += f11;
            }
            i17 = i12 + 1;
            f32 = f14;
            i16 = i16;
            iAbs = i13;
        }
    }

    public final void w(Canvas canvas, float f10, float f11, float f12, ScriptIndicAction scriptIndicAction, AbstractC2759w0 abstractC2759w0, int i10, int i11, sp.aicoin_kline.core.indicator.config.F f13, Map map) {
        int iAbs;
        long jH;
        int iA;
        float f14;
        Integer numP;
        Double dN;
        Long lR;
        int i12;
        Double dN2;
        float f15 = (f11 / 6) - f12;
        float f16 = f15 + f10;
        String histBase = scriptIndicAction.getHistBase();
        float fA = kk.k.a(KLineManager.f142490O, (histBase == null || (dN2 = Ah.v.n(histBase)) == null) ? 0.0d : dN2.doubleValue(), abstractC2759w0);
        int intOffset = scriptIndicAction.getIntOffset();
        if (intOffset < 0) {
            iAbs = Math.abs(intOffset) + i11;
            float f17 = intOffset * f11;
            f15 += f17;
            f16 += f17;
        } else {
            iAbs = i11;
        }
        int i13 = intOffset > 0 ? i10 - intOffset : i10;
        String strA = kk.f.a(scriptIndicAction, new StringBuilder(), "Value");
        int intShowLast = scriptIndicAction.getIntShowLast();
        int i14 = (1 > intShowLast || intShowLast >= (i12 = this.f95151A)) ? -1 : i12 - intShowLast;
        try {
            y1 y1Var = this.f95184n;
            jH = y1Var != null ? y1Var.H(i14) : 0L;
        } catch (Exception unused) {
        }
        while (i13 < iAbs) {
            y1 y1Var2 = this.f95184n;
            Map map2 = (Map) map.get(String.valueOf(y1Var2 != null ? Long.valueOf(y1Var2.H(i13)) : null));
            if (map2 == null) {
                i14 = i14;
            } else {
                String str = (String) map2.get("time");
                long jLongValue = (str == null || (lR = Ah.w.r(str)) == null) ? 0L : lR.longValue();
                String series = scriptIndicAction.getSeries();
                if (series == null) {
                    series = "0";
                }
                String str2 = (String) map2.get(series);
                double dDoubleValue = (str2 == null || (dN = Ah.v.n(str2)) == null) ? 0.0d : dN.doubleValue();
                if (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue")) {
                    iA = dDoubleValue >= 0.0d ? this.f95161K : this.f95162L;
                } else {
                    String str3 = (String) map2.get(strA);
                    iA = (str3 == null || (numP = Ah.w.p(str3)) == null) ? f13.u()[this.f95160J].a() : numP.intValue();
                }
                this.f95196z.setColor(iA);
                if (i14 <= 0 || jLongValue >= jH) {
                    if (dDoubleValue == 0.0d) {
                        float fQ = (abstractC2759w0.u() == 0.0d && abstractC2759w0.v() == 0.0d) ? abstractC2759w0.q() + fA : fA;
                        f14 = f15;
                        canvas.drawLine(f14, fQ, f16, fQ, this.f95196z);
                        i14 = i14;
                    } else {
                        float fA2 = kk.k.a(KLineManager.f142490O, dDoubleValue, abstractC2759w0);
                        if (Math.abs(fA - fA2) < 1.0f) {
                            canvas.drawLine(f15, fA, f16, fA, this.f95196z);
                        } else {
                            i14 = i14;
                            f14 = f15;
                            float fAbs = (Math.abs(f16 - f14) / 2) + f14;
                            float f18 = fA;
                            canvas.drawLine(fAbs, fA2, fAbs, f18, this.f95196z);
                            fA = f18;
                        }
                    }
                    f15 = f14 + f11;
                    f16 += f11;
                }
                f14 = f15;
                f15 = f14 + f11;
                f16 += f11;
            }
            i13++;
            i14 = i14;
        }
    }

    public final void x(Canvas canvas, float f10, float f11, ScriptIndicAction scriptIndicAction, AbstractC2759w0 abstractC2759w0, int i10, int i11, sp.aicoin_kline.core.indicator.config.F f12, Map map) {
        float f13;
        int iAbs;
        long jH;
        Path path;
        float f14;
        Map map2;
        int color;
        float f15;
        float f16;
        PointF pointF;
        Integer numP;
        Double dN;
        Double dN2;
        Long lR;
        int i12;
        Path path2 = this.f95194x;
        if (path2 != null) {
            path2.reset();
        }
        float fFloatValue = ((Number) p162hb.e.c(o(), Float.valueOf(abstractC2759w0.P(abstractC2759w0.v())), Float.valueOf(abstractC2759w0.P(abstractC2759w0.u())))).floatValue();
        int intOffset = scriptIndicAction.getIntOffset();
        String strA = kk.f.a(scriptIndicAction, new StringBuilder(), "Value");
        if (intOffset < 0) {
            iAbs = Math.abs(intOffset) + i11;
            f13 = (intOffset * f11) + f10;
        } else {
            f13 = f10;
            iAbs = i11;
        }
        int i13 = intOffset > 0 ? i10 - intOffset : i10;
        int intShowLast = scriptIndicAction.getIntShowLast();
        int i14 = (1 > intShowLast || intShowLast >= (i12 = this.f95151A)) ? -1 : i12 - intShowLast;
        try {
            y1 y1Var = this.f95184n;
            jH = y1Var != null ? y1Var.H(i14) : 0L;
        } catch (Exception unused) {
        }
        ArrayList<a> arrayList = new ArrayList();
        float f17 = f13;
        boolean z10 = true;
        float f18 = 0.0f;
        float f19 = 0.0f;
        float f20 = 0.0f;
        while (i13 < iAbs) {
            y1 y1Var2 = this.f95184n;
            if (y1Var2 == null || (map2 = (Map) map.get(String.valueOf(y1Var2.H(i13)))) == null) {
                f14 = fFloatValue;
                i13 = i13;
            } else {
                String str = (String) map2.get("time");
                long jLongValue = (str == null || (lR = Ah.w.r(str)) == null) ? 0L : lR.longValue();
                if (i14 <= 0 || jLongValue >= jH) {
                    String str2 = (String) map2.get(scriptIndicAction.getSeries1());
                    double dDoubleValue = (str2 == null || (dN2 = Ah.v.n(str2)) == null) ? 0.0d : dN2.doubleValue();
                    f14 = fFloatValue;
                    String str3 = (String) map2.get(scriptIndicAction.getSeries2());
                    double dDoubleValue2 = (str3 == null || (dN = Ah.v.n(str3)) == null) ? 0.0d : dN.doubleValue();
                    if (dDoubleValue == 0.0d || dDoubleValue2 == 0.0d) {
                        f17 += f11;
                        z10 = true;
                    } else {
                        KLineManager.a aVar = KLineManager.f142490O;
                        float fA = kk.k.a(aVar, dDoubleValue, abstractC2759w0);
                        float fA2 = kk.k.a(aVar, dDoubleValue2, abstractC2759w0);
                        if (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue")) {
                            color = Color.parseColor("#1A9915FF");
                        } else {
                            String str4 = (String) map2.get(strA);
                            color = (str4 == null || (numP = Ah.w.p(str4)) == null) ? f12.u()[this.f95160J].a() : numP.intValue();
                        }
                        int i15 = color;
                        if (z10) {
                            f15 = fA2;
                            f16 = fA;
                        } else {
                            if ((f19 <= f20 || fA >= fA2) && (f19 >= f20 || fA <= fA2)) {
                                pointF = null;
                            } else {
                                float f21 = f17 - f18;
                                float f22 = ((((f19 - f20) - (fA - fA2)) / (2 * f21)) * f21) + f18;
                                pointF = new PointF(f22, ((f22 - f18) * ((fA - f19) / f21)) + f19);
                            }
                            if (pointF != null) {
                                float f23 = pointF.x;
                                float f24 = pointF.y;
                                arrayList.add(new a(f18, f19, f20, f23, f24, f24, f19 < f20, i15));
                                float f25 = pointF.x;
                                float f26 = pointF.y;
                                f15 = fA2;
                                f16 = fA;
                                arrayList.add(new a(f25, f26, f26, f17, f16, f15, fA < fA2, i15));
                            } else {
                                f15 = fA2;
                                f16 = fA;
                                arrayList.add(new a(f18, f19, f20, f17, f16, f15, f19 < f20 && f16 < f15, i15));
                            }
                        }
                        z10 = false;
                        f18 = f17;
                        f19 = f16;
                        f20 = f15;
                        f17 += f11;
                    }
                } else {
                    f17 += f11;
                    f14 = fFloatValue;
                    i13 = i13;
                }
            }
            i13++;
            fFloatValue = f14;
            iAbs = iAbs;
        }
        float f27 = fFloatValue;
        for (a aVar2 : arrayList) {
            Path path3 = this.f95194x;
            if (path3 != null) {
                path3.reset();
            }
            float fA3 = aVar2.a();
            float fB = aVar2.b();
            float fC = aVar2.c();
            float fD = aVar2.d();
            float fE = aVar2.e();
            float f28 = aVar2.f();
            boolean zG = aVar2.g();
            float f29 = zG ? fB : fC;
            if (zG) {
                fB = fC;
            }
            float f30 = zG ? fE : f28;
            if (zG) {
                fE = f28;
            }
            Path path4 = this.f95194x;
            if (path4 != null) {
                path4.moveTo(fA3, f29);
                hk.a.f98027a.d(fA3, f29, fD, f30, f27, path4);
                path4.lineTo(fD, fE);
                path4.lineTo(fA3, fB);
                path4.close();
            }
            Paint paint = this.f95195y;
            if (paint != null) {
                paint.setColor(aVar2.h());
            }
            Paint paint2 = this.f95195y;
            if (paint2 != null && (path = this.f95194x) != null) {
                canvas.drawPath(path, paint2);
            }
        }
    }

    public final void y(Canvas canvas, AbstractC2759w0 abstractC2759w0, double d10, String str) {
        Ah.j jVarC;
        Ah.j.b bVarA;
        if (this.f95183m != null) {
            float fA = kk.k.a(KLineManager.f142490O, d10, abstractC2759w0);
            Path path = this.f95178b0;
            path.reset();
            path.moveTo(this.f95183m.u(), fA);
            path.lineTo(this.f95183m.y(), fA);
            if (str.length() != 0 && (jVarC = Ah.l.c(new Ah.l("rgba\\((\\d+),(\\d+),(\\d+),((?:\\d+(?:\\.\\d*)?|\\.\\d+))\\)"), str, 0, 2, null)) != null && (bVarA = jVarC.a()) != null) {
                Double dN = Ah.v.n((String) kk.j.a(bVarA, 4));
                if (((float) ((dN != null ? dN.doubleValue() : 0.0d) * ((double) 255))) == 0.0f) {
                    return;
                }
            }
            canvas.drawPath(this.f95178b0, this.f95179c0);
        }
    }

    public final void z(Canvas canvas, ScriptIndicAction scriptIndicAction, AbstractC2759w0 abstractC2759w0, sp.aicoin_kline.core.indicator.config.F f10, Map map) {
        String str;
        Map linkedHashMap;
        Double dN;
        Double dN2;
        Long lR;
        Long lR2;
        String str2;
        Integer numP;
        String str3;
        Paint paint;
        int i10 = 1;
        int i11 = 0;
        int i12 = 2;
        String strA = kk.f.a(scriptIndicAction, new StringBuilder(), "Value");
        if (scriptIndicAction.getOutput().getLineWidth() != null && (paint = this.f95188r) != null) {
            paint.setStrokeWidth(scriptIndicAction.getOutput().getFloatLineWidth());
        }
        String str4 = "0";
        if (scriptIndicAction.getOutput().getLineDash() == null || (str = (String) Sf.z.q0(scriptIndicAction.getOutput().getLineDash())) == null) {
            str = "0";
        }
        if (scriptIndicAction.getOutput().getLineDash() != null && (str3 = (String) Sf.z.D0(scriptIndicAction.getOutput().getLineDash())) != null) {
            str4 = str3;
        }
        Float fO = Ah.v.o(str);
        float fFloatValue = fO != null ? fO.floatValue() : 0.0f;
        Float fO2 = Ah.v.o(str4);
        float fFloatValue2 = fO2 != null ? fO2.floatValue() : 0.0f;
        Paint paint2 = this.f95188r;
        if (paint2 != null) {
            paint2.setPathEffect(new DashPathEffect(new float[]{fFloatValue, fFloatValue2}, 0.0f));
        }
        y1 y1Var = this.f95184n;
        long jM = y1Var != null ? y1Var.m() : 0L;
        new LinkedHashMap();
        if (jM > 0) {
            linkedHashMap = (Map) map.get(String.valueOf(jM / ((long) 1000)));
            if (linkedHashMap == null) {
                linkedHashMap = new LinkedHashMap();
            }
        } else {
            Map.Entry entry = (Map.Entry) Sf.z.p0(map.entrySet());
            if (entry == null || (linkedHashMap = (Map) entry.getValue()) == null) {
                linkedHashMap = new LinkedHashMap();
            }
        }
        int iA = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str2 = (String) linkedHashMap.get(strA)) == null || (numP = Ah.w.p(str2)) == null) ? f10.u()[this.f95160J].a() : numP.intValue();
        Paint paint3 = this.f95188r;
        if (paint3 != null) {
            paint3.setColor(iA);
        }
        C2702d c2702d = this.f95183m;
        int iU = c2702d != null ? c2702d.u() : 0;
        y1 y1Var2 = this.f95184n;
        float fW = iU + (y1Var2 != null ? y1Var2.w() : 0.0f);
        String str5 = (String) kk.g.a(scriptIndicAction, new StringBuilder(), "AllBoxes", linkedHashMap);
        if (str5 == null || str5.length() == 0) {
            String str6 = (String) kk.g.a(scriptIndicAction, new StringBuilder(), "AfterTransTime1", linkedHashMap);
            long jLongValue = (str6 == null || (lR2 = Ah.w.r(str6)) == null) ? 0L : lR2.longValue();
            String str7 = (String) kk.g.a(scriptIndicAction, new StringBuilder(), "AfterTransTime2", linkedHashMap);
            long jLongValue2 = (str7 == null || (lR = Ah.w.r(str7)) == null) ? 0L : lR.longValue();
            String str8 = (String) kk.g.a(scriptIndicAction, new StringBuilder(), "AfterTransValue1", linkedHashMap);
            double dDoubleValue = (str8 == null || (dN2 = Ah.v.n(str8)) == null) ? 0.0d : dN2.doubleValue();
            String str9 = (String) kk.g.a(scriptIndicAction, new StringBuilder(), "AfterTransValue2", linkedHashMap);
            double dDoubleValue2 = (str9 == null || (dN = Ah.v.n(str9)) == null) ? 0.0d : dN.doubleValue();
            if (jLongValue <= 0 || jLongValue2 <= 0 || dDoubleValue == 0.0d || dDoubleValue2 == 0.0d) {
                return;
            }
            y1 y1Var3 = this.f95184n;
            float fJ = (y1Var3 != null ? y1Var3.j(jLongValue * ((long) 1000)) : 0.0f) - fW;
            y1 y1Var4 = this.f95184n;
            float fJ2 = (y1Var4 != null ? y1Var4.j(jLongValue2 * ((long) 1000)) : 0.0f) - fW;
            KLineManager.a aVar = KLineManager.f142490O;
            float fA = kk.k.a(aVar, dDoubleValue, abstractC2759w0);
            float fA2 = kk.k.a(aVar, dDoubleValue2, abstractC2759w0);
            Paint paint4 = this.f95188r;
            if (paint4 != null) {
                canvas.drawRect(fJ, fA, fJ2, fA2, paint4);
                return;
            }
            return;
        }
        Iterator it = Ah.y.M0(str5, new String[]{"|"}, false, 0, 6, null).iterator();
        while (it.hasNext()) {
            List listM0 = Ah.y.M0((String) it.next(), new String[]{","}, false, 0, 6, null);
            if (listM0.size() >= 4) {
                Long lR3 = Ah.w.r((String) listM0.get(i11));
                long jLongValue3 = lR3 != null ? lR3.longValue() : 0L;
                Double dN3 = Ah.v.n((String) listM0.get(i10));
                double dDoubleValue3 = dN3 != null ? dN3.doubleValue() : 0.0d;
                Long lR4 = Ah.w.r((String) listM0.get(i12));
                long jLongValue4 = lR4 != null ? lR4.longValue() : 0L;
                Double dN4 = Ah.v.n((String) listM0.get(3));
                double dDoubleValue4 = dN4 != null ? dN4.doubleValue() : 0.0d;
                if (jLongValue3 > 0 && jLongValue4 > 0 && dDoubleValue3 != 0.0d && dDoubleValue4 != 0.0d) {
                    y1 y1Var5 = this.f95184n;
                    float f11 = fW;
                    float fJ3 = (y1Var5 != null ? y1Var5.j(jLongValue3 * ((long) 1000)) : 0.0f) - f11;
                    y1 y1Var6 = this.f95184n;
                    float fJ4 = (y1Var6 != null ? y1Var6.j(((long) 1000) * jLongValue4) : 0.0f) - f11;
                    KLineManager.a aVar2 = KLineManager.f142490O;
                    float fA3 = kk.k.a(aVar2, dDoubleValue3, abstractC2759w0);
                    float fA4 = kk.k.a(aVar2, dDoubleValue4, abstractC2759w0);
                    Paint paint5 = this.f95188r;
                    if (paint5 != null) {
                        canvas.drawRect(fJ3, fA3, fJ4, fA4, paint5);
                    }
                    fW = f11;
                }
                i10 = 1;
                i11 = 0;
                i12 = 2;
            }
        }
    }
}
