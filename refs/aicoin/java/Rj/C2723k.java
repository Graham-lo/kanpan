package Rj;

import android.graphics.Canvas;
import android.graphics.Paint;
import java.util.ArrayList;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: Rj.k, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C2723k extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final Paint f19439l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final Paint f19440m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final Paint f19441n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final Paint f19442o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final Paint f19443p;

    public C2723k(C2732n c2732n, String str) {
        super(c2732n, str);
        Paint paint = new Paint();
        this.f19439l = paint;
        Paint paint2 = new Paint();
        this.f19440m = paint2;
        Paint paint3 = new Paint();
        this.f19443p = paint3;
        Paint paint4 = new Paint();
        this.f19441n = paint4;
        Paint paint5 = new Paint();
        this.f19442o = paint5;
        Paint.Style style = Paint.Style.FILL_AND_STROKE;
        paint4.setStyle(style);
        KLineManager.a aVar = KLineManager.f142490O;
        if (aVar.a().f0() == 1) {
            paint2.setStrokeWidth(1.0f);
            paint5.setStrokeWidth(1.0f);
        }
        paint.setStrokeWidth(2.0f);
        paint4.setStrokeWidth(2.0f);
        int iQ = aVar.a().q(9);
        if (iQ == 0) {
            paint2.setStyle(style);
            paint3.setStyle(style);
        } else {
            if (iQ != 1) {
                return;
            }
            paint2.setStrokeWidth(2.0f);
            Paint.Style style2 = Paint.Style.STROKE;
            paint2.setStyle(style2);
            paint3.setStyle(style2);
        }
    }

    /* JADX WARN: Code duplicated, block: B:66:0x02da  */
    /* JADX WARN: Code duplicated, block: B:68:0x02e0  */
    /* JADX WARN: Code duplicated, block: B:69:0x02ee  */
    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        y1 y1VarM;
        AbstractC2759w0 abstractC2759w0L;
        ArrayList arrayListS;
        boolean z10;
        ArrayList arrayList;
        float f10;
        float f11;
        float f12;
        float f13;
        float f14;
        float f15;
        float f16;
        float f17;
        float f18;
        C2741q c2741qB = i().b();
        C2765z c2765zH = c2741qB.h(c());
        if (c2765zH == null || (y1VarM = c2741qB.m(c())) == null || (abstractC2759w0L = c2741qB.l(b())) == null) {
            return;
        }
        boolean z11 = true;
        int iD = c2765zH.D() - 1;
        AbstractC2755v abstractC2755vG = c2741qB.g(d());
        if (abstractC2755vG == null || (arrayListS = ((AbstractC2720j) abstractC2755vG).s()) == null) {
            return;
        }
        float fU = y1VarM.u();
        float f19 = 2;
        float fJ = y1VarM.J();
        int iR = y1VarM.r();
        float f20 = (fU / 6) - fJ;
        int iQ = y1VarM.q() + 1;
        float f21 = (fU / f19) - fJ;
        int i10 = iR;
        float f22 = ((fU * f19) / 3) + f20;
        float f23 = f20;
        while (i10 < iQ) {
            Sj.b bVarD = (Sj.b) Sf.z.r0(arrayListS, i10);
            if (bVarD == null) {
                arrayList = arrayListS;
                z10 = z11;
                i10 = i10;
            } else {
                if (i10 == iD) {
                    bVarD = nk.c.f134195a.d(bVarD);
                }
                Sj.b bVar = bVarD;
                float fS = abstractC2759w0L.S(bVar.d());
                float fS2 = abstractC2759w0L.S(bVar.a());
                float fS3 = abstractC2759w0L.S(bVar.b());
                float fS4 = abstractC2759w0L.S(bVar.c());
                if (bVar.a() > bVar.d()) {
                    float fFloatValue = ((Number) p162hb.e.c(o(), Float.valueOf(fS), Float.valueOf(fS2))).floatValue();
                    float fFloatValue2 = ((Number) p162hb.e.c(o(), Float.valueOf(fS2), Float.valueOf(fS))).floatValue();
                    float fFloatValue3 = ((Number) p162hb.e.c(o(), Float.valueOf(fS4), Float.valueOf(fS3))).floatValue();
                    float fFloatValue4 = ((Number) p162hb.e.c(o(), Float.valueOf(fS3), Float.valueOf(fS4))).floatValue();
                    if (fFloatValue2 - fFloatValue >= 2.0f) {
                        f14 = fFloatValue2;
                        canvas.drawRect(f23, fFloatValue, f22 - 1, f14, this.f19440m);
                        z10 = true;
                        f15 = fFloatValue;
                    } else {
                        f14 = fFloatValue2;
                        z10 = true;
                        f15 = fFloatValue;
                        canvas.drawLine(f23, f15, f22, fFloatValue, this.f19439l);
                    }
                    if (bVar.b() <= bVar.a()) {
                        f16 = f15;
                        f17 = fFloatValue3;
                        f18 = fFloatValue4;
                    } else if (o()) {
                        canvas.drawLine(f21, fFloatValue4, f21, f14, this.f19439l);
                        f18 = fFloatValue4;
                        f16 = f15;
                        f17 = fFloatValue3;
                    } else {
                        f18 = fFloatValue4;
                        f16 = f15;
                        f17 = fFloatValue3;
                        canvas.drawLine(f21, f17, f21, f16, this.f19439l);
                    }
                    if (bVar.c() < bVar.d()) {
                        if (o()) {
                            canvas.drawLine(f21, f16, f21, f17, this.f19439l);
                        } else {
                            canvas.drawLine(f21, f14, f21, f18, this.f19439l);
                        }
                    }
                } else {
                    z10 = z11;
                    i10 = i10;
                    if (bVar.a() == bVar.d()) {
                        this.f19443p.setStrokeWidth(2.0f);
                        canvas.drawLine(f23, fS, f22, fS, this.f19443p);
                        float f24 = fS;
                        if (bVar.b() > bVar.a()) {
                            canvas.drawLine(f21, abstractC2759w0L.S(bVar.b()), f21, f24, this.f19443p);
                            f24 = f24;
                        }
                        if (bVar.d() > bVar.c()) {
                            canvas.drawLine(f21, f24, f21, abstractC2759w0L.S(bVar.c()), this.f19443p);
                        }
                    } else {
                        arrayList = arrayListS;
                        float fFloatValue5 = ((Number) p162hb.e.c(o(), Float.valueOf(fS2), Float.valueOf(fS))).floatValue();
                        float fFloatValue6 = ((Number) p162hb.e.c(o(), Float.valueOf(fS), Float.valueOf(fS2))).floatValue();
                        float fFloatValue7 = ((Number) p162hb.e.c(o(), Float.valueOf(fS4), Float.valueOf(fS3))).floatValue();
                        float fFloatValue8 = ((Number) p162hb.e.c(o(), Float.valueOf(fS3), Float.valueOf(fS4))).floatValue();
                        if (fFloatValue6 - fFloatValue5 >= 1.0f) {
                            f10 = fFloatValue5;
                            canvas.drawRect(f23, f10, f22, fFloatValue6, this.f19442o);
                        } else {
                            f10 = fFloatValue5;
                            canvas.drawLine(f23, f10, f22, f10, this.f19441n);
                        }
                        if (bVar.b() > bVar.d()) {
                            if (o()) {
                                canvas.drawLine(f21, fFloatValue8, f21, fFloatValue6, this.f19441n);
                                f12 = fFloatValue8;
                                f11 = fFloatValue6;
                            } else {
                                f11 = fFloatValue6;
                                f12 = fFloatValue8;
                                f13 = fFloatValue7;
                                canvas.drawLine(f21, f13, f21, f10, this.f19441n);
                            }
                            if (bVar.c() < bVar.a()) {
                                if (o()) {
                                    canvas.drawLine(f21, f10, f21, f13, this.f19441n);
                                } else {
                                    canvas.drawLine(f21, f11, f21, f12, this.f19441n);
                                }
                            }
                        } else {
                            f11 = fFloatValue6;
                            f12 = fFloatValue8;
                        }
                        f13 = fFloatValue7;
                        if (bVar.c() < bVar.a()) {
                            if (o()) {
                                canvas.drawLine(f21, f10, f21, f13, this.f19441n);
                            } else {
                                canvas.drawLine(f21, f11, f21, f12, this.f19441n);
                            }
                        }
                    }
                    f23 += fU;
                    f22 += fU;
                    f21 += fU;
                }
                arrayList = arrayListS;
                f23 += fU;
                f22 += fU;
                f21 += fU;
            }
            i10++;
            arrayListS = arrayList;
            z11 = z10;
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
        this.f19439l.setColor(aVar.q());
        this.f19440m.setColor(aVar.q());
        this.f19441n.setColor(aVar.l());
        this.f19442o.setColor(aVar.l());
        this.f19443p.setColor(aVar.q());
    }
}
