package Rj;

import android.graphics.Canvas;
import android.graphics.Paint;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import kotlin.jvm.internal.DefaultConstructorMarker;

/* JADX INFO: loaded from: /private/tmp/claude-501/-Users-mdd-kanpan/e5a5bf1c-f427-4144-8ae2-a961a321a4b4/scratchpad/aic/dec/classes7.dex */
public final class L0 extends AbstractC0145e {
    public static final a u = null;
    public final Paint s;
    public boolean t;

    public static final class a {
        public a(DefaultConstructorMarker r1) {
        }
    }

    static {
        u = new a(null);
    }

    public L0(String r2) {
        super(r2);
        Paint r3 = new Paint();
        this.s = r3;
        r3.setStyle(Paint.Style.STROKE);
    }

    @Override // Rj.C0142d
    public void B(int r10, int r11, int r12, int r13, boolean r14) {
        super.B(r10, r11, r12, r13, r14);
        if (K().size() < 1) goto L16;
        int r15 = 0;
        int r1 = ((C0142d) K().get(0)).w() + r10;
        int r16 = K().size();
        int r2 = r11;
    L6:
        if (r15 >= r16) goto L24;
        C0142d r0 = (C0142d) K().get(r15);
        int r4 = r0.v() + r2;
        int r3 = r1;
        r0.B(r10, r2, r3, r4, true);
        r1 = r3;
        int r17 = r15 + 1;
        if (r17 >= K().size()) goto L10;
        r0 = (C0142d) K().get(r17);
    L10:
        r0.B(r1, r2, y(), r4, true);
        int r18 = r15 + 2;
        if (r18 >= K().size()) goto L15;
        C0142d r5 = (C0142d) K().get(r18);
        if (r5.o() != C0142d.a.c) goto L15;
        int r7 = r4 + 40;
        r5.B(u(), r4, y(), r7, true);
        r15 = r15 + 3;
        r2 = r7;
    L15:
        r15 = r18;
        r2 = r4;
        goto L6
    L24:
        return;
    }

    @Override // Rj.C0142d
    public void C(C0181q r20, int r21, int r22) {
        int r3 = r22;
        H(r21, r3);
        List r4 = K();
        ArrayList r5 = new ArrayList();
        Iterator r6 = r4.iterator();
    L4:
        if (r6.hasNext() == false) goto L10;
        Object r7 = r6.next();
        C0142d r8 = (C0142d) r7;
        if (r8.o() == C0142d.a.a) goto L9;
        if (r8.o() != C0142d.a.b) goto L4;
    L9:
        r5.add(r7);
        goto L4
    L10:
        int r9 = (r5.size() + 1) >> 1;
        int r10 = r9 - 1;
        int r11 = (int) (((double) r3) / ((double) (r9 + 2)));
        int[] r12 = new int[r9];
    L11:
        if (r10 <= 0) goto L13;
        r12[r10] = r11;
        r3 = r3 - r11;
        r10 = r10 - 1;
        goto L11
    L13:
        r12[0] = r3;
        int r13 = Xj.a.b(8);
        int r14 = r13 * 7;
        int r15 = r21 / 3;
        y1 r16 = r20.m(c());
        if (r16 != null) goto L16;
    L47:
        int[] r17 = r12;
        int r18 = 1;
        int r23 = 0;
    L48:
        int r19 = r18;
    L50:
        if (r19 >= r5.size()) goto L55;
        C0142d r1 = (C0142d) r5.get(r19);
        int r2 = r17[r19 >> 1];
        if (r1.r() == false) goto L54;
        r2 = r2 - 40;
    L54:
        r1.C(r20, r14, r2);
        r19 = r19 + 2;
        goto L50
    L55:
        int r24 = r21 - r14;
        int r25 = r23;
    L57:
        if (r25 >= r5.size()) goto L87;
        C0142d r26 = (C0142d) r5.get(r25);
        int r27 = r17[r25 >> 1];
        if (r26.r() == false) goto L61;
        r27 = r27 - 40;
    L61:
        r26.C(r20, r24, r27);
        r25 = r25 + 2;
        goto L57
    L87:
        return;
    L16:
        if (r16.r() < 0) goto L47;
        int r28 = Math.max(((r15 - r14) / r13) + 1, 0);
        int[] r110 = new int[r28];
        int r111 = r28 - 1;
    L18:
        if (r111 < 0) goto L20;
        r110[r111] = r16.r();
        r111 = r111 - 1;
        goto L18
    L20:
        int r112 = r16.y();
        String[] r113 = {".m", ".a"};
        double[][] r114 = new double[r28][];
        int r115 = 0;
    L22:
        if (r115 >= r28) goto L24;
        r114[r115] = new double[2];
        r115 = r115 + 1;
        goto L22
    L24:
        r18 = 1;
        r23 = 0;
        int r29 = 0;
        int r116 = 0;
    L26:
        if (r116 >= r5.size()) goto L46;
        if (r29 >= r28) goto L46;
        C0142d r30 = (C0142d) r5.get(r116);
        B0 r31 = (B0) r20.a(r30.d() + "Range.m");
        int r32 = 0;
    L30:
        if (r32 >= 2) goto L44;
        String r117 = r113[r32];
        int r118 = r32;
        StringBuilder r33 = new StringBuilder();
        int r119 = r13;
        r33.append(r30.d());
        r33.append(r117);
        AbstractC0195v r34 = r20.g(r33.toString());
        if (r34 != null) goto L34;
        r32 = r118 + 1;
        r13 = r119;
        goto L30
    L34:
        r34.g(r110, r112, r114, null);
        if (r31 == null) goto L62;
    L37:
        if (r29 >= r28) goto L42;
        int[] r35 = r12;
        int r36 = r29;
        int[] r120 = r35;
        if (Math.max(r31.v(r114[r29][0]), r31.v(r114[r29][1])) <= r14) goto L43;
        r29 = r36 + 1;
        r14 = r14 + r119;
        r12 = r120;
    L43:
        r29 = r36;
    L45:
        r116 = r116 + 2;
        r12 = r120;
        r13 = r119;
        goto L26
    L42:
        r120 = r12;
        r36 = r29;
        goto L43
    L62:
        return;
    L44:
        r119 = r13;
        r120 = r12;
    L46:
        r17 = r12;
        goto L48
    }

