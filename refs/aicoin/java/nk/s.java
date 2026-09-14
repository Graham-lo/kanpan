package nk;

/* JADX INFO: loaded from: classes7.dex */
public final class s {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final s f134244a = new s();

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public static final f f134245b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public static final f f134246c;

    static {
        f fVar = new f();
        fVar.e(10);
        f134245b = fVar;
        f134246c = new f();
    }

    public final String a(double d10, int i10) {
        return Math.abs(d10) < 1.0d ? f134246c.c(d10, i10) : f134245b.c(d10, i10);
    }
}
