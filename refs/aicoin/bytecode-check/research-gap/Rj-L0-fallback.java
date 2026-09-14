package Rj;

/* JADX INFO: loaded from: /private/tmp/claude-501/-Users-mdd-kanpan/e5a5bf1c-f427-4144-8ae2-a961a321a4b4/scratchpad/aic/dec/classes7.dex */
public final class L0 extends Rj.AbstractC0145e {
    public static final Rj.L0.a u = null;
    public final android.graphics.Paint s;
    public boolean t;

    public static final class a {
        public a(kotlin.jvm.internal.DefaultConstructorMarker r1) {
                r0 = this;
                r0.<init>()
                return
        }
    }

    static {
            Rj.L0$a r0 = new Rj.L0$a
            r1 = 0
            r0.<init>(r1)
            Rj.L0.u = r0
            return
    }

    public L0(java.lang.String r2) {
            r1 = this;
            r1.<init>(r2)
            android.graphics.Paint r2 = new android.graphics.Paint
            r2.<init>()
            r1.s = r2
            android.graphics.Paint$Style r0 = android.graphics.Paint.Style.STROKE
            r2.setStyle(r0)
            return
    }

    @Override // Rj.C0142d
    public void B(int r10, int r11, int r12, int r13, boolean r14) {
            r9 = this;
            super.B(r10, r11, r12, r13, r14)
            java.util.List r12 = r9.K()
            int r12 = r12.size()
            r13 = 1
            if (r12 >= r13) goto L10
            goto L98
        L10:
            java.util.List r12 = r9.K()
            r13 = 0
            java.lang.Object r12 = r12.get(r13)
            Rj.d r12 = (Rj.C0142d) r12
            int r12 = r12.w()
            int r1 = r12 + r10
            java.util.List r12 = r9.K()
            int r12 = r12.size()
            r2 = r11
        L2a:
            if (r13 >= r12) goto L98
            java.util.List r11 = r9.K()
            java.lang.Object r11 = r11.get(r13)
            r0 = r11
            Rj.d r0 = (Rj.C0142d) r0
            int r11 = r0.v()
            int r4 = r11 + r2
            r5 = 1
            r3 = r1
            r1 = r10
            r0.B(r1, r2, r3, r4, r5)
            r1 = r3
            int r11 = r13 + 1
            java.util.List r14 = r9.K()
            int r14 = r14.size()
            if (r11 >= r14) goto L5b
            java.util.List r14 = r9.K()
            java.lang.Object r11 = r14.get(r11)
            r0 = r11
            Rj.d r0 = (Rj.C0142d) r0
        L5b:
            int r3 = r9.y()
            r5 = 1
            r0.B(r1, r2, r3, r4, r5)
            int r11 = r13 + 2
            java.util.List r14 = r9.K()
            int r14 = r14.size()
            if (r11 >= r14) goto L95
            java.util.List r14 = r9.K()
            java.lang.Object r14 = r14.get(r11)
            r3 = r14
            Rj.d r3 = (Rj.C0142d) r3
            Rj.d$a r14 = r3.o()
            Rj.d$a r0 = Rj.C0142d.a.c
            if (r14 != r0) goto L95
            int r7 = r4 + 40
            r5 = r4
            int r4 = r9.u()
            int r6 = r9.y()
            r8 = 1
            r3.B(r4, r5, r6, r7, r8)
            int r13 = r13 + 3
            r2 = r7
            goto L2a
        L95:
            r13 = r11
            r2 = r4
            goto L2a
        L98:
            return
    }

