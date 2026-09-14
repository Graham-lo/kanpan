package fk;

import Rj.AbstractC0184r0;
import Rj.AbstractC0195v;
import Rj.AbstractC0199w0;
import Rj.C0172n;
import Rj.C0181q;
import Rj.y1;
import android.graphics.Canvas;
import android.graphics.Paint;
import gk.AbstractC0300h0;
import gk.C0323t0;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: /private/tmp/claude-501/-Users-mdd-kanpan/e5a5bf1c-f427-4144-8ae2-a961a321a4b4/scratchpad/aic/dec/classes7.dex */
public final class M extends AbstractC0184r0 {
    public final Paint l;
    public final Paint m;
    public final Paint n;
    public final Paint o;
    public final Paint p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final Paint f52q;
    public y1 r;
    public AbstractC0199w0 s;
    public AbstractC0300h0 t;
    public final boolean u;
    public final boolean v;

    public M(C0172n r5, String r6) {
        super(r5, r6);
        this.u = true;
        this.v = true;
        Paint r7 = new Paint();
        this.l = r7;
        Paint.Style r0 = Paint.Style.STROKE;
        r7.setStyle(r0);
        Paint r1 = new Paint();
        this.m = r1;
        Paint.Style r2 = Paint.Style.FILL;
        r1.setStyle(r2);
        Paint r3 = new Paint();
        this.n = r3;
        r3.setStyle(r0);
        Paint r4 = new Paint();
        this.o = r4;
        r4.setStyle(r2);
        Paint r8 = new Paint();
        this.p = r8;
        r8.setStyle(r0);
        r8.setAntiAlias(true);
        r8.setStrokeWidth(2.0f);
        Paint r9 = new Paint();
        this.f52q = r9;
        r9.setStyle(r0);
        r9.setAntiAlias(true);
        r9.setStrokeWidth(2.0f);
        if (KLineManager.O.a().f0() != 1) goto L6;
        r3.setStrokeWidth(2.0f);
        r7.setStrokeWidth(2.0f);
        return;
    }

