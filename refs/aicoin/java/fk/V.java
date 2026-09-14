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
import gk.K0;
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
public final class V extends AbstractC2744r0 {

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public Paint f95205A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public final Path f95206B;

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public final Path f95207C;

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public float f95208D;

    /* JADX INFO: renamed from: E, reason: collision with root package name */
    public float f95209E;

    /* JADX INFO: renamed from: F, reason: collision with root package name */
    public float f95210F;

    /* JADX INFO: renamed from: G, reason: collision with root package name */
    public float f95211G;

    /* JADX INFO: renamed from: H, reason: collision with root package name */
    public float f95212H;

    /* JADX INFO: renamed from: I, reason: collision with root package name */
    public int f95213I;

    /* JADX INFO: renamed from: J, reason: collision with root package name */
    public int f95214J;

    /* JADX INFO: renamed from: K, reason: collision with root package name */
    public int f95215K;

    /* JADX INFO: renamed from: L, reason: collision with root package name */
    public float f95216L;

    /* JADX INFO: renamed from: M, reason: collision with root package name */
    public float f95217M;

    /* JADX INFO: renamed from: N, reason: collision with root package name */
    public float f95218N;

    /* JADX INFO: renamed from: O, reason: collision with root package name */
    public float f95219O;

    /* JADX INFO: renamed from: P, reason: collision with root package name */
    public double f95220P;

    /* JADX INFO: renamed from: Q, reason: collision with root package name */
    public double f95221Q;

    /* JADX INFO: renamed from: R, reason: collision with root package name */
    public double f95222R;

    /* JADX INFO: renamed from: S, reason: collision with root package name */
    public double f95223S;

    /* JADX INFO: renamed from: T, reason: collision with root package name */
    public final Paint f95224T;

    /* JADX INFO: renamed from: U, reason: collision with root package name */
    public final Paint f95225U;

    /* JADX INFO: renamed from: V, reason: collision with root package name */
    public final Paint f95226V;

    /* JADX INFO: renamed from: W, reason: collision with root package name */
    public final Paint f95227W;

    /* JADX INFO: renamed from: X, reason: collision with root package name */
    public final Paint f95228X;

    /* JADX INFO: renamed from: Y, reason: collision with root package name */
    public final Paint f95229Y;

    /* JADX INFO: renamed from: Z, reason: collision with root package name */
    public final Path f95230Z;

    /* JADX INFO: renamed from: a0, reason: collision with root package name */
    public int f95231a0;

    /* JADX INFO: renamed from: b0, reason: collision with root package name */
    public final Path f95232b0;

    /* JADX INFO: renamed from: c0, reason: collision with root package name */
    public final Paint f95233c0;

    /* JADX INFO: renamed from: d0, reason: collision with root package name */
    public final PointF f95234d0;

    /* JADX INFO: renamed from: e0, reason: collision with root package name */
    public final PointF f95235e0;

    /* JADX INFO: renamed from: f0, reason: collision with root package name */
    public final String f95236f0;

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final boolean f95237l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public C2702d f95238m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public y1 f95239n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public AbstractC2759w0 f95240o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public K0 f95241p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public Path f95242q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public Paint f95243r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public Path f95244s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public Paint f95245t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public Paint f95246u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public final Rect f95247v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public Paint f95248w;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public Paint f95249x;

    /* JADX INFO: renamed from: y, reason: collision with root package name */
    public Path f95250y;

    /* JADX INFO: renamed from: z, reason: collision with root package name */
    public Paint f95251z;

    public static final class a {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public final float f95252a;

        /* JADX INFO: renamed from: b, reason: collision with root package name */
        public final float f95253b;

        /* JADX INFO: renamed from: c, reason: collision with root package name */
        public final float f95254c;

        /* JADX INFO: renamed from: d, reason: collision with root package name */
        public final float f95255d;

        /* JADX INFO: renamed from: e, reason: collision with root package name */
        public final float f95256e;

        /* JADX INFO: renamed from: f, reason: collision with root package name */
        public final float f95257f;

        /* JADX INFO: renamed from: g, reason: collision with root package name */
        public final boolean f95258g;

        /* JADX INFO: renamed from: h, reason: collision with root package name */
        public final int f95259h;

        public a(float f10, float f11, float f12, float f13, float f14, float f15, boolean z10, int i10) {
            this.f95252a = f10;
            this.f95253b = f11;
            this.f95254c = f12;
            this.f95255d = f13;
            this.f95256e = f14;
            this.f95257f = f15;
            this.f95258g = z10;
            this.f95259h = i10;
        }

        public final float a() {
            return this.f95252a;
        }

        public final float b() {
            return this.f95253b;
        }

        public final float c() {
            return this.f95254c;
        }

        public final float d() {
            return this.f95255d;
        }

        public final float e() {
            return this.f95256e;
        }

        public boolean equals(Object obj) {
            if (this == obj) {
                return true;
            }
            if (!(obj instanceof a)) {
                return false;
            }
            a aVar = (a) obj;
            return Float.compare(this.f95252a, aVar.f95252a) == 0 && Float.compare(this.f95253b, aVar.f95253b) == 0 && Float.compare(this.f95254c, aVar.f95254c) == 0 && Float.compare(this.f95255d, aVar.f95255d) == 0 && Float.compare(this.f95256e, aVar.f95256e) == 0 && Float.compare(this.f95257f, aVar.f95257f) == 0 && this.f95258g == aVar.f95258g && this.f95259h == aVar.f95259h;
        }

        public final float f() {
            return this.f95257f;
        }

        public final boolean g() {
            return this.f95258g;
        }

        public final int h() {
            return this.f95259h;
        }

        public int hashCode() {
            return Integer.hashCode(this.f95259h) + ((Boolean.hashCode(this.f95258g) + kk.a.a(this.f95257f, kk.a.a(this.f95256e, kk.a.a(this.f95255d, kk.a.a(this.f95254c, kk.a.a(this.f95253b, Float.hashCode(this.f95252a) * 31, 31), 31), 31), 31), 31)) * 31);
        }

        public String toString() {
            return "FillSegment(startX=" + this.f95252a + ", startY1=" + this.f95253b + ", startY2=" + this.f95254c + ", endX=" + this.f95255d + ", endY1=" + this.f95256e + ", endY2=" + this.f95257f + ", isFirstLineOnTop=" + this.f95258g + ", color=" + this.f95259h + ')';
        }
    }

    public V(C2732n c2732n, String str, String str2, boolean z10) {
        super(c2732n, str);
        this.f95237l = z10;
        s(z10);
        this.f95247v = new Rect();
        new Rect();
        this.f95248w = new Paint();
        this.f95249x = new Paint();
        this.f95205A = new Paint();
        new Paint();
        this.f95206B = new Path();
        this.f95207C = new Path();
        this.f95208D = 15.0f;
        this.f95209E = 16.0f;
        this.f95210F = 15.0f;
        this.f95211G = 8.0f;
        this.f95212H = 8.0f;
        this.f95214J = -16711936;
        this.f95215K = -65536;
        this.f95224T = new Paint();
        this.f95225U = new Paint();
        this.f95226V = new Paint();
        this.f95227W = new Paint();
        this.f95228X = new Paint();
        this.f95229Y = new Paint();
        this.f95230Z = new Path();
        this.f95231a0 = XGPushManager.MAX_TAG_SIZE;
        this.f95232b0 = new Path();
        this.f95233c0 = new Paint();
        this.f95234d0 = new PointF();
        this.f95235e0 = new PointF();
        this.f95236f0 = str2;
    }

    public final void A(Canvas canvas, ScriptIndicAction scriptIndicAction, Map map, float f10, float f11, int i10, sp.aicoin_kline.core.indicator.config.F f12) {
        String str;
        Integer numP;
        String text = scriptIndicAction.getOutput().getText();
        if (text == null) {
            text = "";
        }
        if (text.length() == 0 || this.f95246u == null) {
            return;
        }
        String bgColor = scriptIndicAction.getOutput().getBgColor();
        if (bgColor != null && bgColor.length() != 0) {
            String str2 = scriptIndicAction.getOutput().getBgColor() + "BGValue";
            Paint paint = this.f95246u;
            if (paint != null) {
                int iA = (str2 == null || str2.length() == 0 || (str = (String) map.get(str2)) == null || (numP = Ah.w.p(str)) == null) ? f12.u()[this.f95213I].a() : numP.intValue();
                paint.setColor(iA);
            }
            this.f95246u.getTextBounds(text, 0, text.length(), this.f95247v);
            float fWidth = this.f95247v.width() / 2;
            canvas.drawRoundRect((f10 - Xj.a.a(4.0f)) - fWidth, f11 - (this.f95247v.height() + 10), (Xj.a.a(6.0f) + (f10 + this.f95247v.width())) - fWidth, (this.f95247v.height() / 3) + f11 + 4.0f, 6.0f, 6.0f, this.f95246u);
        }
        int iWidth = this.f95247v.width() / 2;
        Paint paint2 = this.f95246u;
        if (paint2 != null) {
            paint2.setColor(i10);
        }
        canvas.drawText(text, f10 - iWidth, f11, this.f95246u);
    }

