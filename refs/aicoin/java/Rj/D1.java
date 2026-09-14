package Rj;

import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.Locale;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class D1 extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final SimpleDateFormat f19072l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final SimpleDateFormat f19073m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final float f19074n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final float f19075o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final Paint f19076p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final Paint f19077q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final Paint f19078r;

    public D1(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f19072l = new SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault());
        this.f19073m = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault());
        Paint paint = new Paint();
        this.f19076p = paint;
        paint.setAntiAlias(true);
        paint.setTextAlign(Paint.Align.CENTER);
        paint.setTextSize(nk.l.o(2, 9.0f));
        Paint.FontMetrics fontMetrics = paint.getFontMetrics();
        this.f19074n = (-(((float) Math.ceil(fontMetrics.bottom - fontMetrics.top)) / 2)) - fontMetrics.top;
        this.f19075o = nk.l.o(1, 16.0f) + paint.measureText("0000-00-00 00:00");
        Paint paint2 = new Paint();
        paint2.setStyle(Paint.Style.STROKE);
        this.f19077q = paint2;
        Paint paint3 = new Paint();
        paint3.setStyle(Paint.Style.FILL);
        this.f19078r = paint3;
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        G gI;
        C2702d c2702dE;
        ArrayList arrayListS;
        C2741q c2741qB = i().b();
        y1 y1VarM = c2741qB.m(c());
        if (y1VarM == null || (gI = c2741qB.i(c())) == null || (c2702dE = c2741qB.e(b())) == null) {
            return;
        }
        AbstractC2755v abstractC2755vG = c2741qB.g(c() + ".main.m");
        AbstractC2720j abstractC2720j = abstractC2755vG instanceof AbstractC2720j ? (AbstractC2720j) abstractC2755vG : null;
        if (abstractC2720j == null || (arrayListS = abstractC2720j.s()) == null) {
            return;
        }
        if (!nk.n.f(13)) {
            int iD = y1VarM.D();
            if (iD < 0 || iD >= arrayListS.size() || !y1VarM.E()) {
                return;
            }
            v((nk.n.f134230a.b() < 60 ? this.f19073m : this.f19072l).format(new Date(((Sj.b) arrayListS.get(iD)).e())), canvas, y1.C(y1VarM, 0, 1, null), c2702dE);
            return;
        }
        int iT = gI.t();
        float fB = y1VarM.B(iT);
        Sj.b bVar = (Sj.b) Sf.z.r0(arrayListS, iT);
        if (!gI.B() || bVar == null) {
            return;
        }
        v((nk.n.f134230a.b() < 60 ? this.f19073m : this.f19072l).format(new Date(bVar.e())), canvas, fB, c2702dE);
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        if (aVar == null) {
            return;
        }
        this.f19076p.setColor(aVar.u(6));
        this.f19077q.setColor(aVar.g(6));
        this.f19078r.setColor(aVar.c(3));
    }

    public final void v(String str, Canvas canvas, float f10, C2702d c2702d) {
        float f11;
        float f12;
        float f13 = this.f19075o / 2.0f;
        float f14 = f10 - f13;
        float f15 = f13 + f10;
        float fX = c2702d.x() + this.f19074n;
        if (f14 < 0.0f) {
            float f16 = this.f19075o;
            float f17 = -f16;
            float f18 = 2;
            float f19 = f17 / f18;
            if (f14 >= f19) {
                f10 = f16 / f18;
                f11 = f16;
                f12 = 0.0f;
            } else {
                f12 = f17;
                f11 = 0.0f;
                f10 = f19;
            }
        } else {
            f11 = f15;
            f12 = f14;
        }
        boolean zF = nk.n.f(13);
        Paint paint = new Paint(this.f19078r);
        Paint paint2 = new Paint(this.f19076p);
        if (zF) {
            KLineManager.a aVar = KLineManager.f142490O;
            paint.setColor(((Number) p162hb.e.c(aVar.a().f0() == 1, Integer.valueOf(Color.parseColor("#7A8799")), Integer.valueOf(Color.parseColor("#4A5462")))).intValue());
            paint2.setColor(((Number) p162hb.e.c(aVar.a().f0() == 1, Integer.valueOf(Color.parseColor("#FFFFFF")), Integer.valueOf(Color.parseColor("#C3C7D9")))).intValue());
        }
        canvas.drawRect(f12, c2702d.z(), f11, c2702d.p(), paint);
        canvas.drawText(str, f10, fX, paint2);
    }
}
