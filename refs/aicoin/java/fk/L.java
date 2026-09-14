package fk;

import Rj.AbstractC2735o;
import Rj.C2702d;
import Rj.C2732n;
import Rj.C2741q;
import Rj.y1;
import Sf.AbstractC2801o;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Rect;
import gk.C7490t0;
import sp.aicoin_kline.chart.Chart;
import sp.aicoin_kline.chart.data.SubIndicNamePosition;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class L extends Rj.T {

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public C2702d f95087r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public y1 f95088s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public Rj.G f95089t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public C7490t0 f95090u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public final nk.r f95091v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public final Rect f95092w;

    public L(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f95091v = new nk.r();
        this.f95092w = new Rect();
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        C2702d c2702d;
        y1 y1Var;
        Rj.G g10;
        float f10;
        Double dN0;
        Double dN1;
        Double dN2;
        C7490t0 c7490t0 = this.f95090u;
        if (c7490t0 == null || (c2702d = this.f95087r) == null || (y1Var = this.f95088s) == null || (g10 = this.f95089t) == null || c7490t0.v().length == 0) {
            return;
        }
        Rect rectN = c2702d.n();
        ek.w[] wVarArrL = c7490t0.x().l();
        StringBuffer stringBuffer = new StringBuffer("MACD(");
        nk.h hVar = nk.h.f134211a;
        stringBuffer.append(nk.h.d(hVar, wVarArrL[0].g(), String.valueOf(wVarArrL[0].g()), 0, 4, null));
        stringBuffer.append(",");
        stringBuffer.append(nk.h.d(hVar, wVarArrL[1].g(), String.valueOf(wVarArrL[1].g()), 0, 4, null));
        stringBuffer.append(",");
        stringBuffer.append(nk.h.d(hVar, wVarArrL[2].g(), String.valueOf(wVarArrL[2].g()), 0, 4, null));
        stringBuffer.append(")");
        float fMeasureText = x().measureText(stringBuffer.toString());
        nk.r.b bVarD = this.f95091v.c().d();
        if (rectN.width() < fMeasureText) {
            return;
        }
        canvas.drawText(stringBuffer.toString(), w() + rectN.left, v() + rectN.top, x());
        x().getTextBounds(stringBuffer.toString(), 0, stringBuffer.toString().length(), this.f95092w);
        nk.q.a aVar = nk.q.f134234e;
        nk.q qVarA = aVar.a();
        qVarA.j(new SubIndicNamePosition(this.f95092w.width(), rectN.top, "macd", false, "MACD", 8, null));
        float f11 = 15;
        qVarA.g(w() + rectN.left, (v() + rectN.top) - f11, w() + rectN.left + this.f95092w.width() + f11, Math.abs(x().getFontMetrics().ascent) + v() + rectN.top + x().getFontMetrics().descent + f11);
        bVarD.e(qVarA);
        rectN.left += (int) fMeasureText;
        int iIntValue = ((Number) p162hb.e.c(nk.n.f(13), Integer.valueOf(g10.t()), Integer.valueOf(y1Var.D()))).intValue();
        double[] dArr = (double[]) AbstractC2801o.r0(c7490t0.v(), 0);
        double dDoubleValue = Double.NaN;
        double dDoubleValue2 = (dArr == null || (dN2 = AbstractC2801o.n0(dArr, iIntValue)) == null) ? Double.NaN : dN2.doubleValue();
        double[] dArr2 = (double[]) AbstractC2801o.r0(c7490t0.v(), 1);
        double dDoubleValue3 = (dArr2 == null || (dN1 = AbstractC2801o.n0(dArr2, iIntValue)) == null) ? Double.NaN : dN1.doubleValue();
        double[] dArr3 = (double[]) AbstractC2801o.r0(c7490t0.v(), 2);
        if (dArr3 != null && (dN0 = AbstractC2801o.n0(dArr3, iIntValue)) != null) {
            dDoubleValue = dN0.doubleValue();
        }
        double[] dArr4 = {dDoubleValue2, dDoubleValue3, dDoubleValue};
        if (this.f95087r != null) {
            if (Double.isNaN(dArr4[0])) {
                f10 = f11;
            } else {
                StringBuilder sb2 = new StringBuilder(" DIF:");
                double d10 = dArr4[0];
                f10 = f11;
                sb2.append(nk.h.f(hVar, d10, nk.l.n(nk.l.f134222a, d10, 0, 9, 0, AbstractC2735o.a(i()), 8, null), 0, 4, null));
                String string = sb2.toString();
                float fMeasureText2 = y()[0].measureText(string);
                if (rectN.width() >= fMeasureText2) {
                    canvas.drawText(string, w() + rectN.left, v() + rectN.top, y()[0]);
                    y()[0].getTextBounds(string, 0, string.length(), this.f95092w);
                    nk.q qVarA2 = aVar.a();
                    qVarA2.j(new SubIndicNamePosition(this.f95092w.width(), rectN.top, "macd", false, "MACD", 8, null));
                    qVarA2.g(w() + rectN.left, (v() + rectN.top) - f10, w() + rectN.left + this.f95092w.width() + f10, Math.abs(y()[0].getFontMetrics().ascent) + v() + rectN.top + y()[0].getFontMetrics().descent + f10);
                    bVarD.e(qVarA2);
                    rectN.left += (int) fMeasureText2;
                }
            }
            if (!Double.isNaN(dArr4[1])) {
                StringBuilder sb3 = new StringBuilder(" DEA:");
                double d11 = dArr4[1];
                sb3.append(nk.h.f(hVar, d11, nk.l.n(nk.l.f134222a, d11, 0, 9, 0, AbstractC2735o.a(i()), 8, null), 0, 4, null));
                String string2 = sb3.toString();
                float fMeasureText3 = y()[1].measureText(string2);
                if (rectN.width() >= fMeasureText3) {
                    canvas.drawText(string2, w() + rectN.left, v() + rectN.top, y()[1]);
                    y()[1].getTextBounds(string2, 0, string2.length(), this.f95092w);
                    nk.q qVarA3 = aVar.a();
                    qVarA3.j(new SubIndicNamePosition(this.f95092w.width(), rectN.top, "macd", false, "MACD", 8, null));
                    qVarA3.g(w() + rectN.left, (v() + rectN.top) - f10, w() + rectN.left + this.f95092w.width() + f10, Math.abs(y()[1].getFontMetrics().ascent) + v() + rectN.top + y()[1].getFontMetrics().descent + f10);
                    bVarD.e(qVarA3);
                    rectN.left += (int) fMeasureText3;
                }
            }
            if (!Double.isNaN(dArr4[2])) {
                StringBuilder sb4 = new StringBuilder(" MACD:");
                double d12 = dArr4[2];
                sb4.append(nk.h.f(hVar, d12, nk.l.n(nk.l.f134222a, d12, 0, 9, 0, AbstractC2735o.a(i()), 8, null), 0, 4, null));
                String string3 = sb4.toString();
                float fMeasureText4 = y()[2].measureText(string3);
                if (rectN.width() >= fMeasureText4) {
                    canvas.drawText(string3, w() + rectN.left, v() + rectN.top, y()[2]);
                    y()[2].getTextBounds(string3, 0, string3.length(), this.f95092w);
                    nk.q qVarA4 = aVar.a();
                    qVarA4.j(new SubIndicNamePosition(this.f95092w.width(), rectN.top, "macd", false, "MACD", 8, null));
                    qVarA4.g(w() + rectN.left, (v() + rectN.top) - f10, w() + rectN.left + this.f95092w.width() + f10, Math.abs(y()[2].getFontMetrics().ascent) + v() + rectN.top + y()[2].getFontMetrics().descent + f10);
                    bVarD.e(qVarA4);
                    rectN.left += (int) fMeasureText4;
                }
            }
        }
        bVarD.b();
    }

    @Override // Rj.AbstractC2744r0
    public boolean n(String str, int i10, int i11) {
        Object objD;
        KLineManager.a aVar = KLineManager.f142490O;
        if (!aVar.a().Z() || (objD = this.f95091v.d(i10, i11)) == null) {
            return false;
        }
        SubIndicNamePosition subIndicNamePosition = (SubIndicNamePosition) objD;
        int y10 = subIndicNamePosition.getY();
        if (aVar.a().Z()) {
            Context contextC = i().c();
            int[] iArr = new int[2];
            Chart chartA = i().a();
            if (chartA != null) {
                chartA.getLocationOnScreen(iArr);
            }
            new Rj.S(contextC, false).f(i().a(), 10 + iArr[0], y10 + iArr[1], subIndicNamePosition.getKey(), subIndicNamePosition.getTitle(), new K());
        }
        return true;
    }

    @Override // Rj.T, Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        super.u(aVar);
        C2741q c2741qB = i().b();
        this.f95087r = c2741qB.e(b());
        this.f95088s = c2741qB.m(c());
        this.f95089t = c2741qB.i(c());
        this.f95090u = (C7490t0) c2741qB.g(b() + ".m");
    }
}