    /* JADX WARN: Code duplicated, block: B:72:0x012c  */
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
        int i14 = (1 > intShowLast || intShowLast >= (i12 = this.f95231a0)) ? -1 : i12 - intShowLast;
        try {
            y1 y1Var = this.f95239n;
            jH = y1Var != null ? y1Var.H(i14) : 0L;
        } catch (Exception unused) {
        }
        while (i13 < iAbs) {
            y1 y1Var2 = this.f95239n;
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
                double dDoubleValue = (str5 == null || (dN4 = Ah.v.n(str5)) == null) ? 0.0d : dN4.doubleValue();
                this.f95221Q = dDoubleValue;
                this.f95217M = abstractC2759w0.P(dDoubleValue);
                String high = scriptIndicAction.getHigh();
                if (high == null) {
                    high = "";
                }
                String str6 = (String) map2.get(high);
                double dDoubleValue2 = (str6 == null || (dN3 = Ah.v.n(str6)) == null) ? 0.0d : dN3.doubleValue();
                this.f95220P = dDoubleValue2;
                this.f95216L = abstractC2759w0.P(dDoubleValue2);
                String low = scriptIndicAction.getLow();
                if (low == null) {
                    low = "";
                }
                String str7 = (String) map2.get(low);
                double dDoubleValue3 = (str7 == null || (dN2 = Ah.v.n(str7)) == null) ? 0.0d : dN2.doubleValue();
                this.f95222R = dDoubleValue3;
                this.f95218N = abstractC2759w0.P(dDoubleValue3);
                String close = scriptIndicAction.getClose();
                if (close == null) {
                    close = "";
                }
                String str8 = (String) map2.get(close);
                double dDoubleValue4 = (str8 == null || (dN = Ah.v.n(str8)) == null) ? 0.0d : dN.doubleValue();
                this.f95223S = dDoubleValue4;
                this.f95219O = abstractC2759w0.P(dDoubleValue4);
                String strA = kk.f.a(scriptIndicAction, new StringBuilder(), "Value");
                float f19 = f16;
                f13 = f17;
                if (this.f95221Q == 0.0d || this.f95220P == 0.0d || this.f95222R == 0.0d || this.f95223S == 0.0d) {
                    f14 = f19;
                } else {
                    float fAbs = (Math.abs(f19 - f15) / f13) + f15;
                    if (i14 <= 0 || jLongValue >= jH) {
                        double d10 = this.f95223S;
                        double d11 = this.f95221Q;
                        if (d10 > d11) {
                            this.f95226V.setStrokeWidth(3.0f);
                            Paint paint = this.f95226V;
                            int iIntValue = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str3 = (String) map2.get(strA)) == null || (numP3 = Ah.w.p(str3)) == null) ? this.f95214J : numP3.intValue();
                            paint.setColor(iIntValue);
                            canvas.drawLine(fAbs, this.f95216L, fAbs, this.f95218N, this.f95226V);
                            float f20 = this.f95217M;
                            canvas.drawLine(f15, f20, fAbs, f20, this.f95226V);
                            float f21 = this.f95219O;
                            f14 = f19;
                            canvas.drawLine(fAbs, f21, f14, f21, this.f95226V);
                        } else if (d10 == d11) {
                            this.f95229Y.setStrokeWidth(2.0f);
                            Paint paint2 = this.f95229Y;
                            int iIntValue2 = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str2 = (String) map2.get(strA)) == null || (numP2 = Ah.w.p(str2)) == null) ? this.f95214J : numP2.intValue();
                            paint2.setColor(iIntValue2);
                            canvas.drawLine(fAbs, this.f95216L, fAbs, this.f95218N, this.f95229Y);
                            float f22 = this.f95217M;
                            canvas.drawLine(f15, f22, fAbs, f22, this.f95229Y);
                            float f23 = this.f95219O;
                            f14 = f19;
                            canvas.drawLine(fAbs, f23, f14, f23, this.f95229Y);
                        } else {
                            this.f95228X.setStrokeWidth(3.0f);
                            Paint paint3 = this.f95228X;
                            int iIntValue3 = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str = (String) map2.get(strA)) == null || (numP = Ah.w.p(str)) == null) ? this.f95215K : numP.intValue();
                            paint3.setColor(iIntValue3);
                            canvas.drawLine(fAbs, this.f95216L, fAbs, this.f95218N, this.f95228X);
                            float f24 = this.f95217M;
                            canvas.drawLine(f15, f24, fAbs, f24, this.f95228X);
                            float f25 = this.f95219O;
                            f14 = f19;
                            canvas.drawLine(fAbs, f25, f14, f25, this.f95228X);
                        }
                    } else {
                        f14 = f19;
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
        float[] fArr;
        long jH;
        Paint paint;
        Map map2;
        float f13;
        Paint paint2;
        String str;
        Integer numP;
        Long lR;
        Double dN;
        int i12;
        Float fO;
        Float fO2;
        Integer numP2;
        Path path = this.f95242q;
        if (path != null) {
            path.reset();
        }
        Path path2 = this.f95244s;
        if (path2 != null) {
            path2.reset();
        }
        String offset = scriptIndicAction.getOffset();
        int iIntValue = (offset == null || (numP2 = Ah.w.p(offset)) == null) ? 0 : numP2.intValue();
        int i13 = iIntValue > 0 ? i10 - iIntValue : i10;
        int iAbs = iIntValue < 0 ? Math.abs(iIntValue) + i11 : i11;
        float f14 = iIntValue < 0 ? (iIntValue * f11) + f10 : f10;
        float fFloatValue = ((Number) p162hb.e.c(o(), Float.valueOf(abstractC2759w0.P(abstractC2759w0.v())), Float.valueOf(abstractC2759w0.P(abstractC2759w0.u())))).floatValue();
        float floatLineWidth = scriptIndicAction.getOutput().getFloatLineWidth();
        Paint paint3 = this.f95243r;
        if (paint3 != null) {
            paint3.setStrokeWidth(floatLineWidth);
        }
        Paint paint4 = this.f95245t;
        if (paint4 != null) {
            paint4.setStrokeWidth(floatLineWidth);
        }
        List<String> lineDash = scriptIndicAction.getOutput().getLineDash();
        float f15 = 0.0f;
        if (lineDash != null) {
            String str2 = (String) Sf.z.q0(lineDash);
            float fFloatValue2 = (str2 == null || (fO2 = Ah.v.o(str2)) == null) ? 0.0f : fO2.floatValue();
            String str3 = (String) Sf.z.D0(lineDash);
            fArr = new float[]{fFloatValue2, (str3 == null || (fO = Ah.v.o(str3)) == null) ? 0.0f : fO.floatValue()};
        } else {
            fArr = new float[]{0.0f, 0.0f};
        }
        Paint paint5 = this.f95243r;
        if (paint5 != null) {
            paint5.setPathEffect(new DashPathEffect(fArr, 0.0f));
        }
        Paint paint6 = this.f95245t;
        if (paint6 != null) {
            paint6.setPathEffect(new DashPathEffect(fArr, 0.0f));
        }
        int intShowLast = scriptIndicAction.getIntShowLast();
        int i14 = (1 > intShowLast || intShowLast >= (i12 = this.f95231a0)) ? -1 : i12 - intShowLast;
        try {
            y1 y1Var = this.f95239n;
            jH = y1Var != null ? y1Var.H(i14) : 0L;
        } catch (Exception unused) {
        }
        Qf.p pVar = new Qf.p(Integer.valueOf(i14), Long.valueOf(jH));
        int iIntValue2 = ((Number) pVar.a()).intValue();
        long jLongValue = ((Number) pVar.b()).longValue();
        StringBuilder sb2 = new StringBuilder();
        ActionOutput output = scriptIndicAction.getOutput();
        sb2.append(output != null ? output.getColor() : null);
        sb2.append("Value");
        String string = sb2.toString();
        float f16 = f14;
        int i15 = -13643086;
        float f17 = 0.0f;
        boolean z10 = true;
        while (i13 < iAbs) {
            y1 y1Var2 = this.f95239n;
            if (y1Var2 == null || (map2 = (Map) map.get(String.valueOf(y1Var2.H(i13)))) == null) {
                i13 = i13;
            } else {
                String series = scriptIndicAction.getSeries();
                if (series == null) {
                    series = "0";
                }
                String str4 = (String) map2.get(series);
                boolean zF = AbstractC7609s.f(series, "0");
                double dDoubleValue = (str4 == null || str4.length() <= 0 || (dN = Ah.v.n(str4)) == null) ? 0.0d : dN.doubleValue();
                if (dDoubleValue == 0.0d && (!zF || str4 == null || str4.length() == 0)) {
                    f16 += f11;
                    z10 = true;
                } else {
                    String str5 = (String) map2.get("time");
                    long jLongValue2 = (str5 == null || (lR = Ah.w.r(str5)) == null) ? 0L : lR.longValue();
                    if (iIntValue2 <= 0 || jLongValue2 >= jLongValue) {
                        boolean z11 = this.f95237l;
                        float fQ = z11 ? abstractC2759w0.Q(dDoubleValue, z11) : abstractC2759w0.P(dDoubleValue);
                        int iA = (string == null || string.length() == 0 || AbstractC7609s.f(string, "nullValue") || (str = (String) map2.get(string)) == null || (numP = Ah.w.p(str)) == null) ? f12.u()[this.f95213I].a() : numP.intValue();
                        if (z10) {
                            Paint paint7 = this.f95243r;
                            if (paint7 != null) {
                                paint7.setColor(iA);
                            }
                            Path path3 = this.f95242q;
                            if (path3 != null) {
                                path3.moveTo(f16, fQ);
                            }
                            f13 = fQ;
                            i15 = iA;
                            z10 = false;
                        } else if (iA != i15) {
                            Path path4 = this.f95242q;
                            if (path4 != null && (paint2 = this.f95243r) != null) {
                                canvas.drawPath(path4, paint2);
                            }
                            Path path5 = this.f95242q;
                            if (path5 != null) {
                                path5.reset();
                            }
                            Paint paint8 = this.f95243r;
                            if (paint8 != null) {
                                paint8.setColor(iA);
                            }
                            Path path6 = this.f95242q;
                            if (path6 != null) {
                                path6.moveTo(f15, f17);
                            }
                            f13 = fQ;
                            hk.a.f98027a.d(f15, f17, f16, f13, fFloatValue, this.f95242q);
                            i15 = iA;
                        } else {
                            f13 = fQ;
                            Paint paint9 = this.f95243r;
                            if (paint9 != null) {
                                paint9.setColor(iA);
                            }
                            hk.a.f98027a.d(f15, f17, f16, f13, fFloatValue, this.f95242q);
                        }
                        f15 = f16;
                        f17 = f13;
                        f16 += f11;
                    } else {
                        f16 += f11;
                    }
                }
            }
            i13++;
        }
        Path path7 = this.f95242q;
        if (path7 == null || (paint = this.f95243r) == null) {
            return;
        }
        canvas.drawPath(path7, paint);
    }

    public final void D(Canvas canvas, ScriptIndicAction scriptIndicAction, AbstractC2759w0 abstractC2759w0, sp.aicoin_kline.core.indicator.config.F f10, Map map) {
        Map linkedHashMap;
        Double dN;
        Long lR;
        String str;
        Integer numP;
        y1 y1Var = this.f95239n;
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
        int iA = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str = (String) map2.get(strA)) == null || (numP = Ah.w.p(str)) == null) ? f10.u()[this.f95213I].a() : numP.intValue();
        int i10 = iA;
        String fontSize = scriptIndicAction.getOutput().getFontSize();
        if (fontSize != null && fontSize.length() != 0) {
            float floatFontSize = scriptIndicAction.getOutput().getFloatFontSize();
            Paint paint = this.f95246u;
            if (paint != null) {
                paint.setTextSize(Xj.a.c(floatFontSize));
            }
        }
        C2702d c2702d = this.f95238m;
        int i11 = 0;
        int iU = c2702d != null ? c2702d.u() : 0;
        y1 y1Var2 = this.f95239n;
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
            y1 y1Var3 = this.f95239n;
            A(canvas, scriptIndicAction, map2, (y1Var3 != null ? y1Var3.j(jLongValue * ((long) 1000)) : 0.0f) - fW, abstractC2759w0.P(dDoubleValue), i10, f10);
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
                    y1 y1Var4 = this.f95239n;
                    A(canvas, scriptIndicAction, map2, (y1Var4 != null ? y1Var4.j(jLongValue2 * ((long) 1000)) : 0.0f) - fW, abstractC2759w0.P(dDoubleValue2), i10, f10);
                    j10 = j10;
                    i11 = 0;
                }
            }
        }
    }

    /* JADX WARN: Code duplicated, block: B:60:0x00ee  */
    public final void E(Canvas canvas, float f10, float f11, ScriptIndicAction scriptIndicAction, AbstractC2759w0 abstractC2759w0, int i10, int i11, sp.aicoin_kline.core.indicator.config.F f12, Map map) {
        boolean z10;
        int i12;
        int i13;
        String str;
        Integer numP;
        String str2;
        Integer numP2;
        Canvas canvas2;
        String str3;
        String str4;
        Integer numP3;
        String str5;
        Integer numP4;
        Double dN;
        Double dN2;
        Double dN3;
        int intOffset = scriptIndicAction.getIntOffset();
        ScriptIndicAction scriptIndicAction2 = scriptIndicAction;
        String strA = kk.f.a(scriptIndicAction2, new StringBuilder(), "Value");
        int intShowLast = scriptIndicAction2.getIntShowLast();
        ArrayList arrayList = new ArrayList();
        double dDoubleValue = 0.0d;
        if (intOffset != 0) {
            List listB = Sf.P.B(map);
            int i14 = 0;
            for (Object obj : listB) {
                int i15 = i14 + 1;
                if (i14 < 0) {
                    Sf.r.x();
                }
                int i16 = i14 - intOffset;
                Map map2 = (Map) ((Qf.p) obj).d();
                String series = scriptIndicAction2.getSeries();
                String str6 = (String) map2.get(series == null ? "0" : series);
                boolean z11 = ((str6 == null || (dN3 = Ah.v.n(str6)) == null) ? 0.0d : dN3.doubleValue()) > 0.0d;
                if (i16 >= 0 && i16 < listB.size() && z11) {
                    arrayList.add(listB.get(i16));
                }
                i14 = i15;
            }
        }
        Map mapZ = intOffset != 0 ? Sf.N.z(Sf.N.v(arrayList)) : map;
        nk.x.f134260a.d(mapZ);
        int i17 = (intShowLast <= 0 || intShowLast >= mapZ.size()) ? 0 : (this.f95231a0 - intShowLast) + intOffset;
        while (i10 < i11) {
            y1 y1Var = this.f95239n;
            Map linkedHashMap = (Map) mapZ.get(String.valueOf(y1Var != null ? Long.valueOf(y1Var.H(i10)) : null));
            if (linkedHashMap == null) {
                linkedHashMap = new LinkedHashMap();
            }
            if (intOffset == 0) {
                Object series2 = scriptIndicAction2.getSeries();
                if (series2 == null) {
                    series2 = "0";
                }
                String str7 = (String) linkedHashMap.get(series2);
                if (((str7 == null || (dN2 = Ah.v.n(str7)) == null) ? dDoubleValue : dN2.doubleValue()) > dDoubleValue) {
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
            String str8 = (String) linkedHashMap.get(refSeries);
            if (str8 != null && (dN = Ah.v.n(str8)) != null) {
                dDoubleValue = dN.doubleValue();
            }
            if (dDoubleValue != dDoubleValue && z10 && i10 >= i17) {
                String text = scriptIndicAction2.getOutput().getText();
                if (text == null) {
                    text = "";
                }
                float fP = abstractC2759w0.P(dDoubleValue);
                int iA = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str5 = (String) linkedHashMap.get(strA)) == null || (numP4 = Ah.w.p(str5)) == null) ? f12.u()[this.f95213I].a() : numP4.intValue();
                int i18 = iA;
                String fontSize = scriptIndicAction2.getOutput().getFontSize();
                if (fontSize != null && fontSize.length() != 0) {
                    float floatFontSize = scriptIndicAction2.getOutput().getFloatFontSize();
                    Paint paint = this.f95246u;
                    if (paint != null) {
                        paint.setTextSize(Xj.a.c(floatFontSize));
                    }
                }
                if (!AbstractC7609s.f(scriptIndicAction2.getOutput().getPlacement(), "bottom")) {
                    i12 = i10;
                    i13 = i17;
                    intOffset = intOffset;
                    String str9 = text;
                    if (AbstractC7609s.f(scriptIndicAction.getOutput().getPlacement(), "center")) {
                        if (this.f95246u != null) {
                            float fA = f10 - Xj.a.a(10.0f);
                            String bgColor = scriptIndicAction.getOutput().getBgColor();
                            if (bgColor != null && bgColor.length() != 0) {
                                String str10 = scriptIndicAction.getOutput().getBgColor() + "BGValue";
                                Paint paint2 = this.f95246u;
                                if (paint2 != null) {
                                    int iA2 = (str10 == null || str10.length() == 0 || (str2 = (String) linkedHashMap.get(str10)) == null || (numP2 = Ah.w.p(str2)) == null) ? f12.u()[this.f95213I].a() : numP2.intValue();
                                    paint2.setColor(iA2);
                                }
                                this.f95246u.getTextBounds(str9, 0, str9.length(), this.f95247v);
                                canvas.drawRoundRect(fA - Xj.a.a(3.0f), fP - this.f95247v.height(), this.f95247v.width() + fA + Xj.a.a(3.0f), (this.f95247v.height() / 2) + fP + Xj.a.a(1.0f), Xj.a.a(3.0f), Xj.a.a(3.0f), this.f95246u);
                            }
                            Paint paint3 = this.f95246u;
                            if (paint3 != null) {
                                paint3.setColor(i18);
                            }
                            canvas.drawText(str9, fA, Xj.a.a(2.0f) + fP, this.f95246u);
                        }
                    } else if (this.f95246u != null) {
                        float fA2 = f10 - Xj.a.a(10.0f);
                        float f13 = fP - 10.0f;
                        String bgColor2 = scriptIndicAction.getOutput().getBgColor();
                        if (bgColor2 != null && bgColor2.length() != 0) {
                            String str11 = scriptIndicAction.getOutput().getBgColor() + "BGValue";
                            Paint paint4 = this.f95246u;
                            if (paint4 != null) {
                                int iA3 = (str11 == null || str11.length() == 0 || (str = (String) linkedHashMap.get(str11)) == null || (numP = Ah.w.p(str)) == null) ? f12.u()[this.f95213I].a() : numP.intValue();
                                paint4.setColor(iA3);
                            }
                            this.f95246u.getTextBounds(str9, 0, str9.length(), this.f95247v);
                            canvas.drawRoundRect(fA2 - Xj.a.a(3.0f), (f13 - this.f95247v.height()) - Xj.a.a(2.0f), this.f95247v.width() + fA2 + Xj.a.a(3.0f), (this.f95247v.height() / 2) + f13, Xj.a.a(3.0f), Xj.a.a(3.0f), this.f95246u);
                        }
                        Paint paint5 = this.f95246u;
                        if (paint5 != null) {
                            paint5.setColor(i18);
                        }
                        canvas.drawText(str9, fA2, f13, this.f95246u);
                    }
                } else if (this.f95246u != null) {
                    float fA3 = f10 - Xj.a.a(10.0f);
                    float f14 = fP + 20.0f;
                    String bgColor3 = scriptIndicAction2.getOutput().getBgColor();
                    if (bgColor3 == null || bgColor3.length() == 0) {
                        i12 = i10;
                        i13 = i17;
                        canvas2 = canvas;
                        str3 = text;
                    } else {
                        int i19 = i10;
                        StringBuilder sb2 = new StringBuilder();
                        int i20 = i17;
                        sb2.append(scriptIndicAction2.getOutput().getBgColor());
                        sb2.append("BGValue");
                        String string = sb2.toString();
                        Paint paint6 = this.f95246u;
                        if (paint6 != null) {
                            int iA4 = (string == null || string.length() == 0 || AbstractC7609s.f(string, "nullBGValue") || (str4 = (String) linkedHashMap.get(string)) == null || (numP3 = Ah.w.p(str4)) == null) ? f12.u()[this.f95213I].a() : numP3.intValue();
                            paint6.setColor(iA4);
                        }
                        this.f95246u.getTextBounds(text, 0, text.length(), this.f95247v);
                        i12 = i19;
                        str3 = text;
                        i13 = i20;
                        canvas2 = canvas;
                        canvas2.drawRoundRect(fA3 - Xj.a.a(3.0f), (f14 - this.f95247v.height()) - Xj.a.a(2.0f), Xj.a.a(3.0f) + this.f95247v.width() + fA3, (this.f95247v.height() / 2) + f14, Xj.a.a(3.0f), Xj.a.a(3.0f), this.f95246u);
                    }
                    Paint paint7 = this.f95246u;
                    if (paint7 != null) {
                        paint7.setColor(i18);
                    }
                    canvas2.drawText(str3, fA3, f14, this.f95246u);
                } else {
                    i12 = i10;
                    i13 = i17;
                    intOffset = intOffset;
                }
            } else {
                i12 = i10;
                i13 = i17;
                intOffset = intOffset;
            }
            f10 += f11;
            scriptIndicAction2 = scriptIndicAction;
            i11 = i11;
            i10 = i12 + 1;
            dDoubleValue = dDoubleValue;
            i17 = i13;
            intOffset = intOffset;
        }
    }

    public final void F(Canvas canvas, ScriptIndicAction scriptIndicAction, AbstractC2759w0 abstractC2759w0, sp.aicoin_kline.core.indicator.config.F f10, Map map) {
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
        Path path2 = this.f95242q;
        if (path2 != null) {
            path2.reset();
        }
        Path path3 = this.f95244s;
        if (path3 != null) {
            path3.reset();
        }
        float fFloatValue = ((Number) p162hb.e.c(this.f95237l, Float.valueOf(abstractC2759w0.P(abstractC2759w0.v())), Float.valueOf(abstractC2759w0.P(abstractC2759w0.u())))).floatValue();
        float fFloatValue2 = ((Number) p162hb.e.c(o(), Float.valueOf(abstractC2759w0.P(abstractC2759w0.u())), Float.valueOf(abstractC2759w0.P(abstractC2759w0.v())))).floatValue();
        String strA = kk.f.a(scriptIndicAction, new StringBuilder(), "Value");
        if (scriptIndicAction.getOutput().getLineWidth() != null) {
            Paint paint = this.f95243r;
            if (paint != null) {
                paint.setStrokeWidth(scriptIndicAction.getOutput().getFloatLineWidth());
            }
            Paint paint2 = this.f95245t;
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
        Paint paint3 = this.f95243r;
        if (paint3 != null) {
            paint3.setPathEffect(new DashPathEffect(new float[]{fFloatValue3, fFloatValue4}, 0.0f));
        }
        Paint paint4 = this.f95245t;
        if (paint4 != null) {
            paint4.setPathEffect(new DashPathEffect(new float[]{fFloatValue3, fFloatValue4}, 0.0f));
        }
        y1 y1Var = this.f95239n;
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
        float fP = abstractC2759w0.P(dDoubleValue2);
        float fP2 = abstractC2759w0.P(dDoubleValue);
        PointF pointF = this.f95234d0;
        y1 y1Var2 = this.f95239n;
        pointF.x = y1Var2 != null ? y1Var2.j(jLongValue2 * ((long) 1000)) : 0.0f;
        this.f95234d0.y = fP;
        PointF pointF2 = this.f95235e0;
        y1 y1Var3 = this.f95239n;
        pointF2.x = y1Var3 != null ? y1Var3.j(jLongValue * ((long) 1000)) : 0.0f;
        this.f95235e0.y = fP2;
        int iA = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str2 = (String) linkedHashMap.get(strA)) == null || (numP = Ah.w.p(str2)) == null) ? f10.u()[this.f95213I].a() : numP.intValue();
        hk.a aVar = hk.a.f98027a;
        PointF pointF3 = this.f95234d0;
        float f11 = pointF3.x;
        PointF pointF4 = this.f95235e0;
        aVar.c(f11, pointF4.x, pointF3.y, pointF4.y);
        aVar.a(this.f95234d0, fFloatValue2, fFloatValue);
        Paint paint5 = this.f95243r;
        if (paint5 != null) {
            paint5.setColor(iA);
        }
        C2702d c2702d = this.f95238m;
        int iU = c2702d != null ? c2702d.u() : 0;
        y1 y1Var4 = this.f95239n;
        float fW = iU + (y1Var4 != null ? y1Var4.w() : 0.0f);
        PointF pointF5 = this.f95234d0;
        float f12 = pointF5.x - fW;
        float f13 = pointF5.y;
        PointF pointF6 = this.f95235e0;
        float f14 = pointF6.x - fW;
        float f15 = pointF6.y;
        Path path4 = this.f95242q;
        if (path4 != null) {
            path4.moveTo(f12, f13);
        }
        Path path5 = this.f95242q;
        if (path5 != null) {
            path5.lineTo(f14, f15);
        }
        Paint paint6 = this.f95243r;
        if (paint6 == null || (path = this.f95242q) == null) {
            return;
        }
        canvas.drawPath(path, paint6);
    }

    /* JADX WARN: Code duplicated, block: B:113:0x0242  */
    /* JADX WARN: Code duplicated, block: B:127:0x0270  */
    /* JADX WARN: Failed to restore switch over string. Please report as a decompilation issue */
    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        K0 k10;
        y1 y1Var;
        C2765z c2765zH;
        int i10;
        Map map;
        Object obj;
        List<ScriptIndicAction> action;
        ScriptIndicAction scriptIndicAction;
        Map<String, Map<String, String>> map2;
        int i11;
        sp.aicoin_kline.core.indicator.config.F f10;
        float f11;
        int i12;
        int i13;
        Map map3;
        Object obj2;
        ScriptIndicAction scriptIndicAction2;
        float f12;
        sp.aicoin_kline.core.indicator.config.F f13;
        Double dN;
        int i14;
        Double dN2;
        int iAbs;
        long jH;
        float f14;
        int i15;
        int i16;
        float f15;
        String str;
        float f16;
        Double dN3;
        String str2;
        Integer numP;
        Double dN4;
        Long lR;
        int i17;
        Double dN5;
        ScriptIndicAction scriptIndicAction3;
        AbstractC2759w0 abstractC2759w0;
        ScriptIndicAction scriptIndicAction4;
        AbstractC2759w0 abstractC2759w1;
        ScriptIndicAction scriptIndicAction5;
        sp.aicoin_kline.core.indicator.config.F f17;
        boolean z10;
        AbstractC2759w0 abstractC2759w2;
        int i18;
        String str3;
        Integer numP2;
        Double dN6;
        Double dN7;
        Double dN8;
        String id2;
        this = this;
        Canvas canvas2 = canvas;
        AbstractC2759w0 abstractC2759w3 = this.f95240o;
        if (abstractC2759w3 == null || (k10 = this.f95241p) == null || (y1Var = this.f95239n) == null || (c2765zH = this.i().b().h(this.c())) == null || this.i().b().e(this.b()) == null) {
            return;
        }
        this.f95231a0 = c2765zH.D();
        sp.aicoin_kline.core.indicator.config.F fX = k10.x();
        List listR1 = Sf.z.r1(k10.F());
        int iR = y1Var.r();
        int iQ = y1Var.q();
        this.f95213I = 0;
        float fU = y1Var.u();
        float fJ = y1Var.J();
        float f18 = 2;
        float f19 = (fU / f18) - fJ;
        float f20 = (f18 * fU) / 3;
        int iY = y1Var.y();
        canvas2.save();
        Iterator it = listR1.iterator();
        while (true) {
            if (!it.hasNext()) {
                i10 = iR;
                map = null;
                obj = null;
                break;
            }
            Object next = it.next();
            String str4 = this.f95236f0;
            ScriptIndicConfig config = ((ScriptDrawData) next).getConfig();
            i10 = iR;
            map = null;
            if (Ah.y.T(str4, (config == null || (id2 = config.getId()) == null) ? "" : id2, false, 2, null)) {
                obj = next;
                break;
            } else {
                it = it;
                iR = i10;
            }
        }
        ScriptDrawData scriptDrawData = (ScriptDrawData) obj;
        if (scriptDrawData == null) {
            return;
        }
        Map<String, Map<String, String>> calculateHistoryData = scriptDrawData.getCalculateHistoryData();
        ScriptIndicConfig config2 = scriptDrawData.getConfig();
        Map.Entry entry = (Map.Entry) Sf.z.p0(calculateHistoryData.entrySet());
        Map map4 = entry != null ? (Map) entry.getValue() : map;
        if (config2 != null && (action = config2.getAction()) != null) {
            for (ScriptIndicAction scriptIndicAction6 : action) {
                String action2 = scriptIndicAction6.getAction();
                Map map5 = map4;
                float f21 = fJ;
                float f22 = f20;
                switch (action2.hashCode()) {
                    case -2020374621:
                        scriptIndicAction = scriptIndicAction6;
                        map2 = calculateHistoryData;
                        i11 = iQ;
                        f10 = fX;
                        f11 = fU;
                        i12 = iY;
                        i13 = i10;
                        map3 = map5;
                        obj2 = null;
                        if (action2.equals("plotHist") && !AbstractC7609s.f(scriptIndicAction.getDisplay(), Boolean.FALSE)) {
                            this = this;
                            AbstractC2759w0 abstractC2759w4 = abstractC2759w3;
                            scriptIndicAction2 = scriptIndicAction;
                            f12 = f11;
                            this.w(canvas, f22, f12, f21, scriptIndicAction2, abstractC2759w4, i13, i12, f10, Sf.N.z(map2));
                            abstractC2759w3 = abstractC2759w4;
                            f13 = f10;
                        } else {
                            scriptIndicAction2 = scriptIndicAction;
                            f13 = f10;
                            f12 = f11;
                        }
                        break;
                    case -2020167279:
                        map2 = calculateHistoryData;
                        i11 = iQ;
                        f10 = fX;
                        int i19 = iY;
                        i13 = i10;
                        map3 = map5;
                        obj2 = null;
                        scriptIndicAction2 = scriptIndicAction6;
                        f12 = fU;
                        if (action2.equals("plotOhlc") && !AbstractC7609s.f(scriptIndicAction2.getDisplay(), Boolean.FALSE)) {
                            AbstractC2759w0 abstractC2759w5 = abstractC2759w3;
                            i12 = i19;
                            B(canvas, f22, f12, f21, scriptIndicAction2, abstractC2759w5, i13, i12, Sf.N.z(map2));
                            f11 = f12;
                            scriptIndicAction = scriptIndicAction2;
                            abstractC2759w3 = abstractC2759w5;
                            if (AbstractC7609s.f(scriptIndicAction.getTrackPrice(), Boolean.TRUE) && map3 != null) {
                                String close = scriptIndicAction.getClose();
                                if (close == null) {
                                    close = "";
                                }
                                String str5 = (String) map3.get(close);
                                double dDoubleValue = (str5 == null || (dN = Ah.v.n(str5)) == null) ? 0.0d : dN.doubleValue();
                                if (dDoubleValue != 0.0d) {
                                    StringBuilder sb2 = new StringBuilder();
                                    ActionOutput output = scriptIndicAction.getOutput();
                                    sb2.append(output != null ? output.getColor() : null);
                                    sb2.append("originValue");
                                    String str6 = (String) map3.get(sb2.toString());
                                    y(canvas, abstractC2759w3, dDoubleValue, str6 == null ? "" : str6);
                                }
                            }
                            scriptIndicAction2 = scriptIndicAction;
                            f13 = f10;
                            f12 = f11;
                        } else {
                            this = this;
                            i12 = i19;
                            f13 = f10;
                        }
                        break;
                    case -2020020818:
                        map2 = calculateHistoryData;
                        i11 = iQ;
                        f13 = fX;
                        f11 = fU;
                        i14 = iY;
                        i13 = i10;
                        map3 = map5;
                        obj2 = null;
                        scriptIndicAction2 = scriptIndicAction6;
                        if (action2.equals("plotText") && !AbstractC7609s.f(scriptIndicAction2.getDisplay(), Boolean.FALSE)) {
                            this = this;
                            f12 = f11;
                            AbstractC2759w0 abstractC2759w6 = abstractC2759w3;
                            this.E(canvas, f19, f12, scriptIndicAction2, abstractC2759w6, i13, i11, f13, Sf.N.z(map2));
                            abstractC2759w3 = abstractC2759w6;
                            scriptIndicAction2 = scriptIndicAction2;
                            i13 = i13;
                            f13 = f13;
                            i12 = i14;
                        } else {
                            this = this;
                            i12 = i14;
                            f12 = f11;
                        }
                        break;
                    case -608864346:
                        scriptIndicAction = scriptIndicAction6;
                        map2 = calculateHistoryData;
                        i11 = iQ;
                        f10 = fX;
                        f11 = fU;
                        i14 = iY;
                        i13 = i10;
                        map3 = map5;
                        obj2 = null;
                        if (action2.equals("label.new") && !AbstractC7609s.f(scriptIndicAction.getDisplay(), Boolean.FALSE)) {
                            this = this;
                            AbstractC2759w0 abstractC2759w7 = abstractC2759w3;
                            f13 = f10;
                            this.D(canvas, scriptIndicAction, abstractC2759w7, f13, Sf.N.z(map2));
                            scriptIndicAction2 = scriptIndicAction;
                            abstractC2759w3 = abstractC2759w7;
                            i12 = i14;
                            f12 = f11;
                        }
                        i12 = i14;
                        scriptIndicAction2 = scriptIndicAction;
                        f13 = f10;
                        f12 = f11;
                        break;
                    case -405487794:
                        map2 = calculateHistoryData;
                        i11 = iQ;
                        f10 = fX;
                        f11 = fU;
                        i13 = i10;
                        map3 = map5;
                        obj2 = null;
                        V v10 = this;
                        AbstractC2759w0 abstractC2759w8 = abstractC2759w3;
                        scriptIndicAction2 = scriptIndicAction6;
                        if (!action2.equals("plotCandle")) {
                            this = v10;
                        } else if (!AbstractC7609s.f(scriptIndicAction2.getDisplay(), Boolean.FALSE)) {
                            int i20 = iY;
                            v10.v(canvas, f22, f11, f21, scriptIndicAction2, abstractC2759w8, i13, i20, Sf.N.z(map2));
                            scriptIndicAction = scriptIndicAction2;
                            abstractC2759w3 = abstractC2759w8;
                            i14 = i20;
                            if (AbstractC7609s.f(scriptIndicAction.getTrackPrice(), Boolean.TRUE) && map3 != null) {
                                String close2 = scriptIndicAction.getClose();
                                if (close2 == null) {
                                    close2 = "";
                                }
                                String str7 = (String) map3.get(close2);
                                double dDoubleValue2 = (str7 == null || (dN2 = Ah.v.n(str7)) == null) ? 0.0d : dN2.doubleValue();
                                if (dDoubleValue2 != 0.0d) {
                                    StringBuilder sb3 = new StringBuilder();
                                    ActionOutput output2 = scriptIndicAction.getOutput();
                                    sb3.append(output2 != null ? output2.getColor() : null);
                                    sb3.append("originValue");
                                    String str8 = (String) map3.get(sb3.toString());
                                    y(canvas, abstractC2759w3, dDoubleValue2, str8 == null ? "" : str8);
                                }
                            }
                            i12 = i14;
                            scriptIndicAction2 = scriptIndicAction;
                            f13 = f10;
                            f12 = f11;
                        } else {
                            this = this;
                        }
                        abstractC2759w3 = abstractC2759w8;
                        i12 = iY;
                        f13 = f10;
                        f12 = f11;
                        break;
                    case -392601705:
                        map2 = calculateHistoryData;
                        i11 = iQ;
                        f10 = fX;
                        f11 = fU;
                        i13 = i10;
                        map3 = map5;
                        obj2 = null;
                        V v11 = this;
                        AbstractC2759w0 abstractC2759w9 = abstractC2759w3;
                        if (action2.equals("plotColumn") && !AbstractC7609s.f(scriptIndicAction6.getDisplay(), Boolean.FALSE)) {
                            Map mapZ = Sf.N.z(map2);
                            float f23 = (f11 / 6) - f21;
                            float f24 = f23 + f22;
                            String histBase = scriptIndicAction6.getHistBase();
                            float fP = abstractC2759w9.P((histBase == null || (dN5 = Ah.v.n(histBase)) == null) ? 0.0d : dN5.doubleValue());
                            int intOffset = scriptIndicAction6.getIntOffset();
                            if (intOffset < 0) {
                                iAbs = Math.abs(intOffset) + iY;
                                float f25 = intOffset * f11;
                                f23 += f25;
                                f24 += f25;
                            } else {
                                iAbs = iY;
                            }
                            int i21 = intOffset > 0 ? i13 - intOffset : i13;
                            String strA = kk.f.a(scriptIndicAction6, new StringBuilder(), "Value");
                            if (scriptIndicAction6.getOutput().getFill()) {
                                v11.f95248w.setStyle(Paint.Style.FILL);
                            } else {
                                v11.f95248w.setStyle(Paint.Style.STROKE);
                            }
                            int intShowLast = scriptIndicAction6.getIntShowLast();
                            int i22 = (1 > intShowLast || intShowLast >= (i17 = v11.f95231a0)) ? -1 : i17 - intShowLast;
                            try {
                                y1 y1Var2 = v11.f95239n;
                                jH = y1Var2 != null ? y1Var2.H(i22) : 0L;
                            } catch (Exception unused) {
                            }
                            float f26 = f24;
                            float f27 = f23;
                            while (i21 < iAbs) {
                                int i23 = i22;
                                y1 y1Var3 = v11.f95239n;
                                Map map6 = (Map) mapZ.get(String.valueOf(y1Var3 != null ? Long.valueOf(y1Var3.H(i21)) : null));
                                if (map6 == null) {
                                    str = strA;
                                    i16 = i21;
                                    f16 = fP;
                                    i15 = i23;
                                    iAbs = iAbs;
                                } else {
                                    float f28 = f27;
                                    String str9 = (String) map6.get("time");
                                    long jLongValue = (str9 == null || (lR = Ah.w.r(str9)) == null) ? 0L : lR.longValue();
                                    String series = scriptIndicAction6.getSeries();
                                    if (series == null) {
                                        series = "0";
                                    }
                                    String str10 = (String) map6.get(series);
                                    double dDoubleValue3 = (str10 == null || (dN4 = Ah.v.n(str10)) == null) ? 0.0d : dN4.doubleValue();
                                    int iIntValue = dDoubleValue3 >= 0.0d ? v11.f95214J : v11.f95215K;
                                    if (strA != null && strA.length() != 0 && !AbstractC7609s.f(strA, "nullValue") && (str2 = (String) map6.get(strA)) != null && (numP = Ah.w.p(str2)) != null) {
                                        iIntValue = numP.intValue();
                                    }
                                    float f29 = f26;
                                    v11.f95248w.setColor(iIntValue);
                                    if (i23 <= 0 || jLongValue >= jH) {
                                        if (dDoubleValue3 == 0.0d) {
                                            float fQ = (abstractC2759w9.u() == 0.0d && abstractC2759w9.v() == 0.0d) ? fP + abstractC2759w9.q() : fP;
                                            str = strA;
                                            f15 = f28;
                                            f14 = f29;
                                            i15 = i23;
                                            i16 = i21;
                                            canvas.drawLine(f15, fQ, f14, fQ, v11.f95248w);
                                        } else {
                                            iAbs = iAbs;
                                            f14 = f29;
                                            i15 = i23;
                                            i16 = i21;
                                            f15 = f28;
                                            str = strA;
                                            String series2 = scriptIndicAction6.getSeries();
                                            if (series2 == null) {
                                                series2 = "0";
                                            }
                                            String str11 = (String) map6.get(series2);
                                            float fP2 = abstractC2759w9.P((str11 == null || (dN3 = Ah.v.n(str11)) == null) ? 0.0d : dN3.doubleValue());
                                            if (Math.abs(fP - fP2) < 1.0f) {
                                                float f30 = fP;
                                                canvas.drawLine(f15, f30, f14, fP, v11.f95248w);
                                                f16 = f30;
                                            } else {
                                                f16 = fP;
                                                nk.y.a(canvas, f15, fP2, f14, f16, v11.f95248w);
                                            }
                                        }
                                        f27 = f15 + f11;
                                        f26 = f14 + f11;
                                    } else {
                                        f14 = f29;
                                        i15 = i23;
                                        i16 = i21;
                                        f15 = f28;
                                        str = strA;
                                    }
                                    f16 = fP;
                                    f27 = f15 + f11;
                                    f26 = f14 + f11;
                                }
                                i21 = i16 + 1;
                                fP = f16;
                                iAbs = iAbs;
                                strA = str;
                                i22 = i15;
                            }
                        }
                        this = v11;
                        abstractC2759w3 = abstractC2759w9;
                        scriptIndicAction2 = scriptIndicAction6;
                        i12 = iY;
                        f13 = f10;
                        f12 = f11;
                        break;
                    case 3143043:
                        scriptIndicAction3 = scriptIndicAction6;
                        map2 = calculateHistoryData;
                        i11 = iQ;
                        f11 = fU;
                        i13 = i10;
                        map3 = map5;
                        obj2 = null;
                        if (action2.equals("fill") && !AbstractC7609s.f(scriptIndicAction3.getDisplay(), Boolean.FALSE)) {
                            this = this;
                            AbstractC2759w0 abstractC2759w10 = abstractC2759w3;
                            f12 = f11;
                            this.x(canvas, f19, f12, scriptIndicAction3, abstractC2759w10, i13, i11, fX, Sf.N.z(map2));
                            abstractC2759w3 = abstractC2759w10;
                            scriptIndicAction2 = scriptIndicAction3;
                            i13 = i13;
                            f13 = fX;
                            i12 = iY;
                        } else {
                            this = this;
                            f13 = fX;
                            i12 = iY;
                            scriptIndicAction2 = scriptIndicAction3;
                            f12 = f11;
                        }
                        break;
                    case 3443937:
                        map2 = calculateHistoryData;
                        i11 = iQ;
                        f13 = fX;
                        f11 = fU;
                        map3 = map5;
                        obj2 = null;
                        scriptIndicAction2 = scriptIndicAction6;
                        if (action2.equals("plot") && !AbstractC7609s.f(scriptIndicAction2.getDisplay(), Boolean.FALSE)) {
                            fX = f13;
                            int i24 = i10;
                            AbstractC2759w0 abstractC2759w11 = abstractC2759w3;
                            C(canvas, f19, f11, scriptIndicAction2, abstractC2759w11, i24, i11, fX, Sf.N.z(map2));
                            scriptIndicAction3 = scriptIndicAction2;
                            abstractC2759w3 = abstractC2759w11;
                            i13 = i24;
                            if (AbstractC7609s.f(scriptIndicAction3.getTrackPrice(), Boolean.TRUE) && map3 != null) {
                                String series3 = scriptIndicAction3.getSeries();
                                if (series3 == null) {
                                    series3 = "0";
                                }
                                String str12 = (String) map3.get(series3);
                                if (str12 == null) {
                                    str12 = "0.0";
                                }
                                Double dN9 = Ah.v.n(str12);
                                double dDoubleValue4 = dN9 != null ? dN9.doubleValue() : 0.0d;
                                if (dDoubleValue4 != 0.0d) {
                                    StringBuilder sb4 = new StringBuilder();
                                    ActionOutput output3 = scriptIndicAction3.getOutput();
                                    sb4.append(output3 != null ? output3.getColor() : null);
                                    sb4.append("originValue");
                                    String str13 = (String) map3.get(sb4.toString());
                                    y(canvas, abstractC2759w3, dDoubleValue4, str13 == null ? "" : str13);
                                }
                            }
                            this = this;
                            f13 = fX;
                            i12 = iY;
                            scriptIndicAction2 = scriptIndicAction3;
                            f12 = f11;
                        }
                        this = this;
                        i12 = iY;
                        i13 = i10;
                        f12 = f11;
                        break;
                    case 71185149:
                        map2 = calculateHistoryData;
                        i11 = iQ;
                        f13 = fX;
                        f11 = fU;
                        map3 = map5;
                        obj2 = null;
                        scriptIndicAction2 = scriptIndicAction6;
                        if (action2.equals("box.new") && !AbstractC7609s.f(scriptIndicAction2.getDisplay(), Boolean.FALSE)) {
                            this = this;
                            abstractC2759w0 = abstractC2759w3;
                            scriptIndicAction4 = scriptIndicAction2;
                            this.z(canvas, scriptIndicAction4, abstractC2759w0, f13, Sf.N.z(map2));
                            scriptIndicAction2 = scriptIndicAction4;
                            abstractC2759w3 = abstractC2759w0;
                        } else {
                            this = this;
                        }
                        i12 = iY;
                        i13 = i10;
                        f12 = f11;
                        break;
                    case 1187522726:
                        abstractC2759w1 = abstractC2759w3;
                        scriptIndicAction5 = scriptIndicAction6;
                        map2 = calculateHistoryData;
                        i11 = iQ;
                        f17 = fX;
                        f11 = fU;
                        if (action2.equals("line.new")) {
                            map3 = map5;
                            if (AbstractC7609s.f(scriptIndicAction5.getDisplay(), Boolean.FALSE)) {
                                obj2 = null;
                                this = this;
                                i12 = iY;
                                i13 = i10;
                                scriptIndicAction2 = scriptIndicAction5;
                                f13 = f17;
                                f12 = f11;
                                abstractC2759w3 = abstractC2759w1;
                            } else {
                                scriptIndicAction4 = scriptIndicAction5;
                                f13 = f17;
                                abstractC2759w0 = abstractC2759w1;
                                obj2 = null;
                                this.F(canvas2, scriptIndicAction4, abstractC2759w0, f13, map2);
                                this = this;
                                scriptIndicAction2 = scriptIndicAction4;
                                abstractC2759w3 = abstractC2759w0;
                                i12 = iY;
                                i13 = i10;
                                f12 = f11;
                            }
                        } else {
                            i12 = iY;
                            i13 = i10;
                            map3 = map5;
                            scriptIndicAction2 = scriptIndicAction5;
                            f13 = f17;
                            f12 = f11;
                            abstractC2759w3 = abstractC2759w1;
                            obj2 = null;
                        }
                        break;
                    case 1803007808:
                        if (action2.equals("plotShape") && !AbstractC7609s.f(scriptIndicAction6.getDisplay(), Boolean.FALSE)) {
                            Map mapZ2 = Sf.N.z(calculateHistoryData);
                            this.f95206B.reset();
                            this.f95207C.reset();
                            int intOffset2 = scriptIndicAction6.getIntOffset();
                            String strA2 = kk.f.a(scriptIndicAction6, new StringBuilder(), "Value");
                            scriptIndicAction6.getOutput().getBgColor();
                            int intShowLast2 = scriptIndicAction6.getIntShowLast();
                            scriptIndicAction5 = scriptIndicAction6;
                            ArrayList arrayList = new ArrayList();
                            map2 = calculateHistoryData;
                            if (intOffset2 != 0) {
                                List listB = Sf.P.B(mapZ2);
                                int i25 = 0;
                                for (Object obj3 : listB) {
                                    int i26 = i25 + 1;
                                    if (i25 < 0) {
                                        Sf.r.x();
                                    }
                                    Map map7 = mapZ2;
                                    int i27 = (intOffset2 * (-1)) + i25;
                                    Object objD = ((Qf.p) obj3).d();
                                    sp.aicoin_kline.core.indicator.config.F f31 = fX;
                                    Map map8 = (Map) objD;
                                    String series4 = scriptIndicAction5.getSeries();
                                    float f32 = fU;
                                    String str14 = (String) map8.get(series4 == null ? "0" : series4);
                                    boolean z11 = ((str14 == null || (dN8 = Ah.v.n(str14)) == null) ? 0.0d : dN8.doubleValue()) > 0.0d;
                                    if (i27 >= 0 && i27 < listB.size() && z11) {
                                        arrayList.add(listB.get(i27));
                                    }
                                    fX = f31;
                                    i25 = i26;
                                    fU = f32;
                                    mapZ2 = map7;
                                }
                            }
                            f17 = fX;
                            f11 = fU;
                            Map mapZ3 = intOffset2 != 0 ? Sf.N.z(Sf.N.v(arrayList)) : mapZ2;
                            int i28 = (intShowLast2 <= 0 || intShowLast2 >= mapZ3.size()) ? 0 : (this.f95231a0 - intShowLast2) + intOffset2;
                            nk.x.f134260a.d(mapZ3);
                            float f33 = f19;
                            int i29 = i10;
                            while (i29 < iQ) {
                                y1 y1Var4 = this.f95239n;
                                Map linkedHashMap = (Map) mapZ3.get(String.valueOf(y1Var4 != null ? Long.valueOf(y1Var4.H(i29)) : null));
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
                                Map map9 = mapZ3;
                                String str16 = (String) linkedHashMap.get(refSeries == null ? "" : refSeries);
                                double dDoubleValue5 = (str16 == null || (dN6 = Ah.v.n(str16)) == null) ? 0.0d : dN6.doubleValue();
                                if (dDoubleValue5 != 0.0d && z10) {
                                    float fP3 = abstractC2759w3.P(dDoubleValue5);
                                    int iA = (strA2 == null || strA2.length() == 0 || AbstractC7609s.f(strA2, "nullValue") || (str3 = (String) linkedHashMap.get(strA2)) == null || (numP2 = Ah.w.p(str3)) == null) ? f17.u()[this.f95213I].a() : numP2.intValue();
                                    if (scriptIndicAction5.getOutput().getFill()) {
                                        this.f95205A.setStyle(Paint.Style.FILL_AND_STROKE);
                                    } else {
                                        this.f95205A.setStyle(Paint.Style.STROKE);
                                    }
                                    this.f95205A.setColor(iA);
                                    String placement = scriptIndicAction5.getOutput().getPlacement();
                                    String shape = scriptIndicAction5.getOutput().getShape();
                                    if (i29 >= i28) {
                                        abstractC2759w2 = abstractC2759w3;
                                        i18 = i28;
                                        switch (shape.hashCode()) {
                                            case -1360216880:
                                                if (shape.equals("circle")) {
                                                    this.f95212H = Xj.a.a(10.0f);
                                                    if (AbstractC7609s.f(placement, "bottom")) {
                                                        canvas2.drawCircle(f33, fP3 + this.f95212H, Xj.a.a(3.0f), this.f95205A);
                                                    } else if (AbstractC7609s.f(placement, "center")) {
                                                        canvas2.drawCircle(f33, fP3, Xj.a.a(3.0f), this.f95205A);
                                                    } else {
                                                        canvas2.drawCircle(f33, fP3 - this.f95212H, Xj.a.a(3.0f), this.f95205A);
                                                    }
                                                }
                                                break;
                                            case -1026432949:
                                                if (shape.equals("arrowDown")) {
                                                    this.f95208D = Xj.a.a(6.0f);
                                                    this.f95209E = Xj.a.a(7.0f);
                                                    this.f95210F = Xj.a.a(10.0f);
                                                    this.f95211G = Xj.a.a(2.0f);
                                                    this.f95212H = Xj.a.a(7.0f);
                                                    if (AbstractC7609s.f(placement, "bottom")) {
                                                        this.f95206B.moveTo(f33, this.f95212H + fP3);
                                                        this.f95206B.lineTo(this.f95211G + f33, this.f95212H + fP3);
                                                        this.f95206B.lineTo(this.f95211G + f33, this.f95210F + fP3 + this.f95212H);
                                                        this.f95206B.lineTo(this.f95208D + f33, this.f95210F + fP3 + this.f95212H);
                                                        this.f95206B.lineTo(f33, this.f95210F + fP3 + this.f95209E + this.f95212H);
                                                        this.f95206B.lineTo(f33 - this.f95208D, this.f95210F + fP3 + this.f95212H);
                                                        this.f95206B.lineTo(f33 - this.f95211G, this.f95210F + fP3 + this.f95212H);
                                                        this.f95206B.lineTo(f33 - this.f95211G, fP3 + this.f95212H);
                                                        this.f95206B.close();
                                                    } else if (AbstractC7609s.f(placement, "center")) {
                                                        this.f95206B.moveTo(f33, fP3 - this.f95212H);
                                                        this.f95206B.lineTo(this.f95211G + f33, fP3 - this.f95212H);
                                                        this.f95206B.lineTo(this.f95211G + f33, (this.f95210F + fP3) - this.f95212H);
                                                        this.f95206B.lineTo(this.f95208D + f33, (this.f95210F + fP3) - this.f95212H);
                                                        this.f95206B.lineTo(f33, ((this.f95210F + fP3) + this.f95209E) - this.f95212H);
                                                        this.f95206B.lineTo(f33 - this.f95208D, (this.f95210F + fP3) - this.f95212H);
                                                        this.f95206B.lineTo(f33 - this.f95211G, (this.f95210F + fP3) - this.f95212H);
                                                        this.f95206B.lineTo(f33 - this.f95211G, fP3 - this.f95212H);
                                                        this.f95206B.close();
                                                    } else {
                                                        this.f95206B.moveTo(f33, fP3 - this.f95212H);
                                                        this.f95206B.lineTo(this.f95208D + f33, (fP3 - this.f95209E) - this.f95212H);
                                                        this.f95206B.lineTo(this.f95211G + f33, (fP3 - this.f95209E) - this.f95212H);
                                                        this.f95206B.lineTo(this.f95211G + f33, (fP3 - this.f95210F) - this.f95212H);
                                                        this.f95206B.lineTo(this.f95211G + f33, ((fP3 - this.f95210F) - this.f95209E) - this.f95212H);
                                                        this.f95206B.lineTo(f33 - this.f95211G, ((fP3 - this.f95210F) - this.f95209E) - this.f95212H);
                                                        this.f95206B.lineTo(f33 - this.f95211G, (fP3 - this.f95209E) - this.f95212H);
                                                        this.f95206B.lineTo(f33 - this.f95208D, (fP3 - this.f95209E) - this.f95212H);
                                                        this.f95206B.close();
                                                    }
                                                }
                                                break;
                                            case -742236470:
                                                if (shape.equals("triangleDown")) {
                                                    this.f95208D = Xj.a.a(7.0f);
                                                    this.f95209E = Xj.a.a(9.0f);
                                                    this.f95212H = Xj.a.a(5.0f);
                                                    if (AbstractC7609s.f(placement, "bottom")) {
                                                        this.f95206B.moveTo(f33, this.f95212H + fP3);
                                                        this.f95206B.lineTo(this.f95208D + f33, this.f95212H + fP3);
                                                        this.f95206B.lineTo(f33, this.f95212H + fP3 + this.f95209E);
                                                        this.f95206B.lineTo(f33 - this.f95208D, fP3 + this.f95212H);
                                                        this.f95206B.close();
                                                    } else if (AbstractC7609s.f(placement, "center")) {
                                                        this.f95206B.moveTo(f33, fP3 - this.f95212H);
                                                        this.f95206B.lineTo(this.f95208D + f33, fP3 - this.f95212H);
                                                        this.f95206B.lineTo(f33, (fP3 - this.f95212H) + this.f95209E);
                                                        this.f95206B.lineTo(f33 - this.f95208D, fP3 - this.f95212H);
                                                        this.f95206B.close();
                                                    } else {
                                                        this.f95208D = Xj.a.a(7.0f);
                                                        this.f95209E = Xj.a.a(9.0f);
                                                        float fA = Xj.a.a(5.0f);
                                                        this.f95212H = fA;
                                                        this.f95206B.moveTo(f33, fP3 - fA);
                                                        this.f95206B.lineTo(this.f95208D + f33, (fP3 - this.f95212H) - this.f95209E);
                                                        this.f95206B.lineTo(f33 - this.f95208D, (fP3 - this.f95212H) - this.f95209E);
                                                        this.f95206B.close();
                                                    }
                                                }
                                                break;
                                            case -734027644:
                                                if (shape.equals("arrowUp")) {
                                                    this.f95208D = Xj.a.a(6.0f);
                                                    this.f95209E = Xj.a.a(7.0f);
                                                    this.f95210F = Xj.a.a(10.0f);
                                                    this.f95211G = Xj.a.a(2.0f);
                                                    this.f95212H = Xj.a.a(7.0f);
                                                    if (AbstractC7609s.f(placement, "bottom")) {
                                                        this.f95206B.moveTo(f33, this.f95212H + fP3);
                                                        this.f95206B.lineTo(this.f95208D + f33, this.f95209E + fP3 + this.f95212H);
                                                        this.f95206B.lineTo(this.f95211G + f33, this.f95209E + fP3 + this.f95212H);
                                                        this.f95206B.lineTo(this.f95211G + f33, this.f95210F + fP3 + this.f95212H);
                                                        this.f95206B.lineTo(this.f95211G + f33, this.f95210F + fP3 + this.f95209E + this.f95212H);
                                                        this.f95206B.lineTo(f33 - this.f95211G, this.f95210F + fP3 + this.f95209E + this.f95212H);
                                                        this.f95206B.lineTo(f33 - this.f95211G, this.f95209E + fP3 + this.f95212H);
                                                        this.f95206B.lineTo(f33 - this.f95208D, fP3 + this.f95209E + this.f95212H);
                                                        this.f95206B.close();
                                                    } else if (AbstractC7609s.f(placement, "center")) {
                                                        this.f95206B.moveTo(f33, fP3 - this.f95212H);
                                                        this.f95206B.lineTo(this.f95208D + f33, (this.f95209E + fP3) - this.f95212H);
                                                        this.f95206B.lineTo(this.f95211G + f33, (this.f95209E + fP3) - this.f95212H);
                                                        this.f95206B.lineTo(this.f95211G + f33, (this.f95210F + fP3) - this.f95212H);
                                                        this.f95206B.lineTo(this.f95211G + f33, ((this.f95210F + fP3) + this.f95209E) - this.f95212H);
                                                        this.f95206B.lineTo(f33 - this.f95211G, ((this.f95210F + fP3) + this.f95209E) - this.f95212H);
                                                        this.f95206B.lineTo(f33 - this.f95211G, (this.f95209E + fP3) - this.f95212H);
                                                        this.f95206B.lineTo(f33 - this.f95208D, (fP3 + this.f95209E) - this.f95212H);
                                                        this.f95206B.close();
                                                    } else {
                                                        this.f95206B.moveTo(f33, fP3 - this.f95212H);
                                                        this.f95206B.lineTo(this.f95211G + f33, fP3 - this.f95212H);
                                                        this.f95206B.lineTo(this.f95211G + f33, (fP3 - this.f95210F) - this.f95212H);
                                                        this.f95206B.lineTo(this.f95208D + f33, (fP3 - this.f95210F) - this.f95212H);
                                                        this.f95206B.lineTo(f33, ((fP3 - this.f95210F) - this.f95209E) - this.f95212H);
                                                        this.f95206B.lineTo(f33 - this.f95208D, (fP3 - this.f95210F) - this.f95212H);
                                                        this.f95206B.lineTo(f33 - this.f95211G, (fP3 - this.f95210F) - this.f95212H);
                                                        this.f95206B.lineTo(f33 - this.f95211G, fP3 - this.f95212H);
                                                        this.f95206B.close();
                                                    }
                                                }
                                                break;
                                            case 535540419:
                                                if (shape.equals("triangleUp")) {
                                                    if (AbstractC7609s.f(placement, "bottom")) {
                                                        this.f95208D = Xj.a.a(7.0f);
                                                        this.f95209E = Xj.a.a(9.0f);
                                                        float fA2 = Xj.a.a(5.0f);
                                                        this.f95212H = fA2;
                                                        this.f95206B.moveTo(f33, fA2 + fP3);
                                                        this.f95206B.lineTo(this.f95208D + f33, this.f95212H + fP3 + this.f95209E);
                                                        this.f95206B.lineTo(f33 - this.f95208D, fP3 + this.f95212H + this.f95209E);
                                                        this.f95206B.close();
                                                    } else if (AbstractC7609s.f(placement, "center")) {
                                                        this.f95208D = Xj.a.a(7.0f);
                                                        this.f95209E = Xj.a.a(9.0f);
                                                        float fA3 = Xj.a.a(5.0f);
                                                        this.f95212H = fA3;
                                                        this.f95206B.moveTo(f33, fP3 - fA3);
                                                        this.f95206B.lineTo(this.f95208D + f33, (fP3 - this.f95212H) + this.f95209E);
                                                        this.f95206B.lineTo(f33 - this.f95208D, (fP3 - this.f95212H) + this.f95209E);
                                                        this.f95206B.close();
                                                    } else {
                                                        this.f95208D = Xj.a.a(7.0f);
                                                        this.f95209E = Xj.a.a(9.0f);
                                                        float fA4 = Xj.a.a(5.0f);
                                                        this.f95212H = fA4;
                                                        this.f95206B.moveTo(f33, fP3 - fA4);
                                                        this.f95206B.lineTo(this.f95208D + f33, fP3 - this.f95212H);
                                                        this.f95206B.lineTo(f33, (fP3 - this.f95212H) - this.f95209E);
                                                        this.f95206B.lineTo(f33 - this.f95208D, fP3 - this.f95212H);
                                                        this.f95206B.close();
                                                    }
                                                }
                                                break;
                                        }
                                    } else {
                                        abstractC2759w2 = abstractC2759w3;
                                        i18 = i28;
                                    }
                                } else {
                                    abstractC2759w2 = abstractC2759w3;
                                    i18 = i28;
                                }
                                f33 += f11;
                                i29++;
                                iQ = iQ;
                                mapZ3 = map9;
                                abstractC2759w3 = abstractC2759w2;
                                i28 = i18;
                            }
                            abstractC2759w1 = abstractC2759w3;
                            i11 = iQ;
                            canvas2.drawPath(this.f95206B, this.f95205A);
                            i12 = iY;
                            i13 = i10;
                            map3 = map5;
                            scriptIndicAction2 = scriptIndicAction5;
                            f13 = f17;
                            f12 = f11;
                            abstractC2759w3 = abstractC2759w1;
                            obj2 = null;
                            break;
                        }
                    default:
                        map2 = calculateHistoryData;
                        i11 = iQ;
                        f13 = fX;
                        i12 = iY;
                        i13 = i10;
                        map3 = map5;
                        obj2 = null;
                        scriptIndicAction2 = scriptIndicAction6;
                        f12 = fU;
                        break;
                }
                String color = scriptIndicAction2.getOutput().getColor();
                if (color == null || color.length() == 0) {
                    int i30 = this.f95213I + 1;
                    this.f95213I = i30;
                    if (i30 >= 9) {
                        this.f95213I = 8;
                    }
                }
                canvas2 = canvas;
                fU = f12;
                i10 = i13;
                iY = i12;
                fJ = f21;
                calculateHistoryData = map2;
                iQ = i11;
                fX = f13;
                map4 = map3;
                f20 = f22;
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
        s(this.f95237l);
        C2741q c2741qB = i().b();
        this.f95238m = c2741qB.e(b());
        this.f95239n = c2741qB.m(c());
        this.f95240o = c2741qB.l(b());
        AbstractC2755v abstractC2755vQ = q();
        K0 k10 = abstractC2755vQ instanceof K0 ? (K0) abstractC2755vQ : null;
        if (k10 == null) {
            return;
        }
        if (c2741qB.g(b() + ".m") == null) {
            return;
        }
        this.f95214J = aVar.r();
        this.f95215K = aVar.m();
        this.f95241p = k10;
        this.f95242q = new Path();
        this.f95244s = new Path();
        Paint paint = new Paint();
        Paint.Style style = Paint.Style.STROKE;
        paint.setStyle(style);
        paint.setAntiAlias(true);
        paint.setStrokeWidth(2.0f);
        paint.setColor(-16777216);
        this.f95243r = paint;
        Paint paint2 = new Paint();
        paint2.setStyle(style);
        paint2.setAntiAlias(true);
        paint2.setStrokeWidth(2.0f);
        paint2.setColor(-16777216);
        this.f95245t = paint2;
        Paint paint3 = new Paint(1);
        paint3.setAntiAlias(true);
        paint3.setColor(-16777216);
        paint3.setTextSize(Xj.a.d(12));
        this.f95246u = paint3;
        Paint paint4 = new Paint(1);
        paint4.setAntiAlias(true);
        paint4.setColor(-16777216);
        paint4.setTextSize(Xj.a.d(9));
        Paint paint5 = new Paint();
        paint5.setStyle(style);
        paint5.setAntiAlias(true);
        paint5.setStrokeWidth(2.0f);
        paint5.setColor(-16711936);
        this.f95248w = paint5;
        Paint paint6 = new Paint();
        paint6.setStyle(style);
        paint6.setAntiAlias(true);
        paint6.setStrokeWidth(2.0f);
        paint6.setColor(-16711936);
        this.f95249x = paint6;
        this.f95250y = new Path();
        Paint paint7 = new Paint();
        Paint.Style style2 = Paint.Style.FILL_AND_STROKE;
        paint7.setStyle(style2);
        paint7.setAntiAlias(false);
        paint7.setStrokeWidth(0.0f);
        paint7.setColor(-16711936);
        this.f95251z = paint7;
        Paint paint8 = new Paint();
        paint8.setStyle(style);
        paint8.setAntiAlias(true);
        paint8.setStrokeWidth(Xj.a.a(1.0f));
        paint8.setColor(-16711936);
        this.f95205A = paint8;
        Paint paint9 = new Paint();
        paint9.setStyle(style2);
        paint9.setAntiAlias(true);
        paint9.setStrokeWidth(2.0f);
        paint9.setColor(-1);
        this.f95227W.setStyle(style2);
        if (KLineManager.f142490O.a().f0() == 1) {
            this.f95226V.setStrokeWidth(1.0f);
            this.f95228X.setStrokeWidth(1.0f);
        }
        this.f95225U.setStyle(style);
        this.f95225U.setAntiAlias(true);
        this.f95224T.setStrokeWidth(2.0f);
        this.f95227W.setStrokeWidth(2.0f);
        this.f95225U.setStrokeWidth(1.0f);
        this.f95224T.setColor(aVar.r());
        this.f95225U.setColor(0);
        this.f95226V.setColor(aVar.r());
        this.f95227W.setColor(aVar.m());
        this.f95228X.setColor(aVar.m());
        this.f95229Y.setColor(aVar.r());
        this.f95233c0.setStyle(style);
        this.f95233c0.setStrokeWidth(2.0f);
        this.f95233c0.setColor(aVar.t());
        this.f95233c0.setPathEffect(new DashPathEffect(new float[]{Xj.a.b(3), Xj.a.b(2)}, 0.0f));
    }

    /* JADX WARN: Code duplicated, block: B:89:0x0198  */
    public final void v(Canvas canvas, float f10, float f11, float f12, ScriptIndicAction scriptIndicAction, AbstractC2759w0 abstractC2759w0, int i10, int i11, Map map) {
        int iAbs;
        long jH;
        float f13;
        boolean z10;
        float f14;
        float f15;
        float f16;
        float f17;
        float f18;
        String str;
        Integer numP;
        String str2;
        Integer numP2;
        float f19;
        String str3;
        Integer numP3;
        float f20;
        float f21;
        float f22;
        float f23;
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
        float f24 = (f11 / 6) - f12;
        float f25 = f24 + f10;
        float f26 = 2;
        int intOffset = scriptIndicAction.getIntOffset();
        this.f95230Z.reset();
        if (intOffset < 0) {
            float f27 = intOffset * f11;
            f24 += f27;
            f25 += f27;
            iAbs = Math.abs(intOffset) + i11;
        } else {
            iAbs = i11;
        }
        int intShowLast = scriptIndicAction.getIntShowLast();
        int i13 = (1 > intShowLast || intShowLast >= (i12 = this.f95231a0)) ? -1 : i12 - intShowLast;
        try {
            y1 y1Var = this.f95239n;
            jH = y1Var != null ? y1Var.H(i13) : 0L;
        } catch (Exception unused) {
        }
        float f28 = f24;
        for (int i14 = intOffset > 0 ? i10 - intOffset : i10; i14 < iAbs; i14++) {
            y1 y1Var2 = this.f95239n;
            Map map2 = (Map) map.get(String.valueOf(y1Var2 != null ? Long.valueOf(y1Var2.H(i14)) : null));
            if (map2 != null) {
                String str6 = (String) map2.get("time");
                long jLongValue = (str6 == null || (lR = Ah.w.r(str6)) == null) ? 0L : lR.longValue();
                String open = scriptIndicAction.getOpen();
                String str7 = (String) map2.get(open == null ? "" : open);
                double dDoubleValue = 0.0d;
                double dDoubleValue2 = (str7 == null || (dN4 = Ah.v.n(str7)) == null) ? 0.0d : dN4.doubleValue();
                this.f95221Q = dDoubleValue2;
                if (dDoubleValue2 == 0.0d) {
                    f13 = f28;
                } else {
                    this.f95217M = abstractC2759w0.P(dDoubleValue2);
                    String high = scriptIndicAction.getHigh();
                    if (high == null) {
                        high = "";
                    }
                    String str8 = (String) map2.get(high);
                    double dDoubleValue3 = (str8 == null || (dN3 = Ah.v.n(str8)) == null) ? 0.0d : dN3.doubleValue();
                    this.f95220P = dDoubleValue3;
                    this.f95216L = abstractC2759w0.P(dDoubleValue3);
                    String low = scriptIndicAction.getLow();
                    if (low == null) {
                        low = "";
                    }
                    String str9 = (String) map2.get(low);
                    double dDoubleValue4 = (str9 == null || (dN2 = Ah.v.n(str9)) == null) ? 0.0d : dN2.doubleValue();
                    this.f95222R = dDoubleValue4;
                    this.f95218N = abstractC2759w0.P(dDoubleValue4);
                    String close = scriptIndicAction.getClose();
                    if (close == null) {
                        close = "";
                    }
                    String str10 = (String) map2.get(close);
                    if (str10 != null && (dN = Ah.v.n(str10)) != null) {
                        dDoubleValue = dN.doubleValue();
                    }
                    double d10 = dDoubleValue;
                    this.f95223S = d10;
                    this.f95219O = abstractC2759w0.P(d10);
                    String strA = kk.f.a(scriptIndicAction, new StringBuilder(), "Value");
                    StringBuilder sb2 = new StringBuilder();
                    f13 = f28;
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
                            this.f95225U.setColor(numP6.intValue());
                            z10 = true;
                        } else {
                            z10 = false;
                        }
                    }
                    float fAbs = (Math.abs(f25 - f13) / f26) + f13;
                    if (i13 <= 0 || jLongValue >= jH) {
                        double d11 = this.f95223S;
                        double d12 = this.f95221Q;
                        if (d11 > d12) {
                            this.f95226V.setStrokeWidth(3.0f);
                            float fFloatValue = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95217M), Float.valueOf(this.f95219O))).floatValue();
                            float fFloatValue2 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95219O), Float.valueOf(this.f95217M))).floatValue();
                            float fFloatValue3 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95218N), Float.valueOf(this.f95216L))).floatValue();
                            float fFloatValue4 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95216L), Float.valueOf(this.f95218N))).floatValue();
                            boolean z11 = fFloatValue2 - fFloatValue >= 2.0f;
                            Paint paint = this.f95226V;
                            int iIntValue = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str5 = (String) map2.get(strA)) == null || (numP5 = Ah.w.p(str5)) == null) ? this.f95214J : numP5.intValue();
                            paint.setColor(iIntValue);
                            Paint paint2 = this.f95224T;
                            int iIntValue2 = (str11 == null || str11.length() == 0 || AbstractC7609s.f(str11, "nullValue") || (str4 = (String) map2.get(str11)) == null || (numP4 = Ah.w.p(str4)) == null) ? this.f95214J : numP4.intValue();
                            paint2.setColor(iIntValue2);
                            if (z11) {
                                canvas.drawRect(f13, fFloatValue, f25 - 1, fFloatValue2, this.f95226V);
                                if (z10) {
                                    float f29 = f13 - f26;
                                    float f30 = fFloatValue - f26;
                                    this.f95230Z.moveTo(f29, f30);
                                    float f31 = f25 + f26;
                                    this.f95230Z.lineTo(f31, f30);
                                    float f32 = fFloatValue2 + f26;
                                    this.f95230Z.lineTo(f31, f32);
                                    this.f95230Z.lineTo(f29, f32);
                                    this.f95230Z.close();
                                    canvas.drawPath(this.f95230Z, this.f95225U);
                                }
                                f13 = f13;
                                fFloatValue = fFloatValue;
                            } else {
                                canvas.drawLine(f13, fFloatValue, f25, fFloatValue, this.f95226V);
                            }
                            if (this.f95220P <= this.f95223S) {
                                f20 = fAbs;
                                f21 = fFloatValue;
                                f22 = fFloatValue3;
                                f23 = fFloatValue4;
                            } else if (o()) {
                                f20 = fAbs;
                                canvas.drawLine(f20, fFloatValue4, fAbs, fFloatValue2, this.f95226V);
                                f23 = fFloatValue4;
                                f21 = fFloatValue;
                                f22 = fFloatValue3;
                            } else {
                                f20 = fAbs;
                                f23 = fFloatValue4;
                                float f33 = fFloatValue;
                                canvas.drawLine(f20, fFloatValue3, f20, f33, this.f95226V);
                                f22 = fFloatValue3;
                                f21 = f33;
                            }
                            float f34 = f20;
                            if (this.f95222R < this.f95221Q) {
                                if (o()) {
                                    canvas.drawLine(f34, f21, f34, f22, this.f95226V);
                                } else {
                                    canvas.drawLine(f34, fFloatValue2, f34, f23, this.f95226V);
                                }
                            }
                        } else if (d11 == d12) {
                            float f35 = this.f95217M;
                            Paint paint3 = this.f95229Y;
                            int iIntValue3 = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str3 = (String) map2.get(strA)) == null || (numP3 = Ah.w.p(str3)) == null) ? this.f95214J : numP3.intValue();
                            paint3.setColor(iIntValue3);
                            this.f95229Y.setStrokeWidth(2.0f);
                            float f36 = f35;
                            canvas.drawLine(f13, f36, f25, f35, this.f95229Y);
                            double d13 = this.f95220P;
                            if (d13 > this.f95223S) {
                                f19 = fAbs;
                                canvas.drawLine(f19, abstractC2759w0.P(d13), fAbs, f36, this.f95229Y);
                                f36 = f36;
                            } else {
                                f19 = fAbs;
                            }
                            double d14 = this.f95221Q;
                            f14 = f25;
                            double d15 = this.f95222R;
                            if (d14 > d15) {
                                canvas.drawLine(f19, f36, f19, abstractC2759w0.P(d15), this.f95229Y);
                            }
                        } else {
                            f14 = f25;
                            this.f95228X.setStrokeWidth(3.0f);
                            float fFloatValue5 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95219O), Float.valueOf(this.f95217M))).floatValue();
                            float fFloatValue6 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95217M), Float.valueOf(this.f95219O))).floatValue();
                            float fFloatValue7 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95218N), Float.valueOf(this.f95216L))).floatValue();
                            float f37 = fFloatValue5;
                            float fFloatValue8 = ((Number) p162hb.e.c(o(), Float.valueOf(this.f95216L), Float.valueOf(this.f95218N))).floatValue();
                            boolean z12 = fFloatValue6 - f37 >= 1.0f;
                            Paint paint4 = this.f95228X;
                            int iIntValue4 = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str2 = (String) map2.get(strA)) == null || (numP2 = Ah.w.p(str2)) == null) ? this.f95215K : numP2.intValue();
                            paint4.setColor(iIntValue4);
                            Paint paint5 = this.f95227W;
                            int iIntValue5 = (str11 == null || str11.length() == 0 || AbstractC7609s.f(str11, "nullValue") || (str = (String) map2.get(str11)) == null || (numP = Ah.w.p(str)) == null) ? this.f95215K : numP.intValue();
                            paint5.setColor(iIntValue5);
                            if (z12) {
                                canvas.drawRect(f13, f37, f14, fFloatValue6, this.f95228X);
                                if (z10) {
                                    float f38 = f13 - f26;
                                    float f39 = f37 - f26;
                                    this.f95230Z.moveTo(f38, f39);
                                    float f40 = f14 + f26;
                                    this.f95230Z.lineTo(f40, f39);
                                    float f41 = fFloatValue6 + f26;
                                    this.f95230Z.lineTo(f40, f41);
                                    this.f95230Z.lineTo(f38, f41);
                                    this.f95230Z.close();
                                    canvas.drawPath(this.f95230Z, this.f95225U);
                                }
                                f13 = f13;
                                f37 = f37;
                                f14 = f14;
                            } else {
                                canvas.drawLine(f13, f37, f14, f37, this.f95228X);
                            }
                            if (this.f95220P <= this.f95221Q) {
                                f15 = fAbs;
                                f16 = fFloatValue7;
                                f17 = f37;
                                f18 = fFloatValue8;
                            } else if (o()) {
                                f15 = fAbs;
                                canvas.drawLine(f15, fFloatValue8, fAbs, fFloatValue6, this.f95228X);
                                f18 = fFloatValue8;
                                f16 = fFloatValue7;
                                f17 = f37;
                            } else {
                                f15 = fAbs;
                                f18 = fFloatValue8;
                                float f42 = f37;
                                canvas.drawLine(f15, fFloatValue7, f15, f42, this.f95228X);
                                f16 = fFloatValue7;
                                f17 = f42;
                            }
                            float f43 = f15;
                            if (this.f95222R < this.f95223S) {
                                if (o()) {
                                    canvas.drawLine(f43, f17, f43, f16, this.f95228X);
                                } else {
                                    canvas.drawLine(f43, fFloatValue6, f43, f18, this.f95228X);
                                }
                            }
                        }
                    }
                    f28 = f13 + f11;
                    f25 = f14 + f11;
                }
                f14 = f25;
                f28 = f13 + f11;
                f25 = f14 + f11;
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
        int i14 = (1 > intShowLast || intShowLast >= (i12 = this.f95231a0)) ? -1 : i12 - intShowLast;
        try {
            y1 y1Var = this.f95239n;
            jH = y1Var != null ? y1Var.H(i14) : 0L;
        } catch (Exception unused) {
        }
        while (i13 < iAbs) {
            y1 y1Var2 = this.f95239n;
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
                    iA = dDoubleValue >= 0.0d ? this.f95214J : this.f95215K;
                } else {
                    String str3 = (String) map2.get(strA);
                    if (str3 == null || (numP = Ah.w.p(str3)) == null) {
                        d10 = 0.0d;
                        iA = f13.u()[this.f95213I].a();
                    } else {
                        iA = numP.intValue();
                        d10 = 0.0d;
                    }
                }
                this.f95249x.setColor(iA);
                if (i14 <= 0 || jLongValue >= jH) {
                    if (dDoubleValue == d10) {
                        float fQ = (abstractC2759w0.u() == d10 && abstractC2759w0.v() == d10) ? abstractC2759w0.q() + fP : fP;
                        f14 = f15;
                        canvas.drawLine(f14, fQ, f16, fQ, this.f95249x);
                        i14 = i14;
                    } else {
                        String series2 = scriptIndicAction.getSeries();
                        if (series2 == null) {
                            series2 = "0";
                        }
                        String str4 = (String) map2.get(series2);
                        float fP2 = abstractC2759w0.P((str4 == null || (dN = Ah.v.n(str4)) == null) ? d10 : dN.doubleValue());
                        if (Math.abs(fP - fP2) < 1.0f) {
                            canvas.drawLine(f15, fP, f16, fP, this.f95249x);
                        } else {
                            i14 = i14;
                            f14 = f15;
                            float fAbs = (Math.abs(f16 - f14) / 2) + f14;
                            float f18 = fP;
                            canvas.drawLine(fAbs, fP2, fAbs, f18, this.f95249x);
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
        int color;
        float f15;
        float f16;
        PointF pointF;
        Integer numP;
        Double dN;
        Double dN2;
        Long lR;
        int i12;
        Path path2 = this.f95250y;
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
        int i14 = (1 > intShowLast || intShowLast >= (i12 = this.f95231a0)) ? -1 : i12 - intShowLast;
        try {
            y1 y1Var = this.f95239n;
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
            y1 y1Var2 = this.f95239n;
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
                    if (dDoubleValue == 0.0d && dDoubleValue2 == 0.0d) {
                        f17 += f11;
                        z10 = true;
                    } else {
                        float fP = abstractC2759w0.P(dDoubleValue);
                        float fP2 = abstractC2759w0.P(dDoubleValue2);
                        if (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue")) {
                            color = Color.parseColor("#1A9915FF");
                        } else {
                            String str4 = (String) map2.get(strA);
                            color = (str4 == null || (numP = Ah.w.p(str4)) == null) ? f12.u()[this.f95213I].a() : numP.intValue();
                        }
                        int i15 = color;
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
            Path path3 = this.f95250y;
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
            Path path4 = this.f95250y;
            if (path4 != null) {
                path4.moveTo(fA, f29);
                hk.a.f98027a.d(fA, f29, fD, f30, f27, path4);
                path4.lineTo(fD, fE);
                path4.lineTo(fA, fB);
                path4.close();
            }
            Paint paint = this.f95251z;
            if (paint != null) {
                paint.setColor(aVar.h());
            }
            Paint paint2 = this.f95251z;
            if (paint2 != null && (path = this.f95250y) != null) {
                canvas.drawPath(path, paint2);
            }
        }
    }

    public final void y(Canvas canvas, AbstractC2759w0 abstractC2759w0, double d10, String str) {
        Ah.j jVarC;
        Ah.j.b bVarA;
        if (this.f95238m != null) {
            float fP = abstractC2759w0.P(d10);
            Path path = this.f95232b0;
            path.reset();
            path.moveTo(this.f95238m.u(), fP);
            path.lineTo(this.f95238m.y(), fP);
            if (str.length() != 0 && (jVarC = Ah.l.c(new Ah.l("rgba\\((\\d+),(\\d+),(\\d+),((?:\\d+(?:\\.\\d*)?|\\.\\d+))\\)"), str, 0, 2, null)) != null && (bVarA = jVarC.a()) != null) {
                Double dN = Ah.v.n((String) kk.j.a(bVarA, 4));
                if (((float) ((dN != null ? dN.doubleValue() : 0.0d) * ((double) 255))) == 0.0f) {
                    return;
                }
            }
            canvas.drawPath(this.f95232b0, this.f95233c0);
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
        if (scriptIndicAction.getOutput().getLineWidth() != null && (paint = this.f95243r) != null) {
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
        Paint paint2 = this.f95243r;
        if (paint2 != null) {
            paint2.setPathEffect(new DashPathEffect(new float[]{fFloatValue, fFloatValue2}, 0.0f));
        }
        y1 y1Var = this.f95239n;
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
        int iA = (strA == null || strA.length() == 0 || AbstractC7609s.f(strA, "nullValue") || (str2 = (String) linkedHashMap.get(strA)) == null || (numP = Ah.w.p(str2)) == null) ? f10.u()[this.f95213I].a() : numP.intValue();
        Paint paint3 = this.f95243r;
        if (paint3 != null) {
            paint3.setColor(iA);
        }
        C2702d c2702d = this.f95238m;
        int iU = c2702d != null ? c2702d.u() : 0;
        y1 y1Var2 = this.f95239n;
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
            y1 y1Var3 = this.f95239n;
            float fJ = (y1Var3 != null ? y1Var3.j(jLongValue * ((long) 1000)) : 0.0f) - fW;
            y1 y1Var4 = this.f95239n;
            float fJ2 = (y1Var4 != null ? y1Var4.j(jLongValue2 * ((long) 1000)) : 0.0f) - fW;
            float fP = abstractC2759w0.P(dDoubleValue);
            float fP2 = abstractC2759w0.P(dDoubleValue2);
            Paint paint4 = this.f95243r;
            if (paint4 != null) {
                canvas.drawRect(fJ, fP, fJ2, fP2, paint4);
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
                    y1 y1Var5 = this.f95239n;
                    float f11 = fW;
                    float fJ3 = (y1Var5 != null ? y1Var5.j(jLongValue3 * ((long) 1000)) : 0.0f) - f11;
                    y1 y1Var6 = this.f95239n;
                    float fJ4 = (y1Var6 != null ? y1Var6.j(((long) 1000) * jLongValue4) : 0.0f) - f11;
                    float fP3 = abstractC2759w0.P(dDoubleValue3);
                    float fP4 = abstractC2759w0.P(dDoubleValue4);
                    Paint paint5 = this.f95243r;
                    if (paint5 != null) {
                        canvas.drawRect(fJ3, fP3, fJ4, fP4, paint5);
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
