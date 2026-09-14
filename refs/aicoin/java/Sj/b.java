package Sj;

import java.util.Arrays;
import java.util.Locale;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.T;

/* JADX INFO: loaded from: classes7.dex */
public final class b {

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public static final a f20759g = new a(null);

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final long f20760a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public double f20761b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public double f20762c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public double f20763d;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public double f20764e;

    /* JADX INFO: renamed from: f, reason: collision with root package name */
    public final double f20765f;

    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }

        public final b a() {
            return new b(0L, Double.NaN, Double.NaN, Double.NaN, Double.NaN, Double.NaN);
        }
    }

    public b(long j10, double d10, double d11, double d12, double d13, double d14) {
        this.f20760a = j10;
        this.f20761b = d10;
        this.f20762c = d11;
        this.f20763d = d12;
        this.f20764e = d13;
        this.f20765f = d14;
    }

    public b(b bVar) {
        this.f20760a = bVar.f20760a;
        this.f20761b = bVar.f20761b;
        this.f20762c = bVar.f20762c;
        this.f20763d = bVar.f20763d;
        this.f20764e = bVar.f20764e;
        this.f20765f = bVar.f20765f;
    }

    public final double a() {
        return this.f20764e;
    }

    public final double b() {
        return this.f20762c;
    }

    public final double c() {
        return this.f20763d;
    }

    public final double d() {
        return this.f20761b;
    }

    public final long e() {
        return this.f20760a;
    }

    public final double f() {
        return this.f20765f;
    }

    public final boolean g() {
        return Double.isNaN(this.f20761b) && Double.isNaN(this.f20764e) && Double.isNaN(this.f20762c) && Double.isNaN(this.f20763d);
    }

    public final void h(double d10) {
        this.f20764e = d10;
    }

    public final void i(double d10) {
        this.f20762c = d10;
    }

    public final void j(double d10) {
        this.f20763d = d10;
    }

    public String toString() {
        T t10 = T.f97914a;
        return String.format(Locale.getDefault(), "{date:%d, open:%f, high:%f, low:%f, close:%f, volume:%f}", Arrays.copyOf(new Object[]{Long.valueOf(this.f20760a), Double.valueOf(this.f20761b), Double.valueOf(this.f20762c), Double.valueOf(this.f20763d), Double.valueOf(this.f20764e), Double.valueOf(this.f20765f)}, 6));
    }
}
