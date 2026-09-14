package Rj;

import android.graphics.Canvas;
import kotlin.jvm.internal.DefaultConstructorMarker;

/* JADX INFO: renamed from: Rj.r0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public abstract class AbstractC2744r0 extends AbstractC2721j0 {

    /* JADX INFO: renamed from: k, reason: collision with root package name */
    public static final a f19523k = new a(null);

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public final C2732n f19524g;

    /* JADX INFO: renamed from: h, reason: collision with root package name */
    public final ak.h f19525h;

    /* JADX INFO: renamed from: i, reason: collision with root package name */
    public boolean f19526i;

    /* JADX INFO: renamed from: j, reason: collision with root package name */
    public AbstractC2755v f19527j;

    /* JADX INFO: renamed from: Rj.r0$a */
    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public AbstractC2744r0(C2732n c2732n, String str) {
        super(str);
        this.f19524g = c2732n;
        this.f19525h = new ak.h(c2732n.b(), this, null, 4, null);
    }

    public abstract void g(Canvas canvas);

    public void h(Canvas canvas) {
    }

    public final C2732n i() {
        return this.f19524g;
    }

    public ak.h j() {
        return this.f19525h;
    }

    public final AbstractC2755v k() {
        return this.f19527j;
    }

    public final int l() {
        if (m() == 0) {
            return p();
        }
        return 0;
    }

    public int m() {
        return 0;
    }

    public boolean n(String str, int i10, int i11) {
        return false;
    }

    public final boolean o() {
        return this.f19526i;
    }

    public int p() {
        return -1;
    }

    public AbstractC2755v q() {
        AbstractC2755v abstractC2755v = this.f19527j;
        return abstractC2755v != null ? abstractC2755v : j().g();
    }

    public final void r(AbstractC2755v abstractC2755v) {
        this.f19527j = abstractC2755v;
    }

    public final void s(boolean z10) {
        this.f19526i = z10;
    }

    public abstract void t();

    public abstract void u(mk.a aVar);
}
