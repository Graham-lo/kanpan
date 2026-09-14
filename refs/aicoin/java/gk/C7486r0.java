package gk;

import kotlin.jvm.internal.DefaultConstructorMarker;

/* JADX INFO: renamed from: gk.r0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7486r0 {

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public static final a f96556c = new a(null);

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public static final C7486r0 f96557d = new C7486r0(0, 0);

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final long f96558a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final long f96559b;

    /* JADX INFO: renamed from: gk.r0$a */
    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }

        public final C7486r0 a() {
            return C7486r0.f96557d;
        }
    }

    public C7486r0(long j10, long j11) {
        this.f96558a = j10;
        this.f96559b = j11;
    }

    public final long b() {
        return this.f96559b;
    }

    public final long c() {
        return this.f96558a;
    }

    public final boolean d() {
        return this.f96559b > 0;
    }

    public boolean equals(Object obj) {
        if (this == obj) {
            return true;
        }
        if (!(obj instanceof C7486r0)) {
            return false;
        }
        C7486r0 c7486r0 = (C7486r0) obj;
        return this.f96558a == c7486r0.f96558a && this.f96559b == c7486r0.f96559b;
    }

    public int hashCode() {
        return Long.hashCode(this.f96559b) + (Long.hashCode(this.f96558a) * 31);
    }

    public String toString() {
        return "LargeOrderTimelineSpec(startTimeMs=" + this.f96558a + ", intervalMs=" + this.f96559b + ')';
    }
}
