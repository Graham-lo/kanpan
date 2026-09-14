package nk;

import android.graphics.RectF;
import kotlin.jvm.internal.DefaultConstructorMarker;

/* JADX INFO: loaded from: classes7.dex */
public final class q {

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public static final a f134234e = new a(null);

    /* JADX INFO: renamed from: f, reason: collision with root package name */
    public static final C10211a f134235f = new C10211a();

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final RectF f134236a = new RectF();

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final RectF f134237b = new RectF();

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public Object f134238c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public int f134239d;

    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }

        public final q a() {
            q qVar = (q) q.f134235f.b();
            return qVar == null ? new q() : qVar;
        }

        public final void b() {
            q.f134235f.c();
        }
    }

    public final boolean b(float f10, float f11) {
        return this.f134236a.contains(f10, f11);
    }

    public final boolean c(float f10, float f11) {
        return this.f134237b.contains(f10, f11);
    }

    public final int d() {
        return this.f134239d;
    }

    public final Object e() {
        return this.f134238c;
    }

    public final void f() {
        this.f134236a.setEmpty();
        this.f134237b.setEmpty();
        this.f134238c = null;
        this.f134239d = 0;
        f134235f.a(this);
    }

    public final q g(float f10, float f11, float f12, float f13) {
        this.f134236a.set(f10, f11, f12, f13);
        return this;
    }

    public final void h(int i10) {
        this.f134239d = i10;
    }

    public final q i(float f10, float f11, float f12, float f13) {
        this.f134237b.set(f10, f11, f12, f13);
        return this;
    }

    public final void j(Object obj) {
        this.f134238c = obj;
    }
}
