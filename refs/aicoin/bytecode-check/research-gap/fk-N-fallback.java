package fk;

/* JADX INFO: loaded from: /private/tmp/claude-501/-Users-mdd-kanpan/e5a5bf1c-f427-4144-8ae2-a961a321a4b4/scratchpad/aic/dec/classes7.dex */
public final class N extends Rj.AbstractC0184r0 {
    public final android.graphics.Paint l;
    public final android.graphics.Paint m;
    public final android.graphics.Paint n;
    public final android.graphics.Paint o;
    public Rj.y1 p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public Rj.AbstractC0199w0 f53q;
    public Rj.AbstractC0195v r;
    public final boolean s;
    public final boolean t;
    public final boolean u;

    public N(Rj.C0172n r3, java.lang.String r4) {
            r2 = this;
            r2.<init>(r3, r4)
            android.graphics.Paint r3 = new android.graphics.Paint
            r3.<init>()
            r2.l = r3
            android.graphics.Paint r4 = new android.graphics.Paint
            r4.<init>()
            r2.m = r4
            r0 = 1
            r2.s = r0
            r2.t = r0
            r2.u = r0
            android.graphics.Paint$Style r1 = android.graphics.Paint.Style.FILL
            r3.setStyle(r1)
            r4.setStyle(r1)
            r1 = 1073741824(0x40000000, float:2.0)
            r3.setStrokeWidth(r1)
            r4.setStrokeWidth(r1)
            android.graphics.Paint r3 = new android.graphics.Paint
            r3.<init>()
            r2.n = r3
            android.graphics.Paint$Style r4 = android.graphics.Paint.Style.STROKE
            r3.setStyle(r4)
            r3.setAntiAlias(r0)
            r3.setStrokeWidth(r1)
            android.graphics.Paint r3 = new android.graphics.Paint
            r3.<init>()
            r2.o = r3
            r3.setStyle(r4)
            r3.setAntiAlias(r0)
            r3.setStrokeWidth(r1)
            return
    }