    @Override // Rj.C0142d
    public void C(Rj.C0181q r20, int r21, int r22) {
            r19 = this;
            r0 = r20
            r1 = r21
            r2 = r19
            r3 = r22
            r2.H(r1, r3)
            java.util.List r4 = r2.K()
            java.util.ArrayList r5 = new java.util.ArrayList
            r5.<init>()
            java.util.Iterator r4 = r4.iterator()
        L18:
            boolean r6 = r4.hasNext()
            if (r6 == 0) goto L39
            java.lang.Object r6 = r4.next()
            r7 = r6
            Rj.d r7 = (Rj.C0142d) r7
            Rj.d$a r8 = r7.o()
            Rj.d$a r9 = Rj.C0142d.a.a
            if (r8 == r9) goto L35
            Rj.d$a r7 = r7.o()
            Rj.d$a r8 = Rj.C0142d.a.b
            if (r7 != r8) goto L18
        L35:
            r5.add(r6)
            goto L18
        L39:
            int r4 = r5.size()
            r6 = 1
            int r4 = r4 + r6
            int r4 = r4 >> r6
            double r7 = (double) r3
            int r9 = r4 + (-1)
            int r10 = r4 + 2
            double r10 = (double) r10
            double r7 = r7 / r10
            int r7 = (int) r7
            int[] r4 = new int[r4]
        L4a:
            if (r9 <= 0) goto L52
            r4[r9] = r7
            int r3 = r3 - r7
            int r9 = r9 + (-1)
            goto L4a
        L52:
            r7 = 0
            r4[r7] = r3
            r3 = 8
            int r3 = Xj.a.b(r3)
            int r8 = r3 * 7
            int r9 = r1 / 3
            java.lang.String r10 = r2.c()
            Rj.y1 r10 = r0.m(r10)
            if (r10 == 0) goto L136
            int r11 = r10.r()
            if (r11 < 0) goto L136
            int r9 = r9 - r8
            int r9 = r9 / r3
            int r9 = r9 + r6
            int r9 = java.lang.Math.max(r9, r7)
            int[] r11 = new int[r9]
            int r12 = r9 + (-1)
        L7a:
            if (r12 < 0) goto L85
            int r13 = r10.r()
            r11[r12] = r13
            int r12 = r12 + (-1)
            goto L7a
        L85:
            int r10 = r10.y()
            java.lang.String r12 = ".m"
            java.lang.String r13 = ".a"
            java.lang.String[] r12 = new java.lang.String[]{r12, r13}
            double[][] r13 = new double[r9][]
            r14 = r7
        L94:
            r15 = 2
            if (r14 >= r9) goto L9e
            double[] r15 = new double[r15]
            r13[r14] = r15
            int r14 = r14 + 1
            goto L94
        L9e:
            r16 = r6
            r22 = r7
            r6 = r22
            r14 = r6
        La5:
            int r7 = r5.size()
            if (r14 >= r7) goto L134
            if (r6 >= r9) goto L134
            java.lang.Object r7 = r5.get(r14)
            Rj.d r7 = (Rj.C0142d) r7
            java.lang.StringBuilder r15 = new java.lang.StringBuilder
            r15.<init>()
            java.lang.String r1 = r7.d()
            r15.append(r1)
            java.lang.String r1 = "Range.m"
            r15.append(r1)
            java.lang.String r1 = r15.toString()
            Rj.r0 r1 = r0.a(r1)
            Rj.B0 r1 = (Rj.B0) r1
            r2 = r22
        Ld0:
            r15 = 2
            if (r2 >= r15) goto L125
            r15 = r12[r2]
            r17 = r2
            java.lang.StringBuilder r2 = new java.lang.StringBuilder
            r2.<init>()
            r18 = r3
            java.lang.String r3 = r7.d()
            r2.append(r3)
            r2.append(r15)
            java.lang.String r2 = r2.toString()
            Rj.v r2 = r0.g(r2)
            if (r2 != 0) goto Lf7
            int r2 = r17 + 1
            r3 = r18
            goto Ld0
        Lf7:
            r3 = 0
            r2.g(r11, r10, r13, r3)
            if (r1 != 0) goto Lff
            goto L17d
        Lff:
            if (r6 >= r9) goto L121
            r2 = r13[r6]
            r7 = r4
            r3 = r2[r22]
            int r2 = r1.v(r3)
            r3 = r13[r6]
            r4 = r6
            r15 = r7
            r6 = r3[r16]
            int r3 = r1.v(r6)
            int r2 = java.lang.Math.max(r2, r3)
            if (r2 > r8) goto L11b
            goto L123
        L11b:
            int r6 = r4 + 1
            int r8 = r8 + r18
            r4 = r15
            goto Lff
        L121:
            r15 = r4
            r4 = r6
        L123:
            r6 = r4
            goto L128
        L125:
            r18 = r3
            r15 = r4
        L128:
            int r14 = r14 + 2
            r2 = r19
            r1 = r21
            r4 = r15
            r3 = r18
            r15 = 2
            goto La5
        L134:
            r15 = r4
            goto L13b
        L136:
            r15 = r4
            r16 = r6
            r22 = r7
        L13b:
            r6 = r16
        L13d:
            int r1 = r5.size()
            if (r6 >= r1) goto L15b
            java.lang.Object r1 = r5.get(r6)
            Rj.d r1 = (Rj.C0142d) r1
            int r2 = r6 >> 1
            r2 = r15[r2]
            boolean r3 = r1.r()
            if (r3 == 0) goto L155
            int r2 = r2 + (-40)
        L155:
            r1.C(r0, r8, r2)
            int r6 = r6 + 2
            goto L13d
        L15b:
            int r1 = r21 - r8
            r7 = r22
        L15f:
            int r2 = r5.size()
            if (r7 >= r2) goto L17d
            java.lang.Object r2 = r5.get(r7)
            Rj.d r2 = (Rj.C0142d) r2
            int r3 = r7 >> 1
            r3 = r15[r3]
            boolean r4 = r2.r()
            if (r4 == 0) goto L177
            int r3 = r3 + (-40)
        L177:
            r2.C(r0, r1, r3)
            int r7 = r7 + 2
            goto L15f
        L17d:
            return
    }

