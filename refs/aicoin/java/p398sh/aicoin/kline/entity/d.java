package p398sh.aicoin.kline.entity;

/* JADX INFO: loaded from: classes7.dex */
public class d {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public int f140596a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public int f140597b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public int f140598c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public int f140599d;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public boolean f140600e;

    public d(int i10, int i11, int i12) {
        e(i10);
        h(i11);
        f(i12);
        this.f140598c = i11;
    }

    public int a() {
        return this.f140596a;
    }

    public int b() {
        return this.f140599d;
    }

    public int c() {
        return this.f140600e ? this.f140598c : this.f140597b;
    }

    public boolean d() {
        return this.f140600e;
    }

    public void e(int i10) {
        this.f140596a = i10;
    }

    public void f(int i10) {
        this.f140599d = i10;
    }

    public void g(boolean z10) {
        this.f140600e = z10;
    }

    public void h(int i10) {
        this.f140597b = i10;
    }
}
