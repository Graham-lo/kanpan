package nk;

import android.content.Context;
import android.util.TypedValue;

/* JADX INFO: loaded from: classes7.dex */
public final class u {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final u f134248a = new u();

    public static final float a(Context context, float f10) {
        return context == null ? f10 : TypedValue.applyDimension(1, f10, context.getResources().getDisplayMetrics());
    }
}
