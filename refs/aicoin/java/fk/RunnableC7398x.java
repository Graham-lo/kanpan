package fk;

/* JADX INFO: renamed from: fk.x, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final /* synthetic */ class RunnableC7398x implements Runnable {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final /* synthetic */ String f95581a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final /* synthetic */ long f95582b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final /* synthetic */ C7399y f95583c;

    public /* synthetic */ RunnableC7398x(String str, long j10, C7399y c7399y) {
        this.f95581a = str;
        this.f95582b = j10;
        this.f95583c = c7399y;
    }

    @Override // java.lang.Runnable
    public final void run() {
        C7399y.x(this.f95581a, this.f95582b, this.f95583c);
    }
}
