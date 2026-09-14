package gk;

import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.chart.data.AISRLData;

/* JADX INFO: renamed from: gk.o, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7480o {

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public static final a f96538c = new a(null);

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final AISRLData f96539a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final double f96540b;

    /* JADX INFO: renamed from: gk.o$a */
    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public C7480o(AISRLData aISRLData, double d10) {
        this.f96539a = aISRLData;
        this.f96540b = d10;
    }

    public /* synthetic */ C7480o(AISRLData aISRLData, double d10, int i10, DefaultConstructorMarker defaultConstructorMarker) {
        this((i10 & 1) != 0 ? new AISRLData(null, null, null, 7, null) : aISRLData, (i10 & 2) != 0 ? 1.0d : d10);
    }

    public final AISRLData a() {
        return this.f96539a;
    }

    public final double b() {
        return this.f96540b;
    }

    public boolean equals(Object obj) {
        if (this == obj) {
            return true;
        }
        if (!(obj instanceof C7480o)) {
            return false;
        }
        C7480o c7480o = (C7480o) obj;
        return AbstractC7609s.f(this.f96539a, c7480o.f96539a) && Double.compare(this.f96540b, c7480o.f96540b) == 0;
    }

    public int hashCode() {
        return Double.hashCode(this.f96540b) + (this.f96539a.hashCode() * 31);
    }

    public String toString() {
        return "AISRLDrawSnapshot(data=" + this.f96539a + ", depthGroupInterval=" + this.f96540b + ')';
    }
}