    @Override // Rj.AbstractC0184r0
    public void g(Canvas r31) {
        y1 r1 = this.r;
        if (r1 == null) goto L76;
        AbstractC0199w0 r2 = this.s;
        if (r2 == null) goto L80;
        AbstractC0300h0 r3 = this.t;
        if (r3 == null) goto L81;
        double r6 = 0.0d;
        if (r2.z() == 0.0d) goto L82;
        double[][] r4 = ((C0323t0) r3).v();
        if (r4.length == 0) goto L83;
        float r5 = r1.u();
        float r8 = 2;
        float r9 = (r5 * r8) / 3;
        int r10 = r1.r();
        int r11 = r1.q();
        float r7 = r1.J();
        float r12 = (r5 / 6) - r7;
        float r15 = r2.S(0.0d);
        float r13 = (r5 / r8) - r7;
        double[] r14 = r4[0];
        int r16 = 1;
        double[] r17 = r4[1];
        double[] r18 = r4[2];
        float r19 = r13;
        float r110 = r9 + r12;
        int r20 = r10;
        float r21 = r12;
        float r22 = -1.0f;
        float r111 = -1.0f;
        float r26 = -1.0f;
    L18:
        if (r20 >= r11) goto L84;
        if (r20 < r18.length) goto L22;
    L46:
        double r28 = r6;
        float r23 = r110;
    L28:
        float r112 = r21;
    L48:
        if (r20 < r14.length) goto L50;
    L60:
        float r113 = r22;
        r111 = r111;
    L62:
        if (r20 < r17.length) goto L64;
    L74:
        r26 = r26;
    L75:
        r21 = r112 + r5;
        r110 = r23 + r5;
        r20 = r20 + 1;
        r17 = r17;
        r22 = r19;
        r6 = r28;
        r16 = 1;
        r19 = r19 + r5;
        goto L18
    L64:
        if (Double.isNaN(r17[r20]) == true) goto L74;
        float r24 = r2.S(r17[r20]);
        if (r20 > r10) goto L68;
    L73:
        r26 = r24;
        goto L75
    L68:
        if (this.v == false) goto L73;
        if (r26 == (-1.0f)) goto L73;
        r31.drawLine(r113, r26, r19, r24, this.f52q);
        goto L73
    L50:
        if (Double.isNaN(r14[r20]) == true) goto L60;
        float r25 = r2.S(r14[r20]);
        if (r20 > r10) goto L54;
    L57:
        r113 = r22;
    L59:
        r111 = r25;
        goto L62
    L54:
        if (this.u == false) goto L57;
        if (r111 == (-1.0f)) goto L57;
        r113 = r22;
        r31.drawLine(r113, r111, r19, r25, this.p);
        goto L59
    L22:
        if (Double.isNaN(r18[r20]) == true) goto L46;
        r28 = r6;
        double r27 = r18[r20];
        if (r27 < r28) goto L36;
        float r29 = r2.S(r27);
        if (Math.abs(r15 - r29) >= 2.0f) goto L29;
        float r210 = r15 - r16;
        r23 = r110;
        r31.drawLine(r21, r210, r23, r210, this.l);
        goto L28
    L29:
        if (r20 != 0) goto L31;
    L32:
        double[] r30 = r17;
        r112 = r21;
        float r32 = r16;
        nk.y.a(r31, r112, r29, r110 - r32, r15 - r32, this.l);
        r17 = r30;
    L35:
        r23 = r110;
        goto L48
    L31:
        if (r18[r20] >= r18[r20 - 1]) goto L32;
        double[] r33 = r17;
        float r114 = r15;
        r112 = r21;
        nk.y.a(r31, r112, r29, r110, r114, this.m);
        r17 = r33;
        r23 = r110;
        r15 = r114;
        goto L48
    L36:
        int r34 = r16;
        double[] r115 = r17;
        r112 = r21;
        float r35 = r2.S(r27);
        if (Math.abs(r35 - r15) >= 2.0f) goto L39;
        r17 = r115;
        r31.drawLine(r112, r15, r110, r15, this.n);
        goto L35
    L39:
        r17 = r115;
        if (r20 != 0) goto L42;
    L43:
        r23 = r110;
        float r36 = r34;
        nk.y.a(r31, r112, r15, r23 - r36, r35 - r36, this.n);
        goto L48
    L42:
        if (r18[r20] >= r18[r20 - 1]) goto L43;
        nk.y.a(r31, r112, r15, r110, r35, this.o);
        goto L35
    L84:
        return;
    L83:
        return;
    L82:
        return;
    L81:
        return;
    L80:
        return;
    }

    @Override // Rj.AbstractC0184r0
    public void u(mk.a r4) {
        if (r4 == null) goto L17;
        this.l.setColor(r4.r());
        this.m.setColor(r4.r());
        this.n.setColor(r4.m());
        this.o.setColor(r4.m());
        C0181q r5 = i().b();
        r5.e(b());
        this.r = r5.m(c());
        this.s = r5.l(b());
        AbstractC0195v r6 = r5.g(d());
        AbstractC0300h0 r1 = null;
        if ((r6 instanceof AbstractC0300h0) == false) goto L7;
        AbstractC0300h0 r7 = (AbstractC0300h0) r6;
    L8:
        if (r7 == null) goto L16;
        this.t = r7;
        AbstractC0195v r8 = q();
        if ((r8 instanceof AbstractC0300h0) == false) goto L12;
        r1 = (AbstractC0300h0) r8;
    L12:
        if (r1 == null) goto L18;
        sp.aicoin_kline.core.indicator.config.F r9 = r1.x();
        this.p.setColor(r9.k()[0].a());
        this.p.setStrokeWidth(r9.k()[0].b());
        this.f52q.setColor(r9.k()[1].a());
        this.f52q.setStrokeWidth(r9.k()[1].b());
        return;
    L18:
        return;
    L16:
        return;
    L7:
        r7 = null;
        goto L8
    }

    @Override // Rj.AbstractC0184r0
    public void t() {
    }
}
