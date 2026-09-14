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

/* JADX INFO: loaded from: /private/tmp/claude-501/-Users-mdd-kanpan/e5a5bf1c-f427-4144-8ae2-a961a321a4b4/scratchpad/aic/dec/classes7.dex */
public final class N extends AbstractC0184r0 {
    public final Paint l;
    public final Paint m;
    public final Paint n;
    public final Paint o;
    public y1 p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public AbstractC0199w0 f53q;
    public AbstractC0195v r;
    public final boolean s;
    public final boolean t;
    public final boolean u;

    public N(C0172n r3, String r4) {
        super(r3, r4);
        Paint r5 = new Paint();
        this.l = r5;
        Paint r6 = new Paint();
        this.m = r6;
        this.s = true;
        this.t = true;
        this.u = true;
        Paint.Style r1 = Paint.Style.FILL;
        r5.setStyle(r1);
        r6.setStyle(r1);
        r5.setStrokeWidth(2.0f);
        r6.setStrokeWidth(2.0f);
        Paint r7 = new Paint();
        this.n = r7;
        Paint.Style r8 = Paint.Style.STROKE;
        r7.setStyle(r8);
        r7.setAntiAlias(true);
        r7.setStrokeWidth(2.0f);
        Paint r9 = new Paint();
        this.o = r9;
        r9.setStyle(r8);
        r9.setAntiAlias(true);
        r9.setStrokeWidth(2.0f);
    }

    @Override // Rj.AbstractC0184r0
    public void g(Canvas r27) {
        y1 r1 = this.p;
        if (r1 == null) goto L64;
        AbstractC0199w0 r2 = this.f53q;
        if (r2 == null) goto L68;
        AbstractC0195v r3 = this.r;
        if (r3 == null) goto L69;
        double r6 = 0.0d;
        if (r2.z() == 0.0d) goto L70;
        double[][] r4 = ((C0323t0) r3).v();
        if (r4.length == 0) goto L71;
        float r5 = r1.u();
        int r7 = r1.r();
        int r8 = r1.q();
        float r9 = r1.J();
        float r10 = (r5 / 10) - r9;
        float r14 = r2.S(0.0d);
        float r11 = (r5 / 2) - r9;
        double[] r12 = r4[0];
        double[] r13 = r4[1];
        double[] r15 = r4[2];
        int r16 = r7;
        float r18 = -1.0f;
        float r19 = -1.0f;
        float r23 = -1.0f;
    L18:
        float r20 = r11;
        if (r16 >= r8) goto L72;
        if (r16 < r15.length) goto L23;
    L34:
        double r24 = r6;
        float r17 = r10;
        r16 = r16;
        double[] r21 = r13;
    L36:
        if (r16 < r12.length) goto L38;
    L48:
        float r22 = r19;
    L50:
        if (r16 < r21.length) goto L52;
    L62:
        r23 = r23;
    L63:
        float r110 = r17 + r5;
        r11 = r20 + r5;
        r13 = r21;
        r19 = r22;
        r10 = r110;
        r18 = r20;
        r16 = r16 + 1;
        r6 = r24;
        goto L18
    L52:
        if (Double.isNaN(r21[r16]) == true) goto L62;
        float r25 = r2.S(r21[r16]);
        if (r16 > r7) goto L56;
    L61:
        r23 = r25;
        goto L63
    L56:
        if (this.t == false) goto L61;
        if (r23 == (-1.0f)) goto L61;
        r27.drawLine(r18, r23, r20, r25, this.o);
        goto L61
    L38:
        if (Double.isNaN(r12[r16]) == true) goto L48;
        float r26 = r2.S(r12[r16]);
        if (r16 > r7) goto L42;
    L47:
        r22 = r26;
        goto L50
    L42:
        if (this.s == false) goto L47;
        if (r19 == (-1.0f)) goto L47;
        r27.drawLine(r18, r19, r20, r26, this.n);
        goto L47
    L23:
        if (Double.isNaN(r15[r16]) == true) goto L34;
        r24 = r6;
        double r28 = r15[r16];
        if (r28 < r24) goto L31;
        double[] r111 = r13;
        float r112 = r2.S(r28);
        Paint r113 = this.l;
        if (this.u == false) goto L30;
        r21 = r111;
        r27.drawLine(r20, r112, r20, r14, r113);
    L29:
        r17 = r10;
    L30:
        r21 = r111;
        goto L29
    L31:
        r111 = r13;
        float r29 = r2.S(r28);
        Paint r114 = this.m;
        if (this.u == false) goto L30;
        r16 = r16;
        float r115 = r14;
        r21 = r111;
        r17 = r10;
        r27.drawLine(r17, r115, r10, r29, r114);
        r14 = r115;
        goto L36
    L72:
        return;
    L71:
        return;
    L70:
        return;
    L69:
        return;
    L68:
        return;
    }

    @Override // Rj.AbstractC0184r0
    public void u(mk.a r4) {
        if (r4 == null) goto L12;
        this.l.setColor(r4.r());
        this.m.setColor(r4.m());
        AbstractC0195v r5 = q();
        if ((r5 instanceof AbstractC0300h0) == false) goto L7;
        AbstractC0300h0 r6 = (AbstractC0300h0) r5;
    L8:
        if (r6 != null) goto L10;
        return;
    L10:
        sp.aicoin_kline.core.indicator.config.F r7 = r6.x();
        this.n.setColor(r7.k()[0].a());
        this.o.setColor(r7.k()[0].a());
        C0181q r8 = i().b();
        r8.e(b());
        this.p = r8.m(c());
        this.f53q = r8.l(b());
        this.r = r8.g(d());
        return;
    L7:
        r6 = null;
        goto L8
    }

    @Override // Rj.AbstractC0184r0
    public void t() {
    }
}
