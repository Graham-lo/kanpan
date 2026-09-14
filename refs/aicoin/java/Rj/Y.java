package Rj;

import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class Y extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public a f19276l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final Paint f19277m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final Paint f19278n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final int f19279o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final float f19280p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final int f19281q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final int f19282r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public int f19283s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public boolean f19284t;

    public enum a {
        Polygon,
        Arrow;


        /* JADX INFO: renamed from: d, reason: collision with root package name */
        public static final /* synthetic */ Zf.a f19288d = Zf.b.a(a());
    }

    public /* synthetic */ class b {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public static final /* synthetic */ int[] f19289a;

        static {
            int[] iArr = new int[a.values().length];
            try {
                iArr[a.Polygon.ordinal()] = 1;
            } catch (NoSuchFieldError unused) {
            }
            try {
                iArr[a.Arrow.ordinal()] = 2;
            } catch (NoSuchFieldError unused2) {
            }
            f19289a = iArr;
        }
    }

    public Y(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f19276l = a.Polygon;
        Paint paint = new Paint();
        Paint.Style style = Paint.Style.FILL;
        paint.setStyle(style);
        this.f19277m = paint;
        Paint paint2 = new Paint();
        paint2.setAntiAlias(true);
        paint2.setStyle(style);
        paint2.setTextSize(nk.l.p(KLineManager.f142490O.a().i(), 2, 9.0f));
        this.f19278n = paint2;
        Paint.FontMetrics fontMetrics = paint2.getFontMetrics();
        double dCeil = Math.ceil(fontMetrics.bottom - fontMetrics.top);
        this.f19279o = (int) dCeil;
        this.f19280p = (-(((float) dCeil) / 2.0f)) - fontMetrics.top;
        this.f19281q = (int) nk.l.o(1, 1.0f);
        this.f19282r = (int) nk.l.o(1, 1.0f);
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        C2702d c2702dE;
        String strF;
        AbstractC2759w0 abstractC2759w0L;
        AbstractC2755v abstractC2755vG;
        C2741q c2741qB = i().b();
        String strB = b();
        if (strB == null || (c2702dE = c2741qB.e(strB)) == null || (strF = f()) == null || (abstractC2759w0L = c2741qB.l(strF)) == null || abstractC2759w0L.z() == 0.0d || (abstractC2755vG = c2741qB.g(strF.concat(".m"))) == null) {
            return;
        }
        double dI = abstractC2755vG.i();
        if (Double.isNaN(dI)) {
            return;
        }
        if (this.f19284t) {
            dI = nk.c.e(dI);
        }
        float fU = c2702dE.u() + this.f19281q;
        float fY = c2702dE.y() - this.f19282r;
        float fP = abstractC2759w0L.P(dI);
        int i10 = this.f19279o >> 1;
        int i11 = b.f19289a[this.f19276l.ordinal()];
        if (i11 != 1) {
            if (i11 != 2) {
                throw new Qf.n();
            }
            int color = this.f19278n.getColor();
            this.f19278n.setColor(this.f19283s);
            float f10 = this.f19279o >> 2;
            float f11 = fU + f10;
            canvas.drawLine(fU, fP, f11, fP - f10, this.f19278n);
            canvas.drawLine(fU, fP, i10 + fU, fP, this.f19278n);
            canvas.drawLine(fU, fP, f11, fP + f10, this.f19278n);
            this.f19278n.setTextAlign(Paint.Align.LEFT);
            canvas.drawText(nk.j.f134218a.a(dI), (this.f19279o * 0.6f) + fU, fP + this.f19280p, this.f19278n);
            this.f19278n.setColor(color);
            return;
        }
        float f12 = i10;
        float f13 = fP - f12;
        float f14 = f12 + fP;
        Path path = new Path();
        path.moveTo(fU, f13);
        path.lineTo(fY, f13);
        path.lineTo(fY, f14);
        path.lineTo(fU, f14);
        path.close();
        canvas.drawPath(path, this.f19277m);
        this.f19278n.setTextAlign(Paint.Align.CENTER);
        canvas.drawText(c2741qB.f19512t + nk.l.f134222a.j(dI, AbstractC2735o.a(i())), c2702dE.q(), fP + this.f19280p, this.f19278n);
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        if (aVar == null) {
            return;
        }
        this.f19277m.setColor(aVar.c(6));
        this.f19278n.setColor(aVar.d(".volume.latest_color"));
        this.f19283s = aVar.b(1);
    }
}
