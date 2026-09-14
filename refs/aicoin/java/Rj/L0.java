package Rj;

import android.graphics.Canvas;
import android.graphics.Paint;
import java.util.ArrayList;
import java.util.List;
import kotlin.jvm.internal.DefaultConstructorMarker;

/* JADX INFO: loaded from: classes7.dex */
public final class L0 extends AbstractC2705e {

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public static final a f19189u = new a(null);

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public final Paint f19190s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public boolean f19191t;

    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public L0(String str) {
        super(str);
        Paint paint = new Paint();
        this.f19190s = paint;
        paint.setStyle(Paint.Style.STROKE);
    }

    @Override // Rj.C2702d
    public void B(int i10, int i11, int i12, int i13, boolean z10) {
        super.B(i10, i11, i12, i13, z10);
        if (K().size() < 1) {
            return;
        }
        int i14 = 0;
        int iW = ((C2702d) K().get(0)).w() + i10;
        int size = K().size();
        int i15 = i11;
        while (i14 < size) {
            C2702d c2702d = (C2702d) K().get(i14);
            int iV = c2702d.v() + i15;
            int i16 = iW;
            c2702d.B(i10, i15, i16, iV, true);
            iW = i16;
            int i17 = i14 + 1;
            if (i17 < K().size()) {
                c2702d = (C2702d) K().get(i17);
            }
            c2702d.B(iW, i15, y(), iV, true);
            int i18 = i14 + 2;
            if (i18 < K().size()) {
                C2702d c2702d2 = (C2702d) K().get(i18);
                if (c2702d2.o() == C2702d.a.Timeline) {
                    int i19 = iV + 40;
                    c2702d2.B(u(), iV, y(), i19, true);
                    i14 += 3;
                    i15 = i19;
                }
            }
            i14 = i18;
            i15 = iV;
        }
    }

    @Override // Rj.C2702d
    public void C(C2741q c2741q, int i10, int i11) {
        int[] iArr;
        int i12;
        int i13;
        int i14;
        int[] iArr2;
        int i15;
        int i16 = i11;
        H(i10, i16);
        List listK = K();
        ArrayList arrayList = new ArrayList();
        for (Object obj : listK) {
            C2702d c2702d = (C2702d) obj;
            if (c2702d.o() == C2702d.a.Data || c2702d.o() == C2702d.a.Range) {
                arrayList.add(obj);
            }
        }
        int size = (arrayList.size() + 1) >> 1;
        int i17 = (int) (((double) i16) / ((double) (size + 2)));
        int[] iArr3 = new int[size];
        for (int i18 = size - 1; i18 > 0; i18--) {
            iArr3[i18] = i17;
            i16 -= i17;
        }
        iArr3[0] = i16;
        int iB = Xj.a.b(8);
        int i19 = iB * 7;
        int i20 = i10 / 3;
        y1 y1VarM = c2741q.m(c());
        if (y1VarM == null || y1VarM.r() < 0) {
            iArr = iArr3;
            i12 = 1;
            i13 = 0;
        } else {
            int iMax = Math.max(((i20 - i19) / iB) + 1, 0);
            int[] iArr4 = new int[iMax];
            for (int i21 = iMax - 1; i21 >= 0; i21--) {
                iArr4[i21] = y1VarM.r();
            }
            int iY = y1VarM.y();
            String[] strArr = {".m", ".a"};
            double[][] dArr = new double[iMax][];
            for (int i22 = 0; i22 < iMax; i22++) {
                dArr[i22] = new double[2];
            }
            i12 = 1;
            i13 = 0;
            int i23 = 0;
            int i24 = 0;
            while (i24 < arrayList.size() && i23 < iMax) {
                C2702d c2702d2 = (C2702d) arrayList.get(i24);
                B0 b10 = (B0) c2741q.a(c2702d2.d() + "Range.m");
                int i25 = 0;
                while (true) {
                    if (i25 >= 2) {
                        i14 = iB;
                        iArr2 = iArr3;
                        break;
                    }
                    String str = strArr[i25];
                    int i26 = i25;
                    StringBuilder sb2 = new StringBuilder();
                    i14 = iB;
                    sb2.append(c2702d2.d());
                    sb2.append(str);
                    AbstractC2755v abstractC2755vG = c2741q.g(sb2.toString());
                    if (abstractC2755vG != null) {
                        abstractC2755vG.g(iArr4, iY, dArr, null);
                        if (b10 != null) {
                            while (true) {
                                if (i23 >= iMax) {
                                    iArr2 = iArr3;
                                    i15 = i23;
                                    break;
                                }
                                int[] iArr5 = iArr3;
                                i15 = i23;
                                iArr2 = iArr5;
                                if (Math.max(b10.v(dArr[i23][0]), b10.v(dArr[i23][1])) <= i19) {
                                    break;
                                }
                                i23 = i15 + 1;
                                i19 += i14;
                                iArr3 = iArr2;
                            }
                            i23 = i15;
                            break;
                        }
                        return;
                    }
                    i25 = i26 + 1;
                    iB = i14;
                }
                i24 += 2;
                iArr3 = iArr2;
                iB = i14;
            }
            iArr = iArr3;
        }
        for (int i27 = i12; i27 < arrayList.size(); i27 += 2) {
            C2702d c2702d3 = (C2702d) arrayList.get(i27);
            int i28 = iArr[i27 >> 1];
            if (c2702d3.r()) {
                i28 -= 40;
            }
            c2702d3.C(c2741q, i19, i28);
        }
        int i29 = i10 - i19;
        for (int i30 = i13; i30 < arrayList.size(); i30 += 2) {
            C2702d c2702d4 = (C2702d) arrayList.get(i30);
            int i31 = iArr[i30 >> 1];
            if (c2702d4.r()) {
                i31 -= 40;
            }
            c2702d4.C(c2741q, i29, i31);
        }
    }

    @Override // Rj.AbstractC2705e
    public void J(Canvas canvas) {
        Canvas canvas2;
        if (K().size() < 1) {
            return;
        }
        if (this.f19191t) {
            canvas.drawLine(u(), z(), y(), z(), this.f19190s);
            canvas2 = canvas;
        } else {
            canvas2 = canvas;
        }
        int i10 = 0;
        for (Object obj : K()) {
            int i11 = i10 + 1;
            if (i10 < 0) {
                Sf.r.x();
            }
            C2702d c2702d = (C2702d) obj;
            if (c2702d.o() == C2702d.a.Data) {
                canvas2.drawLine(c2702d.y(), c2702d.z(), c2702d.y(), c2702d.p(), this.f19190s);
            }
            float fP = c2702d.p();
            if (i10 == Sf.r.p(K()) || i10 == Sf.r.p(K()) - 1) {
                fP--;
            }
            float f10 = fP;
            canvas2.drawLine(c2702d.u(), f10, c2702d.y(), f10, this.f19190s);
            i10 = i11;
        }
    }

    @Override // Rj.AbstractC2705e
    public void L(mk.a aVar) {
        this.f19190s.setColor(aVar.g(2));
        this.f19191t = aVar.d(".price_info.bg") == 0;
    }

    public final int M(int i10, int i11) {
        return ((i10 / (i11 + 3)) * 3) - 40;
    }

    public final int N(int i10, int i11, boolean z10) {
        return (i11 >= 0 && (i11 >= 2 || z10)) ? (i11 + 3) * (i10 / 4) : i10;
    }

    public final void O(boolean z10) {
    }
}
