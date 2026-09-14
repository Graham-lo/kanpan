package Rj;

import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Typeface;
import kotlin.jvm.internal.DefaultConstructorMarker;
import sp.aicoin_kline.R;

/* JADX INFO: loaded from: classes7.dex */
public final class J0 extends AbstractC2744r0 {

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public static final a f19153o = new a(null);

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public static final Ah.l f19154p = new Ah.l("\\.script_indic(\\d+)");

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final Paint f19155l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final float f19156m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public String f19157n;

    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public J0(C2732n c2732n, String str) {
        super(c2732n, str);
        Paint paint = new Paint(1);
        paint.setTextAlign(Paint.Align.RIGHT);
        paint.setTextSize(Xj.a.d(11));
        paint.setTypeface(Typeface.create(Typeface.DEFAULT, 1));
        paint.setColor(1929379840);
        this.f19155l = paint;
        this.f19156m = -paint.getFontMetrics().top;
        this.f19157n = "";
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        C2702d c2702dE;
        Integer numP;
        String str;
        boolean zD = false;
        if (Ah.y.T(b(), ".script_indic", false, 2, null)) {
            Ah.j jVarC = Ah.l.c(f19154p, b(), 0, 2, null);
            if (jVarC != null && (numP = Ah.w.p((String) jVarC.b().get(1))) != null) {
                Qf.p pVar = (Qf.p) Sf.z.r0(C2760w1.f19594a.h(), numP.intValue());
                if (pVar != null && (str = (String) pVar.d()) != null) {
                    zD = nk.n.e(str);
                }
            }
        } else {
            AbstractC2759w0 abstractC2759w0L = i().b().l(b());
            if (abstractC2759w0L != null) {
                zD = nk.n.d(abstractC2759w0L.A());
            }
        }
        if (zD && (c2702dE = i().b().e(b())) != null) {
            canvas.drawText(this.f19157n, c2702dE.y() - Xj.a.d(4), c2702dE.z() + this.f19156m, this.f19155l);
        }
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
        this.f19157n = i().c().getString(R.string.kline_reversal_flipped);
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        if (aVar == null) {
            return;
        }
        this.f19157n = i().c().getString(R.string.kline_reversal_flipped);
        this.f19155l.setColor(nk.b.a(1.0f, aVar.u(1)));
    }
}
