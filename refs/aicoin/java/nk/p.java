package nk;

import android.util.Log;

/* JADX INFO: loaded from: classes7.dex */
public final class p {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final p f134232a = new p();

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public static boolean f134233b;

    public final void a(String str, String str2) {
        if (f134233b) {
            Log.d(str, str2);
        }
    }

    public final void b(String str, String str2) {
        Log.e(str, str2);
    }

    public final void c(String str, String str2) {
        if (f134233b) {
            Log.i(str, str2);
        }
    }
}
