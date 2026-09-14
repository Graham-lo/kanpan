package Rj;

import android.animation.ValueAnimator;

/* JADX INFO: renamed from: Rj.x0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final /* synthetic */ class C2762x0 implements ValueAnimator.AnimatorUpdateListener {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final /* synthetic */ C2764y0 f19602a;

    public /* synthetic */ C2762x0(C2764y0 c2764y0) {
        this.f19602a = c2764y0;
    }

    @Override // android.animation.ValueAnimator.AnimatorUpdateListener
    public final void onAnimationUpdate(ValueAnimator valueAnimator) {
        C2764y0.a(this.f19602a, valueAnimator);
    }
}
