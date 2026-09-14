package p398sh.aicoin.kline.winrate;

import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
public final class i {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public String f140724a = "";

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public boolean f140725b = true;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public long f140726c;

    public final long a(String str, boolean z10) {
        if (str == null || !AbstractC7609s.f(this.f140724a, str) || this.f140725b || z10) {
            return 0L;
        }
        return this.f140726c;
    }

    public final void b(String str, boolean z10, long j10) {
        this.f140726c = j10;
        this.f140725b = z10;
        this.f140724a = str;
    }
}
