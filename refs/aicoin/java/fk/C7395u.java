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
import android.graphics.DashPathEffect;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PointF;
import android.graphics.Rect;
import com.tencent.android.tpush.XGPushManager;
import gk.N0;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.chart.data.ActionOutput;
import sp.aicoin_kline.chart.data.ScriptDrawData;
import sp.aicoin_kline.chart.data.ScriptIndicAction;
import sp.aicoin_kline.chart.data.ScriptIndicConfig;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: fk.u, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7395u extends AbstractC2744r0 {

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public Paint f95518A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public final Path f95519B;

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public final Path f95520C;

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public float f95521D;

    /* JADX INFO: renamed from: E, reason: collision with root package name */
    public float f95522E;

    /* JADX INFO: renamed from: F, reason: collision with root package name */
    public float f95523F;

    /* JADX INFO: renamed from: G, reason: collision with root package name */
    public float f95524G;

    /* JADX INFO: renamed from: H, reason: collision with root package name */
    public float f95525H;

    /* JADX INFO: renamed from: I, reason: collision with root package name */
    public int f95526I;

    /* JADX INFO: renamed from: J, reason: collision with root package name */
    public int f95527J;

    /* JADX INFO: renamed from: K, reason: collision with root package name */
    public int f95528K;

    /* JADX INFO: renamed from: L, reason: collision with root package name */
    public float f95529L;

    /* JADX INFO: renamed from: M, reason: collision with root package name */
    public float f95530M;

    /* JADX INFO: renamed from: N, reason: collision with root package name */
    public float f95531N;

    /* JADX INFO: renamed from: O, reason: collision with root package name */
    public float f95532O;

    /* JADX INFO: renamed from: P, reason: collision with root package name */
    public double f95533P;

    /* JADX INFO: renamed from: Q, reason: collision with root package name */
    public double f95534Q;

    /* JADX INFO: renamed from: R, reason: collision with root package name */
    public double f95535R;

    /* JADX INFO: renamed from: S, reason: collision with root package name */
    public double f95536S;

    /* JADX INFO: renamed from: T, reason: collision with root package name */
    public final Paint f95537T;

    /* JADX INFO: renamed from: U, reason: collision with root package name */
    public final Paint f95538U;

    /* JADX INFO: renamed from: V, reason: collision with root package name */
    public final Paint f95539V;

    /* JADX INFO: renamed from: W, reason: collision with root package name */
    public final Paint f95540W;

    /* JADX INFO: renamed from: X, reason: collision with root package name */
    public final Paint f95541X;

    /* JADX INFO: renamed from: Y, reason: collision with root package name */
    public final Paint f95542Y;

    /* JADX INFO: renamed from: Z, reason: collision with root package name */
    public final Path f95543Z;

    /* JADX INFO: renamed from: a0, reason: collision with root package name */
    public int f95544a0;

    /* JADX INFO: renamed from: b0, reason: collision with root package name */
    public final Path f95545b0;

    /* JADX INFO: renamed from: c0, reason: collision with root package name */
    public final Paint f95546c0;

    /* JADX INFO: renamed from: d0, reason: collision with root package name */
    public final PointF f95547d0;

    /* JADX INFO: renamed from: e0, reason: collision with root package name */
    public final PointF f95548e0;

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final String f95549l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public C2702d f95550m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public y1 f95551n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public AbstractC2759w0 f95552o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public N0 f95553p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public Path f95554q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public Paint f95555r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public Path f95556s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public Paint f95557t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public Paint f95558u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public final Rect f95559v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public Paint f95560w;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public Paint f95561x;

    /* JADX INFO: renamed from: y, reason: collision with root package name */
    public Path f95562y;

    /* JADX INFO: renamed from: z, reason: collision with root package name */
    public Paint f95563z;

    /* JADX INFO: renamed from: fk.u$a */
    public static final class a {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public final float f95564a;

        /* JADX INFO: renamed from: b, reason: collision with root package name */
        public final float f95565b;

        /* JADX INFO: renamed from: c, reason: collision with root package name */
        public final float f95566c;

        /* JADX INFO: renamed from: d, reason: collision with root package name */
        public final float f95567d;

        /* JADX INFO: renamed from: e, reason: collision with root package name */
        public final float f95568e;

        /* JADX INFO: renamed from: f, reason: collision with root package name */
        public final float f95569f;

        /* JADX INFO: renamed from: g, reason: collision with root package name */
        public final boolean f95570g;

        /* JADX INFO: renamed from: h, reason: collision with root package name */
        public final int f95571h;

        public a(float f10, float f11, float f12, float f13, float f14, float f15, boolean z10, int i10) {
            this.f95564a = f10;
            this.f95565b = f11;
            this.f95566c = f12;
            this.f95567d = f13;
            this.f95568e = f14;
            this.f95569f = f15;
            this.f95570g = z10;
            this.f95571h = i10;
        }

        public final float a() {
            return this.f95564a;
        }

        public final float b() {
            return this.f95565b;
        }

        public final float c() {
            return this.f95566c;
        }

        public final float d() {
            return this.f95567d;
        }

        public final float e() {
            return this.f95568e;
        }

        public boolean equals(Object obj) {
            if (this == obj) {
                return true;
            }
            if (!(obj instanceof a)) {
                return false;
            }
            a aVar = (a) obj;
            return Float.compare(this.f95564a, aVar.f95564a) == 0 && Float.compare(this.f95565b, aVar.f95565b) == 0 && Float.compare(this.f95566c, aVar.f95566c) == 0 && Float.compare(this.f95567d, aVar.f95567d) == 0 && Float.compare(this.f95568e, aVar.f95568e) == 0 && Float.compare(this.f95569f, aVar.f95569f) == 0 && this.f95570g == aVar.f95570g && this.f95571h == aVar.f95571h;
        }

        public final float f() {
            return this.f95569f;
        }

        public final boolean g() {
            return this.f95570g;
        }

        public final int h() {
            return this.f95571h;
        }

        public int hashCode() {
            return Integer.hashCode(this.f95571h) + ((Boolean.hashCode(this.f95570g) + kk.a.a(this.f95569f, kk.a.a(this.f95568e, kk.a.a(this.f95567d, kk.a.a(this.f95566c, kk.a.a(this.f95565b, Float.hashCode(this.f95564a) * 31, 31), 31), 31), 31), 31)) * 31);
        }

        public String toString() {
            return "FillSegment(startX=" + this.f95564a + ", startY1=" + this.f95565b + ", startY2=" + this.f95566c + ", endX=" + this.f95567d + ", endY1=" + this.f95568e + ", endY2=" + this.f95569f + ", isFirstLineOnTop=" + this.f95570g + ", color=" + this.f95571h + ')';
        }
    }

    public C7395u(C2732n c2732n, String str, String str2) {
        super(c2732n, str);
        this.f95549l = str2;
        this.f95559v = new Rect();
        this.f95560w = new Paint();
        this.f95561x = new Paint();
        this.f95518A = new Paint();
        new Paint();
        this.f95519B = new Path();
        this.f95520C = new Path();
        this.f95521D = 15.0f;
        this.f95522E = 16.0f;
        this.f95523F = 15.0f;
        this.f95524G = 8.0f;
        this.f95525H = 8.0f;
        this.f95527J = -16711936;
        this.f95528K = -65536;
        this.f95537T = new Paint();
        this.f95538U = new Paint();
        this.f95539V = new Paint();
        this.f95540W = new Paint();
        this.f95541X = new Paint();
        this.f95542Y = new Paint();
        this.f95543Z = new Path();
        this.f95544a0 = XGPushManager.MAX_TAG_SIZE;
        this.f95545b0 = new Path();
        this.f95546c0 = new Paint();
        this.f95547d0 = new PointF();
        this.f95548e0 = new PointF();
    }

    public final void A(Canvas canvas, float f10, float f11, float f12, ScriptIndicAction scriptIndicAction, AbstractC2759w0 abstractC2759w0, int i10, int i11, Map map) {
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
        int i14 = (1 > intShowLast || intShowLast >= (i12 = this.f95544a0)) ? -1 : i12 - intShowLast;
        try {
            y1 y1Var = this.f95551n;
            jH = y1Var != null ? y1Var.H(i14) : 0L;
        } catch (Exception unused) {
        }
        while (i13 < iAbs) {
            y1 y1Var2 = this.f95551n;
            Map map2 = (Map) map.get(String.valueOf(y1Var2 != null ? Long.valueOf(y1Var2.H(i13)) : null));
            if (map2 == null) {
                f13 = f17;
            } else {
                String str4 = (String) map2.get("time");
                long jLongValue = (str4 == null || (lR = Ah.w.r(str4)) == null) ? 0L : lR.longValue();
                String open = scriptIndicAction.getOpen();
                if (open == null) {
                    open = "";
                }
                String str5 = (String) map2.get(open);
                double dDoubleValue = 0.0d;
                double dDoubleValue2 = (str5 == null || (dN4 = Ah.v.n(str5)) == null) ? 0.0d : dN4.doubleValue();
                this.f95534Q = dDoubleValue2;
                this.f95530M = abstractC2759w0.P(dDoubleValue2);
                String high = scriptIndicAction.getHigh();
                if (high == null) {
                    high = "";
                }
                String str6 = (String) map2.get(high);
                double dDoubleValue3 = (str6 == null || (dN3 = Ah.v.n(str6)) == null) ? 0.0d : dN3.doubleValue();
                this.f95533P = dDoubleValue3;
                this.f95529L = abstractC2759w0.P(dDoubleValue3);
                String low = scriptIndicAction.getLow();
                if (low == null) {
                    low = "";
                }
                String str7 = (String) map2.get(low);
                double dDoubleValue4 = (str7 == null || (dN2 = Ah.v.n(str7)) == null) ? 0.0d : dN2.doubleValue();
                this.f95535R = dDoubleValue4;
                this.f95531N = abstractC2759w0.P(dDoubleValue4);
                String close = scriptIndicAction.getClose();
                if (close == null) {
                    close = "";
                }
                String str8 = (String) map2.get(close);
                if (str8 != null && (dN = Ah.v.n(str8)) != null) {
                    dDoubleValue = dN.doubleValue();
                }
                double d10 = dDoubleValue;
                this.f95536S = d10;
                this.f95532O = abstractC2759w0.P(d10);
                String strA = kk.f.a(scriptIndicAction, new StringBuilder(), "Value");
                float fAbs = (Math.abs(f16 - f15) / f17) + f15;
                if (i14 <= 0 || jLongValue >= jH) {
                    float f19 = f16;
                    f13 = f17;
                    double d11 = this.f95536S;
                    double d12 = this.f95534Q;
                    if (d11 > d12) {
                        this.f95539V.setStrokeWidth(3.0f);
                        Paint paint = this.f95539V;
                        int iIntValue = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str3 = (String) map2.get(strA)) == null || (numP3 = Ah.w.p(str3)) == null) ? this.f95527J : numP3.intValue();
                        paint.setColor(iIntValue);
                        canvas.drawLine(fAbs, this.f95529L, fAbs, this.f95531N, this.f95539V);
                        float f20 = this.f95530M;
                        canvas.drawLine(f15, f20, fAbs, f20, this.f95539V);
                        float f21 = this.f95532O;
                        f14 = f19;
                        canvas.drawLine(fAbs, f21, f14, f21, this.f95539V);
                    } else if (d11 == d12) {
                        this.f95542Y.setStrokeWidth(2.0f);
                        Paint paint2 = this.f95542Y;
                        int iIntValue2 = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str2 = (String) map2.get(strA)) == null || (numP2 = Ah.w.p(str2)) == null) ? this.f95527J : numP2.intValue();
                        paint2.setColor(iIntValue2);
                        canvas.drawLine(fAbs, this.f95529L, fAbs, this.f95531N, this.f95542Y);
                        float f22 = this.f95530M;
                        canvas.drawLine(f15, f22, fAbs, f22, this.f95542Y);
                        float f23 = this.f95532O;
                        f14 = f19;
                        canvas.drawLine(fAbs, f23, f14, f23, this.f95542Y);
                    } else {
                        this.f95541X.setStrokeWidth(3.0f);
                        Paint paint3 = this.f95541X;
                        int iIntValue3 = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str = (String) map2.get(strA)) == null || (numP = Ah.w.p(str)) == null) ? this.f95528K : numP.intValue();
                        paint3.setColor(iIntValue3);
                        canvas.drawLine(fAbs, this.f95529L, fAbs, this.f95531N, this.f95541X);
                        float f24 = this.f95530M;
                        canvas.drawLine(f15, f24, fAbs, f24, this.f95541X);
                        float f25 = this.f95532O;
                        f14 = f19;
                        canvas.drawLine(fAbs, f25, f14, f25, this.f95541X);
                    }
                } else {
                    f14 = f16;
                    f13 = f17;
                }
                f15 += f11;
                f16 = f14 + f11;
            }
            i13++;
            f17 = f13;
        }
    }

    public final void B(Canvas canvas, float f10, float f11, ScriptIndicAction scriptIndicAction, AbstractC2759w0 abstractC2759w0, int i10, int i11, sp.aicoin_kline.core.indicator.config.F f12, Map map) {
        float[] fArr;
        long jH;
        Paint paint;
        Paint paint2;
        boolean z10;
        Map map2;
        int iA;
        String str;
        Integer numP;
        float f13;
        Long lR;
        Double dN;
        int i12;
        Float fO;
        Float fO2;
        AbstractC2759w0 abstractC2759w1 = abstractC2759w0;
        Path path = this.f95554q;
        if (path != null) {
            path.reset();
        }
        Path path2 = this.f95556s;
        if (path2 != null) {
            path2.reset();
        }
        int intOffset = scriptIndicAction.getIntOffset();
        int i13 = intOffset > 0 ? i10 - intOffset : i10;
        int iAbs = intOffset < 0 ? Math.abs(intOffset) + i11 : i11;
        float f14 = intOffset < 0 ? (intOffset * f11) + f10 : f10;
        float fFloatValue = ((Number) p162hb.e.c(o(), Float.valueOf(abstractC2759w1.P(abstractC2759w1.v())), Float.valueOf(abstractC2759w1.P(abstractC2759w1.u())))).floatValue();
        float floatLineWidth = scriptIndicAction.getOutput().getFloatLineWidth();
        Paint paint3 = this.f95555r;
        if (paint3 != null) {
            paint3.setStrokeWidth(floatLineWidth);
        }
        Paint paint4 = this.f95557t;
        if (paint4 != null) {
            paint4.setStrokeWidth(floatLineWidth);
        }
        List<String> lineDash = scriptIndicAction.getOutput().getLineDash();
        boolean z11 = true;
        float f15 = 0.0f;
        if (lineDash != null) {
            String str2 = (String) Sf.z.q0(lineDash);
            float fFloatValue2 = (str2 == null || (fO2 = Ah.v.o(str2)) == null) ? 0.0f : fO2.floatValue();
            String str3 = (String) Sf.z.D0(lineDash);
            fArr = new float[]{fFloatValue2, (str3 == null || (fO = Ah.v.o(str3)) == null) ? 0.0f : fO.floatValue()};
        } else {
            fArr = new float[]{0.0f, 0.0f};
        }
        Paint paint5 = this.f95555r;
        if (paint5 != null) {
            paint5.setPathEffect(new DashPathEffect(fArr, 0.0f));
        }
        Paint paint6 = this.f95557t;
        if (paint6 != null) {
            paint6.setPathEffect(new DashPathEffect(fArr, 0.0f));
        }
        int intShowLast = scriptIndicAction.getIntShowLast();
        int i14 = (1 > intShowLast || intShowLast >= (i12 = this.f95544a0)) ? -1 : i12 - intShowLast;
        try {
            y1 y1Var = this.f95551n;
            jH = y1Var != null ? y1Var.H(i14) : 0L;
        } catch (Exception unused) {
        }
        Qf.p pVar = new Qf.p(Integer.valueOf(i14), Long.valueOf(jH));
        int iIntValue = ((Number) pVar.a()).intValue();
        long jLongValue = ((Number) pVar.b()).longValue();
        StringBuilder sb2 = new StringBuilder();
        ActionOutput output = scriptIndicAction.getOutput();
        sb2.append(output != null ? output.getColor() : null);
        sb2.append("Value");
        String string = sb2.toString();
        int i15 = -13643086;
        float f16 = f14;
        float f17 = 0.0f;
        boolean z12 = true;
        while (i13 < iAbs) {
            y1 y1Var2 = this.f95551n;
            if (y1Var2 == null || (map2 = (Map) map.get(String.valueOf(y1Var2.H(i13)))) == null) {
                z12 = z12;
                i13 = i13;
                z10 = z11;
            } else {
                String series = scriptIndicAction.getSeries();
                if (series == null) {
                    series = "0";
                }
                String str4 = (String) map2.get(series);
                double dDoubleValue = (str4 == null || (dN = Ah.v.n(str4)) == null) ? 0.0d : dN.doubleValue();
                if (dDoubleValue == 0.0d) {
                    f16 += f11;
                    z10 = z11;
                    z12 = z10;
                } else {
                    z10 = z11;
                    String str5 = (String) map2.get("time");
                    long jLongValue2 = (str5 == null || (lR = Ah.w.r(str5)) == null) ? 0L : lR.longValue();
                    if (iIntValue <= 0 || jLongValue2 >= jLongValue) {
                        float fQ = o() ? abstractC2759w1.Q(dDoubleValue, o()) : abstractC2759w1.P(dDoubleValue);
                        ek.m[] mVarArrU = f12.u();
                        if (mVarArrU.length == 0) {
                            iA = -7829368;
                        } else {
                            int length = this.f95526I;
                            if (length >= mVarArrU.length) {
                                length = mVarArrU.length - 1;
                            } else if (length < 0) {
                                length = 0;
                            }
                            iA = (string == null || string.length() == 0 || AbstractC7609s.f(string, "nullValue") || (str = (String) map2.get(string)) == null || (numP = Ah.w.p(str)) == null) ? mVarArrU[length].a() : numP.intValue();
                        }
                        if (z12 != 0) {
                            Paint paint7 = this.f95555r;
                            if (paint7 != null) {
                                paint7.setColor(iA);
                            }
                            Path path3 = this.f95554q;
                            if (path3 != null) {
                                path3.moveTo(f16, fQ);
                            }
                            f13 = fQ;
                            z12 = false;
                        } else {
                            if (iA != i15) {
                                Paint paint8 = this.f95557t;
                                if (paint8 != null) {
                                    paint8.setColor(iA);
                                }
                                Path path4 = this.f95556s;
                                if (path4 != null) {
                                    path4.moveTo(f15, f17);
                                    path4.lineTo(f16, fQ);
                                }
                            } else {
                                Paint paint9 = this.f95555r;
                                if (paint9 != null) {
                                    paint9.setColor(iA);
                                }
                                Path path5 = this.f95554q;
                                if (path5 != null) {
                                    f13 = fQ;
                                    hk.a.f98027a.d(f15, f17, f16, f13, fFloatValue, path5);
                                }
                                z12 = z12;
                                i15 = iA;
                            }
                            f13 = fQ;
                            z12 = z12;
                            i15 = iA;
                        }
                        f15 = f16;
                        f17 = f13;
                        f16 += f11;
                    } else {
                        f16 += f11;
                    }
                }
                i13++;
                abstractC2759w1 = abstractC2759w0;
                z11 = z10;
            }
            z12 = z12;
            i13++;
            abstractC2759w1 = abstractC2759w0;
            z11 = z10;
        }
        Path path6 = this.f95554q;
        if (path6 != null && (paint2 = this.f95555r) != null) {
            canvas.drawPath(path6, paint2);
        }
        Path path7 = this.f95556s;
        if (path7 == null || (paint = this.f95557t) == null) {
            return;
        }
        canvas.drawPath(path7, paint);
    }

    public final void C(Canvas canvas, ScriptIndicAction scriptIndicAction, AbstractC2759w0 abstractC2759w0, sp.aicoin_kline.core.indicator.config.F f10, Map map) {
        Map linkedHashMap;
        String str;
        Integer numP;
        String str2;
        Integer numP2;
        Double dN;
        Long lR;
        y1 y1Var = this.f95551n;
        long jLongValue = 0;
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
        String str3 = (String) kk.g.a(scriptIndicAction, new StringBuilder(), "AfterTransTime1", linkedHashMap);
        if (str3 != null && (lR = Ah.w.r(str3)) != null) {
            jLongValue = lR.longValue();
        }
        String str4 = (String) kk.g.a(scriptIndicAction, new StringBuilder(), "AfterTransValue1", linkedHashMap);
        double dDoubleValue = (str4 == null || (dN = Ah.v.n(str4)) == null) ? 0.0d : dN.doubleValue();
        String strA = kk.f.a(scriptIndicAction, new StringBuilder(), "Value");
        float fP = abstractC2759w0.P(dDoubleValue);
        int iA = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str2 = (String) linkedHashMap.get(strA)) == null || (numP2 = Ah.w.p(str2)) == null) ? f10.u()[this.f95526I].a() : numP2.intValue();
        String fontSize = scriptIndicAction.getOutput().getFontSize();
        if (fontSize != null && fontSize.length() != 0) {
            float floatFontSize = scriptIndicAction.getOutput().getFloatFontSize();
            Paint paint = this.f95558u;
            if (paint != null) {
                paint.setTextSize(Xj.a.c(floatFontSize));
            }
        }
        if (this.f95558u != null) {
            C2702d c2702d = this.f95550m;
            int iU = c2702d != null ? c2702d.u() : 0;
            y1 y1Var2 = this.f95551n;
            float fW = iU + (y1Var2 != null ? y1Var2.w() : 0.0f);
            y1 y1Var3 = this.f95551n;
            float fJ = (y1Var3 != null ? y1Var3.j(jLongValue * ((long) 1000)) : 0.0f) - fW;
            String bgColor = scriptIndicAction.getOutput().getBgColor();
            if (bgColor != null && bgColor.length() != 0) {
                String str5 = scriptIndicAction.getOutput().getBgColor() + "BGValue";
                Paint paint2 = this.f95558u;
                if (paint2 != null) {
                    int iA2 = (str5 == null || str5.length() == 0 || (str = (String) linkedHashMap.get(str5)) == null || (numP = Ah.w.p(str)) == null) ? f10.u()[this.f95526I].a() : numP.intValue();
                    paint2.setColor(iA2);
                }
                this.f95558u.getTextBounds(scriptIndicAction.getOutput().getText(), 0, scriptIndicAction.getOutput().getText().length(), this.f95559v);
                float fWidth = this.f95559v.width() / 2;
                canvas.drawRoundRect((fJ - Xj.a.a(4.0f)) - fWidth, fP - (this.f95559v.height() + 10), (Xj.a.a(6.0f) + (this.f95559v.width() + fJ)) - fWidth, (this.f95559v.height() / 3) + fP + 4.0f, 6.0f, 6.0f, this.f95558u);
            }
            int iWidth = this.f95559v.width() / 2;
            Paint paint3 = this.f95558u;
            if (paint3 != null) {
                paint3.setColor(iA);
            }
            canvas.drawText(scriptIndicAction.getOutput().getText(), fJ - iWidth, fP, this.f95558u);
        }
    }

    /* JADX WARN: Code duplicated, block: B:60:0x00ee  */
    /* JADX WARN: Code duplicated, block: B:73:0x0111  */
    public final void D(Canvas canvas, float f10, float f11, ScriptIndicAction scriptIndicAction, AbstractC2759w0 abstractC2759w0, int i10, int i11, sp.aicoin_kline.core.indicator.config.F f12, Map map) {
        boolean z10;
        int i12;
        int i13;
        float f13;
        String str;
        Integer numP;
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
        String strA = kk.f.a(scriptIndicAction, new StringBuilder(), "Value");
        int intShowLast = scriptIndicAction.getIntShowLast();
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
                int i17 = i15 - intOffset;
                Map map2 = (Map) ((Qf.p) obj).d();
                String series = scriptIndicAction.getSeries();
                String str5 = (String) map2.get(series == null ? "0" : series);
                boolean z11 = ((str5 == null || (dN3 = Ah.v.n(str5)) == null) ? 0.0d : dN3.doubleValue()) > 0.0d;
                if (i17 >= 0 && i17 < listB.size() && z11) {
                    arrayList.add(listB.get(i17));
                }
                i15 = i16;
            }
        }
        Map mapZ = intOffset != 0 ? Sf.N.z(Sf.N.v(arrayList)) : map;
        nk.x.f134260a.d(mapZ);
        int i18 = (intShowLast <= 0 || intShowLast >= mapZ.size()) ? 0 : (this.f95544a0 - intShowLast) + intOffset;
        while (i10 < i11) {
            y1 y1Var = this.f95551n;
            Map linkedHashMap = (Map) mapZ.get(String.valueOf(y1Var != null ? Long.valueOf(y1Var.H(i10)) : null));
            if (linkedHashMap == null) {
                linkedHashMap = new LinkedHashMap();
            }
            if (intOffset == 0) {
                Object series2 = scriptIndicAction.getSeries();
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
            Object refSeries = scriptIndicAction.getRefSeries();
            if (refSeries == null) {
                refSeries = "";
            }
            String str7 = (String) linkedHashMap.get(refSeries);
            double dDoubleValue = (str7 == null || (dN = Ah.v.n(str7)) == null) ? d10 : dN.doubleValue();
            if (dDoubleValue != d10 && z10 && i10 >= i18) {
                float fP = abstractC2759w0.P(dDoubleValue);
                int iA = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str4 = (String) linkedHashMap.get(strA)) == null || (numP4 = Ah.w.p(str4)) == null) ? f12.u()[this.f95526I].a() : numP4.intValue();
                String fontSize = scriptIndicAction.getOutput().getFontSize();
                if (fontSize != null && fontSize.length() != 0) {
                    float floatFontSize = scriptIndicAction.getOutput().getFloatFontSize();
                    Paint paint = this.f95558u;
                    if (paint != null) {
                        paint.setTextSize(Xj.a.c(floatFontSize));
                    }
                }
                if (!AbstractC7609s.f(scriptIndicAction.getOutput().getPlacement(), "bottom")) {
                    i12 = i10;
                    i13 = i18;
                    intOffset = intOffset;
                    int i19 = iA;
                    if (AbstractC7609s.f(scriptIndicAction.getOutput().getPlacement(), "center")) {
                        if (this.f95558u != null) {
                            float fA = f10 - Xj.a.a(10.0f);
                            String bgColor = scriptIndicAction.getOutput().getBgColor();
                            if (bgColor == null || bgColor.length() == 0) {
                                f14 = fA;
                            } else {
                                String str8 = scriptIndicAction.getOutput().getBgColor() + "BGValue";
                                Paint paint2 = this.f95558u;
                                if (paint2 != null) {
                                    int iA2 = (str8 == null || str8.length() == 0 || (str2 = (String) linkedHashMap.get(str8)) == null || (numP2 = Ah.w.p(str2)) == null) ? f12.u()[this.f95526I].a() : numP2.intValue();
                                    paint2.setColor(iA2);
                                }
                                this.f95558u.getTextBounds(scriptIndicAction.getOutput().getText(), 0, scriptIndicAction.getOutput().getText().length(), this.f95559v);
                                f14 = fA;
                                canvas.drawRoundRect(fA - Xj.a.a(3.0f), fP - this.f95559v.height(), Xj.a.a(3.0f) + this.f95559v.width() + fA, fP + (this.f95559v.height() / 2) + Xj.a.a(1.0f), Xj.a.a(3.0f), Xj.a.a(3.0f), this.f95558u);
                            }
                            Paint paint3 = this.f95558u;
                            if (paint3 != null) {
                                paint3.setColor(i19);
                            }
                            canvas.drawText(scriptIndicAction.getOutput().getText(), f14, Xj.a.a(2.0f) + fP, this.f95558u);
                        }
                    } else if (this.f95558u != null) {
                        float fA2 = f10 - Xj.a.a(10.0f);
                        float f16 = fP - 10.0f;
                        String bgColor2 = scriptIndicAction.getOutput().getBgColor();
                        if (bgColor2 == null || bgColor2.length() == 0) {
                            f13 = fA2;
                        } else {
                            String str9 = scriptIndicAction.getOutput().getBgColor() + "BGValue";
                            Paint paint4 = this.f95558u;
                            if (paint4 != null) {
                                int iA3 = (str9 == null || str9.length() == 0 || (str = (String) linkedHashMap.get(str9)) == null || (numP = Ah.w.p(str)) == null) ? f12.u()[this.f95526I].a() : numP.intValue();
                                paint4.setColor(iA3);
                            }
                            this.f95558u.getTextBounds(scriptIndicAction.getOutput().getText(), 0, scriptIndicAction.getOutput().getText().length(), this.f95559v);
                            f13 = fA2;
                            canvas.drawRoundRect((fA2 - Xj.a.a(3.0f)) + 4.5f, (f16 - this.f95559v.height()) - Xj.a.a(2.5f), Xj.a.a(3.0f) + this.f95559v.width() + fA2, f16 + (this.f95559v.height() / 2), Xj.a.a(3.0f), Xj.a.a(3.0f), this.f95558u);
                        }
                        Paint paint5 = this.f95558u;
                        if (paint5 != null) {
                            paint5.setColor(i19);
                        }
                        canvas.drawText(scriptIndicAction.getOutput().getText(), f13, f16, this.f95558u);
                    }
                } else if (this.f95558u != null) {
                    float fA3 = f10 - Xj.a.a(10.0f);
                    float f17 = fP + 20.0f;
                    String bgColor3 = scriptIndicAction.getOutput().getBgColor();
                    if (bgColor3 == null || bgColor3.length() == 0) {
                        i12 = i10;
                        i13 = i18;
                        f15 = fA3;
                        canvas2 = canvas;
                        i14 = iA;
                    } else {
                        StringBuilder sb2 = new StringBuilder();
                        int i20 = i10;
                        sb2.append(scriptIndicAction.getOutput().getBgColor());
                        sb2.append("BGValue");
                        String string = sb2.toString();
                        Paint paint6 = this.f95558u;
                        if (paint6 != null) {
                            int iA4 = (string == null || string.length() == 0 || AbstractC7609s.f(string, "nullBGValue") || (str3 = (String) linkedHashMap.get(string)) == null || (numP3 = Ah.w.p(str3)) == null) ? f12.u()[this.f95526I].a() : numP3.intValue();
                            paint6.setColor(iA4);
                        }
                        this.f95558u.getTextBounds(scriptIndicAction.getOutput().getText(), 0, scriptIndicAction.getOutput().getText().length(), this.f95559v);
                        i12 = i20;
                        i13 = i18;
                        i14 = iA;
                        f15 = fA3;
                        canvas2 = canvas;
                        canvas2.drawRoundRect(fA3 - Xj.a.a(3.0f), (f17 - this.f95559v.height()) - Xj.a.a(2.0f), Xj.a.a(3.0f) + this.f95559v.width() + fA3, (this.f95559v.height() / 2) + f17, Xj.a.a(3.0f), Xj.a.a(3.0f), this.f95558u);
                    }
                    Paint paint7 = this.f95558u;
                    if (paint7 != null) {
                        paint7.setColor(i14);
                    }
                    canvas2.drawText(scriptIndicAction.getOutput().getText(), f15, f17, this.f95558u);
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
            i11 = i11;
            i10 = i12 + 1;
            i18 = i13;
            intOffset = intOffset;
            d10 = 0.0d;
        }
    }

    public final void E(Canvas canvas, ScriptIndicAction scriptIndicAction, AbstractC2759w0 abstractC2759w0, sp.aicoin_kline.core.indicator.config.F f10, Map map) {
        String str;
        Map linkedHashMap;
        Path path;
        String str2;
        Integer numP;
        Double dN;
        Double dN2;
        Long lR;
        Long lR2;
        String str3;
        Path path2 = this.f95554q;
        if (path2 != null) {
            path2.reset();
        }
        Path path3 = this.f95556s;
        if (path3 != null) {
            path3.reset();
        }
        float fFloatValue = ((Number) p162hb.e.c(o(), Float.valueOf(abstractC2759w0.P(abstractC2759w0.v())), Float.valueOf(abstractC2759w0.P(abstractC2759w0.u())))).floatValue();
        float fFloatValue2 = ((Number) p162hb.e.c(o(), Float.valueOf(abstractC2759w0.P(abstractC2759w0.u())), Float.valueOf(abstractC2759w0.P(abstractC2759w0.v())))).floatValue();
        String strA = kk.f.a(scriptIndicAction, new StringBuilder(), "Value");
        if (scriptIndicAction.getOutput().getLineWidth() != null) {
            Paint paint = this.f95555r;
            if (paint != null) {
                paint.setStrokeWidth(scriptIndicAction.getOutput().getFloatLineWidth());
            }
            Paint paint2 = this.f95557t;
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
        Paint paint3 = this.f95555r;
        if (paint3 != null) {
            paint3.setPathEffect(new DashPathEffect(new float[]{fFloatValue3, fFloatValue4}, 0.0f));
        }
        Paint paint4 = this.f95557t;
        if (paint4 != null) {
            paint4.setPathEffect(new DashPathEffect(new float[]{fFloatValue3, fFloatValue4}, 0.0f));
        }
        y1 y1Var = this.f95551n;
        long jLongValue = 0;
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
        String str5 = (String) kk.g.a(scriptIndicAction, new StringBuilder(), "AfterTransTime1", linkedHashMap);
        long jLongValue2 = (str5 == null || (lR2 = Ah.w.r(str5)) == null) ? 0L : lR2.longValue();
        String str6 = (String) kk.g.a(scriptIndicAction, new StringBuilder(), "AfterTransTime2", linkedHashMap);
        if (str6 != null && (lR = Ah.w.r(str6)) != null) {
            jLongValue = lR.longValue();
        }
        String str7 = (String) kk.g.a(scriptIndicAction, new StringBuilder(), "AfterTransValue1", linkedHashMap);
        double dDoubleValue = 0.0d;
        double dDoubleValue2 = (str7 == null || (dN2 = Ah.v.n(str7)) == null) ? 0.0d : dN2.doubleValue();
        String str8 = (String) kk.g.a(scriptIndicAction, new StringBuilder(), "AfterTransValue2", linkedHashMap);
        if (str8 != null && (dN = Ah.v.n(str8)) != null) {
            dDoubleValue = dN.doubleValue();
        }
        float fS = abstractC2759w0.S(dDoubleValue2);
        float fS2 = abstractC2759w0.S(dDoubleValue);
        PointF pointF = this.f95547d0;
        y1 y1Var2 = this.f95551n;
        pointF.x = y1Var2 != null ? y1Var2.j(jLongValue2 * ((long) 1000)) : 0.0f;
        this.f95547d0.y = fS;
        PointF pointF2 = this.f95548e0;
        y1 y1Var3 = this.f95551n;
        pointF2.x = y1Var3 != null ? y1Var3.j(jLongValue * ((long) 1000)) : 0.0f;
        this.f95548e0.y = fS2;
        int iA = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str2 = (String) linkedHashMap.get(strA)) == null || (numP = Ah.w.p(str2)) == null) ? f10.u()[this.f95526I].a() : numP.intValue();
        hk.a aVar = hk.a.f98027a;
        PointF pointF3 = this.f95547d0;
        float f11 = pointF3.x;
        PointF pointF4 = this.f95548e0;
        aVar.c(f11, pointF4.x, pointF3.y, pointF4.y);
        aVar.a(this.f95547d0, fFloatValue2, fFloatValue);
        Paint paint5 = this.f95555r;
        if (paint5 != null) {
            paint5.setColor(iA);
        }
        C2702d c2702d = this.f95550m;
        int iU = c2702d != null ? c2702d.u() : 0;
        y1 y1Var4 = this.f95551n;
        float fW = iU + (y1Var4 != null ? y1Var4.w() : 0.0f);
        PointF pointF5 = this.f95547d0;
        float f12 = pointF5.x - fW;
        float f13 = pointF5.y;
        PointF pointF6 = this.f95548e0;
        float f14 = pointF6.x - fW;
        float f15 = pointF6.y;
        Path path4 = this.f95554q;
        if (path4 != null) {
            path4.moveTo(f12, f13);
        }
        Path path5 = this.f95554q;
        if (path5 != null) {
            path5.lineTo(f14, f15);
        }
        Paint paint6 = this.f95555r;
        if (paint6 == null || (path = this.f95554q) == null) {
            return;
        }
        canvas.drawPath(path, paint6);
    }

    /* JADX WARN: Code duplicated, block: B:101:0x01fe  */
    /* JADX WARN: Failed to restore switch over string. Please report as a decompilation issue */
    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        N0 n10;
        y1 y1Var;
        C2765z c2765zH;
        List<ScriptIndicAction> action;
        ScriptIndicAction scriptIndicAction;
        sp.aicoin_kline.core.indicator.config.F f10;
        float f11;
        ScriptIndicAction scriptIndicAction2;
        Double dN;
        int i10;
        AbstractC2759w0 abstractC2759w0;
        ScriptIndicAction scriptIndicAction3;
        C7395u c7395u;
        Double dN2;
        int iAbs;
        long jH;
        int iA;
        float f12;
        int i11;
        int i12;
        float f13;
        String str;
        float f14;
        Double dN3;
        Integer numP;
        Double dN4;
        Long lR;
        int i13;
        Double dN5;
        int i14;
        AbstractC2759w0 abstractC2759w1;
        ScriptIndicAction scriptIndicAction4;
        AbstractC2759w0 abstractC2759w2;
        ScriptIndicAction scriptIndicAction5;
        sp.aicoin_kline.core.indicator.config.F f15;
        boolean z10;
        int i15;
        String str2;
        String str3;
        Integer numP2;
        Double dN6;
        Double dN7;
        Double dN8;
        this = this;
        canvas = canvas;
        AbstractC2759w0 abstractC2759w3 = this.f95552o;
        if (abstractC2759w3 == null || (n10 = this.f95553p) == null || (y1Var = this.f95551n) == null || (c2765zH = this.i().b().h(this.c())) == null) {
            return;
        }
        this.f95544a0 = c2765zH.D();
        sp.aicoin_kline.core.indicator.config.F fX = n10.x();
        int iR = y1Var.r();
        int iQ = y1Var.q();
        this.f95526I = 0;
        float fU = y1Var.u();
        float fJ = y1Var.J();
        float f16 = 2;
        float f17 = (fU / f16) - fJ;
        float f18 = (f16 * fU) / 3;
        int iY = y1Var.y();
        canvas.save();
        ScriptDrawData scriptDrawData = (ScriptDrawData) n10.F().get(this.f95549l);
        if (scriptDrawData == null) {
            return;
        }
        Map<String, Map<String, String>> calculateHistoryData = scriptDrawData.getCalculateHistoryData();
        if (calculateHistoryData.isEmpty()) {
            return;
        }
        Map.Entry entry = (Map.Entry) Sf.z.p0(calculateHistoryData.entrySet());
        Map map = entry != null ? (Map) entry.getValue() : null;
        ScriptIndicConfig config = scriptDrawData.getConfig();
        if (config == null || (action = config.getAction()) == null || action.isEmpty()) {
            return;
        }
        for (ScriptIndicAction scriptIndicAction6 : config.getAction()) {
            String action2 = scriptIndicAction6.getAction();
            Map map2 = map;
            fJ = fJ;
            f17 = f17;
            switch (action2.hashCode()) {
                case -2020374621:
                    scriptIndicAction = scriptIndicAction6;
                    calculateHistoryData = calculateHistoryData;
                    f10 = fX;
                    f11 = fU;
                    f18 = f18;
                    iY = iY;
                    map = map2;
                    iQ = iQ;
                    if (action2.equals("plotHist") && !AbstractC7609s.f(scriptIndicAction.getDisplay(), Boolean.FALSE)) {
                        this = this;
                        int i16 = iR;
                        scriptIndicAction2 = scriptIndicAction;
                        fU = f11;
                        AbstractC2759w0 abstractC2759w4 = abstractC2759w3;
                        this.w(canvas, f18, fU, fJ, scriptIndicAction2, abstractC2759w4, i16, iY, f10, Sf.N.z(calculateHistoryData));
                        abstractC2759w3 = abstractC2759w4;
                        iR = i16;
                        fX = f10;
                    } else {
                        scriptIndicAction2 = scriptIndicAction;
                        fX = f10;
                        fU = f11;
                    }
                    break;
                case -2020167279:
                    calculateHistoryData = calculateHistoryData;
                    f10 = fX;
                    f18 = f18;
                    int i17 = iY;
                    map = map2;
                    scriptIndicAction2 = scriptIndicAction6;
                    iQ = iQ;
                    fU = fU;
                    if (action2.equals("plotOhlc") && !AbstractC7609s.f(scriptIndicAction2.getDisplay(), Boolean.FALSE)) {
                        int i18 = iR;
                        iY = i17;
                        AbstractC2759w0 abstractC2759w5 = abstractC2759w3;
                        A(canvas, f18, fU, fJ, scriptIndicAction2, abstractC2759w5, i18, iY, Sf.N.z(calculateHistoryData));
                        f11 = fU;
                        scriptIndicAction = scriptIndicAction2;
                        abstractC2759w3 = abstractC2759w5;
                        iR = i18;
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
                                y(canvas, abstractC2759w3, dDoubleValue, str5 == null ? "" : str5);
                            }
                        }
                        scriptIndicAction2 = scriptIndicAction;
                        fX = f10;
                        fU = f11;
                    } else {
                        this = this;
                        iY = i17;
                        fX = f10;
                    }
                    break;
                case -2020020818:
                    calculateHistoryData = calculateHistoryData;
                    fX = fX;
                    f11 = fU;
                    f18 = f18;
                    i10 = iY;
                    map = map2;
                    scriptIndicAction2 = scriptIndicAction6;
                    iQ = iQ;
                    if (action2.equals("plotText") && !AbstractC7609s.f(scriptIndicAction2.getDisplay(), Boolean.FALSE)) {
                        this = this;
                        fU = f11;
                        AbstractC2759w0 abstractC2759w6 = abstractC2759w3;
                        this.D(canvas, f17, fU, scriptIndicAction2, abstractC2759w6, iR, iQ, fX, Sf.N.z(calculateHistoryData));
                        abstractC2759w3 = abstractC2759w6;
                        scriptIndicAction2 = scriptIndicAction2;
                        fX = fX;
                        iY = i10;
                    } else {
                        this = this;
                        iY = i10;
                        fU = f11;
                    }
                    break;
                case -608864346:
                    scriptIndicAction = scriptIndicAction6;
                    calculateHistoryData = calculateHistoryData;
                    f10 = fX;
                    f11 = fU;
                    f18 = f18;
                    i10 = iY;
                    map = map2;
                    iQ = iQ;
                    if (action2.equals("label.new") && !AbstractC7609s.f(scriptIndicAction.getDisplay(), Boolean.FALSE)) {
                        this = this;
                        AbstractC2759w0 abstractC2759w7 = abstractC2759w3;
                        fX = f10;
                        this.C(canvas, scriptIndicAction, abstractC2759w7, fX, Sf.N.z(calculateHistoryData));
                        scriptIndicAction2 = scriptIndicAction;
                        abstractC2759w3 = abstractC2759w7;
                        iY = i10;
                        fU = f11;
                    }
                    iY = i10;
                    scriptIndicAction2 = scriptIndicAction;
                    fX = f10;
                    fU = f11;
                    break;
                case -405487794:
                    calculateHistoryData = calculateHistoryData;
                    f10 = fX;
                    f11 = fU;
                    map = map2;
                    abstractC2759w0 = abstractC2759w3;
                    scriptIndicAction3 = scriptIndicAction6;
                    iQ = iQ;
                    c7395u = this;
                    if (!action2.equals("plotCandle")) {
                        this = c7395u;
                        abstractC2759w3 = abstractC2759w0;
                        scriptIndicAction2 = scriptIndicAction3;
                    } else if (!AbstractC7609s.f(scriptIndicAction3.getDisplay(), Boolean.FALSE)) {
                        float f19 = f18;
                        int i19 = iR;
                        int i20 = iY;
                        c7395u.v(canvas, f19, f11, fJ, scriptIndicAction3, abstractC2759w0, i19, i20, Sf.N.z(calculateHistoryData));
                        f18 = f19;
                        scriptIndicAction = scriptIndicAction3;
                        abstractC2759w3 = abstractC2759w0;
                        iR = i19;
                        i10 = i20;
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
                                y(canvas, abstractC2759w3, dDoubleValue2, str7 == null ? "" : str7);
                            }
                        }
                        iY = i10;
                        scriptIndicAction2 = scriptIndicAction;
                        fX = f10;
                        fU = f11;
                    } else {
                        this = this;
                        abstractC2759w3 = abstractC2759w0;
                        scriptIndicAction2 = scriptIndicAction3;
                    }
                    iY = iY;
                    fX = f10;
                    fU = f11;
                    break;
                case -392601705:
                    calculateHistoryData = calculateHistoryData;
                    f10 = fX;
                    f11 = fU;
                    map = map2;
                    abstractC2759w0 = abstractC2759w3;
                    scriptIndicAction3 = scriptIndicAction6;
                    iQ = iQ;
                    c7395u = this;
                    if (action2.equals("plotColumn") && !AbstractC7609s.f(scriptIndicAction3.getDisplay(), Boolean.FALSE)) {
                        Map mapZ = Sf.N.z(calculateHistoryData);
                        float f20 = (f11 / 6) - fJ;
                        float f21 = f20 + f18;
                        String histBase = scriptIndicAction3.getHistBase();
                        float fP = abstractC2759w0.P((histBase == null || (dN5 = Ah.v.n(histBase)) == null) ? 0.0d : dN5.doubleValue());
                        int intOffset = scriptIndicAction3.getIntOffset();
                        if (intOffset < 0) {
                            iAbs = Math.abs(intOffset) + iY;
                            float f22 = intOffset * f11;
                            f20 += f22;
                            f21 += f22;
                        } else {
                            iAbs = iY;
                        }
                        int i21 = intOffset > 0 ? iR - intOffset : iR;
                        String strA = kk.f.a(scriptIndicAction3, new StringBuilder(), "Value");
                        if (scriptIndicAction3.getOutput().getFill()) {
                            c7395u.f95560w.setStyle(Paint.Style.FILL);
                        } else {
                            c7395u.f95560w.setStyle(Paint.Style.STROKE);
                        }
                        int intShowLast = scriptIndicAction3.getIntShowLast();
                        int i22 = (1 > intShowLast || intShowLast >= (i13 = c7395u.f95544a0)) ? -1 : i13 - intShowLast;
                        try {
                            y1 y1Var2 = c7395u.f95551n;
                            jH = y1Var2 != null ? y1Var2.H(i22) : 0L;
                        } catch (Exception unused) {
                        }
                        float f23 = f21;
                        float f24 = f20;
                        while (i21 < iAbs) {
                            int i23 = i22;
                            y1 y1Var3 = c7395u.f95551n;
                            Map map3 = (Map) mapZ.get(String.valueOf(y1Var3 != null ? Long.valueOf(y1Var3.H(i21)) : null));
                            if (map3 == null) {
                                str = strA;
                                i12 = i21;
                                f14 = fP;
                                i11 = i23;
                                iAbs = iAbs;
                            } else {
                                float f25 = f24;
                                String str8 = (String) map3.get("time");
                                long jLongValue = (str8 == null || (lR = Ah.w.r(str8)) == null) ? 0L : lR.longValue();
                                String series = scriptIndicAction3.getSeries();
                                if (series == null) {
                                    series = "0";
                                }
                                String str9 = (String) map3.get(series);
                                double dDoubleValue3 = (str9 == null || (dN4 = Ah.v.n(str9)) == null) ? 0.0d : dN4.doubleValue();
                                if (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || map3.isEmpty()) {
                                    iA = dDoubleValue3 >= 0.0d ? c7395u.f95527J : c7395u.f95528K;
                                } else {
                                    String str10 = (String) map3.get(strA);
                                    iA = (str10 == null || (numP = Ah.w.p(str10)) == null) ? f10.u()[c7395u.f95526I].a() : numP.intValue();
                                }
                                float f26 = f23;
                                c7395u.f95560w.setColor(iA);
                                if (i23 <= 0 || jLongValue >= jH) {
                                    if (dDoubleValue3 == 0.0d) {
                                        float fQ = (abstractC2759w0.u() == 0.0d && abstractC2759w0.v() == 0.0d) ? abstractC2759w0.q() + fP : fP;
                                        str = strA;
                                        f13 = f25;
                                        f12 = f26;
                                        i11 = i23;
                                        i12 = i21;
                                        canvas.drawLine(f13, fQ, f12, fQ, c7395u.f95560w);
                                    } else {
                                        iAbs = iAbs;
                                        f12 = f26;
                                        i11 = i23;
                                        i12 = i21;
                                        f13 = f25;
                                        str = strA;
                                        String series2 = scriptIndicAction3.getSeries();
                                        if (series2 == null) {
                                            series2 = "0";
                                        }
                                        String str11 = (String) map3.get(series2);
                                        float fP2 = abstractC2759w0.P((str11 == null || (dN3 = Ah.v.n(str11)) == null) ? 0.0d : dN3.doubleValue());
                                        if (Math.abs(fP - fP2) < 1.0f) {
                                            float f27 = fP;
                                            canvas.drawLine(f13, f27, f12, fP, c7395u.f95560w);
                                            f14 = f27;
                                        } else {
                                            f14 = fP;
                                            nk.y.a(canvas, f13, fP2, f12, f14, c7395u.f95560w);
                                        }
                                    }
                                    f24 = f13 + f11;
                                    f23 = f12 + f11;
                                } else {
                                    f12 = f26;
                                    i11 = i23;
                                    i12 = i21;
                                    f13 = f25;
                                    str = strA;
                                }
                                f14 = fP;
                                f24 = f13 + f11;
                                f23 = f12 + f11;
                            }
                            i21 = i12 + 1;
                            fP = f14;
                            iAbs = iAbs;
                            strA = str;
                            i22 = i11;
                        }
                    }
                    this = c7395u;
                    abstractC2759w3 = abstractC2759w0;
                    scriptIndicAction2 = scriptIndicAction3;
                    iY = iY;
                    fX = f10;
                    fU = f11;
                    break;
                case 3143043:
                    scriptIndicAction = scriptIndicAction6;
                    calculateHistoryData = calculateHistoryData;
                    f11 = fU;
                    map = map2;
                    if (!action2.equals("fill")) {
                        this = this;
                        iQ = iQ;
                        fX = fX;
                        f18 = f18;
                        iY = iY;
                        scriptIndicAction2 = scriptIndicAction;
                        fU = f11;
                    } else if (AbstractC7609s.f(scriptIndicAction.getDisplay(), Boolean.FALSE)) {
                        f10 = fX;
                        iQ = iQ;
                        f18 = f18;
                        iY = iY;
                        scriptIndicAction2 = scriptIndicAction;
                        fX = f10;
                        fU = f11;
                    } else {
                        this = this;
                        AbstractC2759w0 abstractC2759w8 = abstractC2759w3;
                        fU = f11;
                        this.x(canvas, f17, fU, scriptIndicAction, abstractC2759w8, iR, iQ, fX, Sf.N.z(calculateHistoryData));
                        abstractC2759w3 = abstractC2759w8;
                        iQ = iQ;
                        f18 = f18;
                        scriptIndicAction2 = scriptIndicAction;
                        fX = fX;
                        iY = iY;
                    }
                    break;
                case 3443937:
                    calculateHistoryData = calculateHistoryData;
                    i14 = iR;
                    fX = fX;
                    f11 = fU;
                    map = map2;
                    scriptIndicAction2 = scriptIndicAction6;
                    if (action2.equals("plot") && !AbstractC7609s.f(scriptIndicAction2.getDisplay(), Boolean.FALSE)) {
                        fX = fX;
                        iR = i14;
                        AbstractC2759w0 abstractC2759w9 = abstractC2759w3;
                        B(canvas, f17, f11, scriptIndicAction2, abstractC2759w9, iR, iQ, fX, Sf.N.z(calculateHistoryData));
                        scriptIndicAction = scriptIndicAction2;
                        abstractC2759w3 = abstractC2759w9;
                        if (AbstractC7609s.f(scriptIndicAction.getTrackPrice(), Boolean.TRUE) && map != null) {
                            String series3 = scriptIndicAction.getSeries();
                            if (series3 == null) {
                                series3 = "0";
                            }
                            String str12 = (String) map.get(series3);
                            if (str12 == null) {
                                str12 = "0.0";
                            }
                            Double dN9 = Ah.v.n(str12);
                            double dDoubleValue4 = dN9 != null ? dN9.doubleValue() : 0.0d;
                            if (dDoubleValue4 != 0.0d) {
                                StringBuilder sb4 = new StringBuilder();
                                ActionOutput output3 = scriptIndicAction.getOutput();
                                sb4.append(output3 != null ? output3.getColor() : null);
                                sb4.append("originValue");
                                String str13 = (String) map.get(sb4.toString());
                                y(canvas, abstractC2759w3, dDoubleValue4, str13 == null ? "" : str13);
                            }
                        }
                        this = this;
                        iQ = iQ;
                        fX = fX;
                        f18 = f18;
                        iY = iY;
                        scriptIndicAction2 = scriptIndicAction;
                        fU = f11;
                    }
                    this = this;
                    fU = f11;
                    iR = i14;
                    break;
                case 71185149:
                    calculateHistoryData = calculateHistoryData;
                    i14 = iR;
                    fX = fX;
                    f11 = fU;
                    map = map2;
                    scriptIndicAction2 = scriptIndicAction6;
                    if (action2.equals("box.new") && !AbstractC7609s.f(scriptIndicAction2.getDisplay(), Boolean.FALSE)) {
                        this = this;
                        abstractC2759w1 = abstractC2759w3;
                        scriptIndicAction4 = scriptIndicAction2;
                        this.z(canvas, scriptIndicAction4, abstractC2759w1, fX, Sf.N.z(calculateHistoryData));
                        scriptIndicAction2 = scriptIndicAction4;
                        abstractC2759w3 = abstractC2759w1;
                    } else {
                        this = this;
                    }
                    fU = f11;
                    iR = i14;
                    break;
                case 1187522726:
                    abstractC2759w2 = abstractC2759w3;
                    scriptIndicAction5 = scriptIndicAction6;
                    calculateHistoryData = calculateHistoryData;
                    i14 = iR;
                    f15 = fX;
                    f11 = fU;
                    if (action2.equals("line.new")) {
                        map = map2;
                        if (AbstractC7609s.f(scriptIndicAction5.getDisplay(), Boolean.FALSE)) {
                            this = this;
                            scriptIndicAction2 = scriptIndicAction5;
                            abstractC2759w3 = abstractC2759w2;
                            fX = f15;
                        } else {
                            scriptIndicAction4 = scriptIndicAction5;
                            abstractC2759w1 = abstractC2759w2;
                            fX = f15;
                            this.E(canvas, scriptIndicAction4, abstractC2759w1, fX, calculateHistoryData);
                            this = this;
                            scriptIndicAction2 = scriptIndicAction4;
                            abstractC2759w3 = abstractC2759w1;
                        }
                        fU = f11;
                        iR = i14;
                    } else {
                        f18 = f18;
                        iY = iY;
                        map = map2;
                        scriptIndicAction2 = scriptIndicAction5;
                        abstractC2759w3 = abstractC2759w2;
                        fX = f15;
                        fU = f11;
                        iR = i14;
                        iQ = iQ;
                    }
                    break;
                case 1803007808:
                    if (action2.equals("plotShape") && !AbstractC7609s.f(scriptIndicAction6.getDisplay(), Boolean.FALSE)) {
                        Map mapZ2 = Sf.N.z(calculateHistoryData);
                        this.f95519B.reset();
                        this.f95520C.reset();
                        int intOffset2 = scriptIndicAction6.getIntOffset();
                        String strA2 = kk.f.a(scriptIndicAction6, new StringBuilder(), "Value");
                        scriptIndicAction6.getOutput().getBgColor();
                        int intShowLast2 = scriptIndicAction6.getIntShowLast();
                        scriptIndicAction5 = scriptIndicAction6;
                        ArrayList arrayList = new ArrayList();
                        calculateHistoryData = calculateHistoryData;
                        if (intOffset2 != 0) {
                            List listB = Sf.P.B(mapZ2);
                            int i24 = 0;
                            for (Object obj : listB) {
                                int i25 = i24 + 1;
                                if (i24 < 0) {
                                    Sf.r.x();
                                }
                                int i26 = iR;
                                int i27 = (intOffset2 * (-1)) + i24;
                                Object objD = ((Qf.p) obj).d();
                                sp.aicoin_kline.core.indicator.config.F f28 = fX;
                                Map map4 = (Map) objD;
                                String series4 = scriptIndicAction5.getSeries();
                                float f29 = fU;
                                String str14 = (String) map4.get(series4 == null ? "0" : series4);
                                boolean z11 = ((str14 == null || (dN8 = Ah.v.n(str14)) == null) ? 0.0d : dN8.doubleValue()) > 0.0d;
                                if (i27 >= 0 && i27 < listB.size() && z11) {
                                    arrayList.add(listB.get(i27));
                                }
                                fX = f28;
                                i24 = i25;
                                fU = f29;
                                iR = i26;
                            }
                        }
                        i14 = iR;
                        f15 = fX;
                        f11 = fU;
                        if (intOffset2 != 0) {
                            mapZ2 = Sf.N.z(Sf.N.v(arrayList));
                        }
                        int i28 = (intShowLast2 <= 0 || intShowLast2 >= mapZ2.size()) ? 0 : (this.f95544a0 - intShowLast2) + intOffset2;
                        nk.x.f134260a.d(mapZ2);
                        float f30 = f17;
                        int i29 = i14;
                        while (i29 < iQ) {
                            y1 y1Var4 = this.f95551n;
                            Map linkedHashMap = (Map) mapZ2.get(String.valueOf(y1Var4 != null ? Long.valueOf(y1Var4.H(i29)) : null));
                            if (linkedHashMap == null) {
                                linkedHashMap = new LinkedHashMap();
                            }
                            if (intOffset2 == 0) {
                                String series5 = scriptIndicAction5.getSeries();
                                if (series5 == null) {
                                    series5 = "0";
                                }
                                String str15 = (String) linkedHashMap.get(series5);
                                if (((str15 == null || (dN7 = Ah.v.n(str15)) == null) ? 0.0d : dN7.doubleValue()) > 0.0d) {
                                    z10 = true;
                                } else {
                                    z10 = false;
                                }
                            } else {
                                z10 = true;
                            }
                            String refSeries = scriptIndicAction5.getRefSeries();
                            if (refSeries == null) {
                                refSeries = "";
                            }
                            String str16 = (String) linkedHashMap.get(refSeries);
                            double dDoubleValue5 = (str16 == null || (dN6 = Ah.v.n(str16)) == null) ? 0.0d : dN6.doubleValue();
                            if (dDoubleValue5 != 0.0d && z10) {
                                float fP3 = abstractC2759w3.P(dDoubleValue5);
                                int iA2 = (strA2 == null || strA2.length() == 0 || AbstractC7609s.f(strA2, "nullValue") || (str3 = (String) linkedHashMap.get(strA2)) == null || (numP2 = Ah.w.p(str3)) == null) ? f15.u()[this.f95526I].a() : numP2.intValue();
                                if (scriptIndicAction5.getOutput().getFill()) {
                                    this.f95518A.setStyle(Paint.Style.FILL_AND_STROKE);
                                } else {
                                    this.f95518A.setStyle(Paint.Style.STROKE);
                                }
                                this.f95518A.setColor(iA2);
                                String placement = scriptIndicAction5.getOutput().getPlacement();
                                String shape = scriptIndicAction5.getOutput().getShape();
                                if (i29 >= i28) {
                                    i15 = i28;
                                    str2 = strA2;
                                    switch (shape.hashCode()) {
                                        case -1360216880:
                                            if (shape.equals("circle")) {
                                                this.f95525H = Xj.a.a(10.0f);
                                                if (AbstractC7609s.f(placement, "bottom")) {
                                                    canvas.drawCircle(f30, fP3 + this.f95525H, Xj.a.a(3.0f), this.f95518A);
                                                } else if (AbstractC7609s.f(placement, "center")) {
                                                    canvas.drawCircle(f30, fP3, Xj.a.a(3.0f), this.f95518A);
                                                } else {
                                                    canvas.drawCircle(f30, fP3 - this.f95525H, Xj.a.a(3.0f), this.f95518A);
                                                }
                                            }
                                            break;
                                        case -1026432949:
                                            if (shape.equals("arrowDown")) {
                                                this.f95521D = Xj.a.a(6.0f);
                                                this.f95522E = Xj.a.a(7.0f);
                                                this.f95523F = Xj.a.a(10.0f);
                                                this.f95524G = Xj.a.a(2.0f);
                                                this.f95525H = Xj.a.a(7.0f);
                                                if (AbstractC7609s.f(placement, "bottom")) {
                                                    this.f95519B.moveTo(f30, this.f95525H + fP3);
                                                    this.f95519B.lineTo(this.f95524G + f30, this.f95525H + fP3);
                                                    this.f95519B.lineTo(this.f95524G + f30, this.f95523F + fP3 + this.f95525H);
                                                    this.f95519B.lineTo(this.f95521D + f30, this.f95523F + fP3 + this.f95525H);
                                                    this.f95519B.lineTo(f30, this.f95523F + fP3 + this.f95522E + this.f95525H);
                                                    this.f95519B.lineTo(f30 - this.f95521D, this.f95523F + fP3 + this.f95525H);
                                                    this.f95519B.lineTo(f30 - this.f95524G, this.f95523F + fP3 + this.f95525H);
                                                    this.f95519B.lineTo(f30 - this.f95524G, fP3 + this.f95525H);
                                                    this.f95519B.close();
                                                } else if (AbstractC7609s.f(placement, "center")) {
                                                    this.f95519B.moveTo(f30, fP3 - this.f95525H);
                                                    this.f95519B.lineTo(this.f95524G + f30, fP3 - this.f95525H);
                                                    this.f95519B.lineTo(this.f95524G + f30, (this.f95523F + fP3) - this.f95525H);
                                                    this.f95519B.lineTo(this.f95521D + f30, (this.f95523F + fP3) - this.f95525H);
                                                    this.f95519B.lineTo(f30, ((this.f95523F + fP3) + this.f95522E) - this.f95525H);
                                                    this.f95519B.lineTo(f30 - this.f95521D, (this.f95523F + fP3) - this.f95525H);
                                                    this.f95519B.lineTo(f30 - this.f95524G, (this.f95523F + fP3) - this.f95525H);
                                                    this.f95519B.lineTo(f30 - this.f95524G, fP3 - this.f95525H);
                                                    this.f95519B.close();
                                                } else {
                                                    this.f95519B.moveTo(f30, fP3 - this.f95525H);
                                                    this.f95519B.lineTo(this.f95521D + f30, (fP3 - this.f95522E) - this.f95525H);
                                                    this.f95519B.lineTo(this.f95524G + f30, (fP3 - this.f95522E) - this.f95525H);
                                                    this.f95519B.lineTo(this.f95524G + f30, (fP3 - this.f95523F) - this.f95525H);
                                                    this.f95519B.lineTo(this.f95524G + f30, ((fP3 - this.f95523F) - this.f95522E) - this.f95525H);
                                                    this.f95519B.lineTo(f30 - this.f95524G, ((fP3 - this.f95523F) - this.f95522E) - this.f95525H);
                                                    this.f95519B.lineTo(f30 - this.f95524G, (fP3 - this.f95522E) - this.f95525H);
                                                    this.f95519B.lineTo(f30 - this.f95521D, (fP3 - this.f95522E) - this.f95525H);
                                                    this.f95519B.close();
                                                }
                                            }
                                            break;
                                        case -742236470:
                                            if (shape.equals("triangleDown")) {
                                                this.f95521D = Xj.a.a(7.0f);
                                                this.f95522E = Xj.a.a(9.0f);
                                                this.f95525H = Xj.a.a(5.0f);
                                                if (AbstractC7609s.f(placement, "bottom")) {
                                                    this.f95519B.moveTo(f30, this.f95525H + fP3);
                                                    this.f95519B.lineTo(this.f95521D + f30, this.f95525H + fP3);
                                                    this.f95519B.lineTo(f30, this.f95525H + fP3 + this.f95522E);
                                                    this.f95519B.lineTo(f30 - this.f95521D, fP3 + this.f95525H);
                                                    this.f95519B.close();
                                                } else if (AbstractC7609s.f(placement, "center")) {
                                                    this.f95519B.moveTo(f30, fP3 - this.f95525H);
                                                    this.f95519B.lineTo(this.f95521D + f30, fP3 - this.f95525H);
                                                    this.f95519B.lineTo(f30, (fP3 - this.f95525H) + this.f95522E);
                                                    this.f95519B.lineTo(f30 - this.f95521D, fP3 - this.f95525H);
                                                    this.f95519B.close();
                                                } else {
                                                    this.f95521D = Xj.a.a(7.0f);
                                                    this.f95522E = Xj.a.a(9.0f);
                                                    float fA = Xj.a.a(5.0f);
                                                    this.f95525H = fA;
                                                    this.f95519B.moveTo(f30, fP3 - fA);
                                                    this.f95519B.lineTo(this.f95521D + f30, (fP3 - this.f95525H) - this.f95522E);
                                                    this.f95519B.lineTo(f30 - this.f95521D, (fP3 - this.f95525H) - this.f95522E);
                                                    this.f95519B.close();
                                                }
                                            }
                                            break;
                                        case -734027644:
                                            if (shape.equals("arrowUp")) {
                                                this.f95521D = Xj.a.a(6.0f);
                                                this.f95522E = Xj.a.a(7.0f);
                                                this.f95523F = Xj.a.a(10.0f);
                                                this.f95524G = Xj.a.a(2.0f);
                                                this.f95525H = Xj.a.a(7.0f);
                                                if (AbstractC7609s.f(placement, "bottom")) {
                                                    this.f95519B.moveTo(f30, this.f95525H + fP3);
                                                    this.f95519B.lineTo(this.f95521D + f30, this.f95522E + fP3 + this.f95525H);
                                                    this.f95519B.lineTo(this.f95524G + f30, this.f95522E + fP3 + this.f95525H);
                                                    this.f95519B.lineTo(this.f95524G + f30, this.f95523F + fP3 + this.f95525H);
                                                    this.f95519B.lineTo(this.f95524G + f30, this.f95523F + fP3 + this.f95522E + this.f95525H);
                                                    this.f95519B.lineTo(f30 - this.f95524G, this.f95523F + fP3 + this.f95522E + this.f95525H);
                                                    this.f95519B.lineTo(f30 - this.f95524G, this.f95522E + fP3 + this.f95525H);
                                                    this.f95519B.lineTo(f30 - this.f95521D, fP3 + this.f95522E + this.f95525H);
                                                    this.f95519B.close();
                                                } else if (AbstractC7609s.f(placement, "center")) {
                                                    this.f95519B.moveTo(f30, fP3 - this.f95525H);
                                                    this.f95519B.lineTo(this.f95521D + f30, (this.f95522E + fP3) - this.f95525H);
                                                    this.f95519B.lineTo(this.f95524G + f30, (this.f95522E + fP3) - this.f95525H);
                                                    this.f95519B.lineTo(this.f95524G + f30, (this.f95523F + fP3) - this.f95525H);
                                                    this.f95519B.lineTo(this.f95524G + f30, ((this.f95523F + fP3) + this.f95522E) - this.f95525H);
                                                    this.f95519B.lineTo(f30 - this.f95524G, ((this.f95523F + fP3) + this.f95522E) - this.f95525H);
                                                    this.f95519B.lineTo(f30 - this.f95524G, (this.f95522E + fP3) - this.f95525H);
                                                    this.f95519B.lineTo(f30 - this.f95521D, (fP3 + this.f95522E) - this.f95525H);
                                                    this.f95519B.close();
                                                } else {
                                                    this.f95519B.moveTo(f30, fP3 - this.f95525H);
                                                    this.f95519B.lineTo(this.f95524G + f30, fP3 - this.f95525H);
                                                    this.f95519B.lineTo(this.f95524G + f30, (fP3 - this.f95523F) - this.f95525H);
                                                    this.f95519B.lineTo(this.f95521D + f30, (fP3 - this.f95523F) - this.f95525H);
                                                    this.f95519B.lineTo(f30, ((fP3 - this.f95523F) - this.f95522E) - this.f95525H);
                                                    this.f95519B.lineTo(f30 - this.f95521D, (fP3 - this.f95523F) - this.f95525H);
                                                    this.f95519B.lineTo(f30 - this.f95524G, (fP3 - this.f95523F) - this.f95525H);
                                                    this.f95519B.lineTo(f30 - this.f95524G, fP3 - this.f95525H);
                                                    this.f95519B.close();
                                                }
                                            }
                                            break;
                                        case 535540419:
                                            if (shape.equals("triangleUp")) {
                                                if (AbstractC7609s.f(placement, "bottom")) {
                                                    this.f95521D = Xj.a.a(7.0f);
                                                    this.f95522E = Xj.a.a(9.0f);
                                                    float fA2 = Xj.a.a(5.0f);
                                                    this.f95525H = fA2;
                                                    this.f95519B.moveTo(f30, fA2 + fP3);
                                                    this.f95519B.lineTo(this.f95521D + f30, this.f95525H + fP3 + this.f95522E);
                                                    this.f95519B.lineTo(f30 - this.f95521D, fP3 + this.f95525H + this.f95522E);
                                                    this.f95519B.close();
                                                } else if (AbstractC7609s.f(placement, "center")) {
                                                    this.f95521D = Xj.a.a(7.0f);
                                                    this.f95522E = Xj.a.a(9.0f);
                                                    float fA3 = Xj.a.a(5.0f);
                                                    this.f95525H = fA3;
                                                    this.f95519B.moveTo(f30, fP3 - fA3);
                                                    this.f95519B.lineTo(this.f95521D + f30, (fP3 - this.f95525H) + this.f95522E);
                                                    this.f95519B.lineTo(f30 - this.f95521D, (fP3 - this.f95525H) + this.f95522E);
                                                    this.f95519B.close();
                                                } else {
                                                    this.f95521D = Xj.a.a(7.0f);
                                                    this.f95522E = Xj.a.a(9.0f);
                                                    float fA4 = Xj.a.a(5.0f);
                                                    this.f95525H = fA4;
                                                    this.f95519B.moveTo(f30, fP3 - fA4);
                                                    this.f95519B.lineTo(this.f95521D + f30, fP3 - this.f95525H);
                                                    this.f95519B.lineTo(f30, (fP3 - this.f95525H) - this.f95522E);
                                                    this.f95519B.lineTo(f30 - this.f95521D, fP3 - this.f95525H);
                                                    this.f95519B.close();
                                                }
                                            }
                                            break;
                                    }
                                }
                                f30 += f11;
                                i29++;
                                mapZ2 = mapZ2;
                                abstractC2759w3 = abstractC2759w3;
                                i28 = i15;
                                strA2 = str2;
                            } else {
                                abstractC2759w3 = abstractC2759w3;
                            }
                            i15 = i28;
                            str2 = strA2;
                            f30 += f11;
                            i29++;
                            mapZ2 = mapZ2;
                            abstractC2759w3 = abstractC2759w3;
                            i28 = i15;
                            strA2 = str2;
                        }
                        abstractC2759w2 = abstractC2759w3;
                        canvas.drawPath(this.f95519B, this.f95518A);
                        f18 = f18;
                        iY = iY;
                        map = map2;
                        scriptIndicAction2 = scriptIndicAction5;
                        abstractC2759w3 = abstractC2759w2;
                        fX = f15;
                        fU = f11;
                        iR = i14;
                        iQ = iQ;
                        break;
                    }
                default:
                    calculateHistoryData = calculateHistoryData;
                    fX = fX;
                    f18 = f18;
                    iY = iY;
                    map = map2;
                    scriptIndicAction2 = scriptIndicAction6;
                    iQ = iQ;
                    fU = fU;
                    break;
            }
            String color = scriptIndicAction2.getOutput().getColor();
            if (color == null || color.length() == 0) {
                int i30 = this.f95526I + 1;
                this.f95526I = i30;
                if (i30 >= fX.u().length) {
                    this.f95526I = fX.u().length - 1;
                }
                if (this.f95526I < 0) {
                    this.f95526I = 0;
                }
            }
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
        this.f95550m = c2741qB.e(b());
        this.f95551n = c2741qB.m(c());
        this.f95552o = c2741qB.l(b());
        AbstractC2755v abstractC2755vQ = q();
        N0 n10 = abstractC2755vQ instanceof N0 ? (N0) abstractC2755vQ : null;
        if (n10 == null) {
            return;
        }
        if (c2741qB.g(b() + ".m") == null) {
            return;
        }
        this.f95527J = aVar.r();
        this.f95528K = aVar.m();
        this.f95553p = n10;
        this.f95554q = new Path();
        this.f95556s = new Path();
        Paint paint = new Paint();
        Paint.Style style = Paint.Style.STROKE;
        paint.setStyle(style);
        paint.setAntiAlias(true);
        paint.setStrokeWidth(2.0f);
        paint.setColor(-16777216);
        this.f95555r = paint;
        Paint paint2 = new Paint();
        paint2.setStyle(style);
        paint2.setAntiAlias(true);
        paint2.setStrokeWidth(2.0f);
        paint2.setColor(-16777216);
        this.f95557t = paint2;
        Paint paint3 = new Paint(1);
        paint3.setAntiAlias(true);
        paint3.setColor(-16777216);
        paint3.setTextSize(Xj.a.d(12));
        this.f95558u = paint3;
        Paint paint4 = new Paint(1);
        paint4.setAntiAlias(true);
        paint4.setColor(-16777216);
        paint4.setTextSize(Xj.a.d(9));
        Paint paint5 = new Paint();
        paint5.setStyle(style);
        paint5.setAntiAlias(true);
        paint5.setStrokeWidth(2.0f);
        paint5.setColor(-16711936);
        this.f95560w = paint5;
        Paint paint6 = new Paint();
        paint6.setStyle(style);
        paint6.setAntiAlias(true);
        paint6.setStrokeWidth(2.0f);
        paint6.setColor(-16711936);
        this.f95561x = paint6;
        this.f95562y = new Path();
        Paint paint7 = new Paint();
        Paint.Style style2 = Paint.Style.FILL_AND_STROKE;
        paint7.setStyle(style2);
        paint7.setAntiAlias(true);
        paint7.setStrokeWidth(2.0f);
        paint7.setColor(-16711936);
        this.f95563z = paint7;
        Paint paint8 = new Paint();
        paint8.setStyle(style);
        paint8.setAntiAlias(true);
        paint8.setStrokeWidth(Xj.a.a(1.0f));
        paint8.setColor(-16711936);
        this.f95518A = paint8;
        Paint paint9 = new Paint();
        paint9.setStyle(style2);
        paint9.setAntiAlias(true);
        paint9.setStrokeWidth(2.0f);
        paint9.setColor(-1);
        this.f95540W.setStyle(style2);
        if (KLineManager.f142490O.a().f0() == 1) {
            this.f95539V.setStrokeWidth(1.0f);
            this.f95541X.setStrokeWidth(1.0f);
        }
        this.f95538U.setStyle(style);
        this.f95538U.setAntiAlias(true);
        this.f95537T.setStrokeWidth(2.0f);
        this.f95540W.setStrokeWidth(2.0f);
        this.f95538U.setStrokeWidth(1.0f);
        this.f95537T.setColor(aVar.r());
        this.f95538U.setColor(0);
        this.f95539V.setColor(aVar.r());
        this.f95540W.setColor(aVar.m());
        this.f95541X.setColor(aVar.m());
        this.f95542Y.setColor(aVar.r());
        this.f95546c0.setStyle(style);
        this.f95546c0.setStrokeWidth(2.0f);
        this.f95546c0.setColor(aVar.t());
        this.f95546c0.setPathEffect(new DashPathEffect(new float[]{Xj.a.b(3), Xj.a.b(2)}, 0.0f));
    }

    /* JADX WARN: Code duplicated, block: B:85:0x018e  */
    public final void v(Canvas canvas, float f10, float f11, float f12, ScriptIndicAction scriptIndicAction, AbstractC2759w0 abstractC2759w0, int i10, int i11, Map map) {
        int iAbs;
        long jH;
        boolean z10;
        float f13;
        float f14;
        float f15;
        float f16;
        float f17;
        String str;
        Integer numP;
        String str2;
        Integer numP2;
        float f18;
        String str3;
        Integer numP3;
        float f19;
        float f20;
        float f21;
        float f22;
        String str4;
        Integer numP4;
        String str5;
        Integer numP5;
        Double dN;
        Double dN2;
        Double dN3;
        Double dN4;
        Long lR;
        int i12;
        float f23 = (f11 / 6) - f12;
        float f24 = f23 + f10;
        float f25 = 2;
        int intOffset = scriptIndicAction.getIntOffset();
        this.f95543Z.reset();
        if (intOffset < 0) {
            float f26 = intOffset * f11;
            f23 += f26;
            f24 += f26;
            iAbs = Math.abs(intOffset) + i11;
        } else {
            iAbs = i11;
        }
        int intShowLast = scriptIndicAction.getIntShowLast();
        int i13 = (1 > intShowLast || intShowLast >= (i12 = this.f95544a0)) ? -1 : i12 - intShowLast;
        try {
            y1 y1Var = this.f95551n;
            jH = y1Var != null ? y1Var.H(i13) : 0L;
        } catch (Exception unused) {
        }
        float f27 = f23;
        for (int i14 = intOffset > 0 ? i10 - intOffset : i10; i14 < iAbs; i14++) {
            y1 y1Var2 = this.f95551n;
            Map map2 = (Map) map.get(String.valueOf(y1Var2 != null ? Long.valueOf(y1Var2.H(i14)) : null));
            if (map2 != null) {
                String str6 = (String) map2.get("time");
                long jLongValue = (str6 == null || (lR = Ah.w.r(str6)) == null) ? 0L : lR.longValue();
                String open = scriptIndicAction.getOpen();
                String str7 = (String) map2.get(open == null ? "" : open);
                double dDoubleValue = 0.0d;
                double dDoubleValue2 = (str7 == null || (dN4 = Ah.v.n(str7)) == null) ? 0.0d : dN4.doubleValue();
                this.f95534Q = dDoubleValue2;
                this.f95530M = abstractC2759w0.P(dDoubleValue2);
                String high = scriptIndicAction.getHigh();
                if (high == null) {
                    high = "";
                }
                String str8 = (String) map2.get(high);
                double dDoubleValue3 = (str8 == null || (dN3 = Ah.v.n(str8)) == null) ? 0.0d : dN3.doubleValue();
                this.f95533P = dDoubleValue3;
                this.f95529L = abstractC2759w0.P(dDoubleValue3);
                String low = scriptIndicAction.getLow();
                if (low == null) {
                    low = "";
                }
                String str9 = (String) map2.get(low);
                double dDoubleValue4 = (str9 == null || (dN2 = Ah.v.n(str9)) == null) ? 0.0d : dN2.doubleValue();
                this.f95535R = dDoubleValue4;
                this.f95531N = abstractC2759w0.P(dDoubleValue4);
                String close = scriptIndicAction.getClose();
                if (close == null) {
                    close = "";
                }
                String str10 = (String) map2.get(close);
                if (str10 != null && (dN = Ah.v.n(str10)) != null) {
                    dDoubleValue = dN.doubleValue();
                }
                double d10 = dDoubleValue;
                this.f95536S = d10;
                this.f95532O = abstractC2759w0.P(d10);
                String strA = kk.f.a(scriptIndicAction, new StringBuilder(), "Value");
                StringBuilder sb2 = new StringBuilder();
                float f28 = f27;
                sb2.append(scriptIndicAction.getOutput().getBorderColor());
                sb2.append("Value");
                String string = sb2.toString();
                String str11 = scriptIndicAction.getOutput().getWickColor() + "Value";
                if (string == null || string.length() == 0 || AbstractC7609s.f(string, "nullValue")) {
                    z10 = false;
                } else {
                    String str12 = (String) map2.get(string);
                    Integer numP6 = str12 != null ? Ah.w.p(str12) : null;
                    if (numP6 != null) {
                        this.f95538U.setColor(numP6.intValue());
                        z10 = true;
                    } else {
                        z10 = false;
                    }
                }
                float fAbs = (Math.abs(f24 - f28) / f25) + f28;
                if (i13 <= 0 || jLongValue >= jH) {
                    double d11 = this.f95536S;
                    double d12 = this.f95534Q;
                    if (d11 > d12) {
                        this.f95539V.setStrokeWidth(3.0f);
                        float fFloatValue = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95530M), Float.valueOf(this.f95532O))).floatValue();
                        float fFloatValue2 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95532O), Float.valueOf(this.f95530M))).floatValue();
                        float fFloatValue3 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95531N), Float.valueOf(this.f95529L))).floatValue();
                        float fFloatValue4 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95529L), Float.valueOf(this.f95531N))).floatValue();
                        boolean z11 = fFloatValue2 - fFloatValue >= 2.0f;
                        Paint paint = this.f95539V;
                        int iIntValue = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str5 = (String) map2.get(strA)) == null || (numP5 = Ah.w.p(str5)) == null) ? this.f95527J : numP5.intValue();
                        paint.setColor(iIntValue);
                        Paint paint2 = this.f95537T;
                        int iIntValue2 = (str11 == null || str11.length() == 0 || AbstractC7609s.f(str11, "nullValue") || (str4 = (String) map2.get(str11)) == null || (numP4 = Ah.w.p(str4)) == null) ? this.f95527J : numP4.intValue();
                        paint2.setColor(iIntValue2);
                        if (z11) {
                            canvas.drawRect(f28, fFloatValue, f24 - 1, fFloatValue2, this.f95539V);
                            if (z10) {
                                float f29 = f28 - f25;
                                float f30 = fFloatValue - f25;
                                this.f95543Z.moveTo(f29, f30);
                                float f31 = f24 + f25;
                                this.f95543Z.lineTo(f31, f30);
                                float f32 = fFloatValue2 + f25;
                                this.f95543Z.lineTo(f31, f32);
                                this.f95543Z.lineTo(f29, f32);
                                this.f95543Z.close();
                                canvas.drawPath(this.f95543Z, this.f95538U);
                            }
                            f28 = f28;
                            fFloatValue = fFloatValue;
                        } else {
                            canvas.drawLine(f28, fFloatValue, f24, fFloatValue, this.f95539V);
                        }
                        if (this.f95533P <= this.f95536S) {
                            f19 = fAbs;
                            f20 = fFloatValue;
                            f21 = fFloatValue3;
                            f22 = fFloatValue4;
                        } else if (o()) {
                            f19 = fAbs;
                            canvas.drawLine(f19, fFloatValue4, fAbs, fFloatValue2, this.f95539V);
                            f22 = fFloatValue4;
                            f20 = fFloatValue;
                            f21 = fFloatValue3;
                        } else {
                            f19 = fAbs;
                            f22 = fFloatValue4;
                            float f33 = fFloatValue;
                            canvas.drawLine(f19, fFloatValue3, f19, f33, this.f95539V);
                            f21 = fFloatValue3;
                            f20 = f33;
                        }
                        float f34 = f19;
                        if (this.f95535R < this.f95534Q) {
                            if (o()) {
                                canvas.drawLine(f34, f20, f34, f21, this.f95539V);
                            } else {
                                canvas.drawLine(f34, fFloatValue2, f34, f22, this.f95539V);
                            }
                        }
                        f13 = f24;
                    } else if (d11 == d12) {
                        float f35 = this.f95530M;
                        Paint paint3 = this.f95542Y;
                        int iIntValue3 = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str3 = (String) map2.get(strA)) == null || (numP3 = Ah.w.p(str3)) == null) ? this.f95527J : numP3.intValue();
                        paint3.setColor(iIntValue3);
                        this.f95542Y.setStrokeWidth(2.0f);
                        float f36 = f35;
                        canvas.drawLine(f28, f36, f24, f35, this.f95542Y);
                        double d13 = this.f95533P;
                        if (d13 > this.f95536S) {
                            f18 = fAbs;
                            canvas.drawLine(f18, abstractC2759w0.P(d13), fAbs, f36, this.f95542Y);
                            f36 = f36;
                        } else {
                            f18 = fAbs;
                        }
                        double d14 = this.f95534Q;
                        f13 = f24;
                        double d15 = this.f95535R;
                        if (d14 > d15) {
                            canvas.drawLine(f18, f36, f18, abstractC2759w0.P(d15), this.f95542Y);
                        }
                    } else {
                        f13 = f24;
                        this.f95541X.setStrokeWidth(3.0f);
                        float fFloatValue5 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95532O), Float.valueOf(this.f95530M))).floatValue();
                        float fFloatValue6 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95530M), Float.valueOf(this.f95532O))).floatValue();
                        float fFloatValue7 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95531N), Float.valueOf(this.f95529L))).floatValue();
                        float f37 = fFloatValue5;
                        float fFloatValue8 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95529L), Float.valueOf(this.f95531N))).floatValue();
                        boolean z12 = fFloatValue6 - f37 >= 1.0f;
                        Paint paint4 = this.f95541X;
                        int iIntValue4 = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str2 = (String) map2.get(strA)) == null || (numP2 = Ah.w.p(str2)) == null) ? this.f95528K : numP2.intValue();
                        paint4.setColor(iIntValue4);
                        Paint paint5 = this.f95540W;
                        int iIntValue5 = (str11 == null || str11.length() == 0 || AbstractC7609s.f(str11, "nullValue") || (str = (String) map2.get(str11)) == null || (numP = Ah.w.p(str)) == null) ? this.f95528K : numP.intValue();
                        paint5.setColor(iIntValue5);
                        if (z12) {
                            canvas.drawRect(f28, f37, f13, fFloatValue6, this.f95541X);
                            if (z10) {
                                float f38 = f28 - f25;
                                float f39 = f37 - f25;
                                this.f95543Z.moveTo(f38, f39);
                                float f40 = f13 + f25;
                                this.f95543Z.lineTo(f40, f39);
                                float f41 = fFloatValue6 + f25;
                                this.f95543Z.lineTo(f40, f41);
                                this.f95543Z.lineTo(f38, f41);
                                this.f95543Z.close();
                                canvas.drawPath(this.f95543Z, this.f95538U);
                            }
                            f28 = f28;
                            f37 = f37;
                            f13 = f13;
                        } else {
                            canvas.drawLine(f28, f37, f13, f37, this.f95541X);
                        }
                        if (this.f95533P <= this.f95534Q) {
                            f14 = fAbs;
                            f15 = fFloatValue7;
                            f16 = f37;
                            f17 = fFloatValue8;
                        } else if (o()) {
                            f14 = fAbs;
                            canvas.drawLine(f14, fFloatValue8, fAbs, fFloatValue6, this.f95541X);
                            f17 = fFloatValue8;
                            f15 = fFloatValue7;
                            f16 = f37;
                        } else {
                            f14 = fAbs;
                            f17 = fFloatValue8;
                            float f42 = f37;
                            canvas.drawLine(f14, fFloatValue7, f14, f42, this.f95541X);
                            f15 = fFloatValue7;
                            f16 = f42;
                        }
                        float f43 = f14;
                        if (this.f95535R < this.f95536S) {
                            if (o()) {
                                canvas.drawLine(f43, f16, f43, f15, this.f95541X);
                            } else {
                                canvas.drawLine(f43, fFloatValue6, f43, f17, this.f95541X);
                            }
                        }
                    }
                } else {
                    f13 = f24;
                }
                f27 = f28 + f11;
                f24 = f13 + f11;
            }
        }
    }

    public final void w(Canvas canvas, float f10, float f11, float f12, ScriptIndicAction scriptIndicAction, AbstractC2759w0 abstractC2759w0, int i10, int i11, sp.aicoin_kline.core.indicator.config.F f13, Map map) {
        int iAbs;
        long jH;
        double d10;
        int iA;
        float f14;
        Double dN;
        Integer numP;
        Double dN2;
        Long lR;
        int i12;
        Double dN3;
        float f15 = (f11 / 6) - f12;
        float f16 = f15 + f10;
        String histBase = scriptIndicAction.getHistBase();
        float fP = abstractC2759w0.P((histBase == null || (dN3 = Ah.v.n(histBase)) == null) ? 0.0d : dN3.doubleValue());
        int intOffset = scriptIndicAction.getIntOffset();
        String strA = kk.f.a(scriptIndicAction, new StringBuilder(), "Value");
        if (intOffset < 0) {
            iAbs = Math.abs(intOffset) + i11;
            float f17 = intOffset * f11;
            f15 += f17;
            f16 += f17;
        } else {
            iAbs = i11;
        }
        int i13 = intOffset > 0 ? i10 - intOffset : i10;
        int intShowLast = scriptIndicAction.getIntShowLast();
        int i14 = (1 > intShowLast || intShowLast >= (i12 = this.f95544a0)) ? -1 : i12 - intShowLast;
        try {
            y1 y1Var = this.f95551n;
            jH = y1Var != null ? y1Var.H(i14) : 0L;
        } catch (Exception unused) {
        }
        while (i13 < iAbs) {
            y1 y1Var2 = this.f95551n;
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
                double dDoubleValue = (str2 == null || (dN2 = Ah.v.n(str2)) == null) ? 0.0d : dN2.doubleValue();
                if (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue")) {
                    d10 = 0.0d;
                    iA = dDoubleValue >= 0.0d ? this.f95527J : this.f95528K;
                } else {
                    String str3 = (String) map2.get(strA);
                    if (str3 == null || (numP = Ah.w.p(str3)) == null) {
                        d10 = 0.0d;
                        iA = f13.u()[this.f95526I].a();
                    } else {
                        iA = numP.intValue();
                        d10 = 0.0d;
                    }
                }
                this.f95561x.setColor(iA);
                if (i14 <= 0 || jLongValue >= jH) {
                    if (dDoubleValue == d10) {
                        float fQ = (abstractC2759w0.u() == d10 && abstractC2759w0.v() == d10) ? abstractC2759w0.q() + fP : fP;
                        f14 = f15;
                        canvas.drawLine(f14, fQ, f16, fQ, this.f95561x);
                        i14 = i14;
                    } else {
                        String series2 = scriptIndicAction.getSeries();
                        if (series2 == null) {
                            series2 = "0";
                        }
                        String str4 = (String) map2.get(series2);
                        float fP2 = abstractC2759w0.P((str4 == null || (dN = Ah.v.n(str4)) == null) ? d10 : dN.doubleValue());
                        if (Math.abs(fP - fP2) < 1.0f) {
                            canvas.drawLine(f15, fP, f16, fP, this.f95561x);
                        } else {
                            i14 = i14;
                            f14 = f15;
                            float fAbs = (Math.abs(f16 - f14) / 2) + f14;
                            float f18 = fP;
                            canvas.drawLine(fAbs, fP2, fAbs, f18, this.f95561x);
                            fP = f18;
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
        float f15;
        float f16;
        PointF pointF;
        String str;
        Integer numP;
        Double dN;
        Double dN2;
        Long lR;
        int i12;
        Path path2 = this.f95562y;
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
        int i14 = (1 > intShowLast || intShowLast >= (i12 = this.f95544a0)) ? -1 : i12 - intShowLast;
        try {
            y1 y1Var = this.f95551n;
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
            y1 y1Var2 = this.f95551n;
            if (y1Var2 == null || (map2 = (Map) map.get(String.valueOf(y1Var2.H(i13)))) == null) {
                f14 = fFloatValue;
                i13 = i13;
            } else {
                String str2 = (String) map2.get("time");
                long jLongValue = (str2 == null || (lR = Ah.w.r(str2)) == null) ? 0L : lR.longValue();
                if (i14 <= 0 || jLongValue >= jH) {
                    String str3 = (String) map2.get(scriptIndicAction.getSeries1());
                    double dDoubleValue = (str3 == null || (dN2 = Ah.v.n(str3)) == null) ? 0.0d : dN2.doubleValue();
                    f14 = fFloatValue;
                    String str4 = (String) map2.get(scriptIndicAction.getSeries2());
                    double dDoubleValue2 = (str4 == null || (dN = Ah.v.n(str4)) == null) ? 0.0d : dN.doubleValue();
                    if (dDoubleValue == 0.0d || dDoubleValue2 == 0.0d) {
                        f17 += f11;
                        z10 = true;
                    } else {
                        float fP = abstractC2759w0.P(dDoubleValue);
                        float fP2 = abstractC2759w0.P(dDoubleValue2);
                        int iA = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str = (String) map2.get(strA)) == null || (numP = Ah.w.p(str)) == null) ? f12.u()[this.f95526I].a() : numP.intValue();
                        int i15 = iA;
                        if (z10) {
                            f15 = fP2;
                            f16 = fP;
                        } else {
                            if ((f19 <= f20 || fP >= fP2) && (f19 >= f20 || fP <= fP2)) {
                                pointF = null;
                            } else {
                                float f21 = f17 - f18;
                                float f22 = ((((f19 - f20) - (fP - fP2)) / (2 * f21)) * f21) + f18;
                                pointF = new PointF(f22, ((f22 - f18) * ((fP - f19) / f21)) + f19);
                            }
                            if (pointF != null) {
                                float f23 = pointF.x;
                                float f24 = pointF.y;
                                arrayList.add(new a(f18, f19, f20, f23, f24, f24, f19 < f20, i15));
                                float f25 = pointF.x;
                                float f26 = pointF.y;
                                f15 = fP2;
                                f16 = fP;
                                arrayList.add(new a(f25, f26, f26, f17, f16, f15, fP < fP2, i15));
                            } else {
                                f15 = fP2;
                                f16 = fP;
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
        }
        float f27 = fFloatValue;
        for (a aVar : arrayList) {
            Path path3 = this.f95562y;
            if (path3 != null) {
                path3.reset();
            }
            float fA = aVar.a();
            float fB = aVar.b();
            float fC = aVar.c();
            float fD = aVar.d();
            float fE = aVar.e();
            float f28 = aVar.f();
            boolean zG = aVar.g();
            float f29 = zG ? fB : fC;
            if (zG) {
                fB = fC;
            }
            float f30 = zG ? fE : f28;
            if (zG) {
                fE = f28;
            }
            Path path4 = this.f95562y;
            if (path4 != null) {
                path4.moveTo(fA, f29);
                hk.a.f98027a.d(fA, f29, fD - Xj.a.a(0.7f), f30, f27, path4);
                path4.lineTo(fD - Xj.a.a(0.7f), fE);
                path4.lineTo(fA, fB);
                path4.close();
            }
            Paint paint = this.f95563z;
            if (paint != null) {
                paint.setColor(aVar.h());
            }
            Paint paint2 = this.f95563z;
            if (paint2 != null && (path = this.f95562y) != null) {
                canvas.drawPath(path, paint2);
            }
        }
    }

    public final void y(Canvas canvas, AbstractC2759w0 abstractC2759w0, double d10, String str) {
        Ah.j jVarC;
        Ah.j.b bVarA;
        if (this.f95550m != null) {
            float fP = abstractC2759w0.P(d10);
            Path path = this.f95545b0;
            path.reset();
            path.moveTo(this.f95550m.u(), fP);
            path.lineTo(this.f95550m.y(), fP);
            if (str.length() != 0 && (jVarC = Ah.l.c(new Ah.l("rgba\\((\\d+),(\\d+),(\\d+),((?:\\d+(?:\\.\\d*)?|\\.\\d+))\\)"), str, 0, 2, null)) != null && (bVarA = jVarC.a()) != null) {
                Double dN = Ah.v.n((String) kk.j.a(bVarA, 4));
                if (((float) ((dN != null ? dN.doubleValue() : 0.0d) * ((double) 255))) == 0.0f) {
                    return;
                }
            }
            canvas.drawPath(this.f95545b0, this.f95546c0);
        }
    }

    public final void z(Canvas canvas, ScriptIndicAction scriptIndicAction, AbstractC2759w0 abstractC2759w0, sp.aicoin_kline.core.indicator.config.F f10, Map map) {
        String str;
        Map linkedHashMap;
        String str2;
        Integer numP;
        Double dN;
        Double dN2;
        Long lR;
        Long lR2;
        String str3;
        Paint paint;
        String strA = kk.f.a(scriptIndicAction, new StringBuilder(), "Value");
        if (scriptIndicAction.getOutput().getLineWidth() != null && (paint = this.f95555r) != null) {
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
        Paint paint2 = this.f95555r;
        if (paint2 != null) {
            paint2.setPathEffect(new DashPathEffect(new float[]{fFloatValue, fFloatValue2}, 0.0f));
        }
        y1 y1Var = this.f95551n;
        long jLongValue = 0;
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
        String str5 = (String) kk.g.a(scriptIndicAction, new StringBuilder(), "AfterTransTime1", linkedHashMap);
        long jLongValue2 = (str5 == null || (lR2 = Ah.w.r(str5)) == null) ? 0L : lR2.longValue();
        String str6 = (String) kk.g.a(scriptIndicAction, new StringBuilder(), "AfterTransTime2", linkedHashMap);
        if (str6 != null && (lR = Ah.w.r(str6)) != null) {
            jLongValue = lR.longValue();
        }
        String str7 = (String) kk.g.a(scriptIndicAction, new StringBuilder(), "AfterTransValue1", linkedHashMap);
        double dDoubleValue = 0.0d;
        double dDoubleValue2 = (str7 == null || (dN2 = Ah.v.n(str7)) == null) ? 0.0d : dN2.doubleValue();
        String str8 = (String) kk.g.a(scriptIndicAction, new StringBuilder(), "AfterTransValue2", linkedHashMap);
        if (str8 != null && (dN = Ah.v.n(str8)) != null) {
            dDoubleValue = dN.doubleValue();
        }
        C2702d c2702d = this.f95550m;
        int iU = c2702d != null ? c2702d.u() : 0;
        y1 y1Var2 = this.f95551n;
        float fW = iU + (y1Var2 != null ? y1Var2.w() : 0.0f);
        y1 y1Var3 = this.f95551n;
        float fJ = (y1Var3 != null ? y1Var3.j(jLongValue2 * ((long) 1000)) : 0.0f) - fW;
        y1 y1Var4 = this.f95551n;
        float fJ2 = (y1Var4 != null ? y1Var4.j(((long) 1000) * jLongValue) : 0.0f) - fW;
        float fP = abstractC2759w0.P(dDoubleValue2);
        float fP2 = abstractC2759w0.P(dDoubleValue);
        int iA = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str2 = (String) linkedHashMap.get(strA)) == null || (numP = Ah.w.p(str2)) == null) ? f10.u()[this.f95526I].a() : numP.intValue();
        Paint paint3 = this.f95555r;
        if (paint3 != null) {
            paint3.setColor(iA);
        }
        Paint paint4 = this.f95555r;
        if (paint4 != null) {
            canvas.drawRect(fJ, fP, fJ2, fP2, paint4);
        }
    }
}
