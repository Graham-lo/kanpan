package Rj;

import android.graphics.Paint;

/* JADX INFO: renamed from: Rj.f, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public abstract class AbstractC2708f extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final Paint f19382l;

    public AbstractC2708f(C2732n c2732n, String str) {
        super(c2732n, str);
        this.f19382l = new Paint();
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        if (aVar == null) {
            return;
        }
        Paint paint = this.f19382l;
        paint.setStyle(Paint.Style.FILL);
        paint.setColor(aVar.c(1));
    }

    public final Paint v() {
        return this.f19382l;
    }
}
