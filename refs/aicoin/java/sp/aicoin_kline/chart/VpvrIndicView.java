package sp.aicoin_kline.chart;

import Qf.H;
import Qf.InterfaceC2632j;
import Qf.k;
import Rj.AbstractC2755v;
import Rj.AbstractC2759w0;
import Rj.C2741q;
import Rj.C2765z;
import Rj.L1;
import Rj.M1;
import Rj.N1;
import Rj.O1;
import Rj.P1;
import Rj.Q1;
import Rj.R1;
import Rj.S1;
import Rj.T1;
import Rj.U1;
import Sf.r;
import Sf.y;
import Sf.z;
import Sj.b;
import android.content.Context;
import android.content.res.Resources;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.DashPathEffect;
import android.graphics.Paint;
import android.graphics.PathEffect;
import android.graphics.Rect;
import android.graphics.RectF;
import android.util.AttributeSet;
import android.view.MotionEvent;
import android.view.View;
import com.umeng.analytics.pro.am;
import com.umeng.analytics.pro.d;
import ek.I;
import ek.m;
import ek.o;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import kk.c;
import kotlin.Metadata;
import kotlin.jvm.functions.Function1;
import kotlin.jvm.internal.DefaultConstructorMarker;
import nk.A;
import nk.i;
import nk.u;
import p254m.aicoin.kline.main.MainKlineFragment;
import sp.aicoin_kline.R;
import sp.aicoin_kline.chart.data.AICYQItem;
import sp.aicoin_kline.chart.data.VpVrAlertItemData;
import sp.aicoin_kline.chart.data.VpVrConfigData;
import sp.aicoin_kline.core.KLineManager;
import sp.aicoin_kline.core.indicator.config.F;