    @Override // Rj.AbstractC0145e
    public void J(Canvas r15) {
        if (K().size() >= 1) goto L6;
        return;
    L6:
        if (this.t == false) goto L8;
        r15.drawLine(u(), z(), y(), z(), this.s);
        Canvas r8 = r15;
    L9:
        Iterator r16 = K().iterator();
        int r0 = 0;
    L11:
        if (r16.hasNext() == false) goto L28;
        Object r2 = r16.next();
        int r3 = r0 + 1;
        if (r0 >= 0) goto L15;
        Sf.r.x();
    L15:
        C0142d r4 = (C0142d) r2;
        if (r4.o() != C0142d.a.a) goto L18;
        r8.drawLine(r4.y(), r4.z(), r4.y(), r4.p(), this.s);
    L18:
        float r5 = r4.p();
        if (r0 != Sf.r.p(K())) goto L21;
    L24:
        r5 = r5 - 1;
    L23:
        float r10 = r5;
        r8.drawLine(r4.u(), r10, r4.y(), r10, this.s);
        r0 = r3;
        goto L11
    L21:
        if (r0 != (Sf.r.p(K()) - 1)) goto L23;
    L28:
        return;
    L8:
        r8 = r15;
        goto L9
    }

    @Override // Rj.AbstractC0145e
    public void L(mk.a r3) {
        this.s.setColor(r3.g(2));
        if (r3.d(".price_info.bg") != 0) goto L5;
        boolean r4 = true;
    L6:
        this.t = r4;
        return;
    L5:
        r4 = false;
        goto L6
    }

    public final int M(int r1, int r2) {
        return ((r1 / (r2 + 3)) * 3) - 40;
    }

    public final int N(int r3, int r4, boolean r5) {
        int r0 = r3 / 4;
        if (r4 >= 0) goto L6;
    L8:
        return r3;
    L6:
        if (r4 >= 2) goto L10;
        if (r5 == false) goto L8;
    L10:
        return (r4 + 3) * r0;
    }

    public final void O(boolean r1) {
    }
}
