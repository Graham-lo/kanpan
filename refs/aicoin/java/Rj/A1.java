package Rj;

import java.text.SimpleDateFormat;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
public final class A1 {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public float f19030a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public long f19031b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public SimpleDateFormat f19032c;

    public A1(float f10, long j10, SimpleDateFormat simpleDateFormat) {
        this.f19030a = f10;
        this.f19031b = j10;
        this.f19032c = simpleDateFormat;
    }

    public final SimpleDateFormat a() {
        return this.f19032c;
    }

    public final long b() {
        return this.f19031b;
    }

    public final float c() {
        return this.f19030a;
    }

    public boolean equals(Object obj) {
        if (this == obj) {
            return true;
        }
        if (!(obj instanceof A1)) {
            return false;
        }
        A1 a10 = (A1) obj;
        return Float.compare(this.f19030a, a10.f19030a) == 0 && this.f19031b == a10.f19031b && AbstractC7609s.f(this.f19032c, a10.f19032c);
    }

    public int hashCode() {
        return this.f19032c.hashCode() + ((Long.hashCode(this.f19031b) + (Float.hashCode(this.f19030a) * 31)) * 31);
    }

    public String toString() {
        return "TimelineItem(x=" + this.f19030a + ", time=" + this.f19031b + ", format=" + this.f19032c + ')';
    }
}
