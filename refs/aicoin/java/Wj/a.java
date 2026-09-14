package Wj;

import Rj.AbstractC2759w0;
import Rj.C2702d;
import Rj.C2732n;
import Rj.C2738p;
import Rj.C2741q;
import Rj.C2760w1;
import Rj.G;
import Rj.y1;
import android.content.Context;
import android.os.Handler;
import android.os.Message;
import android.view.GestureDetector;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.ViewParent;
import androidx.p022lifecycle.MutableLiveData;
import com.tencent.android.tpush.common.MessageKey;
import kotlin.jvm.internal.DefaultConstructorMarker;
import nk.p;
import sp.aicoin_kline.chart.Chart;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class a {

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public static final b f24740r = new b(null);

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final View f24741a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final String f24742b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public float f24743c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public float f24744d;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public final C2741q f24745e;

    /* JADX INFO: renamed from: f, reason: collision with root package name */
    public final KLineManager f24746f;

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public final Wj.b f24747g;

    /* JADX INFO: renamed from: h, reason: collision with root package name */
    public final GestureDetector f24748h;

    /* JADX INFO: renamed from: i, reason: collision with root package name */
    public float f24749i;

    /* JADX INFO: renamed from: j, reason: collision with root package name */
    public float f24750j;

    /* JADX INFO: renamed from: k, reason: collision with root package name */
    public int f24751k;

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public int f24752l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final int f24753m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final c f24754n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public boolean f24755o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public float f24756p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public double f24757q;

    /* JADX INFO: renamed from: Wj.a$a, reason: collision with other inner class name */
    public final class C0387a extends GestureDetector.SimpleOnGestureListener {
        public C0387a() {
        }

        @Override // android.view.GestureDetector.SimpleOnGestureListener, android.view.GestureDetector.OnDoubleTapListener
        public boolean onDoubleTap(MotionEvent motionEvent) {
            if (motionEvent == null) {
                return false;
            }
            if (a.l(a.this, motionEvent.getX(), motionEvent.getY())) {
                a aVar = a.this;
                aVar.a();
                AbstractC2759w0 abstractC2759w0L = aVar.f24745e.l(aVar.f24742b + ".main");
                if (abstractC2759w0L != null && abstractC2759w0L.F()) {
                    aVar.f24752l = 8;
                    aVar.f24751k = -1;
                    View view = aVar.f24741a;
                    Chart chart = view instanceof Chart ? (Chart) view : null;
                    if (chart != null) {
                        chart.u();
                        return true;
                    }
                    view.invalidate();
                    return true;
                }
            }
            C2738p.f19487a.f();
            return super.onDoubleTap(motionEvent);
        }

        @Override // android.view.GestureDetector.SimpleOnGestureListener, android.view.GestureDetector.OnGestureListener
        public boolean onScroll(MotionEvent motionEvent, MotionEvent motionEvent2, float f10, float f11) {
            y1 y1VarG = a.g(a.this);
            if (y1VarG == null) {
                return true;
            }
            int i10 = a.this.f24751k;
            if (i10 != 2) {
                if (i10 != 6) {
                    if (i10 != 8) {
                        if (i10 != 9) {
                            if (a.this.f24751k == 4) {
                                y1VarG.P();
                            } else {
                                y1VarG.O(-f10);
                            }
                            a.this.f24741a.invalidate();
                        } else {
                            a.m(a.this, f11);
                        }
                    } else if (motionEvent2 != null) {
                        a.this.b(motionEvent2.getY());
                    }
                } else if (motionEvent2 != null) {
                    a aVar = a.this;
                    aVar.f24743c = motionEvent2.getX();
                    aVar.f24744d = motionEvent2.getY();
                    G gE = a.e(aVar);
                    if (gE != null) {
                        gE.F(motionEvent2.getX(), motionEvent2.getY());
                    }
                    aVar.f24741a.invalidate();
                }
            } else if (motionEvent2 != null) {
                a aVar2 = a.this;
                aVar2.f24743c = motionEvent2.getX();
                aVar2.f24744d = motionEvent2.getY();
                aVar2.r();
                aVar2.f24741a.invalidate();
            }
            return super.onScroll(motionEvent, motionEvent2, f10, f11);
        }

        @Override // android.view.GestureDetector.SimpleOnGestureListener, android.view.GestureDetector.OnGestureListener
        public boolean onSingleTapUp(MotionEvent motionEvent) {
            if (motionEvent != null && a.this.f24752l != 2 && a.this.f24752l != 8 && a.this.f24752l != 9) {
                if (a.this.f24755o) {
                    y1 y1VarG = a.g(a.this);
                    if (y1VarG != null) {
                        y1VarG.Y(false);
                    }
                    G gE = a.e(a.this);
                    if (gE != null) {
                        gE.m(motionEvent.getX(), motionEvent.getY());
                    }
                } else {
                    y1 y1VarG2 = a.g(a.this);
                    if (y1VarG2 != null) {
                        y1VarG2.a0();
                    }
                    y1 y1VarG3 = a.g(a.this);
                    if (y1VarG3 != null) {
                        y1VarG3.U(motionEvent.getX());
                    }
                    y1 y1VarG4 = a.g(a.this);
                    if (y1VarG4 != null) {
                        y1VarG4.Z(motionEvent.getY());
                    }
                }
                a.this.f24741a.invalidate();
            }
            return false;
        }
    }

    public static final class b {
        public b(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public final class c extends Handler {
        public c() {
        }

        @Override // android.os.Handler
        public void handleMessage(Message message) {
            if (message.what == 1 && a.this.f24751k == 0) {
                a aVar = a.this;
                a.q(aVar, aVar.f24749i, a.this.f24750j);
            }
        }
    }

    public final class d extends Wj.b.c {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public float f24760a = 1.0f;

        public d() {
        }

        @Override // Wj.b.c, Wj.b.InterfaceC0388b
        public boolean a(Wj.b bVar) {
            p.f134232a.a("KlineLog-onScale", "begin");
            this.f24760a = C2760w1.f19594a.i();
            return super.a(bVar);
        }

        @Override // Wj.b.InterfaceC0388b
        public void b(Wj.b bVar) {
            p.f134232a.a("KlineLog-onScale", MessageKey.MSG_ACCEPT_TIME_END);
            C2760w1.f19594a.l(this.f24760a);
        }

        @Override // Wj.b.InterfaceC0388b
        public boolean c(Wj.b bVar) {
            p.f134232a.a("KlineLog-onScale", "scale");
            if (a.this.f24751k == 2) {
                return true;
            }
            this.f24760a = Math.max(0.4f, Math.min(this.f24760a * bVar.c(), 10.0f));
            y1 y1VarG = a.g(a.this);
            if (y1VarG != null) {
                y1VarG.Q(this.f24760a, bVar.b());
            }
            a.this.f24741a.invalidate();
            return true;
        }
    }

    public a(C2732n c2732n, View view, String str) {
        this.f24741a = view;
        this.f24742b = str;
        Context context = view.getContext();
        this.f24745e = c2732n.b();
        this.f24746f = KLineManager.f142490O.a();
        Wj.b bVar = new Wj.b(context, new d());
        this.f24747g = bVar;
        GestureDetector gestureDetector = new GestureDetector(context, new C0387a());
        this.f24748h = gestureDetector;
        this.f24752l = -1;
        this.f24754n = new c();
        this.f24757q = 1.0d;
        gestureDetector.setIsLongpressEnabled(false);
        bVar.e(false);
        this.f24753m = ViewConfiguration.get(context).getScaledTouchSlop();
    }

    public static final G e(a aVar) {
        return aVar.f24745e.i(aVar.f24742b);
    }

    public static final y1 g(a aVar) {
        return aVar.f24745e.m(aVar.f24742b);
    }

    public static final boolean l(a aVar, float f10, float f11) {
        C2702d c2702dE = aVar.f24745e.e(aVar.f24742b + ".mainRange");
        return c2702dE != null && c2702dE.k(f10, f11);
    }

    public static final void m(a aVar, float f10) {
        AbstractC2759w0 abstractC2759w0L = aVar.f24745e.l(aVar.f24742b + ".main");
        if (abstractC2759w0L != null && abstractC2759w0L.D(Wj.c.f24787a.a(f10))) {
            View view = aVar.f24741a;
            Chart chart = view instanceof Chart ? (Chart) view : null;
            if (chart != null) {
                chart.u();
            } else {
                view.invalidate();
            }
        }
    }

    public static final void q(a aVar, float f10, float f11) {
        aVar.f24751k = 2;
        aVar.f24743c = f10;
        aVar.f24744d = f11;
        y1 y1VarM = aVar.f24745e.m(aVar.f24742b);
        if (y1VarM != null) {
            y1VarM.Y(true);
        }
        aVar.r();
        aVar.f24741a.invalidate();
    }

    public final void a() {
        if (this.f24751k == 8) {
            AbstractC2759w0 abstractC2759w0L = this.f24745e.l(this.f24742b + ".main");
            if (abstractC2759w0L != null) {
                abstractC2759w0L.n();
            }
        }
    }

    public final void b(float f10) {
        AbstractC2759w0 abstractC2759w0L = this.f24745e.l(this.f24742b + ".main");
        if (abstractC2759w0L == null) {
            return;
        }
        C2702d c2702dE = this.f24745e.e(this.f24742b + ".mainRange");
        if (c2702dE == null) {
            return;
        }
        abstractC2759w0L.W(Math.pow(2.0d, ((double) (-(f10 - this.f24756p))) / Math.max(((double) c2702dE.t()) / 4.0d, 1.0d)) * this.f24757q);
        View view = this.f24741a;
        Chart chart = view instanceof Chart ? (Chart) view : null;
        if (chart != null) {
            chart.u();
        } else {
            view.invalidate();
        }
    }

    public final void r() {
        y1 y1VarM = this.f24745e.m(this.f24742b);
        if (y1VarM != null) {
            y1VarM.W(this.f24743c);
        }
        y1 y1VarM2 = this.f24745e.m(this.f24742b);
        if (y1VarM2 != null) {
            y1VarM2.X(this.f24744d);
        }
        y1 y1VarM3 = this.f24745e.m(this.f24742b);
        if (y1VarM3 != null) {
            y1VarM3.Z(this.f24744d);
        }
        y1 y1VarM4 = this.f24745e.m(this.f24742b);
        if (y1VarM4 != null) {
            y1VarM4.K(this.f24743c);
        }
    }

    public final int s() {
        return this.f24752l;
    }

    public final boolean t(MotionEvent motionEvent, boolean z10) {
        G gI;
        MutableLiveData mutableLiveDataU;
        this.f24755o = z10;
        if (z10) {
            y1 y1VarM = this.f24745e.m(this.f24742b);
            if (y1VarM == null || (gI = this.f24745e.i(this.f24742b)) == null) {
                return false;
            }
            int action = motionEvent.getAction() & 255;
            if (action == 0) {
                this.f24749i = motionEvent.getX();
                this.f24750j = motionEvent.getY();
                this.f24752l = -1;
                this.f24751k = gI.y(motionEvent.getX(), motionEvent.getY()) ? 7 : 0;
            } else if (motionEvent.getAction() == 2) {
                int i10 = this.f24751k;
                if (i10 == 0) {
                    if (motionEvent.getPointerCount() > 1) {
                        this.f24754n.removeMessages(1);
                        this.f24751k = y1VarM.M() ? 4 : 3;
                    } else {
                        float fAbs = Math.abs(motionEvent.getX() - this.f24749i);
                        float fAbs2 = Math.abs(motionEvent.getY() - this.f24750j);
                        float f10 = this.f24753m;
                        if (fAbs > f10 || fAbs2 > f10) {
                            if (fAbs2 > ((double) fAbs) * 1.5d) {
                                this.f24751k = 5;
                                this.f24754n.removeMessages(1);
                            } else {
                                this.f24751k = 1;
                            }
                        }
                    }
                } else if (i10 == 7) {
                    if (motionEvent.getPointerCount() > 1) {
                        this.f24754n.removeMessages(1);
                        this.f24751k = y1VarM.M() ? 4 : 3;
                    } else {
                        this.f24754n.removeMessages(1);
                        float x10 = motionEvent.getX();
                        float y10 = motionEvent.getY();
                        this.f24751k = 6;
                        G gI2 = this.f24745e.i(this.f24742b);
                        if (gI2 != null) {
                            gI2.F(x10, y10);
                        }
                        this.f24741a.invalidate();
                        MutableLiveData mutableLiveDataU2 = this.f24746f.U();
                        if (mutableLiveDataU2 != null) {
                            mutableLiveDataU2.setValue(Boolean.TRUE);
                        }
                    }
                }
            } else if (action == 1) {
                if (this.f24751k == 6 && (mutableLiveDataU = this.f24746f.U()) != null) {
                    mutableLiveDataU.setValue(Boolean.FALSE);
                }
                this.f24752l = this.f24751k;
                this.f24751k = -1;
                this.f24754n.removeMessages(1);
                gI.q();
                this.f24741a.invalidate();
            } else if (action == 5) {
                this.f24754n.removeMessages(1);
            } else if (action == 3) {
                this.f24754n.removeMessages(1);
                gI.q();
                this.f24741a.invalidate();
            }
            boolean z11 = this.f24751k != 5;
            ViewParent parent = this.f24741a.getParent();
            if (parent != null) {
                parent.requestDisallowInterceptTouchEvent(z11);
            }
            this.f24748h.onTouchEvent(motionEvent);
            this.f24747g.d(motionEvent);
            return this.f24751k != 5;
        }
        y1 y1VarM2 = this.f24745e.m(this.f24742b);
        if (y1VarM2 == null) {
            return false;
        }
        int action2 = motionEvent.getAction() & 255;
        if (action2 == 0) {
            this.f24749i = motionEvent.getX();
            this.f24750j = motionEvent.getY();
            this.f24752l = -1;
            this.f24751k = 0;
            this.f24754n.sendEmptyMessageDelayed(1, 400L);
        } else if (motionEvent.getAction() == 2) {
            int i11 = this.f24751k;
            if (i11 == 0) {
                long eventTime = motionEvent.getEventTime() - motionEvent.getDownTime();
                if (motionEvent.getPointerCount() > 1) {
                    this.f24754n.removeMessages(1);
                    this.f24751k = y1VarM2.M() ? 4 : 3;
                    p.f134232a.a("KlineLog-onScale", "lastVisible = " + y1VarM2.M());
                } else if (eventTime < 400) {
                    float fAbs3 = Math.abs(motionEvent.getX() - this.f24749i);
                    float fAbs4 = Math.abs(motionEvent.getY() - this.f24750j);
                    float f11 = this.f24753m;
                    if (fAbs3 > f11 || fAbs4 > f11) {
                        float f12 = this.f24749i;
                        float f13 = this.f24750j;
                        C2702d c2702dE = this.f24745e.e(this.f24742b + ".mainRange");
                        if (c2702dE == null || !c2702dE.k(f12, f13) || fAbs4 < this.f24753m || fAbs4 < fAbs3) {
                            Wj.c cVar = Wj.c.f24787a;
                            int i12 = this.f24753m;
                            float f14 = this.f24749i;
                            float f15 = this.f24750j;
                            C2702d c2702dE2 = this.f24745e.e(this.f24742b + ".main");
                            boolean z12 = c2702dE2 != null && c2702dE2.k(f14, f15);
                            AbstractC2759w0 abstractC2759w0L = this.f24745e.l(this.f24742b + ".main");
                            if (cVar.b(fAbs3, fAbs4, i12, z12, abstractC2759w0L != null && abstractC2759w0L.k())) {
                                this.f24751k = 9;
                                this.f24754n.removeMessages(1);
                            } else if (fAbs4 > ((double) fAbs3) * 1.5d) {
                                this.f24751k = 5;
                                this.f24754n.removeMessages(1);
                            } else {
                                this.f24751k = 1;
                            }
                        } else {
                            float y11 = motionEvent.getY();
                            AbstractC2759w0 abstractC2759w0L2 = this.f24745e.l(this.f24742b + ".main");
                            if (abstractC2759w0L2 != null && abstractC2759w0L2.j(y11)) {
                                this.f24756p = y11;
                                this.f24757q = abstractC2759w0L2.B();
                                this.f24751k = 8;
                                this.f24754n.removeMessages(1);
                                b(motionEvent.getY());
                            } else {
                                this.f24751k = 5;
                                this.f24754n.removeMessages(1);
                            }
                        }
                    }
                } else {
                    this.f24754n.removeMessages(1);
                    float x11 = motionEvent.getX();
                    float y12 = motionEvent.getY();
                    this.f24751k = 2;
                    this.f24743c = x11;
                    this.f24744d = y12;
                    y1 y1VarM3 = this.f24745e.m(this.f24742b);
                    if (y1VarM3 != null) {
                        y1VarM3.Y(true);
                    }
                    r();
                    this.f24741a.invalidate();
                }
            } else if (i11 == 8) {
                this.f24754n.removeMessages(1);
                b(motionEvent.getY());
            } else if (i11 == 9) {
                this.f24754n.removeMessages(1);
            }
        } else if (action2 == 1) {
            if (this.f24751k == 2) {
                y1VarM2.Y(true);
                y1VarM2.U(motionEvent.getX());
                y1VarM2.Z(motionEvent.getY());
                y1VarM2.W(-1.0f);
                y1VarM2.X(-1.0f);
            }
            a();
            this.f24752l = this.f24751k;
            this.f24751k = -1;
            this.f24754n.removeMessages(1);
        } else if (action2 == 5) {
            int i13 = this.f24751k;
            if (i13 == 8 || i13 == 9) {
                a();
                this.f24751k = y1VarM2.M() ? 4 : 3;
            }
            this.f24754n.removeMessages(1);
        } else if (action2 == 3) {
            a();
            this.f24754n.removeMessages(1);
        }
        boolean z13 = this.f24751k != 5;
        ViewParent parent2 = this.f24741a.getParent();
        if (parent2 != null) {
            parent2.requestDisallowInterceptTouchEvent(z13);
        }
        this.f24748h.onTouchEvent(motionEvent);
        this.f24747g.d(motionEvent);
        return this.f24751k != 5;
    }

    public final boolean u(boolean z10) {
        a();
        AbstractC2759w0 abstractC2759w0L = this.f24745e.l(this.f24742b + ".main");
        if (abstractC2759w0L == null || !abstractC2759w0L.F()) {
            return false;
        }
        this.f24752l = 8;
        this.f24751k = -1;
        if (!z10) {
            return true;
        }
        View view = this.f24741a;
        Chart chart = view instanceof Chart ? (Chart) view : null;
        if (chart != null) {
            chart.u();
            return true;
        }
        view.invalidate();
        return true;
    }

    public final void v() {
        y1 y1VarM = this.f24745e.m(this.f24742b);
        if (y1VarM != null) {
            y1VarM.a0();
        }
        this.f24741a.invalidate();
    }
}
