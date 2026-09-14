package fk;

import Rj.C2732n;
import Sf.AbstractC2801o;
import android.graphics.Canvas;
import android.graphics.Paint;
import gk.AbstractC7467h0;
import java.util.ArrayList;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class Y extends B {
    public Y(C2732n c2732n, String str, Zj.a aVar) {
        super(c2732n, str, aVar);
    }

    @Override // fk.B, Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        double[] dArr;
        double[] dArr2;
        AbstractC7467h0 abstractC7467h0Y = y();
        if (abstractC7467h0Y == null) {
            return;
        }
        Long[] lArrY = abstractC7467h0Y.y();
        int i10 = 0;
        double[] dArr3 = (double[]) AbstractC2801o.r0(abstractC7467h0Y.v(), 0);
        if (dArr3 == null || (dArr = (double[]) AbstractC2801o.r0(abstractC7467h0Y.v(), 1)) == null || (dArr2 = (double[]) AbstractC2801o.r0(abstractC7467h0Y.v(), 2)) == null) {
            return;
        }
        Paint paint = w() ? z()[0] : A()[0];
        Zj.a aVarX = x();
        Zj.a aVar = Zj.a.DATA;
        if (aVarX == aVar) {
            paint.setStrokeWidth(1.0f);
        }
        Paint paint2 = z()[1];
        if (x() == aVar) {
            paint2.setStrokeWidth(1.0f);
        }
        ek.I i11 = abstractC7467h0Y.x().r()[0];
        ek.I i12 = abstractC7467h0Y.x().r()[1];
        if (i11.b()) {
            if (i12.b()) {
                ArrayList arrayList = new ArrayList(dArr.length);
                int length = dArr.length;
                int i13 = 0;
                while (i10 < length) {
                    double d10 = dArr[i10];
                    int i14 = i13 + 1;
                    Double dN0 = AbstractC2801o.n0(dArr3, i13);
                    arrayList.add(Double.valueOf(d10 + (dN0 != null ? dN0.doubleValue() : 0.0d)));
                    i10++;
                    i13 = i14;
                }
                v(canvas, paint2, Sf.z.n1(arrayList), lArrY);
            }
            v(canvas, paint, dArr3, lArrY);
        } else if (i12.b()) {
            v(canvas, paint2, dArr, lArrY);
        }
        Paint paint3 = w() ? z()[2] : A()[2];
        if (x() == Zj.a.DATA) {
            paint3.setStrokeWidth(1.0f);
        }
        v(canvas, paint3, dArr2, lArrY);
    }

    @Override // fk.B, Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        if (aVar == null) {
            return;
        }
        super.u(aVar);
        Paint paintA = kk.c.a(false);
        Paint.Style style = Paint.Style.FILL;
        paintA.setStyle(style);
        paintA.setColor(aVar.r());
        Qf.H h10 = Qf.H.f17640a;
        Paint paint = new Paint();
        paint.setAntiAlias(false);
        paint.setStyle(style);
        paint.setColor(aVar.m());
        Paint paint2 = new Paint();
        paint2.setAntiAlias(false);
        paint2.setStyle(style);
        paint2.setColor(aVar.v());
        C(new Paint[]{paintA, paint, paint2});
        Paint paint3 = new Paint();
        paint3.setAntiAlias(false);
        Paint.Style style2 = Paint.Style.STROKE;
        paint3.setStyle(style2);
        paint3.setColor(aVar.r());
        paint3.setStrokeWidth(2.0f);
        Paint paint4 = new Paint();
        paint4.setAntiAlias(false);
        paint4.setStyle(style2);
        paint4.setColor(aVar.m());
        paint4.setStrokeWidth(2.0f);
        Paint paint5 = new Paint();
        paint5.setAntiAlias(false);
        paint5.setStyle(style2);
        paint5.setColor(aVar.v());
        paint5.setStrokeWidth(2.0f);
        D(new Paint[]{paint3, paint4, paint5});
        B(KLineManager.f142490O.a().q(9) == 0);
    }
}