    @Override // Rj.AbstractC0184r0
    public void g(android.graphics.Canvas r27) {
            r26 = this;
            r0 = r26
            Rj.y1 r1 = r0.p
            if (r1 != 0) goto L8
            goto L113
        L8:
            Rj.w0 r2 = r0.f53q
            if (r2 != 0) goto Le
            goto L113
        Le:
            Rj.v r3 = r0.r
            if (r3 != 0) goto L14
            goto L113
        L14:
            double r4 = r2.z()
            r6 = 0
            int r4 = (r4 > r6 ? 1 : (r4 == r6 ? 0 : -1))
            if (r4 != 0) goto L20
            goto L113
        L20:
            gk.t0 r3 = (gk.C0323t0) r3
            double[][] r3 = r3.v()
            int r4 = r3.length
            if (r4 != 0) goto L2b
            goto L113
        L2b:
            float r4 = r1.u()
            int r5 = r1.r()
            int r8 = r1.q()
            float r1 = r1.J()
            r9 = 10
            float r9 = (float) r9
            float r9 = r4 / r9
            float r9 = r9 - r1
            float r14 = r2.S(r6)
            r10 = 2
            float r11 = (float) r10
            float r11 = r4 / r11
            float r11 = r11 - r1
            r1 = 0
            r1 = r3[r1]
            r12 = 1
            r12 = r3[r12]
            r3 = r3[r10]
            r16 = -1082130432(0xffffffffbf800000, float:-1.0)
            r10 = r5
            r18 = r16
            r19 = r18
            r23 = r19
        L5b:
            r20 = r11
            if (r10 >= r8) goto L113
            int r11 = r3.length
            if (r10 >= r11) goto La5
            r21 = r3[r10]
            boolean r11 = java.lang.Double.isNaN(r21)
            if (r11 != 0) goto La5
            r24 = r6
            r6 = r3[r10]
            int r11 = (r6 > r24 ? 1 : (r6 == r24 ? 0 : -1))
            if (r11 < 0) goto L8d
            r11 = r12
            float r12 = r2.S(r6)
            android.graphics.Paint r15 = r0.l
            boolean r6 = r0.u
            if (r6 == 0) goto L8a
            r13 = r20
            r7 = r10
            r6 = r11
            r11 = r20
            r10 = r27
            r10.drawLine(r11, r12, r13, r14, r15)
        L88:
            r11 = r9
            goto Laa
        L8a:
            r7 = r10
            r6 = r11
            goto L88
        L8d:
            r11 = r12
            float r6 = r2.S(r6)
            android.graphics.Paint r15 = r0.m
            boolean r7 = r0.u
            if (r7 == 0) goto L8a
            r13 = r9
            r7 = r10
            r12 = r14
            r10 = r27
            r14 = r6
            r6 = r11
            r11 = r9
            r10.drawLine(r11, r12, r13, r14, r15)
            r14 = r12
            goto Laa
        La5:
            r24 = r6
            r11 = r9
            r7 = r10
            r6 = r12
        Laa:
            int r9 = r1.length
            if (r7 >= r9) goto Ld2
            r9 = r1[r7]
            boolean r9 = java.lang.Double.isNaN(r9)
            if (r9 != 0) goto Ld2
            r9 = r1[r7]
            float r21 = r2.S(r9)
            if (r7 <= r5) goto Lcf
            boolean r9 = r0.s
            if (r9 == 0) goto Lcf
            int r9 = (r19 > r16 ? 1 : (r19 == r16 ? 0 : -1))
            if (r9 != 0) goto Lc6
            goto Lcf
        Lc6:
            android.graphics.Paint r9 = r0.n
            r17 = r27
            r22 = r9
            r17.drawLine(r18, r19, r20, r21, r22)
        Lcf:
            r9 = r21
            goto Ld4
        Ld2:
            r9 = r19
        Ld4:
            int r10 = r6.length
            if (r7 >= r10) goto Lfe
            r12 = r6[r7]
            boolean r10 = java.lang.Double.isNaN(r12)
            if (r10 != 0) goto Lfe
            r12 = r6[r7]
            float r21 = r2.S(r12)
            if (r7 <= r5) goto Lfb
            boolean r10 = r0.t
            if (r10 == 0) goto Lfb
            int r10 = (r23 > r16 ? 1 : (r23 == r16 ? 0 : -1))
            if (r10 != 0) goto Lf0
            goto Lfb
        Lf0:
            android.graphics.Paint r10 = r0.o
            r17 = r27
            r22 = r10
            r19 = r23
            r17.drawLine(r18, r19, r20, r21, r22)
        Lfb:
            r23 = r21
            goto L102
        Lfe:
            r19 = r23
            r23 = r19
        L102:
            float r10 = r11 + r4
            float r11 = r20 + r4
            int r7 = r7 + 1
            r12 = r6
            r19 = r9
            r9 = r10
            r18 = r20
            r10 = r7
            r6 = r24
            goto L5b
        L113:
            return
    }

    @Override // Rj.AbstractC0184r0
    public void t() {
            r0 = this;
            return
    }

    @Override // Rj.AbstractC0184r0
    public void u(mk.a r4) {
            r3 = this;
            if (r4 != 0) goto L3
            goto L23
        L3:
            android.graphics.Paint r0 = r3.l
            int r1 = r4.r()
            r0.setColor(r1)
            android.graphics.Paint r0 = r3.m
            int r4 = r4.m()
            r0.setColor(r4)
            Rj.v r4 = r3.q()
            boolean r0 = r4 instanceof gk.AbstractC0300h0
            if (r0 == 0) goto L20
            gk.h0 r4 = (gk.AbstractC0300h0) r4
            goto L21
        L20:
            r4 = 0
        L21:
            if (r4 != 0) goto L24
        L23:
            return
        L24:
            sp.aicoin_kline.core.indicator.config.F r4 = r4.x()
            android.graphics.Paint r0 = r3.n
            ek.m[] r1 = r4.k()
            r2 = 0
            r1 = r1[r2]
            int r1 = r1.a()
            r0.setColor(r1)
            android.graphics.Paint r0 = r3.o
            ek.m[] r4 = r4.k()
            r4 = r4[r2]
            int r4 = r4.a()
            r0.setColor(r4)
            Rj.n r4 = r3.i()
            Rj.q r4 = r4.b()
            java.lang.String r0 = r3.b()
            r4.e(r0)
            java.lang.String r0 = r3.c()
            Rj.y1 r0 = r4.m(r0)
            r3.p = r0
            java.lang.String r0 = r3.b()
            Rj.w0 r0 = r4.l(r0)
            r3.f53q = r0
            java.lang.String r0 = r3.d()
            Rj.v r4 = r4.g(r0)
            r3.r = r4
            return
    }
}
