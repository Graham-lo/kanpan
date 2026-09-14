package Rj;

import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import sp.aicoin_kline.R;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class E0 extends AbstractC2744r0 {

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public final float f19080A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public final float f19081B;

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public final float f19082C;

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final KLineManager f19083l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final SimpleDateFormat f19084m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final Paint f19085n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final Paint f19086o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final Paint f19087p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final Paint f19088q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final Path f19089r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public final RectF f19090s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public final RectF f19091t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public final RectF f19092u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public final float f19093v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public final float f19094w;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public final float f19095x;

    /* JADX INFO: renamed from: y, reason: collision with root package name */
    public final float f19096y;

    /* JADX INFO: renamed from: z, reason: collision with root package name */
    public final float f19097z;

    public E0(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f19083l = KLineManager.f142490O.a();
        this.f19084m = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault());
        Paint paintA = kk.c.a(true);
        Paint.Style style = Paint.Style.FILL;
        paintA.setStyle(style);
        paintA.setColor(Color.parseColor("#111111"));
        this.f19085n = paintA;
        Paint paint = new Paint();
        paint.setAntiAlias(true);
        paint.setStyle(style);
        paint.setColor(Color.parseColor("#111111"));
        this.f19086o = paint;
        Paint paint2 = new Paint();
        paint2.setAntiAlias(true);
        paint2.setStyle(style);
        paint2.setColor(-1);
        paint2.setTextSize(Xj.a.c(10.0f));
        paint2.setTextAlign(Paint.Align.LEFT);
        this.f19087p = paint2;
        Paint paintA2 = kk.c.a(true);
        paintA2.setStyle(Paint.Style.STROKE);
        paintA2.setStrokeWidth(Xj.a.a(1.5f));
        paintA2.setStrokeCap(Paint.Cap.ROUND);
        paintA2.setColor(-1);
        this.f19088q = paintA2;
        this.f19089r = new Path();
        this.f19090s = new RectF();
        this.f19091t = new RectF();
        this.f19092u = new RectF();
        this.f19093v = Xj.a.a(5.0f);
        this.f19094w = Xj.a.a(5.0f);
        this.f19095x = Xj.a.a(8.0f);
        this.f19096y = Xj.a.a(4.0f);
        this.f19097z = Xj.a.a(3.0f);
        this.f19080A = Xj.a.a(6.0f);
        this.f19081B = Xj.a.a(6.0f);
        this.f19082C = Xj.a.a(4.0f);
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        C2741q c2741qB;
        C2702d c2702dE;
        y1 y1VarM;
        AbstractC2759w0 abstractC2759w0L;
        this.f19091t.setEmpty();
        this.f19092u.setEmpty();
        long J10 = this.f19083l.J();
        double dI = this.f19083l.I();
        if (J10 == 0 || (c2702dE = (c2741qB = i().b()).e(b())) == null || (y1VarM = c2741qB.m(c())) == null || (abstractC2759w0L = c2741qB.l(b())) == null) {
            return;
        }
        float fU = y1VarM.A() >= 0 ? y1VarM.u() * (y1VarM.A() + 0.5f) : y1VarM.j(J10);
        if (fU < 0.0f) {
            return;
        }
        float fW = (fU - y1VarM.w()) + c2702dE.u();
        if (fW < c2702dE.u() || fW > c2702dE.y()) {
            return;
        }
        float fP = abstractC2759w0L.P(dI);
        if (fP < c2702dE.z() || fP > c2702dE.p()) {
            return;
        }
        String str = this.f19084m.format(new Date(J10));
        float fMeasureText = this.f19087p.measureText(str);
        Paint.FontMetrics fontMetrics = this.f19087p.getFontMetrics();
        float f10 = fontMetrics.descent - fontMetrics.ascent;
        String string = i().c().getResources().getString(R.string.kline_scroll_target_last_available_kline);
        float fMeasureText2 = this.f19087p.measureText(string);
        float fA = Xj.a.a(2.0f);
        float f11 = 2;
        float f12 = (this.f19095x * f11) + fMeasureText + this.f19081B + this.f19080A;
        C2765z c2765zH = c2741qB.h(c());
        boolean z10 = y1VarM.A() < 0 ? !(c2765zH == null || c2765zH.C().isEmpty() || ((Sj.b) Sf.z.o0(c2765zH.C())).e() != J10) : y1VarM.A() == 0;
        float fU2 = fW - (f12 / 2.0f);
        float fA2 = Xj.a.a(4.0f);
        boolean z11 = fU2 < ((float) c2702dE.u()) + fA2;
        if (z11) {
            fU2 = c2702dE.u() + fA2;
        }
        if (z10 && fMeasureText2 > fMeasureText) {
            f12 = (this.f19095x * f11) + fMeasureText2 + this.f19081B + this.f19080A;
        }
        float f13 = (this.f19096y * f11) + f10 + (z10 ? f10 + fA : 0.0f);
        float f14 = f12 + fU2;
        float f15 = z11 ? fP : this.f19094w + fP;
        if (!z11) {
            this.f19089r.reset();
            this.f19089r.moveTo(fW, fP);
            this.f19089r.lineTo(fW - this.f19093v, this.f19094w + fP);
            this.f19089r.lineTo(fW + this.f19093v, fP + this.f19094w);
            this.f19089r.close();
            canvas.drawPath(this.f19089r, this.f19086o);
        }
        this.f19090s.set(fU2, f15, f14, f15 + f13);
        RectF rectF = this.f19090s;
        float f16 = this.f19097z;
        canvas.drawRoundRect(rectF, f16, f16, this.f19085n);
        float f17 = fU2 + this.f19095x;
        if (z10) {
            float f18 = f10 / 2.0f;
            canvas.drawText(string, f17, ((this.f19096y + f15) + f18) - ((fontMetrics.ascent + fontMetrics.descent) / 2.0f), this.f19087p);
            canvas.drawText(str, f17, ((((this.f19096y + f15) + f10) + fA) + f18) - ((fontMetrics.ascent + fontMetrics.descent) / 2.0f), this.f19087p);
        } else {
            canvas.drawText(str, f17, ((f13 / 2.0f) + f15) - ((fontMetrics.ascent + fontMetrics.descent) / 2.0f), this.f19087p);
        }
        float f19 = f14 - this.f19095x;
        float f20 = this.f19080A;
        float f21 = f15;
        float f22 = f19 - f20;
        float f23 = f21 + ((f13 - f20) / 2.0f);
        float f24 = f20 + f23;
        this.f19091t.set(f22, f23, f19, f24);
        this.f19092u.set(this.f19091t);
        RectF rectF2 = this.f19092u;
        float f25 = -this.f19082C;
        rectF2.inset(f25, f25);
        canvas.drawLine(f22, f23, f19, f24, this.f19088q);
        canvas.drawLine(f22, f24, f19, f23, this.f19088q);
    }

    @Override // Rj.AbstractC2744r0
    public boolean n(String str, int i10, int i11) {
        if (this.f19092u.isEmpty() || !this.f19092u.contains(i10, i11)) {
            return false;
        }
        this.f19083l.W0(0L);
        this.f19083l.V0(0.0d);
        i().e().invalidate();
        this.f19091t.setEmpty();
        this.f19092u.setEmpty();
        return true;
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        if (aVar == null) {
            return;
        }
        if (aVar.w()) {
            this.f19087p.setColor(-16777216);
            this.f19086o.setColor(Color.parseColor("#FFFFFF"));
            this.f19085n.setColor(Color.parseColor("#FFFFFF"));
            this.f19088q.setColor(-16777216);
            return;
        }
        this.f19087p.setColor(-1);
        this.f19086o.setColor(Color.parseColor("#111111"));
        this.f19085n.setColor(Color.parseColor("#111111"));
        this.f19088q.setColor(-1);
    }
}
