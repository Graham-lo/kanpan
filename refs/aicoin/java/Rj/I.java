package Rj;

/* JADX INFO: loaded from: classes7.dex */
public final class I {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public boolean f19145a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public boolean f19146b;

    public final void a() {
        this.f19146b = true;
    }

    public final boolean b(boolean z10, boolean z11) {
        if (!z10) {
            this.f19145a = false;
            this.f19146b = false;
            return false;
        }
        if (this.f19145a) {
            if (this.f19146b) {
                return false;
            }
            return z11;
        }
        this.f19145a = true;
        this.f19146b = !z11;
        return z11;
    }
}
