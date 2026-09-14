package fk;

import android.view.MotionEvent;

/* JADX INFO: renamed from: fk.n, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7389n {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final C7389n f95436a = new C7389n();

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public static C7393s f95437b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public static boolean f95438c;

    public final boolean a(MotionEvent motionEvent) {
        C7393s c7393s = f95437b;
        if (c7393s == null) {
            return false;
        }
        int action = motionEvent.getAction() & 255;
        if (action == 0) {
            f95438c = false;
            return false;
        }
        if (action != 1) {
            if (action == 2) {
                if (c7393s.J()) {
                    c7393s.M(motionEvent.getY());
                    return true;
                }
                if (c7393s.H() == null || f95438c || !c7393s.K(motionEvent.getY())) {
                    return false;
                }
                f95438c = true;
                return true;
            }
            if (action != 3) {
                return false;
            }
        }
        if (f95438c) {
            c7393s.L();
            f95438c = false;
            return true;
        }
        if (c7393s.H() != null) {
            return c7393s.I();
        }
        return false;
    }

    public final void b(C7393s c7393s) {
        f95437b = c7393s;
    }
}
