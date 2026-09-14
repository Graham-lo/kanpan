package fk;

import Rj.AbstractC2744r0;
import Rj.AbstractC2755v;
import Rj.AbstractC2759w0;
import Rj.C2702d;
import Rj.C2732n;
import Rj.C2738p;
import Rj.C2741q;
import Rj.y1;
import android.content.Context;
import android.content.res.Resources;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.DashPathEffect;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.Rect;
import android.graphics.RectF;
import android.os.Handler;
import android.os.Looper;
import androidx.p022lifecycle.CoroutineLiveDataKt;
import com.tencent.android.tpush.common.MessageKey;
import gk.C7495w;
import java.lang.reflect.Field;
import java.util.Iterator;
import java.util.List;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.R;
import sp.aicoin_kline.chart.data.AlertLineItem;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: fk.s, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C7393s extends AbstractC2744r0 {

    /* JADX INFO: renamed from: r0, reason: collision with root package name */
    public static final a f95443r0 = new a(null);

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public boolean f95444A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public boolean f95445B;

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public final Handler f95446C;

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public final Runnable f95447D;

    /* JADX INFO: renamed from: E, reason: collision with root package name */
    public final long f95448E;

    /* JADX INFO: renamed from: F, reason: collision with root package name */
    public final Handler f95449F;

    /* JADX INFO: renamed from: G, reason: collision with root package name */
    public final Runnable f95450G;

    /* JADX INFO: renamed from: H, reason: collision with root package name */
    public final long f95451H;

    /* JADX INFO: renamed from: I, reason: collision with root package name */
    public final Handler f95452I;

    /* JADX INFO: renamed from: J, reason: collision with root package name */
    public final Runnable f95453J;

    /* JADX INFO: renamed from: K, reason: collision with root package name */
    public final long f95454K;

    /* JADX INFO: renamed from: L, reason: collision with root package name */
    public final Handler f95455L;

    /* JADX INFO: renamed from: M, reason: collision with root package name */
    public final Runnable f95456M;

    /* JADX INFO: renamed from: N, reason: collision with root package name */
    public final long f95457N;

    /* JADX INFO: renamed from: O, reason: collision with root package name */
    public boolean f95458O;

    /* JADX INFO: renamed from: P, reason: collision with root package name */
    public float f95459P;

    /* JADX INFO: renamed from: Q, reason: collision with root package name */
    public AlertLineItem f95460Q;

    /* JADX INFO: renamed from: R, reason: collision with root package name */
    public final float f95461R;

    /* JADX INFO: renamed from: S, reason: collision with root package name */
    public long f95462S;

    /* JADX INFO: renamed from: T, reason: collision with root package name */
    public final long f95463T;

    /* JADX INFO: renamed from: U, reason: collision with root package name */
    public boolean f95464U;

    /* JADX INFO: renamed from: V, reason: collision with root package name */
    public Double f95465V;

    /* JADX INFO: renamed from: W, reason: collision with root package name */
    public boolean f95466W;

    /* JADX INFO: renamed from: X, reason: collision with root package name */
    public boolean f95467X;

    /* JADX INFO: renamed from: Y, reason: collision with root package name */
    public String f95468Y;

    /* JADX INFO: renamed from: Z, reason: collision with root package name */
    public float f95469Z;

    /* JADX INFO: renamed from: a0, reason: collision with root package name */
    public double f95470a0;

    /* JADX INFO: renamed from: b0, reason: collision with root package name */
    public double f95471b0;

    /* JADX INFO: renamed from: c0, reason: collision with root package name */
    public String f95472c0;

    /* JADX INFO: renamed from: d0, reason: collision with root package name */
    public final RectF f95473d0;

    /* JADX INFO: renamed from: e0, reason: collision with root package name */
    public boolean f95474e0;

    /* JADX INFO: renamed from: f0, reason: collision with root package name */
    public float f95475f0;

    /* JADX INFO: renamed from: g0, reason: collision with root package name */
    public double f95476g0;

    /* JADX INFO: renamed from: h0, reason: collision with root package name */
    public final Paint f95477h0;

    /* JADX INFO: renamed from: i0, reason: collision with root package name */
    public final Paint f95478i0;

    /* JADX INFO: renamed from: j0, reason: collision with root package name */
    public final Paint f95479j0;

    /* JADX INFO: renamed from: k0, reason: collision with root package name */
    public final float f95480k0;

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final Paint f95481l;

    /* JADX INFO: renamed from: l0, reason: collision with root package name */
    public final float f95482l0;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final Paint f95483m;

    /* JADX INFO: renamed from: m0, reason: collision with root package name */
    public float f95484m0;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final Paint f95485n;

    /* JADX INFO: renamed from: n0, reason: collision with root package name */
    public C2741q f95486n0;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final Paint f95487o;

    /* JADX INFO: renamed from: o0, reason: collision with root package name */
    public y1 f95488o0;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final Paint f95489p;

    /* JADX INFO: renamed from: p0, reason: collision with root package name */
    public AbstractC2759w0 f95490p0;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public final Path f95491q;

    /* JADX INFO: renamed from: q0, reason: collision with root package name */
    public C7495w f95492q0;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final float f95493r;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public Bitmap f95494s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public Bitmap f95495t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public Bitmap f95496u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public final float f95497v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public final float f95498w;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public final float f95499x;

    /* JADX INFO: renamed from: y, reason: collision with root package name */
    public String f95500y;

    /* JADX INFO: renamed from: z, reason: collision with root package name */
    public final nk.r f95501z;

    /* JADX INFO: renamed from: fk.s$a */
    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }
    }

    public C7393s(C2732n c2732n, String str) {
        super(c2732n, str);
        Paint paint = new Paint();
        Paint.Style style = Paint.Style.STROKE;
        paint.setStyle(style);
        paint.setAntiAlias(true);
        paint.setStrokeWidth(2.0f);
        paint.setColor(Color.parseColor("#FAAD14"));
        paint.setPathEffect(new DashPathEffect(new float[]{10.0f, 5.0f}, 0.0f));
        this.f95481l = paint;
        Paint paint2 = new Paint();
        paint2.setStyle(style);
        paint2.setAntiAlias(true);
        paint2.setStrokeWidth(3.0f);
        paint2.setColor(Color.parseColor("#E89611"));
        paint2.setPathEffect(new DashPathEffect(new float[]{10.0f, 5.0f}, 0.0f));
        this.f95483m = paint2;
        Paint paint3 = new Paint();
        paint3.setStyle(style);
        paint3.setAntiAlias(true);
        paint3.setStrokeWidth(2.0f);
        paint3.setColor(Color.parseColor("#80FAAD14"));
        paint3.setPathEffect(new DashPathEffect(new float[]{10.0f, 5.0f}, 0.0f));
        this.f95485n = paint3;
        Paint paint4 = new Paint();
        Paint.Style style2 = Paint.Style.FILL;
        paint4.setStyle(style2);
        paint4.setAntiAlias(true);
        paint4.setColor(Color.parseColor("#FAAD14"));
        Paint paint5 = new Paint();
        paint5.setStyle(style2);
        paint5.setAntiAlias(true);
        paint5.setColor(Color.parseColor("#E89611"));
        Paint paint6 = new Paint();
        paint6.setStyle(style);
        paint6.setAntiAlias(true);
        paint6.setStrokeWidth(2.0f);
        paint6.setColor(-1);
        Paint paint7 = new Paint();
        paint7.setStyle(style2);
        paint7.setAntiAlias(true);
        paint7.setColor(-1);
        paint7.setShadowLayer(12.0f, 0.0f, 4.0f, Color.parseColor("#33000000"));
        this.f95487o = paint7;
        Paint paintA = kk.c.a(true);
        paintA.setColor(Color.parseColor("#333333"));
        paintA.setTextSize(24.0f);
        Paint.Align align = Paint.Align.CENTER;
        paintA.setTextAlign(align);
        this.f95489p = paintA;
        this.f95491q = new Path();
        this.f95493r = 19.0f;
        this.f95497v = 8.0f;
        this.f95498w = 16.0f;
        this.f95499x = 20.0f;
        this.f95501z = new nk.r();
        this.f95444A = true;
        this.f95445B = true;
        this.f95446C = new Handler(Looper.getMainLooper());
        this.f95447D = new RunnableC7390o(this);
        this.f95448E = CoroutineLiveDataKt.DEFAULT_TIMEOUT;
        this.f95449F = new Handler(Looper.getMainLooper());
        this.f95450G = new RunnableC7391p(this);
        this.f95451H = CoroutineLiveDataKt.DEFAULT_TIMEOUT;
        this.f95452I = new Handler(Looper.getMainLooper());
        this.f95453J = new RunnableC7392q(this);
        this.f95454K = 2000L;
        this.f95455L = new Handler(Looper.getMainLooper());
        this.f95456M = new r(this);
        this.f95457N = 100L;
        this.f95461R = 1.0f;
        this.f95463T = 1L;
        this.f95472c0 = "";
        this.f95473d0 = new RectF();
        Paint paint8 = new Paint();
        paint8.setStyle(style2);
        paint8.setAntiAlias(true);
        paint8.setColor(-1);
        this.f95477h0 = paint8;
        Paint paint9 = new Paint();
        paint9.setStyle(style2);
        paint9.setAntiAlias(true);
        paint9.setColor(Color.parseColor("#0FFAAD14"));
        this.f95478i0 = paint9;
        Paint paintA2 = kk.c.a(true);
        paintA2.setColor(Color.parseColor("#FAAD14"));
        paintA2.setTextSize(24.0f);
        paintA2.setTextAlign(align);
        this.f95479j0 = paintA2;
        this.f95480k0 = 12.0f;
        this.f95482l0 = 6.0f;
    }

    public static final void D(C7393s c7393s) {
        y1 y1Var = c7393s.f95488o0;
        if (y1Var == null) {
            return;
        }
        if (!c7393s.f95444A) {
            y1Var.Y(false);
            y1Var.W(-1.0f);
            y1Var.X(-1.0f);
            c7393s.i().e().x();
            return;
        }
        y1Var.Y(false);
        y1Var.W(-1.0f);
        y1Var.X(-1.0f);
        c7393s.i().e().x();
        c7393s.f95455L.removeCallbacks(c7393s.f95456M);
        c7393s.f95455L.postDelayed(c7393s.f95456M, c7393s.f95457N);
    }

    public static final void F(C7393s c7393s) {
        y1 y1Var = c7393s.f95488o0;
        if (y1Var == null) {
            return;
        }
        y1Var.Y(true);
        y1Var.W(-1.0f);
        y1Var.X(-1.0f);
        c7393s.i().e().x();
    }

    public static final void G(C7393s c7393s) {
        if (c7393s.f95467X) {
            c7393s.f95449F.removeCallbacks(c7393s.f95450G);
            c7393s.f95467X = false;
            c7393s.f95468Y = null;
            c7393s.f95469Z = 0.0f;
            c7393s.i().e().x();
        }
    }

    public static final void x(C7393s c7393s) {
        if (c7393s.f95500y == null || c7393s.f95458O) {
            return;
        }
        c7393s.f95500y = null;
        c7393s.f95460Q = null;
        c7393s.f95465V = null;
        c7393s.f95462S = 0L;
        c7393s.f95466W = false;
        c7393s.f95474e0 = false;
        c7393s.f95475f0 = 0.0f;
        c7393s.f95476g0 = 0.0d;
        c7393s.f95484m0 = 0.0f;
        c7393s.w();
        c7393s.i().e().x();
    }

    public static void y(nk.r.b bVar, AlertLineItem alertLineItem, float f10, float f11, float f12) {
        float f13;
        float f14;
        nk.q qVarA = nk.q.f134234e.a();
        if (AbstractC7609s.f(MessageKey.CUSTOM_LAYOUT_RIGHT_ICON, MessageKey.CUSTOM_LAYOUT_RIGHT_ICON)) {
            f13 = (f10 - f12) - 10.0f;
        } else {
            f13 = AbstractC7609s.f(MessageKey.CUSTOM_LAYOUT_RIGHT_ICON, "delete_icon") ? (f10 - f12) - 15.0f : f10 - f12;
        }
        if (AbstractC7609s.f(MessageKey.CUSTOM_LAYOUT_RIGHT_ICON, MessageKey.CUSTOM_LAYOUT_RIGHT_ICON)) {
            f14 = f10 + f12 + 35.0f;
        } else {
            f14 = f10 + f12;
            if (AbstractC7609s.f(MessageKey.CUSTOM_LAYOUT_RIGHT_ICON, "delete_icon")) {
                f14 += 15.0f;
            }
        }
        float f15 = AbstractC7609s.f(MessageKey.CUSTOM_LAYOUT_RIGHT_ICON, MessageKey.CUSTOM_LAYOUT_RIGHT_ICON) ? (f11 - f12) - 15.0f : f11 - f12;
        float f16 = f11 + f12;
        if (AbstractC7609s.f(MessageKey.CUSTOM_LAYOUT_RIGHT_ICON, MessageKey.CUSTOM_LAYOUT_RIGHT_ICON)) {
            f16 += 15.0f;
        }
        qVarA.g(f13, f15, f14, f16);
        qVarA.i(f13, f15, f14, f16);
        qVarA.j(new Qf.p(alertLineItem, MessageKey.CUSTOM_LAYOUT_RIGHT_ICON));
        bVar.e(qVarA);
    }

    /* JADX WARN: Code duplicated, block: B:12:0x0043  */
    public final void A(AlertLineItem alertLineItem, float f10) {
        Double dN;
        this.f95460Q = alertLineItem;
        this.f95459P = f10;
        this.f95458O = false;
        this.f95464U = false;
        this.f95466W = false;
        this.f95462S = System.currentTimeMillis();
        KLineManager.a aVar = KLineManager.f142490O;
        if (!AbstractC7609s.f(aVar.a().A(), "cny") || aVar.a().Q()) {
            String mode_info = alertLineItem.getMode_info();
            if (mode_info != null) {
                dN = Ah.v.n(mode_info);
            } else {
                dN = null;
            }
        } else {
            String mode_info_cmp = alertLineItem.getMode_info_cmp();
            if (mode_info_cmp != null) {
                dN = Ah.v.n(mode_info_cmp);
            } else {
                dN = null;
            }
        }
        this.f95465V = dN;
        this.f95474e0 = false;
        this.f95475f0 = 0.0f;
        this.f95476g0 = 0.0d;
        this.f95484m0 = 0.0f;
        y1 y1Var = this.f95488o0;
        if (y1Var != null) {
            this.f95452I.removeCallbacks(this.f95453J);
            this.f95455L.removeCallbacks(this.f95456M);
            this.f95444A = y1Var.E();
            y1Var.Y(false);
            y1Var.W(-1.0f);
            y1Var.X(-1.0f);
            E();
        }
        if (this.f95500y != null) {
            E();
        }
    }

    /* JADX WARN: Code duplicated, block: B:55:0x00e9  */
    /* JADX WARN: Code duplicated, block: B:58:0x00f3  */
    /* JADX WARN: Code duplicated, block: B:62:0x00fc  */
    public final boolean B(AlertLineItem alertLineItem, String str, int i10) {
        Double dN;
        double dDoubleValue;
        Double dN2;
        double dDoubleValue2;
        String set_price;
        double dDoubleValue3;
        String frequency;
        y1 y1Var;
        Double dN3;
        Double dN4;
        Double dN5;
        String str2 = this.f95500y;
        if (str2 == null) {
            AbstractC2759w0 abstractC2759w0 = this.f95490p0;
            if (abstractC2759w0 == null) {
                return false;
            }
            KLineManager.a aVar = KLineManager.f142490O;
            if (!AbstractC7609s.f(aVar.a().A(), "cny") || aVar.a().Q()) {
                String mode_info = alertLineItem.getMode_info();
                if (mode_info == null || (dN = Ah.v.n(mode_info)) == null) {
                    return false;
                }
                dDoubleValue = dN.doubleValue();
            } else {
                String mode_info_cmp = alertLineItem.getMode_info_cmp();
                if (mode_info_cmp == null || (dN5 = Ah.v.n(mode_info_cmp)) == null) {
                    return false;
                }
                dDoubleValue = dN5.doubleValue();
            }
            if (dDoubleValue <= abstractC2759w0.u() && dDoubleValue >= abstractC2759w0.v()) {
                float fP = abstractC2759w0.P(dDoubleValue);
                if (!AbstractC7609s.f(str, MessageKey.CUSTOM_LAYOUT_RIGHT_ICON)) {
                    if (AbstractC7609s.f(this.f95468Y, alertLineItem.getId()) && this.f95467X) {
                        C();
                    } else {
                        C();
                        if (!AbstractC7609s.f(aVar.a().A(), "cny") || aVar.a().Q()) {
                            String mode_info2 = alertLineItem.getMode_info();
                            if (mode_info2 != null && (dN2 = Ah.v.n(mode_info2)) != null) {
                                dDoubleValue2 = dN2.doubleValue();
                                this.f95467X = true;
                                this.f95468Y = alertLineItem.getId();
                                this.f95469Z = fP;
                                this.f95471b0 = dDoubleValue2;
                                set_price = alertLineItem.getSet_price();
                                if (set_price != null || (dN3 = Ah.v.n(set_price)) == null) {
                                    dDoubleValue3 = 0.0d;
                                } else {
                                    dDoubleValue3 = dN3.doubleValue();
                                }
                                this.f95470a0 = dDoubleValue3;
                                frequency = alertLineItem.getFrequency();
                                if (frequency == null) {
                                    frequency = "";
                                }
                                this.f95472c0 = frequency;
                                y1Var = this.f95488o0;
                                if (y1Var != null) {
                                    this.f95452I.removeCallbacks(this.f95453J);
                                    this.f95455L.removeCallbacks(this.f95456M);
                                    this.f95445B = y1Var.E();
                                    y1Var.Y(false);
                                    y1Var.W(-1.0f);
                                    y1Var.X(-1.0f);
                                }
                                this.f95449F.removeCallbacks(this.f95450G);
                                this.f95449F.postDelayed(this.f95450G, this.f95451H);
                            }
                        } else {
                            String mode_info_cmp2 = alertLineItem.getMode_info_cmp();
                            if (mode_info_cmp2 != null && (dN4 = Ah.v.n(mode_info_cmp2)) != null) {
                                dDoubleValue2 = dN4.doubleValue();
                                this.f95467X = true;
                                this.f95468Y = alertLineItem.getId();
                                this.f95469Z = fP;
                                this.f95471b0 = dDoubleValue2;
                                set_price = alertLineItem.getSet_price();
                                if (set_price != null) {
                                    dDoubleValue3 = 0.0d;
                                } else {
                                    dDoubleValue3 = 0.0d;
                                }
                                this.f95470a0 = dDoubleValue3;
                                frequency = alertLineItem.getFrequency();
                                if (frequency == null) {
                                    frequency = "";
                                }
                                this.f95472c0 = frequency;
                                y1Var = this.f95488o0;
                                if (y1Var != null) {
                                    this.f95452I.removeCallbacks(this.f95453J);
                                    this.f95455L.removeCallbacks(this.f95456M);
                                    this.f95445B = y1Var.E();
                                    y1Var.Y(false);
                                    y1Var.W(-1.0f);
                                    y1Var.X(-1.0f);
                                }
                                this.f95449F.removeCallbacks(this.f95450G);
                                this.f95449F.postDelayed(this.f95450G, this.f95451H);
                            }
                        }
                    }
                    i().e().x();
                    return true;
                }
                this.f95500y = alertLineItem.getId();
                A(alertLineItem, i10);
                C();
                if (this.f95500y != null) {
                    E();
                }
            }
        } else if (AbstractC7609s.f(str2, alertLineItem.getId())) {
            A(alertLineItem, i10);
        } else {
            this.f95500y = alertLineItem.getId();
            L();
            this.f95460Q = alertLineItem;
            A(alertLineItem, i10);
        }
        i().e().x();
        return true;
    }

    public final void C() {
        y1 y1Var;
        boolean z10 = this.f95467X;
        this.f95449F.removeCallbacks(this.f95450G);
        this.f95467X = false;
        this.f95468Y = null;
        this.f95469Z = 0.0f;
        if (z10 && this.f95500y == null && (y1Var = this.f95488o0) != null) {
            y1Var.Y(this.f95445B);
            if (this.f95445B) {
                y1Var.W(-1.0f);
                y1Var.X(-1.0f);
            }
        }
    }

    public final void E() {
        this.f95446C.removeCallbacks(this.f95447D);
        this.f95446C.postDelayed(this.f95447D, this.f95448E);
    }

    public final AlertLineItem H() {
        return this.f95460Q;
    }

    public final boolean I() {
        if (this.f95500y != null && this.f95460Q != null && !this.f95458O) {
            this.f95462S = 0L;
            this.f95464U = false;
            this.f95466W = false;
            this.f95474e0 = false;
            this.f95475f0 = 0.0f;
            this.f95476g0 = 0.0d;
            this.f95484m0 = 0.0f;
            E();
        }
        return false;
    }

    public final boolean J() {
        return this.f95458O;
    }

    /* JADX WARN: Code duplicated, block: B:44:0x00a7  */
    public final boolean K(float f10) {
        double dR;
        String mode_info;
        Double dN;
        String mode_info_cmp;
        Double dN2;
        if (this.f95460Q != null && !this.f95458O) {
            float fAbs = Math.abs(f10 - this.f95459P);
            long jCurrentTimeMillis = System.currentTimeMillis() - this.f95462S;
            if (fAbs >= this.f95461R || jCurrentTimeMillis >= this.f95463T) {
                if (!this.f95464U) {
                    this.f95464U = true;
                }
                this.f95458O = true;
                this.f95466W = true;
                y1 y1Var = this.f95488o0;
                if (y1Var != null && y1Var.E()) {
                    y1Var.Y(false);
                }
                this.f95446C.removeCallbacks(this.f95447D);
                this.f95474e0 = true;
                this.f95475f0 = f10;
                AbstractC2759w0 abstractC2759w0 = this.f95490p0;
                KLineManager.a aVar = KLineManager.f142490O;
                if (!AbstractC7609s.f(aVar.a().A(), "cny") || aVar.a().Q()) {
                    AlertLineItem alertLineItem = this.f95460Q;
                    if (alertLineItem != null && (mode_info = alertLineItem.getMode_info()) != null && (dN = Ah.v.n(mode_info)) != null) {
                        dR = dN.doubleValue();
                    } else if (abstractC2759w0 != null) {
                        dR = abstractC2759w0.R(f10);
                    } else {
                        dR = 0.0d;
                    }
                } else {
                    AlertLineItem alertLineItem2 = this.f95460Q;
                    if (alertLineItem2 != null && (mode_info_cmp = alertLineItem2.getMode_info_cmp()) != null && (dN2 = Ah.v.n(mode_info_cmp)) != null) {
                        dR = dN2.doubleValue();
                    } else if (abstractC2759w0 != null) {
                        dR = abstractC2759w0.R(f10);
                    } else {
                        dR = 0.0d;
                    }
                }
                this.f95476g0 = dR;
                String strB = nk.A.b(dR, aVar.a().j());
                Rect rect = new Rect();
                this.f95479j0.getTextBounds(strB, 0, strB.length(), rect);
                this.f95484m0 = Math.max((this.f95480k0 * 2) + rect.width(), Xj.a.b(80));
                return true;
            }
            if (this.f95500y != null) {
                E();
            }
        }
        return false;
    }

    /* JADX WARN: Code duplicated, block: B:28:0x0068  */
    public final void L() {
        AlertLineItem alertLineItem;
        Double dN;
        boolean z10 = Math.abs(this.f95475f0 - this.f95459P) >= this.f95461R || System.currentTimeMillis() - this.f95462S >= this.f95463T;
        if (this.f95458O && (alertLineItem = this.f95460Q) != null && this.f95464U && this.f95466W && z10) {
            KLineManager.a aVar = KLineManager.f142490O;
            if (!AbstractC7609s.f(aVar.a().A(), "cny") || aVar.a().Q()) {
                String mode_info = alertLineItem.getMode_info();
                if (mode_info != null) {
                    dN = Ah.v.n(mode_info);
                } else {
                    dN = null;
                }
            } else {
                String mode_info_cmp = alertLineItem.getMode_info_cmp();
                if (mode_info_cmp != null) {
                    dN = Ah.v.n(mode_info_cmp);
                } else {
                    dN = null;
                }
            }
            boolean zD = AbstractC7609s.d(this.f95465V, dN);
            if (zD) {
                this.f95500y = null;
                this.f95460Q = null;
                w();
            } else {
                C2738p.f19487a.d(alertLineItem);
                this.f95500y = null;
                this.f95460Q = null;
                this.f95465V = null;
                this.f95462S = 0L;
                this.f95466W = false;
                w();
            }
            if (zD && this.f95500y != null) {
                E();
            }
        } else if (this.f95460Q != null && this.f95500y != null) {
            E();
        }
        this.f95458O = false;
        this.f95459P = 0.0f;
        this.f95462S = 0L;
        this.f95464U = false;
        this.f95466W = false;
        this.f95465V = null;
        this.f95474e0 = false;
        this.f95475f0 = 0.0f;
        this.f95476g0 = 0.0d;
        this.f95484m0 = 0.0f;
        C();
        i().e().x();
    }

    public final void M(float f10) {
        if (this.f95458O && this.f95460Q != null && this.f95464U && this.f95466W) {
            long jCurrentTimeMillis = System.currentTimeMillis() - this.f95462S;
            if (Math.abs(f10 - this.f95459P) >= this.f95461R || jCurrentTimeMillis >= this.f95463T) {
                y1 y1Var = this.f95488o0;
                if (y1Var != null) {
                    if (y1Var.E()) {
                        y1Var.Y(false);
                    }
                    y1Var.W(-1.0f);
                    y1Var.X(-1.0f);
                }
                AbstractC2759w0 abstractC2759w0 = this.f95490p0;
                if (abstractC2759w0 == null) {
                    return;
                }
                double dR = abstractC2759w0.R(f10);
                if (dR > abstractC2759w0.u()) {
                    dR = abstractC2759w0.u();
                } else if (dR < abstractC2759w0.v()) {
                    dR = abstractC2759w0.v();
                }
                this.f95474e0 = true;
                this.f95475f0 = f10;
                this.f95476g0 = dR;
                AlertLineItem alertLineItem = this.f95460Q;
                try {
                    KLineManager.a aVar = KLineManager.f142490O;
                    if (!AbstractC7609s.f(aVar.a().A(), "cny") || aVar.a().Q()) {
                        Field declaredField = AlertLineItem.class.getDeclaredField("mode_info");
                        declaredField.setAccessible(true);
                        declaredField.set(alertLineItem, String.valueOf(dR));
                    } else {
                        String mode_info_cmp = alertLineItem.getMode_info_cmp();
                        Double dN = mode_info_cmp != null ? Ah.v.n(mode_info_cmp) : null;
                        String mode_info = alertLineItem.getMode_info();
                        Double dN2 = mode_info != null ? Ah.v.n(mode_info) : null;
                        double dDoubleValue = (dN == null || dN2 == null || dN.doubleValue() <= 0.0d) ? dR : (dN2.doubleValue() / dN.doubleValue()) * dR;
                        Field declaredField2 = AlertLineItem.class.getDeclaredField("mode_info");
                        declaredField2.setAccessible(true);
                        declaredField2.set(alertLineItem, String.valueOf(dDoubleValue));
                        Field declaredField3 = AlertLineItem.class.getDeclaredField("mode_info_cmp");
                        declaredField3.setAccessible(true);
                        declaredField3.set(alertLineItem, String.valueOf(dR));
                    }
                } catch (Exception unused) {
                }
                i().e().x();
            }
        }
    }

    /* JADX WARN: Code duplicated, block: B:147:0x0205 A[SYNTHETIC] */
    /* JADX WARN: Code duplicated, block: B:148:0x01ed A[SYNTHETIC] */
    /* JADX WARN: Code duplicated, block: B:149:0x01e6 A[SYNTHETIC] */
    /* JADX WARN: Code duplicated, block: B:76:0x0148  */
    /* JADX WARN: Code duplicated, block: B:78:0x015b  */
    /* JADX WARN: Code duplicated, block: B:81:0x018b  */
    /* JADX WARN: Code duplicated, block: B:87:0x01f3  */
    /* JADX WARN: Code duplicated, block: B:93:0x0236  */
    /* JADX WARN: Code duplicated, block: B:99:0x0247  */
    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        AbstractC2759w0 abstractC2759w0;
        C7495w c7495w;
        C2702d c2702dE;
        y1 y1Var;
        String string;
        Double dN;
        double dDoubleValue;
        float f10;
        Paint paint;
        float fU;
        float f11;
        float f12;
        float fY;
        AbstractC2759w0 abstractC2759w1;
        byte b10;
        String str;
        Bitmap bitmap;
        Bitmap bitmap2;
        y1 y1Var2;
        Double dN2;
        if (!KLineManager.f142490O.a().W() || (abstractC2759w0 = this.f95490p0) == null || (c7495w = this.f95492q0) == null || (c2702dE = i().b().e(b())) == null) {
            return;
        }
        List<AlertLineItem> listR1 = Sf.z.r1(c7495w.s());
        if (this.f95500y != null) {
            y1 y1Var3 = this.f95488o0;
            if (y1Var3 != null) {
                if (y1Var3.E()) {
                    y1Var3.Y(false);
                }
                y1Var3.W(-1.0f);
                y1Var3.X(-1.0f);
            }
        } else if (this.f95467X && (y1Var = this.f95488o0) != null) {
            if (y1Var.E()) {
                y1Var.Y(false);
            }
            y1Var.W(-1.0f);
            y1Var.X(-1.0f);
        }
        nk.r.b bVarC = this.f95501z.c();
        bVarC.d();
        for (AlertLineItem alertLineItem : listR1) {
            KLineManager.a aVar = KLineManager.f142490O;
            if (!AbstractC7609s.f(aVar.a().A(), "cny") || aVar.a().Q()) {
                String mode_info = alertLineItem.getMode_info();
                if (mode_info != null && (dN = Ah.v.n(mode_info)) != null) {
                    dDoubleValue = dN.doubleValue();
                    if (dDoubleValue > abstractC2759w0.u() && dDoubleValue >= abstractC2759w0.v()) {
                        float fP = abstractC2759w0.P(dDoubleValue);
                        if (AbstractC7609s.f(this.f95500y, alertLineItem.getId())) {
                            f10 = 10.0f;
                        } else {
                            if (this.f95458O) {
                                AlertLineItem alertLineItem2 = this.f95460Q;
                                f10 = 10.0f;
                                if (AbstractC7609s.f(alertLineItem2 != null ? alertLineItem2.getId() : null, alertLineItem.getId())) {
                                }
                                fU = c2702dE.u() + 35.0f;
                                f11 = this.f95493r * 2.0f;
                                f12 = 2;
                                fY = (c2702dE.y() - 2.0f) - (this.f95493r / f12);
                                if (AbstractC7609s.f(this.f95500y, alertLineItem.getId())) {
                                    float f13 = f11 / f12;
                                    float f14 = fU + f13;
                                    abstractC2759w1 = abstractC2759w0;
                                    RectF rectF = new RectF(fU - f13, fP - f13, f14, fP + f13);
                                    bitmap = this.f95496u;
                                    if (bitmap == null) {
                                        bitmap = null;
                                    }
                                    canvas.drawBitmap(bitmap, (Rect) null, rectF, (Paint) null);
                                    Path path = this.f95491q;
                                    path.reset();
                                    path.moveTo(f14 + 5.0f, fP);
                                    path.lineTo(c2702dE.y(), fP);
                                    canvas.drawPath(this.f95491q, paint);
                                    float f15 = this.f95493r / f12;
                                    RectF rectF2 = new RectF(fY - f15, fP - f15, f15 + fY, f15 + fP);
                                    bitmap2 = this.f95494s;
                                    if (bitmap2 == null) {
                                        bitmap2 = null;
                                    }
                                    canvas.drawBitmap(bitmap2, (Rect) null, rectF2, (Paint) null);
                                    float f16 = (fY - ((this.f95493r / f12) + 30.0f)) - f10;
                                    nk.q.a aVar2 = nk.q.f134234e;
                                    nk.q qVarA = aVar2.a();
                                    float fMax = Math.max(f16, 255.0f);
                                    float f17 = fP - 40.0f;
                                    float f18 = fP + 40.0f;
                                    qVarA.g(205.0f, f17, fMax, f18);
                                    qVarA.i(205.0f, f17, fMax, f18);
                                    qVarA.j(alertLineItem);
                                    bVarC.e(qVarA);
                                    y(bVarC, alertLineItem, fY, fP, (this.f95493r / f12) + 30.0f);
                                    nk.q qVarA2 = aVar2.a();
                                    float f19 = f13 + 60.0f;
                                    float f20 = (fP - f19) - 25.0f;
                                    float f21 = fP + f19 + 25.0f;
                                    qVarA2.g(0.0f, f20, 200.0f, f21);
                                    qVarA2.i(0.0f, f20, 200.0f, f21);
                                    qVarA2.j(new Qf.p(alertLineItem, "delete_icon_priority"));
                                    bVarC.e(qVarA2);
                                    y1Var2 = this.f95488o0;
                                    if (y1Var2 == null) {
                                        abstractC2759w0 = abstractC2759w1;
                                    } else {
                                        if (y1Var2.E()) {
                                            y1Var2.Y(false);
                                        }
                                        b10 = -1082130432;
                                        y1Var2.W(-1.0f);
                                        y1Var2.X(-1.0f);
                                    }
                                } else {
                                    abstractC2759w1 = abstractC2759w0;
                                    b10 = -1082130432;
                                    Path path2 = this.f95491q;
                                    path2.reset();
                                    path2.moveTo(c2702dE.u(), fP);
                                    path2.lineTo(c2702dE.y(), fP);
                                    canvas.drawPath(this.f95491q, paint);
                                    float f22 = this.f95493r / f12;
                                    RectF rectF3 = new RectF(fY - f22, fP - f22, f22 + fY, f22 + fP);
                                    str = this.f95500y;
                                    if (str != null || AbstractC7609s.f(str, alertLineItem.getId()) ? (bitmap = this.f95494s) == null : (bitmap = this.f95495t) == null) {
                                    }
                                    canvas.drawBitmap(bitmap, (Rect) null, rectF3, (Paint) null);
                                    float f23 = (fY - ((this.f95493r / f12) + 30.0f)) - 60.0f;
                                    nk.q qVarA3 = nk.q.f134234e.a();
                                    float fMax2 = Math.max(f23, 255.0f);
                                    float f24 = fP - 40.0f;
                                    float f25 = fP + 40.0f;
                                    qVarA3.g(205.0f, f24, fMax2, f25);
                                    qVarA3.i(205.0f, f24, fMax2, f25);
                                    qVarA3.j(alertLineItem);
                                    bVarC.e(qVarA3);
                                    y(bVarC, alertLineItem, fY, fP, (this.f95493r / f12) + 30.0f);
                                }
                                abstractC2759w0 = abstractC2759w1;
                            } else {
                                f10 = 10.0f;
                            }
                            String str2 = this.f95500y;
                            paint = (str2 == null || AbstractC7609s.f(str2, alertLineItem.getId())) ? this.f95481l : this.f95485n;
                            fU = c2702dE.u() + 35.0f;
                            f11 = this.f95493r * 2.0f;
                            f12 = 2;
                            fY = (c2702dE.y() - 2.0f) - (this.f95493r / f12);
                            if (AbstractC7609s.f(this.f95500y, alertLineItem.getId())) {
                                float f110 = f11 / f12;
                                float f111 = fU + f110;
                                abstractC2759w1 = abstractC2759w0;
                                RectF rectF4 = new RectF(fU - f110, fP - f110, f111, fP + f110);
                                bitmap = this.f95496u;
                                if (bitmap == null) {
                                    bitmap = null;
                                }
                                canvas.drawBitmap(bitmap, (Rect) null, rectF4, (Paint) null);
                                Path path3 = this.f95491q;
                                path3.reset();
                                path3.moveTo(f111 + 5.0f, fP);
                                path3.lineTo(c2702dE.y(), fP);
                                canvas.drawPath(this.f95491q, paint);
                                float f112 = this.f95493r / f12;
                                RectF rectF5 = new RectF(fY - f112, fP - f112, f112 + fY, f112 + fP);
                                bitmap2 = this.f95494s;
                                if (bitmap2 == null) {
                                    bitmap2 = null;
                                }
                                canvas.drawBitmap(bitmap2, (Rect) null, rectF5, (Paint) null);
                                float f113 = (fY - ((this.f95493r / f12) + 30.0f)) - f10;
                                nk.q.a aVar3 = nk.q.f134234e;
                                nk.q qVarA4 = aVar3.a();
                                float fMax3 = Math.max(f113, 255.0f);
                                float f114 = fP - 40.0f;
                                float f115 = fP + 40.0f;
                                qVarA4.g(205.0f, f114, fMax3, f115);
                                qVarA4.i(205.0f, f114, fMax3, f115);
                                qVarA4.j(alertLineItem);
                                bVarC.e(qVarA4);
                                y(bVarC, alertLineItem, fY, fP, (this.f95493r / f12) + 30.0f);
                                nk.q qVarA5 = aVar3.a();
                                float f116 = f110 + 60.0f;
                                float f26 = (fP - f116) - 25.0f;
                                float f27 = fP + f116 + 25.0f;
                                qVarA5.g(0.0f, f26, 200.0f, f27);
                                qVarA5.i(0.0f, f26, 200.0f, f27);
                                qVarA5.j(new Qf.p(alertLineItem, "delete_icon_priority"));
                                bVarC.e(qVarA5);
                                y1Var2 = this.f95488o0;
                                if (y1Var2 == null) {
                                    abstractC2759w0 = abstractC2759w1;
                                } else {
                                    if (y1Var2.E()) {
                                        y1Var2.Y(false);
                                    }
                                    b10 = -1082130432;
                                    y1Var2.W(-1.0f);
                                    y1Var2.X(-1.0f);
                                }
                            } else {
                                abstractC2759w1 = abstractC2759w0;
                                b10 = -1082130432;
                                Path path4 = this.f95491q;
                                path4.reset();
                                path4.moveTo(c2702dE.u(), fP);
                                path4.lineTo(c2702dE.y(), fP);
                                canvas.drawPath(this.f95491q, paint);
                                float f28 = this.f95493r / f12;
                                RectF rectF6 = new RectF(fY - f28, fP - f28, f28 + fY, f28 + fP);
                                str = this.f95500y;
                                Bitmap bitmap3 = str != null ? null : null;
                                canvas.drawBitmap(bitmap3, (Rect) null, rectF6, (Paint) null);
                                float f29 = (fY - ((this.f95493r / f12) + 30.0f)) - 60.0f;
                                nk.q qVarA6 = nk.q.f134234e.a();
                                float fMax4 = Math.max(f29, 255.0f);
                                float f210 = fP - 40.0f;
                                float f211 = fP + 40.0f;
                                qVarA6.g(205.0f, f210, fMax4, f211);
                                qVarA6.i(205.0f, f210, fMax4, f211);
                                qVarA6.j(alertLineItem);
                                bVarC.e(qVarA6);
                                y(bVarC, alertLineItem, fY, fP, (this.f95493r / f12) + 30.0f);
                            }
                            abstractC2759w0 = abstractC2759w1;
                        }
                        paint = this.f95483m;
                        fU = c2702dE.u() + 35.0f;
                        f11 = this.f95493r * 2.0f;
                        f12 = 2;
                        fY = (c2702dE.y() - 2.0f) - (this.f95493r / f12);
                        if (AbstractC7609s.f(this.f95500y, alertLineItem.getId())) {
                            float f117 = f11 / f12;
                            float f118 = fU + f117;
                            abstractC2759w1 = abstractC2759w0;
                            RectF rectF7 = new RectF(fU - f117, fP - f117, f118, fP + f117);
                            bitmap = this.f95496u;
                            if (bitmap == null) {
                                bitmap = null;
                            }
                            canvas.drawBitmap(bitmap, (Rect) null, rectF7, (Paint) null);
                            Path path5 = this.f95491q;
                            path5.reset();
                            path5.moveTo(f118 + 5.0f, fP);
                            path5.lineTo(c2702dE.y(), fP);
                            canvas.drawPath(this.f95491q, paint);
                            float f119 = this.f95493r / f12;
                            RectF rectF8 = new RectF(fY - f119, fP - f119, f119 + fY, f119 + fP);
                            bitmap2 = this.f95494s;
                            if (bitmap2 == null) {
                                bitmap2 = null;
                            }
                            canvas.drawBitmap(bitmap2, (Rect) null, rectF8, (Paint) null);
                            float f1110 = (fY - ((this.f95493r / f12) + 30.0f)) - f10;
                            nk.q.a aVar4 = nk.q.f134234e;
                            nk.q qVarA7 = aVar4.a();
                            float fMax5 = Math.max(f1110, 255.0f);
                            float f1111 = fP - 40.0f;
                            float f1112 = fP + 40.0f;
                            qVarA7.g(205.0f, f1111, fMax5, f1112);
                            qVarA7.i(205.0f, f1111, fMax5, f1112);
                            qVarA7.j(alertLineItem);
                            bVarC.e(qVarA7);
                            y(bVarC, alertLineItem, fY, fP, (this.f95493r / f12) + 30.0f);
                            nk.q qVarA8 = aVar4.a();
                            float f1113 = f117 + 60.0f;
                            float f212 = (fP - f1113) - 25.0f;
                            float f213 = fP + f1113 + 25.0f;
                            qVarA8.g(0.0f, f212, 200.0f, f213);
                            qVarA8.i(0.0f, f212, 200.0f, f213);
                            qVarA8.j(new Qf.p(alertLineItem, "delete_icon_priority"));
                            bVarC.e(qVarA8);
                            y1Var2 = this.f95488o0;
                            if (y1Var2 == null) {
                                abstractC2759w0 = abstractC2759w1;
                            } else {
                                if (y1Var2.E()) {
                                    y1Var2.Y(false);
                                }
                                b10 = -1082130432;
                                y1Var2.W(-1.0f);
                                y1Var2.X(-1.0f);
                            }
                        } else {
                            abstractC2759w1 = abstractC2759w0;
                            b10 = -1082130432;
                            Path path6 = this.f95491q;
                            path6.reset();
                            path6.moveTo(c2702dE.u(), fP);
                            path6.lineTo(c2702dE.y(), fP);
                            canvas.drawPath(this.f95491q, paint);
                            float f214 = this.f95493r / f12;
                            RectF rectF9 = new RectF(fY - f214, fP - f214, f214 + fY, f214 + fP);
                            str = this.f95500y;
                            if (str != null) {
                            }
                            canvas.drawBitmap(bitmap3, (Rect) null, rectF9, (Paint) null);
                            float f215 = (fY - ((this.f95493r / f12) + 30.0f)) - 60.0f;
                            nk.q qVarA9 = nk.q.f134234e.a();
                            float fMax6 = Math.max(f215, 255.0f);
                            float f216 = fP - 40.0f;
                            float f217 = fP + 40.0f;
                            qVarA9.g(205.0f, f216, fMax6, f217);
                            qVarA9.i(205.0f, f216, fMax6, f217);
                            qVarA9.j(alertLineItem);
                            bVarC.e(qVarA9);
                            y(bVarC, alertLineItem, fY, fP, (this.f95493r / f12) + 30.0f);
                        }
                        abstractC2759w0 = abstractC2759w1;
                    }
                }
            } else {
                String mode_info_cmp = alertLineItem.getMode_info_cmp();
                if (mode_info_cmp != null && (dN2 = Ah.v.n(mode_info_cmp)) != null) {
                    dDoubleValue = dN2.doubleValue();
                    if (dDoubleValue > abstractC2759w0.u()) {
                    }
                }
            }
        }
        bVarC.b();
        if (this.f95474e0 && this.f95458O) {
            C2702d c2702dE2 = i().b().e(b() + "Range");
            if (c2702dE2 != null) {
                String strB = nk.A.b(this.f95476g0, KLineManager.f142490O.a().j());
                Rect rect = new Rect();
                this.f95479j0.getTextBounds(strB, 0, strB.length(), rect);
                float fHeight = rect.height();
                float fB = this.f95484m0;
                if (fB <= 0.0f) {
                    fB = Xj.a.b(80);
                }
                float f30 = 2;
                float f31 = (this.f95480k0 * f30) + fHeight;
                float fU2 = c2702dE2.u() + 4.0f;
                float fY2 = c2702dE2.y() - 4.0f;
                float f32 = (fU2 + fY2) / 2.0f;
                float f33 = fB / 2.0f;
                float fMax7 = Math.max(f32 - f33, fU2);
                float fMin = Math.min(f32 + f33, fY2);
                float f34 = this.f95475f0 - (f31 / 2.0f);
                float f35 = f34 + f31;
                float fMax8 = Math.max(f34, c2702dE2.z() + 4.0f);
                float fMin2 = Math.min(f35, c2702dE2.p() - 4.0f);
                if (fMin2 - fMax8 < f31) {
                    fMax8 = fMin2 - f31;
                }
                RectF rectF10 = new RectF(fMax7, fMax8, fMin, f31 + fMax8);
                float f36 = this.f95482l0;
                canvas.drawRoundRect(rectF10, f36, f36, this.f95477h0);
                float f37 = this.f95482l0;
                canvas.drawRoundRect(rectF10, f37, f37, this.f95478i0);
                canvas.drawText(strB, rectF10.centerX(), ((this.f95479j0.getTextSize() / f30) - this.f95479j0.descent()) + rectF10.centerY(), this.f95479j0);
            }
        }
        Resources resources = i().c().getResources();
        if (this.f95467X) {
            if (AbstractC7609s.f("always", this.f95472c0)) {
                string = resources.getString(R.string.kline_alert_line_frency_always);
            } else if (AbstractC7609s.f("day", this.f95472c0)) {
                string = resources.getString(R.string.kline_alert_line_frency_day);
            } else {
                string = AbstractC7609s.f("5min", this.f95472c0) ? resources.getString(R.string.kline_alert_line_frency_min) : resources.getString(R.string.kline_alert_line_frency_once);
            }
            String str3 = this.f95471b0 >= this.f95470a0 ? resources.getString(R.string.kline_alert_line_move_up) + ' ' + nk.A.b(this.f95471b0, KLineManager.f142490O.a().j()) + ',' + string : resources.getString(R.string.kline_alert_line_move_down) + ' ' + nk.A.b(this.f95471b0, KLineManager.f142490O.a().j()) + ',' + string;
            float f38 = this.f95469Z;
            Rect rect2 = new Rect();
            this.f95489p.getTextBounds(str3, 0, str3.length(), rect2);
            float fWidth = rect2.width();
            float fHeight2 = rect2.height();
            float f39 = 2;
            float f40 = this.f95498w * f39;
            float f41 = fWidth + f40;
            float f42 = f40 + fHeight2;
            float fY3 = (((c2702dE.y() - c2702dE.u()) / 2.0f) + c2702dE.u()) - (f41 / 2.0f);
            float f43 = f38 + this.f95499x;
            float fMax9 = Math.max(fY3, c2702dE.u() + 10.0f);
            float fMin3 = Math.min(f41 + fY3, c2702dE.y() - 10.0f);
            float fMin4 = Math.min(f43, (c2702dE.p() - f42) - 10.0f);
            RectF rectF11 = new RectF(fMax9, fMin4, fMin3, f42 + fMin4);
            this.f95473d0.set(rectF11);
            float f44 = this.f95497v;
            canvas.drawRoundRect(rectF11, f44, f44, this.f95487o);
            canvas.drawText(str3, rectF11.centerX(), ((this.f95489p.getTextSize() / f39) - this.f95489p.descent()) + rectF11.centerY(), this.f95489p);
        }
    }

    /* JADX WARN: Code duplicated, block: B:31:0x0065  */
    /* JADX WARN: Code duplicated, block: B:34:0x006f  */
    /* JADX WARN: Code duplicated, block: B:41:0x009d  */
    /* JADX WARN: Code duplicated, block: B:43:0x00a3  */
    /* JADX WARN: Code duplicated, block: B:44:0x00a8  */
    /* JADX WARN: Code duplicated, block: B:91:0x00cd A[SYNTHETIC] */
    @Override // Rj.AbstractC2744r0
    public boolean n(String str, int i10, int i11) {
        AlertLineItem alertLineItemV;
        AbstractC2759w0 abstractC2759w0;
        C2741q c2741q;
        C2702d c2702dE;
        Iterator it;
        AlertLineItem alertLineItem;
        KLineManager.a aVar;
        String mode_info;
        Double dN;
        Object next;
        Object objD = this.f95501z.d(i10, i11);
        if (this.f95500y != null && i10 <= 200) {
            C7495w c7495w = this.f95492q0;
            if (c7495w != null && (abstractC2759w0 = this.f95490p0) != null && (c2741q = this.f95486n0) != null && (c2702dE = c2741q.e(b())) != null) {
                List listR1 = Sf.z.r1(c7495w.s());
                String str2 = this.f95500y;
                if (str2 == null) {
                    it = listR1.iterator();
                    while (true) {
                        if (it.hasNext()) {
                            alertLineItemV = null;
                            break;
                        }
                        alertLineItem = (AlertLineItem) it.next();
                        aVar = KLineManager.f142490O;
                        if (AbstractC7609s.f(aVar.a().A(), "cny")) {
                            mode_info = alertLineItem.getMode_info();
                            if (mode_info != null) {
                                dN = Ah.v.n(mode_info);
                            } else {
                                dN = null;
                            }
                        } else {
                            mode_info = alertLineItem.getMode_info();
                            if (mode_info != null) {
                                dN = Ah.v.n(mode_info);
                            } else {
                                dN = null;
                            }
                        }
                        if (dN == null) {
                        }
                    }
                } else {
                    Iterator it2 = listR1.iterator();
                    do {
                        if (!it2.hasNext()) {
                            next = null;
                            break;
                        }
                        next = it2.next();
                    } while (!AbstractC7609s.f(((AlertLineItem) next).getId(), str2));
                    AlertLineItem alertLineItem2 = (AlertLineItem) next;
                    if (alertLineItem2 == null || (alertLineItemV = v(alertLineItem2, i10, i11, c2702dE, abstractC2759w0)) == null) {
                        it = listR1.iterator();
                        while (true) {
                            if (it.hasNext()) {
                                alertLineItemV = null;
                                break;
                            }
                            alertLineItem = (AlertLineItem) it.next();
                            aVar = KLineManager.f142490O;
                            if (AbstractC7609s.f(aVar.a().A(), "cny") || aVar.a().Q()) {
                                mode_info = alertLineItem.getMode_info();
                                if (mode_info != null) {
                                    dN = Ah.v.n(mode_info);
                                } else {
                                    dN = null;
                                }
                            } else {
                                String mode_info_cmp = alertLineItem.getMode_info_cmp();
                                if (mode_info_cmp != null) {
                                    dN = Ah.v.n(mode_info_cmp);
                                } else {
                                    dN = null;
                                }
                            }
                            if (dN == null && dN.doubleValue() <= abstractC2759w0.u() && dN.doubleValue() >= abstractC2759w0.v() && (alertLineItemV = v(alertLineItem, i10, i11, c2702dE, abstractC2759w0)) != null) {
                                break;
                            }
                        }
                    }
                }
            } else {
                alertLineItemV = null;
                break;
            }
            if (alertLineItemV != null) {
                z(alertLineItemV);
                return true;
            }
        }
        if (!(objD instanceof Qf.p)) {
            if (objD instanceof AlertLineItem) {
                return B((AlertLineItem) objD, "line", i11);
            }
            if (!this.f95467X) {
                return false;
            }
            C();
            i().e().x();
            return true;
        }
        Qf.p pVar = (Qf.p) objD;
        Object objC = pVar.c();
        AlertLineItem alertLineItem3 = objC instanceof AlertLineItem ? (AlertLineItem) objC : null;
        if (alertLineItem3 == null) {
            return false;
        }
        Object objD2 = pVar.d();
        String str3 = objD2 instanceof String ? (String) objD2 : null;
        if (str3 == null) {
            return false;
        }
        if (!AbstractC7609s.f(str3, "delete_icon") && !AbstractC7609s.f(str3, "delete_icon_priority")) {
            return B(alertLineItem3, str3, i11);
        }
        z(alertLineItem3);
        return true;
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        Resources resources;
        if (aVar == null) {
            return;
        }
        C2741q c2741qB = i().b();
        this.f95486n0 = c2741qB;
        c2741qB.e(b());
        this.f95488o0 = c2741qB.m(c());
        this.f95490p0 = c2741qB.l(b());
        AbstractC2755v abstractC2755vQ = q();
        C7495w c7495w = abstractC2755vQ instanceof C7495w ? (C7495w) abstractC2755vQ : null;
        if (c7495w == null) {
            return;
        }
        this.f95492q0 = c7495w;
        this.f95489p.setColor(aVar.c(10));
        this.f95487o.setColor(aVar.c(9));
        try {
            KLineManager.a aVar2 = KLineManager.f142490O;
            Context contextW = aVar2.a().w();
            if (contextW == null || (resources = contextW.getResources()) == null) {
                resources = aVar2.a().i().getResources();
            }
            this.f95494s = BitmapFactory.decodeResource(resources, R.mipmap.alert_line_icon);
            this.f95495t = BitmapFactory.decodeResource(resources, R.mipmap.alert_line_icon_low);
            this.f95496u = BitmapFactory.decodeResource(resources, R.mipmap.alert_line_delete_icon);
        } catch (Exception unused) {
            Bitmap.Config config = Bitmap.Config.ARGB_8888;
            this.f95494s = Bitmap.createBitmap(1, 1, config);
            this.f95495t = Bitmap.createBitmap(1, 1, config);
            this.f95496u = Bitmap.createBitmap(1, 1, config);
        }
        C7389n.f95436a.b(this);
    }

    /* JADX WARN: Code duplicated, block: B:30:0x0084  */
    public final AlertLineItem v(AlertLineItem alertLineItem, int i10, int i11, C2702d c2702d, AbstractC2759w0 abstractC2759w0) {
        Double dN;
        double dDoubleValue;
        float f10;
        float f11;
        Double dN2;
        KLineManager.a aVar = KLineManager.f142490O;
        if (!AbstractC7609s.f(aVar.a().A(), "cny") || aVar.a().Q()) {
            String mode_info = alertLineItem.getMode_info();
            if (mode_info != null && (dN = Ah.v.n(mode_info)) != null) {
                dDoubleValue = dN.doubleValue();
            }
            return null;
        }
        String mode_info_cmp = alertLineItem.getMode_info_cmp();
        if (mode_info_cmp == null || (dN2 = Ah.v.n(mode_info_cmp)) == null) {
            return null;
        }
        dDoubleValue = dN2.doubleValue();
        if (dDoubleValue <= abstractC2759w0.u() && dDoubleValue >= abstractC2759w0.v()) {
            float fP = abstractC2759w0.P(dDoubleValue);
            float fU = c2702d.u() + 35.0f;
            float f12 = ((this.f95493r * 2.0f) / 2) + 60.0f;
            float f13 = (fP - f12) - 25.0f;
            float f14 = fP + f12 + 25.0f;
            float f15 = i10;
            if (f15 < 0.0f || f15 > 200.0f) {
                f10 = f15 - fU;
                f11 = i11 - fP;
                if (((float) Math.sqrt((f11 * f11) + (f10 * f10))) <= f12 + 35.0f) {
                }
            } else {
                float f16 = i11;
                if (f16 < f13 || f16 > f14) {
                    f10 = f15 - fU;
                    f11 = i11 - fP;
                    if (((float) Math.sqrt((f11 * f11) + (f10 * f10))) <= f12 + 35.0f) {
                    }
                }
            }
            return alertLineItem;
        }
        return null;
    }

    public final void w() {
        this.f95446C.removeCallbacks(this.f95447D);
        this.f95455L.removeCallbacks(this.f95456M);
        y1 y1Var = this.f95488o0;
        if (y1Var == null) {
            return;
        }
        y1Var.Y(false);
        y1Var.W(-1.0f);
        y1Var.X(-1.0f);
        this.f95452I.removeCallbacks(this.f95453J);
        this.f95452I.postDelayed(this.f95453J, this.f95454K);
    }

    public final void z(AlertLineItem alertLineItem) {
        this.f95452I.removeCallbacks(this.f95453J);
        this.f95455L.removeCallbacks(this.f95456M);
        C2738p.f19487a.c(alertLineItem);
        AlertLineItem alertLineItem2 = this.f95460Q;
        if (AbstractC7609s.f(alertLineItem2 != null ? alertLineItem2.getId() : null, alertLineItem.getId())) {
            this.f95460Q = null;
            this.f95465V = null;
        }
        if (AbstractC7609s.f(this.f95500y, alertLineItem.getId())) {
            this.f95500y = null;
        }
        if (AbstractC7609s.f(this.f95468Y, alertLineItem.getId())) {
            C();
        }
        if (this.f95500y != null) {
            this.f95500y = null;
            this.f95460Q = null;
            this.f95465V = null;
            this.f95462S = 0L;
            this.f95466W = false;
            w();
        }
        L();
        this.f95474e0 = false;
        this.f95475f0 = 0.0f;
        this.f95476g0 = 0.0d;
        this.f95484m0 = 0.0f;
        C();
        i().e().x();
    }
}
