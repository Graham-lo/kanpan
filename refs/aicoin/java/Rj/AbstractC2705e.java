package Rj;

import android.graphics.Canvas;
import java.util.ArrayList;
import java.util.List;

/* JADX INFO: renamed from: Rj.e, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public abstract class AbstractC2705e extends C2702d {

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final ArrayList f19363r;

    public AbstractC2705e(String str) {
        super(str);
        this.f19363r = new ArrayList();
    }

    public final void I(C2702d c2702d) {
        this.f19363r.add(c2702d);
    }

    public abstract void J(Canvas canvas);

    public final List K() {
        return this.f19363r;
    }

    public abstract void L(mk.a aVar);
}
