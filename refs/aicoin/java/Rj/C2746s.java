package Rj;

import android.content.Context;
import android.view.GestureDetector;
import android.view.MotionEvent;
import android.view.VelocityTracker;
import android.view.View;
import android.view.ViewConfiguration;
import android.widget.OverScroller;
import com.davemorrissey.labs.subscaleview.SubsamplingScaleImageView;

/* JADX INFO: renamed from: Rj.s, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C2746s {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final C2732n f19529a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final View f19530b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final Wj.a f19531c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public final String f19532d;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public final GestureDetector f19533e;

    /* JADX INFO: renamed from: f, reason: collision with root package name */
    public VelocityTracker f19534f;

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public final OverScroller f19535g;

    /* JADX INFO: renamed from: h, reason: collision with root package name */
    public final int f19536h;

    /* JADX INFO: renamed from: i, reason: collision with root package name */
    public final int f19537i;

    /* JADX INFO: renamed from: j, reason: collision with root package name */
    public int f19538j;

    /* JADX INFO: renamed from: k, reason: collision with root package name */
    public final Yj.a f19539k;

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public boolean f19540l;

    /* JADX INFO: renamed from: Rj.s$a */
    public static final class a extends GestureDetector.SimpleOnGestureListener {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public final C2732n f19541a;

        /* JADX INFO: renamed from: b, reason: collision with root package name */
        public final String f19542b;

        public a(C2732n c2732n, String str) {
            this.f19541a = c2732n;
            this.f19542b = str;
        }

        @Override // android.view.GestureDetector.SimpleOnGestureListener, android.view.GestureDetector.OnGestureListener
        public boolean onSingleTapUp(MotionEvent motionEvent) {
            if (motionEvent == null) {
                return false;
            }
            C2741q c2741qB = this.f19541a.b();
            String str = this.f19542b;
            int x10 = (int) motionEvent.getX();
            int y10 = (int) motionEvent.getY();
            if (str == null) {
                c2741qB.getClass();
                return false;
            }
            for (AbstractC2744r0 abstractC2744r0 : c2741qB.f19502j.values()) {
                if (abstractC2744r0 != null && str.equals(abstractC2744r0.c()) && abstractC2744r0.n(str, x10, y10)) {
                    return true;
                }
            }
            for (AbstractC2744r0 abstractC2744r1 : c2741qB.f19501i.values()) {
                if (abstractC2744r1 != null && str.equals(abstractC2744r1.c()) && abstractC2744r1.n(str, x10, y10)) {
                    return true;
                }
            }
            return false;
        }
    }

    public C2746s(C2732n c2732n, View view, Wj.a aVar, String str) {
        this.f19529a = c2732n;
        this.f19530b = view;
        this.f19531c = aVar;
        this.f19532d = str;
        Context context = view.getContext();
        this.f19535g = new OverScroller(context);
        ViewConfiguration viewConfiguration = ViewConfiguration.get(context);
        this.f19536h = viewConfiguration.getScaledMinimumFlingVelocity();
        this.f19537i = viewConfiguration.getScaledMaximumFlingVelocity();
        this.f19533e = new GestureDetector(context, new a(c2732n, str));
        this.f19539k = (Yj.a) Yj.d.a("animation");
    }

    public final void a() {
        if (!this.f19535g.computeScrollOffset()) {
            if (this.f19540l) {
                this.f19539k.c(4);
                return;
            } else {
                this.f19539k.c(0);
                return;
            }
        }
        y1 y1VarM = this.f19529a.b().m(this.f19532d);
        int currX = this.f19535g.getCurrX() - this.f19538j;
        this.f19538j = this.f19535g.getCurrX();
        if (y1VarM != null && y1VarM.O(currX)) {
            if (currX > 0) {
                C2738p.m();
            } else if (currX < 0) {
                C2738p.p();
            }
            b();
        }
        this.f19530b.invalidate();
        this.f19539k.c(8);
    }

    public final void b() {
        this.f19535g.forceFinished(true);
    }

    public final void c(MotionEvent motionEvent) {
        VelocityTracker velocityTrackerObtain = this.f19534f;
        if (velocityTrackerObtain == null) {
            velocityTrackerObtain = VelocityTracker.obtain();
            this.f19534f = velocityTrackerObtain;
        }
        if (velocityTrackerObtain != null) {
            velocityTrackerObtain.addMovement(motionEvent);
        }
        this.f19533e.onTouchEvent(motionEvent);
    }

    public final void d(MotionEvent motionEvent) {
        this.f19540l = true;
        motionEvent.getX();
        this.f19535g.forceFinished(true);
        this.f19539k.c(4);
    }

    public final void e(MotionEvent motionEvent) {
        if (motionEvent.getPointerCount() != 1) {
            return;
        }
        this.f19540l = false;
        this.f19538j = (int) motionEvent.getX();
        VelocityTracker velocityTracker = this.f19534f;
        if (velocityTracker != null) {
            velocityTracker.computeCurrentVelocity(1000, this.f19537i);
            int xVelocity = (int) velocityTracker.getXVelocity();
            int iS = this.f19531c.s();
            if (Math.abs(xVelocity) > this.f19536h && iS != 2 && iS != 6 && iS != 8 && iS != 9) {
                this.f19535g.fling(this.f19538j, 0, xVelocity, 0, Integer.MIN_VALUE, SubsamplingScaleImageView.TILE_SIZE_AUTO, 0, 0);
                this.f19530b.invalidate();
            }
            VelocityTracker velocityTracker2 = this.f19534f;
            if (velocityTracker2 != null) {
                velocityTracker2.recycle();
                this.f19534f = null;
            }
        }
        this.f19539k.c(0);
    }
}
