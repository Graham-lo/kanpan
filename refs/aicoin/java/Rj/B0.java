package Rj;

import android.graphics.Canvas;
import android.graphics.Paint;
import java.text.DecimalFormat;
import java.util.ArrayList;
import java.util.List;

/* JADX INFO: loaded from: classes7.dex */
public class B0 extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final int f19033l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final int f19034m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final Paint f19035n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final Paint f19036o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public boolean f19037p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final int f19038q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final List f19039r;

    public B0(C2732n c2732n, String str) {
        super(c2732n, str);
        new DecimalFormat("#.00");
        Paint paint = new Paint();
        this.f19035n = paint;
        Paint paint2 = new Paint();
        this.f19036o = paint2;
        this.f19039r = Sf.r.t(52, 56);
        paint.setAntiAlias(true);
        paint.setTextAlign(Paint.Align.CENTER);
        paint.setTextSize(Xj.a.d(9));
        Paint.FontMetrics fontMetrics = paint.getFontMetrics();
        int iCeil = (int) Math.ceil(fontMetrics.bottom - fontMetrics.top);
        this.f19038q = iCeil;
        this.f19033l = (-(iCeil >> 1)) - ((int) fontMetrics.top);
        paint2.setStyle(Paint.Style.STROKE);
        this.f19034m = Xj.a.b(4);
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        y1 y1VarM;
        String strF;
        AbstractC2759w0 abstractC2759w0L;
        String strI;
        C2741q c2741qB = i().b();
        C2702d c2702dE = c2741qB.e(b());
        if (c2702dE == null || (y1VarM = c2741qB.m(c())) == null || (strF = f()) == null || (abstractC2759w0L = c2741qB.l(strF)) == null || abstractC2759w0L.z() == 0.0d) {
            return;
        }
        ArrayList arrayListP = abstractC2759w0L.p();
        boolean z10 = abstractC2759w0L instanceof C2694a0;
        boolean z11 = abstractC2759w0L instanceof C2742q0;
        if (arrayListP.size() == 0) {
            return;
        }
        int i10 = 0;
        Double dValueOf = arrayListP.size() == 1 ? (Double) arrayListP.get(0) : Double.valueOf(((Number) arrayListP.get(0)).doubleValue() - ((Number) arrayListP.get(1)).doubleValue());
        String str = this.f19037p ? c2741qB.f19512t : "";
        int iU = c2702dE.u();
        int iY = c2702dE.y();
        int iQ = c2702dE.q();
        int size = arrayListP.size();
        if (z11) {
            int size2 = ((C2742q0) abstractC2759w0L).Y().size();
            while (i10 < size2) {
                double dDoubleValue = ((Number) arrayListP.get(i10)).doubleValue();
                if (Double.isInfinite(dDoubleValue)) {
                    i10++;
                } else {
                    float fS = abstractC2759w0L.S(dDoubleValue);
                    int i11 = iQ;
                    int i12 = iY;
                    canvas.drawLine(iU, fS, this.f19034m + iU, fS, this.f19036o);
                    canvas.drawLine(i12 - this.f19034m, fS, i12, fS, this.f19036o);
                    double dS = y1VarM.s();
                    canvas.drawText(kk.i.a(str, kk.h.a(new StringBuilder(), nk.l.f134222a.i(((dDoubleValue - dS) * ((double) 100)) / dS, 2, AbstractC2735o.a(i())), '%')), i11, fS + this.f19033l, this.f19035n);
                    i10++;
                    iY = i12;
                    iQ = i11;
                }
            }
            return;
        }
        Canvas canvas2 = canvas;
        int i13 = 0;
        while (i13 < size) {
            double dDoubleValue2 = ((Number) arrayListP.get(i13)).doubleValue();
            if (Double.isInfinite(dDoubleValue2)) {
                i13++;
            } else {
                int i14 = i13;
                float fS2 = abstractC2759w0L.S(dDoubleValue2);
                int i15 = iQ;
                int i16 = size;
                AbstractC2759w0 abstractC2759w0 = abstractC2759w0L;
                ArrayList arrayList = arrayListP;
                canvas2.drawLine(iU, fS2, this.f19034m + iU, fS2, this.f19036o);
                canvas2 = canvas;
                canvas2.drawLine(iY - this.f19034m, fS2, iY, fS2, this.f19036o);
                if (Ah.y.T(strF, "main", false, 2, null)) {
                    strI = (dValueOf.doubleValue() <= 0.99d || z10) ? nk.l.f134222a.j(dDoubleValue2, AbstractC2735o.a(i())) : nk.l.f134222a.i(dDoubleValue2, 0, AbstractC2735o.a(i()));
                } else if (this.f19039r.contains(Integer.valueOf(abstractC2759w0.A()))) {
                    strI = nk.l.f134222a.g(Double.valueOf(dDoubleValue2), abstractC2759w0.A() == 56 ? "publicScript-activeTradeVolume" : "publicScript-fundingRate");
                } else {
                    strI = nk.h.i(nk.h.f134211a, dDoubleValue2, false, 0, AbstractC2735o.a(i()), 6, null);
                }
                canvas2.drawText(kk.i.a(str, strI), i15, fS2 + this.f19033l, this.f19035n);
                i13 = i14 + 1;
                iQ = i15;
                size = i16;
                abstractC2759w0L = abstractC2759w0;
                arrayListP = arrayList;
            }
        }
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        this.f19035n.setColor(aVar.u(4));
        this.f19036o.setColor(aVar.g(2));
    }

    public int v(double d10) {
        String strJ;
        C2741q c2741qB = i().b();
        String strF = f();
        if (strF == null) {
            strF = "";
        }
        double dAbs = Math.abs(d10);
        if (d10 == -1.7976931348623157E308d || d10 == Double.MAX_VALUE) {
            strJ = "NaN";
        } else {
            strJ = Ah.y.T(strF, "main", false, 2, null) ? nk.l.f134222a.j(dAbs, AbstractC2735o.a(i())) : nk.h.i(nk.h.f134211a, dAbs, false, 0, AbstractC2735o.a(i()), 6, null);
        }
        String str = this.f19037p ? c2741qB.f19512t : "";
        return ((int) this.f19035n.measureText(str + strJ)) + (this.f19034m << 1);
    }

    public int w() {
        return this.f19038q;
    }

    public final void x(boolean z10) {
        this.f19037p = z10;
    }

    public void y(DecimalFormat decimalFormat) {
    }
}