    @Override // Rj.AbstractC0145e
    public void J(android.graphics.Canvas r15) {
            r14 = this;
            java.util.List r0 = r14.K()
            int r0 = r0.size()
            r1 = 1
            if (r0 >= r1) goto Ld
            goto L9d
        Ld:
            boolean r0 = r14.t
            if (r0 == 0) goto L2d
            int r0 = r14.u()
            float r3 = (float) r0
            int r0 = r14.z()
            float r4 = (float) r0
            int r0 = r14.y()
            float r5 = (float) r0
            int r0 = r14.z()
            float r6 = (float) r0
            android.graphics.Paint r7 = r14.s
            r2 = r15
            r2.drawLine(r3, r4, r5, r6, r7)
            r8 = r2
            goto L2e
        L2d:
            r8 = r15
        L2e:
            java.util.List r15 = r14.K()
            java.util.Iterator r15 = r15.iterator()
            r0 = 0
        L37:
            boolean r2 = r15.hasNext()
            if (r2 == 0) goto L9d
            java.lang.Object r2 = r15.next()
            int r3 = r0 + 1
            if (r0 >= 0) goto L48
            Sf.r.x()
        L48:
            Rj.d r2 = (Rj.C0142d) r2
            Rj.d$a r4 = r2.o()
            Rj.d$a r5 = Rj.C0142d.a.a
            if (r4 != r5) goto L6b
            int r4 = r2.y()
            float r9 = (float) r4
            int r4 = r2.z()
            float r10 = (float) r4
            int r4 = r2.y()
            float r11 = (float) r4
            int r4 = r2.p()
            float r12 = (float) r4
            android.graphics.Paint r13 = r14.s
            r8.drawLine(r9, r10, r11, r12, r13)
        L6b:
            int r4 = r2.p()
            float r4 = (float) r4
            java.util.List r5 = r14.K()
            int r5 = Sf.r.p(r5)
            if (r0 == r5) goto L88
            java.util.List r5 = r14.K()
            int r5 = Sf.r.p(r5)
            int r5 = r5 - r1
            if (r0 != r5) goto L86
            goto L88
        L86:
            r10 = r4
            goto L8b
        L88:
            float r0 = (float) r1
            float r4 = r4 - r0
            goto L86
        L8b:
            int r0 = r2.u()
            float r9 = (float) r0
            int r0 = r2.y()
            float r11 = (float) r0
            android.graphics.Paint r13 = r14.s
            r12 = r10
            r8.drawLine(r9, r10, r11, r12, r13)
            r0 = r3
            goto L37
        L9d:
            return
    }

    @Override // Rj.AbstractC0145e
    public void L(mk.a r3) {
            r2 = this;
            android.graphics.Paint r0 = r2.s
            r1 = 2
            int r1 = r3.g(r1)
            r0.setColor(r1)
            java.lang.String r0 = ".price_info.bg"
            int r3 = r3.d(r0)
            if (r3 != 0) goto L14
            r3 = 1
            goto L15
        L14:
            r3 = 0
        L15:
            r2.t = r3
            return
    }

    public final int M(int r1, int r2) {
            r0 = this;
            int r2 = r2 + 3
            int r1 = r1 / r2
            int r1 = r1 * 3
            int r1 = r1 + (-40)
            return r1
    }

    public final int N(int r3, int r4, boolean r5) {
            r2 = this;
            int r0 = r3 / 4
            if (r4 >= 0) goto L5
            goto La
        L5:
            r1 = 2
            if (r4 >= r1) goto Lb
            if (r5 != 0) goto Lb
        La:
            return r3
        Lb:
            int r4 = r4 + 3
            int r4 = r4 * r0
            return r4
    }

    public final void O(boolean r1) {
            r0 = this;
            return
    }
}
