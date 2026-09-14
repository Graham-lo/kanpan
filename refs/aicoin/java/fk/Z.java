package fk;

import Rj.C2732n;
import Sf.AbstractC2801o;
import android.graphics.Canvas;
import android.graphics.Paint;
import gk.AbstractC7467h0;
import java.util.ArrayList;

/* JADX INFO: loaded from: classes7.dex */
public final class Z extends F {
    public Z(C2732n c2732n, String str, Zj.a aVar) {
        super(c2732n, str, aVar);
    }

    @Override // fk.F, Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        double[] dArr;
        double[] dArr2;
        AbstractC7467h0 abstractC7467h0W = w();
        if (abstractC7467h0W == null) {
            return;
        }
        Long[] lArrY = abstractC7467h0W.y();
        int i10 = 0;
        double[] dArr3 = (double[]) AbstractC2801o.r0(abstractC7467h0W.v(), 0);
        if (dArr3 == null || (dArr = (double[]) AbstractC2801o.r0(abstractC7467h0W.v(), 1)) == null || (dArr2 = (double[]) AbstractC2801o.r0(abstractC7467h0W.v(), 2)) == null) {
            return;
        }
        Paint paint = x()[0];
        paint.setStrokeWidth(2.0f);
        Paint paint2 = x()[1];
        paint2.setStrokeWidth(2.0f);
        ek.I i11 = abstractC7467h0W.x().r()[0];
        ek.I i12 = abstractC7467h0W.x().r()[1];
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
        v(canvas, x()[2], dArr2, lArrY);
    }

    @Override // fk.F, Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        if (aVar == null) {
            return;
        }
        super.u(aVar);
        Paint paintA = kk.c.a(false);
        Paint.Style style = Paint.Style.FILL;
        paintA.setStyle(style);
        paintA.setColor(aVar.m());
        paintA.setStrokeWidth(2.0f);
        Qf.H h10 = Qf.H.f17640a;
        Paint paint = new Paint();
        paint.setAntiAlias(false);
        paint.setStyle(style);
        paint.setColor(aVar.r());
        paint.setStrokeWidth(2.0f);
        Paint paint2 = new Paint();
        paint2.setAntiAlias(false);
        paint2.setStyle(style);
        paint2.setColor(aVar.v());
        paint2.setStrokeWidth(2.0f);
        y(new Paint[]{paintA, paint, paint2});
    }
}
