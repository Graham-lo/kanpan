package Rj;

import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import java.text.DecimalFormat;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class V1 extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public DecimalFormat f19252l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public a f19253m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final Paint f19254n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final Paint f19255o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final int f19256p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final float f19257q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final int f19258r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public final int f19259s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public int f19260t;

    public enum a {
        Polygon,
        Arrow;


        /* JADX INFO: renamed from: d, reason: collision with root package name */
        public static final /* synthetic */ Zf.a f19264d = Zf.b.a(a());
    }

    public /* synthetic */ class b {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public static final /* synthetic */ int[] f19265a;

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
            f19265a = iArr;
        }
    }

    public V1(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f19252l = new DecimalFormat("#.00");
        this.f19253m = a.Polygon;
        Paint paint = new Paint();
        Paint.Style style = Paint.Style.FILL;
        paint.setStyle(style);
        this.f19254n = paint;
        Paint paint2 = new Paint();
        paint2.setAntiAlias(true);
        paint2.setStyle(style);
        paint2.setTextSize(nk.l.p(KLineManager.f142490O.a().i(), 2, 9.0f));
        this.f19255o = paint2;
        Paint.FontMetrics fontMetrics = paint2.getFontMetrics();
        float fCeil = (float) Math.ceil(fontMetrics.bottom - fontMetrics.top);
        this.f19256p = (int) fCeil;
        this.f19257q = (-(fCeil / 2.0f)) - fontMetrics.top;
        this.f19258r = (int) nk.l.o(1, 1.0f);
        this.f19259s = (int) nk.l.o(1, 2.0f);
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        String strF;
        AbstractC2759w0 abstractC2759w0L;
        AbstractC2755v abstractC2755vG;
        C2741q c2741qB = i().b();
        C2702d c2702dE = c2741qB.e(b());
        if (c2702dE == null || (strF = f()) == null || (abstractC2759w0L = c2741qB.l(strF)) == null) {
            return;
        }
        if (abstractC2759w0L.z() == 0.0d) {
            abstractC2759w0L = null;
        }
        if (abstractC2759w0L == null || (abstractC2755vG = c2741qB.g(strF.concat(".m"))) == null) {
            return;
        }
        double dI = abstractC2755vG.i();
        float fU = c2702dE.u() + this.f19258r;
        float fY = c2702dE.y() - this.f19259s;
        float fS = abstractC2759w0L.S(dI);
        int i10 = this.f19256p;
        int i11 = i10 >> 1;
        float f10 = i10 >> 2;
        float f11 = fU + f10;
        String str = this.f19252l.format(dI);
        int i12 = b.f19265a[this.f19253m.ordinal()];
        if (i12 != 1) {
            if (i12 != 2) {
                throw new Qf.n();
            }
            int color = this.f19255o.getColor();
            this.f19255o.setColor(this.f19260t);
            canvas.drawLine(fU, fS, f11, fS - f10, this.f19255o);
            canvas.drawLine(fU, fS, fU + i11, fS, this.f19255o);
            canvas.drawLine(fU, fS, f11, f10 + fS, this.f19255o);
            this.f19255o.setTextAlign(Paint.Align.LEFT);
            canvas.drawText(str, (this.f19256p * 0.6f) + fU, fS + this.f19257q, this.f19255o);
            this.f19255o.setColor(color);
            return;
        }
        float f12 = i11;
        float f13 = fS - f12;
        float f14 = f12 + fS;
        this.f19255o.setStyle(Paint.Style.STROKE);
        Path path = new Path();
        path.moveTo(fU, fS);
        path.lineTo(f11, f13);
        path.lineTo(fY, f13);
        path.lineTo(fY, f14);
        path.lineTo(f11, f14);
        path.close();
        canvas.drawPath(path, this.f19254n);
        canvas.drawPath(path, this.f19255o);
        this.f19255o.setStyle(Paint.Style.FILL);
        this.f19255o.setTextAlign(Paint.Align.CENTER);
        canvas.drawText(str, c2702dE.q(), fS + this.f19257q, this.f19255o);
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        if (aVar == null) {
            return;
        }
        this.f19254n.setColor(aVar.c(2));
        this.f19255o.setColor(aVar.u(2));
        this.f19260t = aVar.b(1);
    }

    public final void v(DecimalFormat decimalFormat) {
        this.f19252l = decimalFormat;
    }
}
