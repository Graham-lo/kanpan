package Pj;

/* JADX INFO: loaded from: classes7.dex */
public abstract class e {

    public static class a {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public double f17173a = 0.0d;
    }

    public static void a(double[] dArr, double[] dArr2, a aVar, a aVar2) {
        int length = dArr.length;
        double d10 = 0.0d;
        double d11 = 0.0d;
        double d12 = 0.0d;
        double d13 = 0.0d;
        double d14 = 0.0d;
        double d15 = 0.0d;
        for (int i10 = 0; i10 < length; i10++) {
            double d16 = dArr[i10];
            d12 += d16;
            d13 += d16 * d16;
            double d17 = dArr2[i10];
            d11 += d17;
            d14 += d16 * d17;
            double d18 = length;
            double d19 = d13 * d18;
            double d20 = d12 * d12;
            d10 = ((d11 * d13) - (d14 * d12)) / (d19 - d20);
            d15 = ((d11 * d12) - (d18 * d14)) / (d20 - d19);
        }
        aVar.f17173a = d10;
        aVar2.f17173a = d15;
    }
}
