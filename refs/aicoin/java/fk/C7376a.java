package fk;

import Rj.AbstractC2735o;
import Rj.AbstractC2744r0;
import Rj.AbstractC2755v;
import Rj.AbstractC2759w0;
import Rj.C2702d;
import Rj.C2732n;
import Rj.C2741q;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.Rect;
import com.tencent.android.tpns.mqtt.MqttTopic;
import gk.C7458d;
import java.util.Arrays;
import java.util.List;
import sp.aicoin_kline.chart.data.AIHandleLineItem;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: fk.a, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7376a extends AbstractC2744r0 {

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public boolean f95306A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public int f95307B;

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public int f95308C;

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final Paint f95309l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final Paint f95310m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final Paint f95311n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final Paint f95312o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final Paint f95313p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final Paint f95314q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final Paint f95315r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public final Paint f95316s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public final Paint f95317t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public final Paint f95318u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public final Path f95319v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public AbstractC2759w0 f95320w;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public C7458d f95321x;

    /* JADX INFO: renamed from: y, reason: collision with root package name */
    public final Rect f95322y;

    /* JADX INFO: renamed from: z, reason: collision with root package name */
    public final Rect f95323z;

    public C7376a(C2732n c2732n, String str) {
        super(c2732n, str);
        Paint paint = new Paint();
        Paint.Style style = Paint.Style.STROKE;
        paint.setStyle(style);
        paint.setAntiAlias(false);
        paint.setPathEffect(paint.getPathEffect());
        Paint paint2 = new Paint();
        Paint.Style style2 = Paint.Style.FILL;
        paint2.setStyle(style2);
        paint2.setAntiAlias(true);
        this.f95309l = paint2;
        Paint paint3 = new Paint();
        paint3.setStyle(style2);
        paint3.setAntiAlias(true);
        this.f95310m = paint3;
        Paint paint4 = new Paint();
        paint4.setStyle(style2);
        paint4.setAntiAlias(true);
        this.f95311n = paint4;
        Paint paint5 = new Paint();
        paint5.setStyle(style2);
        paint5.setAntiAlias(true);
        this.f95312o = paint5;
        Paint paint6 = new Paint();
        paint6.setTextSize(Xj.a.c(9.0f));
        paint6.setAntiAlias(true);
        paint6.setStyle(style2);
        paint6.setColor(Color.parseColor("#FFFFFF"));
        this.f95313p = paint6;
        Paint paint7 = new Paint();
        paint7.setTextSize(Xj.a.c(9.0f));
        paint7.setAntiAlias(true);
        paint7.setStyle(style2);
        paint7.setColor(Color.parseColor("#FFFFFF"));
        this.f95314q = paint7;
        this.f95315r = new Paint(paint);
        this.f95316s = new Paint(paint);
        this.f95317t = new Paint(paint);
        Paint paint8 = new Paint();
        paint8.setStyle(style);
        paint8.setStrokeWidth(2.0f);
        paint8.setAntiAlias(true);
        paint8.setColor(Color.parseColor("#D9D9D9"));
        this.f95318u = paint8;
        this.f95319v = new Path();
        this.f95322y = new Rect();
        this.f95323z = new Rect();
        this.f95307B = -65536;
        this.f95308C = -16711936;
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        AbstractC2759w0 abstractC2759w0;
        C7458d c7458d;
        C2702d c2702dE;
        AbstractC2759w0 abstractC2759w1;
        C2702d c2702d;
        KLineManager kLineManager;
        float f10;
        float f11;
        float f12;
        float f13;
        Double dN;
        Canvas canvas2 = canvas;
        KLineManager.a aVar = KLineManager.f142490O;
        if (!aVar.a().c0() || (abstractC2759w0 = this.f95320w) == null || (c7458d = this.f95321x) == null || (c2702dE = i().b().e(b())) == null) {
            return;
        }
        List listR1 = Sf.z.r1(c7458d.s());
        KLineManager kLineManagerA = aVar.a();
        for (AIHandleLineItem aIHandleLineItem : Sf.z.l0(listR1)) {
            String price = aIHandleLineItem.getPrice();
            double dDoubleValue = (price == null || (dN = Ah.v.n(price)) == null) ? 0.0d : dN.doubleValue();
            if (dDoubleValue <= abstractC2759w0.u() && dDoubleValue >= abstractC2759w0.v()) {
                float fP = abstractC2759w0.P(dDoubleValue);
                Paint paint = aIHandleLineItem.isBids() ? this.f95316s : this.f95315r;
                Paint paint2 = aIHandleLineItem.isBids() ? this.f95310m : this.f95312o;
                if (kLineManagerA.y()) {
                    Path path = this.f95319v;
                    path.reset();
                    path.moveTo(c2702dE.u(), fP);
                    path.lineTo(c2702dE.y(), fP);
                    canvas2.drawPath(this.f95319v, paint);
                } else {
                    boolean zN = kLineManagerA.n();
                    Double dN2 = Ah.v.n(aIHandleLineItem.getProfit());
                    double dDoubleValue2 = dN2 != null ? dN2.doubleValue() : 0.0d;
                    Double dN3 = Ah.v.n(aIHandleLineItem.getDegree());
                    double dDoubleValue3 = dN3 != null ? dN3.doubleValue() : 0.0d;
                    if (dDoubleValue2 >= 0.0d) {
                        this.f95314q.setColor(this.f95308C);
                    } else {
                        this.f95314q.setColor(this.f95307B);
                    }
                    StringBuilder sb2 = new StringBuilder();
                    nk.l lVar = nk.l.f134222a;
                    sb2.append(lVar.t(lVar.j(dDoubleValue2, AbstractC2735o.a(i()))));
                    sb2.append(' ');
                    String string = sb2.toString();
                    StringBuilder sb3 = new StringBuilder("(");
                    Double dValueOf = Double.valueOf(dDoubleValue3);
                    p167hg.T t10 = p167hg.T.f97914a;
                    sb3.append(String.format("%.2f", Arrays.copyOf(new Object[]{dValueOf}, 1)));
                    sb3.append("%) ");
                    String strConcat = kLineManagerA.m() ? String.format("%.2f", Arrays.copyOf(new Object[]{Double.valueOf(dDoubleValue3)}, 1)).concat("%") : kk.i.a(string, sb3.toString());
                    Double dN4 = Ah.v.n(aIHandleLineItem.getPosition());
                    double dDoubleValue4 = dN4 != null ? dN4.doubleValue() : 0.0d;
                    String str = (aIHandleLineItem.isBids() ? MqttTopic.SINGLE_LEVEL_WILDCARD : "-") + lVar.t(lVar.j(dDoubleValue4, AbstractC2735o.a(i()))) + ' ';
                    if (strConcat.length() > 0) {
                        this.f95314q.getTextBounds(strConcat, 0, strConcat.length(), this.f95322y);
                        this.f95313p.getTextBounds(str, 0, str.length(), this.f95323z);
                        float fMeasureText = this.f95314q.measureText(strConcat);
                        float fMeasureText2 = this.f95313p.measureText(str);
                        float fHeight = this.f95322y.height() / 2.0f;
                        float f14 = (fP - fHeight) - 10.0f;
                        float f15 = fHeight + fP;
                        float f16 = 10.0f + f15;
                        float f17 = f15 - 5.0f;
                        if (this.f95306A) {
                            float f18 = 15.0f * 2;
                            float f19 = fMeasureText + 0.0f + f18;
                            abstractC2759w1 = abstractC2759w0;
                            kLineManager = kLineManagerA;
                            c2702d = c2702dE;
                            canvas.drawRect(0.0f, f14, f19, f16, this.f95309l);
                            canvas.drawText(strConcat, 15.0f, f17, this.f95314q);
                            if (!KLineManager.f142490O.a().m()) {
                                float f20 = f19 + fMeasureText2 + f18;
                                canvas.drawRect(f19, f14, f20, f16, paint2);
                                canvas.drawText(str, f19 + 15.0f, f17, this.f95313p);
                                f19 = f20;
                            }
                            canvas.drawRect(0.0f, f14, f19, f16, this.f95318u);
                            if (!zN) {
                                Path path2 = this.f95319v;
                                path2.reset();
                                path2.moveTo(f19, fP);
                                path2.lineTo(c2702d.y(), fP);
                                canvas.drawPath(this.f95319v, paint);
                            }
                            canvas2 = canvas;
                        } else {
                            abstractC2759w1 = abstractC2759w0;
                            c2702d = c2702dE;
                            kLineManager = kLineManagerA;
                            float f21 = 2 * 15.0f;
                            float f22 = fMeasureText + f21;
                            float fY = c2702d.y();
                            if (KLineManager.f142490O.a().m()) {
                                canvas2 = canvas;
                                f10 = fY;
                                f11 = f14;
                                f12 = f16;
                                f13 = f10;
                            } else {
                                float f23 = fMeasureText2 + f21;
                                float fY2 = c2702d.y();
                                float f24 = fY2 - f23;
                                canvas2 = canvas;
                                f10 = fY;
                                f11 = f14;
                                f12 = f16;
                                canvas2.drawRect(f24, f11, fY2, f12, paint2);
                                canvas2.drawText(str, f24 + 15.0f, f17, this.f95313p);
                                f13 = f24;
                            }
                            float f25 = f13 - f22;
                            canvas2.drawRect(f25, f11, f13, f12, this.f95309l);
                            canvas2.drawText(strConcat, f25 + 15.0f, f17, this.f95314q);
                            canvas2.drawRect(f25, f11, f10, f12, this.f95318u);
                            if (!zN) {
                                Path path3 = this.f95319v;
                                path3.reset();
                                path3.moveTo(c2702d.u(), fP);
                                path3.lineTo(f25, fP);
                                canvas2.drawPath(this.f95319v, paint);
                            }
                        }
                    } else {
                        abstractC2759w1 = abstractC2759w0;
                        c2702d = c2702dE;
                        kLineManager = kLineManagerA;
                        if (!zN) {
                            Path path4 = this.f95319v;
                            path4.reset();
                            path4.moveTo(c2702d.u(), fP);
                            path4.lineTo(c2702d.y(), fP);
                            canvas2.drawPath(this.f95319v, paint);
                        }
                    }
                    c2702dE = c2702d;
                    kLineManagerA = kLineManager;
                    abstractC2759w0 = abstractC2759w1;
                }
            }
        }
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        if (aVar == null) {
            return;
        }
        this.f95317t.setColor(Color.parseColor("#FFD700"));
        this.f95311n.setColor(Color.parseColor("#FFD700"));
        KLineManager.a aVar2 = KLineManager.f142490O;
        this.f95308C = aVar.d(aVar2.a().V() ? ".main_red.color" : ".main_green.color");
        this.f95307B = aVar.d(aVar2.a().V() ? ".main_green.color" : ".main_red.color");
        this.f95315r.setStrokeWidth(2.0f);
        this.f95316s.setStrokeWidth(2.0f);
        this.f95317t.setStrokeWidth(2.0f);
        this.f95315r.setColor(this.f95307B);
        this.f95312o.setColor(this.f95307B);
        this.f95310m.setColor(this.f95308C);
        this.f95309l.setColor(-1);
        this.f95316s.setColor(this.f95308C);
        C2741q c2741qB = i().b();
        c2741qB.e(b());
        c2741qB.m(c());
        this.f95320w = c2741qB.l(b());
        this.f95306A = aVar2.a().z();
        AbstractC2755v abstractC2755vQ = q();
        C7458d c7458d = abstractC2755vQ instanceof C7458d ? (C7458d) abstractC2755vQ : null;
        if (c7458d == null) {
            return;
        }
        this.f95321x = c7458d;
    }
}
