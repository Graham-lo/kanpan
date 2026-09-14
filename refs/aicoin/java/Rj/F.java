package Rj;

import android.graphics.Canvas;
import android.graphics.Paint;

/* JADX INFO: loaded from: classes7.dex */
public final class F extends AbstractC2705e {

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public final Paint f19103s;

    public /* synthetic */ class a {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public static final /* synthetic */ int[] f19104a;

        static {
            int[] iArr = new int[C2702d.b.values().length];
            try {
                iArr[C2702d.b.Left.ordinal()] = 1;
            } catch (NoSuchFieldError unused) {
            }
            try {
                iArr[C2702d.b.Right.ordinal()] = 2;
            } catch (NoSuchFieldError unused2) {
            }
            try {
                iArr[C2702d.b.Top.ordinal()] = 3;
            } catch (NoSuchFieldError unused3) {
            }
            try {
                iArr[C2702d.b.Bottom.ordinal()] = 4;
            } catch (NoSuchFieldError unused4) {
            }
            try {
                iArr[C2702d.b.Fill.ordinal()] = 5;
            } catch (NoSuchFieldError unused5) {
            }
            f19104a = iArr;
        }
    }

    public F(String str) {
        super(str);
        Paint paint = new Paint();
        paint.setStyle(Paint.Style.STROKE);
        this.f19103s = paint;
    }

    @Override // Rj.C2702d
    public void B(int i10, int i11, int i12, int i13, boolean z10) {
        int i14;
        int i15;
        super.B(i10, i11, i12, i13, z10);
        int i16 = i10;
        int i17 = i11;
        int i18 = i12;
        int i19 = i13;
        for (C2702d c2702d : K()) {
            int iW = c2702d.w();
            int iV = c2702d.v();
            C2702d.b bVarS = c2702d.s();
            int i20 = bVarS == null ? -1 : a.f19104a[bVarS.ordinal()];
            if (i20 != -1) {
                if (i20 != 1) {
                    if (i20 == 2) {
                        int i21 = i18;
                        i14 = i19;
                        i18 = i21 - iW;
                        i15 = i17;
                        c2702d.B(i18, i15, i21, i14, true);
                    } else if (i20 == 3) {
                        i14 = i19;
                        i15 = i17 + iV;
                        c2702d.B(i16, i17, i18, i15, true);
                    } else if (i20 == 4) {
                        int i22 = i17;
                        int i23 = i19 - iV;
                        c2702d.B(i16, i23, i18, i19, true);
                        i19 = i23;
                        i17 = i22;
                    } else {
                        if (i20 != 5) {
                            throw new Qf.n();
                        }
                        c2702d.B(i16, i17, i18, i19, true);
                        i16 = i18;
                        i17 = i19;
                    }
                    i17 = i15;
                    i19 = i14;
                } else {
                    int i24 = i18;
                    int i25 = i16 + iW;
                    c2702d.B(i16, i17, i25, i19, true);
                    i16 = i25;
                    i18 = i24;
                }
            }
        }
    }

    @Override // Rj.C2702d
    public void C(C2741q c2741q, int i10, int i11) {
        int iW;
        H(i10, i11);
        for (C2702d c2702d : K()) {
            c2702d.C(c2741q, i10, i11);
            C2702d.b bVarS = c2702d.s();
            int i12 = bVarS == null ? -1 : a.f19104a[bVarS.ordinal()];
            if (i12 != -1) {
                if (i12 == 1 || i12 == 2) {
                    iW = c2702d.w();
                    i11 -= iW;
                } else if (i12 == 3 || i12 == 4) {
                    iW = c2702d.v();
                    i11 -= iW;
                } else {
                    if (i12 != 5) {
                        throw new Qf.n();
                    }
                    i11 = 0;
                    i10 = 0;
                }
            }
        }
    }

    @Override // Rj.AbstractC2705e
    public void J(Canvas canvas) {
        float fU = u();
        float fY = y();
        for (C2702d c2702d : K()) {
            if (c2702d.s() == C2702d.b.Bottom) {
                float fZ = c2702d.z();
                canvas.drawLine(fU, fZ, fY, fZ, this.f19103s);
            }
        }
    }

    @Override // Rj.AbstractC2705e
    public void L(mk.a aVar) {
        if (aVar == null) {
            return;
        }
        this.f19103s.setColor(aVar.g(4));
    }
}
