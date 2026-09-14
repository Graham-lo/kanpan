package Rj;

import java.math.BigDecimal;
import java.math.RoundingMode;
import kotlin.jvm.internal.DefaultConstructorMarker;

/* JADX INFO: renamed from: Rj.v, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public abstract class AbstractC2755v extends AbstractC2721j0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public static final a f19560l = new a(null);

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public static final String[] f19561m = {".m", ".a", ".msk", ".mrk", ".drawing", ".window"};

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public final C2732n f19562g;

    /* JADX INFO: renamed from: h, reason: collision with root package name */
    public double f19563h;

    /* JADX INFO: renamed from: i, reason: collision with root package name */
    public double f19564i;

    /* JADX INFO: renamed from: j, reason: collision with root package name */
    public int f19565j;

    /* JADX INFO: renamed from: k, reason: collision with root package name */
    public int f19566k;

    /* JADX INFO: renamed from: Rj.v$a */
    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public AbstractC2755v(C2732n c2732n, String str) {
        super(str);
        this.f19562g = c2732n;
    }

    public final void g(int[] iArr, int i10, double[][] dArr, int[][] iArr2) {
        double[] dArr2 = new double[2];
        int length = iArr.length;
        int i11 = -1;
        int i12 = -1;
        double d10 = -1.7976931348623157E308d;
        double d11 = Double.MAX_VALUE;
        int i13 = i10;
        for (int i14 = 0; i14 < length; i14++) {
            int i15 = iArr[i14];
            if (i13 < i15) {
                double[] dArr3 = dArr[i14];
                dArr3[0] = 0.0d;
                dArr3[1] = 0.0d;
            } else {
                while (i13 >= i15) {
                    l(i13, dArr2);
                    double d12 = dArr2[0];
                    if (d11 > d12) {
                        i11 = i13;
                        d11 = d12;
                    }
                    double d13 = dArr2[1];
                    if (d10 < d13) {
                        i12 = i13;
                        d10 = d13;
                    }
                    i13--;
                }
                double[] dArr4 = dArr[i14];
                dArr4[0] = d11;
                dArr4[1] = d10;
            }
            if (iArr2 != null) {
                int[] iArr3 = iArr2[i14];
                iArr3[0] = i11;
                iArr3[1] = i12;
            }
        }
    }

    public final C2732n h() {
        return this.f19562g;
    }

    public double i() {
        return 0.0d;
    }

    public final double j() {
        return this.f19564i;
    }

    public final int k() {
        return this.f19566k;
    }

    public abstract void l(int i10, double[] dArr);

    public final double m() {
        return this.f19563h;
    }

    public final int n() {
        return this.f19565j;
    }

    public boolean o() {
        return false;
    }

    public int p() {
        return -1;
    }

    public abstract void q(dk.s sVar);

    public final void r() {
        y1 y1VarM = this.f19562g.b().m(c());
        if (y1VarM == null) {
            return;
        }
        double[][] dArr = {new double[2]};
        int[][] iArr = {new int[2]};
        g(new int[]{y1VarM.r()}, y1VarM.y(), dArr, iArr);
        double dDoubleValue = dArr[0][0];
        int iP = p();
        if (iP >= 0) {
            dDoubleValue = new BigDecimal(String.valueOf(dDoubleValue)).setScale(iP, RoundingMode.CEILING).doubleValue();
        }
        this.f19563h = dDoubleValue;
        double dDoubleValue2 = dArr[0][1];
        int iP2 = p();
        if (iP2 >= 0) {
            dDoubleValue2 = new BigDecimal(String.valueOf(dDoubleValue2)).setScale(iP2, RoundingMode.CEILING).doubleValue();
        }
        this.f19564i = dDoubleValue2;
        int[] iArr2 = iArr[0];
        this.f19565j = iArr2[0];
        this.f19566k = iArr2[1];
    }
}
