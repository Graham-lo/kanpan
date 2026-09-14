package Rj;

import java.util.ArrayList;
import java.util.List;

/* JADX INFO: renamed from: Rj.w1, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C2760w1 {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final C2760w1 f19594a = new C2760w1();

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public static final ArrayList f19595b = new ArrayList();

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public static final ArrayList f19596c = new ArrayList();

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public static final ArrayList f19597d = new ArrayList();

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public static final ArrayList f19598e = new ArrayList();

    /* JADX INFO: renamed from: f, reason: collision with root package name */
    public static boolean f19599f = true;

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public static float f19600g = 1.0f;

    public final void a() {
        f19598e.clear();
    }

    public final void b(List list) {
        ArrayList arrayList = f19596c;
        arrayList.clear();
        arrayList.addAll(list);
    }

    public final void c(List list) {
        ArrayList arrayList = f19595b;
        arrayList.clear();
        arrayList.addAll(list);
    }

    public final void d(List list) {
        ArrayList arrayList = f19597d;
        arrayList.clear();
        arrayList.addAll(list);
    }

    public final List e() {
        return f19596c;
    }

    public final List f() {
        return f19595b;
    }

    public final List g() {
        return f19598e;
    }

    public final List h() {
        return f19597d;
    }

    public final float i() {
        return f19600g;
    }

    public final boolean j() {
        return f19599f;
    }

    public final void k(boolean z10) {
        f19599f = z10;
    }

    public final void l(float f10) {
        f19600g = f10;
    }
}
