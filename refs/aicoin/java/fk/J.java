package fk;

import Rj.AbstractC2744r0;
import Rj.AbstractC2755v;
import Rj.AbstractC2759w0;
import Rj.C2702d;
import Rj.C2732n;
import Rj.C2741q;
import android.content.Context;
import android.content.res.Resources;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.DashPathEffect;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.Rect;
import android.graphics.RectF;
import gk.C7488s0;
import java.util.Iterator;
import sp.aicoin_kline.R;
import sp.aicoin_kline.chart.data.LiQuiLineItem;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class J extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public C7488s0 f95078l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public C2702d f95079m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public AbstractC2759w0 f95080n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final Paint f95081o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final Paint f95082p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final Paint f95083q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final float f95084r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public final float f95085s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public final float f95086t;

    public J(C2732n c2732n, String str) {
        super(c2732n, str);
        Paint paint = new Paint();
        paint.setStyle(Paint.Style.STROKE);
        paint.setAntiAlias(true);
        paint.setStrokeWidth(2.0f);
        paint.setColor(Color.parseColor("#E99F27"));
        paint.setPathEffect(new DashPathEffect(new float[]{10.0f, 5.0f}, 0.0f));
        this.f95081o = paint;
        Paint paint2 = new Paint();
        Paint.Style style = Paint.Style.FILL;
        paint2.setStyle(style);
        paint2.setAntiAlias(true);
        paint2.setColor(Color.parseColor("#E99F27"));
        this.f95082p = paint2;
        Paint paint3 = new Paint();
        paint3.setStyle(style);
        paint3.setAntiAlias(true);
        paint3.setColor(-1);
        paint3.setTextAlign(Paint.Align.CENTER);
        paint3.setTextSize(24.0f);
        this.f95083q = paint3;
        this.f95084r = 8.0f;
        this.f95085s = 4.0f;
        this.f95086t = 32.0f;
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        AbstractC2759w0 abstractC2759w0;
        C2702d c2702d;
        C7488s0 c7488s0;
        Resources resources;
        Canvas canvas2;
        KLineManager.a aVar = KLineManager.f142490O;
        if (!aVar.a().a0() || (abstractC2759w0 = this.f95080n) == null || (c2702d = this.f95079m) == null || (c7488s0 = this.f95078l) == null || abstractC2759w0.z() == 0.0d || c7488s0.s().isEmpty()) {
            return;
        }
        Context contextW = aVar.a().w();
        if (contextW == null || (resources = contextW.getResources()) == null) {
            resources = aVar.a().i().getResources();
        }
        String string = resources.getString(R.string.kline_liqui_line_title);
        int iU = c2702d.u();
        int iY = c2702d.y();
        Iterator it = c7488s0.s().iterator();
        while (it.hasNext()) {
            try {
                Double dN = Ah.v.n(((LiQuiLineItem) it.next()).getPrice());
                if (dN != null) {
                    float fS = abstractC2759w0.S(dN.doubleValue());
                    if (fS >= c2702d.z() && fS <= c2702d.p()) {
                        canvas2 = canvas;
                        try {
                            v(canvas2, iU, iY, fS, string);
                        } catch (Exception unused) {
                        }
                        canvas = canvas2;
                    }
                }
            } catch (Exception unused2) {
                canvas2 = canvas;
            }
        }
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        AbstractC2755v abstractC2755vQ = q();
        C7488s0 c7488s0 = abstractC2755vQ instanceof C7488s0 ? (C7488s0) abstractC2755vQ : null;
        if (c7488s0 == null) {
            return;
        }
        this.f95078l = c7488s0;
        C2741q c2741qB = i().b();
        this.f95079m = c2741qB.e(b());
        c2741qB.m(c());
        this.f95080n = c2741qB.l(b());
    }

    public final void v(Canvas canvas, float f10, float f11, float f12, String str) {
        Rect rect = new Rect();
        this.f95083q.getTextBounds(str, 0, str.length(), rect);
        int iWidth = rect.width();
        int iHeight = rect.height();
        float f13 = 2;
        float f14 = this.f95084r * f13;
        float f15 = iWidth + f14;
        float f16 = f14 + iHeight;
        float f17 = f11 - this.f95086t;
        float f18 = f17 - f15;
        float f19 = f16 / f13;
        float f20 = f12 - f19;
        Path path = new Path();
        path.moveTo(f10, f12);
        path.lineTo(f11, f12);
        canvas.drawPath(path, this.f95081o);
        RectF rectF = new RectF(f18, f20, f17, f16 + f20);
        float f21 = this.f95085s;
        canvas.drawRoundRect(rectF, f21, f21, this.f95082p);
        canvas.drawText(str, (f15 / f13) + f18, ((f20 + f19) + (iHeight / 2)) - this.f95083q.getFontMetrics().descent, this.f95083q);
    }
}