/* JADX INFO: loaded from: classes7.dex */
@Metadata(d1 = {"\u0000n\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0010\b\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\b\n\u0002\u0010\u000b\n\u0002\b\u0007\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u0019\n\u0002\u0018\u0002\n\u0002\b\u0007\n\u0002\u0018\u0002\n\u0002\u0010!\n\u0002\u0018\u0002\n\u0002\b\t\b\u0007\u0018\u00002\u00020\u0001:\u0001WB\u001b\b\u0016\u0012\u0006\u0010\u0003\u001a\u00020\u0002\u0012\b\u0010\u0005\u001a\u0004\u0018\u00010\u0004¢\u0006\u0004\b\u0006\u0010\u0007B#\b\u0016\u0012\u0006\u0010\u0003\u001a\u00020\u0002\u0012\b\u0010\u0005\u001a\u0004\u0018\u00010\u0004\u0012\u0006\u0010\t\u001a\u00020\b¢\u0006\u0004\b\u0006\u0010\nJ%\u0010\u0010\u001a\u00020\u000f2\u0006\u0010\f\u001a\u00020\u000b2\u0006\u0010\r\u001a\u00020\b2\u0006\u0010\u000e\u001a\u00020\b¢\u0006\u0004\b\u0010\u0010\u0011J\u0015\u0010\u0013\u001a\u00020\u000f2\u0006\u0010\f\u001a\u00020\u0012¢\u0006\u0004\b\u0013\u0010\u0014J\r\u0010\u0015\u001a\u00020\u000f¢\u0006\u0004\b\u0015\u0010\u0016J\u001f\u0010\u0019\u001a\u00020\u000f2\u0006\u0010\u0017\u001a\u00020\b2\u0006\u0010\u0018\u001a\u00020\bH\u0014¢\u0006\u0004\b\u0019\u0010\u001aJ7\u0010!\u001a\u00020\u000f2\u0006\u0010\u001c\u001a\u00020\u001b2\u0006\u0010\u001d\u001a\u00020\b2\u0006\u0010\u001e\u001a\u00020\b2\u0006\u0010\u001f\u001a\u00020\b2\u0006\u0010 \u001a\u00020\bH\u0014¢\u0006\u0004\b!\u0010\"J\u0017\u0010%\u001a\u00020\u000f2\u0006\u0010$\u001a\u00020#H\u0014¢\u0006\u0004\b%\u0010&J\u0019\u0010)\u001a\u00020\u001b2\b\u0010(\u001a\u0004\u0018\u00010'H\u0016¢\u0006\u0004\b)\u0010*R\u001b\u00100\u001a\u00020+8BX\u0082\u0084\u0002¢\u0006\f\n\u0004\b,\u0010-\u001a\u0004\b.\u0010/R\u001b\u00103\u001a\u00020+8BX\u0082\u0084\u0002¢\u0006\f\n\u0004\b1\u0010-\u001a\u0004\b2\u0010/R\u001b\u00106\u001a\u00020+8BX\u0082\u0084\u0002¢\u0006\f\n\u0004\b4\u0010-\u001a\u0004\b5\u0010/R\u001b\u00109\u001a\u00020+8BX\u0082\u0084\u0002¢\u0006\f\n\u0004\b7\u0010-\u001a\u0004\b8\u0010/R\u001b\u0010<\u001a\u00020+8BX\u0082\u0084\u0002¢\u0006\f\n\u0004\b:\u0010-\u001a\u0004\b;\u0010/R\u001b\u0010>\u001a\u00020+8BX\u0082\u0084\u0002¢\u0006\f\n\u0004\b\u0010\u0010-\u001a\u0004\b=\u0010/R\u001b\u0010A\u001a\u00020+8BX\u0082\u0084\u0002¢\u0006\f\n\u0004\b?\u0010-\u001a\u0004\b@\u0010/R\u001b\u0010D\u001a\u00020+8BX\u0082\u0084\u0002¢\u0006\f\n\u0004\bB\u0010-\u001a\u0004\bC\u0010/R(\u0010L\u001a\b\u0012\u0004\u0012\u00020\u000f0E8\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\bF\u0010G\u001a\u0004\bH\u0010I\"\u0004\bJ\u0010KR4\u0010V\u001a\u0014\u0012\n\u0012\b\u0012\u0004\u0012\u00020O0N\u0012\u0004\u0012\u00020\u000f0M8\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\bP\u0010Q\u001a\u0004\bR\u0010S\"\u0004\bT\u0010U¨\u0006X"}, d2 = {"Lsp/aicoin_kline/chart/VpvrIndicView;", "Landroid/view/View;", "Landroid/content/Context;", d.f89950R, "Landroid/util/AttributeSet;", "attrs", "<init>", "(Landroid/content/Context;Landroid/util/AttributeSet;)V", "", "defStyleAttr", "(Landroid/content/Context;Landroid/util/AttributeSet;I)V", "Lsp/aicoin_kline/chart/data/AICYQItem;", "data", "topPadding", "bottomLinePadding", "LQf/H;", "l", "(Lsp/aicoin_kline/chart/data/AICYQItem;II)V", "Lsp/aicoin_kline/chart/data/VpVrConfigData;", "setConfigData", "(Lsp/aicoin_kline/chart/data/VpVrConfigData;)V", "k", "()V", "widthMeasureSpec", "heightMeasureSpec", "onMeasure", "(II)V", "", "changed", "left", "top", "right", "bottom", "onLayout", "(ZIIII)V", "Landroid/graphics/Canvas;", "canvas", "onDraw", "(Landroid/graphics/Canvas;)V", "Landroid/view/MotionEvent;", "event", "onTouchEvent", "(Landroid/view/MotionEvent;)Z", "Landroid/graphics/Paint;", "f", "LQf/j;", "getSelectedRectLinePaint", "()Landroid/graphics/Paint;", "selectedRectLinePaint", "g", "getMWhitePaint", "mWhitePaint", am.aG, "getMPressPaint", "mPressPaint", am.aC, "getMControlPointPaint", "mControlPointPaint", "j", "getMSupportPaint", "mSupportPaint", "getMAskPaint", "mAskPaint", "m", "getMBidsPaint", "mBidsPaint", "n", "getMRangeLinePaint", "mRangeLinePaint", "Lkotlin/Function0;", "q", "Lgg/a;", "getOnDetailClickItem", "()Lgg/a;", "setOnDetailClickItem", "(Lgg/a;)V", "onDetailClickItem", "Lkotlin/Function1;", "", "Lsp/aicoin_kline/chart/data/VpVrAlertItemData;", "r", "Lkotlin/jvm/functions/Function1;", "getOnAlertClickItem", "()Lkotlin/jvm/functions/Function1;", "setOnAlertClickItem", "(Lkotlin/jvm/functions/Function1;)V", "onAlertClickItem", am.av, "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final class VpvrIndicView extends View {

    /* JADX INFO: renamed from: Q, reason: collision with root package name */
    public static final a f142420Q = new a(null);

    /* JADX INFO: renamed from: R, reason: collision with root package name */
    public static final int f142421R = Color.parseColor("#FFB7BFC8");

    /* JADX INFO: renamed from: S, reason: collision with root package name */
    public static final int f142422S = Color.parseColor("#515A66");

    /* JADX INFO: renamed from: T, reason: collision with root package name */
    public static final int f142423T = Color.parseColor("#FF7A8899");

    /* JADX INFO: renamed from: U, reason: collision with root package name */
    public static final int f142424U = Color.parseColor("#FF667180");

    /* JADX INFO: renamed from: A, reason: collision with root package name */
    public float f142425A;

    /* JADX INFO: renamed from: B, reason: collision with root package name */
    public int f142426B;

    /* JADX INFO: renamed from: C, reason: collision with root package name */
    public double f142427C;

    /* JADX INFO: renamed from: D, reason: collision with root package name */
    public double f142428D;

    /* JADX INFO: renamed from: E, reason: collision with root package name */
    public List f142429E;

    /* JADX INFO: renamed from: F, reason: collision with root package name */
    public List f142430F;

    /* JADX INFO: renamed from: G, reason: collision with root package name */
    public ArrayList f142431G;

    /* JADX INFO: renamed from: H, reason: collision with root package name */
    public final ArrayList f142432H;

    /* JADX INFO: renamed from: I, reason: collision with root package name */
    public float f142433I;

    /* JADX INFO: renamed from: J, reason: collision with root package name */
    public int f142434J;

    /* JADX INFO: renamed from: K, reason: collision with root package name */
    public int f142435K;

    /* JADX INFO: renamed from: L, reason: collision with root package name */
    public final String f142436L;

    /* JADX INFO: renamed from: M, reason: collision with root package name */
    public final int f142437M;

    /* JADX INFO: renamed from: N, reason: collision with root package name */
    public final String f142438N;

    /* JADX INFO: renamed from: O, reason: collision with root package name */
    public final Bitmap f142439O;

    /* JADX INFO: renamed from: P, reason: collision with root package name */
    public final Bitmap f142440P;

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final Rect f142441a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final Rect f142442b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final RectF f142443c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public final RectF f142444d;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public final F f142445e;

    /* JADX INFO: renamed from: f, reason: collision with root package name and from kotlin metadata */
    public final InterfaceC2632j selectedRectLinePaint;

    /* JADX INFO: renamed from: g, reason: collision with root package name and from kotlin metadata */
    public final InterfaceC2632j mWhitePaint;

    /* JADX INFO: renamed from: h, reason: collision with root package name and from kotlin metadata */
    public final InterfaceC2632j mPressPaint;

    /* JADX INFO: renamed from: i, reason: collision with root package name and from kotlin metadata */
    public final InterfaceC2632j mControlPointPaint;

    /* JADX INFO: renamed from: j, reason: collision with root package name and from kotlin metadata */
    public final InterfaceC2632j mSupportPaint;

    /* JADX INFO: renamed from: k, reason: collision with root package name */
    public final Paint f142451k;

    /* JADX INFO: renamed from: l, reason: collision with root package name and from kotlin metadata */
    public final InterfaceC2632j mAskPaint;

    /* JADX INFO: renamed from: m, reason: collision with root package name and from kotlin metadata */
    public final InterfaceC2632j mBidsPaint;

    /* JADX INFO: renamed from: n, reason: collision with root package name and from kotlin metadata */
    public final InterfaceC2632j mRangeLinePaint;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final Paint f142455o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public List f142456p;

    /* JADX INFO: renamed from: q, reason: collision with root package name and from kotlin metadata */
    public p146gg.a onDetailClickItem;

    /* JADX INFO: renamed from: r, reason: collision with root package name and from kotlin metadata */
    public Function1 onAlertClickItem;

    /* JADX INFO: renamed from: s, reason: collision with root package name */
    public double f142459s;

    /* JADX INFO: renamed from: t, reason: collision with root package name */
    public int f142460t;

    /* JADX INFO: renamed from: u, reason: collision with root package name */
    public float f142461u;

    /* JADX INFO: renamed from: v, reason: collision with root package name */
    public float f142462v;

    /* JADX INFO: renamed from: w, reason: collision with root package name */
    public final RectF f142463w;

    /* JADX INFO: renamed from: x, reason: collision with root package name */
    public float f142464x;

    /* JADX INFO: renamed from: y, reason: collision with root package name */
    public float f142465y;

    /* JADX INFO: renamed from: z, reason: collision with root package name */
    public float f142466z;

    public static final class a {
        public a(DefaultConstructorMarker defaultConstructorMarker) {
        }

        public final PathEffect a() {
            return new DashPathEffect(new float[]{7.0f, 7.0f}, 0.0f);
        }
    }

    public VpvrIndicView(Context context, AttributeSet attributeSet) {
        this(context, attributeSet, 0);
    }

    public VpvrIndicView(Context context, AttributeSet attributeSet, int i10) {
        super(context, attributeSet, i10);
        this.f142441a = new Rect();
        new Rect();
        this.f142442b = new Rect();
        this.f142443c = new RectF();
        this.f142444d = new RectF();
        this.f142445e = (F) o.f93330a.b().get("vpvr");
        this.selectedRectLinePaint = k.b(new L1());
        this.mWhitePaint = k.b(new M1(this));
        this.mPressPaint = k.b(new N1());
        this.mControlPointPaint = k.b(new O1());
        this.mSupportPaint = k.b(new P1());
        Paint paint = new Paint(1);
        paint.setAntiAlias(true);
        paint.setColor(Color.parseColor("#FF7A8899"));
        paint.setTextSize(Xj.a.d(9));
        this.f142451k = paint;
        Paint paint2 = new Paint(1);
        paint2.setAntiAlias(true);
        paint2.setColor(Color.parseColor("#FF1478FA"));
        paint2.setTextSize(Xj.a.d(9));
        this.mAskPaint = k.b(new Q1());
        this.mBidsPaint = k.b(new R1());
        this.mRangeLinePaint = k.b(new S1());
        Paint paint3 = new Paint(1);
        paint3.setAntiAlias(true);
        paint3.setColor(Color.parseColor("#FF1478FA"));
        paint3.setTextSize(Xj.a.d(10));
        this.f142455o = paint3;
        this.onDetailClickItem = new T1();
        this.onAlertClickItem = new U1();
        this.f142461u = 830.0f;
        this.f142462v = 80.0f;
        this.f142463w = new RectF();
        this.f142429E = new ArrayList();
        this.f142430F = new ArrayList();
        new ArrayList();
        this.f142431G = new ArrayList();
        this.f142432H = new ArrayList();
        this.f142434J = Xj.a.b(30);
        this.f142435K = Xj.a.b(9);
        this.f142436L = "ds0.main";
        this.f142437M = KLineManager.f142490O.a().j();
        this.f142438N = "******";
        this.f142439O = BitmapFactory.decodeResource(getContext().getResources(), R.mipmap.vpvr_click_src);
        this.f142440P = BitmapFactory.decodeResource(getContext().getResources(), R.mipmap.vpvr_alert_src);
    }

    public static final H a(List list) {
        return H.f17640a;
    }

    public static final Paint b() {
        Paint paintA = c.a(true);
        paintA.setStyle(Paint.Style.FILL);
        paintA.setStrokeWidth(1.0f);
        paintA.setTextAlign(Paint.Align.CENTER);
        paintA.setColor(Color.parseColor("#33FAAD14"));
        return paintA;
    }

    public static final Paint c(VpvrIndicView vpvrIndicView) {
        Paint paintA = c.a(true);
        paintA.setStyle(Paint.Style.FILL);
        paintA.setStrokeWidth(1.0f);
        paintA.setTextAlign(Paint.Align.CENTER);
        paintA.setColor(vpvrIndicView.getContext().getResources().getColor(R.color.kline_vpvr_white_color));
        return paintA;
    }

    public static final Paint d() {
        Paint paintA = c.a(true);
        paintA.setStyle(Paint.Style.FILL);
        paintA.setStrokeWidth(1.0f);
        paintA.setTextAlign(Paint.Align.CENTER);
        paintA.setColor(Color.parseColor("#331478FA"));
        return paintA;
    }

    public static final Paint e() {
        Paint paint = new Paint();
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(6.0f);
        paint.setAntiAlias(true);
        paint.setColor(Color.parseColor("#3B87EB"));
        paint.setPathEffect(new DashPathEffect(new float[]{6.0f, 6.0f}, 0.0f));
        return paint;
    }

    public static final Paint f() {
        Paint paint = new Paint();
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(3.0f);
        paint.setAntiAlias(true);
        paint.setColor(f142421R);
        paint.setPathEffect(f142420Q.a());
        return paint;
    }

    public static final Paint g() {
        Paint paintA = c.a(true);
        paintA.setStyle(Paint.Style.FILL);
        paintA.setStrokeWidth(0.5f);
        paintA.setTextAlign(Paint.Align.CENTER);
        paintA.setColor(-1381654);
        return paintA;
    }

    private final Paint getMAskPaint() {
        return (Paint) this.mAskPaint.getValue();
    }

    private final Paint getMBidsPaint() {
        return (Paint) this.mBidsPaint.getValue();
    }

    private final Paint getMControlPointPaint() {
        return (Paint) this.mControlPointPaint.getValue();
    }

    private final Paint getMPressPaint() {
        return (Paint) this.mPressPaint.getValue();
    }

    private final Paint getMRangeLinePaint() {
        return (Paint) this.mRangeLinePaint.getValue();
    }

    private final Paint getMSupportPaint() {
        return (Paint) this.mSupportPaint.getValue();
    }

    private final Paint getMWhitePaint() {
        return (Paint) this.mWhitePaint.getValue();
    }

    private final Paint getSelectedRectLinePaint() {
        return (Paint) this.selectedRectLinePaint.getValue();
    }

    public static final Paint h() {
        Paint paint = new Paint();
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(3.0f);
        paint.setAntiAlias(true);
        paint.setColor(f142421R);
        paint.setPathEffect(f142420Q.a());
        return paint;
    }

    public static final H i() {
        return H.f17640a;
    }

    public static final Paint j() {
        Paint paint = new Paint();
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(3.0f);
        paint.setAntiAlias(true);
        paint.setColor(f142423T);
        paint.setPathEffect(f142420Q.a());
        return paint;
    }

    public final Function1 getOnAlertClickItem() {
        return this.onAlertClickItem;
    }

    public final p146gg.a getOnDetailClickItem() {
        return this.onDetailClickItem;
    }

    public final void k() {
        Xj.c.f25377a.m(this.f142431G);
    }

    public final void l(AICYQItem data, int topPadding, int bottomLinePadding) {
        Object next;
        Double d10;
        Double d11;
        Double d12;
        Double d13;
        List list = this.f142456p;
        if (list != null) {
            list.clear();
        }
        Xj.c.f25377a.b();
        Chart chartG = KLineManager.f142490O.a().g();
        if (chartG != null) {
            chartG.x();
        }
        List listU1 = z.u1(data.getDataList());
        this.f142456p = listU1;
        if (listU1 != null) {
            y.X(listU1);
        }
        this.f142461u = data.getMaxY() - this.f142434J;
        this.f142462v = data.getMinY();
        data.getMinValue();
        data.getMaxValue();
        Iterator it = listU1.iterator();
        Object next2 = null;
        double dDoubleValue = 0.0d;
        if (it.hasNext()) {
            next = it.next();
            if (it.hasNext()) {
                Double d14 = (Double) ((Map) next).get(MainKlineFragment.KEY_AISRL_BIDS);
                double dDoubleValue2 = d14 != null ? d14.doubleValue() : 0.0d;
                do {
                    Object next3 = it.next();
                    Double d15 = (Double) ((Map) next3).get(MainKlineFragment.KEY_AISRL_BIDS);
                    double dDoubleValue3 = d15 != null ? d15.doubleValue() : 0.0d;
                    if (Double.compare(dDoubleValue2, dDoubleValue3) < 0) {
                        next = next3;
                        dDoubleValue2 = dDoubleValue3;
                    }
                } while (it.hasNext());
            }
        } else {
            next = null;
        }
        Map map = (Map) next;
        Iterator it2 = listU1.iterator();
        if (it2.hasNext()) {
            next2 = it2.next();
            if (it2.hasNext()) {
                Double d16 = (Double) ((Map) next2).get(MainKlineFragment.KEY_AISRL_ASKS);
                double dDoubleValue4 = d16 != null ? d16.doubleValue() : 0.0d;
                do {
                    Object next4 = it2.next();
                    Double d17 = (Double) ((Map) next4).get(MainKlineFragment.KEY_AISRL_ASKS);
                    double dDoubleValue5 = d17 != null ? d17.doubleValue() : 0.0d;
                    if (Double.compare(dDoubleValue4, dDoubleValue5) < 0) {
                        next2 = next4;
                        dDoubleValue4 = dDoubleValue5;
                    }
                } while (it2.hasNext());
            }
        }
        Map map2 = (Map) next2;
        double dDoubleValue6 = (map == null || (d13 = (Double) map.get(MainKlineFragment.KEY_AISRL_BIDS)) == null) ? 0.0d : d13.doubleValue();
        double dDoubleValue7 = (map == null || (d12 = (Double) map.get(MainKlineFragment.KEY_AISRL_ASKS)) == null) ? 0.0d : d12.doubleValue();
        double dDoubleValue8 = (map2 == null || (d11 = (Double) map2.get(MainKlineFragment.KEY_AISRL_ASKS)) == null) ? 0.0d : d11.doubleValue();
        if (map2 != null && (d10 = (Double) map2.get(MainKlineFragment.KEY_AISRL_BIDS)) != null) {
            dDoubleValue = d10.doubleValue();
        }
        double d18 = dDoubleValue6 + dDoubleValue7;
        double d19 = dDoubleValue + dDoubleValue8;
        if (d18 > d19) {
            this.f142459s = Math.abs(d18);
        } else {
            this.f142459s = Math.abs(d19);
        }
        Xj.c cVar = Xj.c.f25377a;
        this.f142429E = cVar.a(data, this.f142427C);
        this.f142430F = cVar.a(data, this.f142428D);
        this.f142434J = Xj.a.b(topPadding);
        this.f142435K = Xj.a.b(bottomLinePadding);
        List listN = this.f142456p;
        if (listN == null) {
            listN = r.n();
        }
        ArrayList arrayList = new ArrayList();
        Iterator it3 = new i().a(listN).iterator();
        while (it3.hasNext()) {
            arrayList.add(Integer.valueOf(((i.a) it3.next()).a()));
        }
        this.f142431G = arrayList;
        Xj.c.f25377a.h(this.f142456p);
        invalidate();
    }

    /* JADX WARN: Code duplicated, block: B:160:0x02f2  */
    /* JADX WARN: Code duplicated, block: B:217:0x042a  */
    /* JADX WARN: Code duplicated, block: B:249:0x05ad  */
    /* JADX WARN: Code duplicated, block: B:252:0x05ea  */
    /* JADX WARN: Code duplicated, block: B:32:0x00c6  */
    /* JADX WARN: Code duplicated, block: B:42:0x00f9  */
    @Override // android.view.View
    public void onDraw(Canvas canvas) {
        AbstractC2759w0 abstractC2759w0L;
        Double dValueOf;
        Double dValueOf2;
        Canvas canvas2;
        String string;
        Resources resources;
        double d10;
        AbstractC2759w0 abstractC2759w0;
        String string2;
        Resources resources2;
        String string3;
        Resources resources3;
        I[] iArrR;
        I i10;
        m[] mVarArrK;
        m mVar;
        m[] mVarArrK2;
        m mVar2;
        m[] mVarArrK3;
        I[] iArrR2;
        I i11;
        int color;
        m[] mVarArrK4;
        m[] mVarArrK5;
        m mVar3;
        m[] mVarArrK6;
        I[] iArrR3;
        I i12;
        m[] mVarArrK7;
        m mVar4;
        m[] mVarArrK8;
        m mVar5;
        m[] mVarArrK9;
        b bVarM;
        Canvas canvas3 = canvas;
        super.onDraw(canvas);
        this.f142432H.clear();
        KLineManager.a aVar = KLineManager.f142490O;
        int i13 = 0;
        int i14 = 1;
        boolean z10 = aVar.a().f0() == 1;
        if (z10) {
            getMWhitePaint().setColor(getContext().getResources().getColor(R.color.kline_vpvr_white_color));
            getMRangeLinePaint().setColor(-1381654);
        } else {
            getMWhitePaint().setColor(getContext().getResources().getColor(R.color.kline_vpvr_white_color_night));
            getMRangeLinePaint().setColor(-13947075);
        }
        int i15 = z10 ? f142421R : f142422S;
        getMPressPaint().setColor(i15);
        getMSupportPaint().setColor(i15);
        getSelectedRectLinePaint().setColor(z10 ? f142423T : f142424U);
        C2741q c2741qX = aVar.a().x();
        if (c2741qX == null || (abstractC2759w0L = c2741qX.l(this.f142436L)) == null) {
            return;
        }
        int i16 = 2;
        C2765z c2765zH = c2741qX.h(Ah.y.e1(this.f142436L, ".", null, 2, null));
        double d11 = 0.0d;
        if (c2765zH == null || (bVarM = c2765zH.M()) == null) {
            dValueOf = null;
        } else {
            double dA = bVarM.a();
            dValueOf = Double.valueOf(dA);
            if (dA <= 0.0d || Double.isNaN(dA) || Double.isInfinite(dA)) {
                dValueOf = null;
            }
        }
        AbstractC2755v abstractC2755vG = c2741qX.g(this.f142436L + ".m");
        if (abstractC2755vG != null) {
            double dI = abstractC2755vG.i();
            dValueOf2 = Double.valueOf(dI);
            if (dI <= 0.0d || Double.isNaN(dI) || Double.isInfinite(dI)) {
                dValueOf2 = null;
            }
        } else {
            dValueOf2 = null;
        }
        if (dValueOf == null) {
            dValueOf = dValueOf2;
        }
        Double dValueOf3 = dValueOf != null ? Double.valueOf(nk.c.e(dValueOf.doubleValue())) : null;
        if (dValueOf3 != null) {
            double dDoubleValue = dValueOf3.doubleValue();
            this.f142426B = 0;
            this.f142433I = this.f142461u + Xj.a.b(20);
            List list = this.f142456p;
            if (list == null || list.isEmpty()) {
                return;
            }
            List<Map> list2 = this.f142456p;
            if (list2 != null) {
                for (Map map : list2) {
                    Double d12 = (Double) map.get(MainKlineFragment.KEY_AISRL_BIDS);
                    d11 = d11;
                    this.f142464x = (float) (((d12 != null ? d12.doubleValue() : d11) * ((double) this.f142460t)) / this.f142459s);
                    Double d13 = (Double) map.get(MainKlineFragment.KEY_AISRL_ASKS);
                    this.f142465y = (float) (((d13 != null ? d13.doubleValue() : d11) * ((double) this.f142460t)) / this.f142459s);
                    Double d14 = (Double) map.get("from");
                    double dDoubleValue2 = d14 != null ? d14.doubleValue() : d11;
                    Double d15 = (Double) map.get("to");
                    double dDoubleValue3 = d15 != null ? d15.doubleValue() : d11;
                    Double d16 = (Double) map.get(MainKlineFragment.KEY_AISRL_BIDS);
                    double dDoubleValue4 = d16 != null ? d16.doubleValue() : d11;
                    Double d17 = (Double) map.get(MainKlineFragment.KEY_AISRL_ASKS);
                    double dDoubleValue5 = d17 != null ? d17.doubleValue() : d11;
                    if (dDoubleValue2 <= d11) {
                        i13 = 0;
                    } else if (dDoubleValue3 <= d11) {
                        d11 = d11;
                    } else {
                        this.f142466z = abstractC2759w0L.S(dDoubleValue3) - this.f142434J;
                        float fS = abstractC2759w0L.S(dDoubleValue2) - this.f142434J;
                        this.f142425A = fS;
                        float f10 = this.f142466z;
                        int i17 = i13;
                        float f11 = this.f142461u;
                        if (f10 <= f11) {
                            if (fS > f11) {
                                d11 = d11;
                                i13 = i17;
                            } else {
                                double d18 = dDoubleValue4 + dDoubleValue5;
                                F f12 = this.f142445e;
                                if (((f12 == null || (mVarArrK9 = f12.k()) == null) ? i17 : mVarArrK9.length) > i16) {
                                    Paint mBidsPaint = getMBidsPaint();
                                    F f13 = this.f142445e;
                                    mBidsPaint.setColor((f13 == null || (mVarArrK8 = f13.k()) == null || (mVar5 = mVarArrK8[i14]) == null) ? Color.parseColor("#331478FA") : mVar5.a());
                                    Paint mAskPaint = getMAskPaint();
                                    F f14 = this.f142445e;
                                    mAskPaint.setColor((f14 == null || (mVarArrK7 = f14.k()) == null || (mVar4 = mVarArrK7[i16]) == null) ? Color.parseColor("#33FAAD14") : mVar4.a());
                                } else {
                                    getMBidsPaint().setColor(Color.parseColor("#331478FA"));
                                    getMAskPaint().setColor(Color.parseColor("#33FAAD14"));
                                }
                                if (this.f142429E.contains(Integer.valueOf(this.f142426B))) {
                                    F f15 = this.f142445e;
                                    if (((f15 == null || (iArrR3 = f15.r()) == null || (i12 = iArrR3[i14]) == null || i12.b() != i14) ? i17 : i14) != 0) {
                                        F f16 = this.f142445e;
                                        if (((f16 == null || (mVarArrK6 = f16.k()) == null) ? i17 : mVarArrK6.length) > 4) {
                                            Paint mBidsPaint2 = getMBidsPaint();
                                            F f17 = this.f142445e;
                                            mBidsPaint2.setColor((f17 == null || (mVarArrK5 = f17.k()) == null || (mVar3 = mVarArrK5[3]) == null) ? Color.parseColor("#B34A6EFF") : mVar3.a());
                                            Paint mAskPaint2 = getMAskPaint();
                                            F f18 = this.f142445e;
                                            if (f18 != null && (mVarArrK4 = f18.k()) != null) {
                                                m mVar6 = mVarArrK4[4];
                                                if (mVar6 != null) {
                                                    color = mVar6.a();
                                                }
                                                mAskPaint2.setColor(color);
                                            }
                                            color = Color.parseColor("#B3FFA442");
                                            mAskPaint2.setColor(color);
                                        } else {
                                            getMBidsPaint().setColor(Color.parseColor("#B34A6EFF"));
                                            getMAskPaint().setColor(Color.parseColor("#B3FFA442"));
                                        }
                                    }
                                }
                                if (this.f142430F.contains(Integer.valueOf(this.f142426B))) {
                                    F f19 = this.f142445e;
                                    if (((f19 == null || (iArrR2 = f19.r()) == null || (i11 = iArrR2[i16]) == null || i11.b() != i14) ? i17 : i14) != 0) {
                                        F f20 = this.f142445e;
                                        if (((f20 == null || (mVarArrK3 = f20.k()) == null) ? i17 : mVarArrK3.length) > 6) {
                                            Paint mBidsPaint3 = getMBidsPaint();
                                            F f21 = this.f142445e;
                                            mBidsPaint3.setColor((f21 == null || (mVarArrK2 = f21.k()) == null || (mVar2 = mVarArrK2[5]) == null) ? Color.parseColor("#7F1478FA") : mVar2.a());
                                            Paint mAskPaint3 = getMAskPaint();
                                            F f22 = this.f142445e;
                                            mAskPaint3.setColor((f22 == null || (mVarArrK = f22.k()) == null || (mVar = mVarArrK[6]) == null) ? Color.parseColor("#7FFAAD14") : mVar.a());
                                        } else {
                                            getMBidsPaint().setColor(Color.parseColor("#7F1478FA"));
                                            getMAskPaint().setColor(Color.parseColor("#7FFAAD14"));
                                        }
                                    }
                                }
                                this.f142463w.set(0.0f, this.f142466z, this.f142464x, this.f142425A);
                                canvas3.drawRect(this.f142463w, getMBidsPaint());
                                RectF rectF = this.f142463w;
                                float f23 = this.f142464x;
                                rectF.set(f23, this.f142466z, this.f142465y + f23, this.f142425A);
                                canvas3.drawRect(this.f142463w, getMAskPaint());
                                this.f142463w.set(0.0f, this.f142466z - u.a(getContext(), 1.0f), this.f142460t, this.f142466z);
                                canvas3.drawRect(this.f142463w, getMWhitePaint());
                                if ((d18 == this.f142459s ? i14 : i17) == 0) {
                                    d10 = dDoubleValue3;
                                } else {
                                    F f24 = this.f142445e;
                                    if (((f24 == null || (iArrR = f24.r()) == null || (i10 = iArrR[i17]) == null || i10.b() != i14) ? i17 : i14) == 0) {
                                        Xj.c cVar = Xj.c.f25377a;
                                        double d19 = cVar.d(dDoubleValue2, dDoubleValue3);
                                        float fS2 = abstractC2759w0L.S(d19) - this.f142434J;
                                        d10 = dDoubleValue3;
                                        canvas3.drawLine(0.0f, fS2, this.f142460t, fS2, getMControlPointPaint());
                                        cVar.i(d19);
                                    } else {
                                        d10 = dDoubleValue3;
                                    }
                                }
                                ArrayList arrayList = this.f142431G;
                                if (arrayList == null || !arrayList.contains(Integer.valueOf(this.f142426B))) {
                                    canvas3 = canvas;
                                    abstractC2759w0 = abstractC2759w0L;
                                } else {
                                    double d20 = Xj.c.f25377a.d(dDoubleValue2, d10);
                                    abstractC2759w0 = abstractC2759w0L;
                                    float fS3 = abstractC2759w0.S(d20) - this.f142434J;
                                    this.f142451k.getTextBounds("压力位1", i17, 4, this.f142441a);
                                    KLineManager.a aVar2 = KLineManager.f142490O;
                                    String strB = aVar2.a().d0() ? A.b(d20, this.f142437M) : this.f142438N;
                                    this.f142432H.add(new VpVrAlertItemData(A.b(d20, this.f142437M), A.b(d18, this.f142437M)));
                                    if (d20 > dDoubleValue) {
                                        canvas3 = canvas;
                                        canvas3.drawLine(0.0f, fS3, this.f142460t, fS3, getMPressPaint());
                                        this.f142433I = (this.f142441a.bottom * 12) + this.f142433I;
                                        Context contextW = aVar2.a().w();
                                        if (contextW == null || (resources3 = contextW.getResources()) == null || (string3 = resources3.getString(R.string.kline_vpvr_press)) == null) {
                                            string3 = aVar2.a().i().getResources().getString(R.string.kline_vpvr_press);
                                        }
                                        this.f142451k.setColor(Color.parseColor("#3B87EB"));
                                        canvas3.drawText(string3, this.f142441a.left + Xj.a.b(10), this.f142433I, this.f142451k);
                                        canvas3.drawText(strB, this.f142441a.right + Xj.a.b(15), this.f142433I, this.f142451k);
                                    } else {
                                        canvas3 = canvas;
                                        canvas3.drawLine(0.0f, fS3, this.f142460t, fS3, getMSupportPaint());
                                        this.f142433I = (this.f142441a.bottom * 12) + this.f142433I;
                                        Context contextW2 = aVar2.a().w();
                                        if (contextW2 == null || (resources2 = contextW2.getResources()) == null || (string2 = resources2.getString(R.string.kline_vpvr_support)) == null) {
                                            string2 = aVar2.a().i().getResources().getString(R.string.kline_vpvr_support);
                                        }
                                        this.f142451k.setColor(Color.parseColor("#FF7A8899"));
                                        canvas3.drawText(string2, this.f142441a.left + Xj.a.b(10), this.f142433I, this.f142451k);
                                        canvas3.drawText(strB, this.f142441a.right + Xj.a.b(15), this.f142433I, this.f142451k);
                                    }
                                    canvas3.drawBitmap(this.f142440P, this.f142460t - Xj.a.b(10), this.f142433I - Xj.a.b(9), (Paint) null);
                                }
                                this.f142426B++;
                                abstractC2759w0L = abstractC2759w0;
                                i14 = i14;
                                i16 = i16;
                            }
                        }
                        i13 = 0;
                    }
                }
            }
            AbstractC2759w0 abstractC2759w1 = abstractC2759w0L;
            double d21 = d11;
            this.f142444d.set(0.0f, this.f142461u + Xj.a.b(20), this.f142460t, this.f142433I + Xj.a.b(20));
            float f25 = this.f142435K + this.f142461u;
            canvas3.drawLine(0.0f, f25, this.f142460t, f25, getMRangeLinePaint());
            double dF = Xj.c.f25377a.f();
            if (dF <= d21) {
                canvas2 = canvas;
            } else {
                float fS4 = abstractC2759w1.S(dF) - this.f142434J;
                if (fS4 < this.f142462v || fS4 > this.f142461u) {
                    canvas2 = canvas;
                } else {
                    canvas2 = canvas;
                    canvas2.drawLine(0.0f, fS4, this.f142460t, fS4, getSelectedRectLinePaint());
                }
            }
            KLineManager.a aVar3 = KLineManager.f142490O;
            if (aVar3.a().d0()) {
                this.f142433I += Xj.a.b(20);
                this.f142455o.getTextBounds("筹码解读", 0, 4, this.f142442b);
                this.f142443c.set((this.f142460t / 2.0f) - (this.f142439O.getWidth() / 2.0f), this.f142433I - Xj.a.b(20), ((this.f142460t / 2.0f) - (this.f142439O.getWidth() / 2.0f)) + Xj.a.b(50), this.f142433I + Xj.a.b(20));
                Bitmap bitmap = this.f142439O;
                canvas2.drawBitmap(bitmap, (this.f142460t / 2.0f) - (bitmap.getWidth() / 2.0f), this.f142433I, (Paint) null);
                Context contextW3 = aVar3.a().w();
                if (contextW3 == null || (resources = contextW3.getResources()) == null || (string = resources.getString(R.string.kline_vpvr_get)) == null) {
                    string = aVar3.a().i().getResources().getString(R.string.kline_vpvr_get);
                }
                canvas2.drawText(string, (this.f142460t / 2.0f) - (this.f142442b.width() / 2), this.f142433I + this.f142442b.height() + Xj.a.b(3), this.f142455o);
            }
        }
    }

    @Override // android.view.View
    public void onLayout(boolean changed, int left, int top, int right, int bottom) {
        super.onLayout(changed, left, top, right, bottom);
        this.f142460t = getWidth();
    }

    @Override // android.view.View
    public void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec);
        int mode = View.MeasureSpec.getMode(widthMeasureSpec);
        int size = View.MeasureSpec.getSize(widthMeasureSpec);
        int mode2 = View.MeasureSpec.getMode(heightMeasureSpec);
        int size2 = View.MeasureSpec.getSize(heightMeasureSpec);
        if (mode != 1073741824) {
            size = getPaddingRight() + getWidth() + getPaddingLeft();
        }
        if (mode2 != 1073741824) {
            size2 = getPaddingBottom() + getHeight() + getPaddingTop();
        }
        setMeasuredDimension(size, size2);
    }

    @Override // android.view.View
    public boolean onTouchEvent(MotionEvent event) {
        C2741q c2741qX;
        AbstractC2759w0 abstractC2759w0L;
        Double dValueOf = null;
        Integer numValueOf = event != null ? Integer.valueOf(event.getAction()) : null;
        if (numValueOf == null || numValueOf.intValue() != 0) {
            if (numValueOf != null && numValueOf.intValue() == 1) {
                return true;
            }
            return super.onTouchEvent(event);
        }
        if (this.f142443c.contains(event.getX(), event.getY())) {
            this.onDetailClickItem.invoke();
        } else if (this.f142444d.contains(event.getX(), event.getY())) {
            this.onAlertClickItem.invoke(this.f142432H);
        } else {
            float x10 = event.getX();
            float y10 = event.getY();
            List<Map> list = this.f142456p;
            if (list != null && !list.isEmpty() && this.f142459s > 0.0d && (c2741qX = KLineManager.f142490O.a().x()) != null && (abstractC2759w0L = c2741qX.l(this.f142436L)) != null) {
                for (Map map : list) {
                    Double d10 = (Double) map.get("from");
                    double dDoubleValue = d10 != null ? d10.doubleValue() : 0.0d;
                    Double d11 = (Double) map.get("to");
                    double dDoubleValue2 = d11 != null ? d11.doubleValue() : 0.0d;
                    if (dDoubleValue > 0.0d && dDoubleValue2 > 0.0d) {
                        float fS = abstractC2759w0L.S(dDoubleValue2) - this.f142434J;
                        float fS2 = abstractC2759w0L.S(dDoubleValue) - this.f142434J;
                        float f10 = this.f142461u;
                        if (fS <= f10 && fS2 <= f10 && 0.0f <= x10 && x10 <= this.f142460t && fS <= y10 && y10 <= fS2) {
                            dValueOf = Double.valueOf(Xj.c.f25377a.d(dDoubleValue, dDoubleValue2));
                            break;
                        }
                    }
                }
            }
            if (dValueOf != null) {
                double dDoubleValue3 = dValueOf.doubleValue();
                Xj.c cVar = Xj.c.f25377a;
                double dF = cVar.f();
                if (dF <= 0.0d || Math.abs(dF - dDoubleValue3) > 1.0E-8d) {
                    cVar.k(dDoubleValue3);
                } else {
                    cVar.b();
                }
                invalidate();
                Chart chartG = KLineManager.f142490O.a().g();
                if (chartG != null) {
                    chartG.x();
                }
            }
        }
        return true;
    }

    public final void setConfigData(VpVrConfigData data) {
        this.f142427C = data.getVolConfig1();
        this.f142428D = data.getVolConfig2();
        invalidate();
    }

    public final void setOnAlertClickItem(Function1 function1) {
        this.onAlertClickItem = function1;
    }

    public final void setOnDetailClickItem(p146gg.a aVar) {
        this.onDetailClickItem = aVar;
    }
}
