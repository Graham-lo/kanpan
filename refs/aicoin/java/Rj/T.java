package Rj;

import android.graphics.Paint;
import android.graphics.Rect;
import kotlin.jvm.internal.DefaultConstructorMarker;

/* JADX INFO: loaded from: classes7.dex */
public abstract class T extends AbstractC2744r0 {

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public static final a f19241q = new a(null);

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final Paint f19242l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final Paint[] f19243m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final float f19244n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final float f19245o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public boolean f19246p;

    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public T(C2732n c2732n, String str) {
        super(c2732n, str);
        new nk.r();
        new Rect();
        Paint paint = new Paint();
        paint.setAntiAlias(true);
        paint.setTextAlign(Paint.Align.LEFT);
        paint.setTextSize(Xj.a.d(9));
        this.f19242l = paint;
        Paint[] paintArr = new Paint[6];
        for (int i10 = 0; i10 < 6; i10++) {
            paintArr[i10] = new Paint(this.f19242l);
        }
        this.f19243m = paintArr;
        this.f19244n = 8.0f;
        this.f19245o = -this.f19242l.getFontMetrics().top;
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        if (aVar == null) {
            return;
        }
        this.f19242l.setColor(aVar.u(1));
        this.f19246p = aVar.w();
        int length = this.f19243m.length;
        for (int i10 = 0; i10 < length; i10++) {
            this.f19243m[i10].setColor(aVar.b(i10));
        }
    }

    public final float v() {
        return this.f19245o;
    }

    public final float w() {
        return this.f19244n;
    }

    public final Paint x() {
        return this.f19242l;
    }

    public final Paint[] y() {
        return this.f19243m;
    }
}
