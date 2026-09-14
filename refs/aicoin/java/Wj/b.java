package Wj;

import android.content.Context;
import android.os.Handler;
import android.view.GestureDetector;
import android.view.MotionEvent;
import android.view.ViewConfiguration;

/* JADX INFO: loaded from: classes7.dex */
public class b {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final Context f24762a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final InterfaceC0388b f24763b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public float f24764c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public float f24765d;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public boolean f24766e;

    /* JADX INFO: renamed from: f, reason: collision with root package name */
    public boolean f24767f;

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public float f24768g;

    /* JADX INFO: renamed from: h, reason: collision with root package name */
    public float f24769h;

    /* JADX INFO: renamed from: i, reason: collision with root package name */
    public float f24770i;

    /* JADX INFO: renamed from: j, reason: collision with root package name */
    public float f24771j;

    /* JADX INFO: renamed from: k, reason: collision with root package name */
    public float f24772k;

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public float f24773l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public float f24774m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public long f24775n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public long f24776o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public boolean f24777p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final int f24778q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final int f24779r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public final Handler f24780s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public float f24781t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public float f24782u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public int f24783v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public GestureDetector f24784w;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public boolean f24785x;

    public class a extends GestureDetector.SimpleOnGestureListener {
        public a() {
        }

        @Override // android.view.GestureDetector.SimpleOnGestureListener, android.view.GestureDetector.OnDoubleTapListener
        public boolean onDoubleTap(MotionEvent motionEvent) {
            b.this.f24781t = motionEvent.getX();
            b.this.f24782u = motionEvent.getY();
            b.this.f24783v = 1;
            return true;
        }
    }

    /* JADX INFO: renamed from: Wj.b$b, reason: collision with other inner class name */
    public interface InterfaceC0388b {
        boolean a(b bVar);

        void b(b bVar);

        boolean c(b bVar);
    }

    public static class c implements InterfaceC0388b {
        @Override // Wj.b.InterfaceC0388b
        public boolean a(b bVar) {
            return true;
        }
    }

    public b(Context context, InterfaceC0388b interfaceC0388b) {
        this(context, interfaceC0388b, null);
    }

    public b(Context context, InterfaceC0388b interfaceC0388b, Handler handler) {
        this.f24783v = 0;
        this.f24762a = context;
        this.f24763b = interfaceC0388b;
        this.f24778q = ViewConfiguration.get(context).getScaledTouchSlop() * 2;
        this.f24779r = 50;
        this.f24780s = handler;
        int i10 = context.getApplicationInfo().targetSdkVersion;
        if (i10 > 18) {
            e(true);
        }
        if (i10 > 22) {
            f(true);
        }
    }

    public final boolean a() {
        return this.f24783v != 0;
    }

    public float b() {
        return this.f24764c;
    }

    public float c() {
        if (!a()) {
            float f10 = this.f24769h;
            if (f10 > 0.0f) {
                return this.f24768g / f10;
            }
            return 1.0f;
        }
        boolean z10 = this.f24785x;
        boolean z11 = (z10 && this.f24768g < this.f24769h) || (!z10 && this.f24768g > this.f24769h);
        float fAbs = Math.abs(1.0f - (this.f24768g / this.f24769h)) * 0.5f;
        if (this.f24769h <= this.f24778q) {
            return 1.0f;
        }
        return z11 ? fAbs + 1.0f : 1.0f - fAbs;
    }

    public boolean d(MotionEvent motionEvent) {
        float f10;
        float f11;
        this.f24775n = motionEvent.getEventTime();
        int actionMasked = motionEvent.getActionMasked();
        if (this.f24766e) {
            this.f24784w.onTouchEvent(motionEvent);
        }
        int pointerCount = motionEvent.getPointerCount();
        boolean z10 = (motionEvent.getButtonState() & 32) != 0;
        boolean z11 = this.f24783v == 2 && !z10;
        boolean z12 = actionMasked == 1 || actionMasked == 3 || z11;
        float fAbs = 0.0f;
        if (actionMasked == 0 || z12) {
            if (this.f24777p) {
                this.f24763b.b(this);
                this.f24777p = false;
                this.f24770i = 0.0f;
                this.f24783v = 0;
            } else if (a() && z12) {
                this.f24777p = false;
                this.f24770i = 0.0f;
                this.f24783v = 0;
            }
            if (z12) {
                return true;
            }
        }
        if (!this.f24777p && this.f24767f && !a() && !z12 && z10) {
            this.f24781t = motionEvent.getX();
            this.f24782u = motionEvent.getY();
            this.f24783v = 2;
            this.f24770i = 0.0f;
        }
        boolean z13 = actionMasked == 0 || actionMasked == 6 || actionMasked == 5 || z11;
        boolean z14 = actionMasked == 6;
        int actionIndex = z14 ? motionEvent.getActionIndex() : -1;
        int i10 = z14 ? pointerCount - 1 : pointerCount;
        if (a()) {
            f11 = this.f24781t;
            f10 = this.f24782u;
            if (motionEvent.getY() < f10) {
                this.f24785x = true;
            } else {
                this.f24785x = false;
            }
        } else {
            float y10 = 0.0f;
            float x10 = 0.0f;
            for (int i11 = 0; i11 < pointerCount; i11++) {
                if (actionIndex != i11) {
                    x10 += motionEvent.getX(i11);
                    y10 += motionEvent.getY(i11);
                }
            }
            float f12 = i10;
            f10 = y10 / f12;
            f11 = x10 / f12;
        }
        float f13 = 0.0f;
        for (int i12 = 0; i12 < pointerCount; i12++) {
            if (actionIndex != i12) {
                float fAbs2 = Math.abs(motionEvent.getX(i12) - f11) + f13;
                fAbs = Math.abs(motionEvent.getY(i12) - f10) + fAbs;
                f13 = fAbs2;
            }
        }
        float f14 = i10;
        float f15 = (f13 / f14) * 2.0f;
        float f16 = (fAbs / f14) * 2.0f;
        float fHypot = a() ? f16 : (float) Math.hypot(f15, f16);
        boolean z15 = this.f24777p;
        this.f24764c = f11;
        this.f24765d = f10;
        if (!a() && this.f24777p && (fHypot < this.f24779r || z13)) {
            this.f24763b.b(this);
            this.f24777p = false;
            this.f24770i = fHypot;
        }
        if (z13) {
            this.f24771j = f15;
            this.f24773l = f15;
            this.f24772k = f16;
            this.f24774m = f16;
            this.f24768g = fHypot;
            this.f24769h = fHypot;
            this.f24770i = fHypot;
        }
        int i13 = a() ? this.f24778q : this.f24779r;
        if (!this.f24777p && fHypot >= i13 && (z15 || Math.abs(fHypot - this.f24770i) > this.f24778q)) {
            this.f24771j = f15;
            this.f24773l = f15;
            this.f24772k = f16;
            this.f24774m = f16;
            this.f24768g = fHypot;
            this.f24769h = fHypot;
            this.f24776o = this.f24775n;
            this.f24777p = this.f24763b.a(this);
        }
        if (actionMasked == 2) {
            this.f24771j = f15;
            this.f24772k = f16;
            this.f24768g = fHypot;
            if (this.f24777p ? this.f24763b.c(this) : true) {
                this.f24773l = this.f24771j;
                this.f24774m = this.f24772k;
                this.f24769h = this.f24768g;
                this.f24776o = this.f24775n;
            }
        }
        return true;
    }

    public void e(boolean z10) {
        this.f24766e = z10;
        if (z10 && this.f24784w == null) {
            this.f24784w = new GestureDetector(this.f24762a, new a(), this.f24780s);
        }
    }

    public void f(boolean z10) {
        this.f24767f = z10;
    }
}
